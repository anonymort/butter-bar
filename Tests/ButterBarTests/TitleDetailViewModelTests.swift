import XCTest
import MetadataDomain
@testable import ButterBar

@MainActor
final class TitleDetailViewModelTests: XCTestCase {

    // MARK: - Movie variant — happy path

    func testLoadMovieSucceeds() async {
        let provider = StubProvider()
        provider.movieDetailResult = .success(Self.sampleMovie)
        provider.recommendationsResult = .success([.movie(Self.sampleMovie)])

        let vm = TitleDetailViewModel(
            id: Self.sampleMovieID,
            kind: .movie,
            provider: provider
        )
        await vm.load()

        guard case .loaded(let detail, let revalidating) = vm.state else {
            return XCTFail("Expected .loaded; got \(vm.state)")
        }
        XCTAssertFalse(revalidating)
        XCTAssertTrue(detail.isMovie)
        XCTAssertEqual(detail.displayTitle, "Inception")
        XCTAssertEqual(detail.year, 2010)
        XCTAssertEqual(detail.runtimeMinutes, 148)
        XCTAssertEqual(detail.recommendations.count, 1)
        XCTAssertNil(detail.libraryMatch)
    }

    // MARK: - Show variant — happy path

    func testLoadShowSucceeds() async {
        let provider = StubProvider()
        provider.showDetailResult = .success(Self.sampleShow)
        provider.recommendationsResult = .success([])

        let vm = TitleDetailViewModel(
            id: Self.sampleShowID,
            kind: .show,
            provider: provider
        )
        await vm.load()

        guard case .loaded(let detail, _) = vm.state else {
            return XCTFail("Expected .loaded; got \(vm.state)")
        }
        XCTAssertFalse(detail.isMovie)
        XCTAssertEqual(detail.displayTitle, "Game of Thrones")
        XCTAssertEqual(detail.year, 2011)
        XCTAssertNil(detail.runtimeMinutes,
                     "Shows surface runtime per-episode (#16); detail page does not show one.")
        XCTAssertTrue(detail.recommendations.isEmpty)
    }

    // MARK: - Error path

    func testLoadFailureSetsErrorState() async {
        let provider = StubProvider()
        provider.movieDetailResult = .failure(MetadataProviderError.transport)

        let vm = TitleDetailViewModel(
            id: Self.sampleMovieID,
            kind: .movie,
            provider: provider
        )
        await vm.load()

        XCTAssertEqual(vm.state, .error)
    }

    // MARK: - Retry path — error → loaded after fix

    func testRetryRecoversFromError() async {
        let provider = StubProvider()
        provider.movieDetailResult = .failure(MetadataProviderError.transport)

        let vm = TitleDetailViewModel(
            id: Self.sampleMovieID,
            kind: .movie,
            provider: provider
        )
        await vm.load()
        XCTAssertEqual(vm.state, .error)

        provider.movieDetailResult = .success(Self.sampleMovie)
        await vm.retry()

        guard case .loaded = vm.state else {
            return XCTFail("Expected .loaded after retry; got \(vm.state)")
        }
    }

    // MARK: - Re-entry on already-loaded marks revalidating then settles

    func testReloadFlipsRevalidatingFlag() async {
        let provider = StubProvider()
        provider.movieDetailResult = .success(Self.sampleMovie)

        let vm = TitleDetailViewModel(
            id: Self.sampleMovieID,
            kind: .movie,
            provider: provider
        )
        await vm.load()
        guard case .loaded(_, false) = vm.state else {
            return XCTFail("Expected initial loaded with isRevalidating=false; got \(vm.state)")
        }

        await vm.load()
        guard case .loaded(_, false) = vm.state else {
            return XCTFail("Expected loaded with isRevalidating=false after second fetch; got \(vm.state)")
        }
    }

    // MARK: - Library match surfaces "in your library"

    func testLibraryMatchPropagates() async {
        let provider = StubProvider()
        provider.movieDetailResult = .success(Self.sampleMovie)

        let expectedMatch = LibraryMatch(
            torrentID: "abc123",
            fileIndex: 0,
            displayName: "Inception (2010).mkv"
        )

        let vm = TitleDetailViewModel(
            id: Self.sampleMovieID,
            kind: .movie,
            provider: provider,
            libraryMatcher: { _ in expectedMatch }
        )
        await vm.load()

        guard case .loaded(let detail, _) = vm.state else {
            return XCTFail("Expected .loaded; got \(vm.state)")
        }
        XCTAssertEqual(detail.libraryMatch, expectedMatch)
    }

    func testLibraryMatchAbsentWhenMatcherReturnsNil() async {
        let provider = StubProvider()
        provider.movieDetailResult = .success(Self.sampleMovie)

        let vm = TitleDetailViewModel(
            id: Self.sampleMovieID,
            kind: .movie,
            provider: provider,
            libraryMatcher: { _ in nil }
        )
        await vm.load()

        guard case .loaded(let detail, _) = vm.state else {
            return XCTFail("Expected .loaded; got \(vm.state)")
        }
        XCTAssertNil(detail.libraryMatch)
    }

    // MARK: - Recommendations failure is non-fatal

    func testRecommendationsFailureDoesNotBlockRender() async {
        let provider = StubProvider()
        provider.movieDetailResult = .success(Self.sampleMovie)
        provider.recommendationsResult = .failure(MetadataProviderError.transport)

        let vm = TitleDetailViewModel(
            id: Self.sampleMovieID,
            kind: .movie,
            provider: provider
        )
        await vm.load()

        guard case .loaded(let detail, _) = vm.state else {
            return XCTFail("Expected .loaded; got \(vm.state)")
        }
        XCTAssertTrue(detail.recommendations.isEmpty,
                      "Failed recommendations fetch should yield an empty list, not block the page.")
    }

