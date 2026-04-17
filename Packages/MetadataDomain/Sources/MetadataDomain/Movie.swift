import Foundation

public struct Movie: Equatable, Sendable, Hashable, Codable {
    public let id: MediaID
    public let title: String
    public let originalTitle: String
    public let releaseYear: Int?
    public let runtimeMinutes: Int?
    public let overview: String
    public let genres: [Genre]
    /// TMDB image path (e.g. `/abc123.jpg`); combine with
    /// `MetadataProvider.imageURL(path:size:)` to produce a full URL.
    public let posterPath: String?
    public let backdropPath: String?
    public let voteAverage: Double?
    public let popularity: Double?
    public let cast: [CastMember]

    public init(id: MediaID,
                title: String,
                originalTitle: String,
                releaseYear: Int?,
                runtimeMinutes: Int?,
                overview: String,
                genres: [Genre],
                posterPath: String?,
                backdropPath: String?,
                voteAverage: Double?,
                popularity: Double?,
                cast: [CastMember] = []) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.releaseYear = releaseYear
        self.runtimeMinutes = runtimeMinutes
        self.overview = overview
        self.genres = genres
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.voteAverage = voteAverage
        self.popularity = popularity
        self.cast = cast
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, originalTitle, releaseYear, runtimeMinutes, overview
        case genres, posterPath, backdropPath, voteAverage, popularity, cast
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(MediaID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        originalTitle = try container.decode(String.self, forKey: .originalTitle)
        releaseYear = try container.decodeIfPresent(Int.self, forKey: .releaseYear)
        runtimeMinutes = try container.decodeIfPresent(Int.self, forKey: .runtimeMinutes)
        overview = try container.decode(String.self, forKey: .overview)
        genres = try container.decode([Genre].self, forKey: .genres)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try container.decodeIfPresent(String.self, forKey: .backdropPath)
        voteAverage = try container.decodeIfPresent(Double.self, forKey: .voteAverage)
        popularity = try container.decodeIfPresent(Double.self, forKey: .popularity)
        cast = try container.decodeIfPresent([CastMember].self, forKey: .cast) ?? []
    }
}
