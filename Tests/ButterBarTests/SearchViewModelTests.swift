import XCTest
import MetadataDomain
@testable import ButterBar

@MainActor
final class SearchViewModelTests: XCTestCase {
    func testDebounceCoalescesRapidQueries() async {
        let provider = SearchFakeProvider()
        let vm = SearchViewModel(provider: provider, debounce: .milliseconds(40))

        vm.updateQuery("inc")
        vm.updateQuery("inception")
        try? await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(provider.searchCalls, ["inception"])
        guard case .loaded(let query, let results) = vm.state else {
            return XCTFail("Expected loaded state; got \(vm.state)")
        }
        XCTAssertEqual(query, "inception")
        XCTAssertEqual(results.count, 1)
    }

    func testInFlightSearchCancellationLeavesLatestResult() async {
        let provider = SearchFakeProvider()
        provider.delay = .milliseconds(120)
        let vm = SearchViewModel(provider: provider, debounce: .milliseconds(0))

        vm.updateQuery("first")
        try? await Task.sleep(for: .milliseconds(20))
        vm.updateQuery("second")
        try? await Task.sleep(for: .milliseconds(220))

        XCTAssertEqual(provider.searchCalls, ["first", "second"])
        guard case .loaded(let query, _) = vm.state else {
            return XCTFail("Expected latest loaded state; got \(vm.state)")
        }
        XCTAssertEqual(query, "second")
    }

    func testEmptyQueryClearsResultsAndDoesNotSearch() async {
        let provider = SearchFakeProvider()
        let vm = SearchViewModel(provider: provider, debounce: .milliseconds(0))

        vm.updateQuery("   ")
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(vm.state, .idle)
        XCTAssertTrue(provider.searchCalls.isEmpty)
        XCTAssertEqual(vm.page, 0)
        XCTAssertFalse(vm.canLoadMore)
    }

    func testNoResultsAndErrorStates() async {
        let provider = SearchFakeProvider()
        provider.results = []
        let vm = SearchViewModel(provider: provider, debounce: .milliseconds(0))
        vm.updateQuery("missing")
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(vm.state, .noResults(query: "missing"))

        provider.error = MetadataProviderError.transport
        vm.updateQuery("broken")
        try? await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(vm.state, .error(query: "broken"))
    }
}

private final class SearchFakeProvider: MetadataProvider, @unchecked Sendable {
    var searchCalls: [String] = []
    var results: [MediaItem] = [.movie(Movie(
        id: MediaID(provider: .tmdb, id: 1),
        title: "Inception",
        originalTitle: "Inception",
        releaseYear: 2010,
        runtimeMinutes: 148,
        overview: "A dream within a dream.",
        genres: [],
        posterPath: "/poster.jpg",
        backdropPath: nil,
        voteAverage: nil,
        popularity: nil
    ))]
    var error: Error?
    var delay: Duration = .zero

    func searchMulti(query: String) async throws -> [MediaItem] {
        searchCalls.append(query)
        if delay != .zero { try await Task.sleep(for: delay) }
        try Task.checkCancellation()
        if let error { throw error }
        return results
    }

    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] { [] }
    func popular(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func topRated(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func movieDetail(id: MediaID) async throws -> Movie { throw MetadataProviderError.notFound }
    func showDetail(id: MediaID) async throws -> Show { throw MetadataProviderError.notFound }
    func seasonDetail(showID: MediaID, season: Int) async throws -> Season { throw MetadataProviderError.notFound }
    func recommendations(for id: MediaID) async throws -> [MediaItem] { [] }
    func imageURL(path: String, size: TMDBImageSize) -> URL { URL(string: "https://example.invalid")! }
}
