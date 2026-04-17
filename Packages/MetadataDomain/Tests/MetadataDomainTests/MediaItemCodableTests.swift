import XCTest
@testable import MetadataDomain

final class MediaItemCodableTests: XCTestCase {

    // MARK: - Round-trips

    func test_movie_roundTrip() throws {
        let movie = Self.sampleMovie()
        try assertCodableRoundTrip(movie)
    }

    func test_show_roundTrip() throws {
        let show = Self.sampleShow()
        try assertCodableRoundTrip(show)
    }

    func test_season_roundTrip() throws {
        let season = Self.sampleSeason()
        try assertCodableRoundTrip(season)
    }

    func test_episode_roundTrip() throws {
        let episode = Self.sampleEpisode()
        try assertCodableRoundTrip(episode)
    }

    func test_genre_roundTrip() throws {
        try assertCodableRoundTrip(Genre(id: 28, name: "Action"))
    }

    func test_showStatus_eachCase_roundTrips() throws {
        for status in [ShowStatus.returning, .ended, .canceled, .inProduction] {
            try assertCodableRoundTrip(status)
        }
    }

    func test_mediaItem_movieCase_roundTrip() throws {
        let item = MediaItem.movie(Self.sampleMovie())
        try assertCodableRoundTrip(item)
    }

    func test_mediaItem_showCase_roundTrip() throws {
        let item = MediaItem.show(Self.sampleShow())
        try assertCodableRoundTrip(item)
    }

    func test_mediaItem_id_returnsUnderlyingID() {
        let movie = Self.sampleMovie()
        XCTAssertEqual(MediaItem.movie(movie).id, movie.id)

        let show = Self.sampleShow()
        XCTAssertEqual(MediaItem.show(show).id, show.id)
    }

    // MARK: - Schema shape (JSON snapshot guards)

    func test_movie_jsonSchemaShape() throws {
        let movie = Self.sampleMovie()
        let json = try jsonObject(for: movie)
        // Sentinel keys present.
        for key in ["id", "title", "originalTitle", "releaseYear",
                    "runtimeMinutes", "overview", "genres", "posterPath",
                    "backdropPath", "voteAverage", "popularity"] {
            XCTAssertNotNil(json[key], "missing key: \(key)")
        }
    }

    func test_show_jsonSchemaShape() throws {
        let show = Self.sampleShow()
        let json = try jsonObject(for: show)
        for key in ["id", "name", "originalName", "firstAirYear",
                    "lastAirYear", "status", "overview", "genres",
                    "posterPath", "backdropPath", "voteAverage",
                    "popularity", "seasons"] {
            XCTAssertNotNil(json[key], "missing key: \(key)")
        }
    }

    func test_episode_jsonSchemaShape() throws {
        let json = try jsonObject(for: Self.sampleEpisode())
        for key in ["id", "showID", "seasonNumber", "episodeNumber",
                    "name", "overview", "stillPath", "runtimeMinutes",
                    "airDate"] {
            XCTAssertNotNil(json[key], "missing key: \(key)")
        }
    }

    func test_mediaItem_movie_jsonShape_carriesDiscriminator() throws {
        let data = try JSONEncoder().encode(MediaItem.movie(Self.sampleMovie()))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Swift synthesises `{ "movie": { ... } }` for enums with associated values.
        XCTAssertNotNil(json["movie"])
        XCTAssertNil(json["show"])
    }

    func test_mediaItem_show_jsonShape_carriesDiscriminator() throws {
        let data = try JSONEncoder().encode(MediaItem.show(Self.sampleShow()))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["show"])
        XCTAssertNil(json["movie"])
    }

    // MARK: - Helpers

    private func assertCodableRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(value)
        let decoded = try decoder.decode(T.self, from: data)
        XCTAssertEqual(value, decoded, file: file, line: line)
    }

    private func jsonObject<T: Encodable>(for value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Fixtures

    static func sampleMovie() -> Movie {
        Movie(
            id: MediaID(provider: .tmdb, id: 1668),
            title: "Friends",
            originalTitle: "Friends",
            releaseYear: 1994,
            runtimeMinutes: 22,
            overview: "Six friends.",
            genres: [Genre(id: 35, name: "Comedy")],
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            voteAverage: 8.4,
            popularity: 250.0
        )
    }

    static func sampleShow() -> Show {
        Show(
            id: MediaID(provider: .tmdb, id: 1668),
            name: "Friends",
            originalName: "Friends",
            firstAirYear: 1994,
            lastAirYear: 2004,
            status: .ended,
            overview: "Six friends in NYC.",
            genres: [Genre(id: 35, name: "Comedy")],
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            voteAverage: 8.4,
            popularity: 250.0,
            seasons: [sampleSeason()]
        )
    }

    static func sampleSeason() -> Season {
        Season(
            showID: MediaID(provider: .tmdb, id: 1668),
            seasonNumber: 1,
            name: "Season 1",
            overview: "The first season.",
            posterPath: "/season1.jpg",
            airDate: Date(timeIntervalSince1970: 778464000),
            episodes: [sampleEpisode()]
        )
    }

    static func sampleEpisode() -> Episode {
        Episode(
            id: MediaID(provider: .tmdb, id: 85987),
            showID: MediaID(provider: .tmdb, id: 1668),
            seasonNumber: 1,
            episodeNumber: 1,
            name: "The One Where Monica Gets a Roommate",
            overview: "Pilot.",
            stillPath: "/still.jpg",
            runtimeMinutes: 22,
            airDate: Date(timeIntervalSince1970: 778464000)
        )
    }
}
