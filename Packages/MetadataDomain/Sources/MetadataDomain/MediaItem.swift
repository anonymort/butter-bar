import Foundation

/// Discriminated union over the two top-level metadata entities. Every
/// browse row, detail view, search result, and continue-watching projection
/// ranges over `[MediaItem]`. Codable round-trips cleanly via Swift's
/// automatic synthesis on enums with associated values.
public enum MediaItem: Equatable, Sendable, Hashable, Codable {
    case movie(Movie)
    case show(Show)

    public var id: MediaID {
        switch self {
        case .movie(let m): return m.id
        case .show(let s): return s.id
        }
    }
}

public enum TrendingMedia: String, Sendable, Equatable, Hashable, Codable {
    case movie
    case tv
    case all
}

public enum TrendingWindow: String, Sendable, Equatable, Hashable, Codable {
    case day
    case week
}
