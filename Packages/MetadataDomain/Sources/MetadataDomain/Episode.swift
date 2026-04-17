import Foundation

public struct Episode: Equatable, Sendable, Hashable, Codable {
    /// Distinct TMDB ID per episode.
    public let id: MediaID
    public let showID: MediaID
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let name: String
    public let overview: String
    public let stillPath: String?
    public let runtimeMinutes: Int?
    public let airDate: Date?

    public init(id: MediaID,
                showID: MediaID,
                seasonNumber: Int,
                episodeNumber: Int,
                name: String,
                overview: String,
                stillPath: String?,
                runtimeMinutes: Int?,
                airDate: Date?) {
        self.id = id
        self.showID = showID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.name = name
        self.overview = overview
        self.stillPath = stillPath
        self.runtimeMinutes = runtimeMinutes
        self.airDate = airDate
    }
}
