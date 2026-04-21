import Foundation
import ProviderDomain
import MetadataDomain

/// Searches EZTV (https://eztv.re) for TV show torrents.
///
/// EZTV is TV-only. Calling `search(for:)` with a `.movie` item always
/// returns an empty array without hitting the network.
struct EZTVProvider: MediaProvider {
    var name: String { "EZTV" }
    var authModel: ProviderAuthModel { .none }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(for item: MediaItem, page: Int) async throws -> [SourceCandidate] {
        guard case .show(let show) = item else { return [] }

        var components = URLComponents(string: "https://eztv.re/api/get-torrents")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "query", value: show.name),
        ]

        let url = components.url!
        let data: Data
        do {
            let (responseData, _) = try await session.data(from: url)
            data = responseData
        } catch {
            throw MediaProviderError.networkError(underlying: error as NSError)
        }

        let response = try JSONDecoder().decode(EZTVResponse.self, from: data)

        return (response.torrents ?? []).map { torrent in
            let hash = torrent.hash.lowercased()
            return SourceCandidate(
                id: "eztv:\(hash)",
                infoHash: hash,
                magnetURI: torrent.magnetURL,
                torrentURL: nil,
                title: torrent.title,
                quality: parseQuality(from: torrent.title),
                seeders: torrent.seeds,
                leechers: torrent.peers,
                sizeBytes: torrent.sizeBytes.flatMap { Int64($0) },
                providerName: name
            )
        }
    }

    // MARK: - Quality parsing

    private func parseQuality(from title: String) -> SourceQuality {
        let t = title.uppercased()
        if t.contains("2160P") || t.contains("4K") { return .remux }
        if t.contains("1080P") { return .bluRay }
        if t.contains("720P") { return .webDL }
        if t.contains("DVDRIP") || t.contains("480P") { return .dvdRip }
        if t.contains("HDTS") || t.contains(" TS ") || t.hasSuffix(" TS") || t.contains(".TS.") { return .ts }
        if t.contains("CAM") { return .cam }
        return .unknown
    }
}

// MARK: - Codable response types

private struct EZTVResponse: Decodable {
    let torrents: [EZTVTorrent]?
}

private struct EZTVTorrent: Decodable {
    let title: String
    let imdbID: String?
    let seeds: Int
    let peers: Int
    /// EZTV returns size_bytes as a JSON string.
    let sizeBytes: String?
    let magnetURL: String?
    let hash: String

    private enum CodingKeys: String, CodingKey {
        case title, seeds, peers, hash
        case imdbID = "imdb_id"
        case sizeBytes = "size_bytes"
        case magnetURL = "magnet_url"
    }
}
