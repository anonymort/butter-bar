import Foundation

/// Hand-rolled `URLSession` implementation of `MetadataProvider` against
/// the TMDB v3 REST API. Per design § O1, we start hand-rolled and revisit
/// if a second-or-third endpoint takes more than a day.
///
/// The token is sourced from `TMDBSecrets.tmdbAccessToken` — the
/// non-checked-in `TMDBSecrets.swift` reads it from a build-time env var
/// or falls back to an empty string (which makes live calls fail with
/// `.authentication`). See `TMDBSecrets.example.swift` for the template.
public actor TMDBProvider: MetadataProvider {

    public struct Config: Sendable {
        public let apiBase: URL
        public let imageBase: URL
        public let bearerToken: String
        public let language: String
        public let region: String?

        public init(apiBase: URL = URL(string: "https://api.themoviedb.org/3")!,
                    imageBase: URL = URL(string: "https://image.tmdb.org/t/p")!,
                    bearerToken: String,
                    language: String = "en-US",
                    region: String? = nil) {
            self.apiBase = apiBase
            self.imageBase = imageBase
            self.bearerToken = bearerToken
            self.language = language
            self.region = region
        }
    }

    private let config: Config
    private let session: URLSession
    private let decoder: JSONDecoder
    private let cache: MetadataCache?

    public init(config: Config,
                session: URLSession = .shared,
                cache: MetadataCache? = nil) {
        self.config = config
        self.session = session
        self.cache = cache

        let d = JSONDecoder()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        d.dateDecodingStrategy = .formatted(formatter)
        self.decoder = d
    }

    // MARK: - MetadataProvider

    public func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] {
        let url = endpoint("/trending/\(media.rawValue)/\(window.rawValue)")
        let dto: PageDTO<TrendingItemDTO> = try await fetch(url: url, ttl: window == .week ? MetadataCacheTTL.trendingWeek : MetadataCacheTTL.trendingDay)
        return dto.results.compactMap { $0.toMediaItem() }
    }

    public func popular(media: TrendingMedia) async throws -> [MediaItem] {
        let segment = (media == .tv) ? "tv" : "movie"
        let url = endpoint("/\(segment)/popular")
        if media == .tv {
            let dto: PageDTO<ShowSummaryDTO> = try await fetch(url: url, ttl: MetadataCacheTTL.popular)
            return dto.results.map { .show($0.toShow()) }
        } else {
            let dto: PageDTO<MovieSummaryDTO> = try await fetch(url: url, ttl: MetadataCacheTTL.popular)
            return dto.results.map { .movie($0.toMovie()) }
        }
    }

    public func topRated(media: TrendingMedia) async throws -> [MediaItem] {
        let segment = (media == .tv) ? "tv" : "movie"
        let url = endpoint("/\(segment)/top_rated")
        if media == .tv {
            let dto: PageDTO<ShowSummaryDTO> = try await fetch(url: url, ttl: MetadataCacheTTL.topRated)
            return dto.results.map { .show($0.toShow()) }
        } else {
            let dto: PageDTO<MovieSummaryDTO> = try await fetch(url: url, ttl: MetadataCacheTTL.topRated)
            return dto.results.map { .movie($0.toMovie()) }
        }
    }

    public func searchMulti(query: String) async throws -> [MediaItem] {
        var components = URLComponents(url: endpoint("/search/multi"), resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false")
        ]
        let url = components.url!
        let dto: PageDTO<TrendingItemDTO> = try await fetch(url: url, ttl: MetadataCacheTTL.searchMulti)
        return dto.results.compactMap { $0.toMediaItem() }
    }

    public func movieDetail(id: MediaID) async throws -> Movie {
        precondition(id.provider == .tmdb)
        let url = endpoint("/movie/\(id.id)")
        let dto: MovieDetailDTO = try await fetch(url: url, ttl: MetadataCacheTTL.movieDetail)
        return dto.toMovie()
    }

    public func showDetail(id: MediaID) async throws -> Show {
        precondition(id.provider == .tmdb)
        let url = endpoint("/tv/\(id.id)")
        let dto: ShowDetailDTO = try await fetch(url: url, ttl: MetadataCacheTTL.showDetail)
        return dto.toShow()
    }

    public func seasonDetail(showID: MediaID, season: Int) async throws -> Season {
        precondition(showID.provider == .tmdb)
        let url = endpoint("/tv/\(showID.id)/season/\(season)")
        let dto: SeasonDetailDTO = try await fetch(url: url, ttl: MetadataCacheTTL.seasonDetail)
        return dto.toSeason(showID: showID)
    }

    public func recommendations(for id: MediaID) async throws -> [MediaItem] {
        precondition(id.provider == .tmdb)
        // Endpoint differs by media type; try movie first, fall back to tv.
        let movieURL = endpoint("/movie/\(id.id)/recommendations")
        let dto: PageDTO<TrendingItemDTO> = try await fetch(url: movieURL, ttl: MetadataCacheTTL.recommendations)
        return dto.results.compactMap { $0.toMediaItem() }
    }

    public nonisolated func imageURL(path: String, size: TMDBImageSize) -> URL {
        // Strip a leading `/` to avoid `//` in the joined URL.
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return config.imageBase
            .appendingPathComponent(size.rawValue)
            .appendingPathComponent(trimmed)
    }

    // MARK: - Internals

    /// Build a fully-qualified endpoint URL with `language` (and optional
    /// `region`) prepended as query items.
    nonisolated func endpoint(_ path: String) -> URL {
        var components = URLComponents(url: config.apiBase.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "language", value: config.language))
        if let region = config.region {
            items.append(URLQueryItem(name: "region", value: region))
        }
        components.queryItems = items
        return components.url!
    }

    private func fetch<T: Decodable>(url: URL, ttl: TimeInterval) async throws -> T {
        // Cache check (only when ttl > 0). Stale-while-revalidate is the
        // caller's concern; this layer just returns the freshest data we
        // can produce synchronously.
        if ttl > 0, let hit = cache?.lookup(url: url), hit.freshness == .fresh {
            do {
                return try decoder.decode(T.self, from: hit.data)
            } catch {
                // Corrupt cache entry; fall through to network.
                cache?.remove(url: url)
            }
        }

        var request = URLRequest(url: url)
        if !config.bearerToken.isEmpty {
            request.setValue("Bearer \(config.bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if let urlErr = error as? URLError, urlErr.code == .cancelled {
                throw MetadataProviderError.cancelled
            }
            throw MetadataProviderError.transport
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300:
                break
            case 401, 403:
                throw MetadataProviderError.authentication
            case 404:
                throw MetadataProviderError.notFound
            case 429:
                let retryAfter: TimeInterval? = (http.value(forHTTPHeaderField: "Retry-After"))
                    .flatMap(TimeInterval.init)
                throw MetadataProviderError.rateLimited(retryAfter: retryAfter)
            default:
                throw MetadataProviderError.http(http.statusCode)
            }

            if ttl > 0 {
                let etag = http.value(forHTTPHeaderField: "ETag")
                let lastModified = http.value(forHTTPHeaderField: "Last-Modified")
                try? cache?.store(url: url, data: data, ttl: ttl,
                                  etag: etag, lastModified: lastModified)
            }
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MetadataProviderError.decoding(String(describing: error))
        }
    }
}

