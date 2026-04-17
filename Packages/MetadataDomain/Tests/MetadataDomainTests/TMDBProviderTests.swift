import XCTest
@testable import MetadataDomain

/// Pure tests for `TMDBProvider`'s URL construction and DTO decoding.
/// Does not exercise the network. The live integration suite is gated by
/// `TMDB_LIVE_TESTS` and not run in CI.
final class TMDBProviderTests: XCTestCase {

    // MARK: - imageURL

    func test_imageURL_buildsTMDBPath() async {
        let provider = makeProvider()
        let url = await provider.imageURL(path: "/inception.jpg", size: .w500)
        XCTAssertEqual(url.absoluteString,
                       "https://image.tmdb.org/t/p/w500/inception.jpg")
    }

    func test_imageURL_stripsLeadingSlash() async {
        let provider = makeProvider()
        let url = await provider.imageURL(path: "abc.jpg", size: .w342)
        XCTAssertFalse(url.absoluteString.contains("//abc"))
    }

    // MARK: - DTO decoding

    func test_movieDetailDTO_decodesAndMapsToMovie() throws {
        let json = """
        {
          "id": 27205,
          "title": "Inception",
          "original_title": "Inception",
          "release_date": "2010-07-16",
          "runtime": 148,
          "overview": "A thief...",
          "poster_path": "/inception.jpg",
          "backdrop_path": "/back.jpg",
          "vote_average": 8.4,
          "popularity": 100.0,
          "genres": [{"id": 28, "name": "Action"}]
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(MovieDetailDTO.self, from: json)
        let movie = dto.toMovie()
        XCTAssertEqual(movie.id, MediaID(provider: .tmdb, id: 27205))
        XCTAssertEqual(movie.title, "Inception")
        XCTAssertEqual(movie.releaseYear, 2010)
        XCTAssertEqual(movie.runtimeMinutes, 148)
        XCTAssertEqual(movie.genres.first?.name, "Action")
    }

    func test_showDetailDTO_decodesAndMapsToShow() throws {
        let json = """
        {
          "id": 1399,
          "name": "Game of Thrones",
          "original_name": "Game of Thrones",
          "first_air_date": "2011-04-17",
          "last_air_date": "2019-05-19",
          "status": "Ended",
          "in_production": false,
          "overview": "Seven noble families...",
          "poster_path": "/got.jpg",
          "backdrop_path": "/back.jpg",
          "vote_average": 8.4,
          "popularity": 200.0,
          "genres": [{"id": 18, "name": "Drama"}],
          "seasons": [
            {"season_number": 1, "name": "Season 1", "overview": "", "poster_path": "/s1.jpg"}
          ]
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(ShowDetailDTO.self, from: json)
        let show = dto.toShow()
        XCTAssertEqual(show.id, MediaID(provider: .tmdb, id: 1399))
        XCTAssertEqual(show.firstAirYear, 2011)
        XCTAssertEqual(show.lastAirYear, 2019)
        XCTAssertEqual(show.status, .ended)
        XCTAssertEqual(show.seasons.count, 1)
        XCTAssertEqual(show.seasons.first?.seasonNumber, 1)
    }

    func test_trendingItemDTO_movie_mapsToMovieMediaItem() throws {
        let json = """
        {
          "media_type": "movie",
          "id": 1,
          "title": "Title",
          "original_title": "Title",
          "release_date": "2020-01-01",
          "overview": "x",
          "poster_path": "/p.jpg",
          "backdrop_path": "/b.jpg",
          "vote_average": 7.0,
          "popularity": 50.0,
          "genre_ids": [28]
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(TrendingItemDTO.self, from: json)
        let item = dto.toMediaItem()
        switch item {
        case .movie(let m): XCTAssertEqual(m.id.id, 1)
        default: XCTFail("Expected movie")
        }
    }

    func test_trendingItemDTO_tv_mapsToShowMediaItem() throws {
        let json = """
        {
          "media_type": "tv",
          "id": 2,
          "name": "Show",
          "original_name": "Show",
          "first_air_date": "2018-09-25",
          "overview": "y",
          "poster_path": "/p.jpg",
          "backdrop_path": "/b.jpg",
          "vote_average": 7.5,
          "popularity": 60.0,
          "genre_ids": [18]
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(TrendingItemDTO.self, from: json)
        let item = dto.toMediaItem()
        switch item {
        case .show(let s): XCTAssertEqual(s.id.id, 2)
        default: XCTFail("Expected show")
        }
    }

    func test_trendingItemDTO_person_mapsToNil() throws {
        let json = """
        {"media_type": "person", "id": 3, "name": "Actor"}
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(TrendingItemDTO.self, from: json)
        XCTAssertNil(dto.toMediaItem())
    }

    func test_seasonDetailDTO_mapsEpisodes() throws {
        let json = """
        {
          "season_number": 1,
          "name": "Season 1",
          "overview": "",
          "poster_path": "/p.jpg",
          "air_date": "2011-04-17",
          "episodes": [
            {
              "id": 100,
              "season_number": 1,
              "episode_number": 1,
              "name": "Pilot",
              "overview": "",
              "still_path": "/s.jpg",
              "runtime": 60,
              "air_date": "2011-04-17"
            }
          ]
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(SeasonDetailDTO.self, from: json)
        let showID = MediaID(provider: .tmdb, id: 1399)
        let season = dto.toSeason(showID: showID)
        XCTAssertEqual(season.episodes.count, 1)
        XCTAssertEqual(season.episodes[0].episodeNumber, 1)
        XCTAssertEqual(season.episodes[0].showID, showID)
    }

    // MARK: - Helpers

    private func makeProvider() -> TMDBProvider {
        TMDBProvider(config: .init(bearerToken: ""))
    }
}
