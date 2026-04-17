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
                seasons: [Season]) {
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
    }
}
