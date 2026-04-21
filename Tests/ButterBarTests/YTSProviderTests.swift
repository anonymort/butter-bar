import XCTest
import MetadataDomain
import ProviderDomain
@testable import ButterBar

final class YTSProviderTests: XCTestCase {

    // MARK: - testSearch_movie_parsesResults

    func testSearch_movie_parsesResults() async throws {
        let session = URLSession.mockSession(data: ytsFixture, statusCode: 200)
        let provider = YTSProvider(session: session)
        let movie = makeMovie(title: "Blade Runner 2049", year: 2017)

        let results = try await provider.search(for: .movie(movie), page: 1)

        // Fixture has 2 movies × 3 torrents each = 6 candidates (years match).
        XCTAssertEqual(results.count, 6)

        // Check quality mapping: bluray type → .bluRay
        let blurayResults = results.filter { $0.quality == .bluRay }
        XCTAssertFalse(blurayResults.isEmpty)

        // Check quality mapping: web type → .webDL
        let webResults = results.filter { $0.quality == .webDL }
        XCTAssertFalse(webResults.isEmpty)

        // Provider name on every candidate
        XCTAssertTrue(results.allSatisfy { $0.providerName == "YTS" })

        // id prefixed with yts:
        XCTAssertTrue(results.allSatisfy { $0.id.hasPrefix("yts:") })

        // Magnet URIs present
        XCTAssertTrue(results.allSatisfy { $0.magnetURI != nil })
    }

    // MARK: - testSearch_show_returnsEmpty

    func testSearch_show_returnsEmpty() async throws {
        let session = URLSession.mockSession(data: ytsFixture, statusCode: 200)
        let provider = YTSProvider(session: session)
        let show = makeShow(name: "Breaking Bad")

        let results = try await provider.search(for: .show(show), page: 1)
        XCTAssertEqual(results.count, 0, "YTS must return [] for shows without hitting the network")
    }

    // MARK: - testSearch_yearFilterDropsDistantMatch

    func testSearch_yearFilterDropsDistantMatch() async throws {
        // Fixture movie years are 2017. Request year 2012 — delta is 5, beyond threshold of 2.
        let session = URLSession.mockSession(data: ytsFixture, statusCode: 200)
        let provider = YTSProvider(session: session)
        let movie = makeMovie(title: "Blade Runner 2049", year: 2012)

        let results = try await provider.search(for: .movie(movie), page: 1)
        XCTAssertEqual(results.count, 0, "Results with year off by >2 must be dropped")
    }

    // MARK: - Fixtures

    private func makeMovie(title: String, year: Int?) -> Movie {
        Movie(
            id: MediaID(source: .tmdb, value: "1"),
            title: title,
            originalTitle: title,
            releaseYear: year,
            runtimeMinutes: nil,
            overview: "",
            genres: [],
            posterPath: nil,
            backdropPath: nil,
            voteAverage: nil,
            popularity: nil
        )
    }

    private func makeShow(name: String) -> Show {
        Show(
            id: MediaID(source: .tmdb, value: "2"),
            name: name,
            originalName: name,
            firstAirYear: nil,
            lastAirYear: nil,
            status: .returning,
            overview: "",
            genres: [],
            posterPath: nil,
            backdropPath: nil,
            voteAverage: nil,
            popularity: nil,
            seasons: []
        )
    }

    /// Fixture: 2 movies, 3 torrents each. Movie years are both 2017.
    private let ytsFixture = Data("""
    {
        "data": {
            "movies": [
                {
                    "title": "Blade Runner 2049",
                    "year": 2017,
                    "imdb_code": "tt1856101",
                    "torrents": [
                        { "hash": "aabbccdd112233440000000000000001", "quality": "1080p", "seeds": 500, "peers": 50, "size_bytes": 2147483648, "type": "bluray" },
                        { "hash": "aabbccdd112233440000000000000002", "quality": "720p",  "seeds": 200, "peers": 30, "size_bytes": 1073741824, "type": "web" },
                        { "hash": "aabbccdd112233440000000000000003", "quality": "480p",  "seeds": 100, "peers": 20, "size_bytes": 536870912,  "type": "web" }
                    ]
                },
                {
                    "title": "Blade Runner 2049 Extended",
                    "year": 2017,
                    "imdb_code": "tt9999999",
                    "torrents": [
                        { "hash": "bbbbccdd112233440000000000000001", "quality": "2160p", "seeds": 300, "peers": 40, "size_bytes": 8589934592, "type": "bluray" },
                        { "hash": "bbbbccdd112233440000000000000002", "quality": "1080p", "seeds": 150, "peers": 25, "size_bytes": 2147483648, "type": "bluray" },
                        { "hash": "bbbbccdd112233440000000000000003", "quality": "720p",  "seeds": 80,  "peers": 15, "size_bytes": 1073741824, "type": "web" }
                    ]
                }
            ]
        }
    }
    """.utf8)
}
