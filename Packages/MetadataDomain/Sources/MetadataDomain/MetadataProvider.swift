import Foundation

/// Errors that any `MetadataProvider` impl should map its native failures
/// onto. The concrete UI is allowed to inspect these to render calm copy
/// per `06-brand.md § Voice` ("We can't reach the catalogue right now").
public enum MetadataProviderError: Error, Equatable, Sendable {
    case transport
    case rateLimited(retryAfter: TimeInterval?)
    case authentication
    case http(Int)
    case decoding(String)
    case notFound
    case cancelled
}

/// Single seam between the app and a metadata source. The TMDB-backed
/// concrete impl lives in `TMDBProvider`; tests use `FakeMetadataProvider`
/// from `Tests/Support/`. Adding new providers is one file each.
public protocol MetadataProvider: Sendable {
    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem]
    func popular(media: TrendingMedia) async throws -> [MediaItem]
    func topRated(media: TrendingMedia) async throws -> [MediaItem]

    func searchMulti(query: String) async throws -> [MediaItem]

    func movieDetail(id: MediaID) async throws -> Movie
    func showDetail(id: MediaID) async throws -> Show
    func seasonDetail(showID: MediaID, season: Int) async throws -> Season

    func recommendations(for id: MediaID) async throws -> [MediaItem]

    func imageURL(path: String, size: TMDBImageSize) -> URL
}
