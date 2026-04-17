import Foundation

public struct Season: Equatable, Sendable, Hashable, Codable {
    public let showID: MediaID
    public let seasonNumber: Int
    public let name: String
    public let overview: String
    public let posterPath: String?
    public let airDate: Date?
    public let episodes: [Episode]

    public init(showID: MediaID,
                seasonNumber: Int,
                name: String,
                overview: String,
                posterPath: String?,
                airDate: Date?,
                episodes: [Episode]) {
        self.showID = showID
        self.seasonNumber = seasonNumber
        self.name = name
        self.overview = overview
        self.posterPath = posterPath
        self.airDate = airDate
        self.episodes = episodes
    }
}
