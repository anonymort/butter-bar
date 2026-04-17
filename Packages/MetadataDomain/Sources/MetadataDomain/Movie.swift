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
                popularity: Double?) {
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
    }
}
