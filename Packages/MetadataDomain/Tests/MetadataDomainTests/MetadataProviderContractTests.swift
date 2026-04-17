import XCTest
@testable import MetadataDomain

/// Protocol-level contract suite that any `MetadataProvider` impl must
/// satisfy. Run against `FakeMetadataProvider` in CI; the live-TMDB
/// integration suite is gated behind `TMDB_LIVE_TESTS=1` and never runs
/// in CI (no embedded keys).
///
/// Subclasses override `makeProvider()` to plug in different impls.
class MetadataProviderContractTests: XCTestCase {

    func makeProvider() -> MetadataProvider { FakeMetadataProvider() }

    // MARK: - Trending / popular / top-rated

    func test_trending_movieWeek_returnsMediaItems() async throws {
        let provider = makeProvider()
        let items = try await provider.trending(media: .movie, window: .week)
        XCTAssertFalse(items.isEmpty)
    }

    func test_trending_tvDay_returnsMediaItems() async throws {
        let provider = makeProvider()
        let items = try await provider.trending(media: .tv, window: .day)
        XCTAssertFalse(items.isEmpty)
    }

    func test_popular_movies_returnsMovieItems() async throws {
        let provider = makeProvider()
        let items = try await provider.popular(media: .movie)
        for item in items {
            if case .movie = item { continue }
            XCTFail("popular(.movie) returned a non-movie item: \(item)")
        }
    }

    func test_popular_tv_returnsShowItems() async throws {
        let provider = makeProvider()
        let items = try await provider.popular(media: .tv)
        for item in items {
            if case .show = item { continue }
            XCTFail("popular(.tv) returned a non-show item: \(item)")
        }
    }

    func test_topRated_movies_returnsMovieItems() async throws {
        let provider = makeProvider()
        let items = try await provider.topRated(media: .movie)
        for item in items {
            if case .movie = item { continue }
            XCTFail("topRated(.movie) returned a non-movie item: \(item)")
        }
    }

    // MARK: - Search

    func test_searchMulti_emptyQuery_doesNotCrash() async throws {
        let provider = makeProvider()
        _ = try await provider.searchMulti(query: "")
    }

    func test_searchMulti_returnsMediaItems() async throws {
        let provider = makeProvider()
        let items = try await provider.searchMulti(query: "matrix")
        XCTAssertFalse(items.isEmpty)
    }

    // MARK: - Detail

    func test_movieDetail_byID_returnsMatchingMovie() async throws {
        let provider = makeProvider()
        let id = MediaID(provider: .tmdb, id: 27205)
        let movie = try await provider.movieDetail(id: id)
        XCTAssertEqual(movie.id, id)
    }

    func test_showDetail_byID_returnsMatchingShow() async throws {
        let provider = makeProvider()
        let id = MediaID(provider: .tmdb, id: 1399)
        let show = try await provider.showDetail(id: id)
        XCTAssertEqual(show.id, id)
    }

    func test_seasonDetail_byShowAndSeason_returnsCorrectSeason() async throws {
        let provider = makeProvider()
        let showID = MediaID(provider: .tmdb, id: 1399)
        let season = try await provider.seasonDetail(showID: showID, season: 1)
        XCTAssertEqual(season.showID, showID)
        XCTAssertEqual(season.seasonNumber, 1)
    }

    // MARK: - Recommendations

    func test_recommendations_returnsMediaItems() async throws {
        let provider = makeProvider()
        let id = MediaID(provider: .tmdb, id: 27205)
        let items = try await provider.recommendations(for: id)
        XCTAssertFalse(items.isEmpty)
    }

    // MARK: - Image URL

    func test_imageURL_includesSizeAndPath() {
        let provider = makeProvider()
        let url = provider.imageURL(path: "/abc.jpg", size: .w342)
        XCTAssertTrue(url.absoluteString.contains("w342"))
        XCTAssertTrue(url.absoluteString.hasSuffix("abc.jpg"))
    }

    func test_imageURL_handlesPathWithoutLeadingSlash() {
        let provider = makeProvider()
        let url = provider.imageURL(path: "abc.jpg", size: .w500)
        XCTAssertTrue(url.absoluteString.contains("w500"))
        XCTAssertFalse(url.absoluteString.contains("//abc"))
    }

    func test_imageURL_isPureFunction() {
        let provider = makeProvider()
        let a = provider.imageURL(path: "/x.jpg", size: .w1280)
        let b = provider.imageURL(path: "/x.jpg", size: .w1280)
        XCTAssertEqual(a, b)
    }
}

/// Concrete invocation of the contract suite against `FakeMetadataProvider`.
/// (Subclassing is enough for XCTest to discover the parent's tests, but
/// exposing a named subclass makes the run output unambiguous.)
final class FakeMetadataProviderContractTests: MetadataProviderContractTests {
    override func makeProvider() -> MetadataProvider { FakeMetadataProvider() }
}
