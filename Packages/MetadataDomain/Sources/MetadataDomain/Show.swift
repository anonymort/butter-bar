import Foundation

public struct Show: Equatable, Sendable, Hashable, Codable {
    public let id: MediaID
    public let name: String
    public let originalName: String
    public let firstAirYear: Int?
    public let lastAirYear: Int?
    public let status: ShowStatus
    public let overview: String
    public let genres: [Genre]
    public let posterPath: String?
    public let backdropPath: String?
    public let voteAverage: Double?
    public let popularity: Double?
    /// Hydrated lazily by the detail fetch; can be empty for browse-row results.
    public let seasons: [Season]
    public let cast: [CastMember]
    /// IMDb identifier in canonical `tt0903747` form. Populated from TMDb
    /// external IDs when detail is fetched; `nil` for browse-row projections.
    /// Consumed by external provider integrations (e.g. Jackett/Torznab) that
    /// support `imdbid` lookups in addition to `tmdbid`.
    public let imdbID: String?

    public init(id: MediaID,
                name: String,
                originalName: String,
                firstAirYear: Int?,
                lastAirYear: Int?,
                status: ShowStatus,
                overview: String,
                genres: [Genre],
                posterPath: String?,
                backdropPath: String?,
                voteAverage: Double?,
                popularity: Double?,
                seasons: [Season],
                cast: [CastMember] = [],
                imdbID: String? = nil) {
        self.id = id
        self.name = name
        self.originalName = originalName
        self.firstAirYear = firstAirYear
        self.lastAirYear = lastAirYear
        self.status = status
        self.overview = overview
        self.genres = genres
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.voteAverage = voteAverage
        self.popularity = popularity
        self.seasons = seasons
        self.cast = cast
        self.imdbID = imdbID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, originalName, firstAirYear, lastAirYear, status
        case overview, genres, posterPath, backdropPath, voteAverage
        case popularity, seasons, cast, imdbID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(MediaID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        originalName = try container.decode(String.self, forKey: .originalName)
        firstAirYear = try container.decodeIfPresent(Int.self, forKey: .firstAirYear)
        lastAirYear = try container.decodeIfPresent(Int.self, forKey: .lastAirYear)
        status = try container.decode(ShowStatus.self, forKey: .status)
        overview = try container.decode(String.self, forKey: .overview)
        genres = try container.decode([Genre].self, forKey: .genres)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try container.decodeIfPresent(String.self, forKey: .backdropPath)
        voteAverage = try container.decodeIfPresent(Double.self, forKey: .voteAverage)
        popularity = try container.decodeIfPresent(Double.self, forKey: .popularity)
        seasons = try container.decode([Season].self, forKey: .seasons)
        cast = try container.decodeIfPresent([CastMember].self, forKey: .cast) ?? []
        imdbID = try container.decodeIfPresent(String.self, forKey: .imdbID)
    }
}
