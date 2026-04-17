import Foundation

/// `URLCache`-backed image fetcher. No third-party image library; everything
/// goes through `URLSession` with a custom `URLCache` configured against a
/// 500 MB disk budget under `metadata/images/`.
///
/// Failure mode: callers receive a typed error, never a broken image; the
/// SwiftUI consumer renders a brand-tokenized placeholder. Placeholder
/// rendering itself is UI-side; this layer is concerned only with bytes.
public final class ImageCache: @unchecked Sendable {

    public let urlCache: URLCache
    public let session: URLSession
    public let diskPath: URL

    public init(baseDirectory: URL) throws {
        let dir = baseDirectory.appendingPathComponent(ImageCacheConfig.directoryName,
                                                       isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.diskPath = dir
        self.urlCache = URLCache(
            memoryCapacity: ImageCacheConfig.memoryCapacityBytes,
            diskCapacity: ImageCacheConfig.diskCapacityBytes,
            directory: dir
        )
        let config = URLSessionConfiguration.default
        config.urlCache = urlCache
        config.requestCachePolicy = .useProtocolCachePolicy
        self.session = URLSession(configuration: config)
    }

    public enum Failure: Error, Equatable, Sendable {
        case transport
        case http(Int)
        case empty
    }

    /// Fetch image bytes. Cached at the `URLCache` layer.
    public func data(for url: URL) async -> Result<Data, Failure> {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                return .failure(.http(http.statusCode))
            }
            if data.isEmpty {
                return .failure(.empty)
            }
            return .success(data)
        } catch {
            return .failure(.transport)
        }
    }
}
