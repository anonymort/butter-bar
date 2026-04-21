import MetadataDomain

/// Abstraction over a single torrent-source provider.
///
/// Conforming types must be `Sendable` — they are called concurrently from the
/// source-resolution pipeline. Non-torrent providers (HTTP streams) are a
/// v1.5+ extension; the protocol is intentionally left open for that.
///
/// Results are returned in provider-defined order. Ranking across providers
/// is the responsibility of the source-resolution pipeline, not the provider.
public protocol MediaProvider: Sendable {
    /// Human-readable provider name used in UI and logging (e.g. `"YTS"`).
    var name: String { get }

    /// Declares how this provider authenticates. The pipeline reads this to
    /// gate providers that require credentials the user has not supplied.
    var authModel: ProviderAuthModel { get }

    /// Search for sources matching `item`. `page` is 1-indexed; providers
    /// that do not support pagination should ignore it and always return their
    /// full result set.
    ///
    /// Throws `MediaProviderError` for recoverable failures.
    func search(for item: MediaItem, page: Int) async throws -> [SourceCandidate]
}
