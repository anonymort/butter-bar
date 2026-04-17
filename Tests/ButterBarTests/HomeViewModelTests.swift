import XCTest
import MetadataDomain
@testable import ButterBar

@MainActor
final class HomeViewModelTests: XCTestCase {

    // MARK: - Initial state

    func testInitialStateContinueWatchingEmptyOthersLoading() {
        let vm = HomeViewModel(provider: HomeViewModelTestsFake())
        XCTAssertEqual(vm.rowStates[.continueWatching], .empty)
        for kind in HomeRowKind.allCases where kind != .continueWatching {
            if case .loading = vm.rowStates[kind]! { /* ok */ } else {
                XCTFail("Row \(kind) should start in .loading; got \(String(describing: vm.rowStates[kind]))")
            }
        }
    }

    func testRowsEnumeratedInD11Order() {
        let vm = HomeViewModel(provider: HomeViewModelTestsFake())
        XCTAssertEqual(vm.rows.map(\.kind), [
            .continueWatching,
            .trendingMovies,
            .trendingShows,
            .popularMovies,
            .popularShows,
            .topRatedMovies,
            .topRatedShows,
        ])
    }

    func testContinueWatchingHiddenWhenEmpty() {
        let vm = HomeViewModel(provider: HomeViewModelTestsFake())
        XCTAssertFalse(vm.shouldRender(.continueWatching))
        XCTAssertTrue(vm.shouldRender(.trendingMovies))
    }

    // MARK: - Row composition (full success)

    func testLoadPopulatesAllDataBearingRows() async {
        let fake = HomeViewModelTestsFake()
        let vm = HomeViewModel(provider: fake)
        await vm.load()

        for kind in HomeRowKind.allCases where kind != .continueWatching {
            switch vm.rowStates[kind]! {
            case .loaded(let items):
                XCTAssertFalse(items.isEmpty, "Row \(kind) loaded with no items")
            default:
                XCTFail("Row \(kind) did not transition to .loaded; got \(String(describing: vm.rowStates[kind]))")
            }
        }
        XCTAssertEqual(vm.rowStates[.continueWatching], .empty)
    }

    func testLoadCallsCorrectProviderEndpoints() async {
        let fake = HomeViewModelTestsFake()
        let vm = HomeViewModel(provider: fake)
        await vm.load()

        // TaskGroup ordering is undefined; compare sets of (media, window).
        XCTAssertEqual(Set(fake.trendingCalls), Set([
            HomeViewModelTestsFake.TrendingCall(media: .movie, window: .week),
            HomeViewModelTestsFake.TrendingCall(media: .tv, window: .week),
        ]))
        XCTAssertEqual(Set(fake.popularCalls), Set([.movie, .tv]))
        XCTAssertEqual(Set(fake.topRatedCalls), Set([.movie, .tv]))
    }

    // MARK: - Error propagation (single row failure)

    func testFailedRowBecomesFailedNotEmpty() async {
        let fake = HomeViewModelTestsFake()
        fake.failFor = [.popularMovies]
        let vm = HomeViewModel(provider: fake)
        await vm.load()

        XCTAssertEqual(vm.rowStates[.popularMovies], .failed)
        // Other rows still load normally — failure is per-row.
        if case .loaded = vm.rowStates[.popularShows]! { /* ok */ } else {
            XCTFail("Popular shows should have loaded; got \(String(describing: vm.rowStates[.popularShows]))")
        }
    }

    func testEmptyResponseBecomesEmptyState() async {
        let fake = HomeViewModelTestsFake()
        fake.emptyFor = [.trendingMovies]
        let vm = HomeViewModel(provider: fake)
        await vm.load()

        XCTAssertEqual(vm.rowStates[.trendingMovies], .empty)
    }

    // MARK: - Coalescing

    func testRepeatedLoadRowIsCoalesced() async {
        let fake = HomeViewModelTestsFake()
        fake.holdRequests = true   // requests park until released
        let vm = HomeViewModel(provider: fake)

        // Fire two concurrent loads of the same row; only one provider call.
        async let first: Void = vm.loadRow(.popularMovies)
        async let second: Void = vm.loadRow(.popularMovies)
        // Give both tasks a chance to enter loadRow.
        try? await Task.sleep(nanoseconds: 50_000_000)
        fake.release()
        _ = await (first, second)

        XCTAssertEqual(fake.popularCallCount, 1,
                       "Coalescing should collapse concurrent loadRow into one fetch")
    }