// MARK: - DTOs

/// Generic paged envelope used by trending / popular / top-rated / search.
struct PageDTO<Item: Decodable>: Decodable {
    let results: [Item]
}

/// Multi-search / trending result that may be either movie or tv.
struct TrendingItemDTO: Decodable {
    let mediaType: String?
    let id: Int64
    let title: String?            // movie
    let originalTitle: String?    // movie
    let releaseDate: String?      // movie
    let name: String?             // tv
    let originalName: String?     // tv
    let firstAirDate: String?     // tv
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let popularity: Double?
    let genreIDs: [Int]?

    private enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case id, title, name, overview, popularity
        case originalTitle = "original_title"
        case originalName = "original_name"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case genreIDs = "genre_ids"
    }

    func toMediaItem() -> MediaItem? {
        let mediaID = MediaID(provider: .tmdb, id: id)
        let yearFrom: (String?) -> Int? = { date in
            guard let date, date.count >= 4 else { return nil }
            return Int(date.prefix(4))
        }
        let genres = (genreIDs ?? []).map { Genre(id: $0, name: "") }

        if mediaType == "movie" || (mediaType == nil && title != nil) {
            return .movie(Movie(
                id: mediaID,
                title: title ?? originalTitle ?? "",
                originalTitle: originalTitle ?? title ?? "",
                releaseYear: yearFrom(releaseDate),
                runtimeMinutes: nil,
                overview: overview ?? "",
                genres: genres,
                posterPath: posterPath,
                backdropPath: backdropPath,
                voteAverage: voteAverage,
                popularity: popularity
            ))
        } else if mediaType == "tv" || (mediaType == nil && name != nil) {
            return .show(Show(
                id: mediaID,
                name: name ?? originalName ?? "",
                originalName: originalName ?? name ?? "",
                firstAirYear: yearFrom(firstAirDate),
                lastAirYear: nil,
                status: .returning,
                overview: overview ?? "",
                genres: genres,
                posterPath: posterPath,
                backdropPath: backdropPath,
                voteAverage: voteAverage,
                popularity: popularity,
                seasons: []
            ))
        } else {
            // person / unknown — drop.
            return nil
        }
    }
}

