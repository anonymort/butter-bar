import XCTest
@testable import MetadataDomain

final class TMDBProviderCastTests: XCTestCase {
    func testMovieDetailDecodesCreditsCast() throws {
        let json = """
        {
          "id": 27205,
          "title": "Inception",
          "original_title": "Inception",
          "release_date": "2010-07-16",
          "runtime": 148,
          "overview": "A thief who steals corporate secrets.",
          "poster_path": "/poster.jpg",
          "backdrop_path": "/backdrop.jpg",
          "vote_average": 8.4,
          "popularity": 100.0,
          "genres": [{ "id": 28, "name": "Action" }],
          "credits": {
            "cast": [
              { "id": 1, "name": "Leonardo DiCaprio", "character": "Cobb", "profile_path": "/leo.jpg" },
              { "id": 2, "name": "Elliot Page", "character": "Ariadne", "profile_path": null }
            ]
          }
        }
        """
        let dto = try JSONDecoder().decode(MovieDetailDTO.self, from: Data(json.utf8))
        let movie = dto.toMovie()

        XCTAssertEqual(movie.cast, [
            CastMember(id: 1, name: "Leonardo DiCaprio", character: "Cobb", profilePath: "/leo.jpg"),
            CastMember(id: 2, name: "Elliot Page", character: "Ariadne", profilePath: nil)
        ])
    }

    func testShowDetailDecodesCreditsCast() throws {
        let json = """
        {
          "id": 1399,
          "name": "Game of Thrones",
          "original_name": "Game of Thrones",
          "first_air_date": "2011-04-17",
          "last_air_date": "2019-05-19",
          "status": "Ended",
          "in_production": false,
          "overview": "Seven noble families fight for control.",
          "poster_path": "/poster.jpg",
          "backdrop_path": "/backdrop.jpg",
          "vote_average": 8.4,
          "popularity": 200.0,
          "genres": [{ "id": 18, "name": "Drama" }],
          "seasons": [],
          "credits": {
            "cast": [
              { "id": 3, "name": "Emilia Clarke", "character": "Daenerys Targaryen", "profile_path": "/emilia.jpg" }
            ]
          }
        }
        """
        let dto = try JSONDecoder().decode(ShowDetailDTO.self, from: Data(json.utf8))
        let show = dto.toShow()

        XCTAssertEqual(show.cast, [
            CastMember(id: 3, name: "Emilia Clarke", character: "Daenerys Targaryen", profilePath: "/emilia.jpg")
        ])
    }
}