    // MARK: - Cast injection truncates to default top N (8)

    func testCastIsTruncatedToDefault() async {
        let provider = StubProvider()
        provider.movieDetailResult = .success(Self.sampleMovie)

        let many = (0..<20).map { i in
            CastMember(id: i, name: "Actor \(i)", character: "Role \(i)", profilePath: nil)
        }
        let vm = TitleDetailViewModel(
            id: Self.sampleMovieID,
            kind: .movie,
            provider: provider,
            castProvider: { _ in many }
        )
        await vm.load()

        guard case .loaded(let detail, _) = vm.state else {
            return XCTFail("Expected .loaded; got \(vm.state)")
        }
        XCTAssertEqual(detail.cast.count, TitleDetailViewModel.defaultCastCount)
    }

    func testUsesCastFromDetailPayloadWhenNoCastProviderInjected() async {
        let provider = StubProvider()
        let cast = [CastMember(id: 1, name: "Actor", character: "Lead", profilePath: "/actor.jpg")]
        provider.movieDetailResult = .success(Self.sampleMovie.withCast(cast))
        let vm = TitleDetailViewModel(
            id: Self.sampleMovieID,
            kind: .movie,
            provider: provider
        )
        await vm.load()

        guard case .loaded(let detail, _) = vm.state else {
            return XCTFail("Expected .loaded; got \(vm.state)")
        }
        XCTAssertEqual(detail.cast, cast)
    }

    // MARK: - Image URL helpers route through the provider

    func testImageURLHelpersUseProvider() async {
        let provider = StubProvider()
        let vm = TitleDetailViewModel(
            id: Self.sampleMovieID,
            kind: .movie,
            provider: provider
        )
        let backdropURL = vm.backdropURL("/abc.jpg")
        XCTAssertTrue(backdropURL.absoluteString.contains("w1280"),
                      "Backdrop should use w1280 per AC; got \(backdropURL).")
        XCTAssertTrue(backdropURL.absoluteString.contains("abc.jpg"))
    }

    // MARK: - Fixtures

    static let sampleMovieID = MediaID(provider: .tmdb, id: 27205)
    static let sampleShowID = MediaID(provider: .tmdb, id: 1399)

    static var sampleMovie: Movie {
        Movie(
            id: sampleMovieID,
            title: "Inception",
            originalTitle: "Inception",
            releaseYear: 2010,
            runtimeMinutes: 148,
            overview: "A thief who steals corporate secrets.",
            genres: [Genre(id: 28, name: "Action"), Genre(id: 878, name: "Science Fiction")],
            posterPath: "/inception.jpg",
            backdropPath: "/inception_back.jpg",
            voteAverage: 8.4,
            popularity: 100.0
        )
    }

    static var sampleShow: Show {
        Show(
            id: sampleShowID,
            name: "Game of Thrones",
            originalName: "Game of Thrones",
            firstAirYear: 2011,
            lastAirYear: 2019,
            status: .ended,
            overview: "Seven noble families fight for control.",
            genres: [Genre(id: 18, name: "Drama")],
            posterPath: "/got.jpg",
            backdropPath: "/got_back.jpg",
            voteAverage: 8.4,
            popularity: 200.0,
            seasons: []
        )
    }
}

private extension Movie {
    func withCast(_ cast: [CastMember]) -> Movie {
        Movie(
            id: id,
            title: title,
            originalTitle: originalTitle,
            releaseYear: releaseYear,
            runtimeMinutes: runtimeMinutes,
            overview: overview,
            genres: genres,
            posterPath: posterPath,
            backdropPath: backdropPath,
            voteAverage: voteAverage,
            popularity: popularity,
            cast: cast
        )
    }
}

// MARK: - Stub provider local to this test target.
//
// `FakeMetadataProvider` lives in MetadataDomain's test target and is not
// reachable from ButterBarTests, so we hand-roll the minimum surface we
// need. Each handler closure returns a `Result` so individual tests can
// pin success / failure per call.

private final class StubProvider: MetadataProvider, @unchecked Sendable {
    var movieDetailResult: Result<Movie, Error> = .failure(MetadataProviderError.notFound)
    var showDetailResult: Result<Show, Error> = .failure(MetadataProviderError.notFound)
    var recommendationsResult: Result<[MediaItem], Error> = .success([])

    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] { [] }
    func popular(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func topRated(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func searchMulti(query: String) async throws -> [MediaItem] { [] }

    func movieDetail(id: MediaID) async throws -> Movie {
        try movieDetailResult.get()
    }

    func showDetail(id: MediaID) async throws -> Show {
        try showDetailResult.get()
    }

    func seasonDetail(showID: MediaID, season: Int) async throws -> Season {
        Season(showID: showID, seasonNumber: season, name: "S\(season)",
               overview: "", posterPath: nil, airDate: nil, episodes: [])
    }

    func recommendations(for id: MediaID) async throws -> [MediaItem] {
        try recommendationsResult.get()
    }

    func imageURL(path: String, size: TMDBImageSize) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "https://image.tmdb.org/t/p")!
            .appendingPathComponent(size.rawValue)
            .appendingPathComponent(trimmed)
    }
}
