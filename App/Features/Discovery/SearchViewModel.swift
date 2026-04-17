import Combine
import Foundation
import MetadataDomain

protocol SearchDebounceSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct TaskSearchDebounceSleeper: SearchDebounceSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

enum SearchViewState: Equatable {
    case idle
    case loading(query: String)
    case loaded(query: String, results: [MediaItem])
    case noResults(query: String)
    case error(query: String)
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published private(set) var query: String = ""
    @Published private(set) var state: SearchViewState = .idle
    @Published private(set) var page: Int = 0
    @Published private(set) var canLoadMore: Bool = false

    private let provider: MetadataProvider
    private let debounce: Duration
    private let sleeper: SearchDebounceSleeping
    private var searchTask: Task<Void, Never>?

    init(provider: MetadataProvider,
         debounce: Duration = .milliseconds(250),
         sleeper: SearchDebounceSleeping = TaskSearchDebounceSleeper()) {
        self.provider = provider
        self.debounce = debounce
        self.sleeper = sleeper
    }

    deinit {
        searchTask?.cancel()
    }

    func updateQuery(_ newValue: String) {
        query = newValue
        searchTask?.cancel()

        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            page = 0
            canLoadMore = false
            state = .idle
            return
        }

        searchTask = Task { [provider, debounce, sleeper] in
            do {
                try await sleeper.sleep(for: debounce)
                try Task.checkCancellation()
                await MainActor.run {
                    self.page = 1
                    self.canLoadMore = false
                    self.state = .loading(query: trimmed)
                }
                let results = try await provider.searchMulti(query: trimmed)
                try Task.checkCancellation()
                await MainActor.run {
                    if results.isEmpty {
                        self.state = .noResults(query: trimmed)
                    } else {
                        self.state = .loaded(query: trimmed, results: results)
                    }
                }
            } catch is CancellationError {
                return
            } catch MetadataProviderError.cancelled {
                return
            } catch {
                await MainActor.run {
                    self.page = 1
                    self.canLoadMore = false
                    self.state = .error(query: trimmed)
                }
            }
        }
    }

    func loadNextPage() async {
        guard canLoadMore else { return }
    }

    func _setStateForTesting(_ state: SearchViewState) {
        self.state = state
    }
}