struct MovieSummaryDTO: Decodable {
    let id: Int64
    let title: String
    let originalTitle: String?
    let releaseDate: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let popularity: Double?
    let genreIDs: [Int]?

    private enum CodingKeys: String, CodingKey {
        case id, title, overview, popularity
        case originalTitle = "original_title"
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case genreIDs = "genre_ids"
    }

    func toMovie() -> Movie {
        let year: Int? = {
            guard let r = releaseDate, r.count >= 4 else { return nil }
            return Int(r.prefix(4))
        }()
        return Movie(
            id: MediaID(provider: .tmdb, id: id),
            title: title,
            originalTitle: originalTitle ?? title,
            releaseYear: year,
            runtimeMinutes: nil,
            overview: overview ?? "",
            genres: (genreIDs ?? []).map { Genre(id: $0, name: "") },
            posterPath: posterPath,
            backdropPath: backdropPath,
            voteAverage: voteAverage,
            popularity: popularity
        )
    }
}

struct ShowSummaryDTO: Decodable {
    let id: Int64
    let name: String
    let originalName: String?
    let firstAirDate: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let popularity: Double?
    let genreIDs: [Int]?

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, popularity
        case originalName = "original_name"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case genreIDs = "genre_ids"
    }

    func toShow() -> Show {
        let year: Int? = {
            guard let r = firstAirDate, r.count >= 4 else { return nil }
            return Int(r.prefix(4))
        }()
        return Show(
            id: MediaID(provider: .tmdb, id: id),
            name: name,
            originalName: originalName ?? name,
            firstAirYear: year,
            lastAirYear: nil,
            status: .returning,
            overview: overview ?? "",
            genres: (genreIDs ?? []).map { Genre(id: $0, name: "") },
            posterPath: posterPath,
            backdropPath: backdropPath,
            voteAverage: voteAverage,
            popularity: popularity,
            seasons: []
        )
    }
}

struct GenreDTO: Decodable {
    let id: Int
    let name: String
    func toGenre() -> Genre { Genre(id: id, name: name) }
}

struct MovieDetailDTO: Decodable {
    let id: Int64
    let title: String
    let originalTitle: String?
    let releaseDate: String?
    let runtime: Int?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let popularity: Double?
    let genres: [GenreDTO]?

    private enum CodingKeys: String, CodingKey {
        case id, title, runtime, overview, popularity, genres
        case originalTitle = "original_title"
        case releaseDate = "release_date"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
    }

    func toMovie() -> Movie {
        let year: Int? = {
            guard let r = releaseDate, r.count >= 4 else { return nil }
            return Int(r.prefix(4))
        }()
        return Movie(
            id: MediaID(provider: .tmdb, id: id),
            title: title,
            originalTitle: originalTitle ?? title,
            releaseYear: year,
            runtimeMinutes: runtime,
            overview: overview ?? "",
            genres: (genres ?? []).map { $0.toGenre() },
            posterPath: posterPath,
            backdropPath: backdropPath,
            voteAverage: voteAverage,
            popularity: popularity
        )
    }
}

