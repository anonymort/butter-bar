import Foundation
import ProviderDomain
import MetadataDomain

/// Orchestrates concurrent source resolution across all configured providers.
///
/// Call `search(for:)` to fan out to every provider simultaneously. Each
/// provider gets `timeoutSeconds` before its task is cancelled and its slot
/// recorded as a timeout error. Results from all providers are merged,
/// de-duplicated by `infoHash`, and sorted descending by `SourceCandidate.rank`.
///
/// This type is `@MainActor` so `@Published` properties bind directly to SwiftUI
/// views without extra hops.
@MainActor
final class ProviderSearchPipeline: ObservableObject {

    @Published private(set) var candidates: [SourceCandidate] = []
    @Published private(set) var isSearching: Bool = false
    /// Keyed by provider name. Populated when a provider throws or times out.
    @Published private(set) var errors: [String: Error] = [:]

    private let providers: [any MediaProvider]
    private let timeoutSeconds: TimeInterval

    /// Holds the currently running search group task so it can be cancelled
    /// when a new search starts before the previous one finishes.
    private var searchTask: Task<Void, Never>?

    init(providers: [any MediaProvider], timeout: TimeInterval = 10) {
        self.providers = providers
        self.timeoutSeconds = timeout
    }

    /// Launches a parallel search across all providers.
    ///
    /// If a prior search is running it is cancelled before the new one begins.
    func search(for item: MediaItem) async {
        cancel()

        isSearching = true
        candidates = []
        errors = [:]

        searchTask = Task {
            var gathered: [SourceCandidate] = []
            var providerErrors: [String: Error] = [:]

            await withTaskGroup(of: ProviderResult.self) { group in
                for provider in self.providers {
                    group.addTask {
                        await self.runWithTimeout(
                            provider: provider,
                            item: item,
                            timeout: self.timeoutSeconds
                        )
                    }
                }
                for await result in group {
                    switch result {
                    case .success(let items):
                        gathered.append(contentsOf: items)
                    case .failure(let name, let error):
                        providerErrors[name] = error
                    }
                }
            }

            // De-duplicate by infoHash, keeping the first occurrence (highest
            // seeder count providers should be listed first if ordering matters).
            var seen = Set<String>()
            let unique = gathered.filter { seen.insert($0.infoHash).inserted }

            let sorted = unique.sorted { $0.rank > $1.rank }

            // Guard against the task having been cancelled between the group
            // completing and this assignment — the pipeline may already be
            // presenting results from a newer search.
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.candidates = sorted
                self.errors = providerErrors
                self.isSearching = false
            }
        }

        await searchTask?.value
    }

    /// Cancels any in-flight search and resets `isSearching`.
    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }

    // MARK: - Private helpers

    /// Runs a single provider search under a deadline. Returns `.failure` on
    /// timeout or provider error so that sibling provider tasks are unaffected.
    private func runWithTimeout(
        provider: any MediaProvider,
        item: MediaItem,
        timeout: TimeInterval
    ) async -> ProviderResult {
        // Race the real work against a sleep-then-cancel pattern.
        let workTask = Task<[SourceCandidate], Error> {
            try await provider.search(for: item, page: 1)
        }

        let deadlineTask = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(timeout))
            workTask.cancel()
        }

        defer { deadlineTask.cancel() }

        do {
            let results = try await workTask.value
            return .success(results)
        } catch is CancellationError {
            return .failure(
                providerName: provider.name,
                error: ProviderTimeoutError(providerName: provider.name, timeout: timeout)
            )
        } catch {
            return .failure(providerName: provider.name, error: error)
        }
    }
}

// MARK: - Internal result carrier

private enum ProviderResult: Sendable {
    case success([SourceCandidate])
    case failure(providerName: String, error: Error)
}

// MARK: - Timeout error

/// Typed error surfaced when a provider exceeds its allotted search window.
struct ProviderTimeoutError: Error, LocalizedError, Sendable {
    let providerName: String
    let timeout: TimeInterval

    var errorDescription: String? {
        "\(providerName) did not respond within \(Int(timeout))s."
    }
}
