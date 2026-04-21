import Foundation
import ProviderDomain
import MetadataDomain

/// Searches YTS (https://yts.mx) for movie torrents.
///
/// YTS is movies-only. Calling `search(for:)` with a `.show` item always
/// returns an empty array without hitting the network.
struct YTSProvider: MediaProvider {
    var name: String { "YTS" }
    var authModel: ProviderAuthModel { .none }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(for item: MediaItem, page: Int) async throws -> [SourceCandidate] {
        guard case .movie(let movie) = item else { return [] }

        var components = URLComponents(string: "https://yts.mx/api/v2/list_movies.json")!
        components.queryItems = [
            URLQueryItem(name: "query_term", value: movie.title),
            URLQueryItem(name: "sort_by", value: "seeds"),
            URLQueryItem(name: "limit", value: "20"),
            URLQueryItem(name: "page", value: "\(page)"),
        ]

        let url = components.url!
        let data: Data
        do {
            let (responseData, _) = try await session.data(from: url)
            data = responseData
        } catch {
            throw MediaProviderError.networkError(underlying: error as NSError)
        }

        let response = try JSONDecoder().decode(YTSResponse.self, from: data)
        let movies = response.data.movies ?? []

        var candidates: [SourceCandidate] = []
        for ytsMovie in movies {
            // Drop results where year is off by more than 2 if we have a known year.
            if let known = movie.releaseYear, let resultYear = ytsMovie.year {
                if abs(known - resultYear) > 2 { continue }
            }
            for torrent in ytsMovie.torrents ?? [] {
                let quality = resolveQuality(type: torrent.type, qualityString: torrent.quality)
                let hash = torrent.hash.lowercased()
                let encodedTitle = ytsMovie.title
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ytsMovie.title
                let magnet = "magnet:?xt=urn:btih:\(hash)&dn=\(encodedTitle)"
                    + "&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce"
                    + "&tr=udp%3A%2F%2Fopen.tracker.cl%3A1337%2Fannounce"

                candidates.append(SourceCandidate(
                    id: "yts:\(hash)",
                    infoHash: hash,
                    magnetURI: magnet,
                    torrentURL: nil,
                    title: "\(ytsMovie.title) (\(ytsMovie.year.map(String.init) ?? "?")) [\(torrent.quality)]",
                    quality: quality,
                    seeders: torrent.seeds,
                    leechers: torrent.peers,
                    sizeBytes: torrent.sizeBytes,
                    providerName: name
                ))
            }
        }
        return candidates
    }

    // MARK: - Quality resolution

    private func resolveQuality(type: String?, qualityString: String) -> SourceQuality {
        // type field takes precedence
        if let type {
            switch type.lowercased() {
            case "bluray": return .bluRay
            case "web":    return .webDL
            case "dvd":    return .dvdRip
            default: break
            }
        }
        // fall back to quality string
        switch qualityString {
        case "2160p": return .remux
        case "1080p": return .bluRay
        case "720p", "480p": return .webDL
        default: return .unknown
        }
    }
}

// MARK: - Codable response types

private struct YTSResponse: Decodable {
    let data: YTSData
}

private struct YTSData: Decodable {
    let movies: [YTSMovie]?
}

private struct YTSMovie: Decodable {
    let title: String
    let year: Int?
    let imdbCode: String?
    let torrents: [YTSTorrent]?

    private enum CodingKeys: String, CodingKey {
        case title, year, torrents
        case imdbCode = "imdb_code"
    }
}

private struct YTSTorrent: Decodable {
    let hash: String
    let quality: String
    let seeds: Int
    let peers: Int
    let sizeBytes: Int64?
    let type: String?

    private enum CodingKeys: String, CodingKey {
        case hash, quality, seeds, peers, type
        case sizeBytes = "size_bytes"
    }
}