    func testSecondLoadRowAfterCompletionRefetches() async {
        let fake = HomeViewModelTestsFake()
        let vm = HomeViewModel(provider: fake)

        await vm.loadRow(.popularMovies)
        await vm.loadRow(.popularMovies)

        XCTAssertEqual(fake.popularCallCount, 2,
                       "After completion, a fresh loadRow should hit the provider again")
    }

    func testRefetchKeepsLoadedItemsVisible() async {
        let fake = HomeViewModelTestsFake()
        let vm = HomeViewModel(provider: fake)
        await vm.loadRow(.popularMovies)
        guard case .loaded = vm.rowStates[.popularMovies]! else {
            return XCTFail("Expected .loaded after first fetch")
        }

        fake.holdRequests = true
        async let refetch: Void = vm.loadRow(.popularMovies)
        try? await Task.sleep(nanoseconds: 30_000_000)
        // Mid-refetch the row must NOT shimmer back to .loading; users would
        // see content disappear, breaking the calm motion brief.
        guard case .loaded = vm.rowStates[.popularMovies]! else {
            return XCTFail("Refetch should not blow away loaded state to .loading")
        }
        fake.release()
        await refetch
    }
}

// MARK: - Test fake

/// Local fake provider for the app test target. Mirrors the shape of
/// `FakeMetadataProvider` in `Packages/MetadataDomain/Tests/Support/` but
/// adds call-recording so we can assert orchestration behaviour.
private final class HomeViewModelTestsFake: MetadataProvider, @unchecked Sendable {

    struct TrendingCall: Hashable {
        let media: TrendingMedia
        let window: TrendingWindow
    }

    var trendingCalls: [TrendingCall] = []
    var popularCalls: [TrendingMedia] = []
    var topRatedCalls: [TrendingMedia] = []
    var popularCallCount: Int { popularCalls.count }

    var failFor: Set<HomeRowKind> = []
    var emptyFor: Set<HomeRowKind> = []

    /// Hold-and-release gate to exercise coalescing.
    var holdRequests: Bool = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    func release() {
        let pending = continuations
        continuations = []
        for c in pending { c.resume() }
    }

    private func gate() async {
        guard holdRequests else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] {
        await gate()
        trendingCalls.append(.init(media: media, window: window))
        let kind: HomeRowKind = (media == .movie) ? .trendingMovies : .trendingShows
        if failFor.contains(kind) { throw MetadataProviderError.transport }
        if emptyFor.contains(kind) { return [] }
        return [Self.sampleMovie(id: 1)]
    }

    func popular(media: TrendingMedia) async throws -> [MediaItem] {
        await gate()
        popularCalls.append(media)
        let kind: HomeRowKind = (media == .movie) ? .popularMovies : .popularShows
        if failFor.contains(kind) { throw MetadataProviderError.transport }
        if emptyFor.contains(kind) { return [] }
        return [Self.sampleMovie(id: 2)]
    }

    func topRated(media: TrendingMedia) async throws -> [MediaItem] {
        await gate()
        topRatedCalls.append(media)
        let kind: HomeRowKind = (media == .movie) ? .topRatedMovies : .topRatedShows
        if failFor.contains(kind) { throw MetadataProviderError.transport }
        if emptyFor.contains(kind) { return [] }
        return [Self.sampleMovie(id: 3)]
    }

    func searchMulti(query: String) async throws -> [MediaItem] { [] }

    func movieDetail(id: MediaID) async throws -> Movie {
        Self.sampleMovieStruct(id: id)
    }

    func showDetail(id: MediaID) async throws -> Show {
        Show(id: id, name: "X", originalName: "X", firstAirYear: nil, lastAirYear: nil,
             status: .ended, overview: "", genres: [], posterPath: nil, backdropPath: nil,
             voteAverage: nil, popularity: nil, seasons: [])
    }

    func seasonDetail(showID: MediaID, season: Int) async throws -> Season {
        Season(showID: showID, seasonNumber: season, name: "S\(season)",
               overview: "", posterPath: nil, airDate: nil, episodes: [])
    }

    func recommendations(for id: MediaID) async throws -> [MediaItem] { [] }

    func imageURL(path: String, size: TMDBImageSize) -> URL {
        URL(string: "https://example.invalid/\(size.rawValue)\(path)")!
    }

    private static func sampleMovieStruct(id: MediaID) -> Movie {
        Movie(id: id, title: "Sample", originalTitle: "Sample",
              releaseYear: 2020, runtimeMinutes: 100, overview: "",
              genres: [], posterPath: "/p.jpg", backdropPath: nil,
              voteAverage: nil, popularity: nil)
    }

    private static func sampleMovie(id: Int64) -> MediaItem {
        .movie(sampleMovieStruct(id: MediaID(provider: .tmdb, id: id)))
    }
}