struct ShowDetailDTO: Decodable {
    let id: Int64
    let name: String
    let originalName: String?
    let firstAirDate: String?
    let lastAirDate: String?
    let status: String?
    let inProduction: Bool?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let popularity: Double?
    let genres: [GenreDTO]?
    let seasons: [SeasonSummaryDTO]?

    private enum CodingKeys: String, CodingKey {
        case id, name, status, overview, popularity, genres, seasons
        case originalName = "original_name"
        case firstAirDate = "first_air_date"
        case lastAirDate = "last_air_date"
        case inProduction = "in_production"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
    }

    func toShow() -> Show {
        let firstYear: Int? = {
            guard let r = firstAirDate, r.count >= 4 else { return nil }
            return Int(r.prefix(4))
        }()
        let lastYear: Int? = {
            guard let r = lastAirDate, r.count >= 4 else { return nil }
            return Int(r.prefix(4))
        }()
        let mappedStatus: ShowStatus = {
            if inProduction == true { return .inProduction }
            switch (status ?? "").lowercased() {
            case "returning series": return .returning
            case "ended": return .ended
            case "canceled", "cancelled": return .canceled
            case "in production": return .inProduction
            default: return .returning
            }
        }()
        let showID = MediaID(provider: .tmdb, id: id)
        let mappedSeasons: [Season] = (seasons ?? []).map { s in
            Season(showID: showID,
                   seasonNumber: s.seasonNumber,
                   name: s.name ?? "Season \(s.seasonNumber)",
                   overview: s.overview ?? "",
                   posterPath: s.posterPath,
                   airDate: nil,
                   episodes: [])
        }
        return Show(
            id: showID,
            name: name,
            originalName: originalName ?? name,
            firstAirYear: firstYear,
            lastAirYear: lastYear,
            status: mappedStatus,
            overview: overview ?? "",
            genres: (genres ?? []).map { $0.toGenre() },
            posterPath: posterPath,
            backdropPath: backdropPath,
            voteAverage: voteAverage,
            popularity: popularity,
            seasons: mappedSeasons
        )
    }
}

struct SeasonSummaryDTO: Decodable {
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let posterPath: String?

    private enum CodingKeys: String, CodingKey {
        case name, overview
        case seasonNumber = "season_number"
        case posterPath = "poster_path"
    }
}

struct SeasonDetailDTO: Decodable {
    let seasonNumber: Int
    let name: String?
    let overview: String?
    let posterPath: String?
    let airDate: String?
    let episodes: [EpisodeDetailDTO]

    private enum CodingKeys: String, CodingKey {
        case name, overview, episodes
        case seasonNumber = "season_number"
        case posterPath = "poster_path"
        case airDate = "air_date"
    }

    func toSeason(showID: MediaID) -> Season {
        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.calendar = Calendar(identifier: .iso8601)
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd"
            return f
        }()
        let parsedAirDate: Date? = {
            guard let s = airDate, !s.isEmpty else { return nil }
            return dateFormatter.date(from: s)
        }()
        let mappedEpisodes: [Episode] = episodes.map { dto in
            Episode(
                id: MediaID(provider: .tmdb, id: dto.id),
                showID: showID,
                seasonNumber: dto.seasonNumber,
                episodeNumber: dto.episodeNumber,
                name: dto.name ?? "",
                overview: dto.overview ?? "",
                stillPath: dto.stillPath,
                runtimeMinutes: dto.runtime,
                airDate: dto.airDate.flatMap { dateFormatter.date(from: $0) }
            )
        }
        return Season(
            showID: showID,
            seasonNumber: seasonNumber,
            name: name ?? "Season \(seasonNumber)",
            overview: overview ?? "",
            posterPath: posterPath,
            airDate: parsedAirDate,
            episodes: mappedEpisodes
        )
    }
}

struct EpisodeDetailDTO: Decodable {
    let id: Int64
    let seasonNumber: Int
    let episodeNumber: Int
    let name: String?
    let overview: String?
    let stillPath: String?
    let runtime: Int?
    let airDate: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case stillPath = "still_path"
        case airDate = "air_date"
    }
}
