import Foundation
@testable import MetadataDomain

/// Test-only `MetadataProvider` impl that returns canned responses from
/// pre-baked Swift fixtures. Lives under `Tests/MetadataDomainTests/Support/`
/// so any consumer test can substitute it without a network call.
///
/// Behaviour notes:
/// - Each method has an injectable `closure` so tests can return per-call
///   shaped responses; the default returns the standard fixture.
/// - `imageURL(path:size:)` is pure and uses the same shape as
///   `TMDBProvider.imageURL` so contract tests cover both impls.
public final class FakeMetadataProvider: MetadataProvider, @unchecked Sendable {

    public init() {}

    public var trendingHandler: (@Sendable (TrendingMedia, TrendingWindow) async throws -> [MediaItem])?
    public var popularHandler: (@Sendable (TrendingMedia) async throws -> [MediaItem])?
    public var topRatedHandler: (@Sendable (TrendingMedia) async throws -> [MediaItem])?
    public var searchMultiHandler: (@Sendable (String) async throws -> [MediaItem])?
    public var movieDetailHandler: (@Sendable (MediaID) async throws -> Movie)?
    public var showDetailHandler: (@Sendable (MediaID) async throws -> Show)?
    public var seasonDetailHandler: (@Sendable (MediaID, Int) async throws -> Season)?
    public var recommendationsHandler: (@Sendable (MediaID) async throws -> [MediaItem])?

    public func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] {
        if let h = trendingHandler { return try await h(media, window) }
        return [Self.canonicalMovie(), Self.canonicalShow()]
    }

    public func popular(media: TrendingMedia) async throws -> [MediaItem] {
        if let h = popularHandler { return try await h(media) }
        switch media {
        case .movie: return [Self.canonicalMovie()]
        case .tv: return [Self.canonicalShow()]
        case .all: return [Self.canonicalMovie(), Self.canonicalShow()]
        }
    }

    public func topRated(media: TrendingMedia) async throws -> [MediaItem] {
        if let h = topRatedHandler { return try await h(media) }
        switch media {
        case .movie: return [Self.canonicalMovie()]
        case .tv: return [Self.canonicalShow()]
        case .all: return [Self.canonicalMovie(), Self.canonicalShow()]
        }
    }

    public func searchMulti(query: String) async throws -> [MediaItem] {
        if let h = searchMultiHandler { return try await h(query) }
        // Fixed canned response for search; tests inspect the query as needed.
        return [Self.canonicalMovie()]
    }

    public func movieDetail(id: MediaID) async throws -> Movie {
        if let h = movieDetailHandler { return try await h(id) }
        return Self.canonicalMovieStruct(id: id)
    }

    public func showDetail(id: MediaID) async throws -> Show {
        if let h = showDetailHandler { return try await h(id) }
        return Self.canonicalShowStruct(id: id)
    }

    public func seasonDetail(showID: MediaID, season: Int) async throws -> Season {
        if let h = seasonDetailHandler { return try await h(showID, season) }
        return Self.canonicalSeasonStruct(showID: showID, season: season)
    }

    public func recommendations(for id: MediaID) async throws -> [MediaItem] {
        if let h = recommendationsHandler { return try await h(id) }
        return [Self.canonicalMovie()]
    }

    public func imageURL(path: String, size: TMDBImageSize) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "https://image.tmdb.org/t/p")!
            .appendingPathComponent(size.rawValue)
            .appendingPathComponent(trimmed)
    }

    // MARK: - Canned fixtures

    public static func canonicalMovie() -> MediaItem { .movie(canonicalMovieStruct()) }
    public static func canonicalShow() -> MediaItem { .show(canonicalShowStruct()) }

    public static func canonicalMovieStruct(id: MediaID = MediaID(provider: .tmdb, id: 27205)) -> Movie {
        Movie(id: id,
              title: "Inception",
              originalTitle: "Inception",
              releaseYear: 2010,
              runtimeMinutes: 148,
              overview: "A thief who steals corporate secrets.",
              genres: [Genre(id: 28, name: "Action"), Genre(id: 878, name: "Science Fiction")],
              posterPath: "/inception.jpg",
              backdropPath: "/inception_back.jpg",
              voteAverage: 8.4,
              popularity: 100.0)
    }

    public static func canonicalShowStruct(id: MediaID = MediaID(provider: .tmdb, id: 1399)) -> Show {
        Show(id: id,
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
             seasons: [])
    }

    public static func canonicalSeasonStruct(showID: MediaID = MediaID(provider: .tmdb, id: 1399),
                                             season: Int = 1) -> Season {
        Season(showID: showID,
               seasonNumber: season,
               name: "Season \(season)",
               overview: "The first season.",
               posterPath: "/got_s1.jpg",
               airDate: nil,
               episodes: [
                Episode(id: MediaID(provider: .tmdb, id: 63056),
                        showID: showID,
                        seasonNumber: season,
                        episodeNumber: 1,
                        name: "Winter Is Coming",
                        overview: "Eddard Stark.",
                        stillPath: "/s1e1.jpg",
                        runtimeMinutes: 62,
                        airDate: nil)
               ])
    }
}
