import Foundation

/// Stable identifier for a metadata entity (movie, show, season, episode).
///
/// Wraps a `(provider, id)` pair so v1.5+ can introduce additional providers
/// (`.imdb`, `.tvdb`, `.fanart`) without migrating cached data — the
/// `provider` discriminator silently invalidates entries that don't carry it.
public struct MediaID: Equatable, Sendable, Hashable, Codable {
    public let provider: Provider
    public let id: Int64

    public init(provider: Provider, id: Int64) {
        self.provider = provider
        self.id = id
    }

    public enum Provider: String, Sendable, Codable, Hashable, Equatable {
        case tmdb
    }
}
