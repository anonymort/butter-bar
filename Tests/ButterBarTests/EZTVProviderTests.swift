import XCTest
import MetadataDomain
import ProviderDomain
@testable import ButterBar

final class EZTVProviderTests: XCTestCase {

    // MARK: - testSearch_show_parsesResults

    func testSearch_show_parsesResults() async throws {
        let session = URLSession.mockSession(data: eztvFixture, statusCode: 200)
        let provider = EZTVProvider(session: session)
        let show = makeShow(name: "Severance")

        let results = try await provider.search(for: .show(show), page: 1)

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy { $0.providerName == "EZTV" })
        XCTAssertTrue(results.allSatisfy { $0.id.hasPrefix("eztv:") })

        // Quality parsed from title strings.
        // Torrent 1 title contains "1080p" → .bluRay
        XCTAssertEqual(results[0].quality, .bluRay)
        // Torrent 2 title contains "720p" → .webDL
        XCTAssertEqual(results[1].quality, .webDL)
        // Torrent 3 title contains "2160p" → .remux
        XCTAssertEqual(results[2].quality, .remux)
    }

    // MARK: - testSearch_movie_returnsEmpty

    func testSearch_movie_returnsEmpty() async throws {
        let session = URLSession.mockSession(data: eztvFixture, statusCode: 200)
        let provider = EZTVProvider(session: session)
        let movie = makeMovie(title: "Dune Part Two")

        let results = try await provider.search(for: .movie(movie), page: 1)
        XCTAssertEqual(results.count, 0, "EZTV must return [] for movies without hitting the network")
    }

    // MARK: - testSearch_sizeBytesAsString_parsedCorrectly

    func testSearch_sizeBytesAsString_parsedCorrectly() async throws {
        let session = URLSession.mockSession(data: eztvFixture, statusCode: 200)
        let provider = EZTVProvider(session: session)
        let show = makeShow(name: "Severance")

        let results = try await provider.search(for: .show(show), page: 1)

        // First torrent has size_bytes "1234567890"
        XCTAssertEqual(results.first?.sizeBytes, Int64(1_234_567_890))
    }

    // MARK: - Fixtures

    private func makeMovie(title: String) -> Movie {
        Movie(
            id: MediaID(source: .tmdb, value: "10"),
            title: title,
            originalTitle: title,
            releaseYear: 2024,
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
            id: MediaID(source: .tmdb, value: "20"),
            name: name,
            originalName: name,
            firstAirYear: 2022,
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

    /// Fixture: 3 torrents with quality encoded in title strings.
    private let eztvFixture = Data("""
    {
        "torrents": [
            {
                "title": "Severance S02E01 1080p WEB-DL",
                "imdb_id": "tt11280740",
                "seeds": 800,
                "peers": 60,
                "size_bytes": "1234567890",
                "magnet_url": "magnet:?xt=urn:btih:cc001122334455667788990011223344556677cc",
                "hash": "cc001122334455667788990011223344556677cc"
            },
            {
                "title": "Severance S02E01 720p WEB-DL",
                "imdb_id": "tt11280740",
                "seeds": 400,
                "peers": 35,
                "size_bytes": "567890123",
                "magnet_url": "magnet:?xt=urn:btih:dd001122334455667788990011223344556677dd",
                "hash": "dd001122334455667788990011223344556677dd"
            },
            {
                "title": "Severance S02E01 2160p UHD BluRay",
                "imdb_id": "tt11280740",
                "seeds": 200,
                "peers": 20,
                "size_bytes": "9876543210",
                "magnet_url": "magnet:?xt=urn:btih:ee001122334455667788990011223344556677ee",
                "hash": "ee001122334455667788990011223344556677ee"
            }
        ]
    }
    """.utf8)
}
