import Foundation
import ProviderDomain
import MetadataDomain

/// Searches a user-run [Jackett](https://github.com/Jackett/Jackett) instance
/// for torrents across whichever indexers the user has configured in Jackett
/// itself. Jackett exposes a unified Torznab endpoint; ButterBar delegates all
/// per-indexer complexity to Jackett and parses the resulting RSS/XML response.
///
/// This provider is only registered when the user has entered a non-empty API
/// key in Settings > Providers — see `DefaultProviderRegistry`.
///
/// Category routing: `cat=2000` for movies, `cat=5000` for TV shows, matching
/// the Torznab category tree.
struct JackettProvider: MediaProvider {
    var name: String { "Jackett" }
    var authModel: ProviderAuthModel { .apiKey(key: apiKey) }

    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession

    init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    func search(for item: MediaItem, page _: Int) async throws -> [SourceCandidate] {
        let query: String
        let category: String
        let tmdbID: String?
        let imdbID: String?
        switch item {
        case .movie(let movie):
            query = movie.title
            category = "2000"
            tmdbID = idString(for: movie.id)
            imdbID = Self.normaliseIMDbID(movie.imdbID)
        case .show(let show):
            query = show.name
            category = "5000"
            tmdbID = idString(for: show.id)
            imdbID = Self.normaliseIMDbID(show.imdbID)
        }

        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v2.0/indexers/all/results/torznab/api"),
            resolvingAgainstBaseURL: false
        ) else {
            throw MediaProviderError.networkError(underlying: JackettURLError.invalidBaseURL as NSError)
        }
        // Torznab `t=search` supports metadata-id filters on indexers that
        // implement them. Passing both `tmdbid` and `imdbid` lets ButterBar
        // benefit from the most accurate match an indexer can offer without
        // giving up free-text fallback for indexers that ignore the IDs.
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "t", value: "search"),
            URLQueryItem(name: "apikey", value: apiKey),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "cat", value: category),
        ]
        if let tmdbID { queryItems.append(URLQueryItem(name: "tmdbid", value: tmdbID)) }
        if let imdbID { queryItems.append(URLQueryItem(name: "imdbid", value: imdbID)) }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw MediaProviderError.networkError(underlying: JackettURLError.invalidBaseURL as NSError)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw MediaProviderError.networkError(underlying: error as NSError)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 401, 403: throw MediaProviderError.authRequired
            case 429: throw MediaProviderError.rateLimited
            default:
                throw MediaProviderError.networkError(
                    underlying: JackettURLError.httpStatus(http.statusCode) as NSError
                )
            }
        }

        let items = TorznabXMLParser.parse(data: data)
        return items.compactMap { item -> SourceCandidate? in
            let hash = infoHash(from: item)
            guard !hash.isEmpty || item.magnetURI != nil || item.link != nil else {
                return nil
            }
            let effectiveHash = hash.isEmpty ? fallbackIdentifier(for: item) : hash
            let torrentURL: URL? = {
                guard item.magnetURI == nil, let link = item.link else { return nil }
                return URL(string: link)
            }()
            return SourceCandidate(
                id: "jackett:\(effectiveHash)",
                infoHash: effectiveHash,
                magnetURI: item.magnetURI,
                torrentURL: torrentURL,
                title: item.title,
                quality: parseQuality(from: item.title),
                seeders: item.seeders ?? 0,
                leechers: item.leechers ?? 0,
                sizeBytes: item.sizeBytes,
                providerName: name
            )
        }
    }

    // MARK: - Helpers

    /// Produce the TMDb numeric ID as a string. Returns `nil` when the
    /// MediaID provider isn't TMDb (reserved for v1.5+ identity providers).
    private func idString(for mediaID: MediaID) -> String? {
        guard mediaID.provider == .tmdb else { return nil }
        return String(mediaID.id)
    }

    /// Torznab expects IMDb IDs without the `tt` prefix. Accepts both forms
    /// and returns the 7-or-more-digit numeric portion, or `nil` when the
    /// input isn't a recognisable IMDb ID.
    static func normaliseIMDbID(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.lowercased().hasPrefix("tt") {
            s = String(s.dropFirst(2))
        }
        return s.allSatisfy(\.isNumber) && !s.isEmpty ? s : nil
    }

    /// Extracts the 40-char hex info hash from either the explicit `infohash`
    /// torznab attr or by parsing the magnet URI's `xt=urn:btih:` parameter.
    private func infoHash(from item: TorznabItem) -> String {
        if let explicit = item.infoHash, !explicit.isEmpty {
            return explicit.lowercased()
        }
        if let magnet = item.magnetURI, let hash = Self.parseBTIH(from: magnet) {
            return hash.lowercased()
        }
        return ""
    }

    /// Stable identifier when Jackett returned a torrent file URL without an
    /// info hash — GUID falls back to the link string hash.
    private func fallbackIdentifier(for item: TorznabItem) -> String {
        if let guid = item.guid, !guid.isEmpty { return guid }
        if let link = item.link, !link.isEmpty { return link }
        return item.title
    }

    private static func parseBTIH(from magnet: String) -> String? {
        guard let components = URLComponents(string: magnet) else { return nil }
        for qi in components.queryItems ?? [] where qi.name == "xt" {
            if let value = qi.value, value.lowercased().hasPrefix("urn:btih:") {
                return String(value.dropFirst("urn:btih:".count))
            }
        }
        return nil
    }

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

// MARK: - Local errors

enum JackettURLError: Error {
    case invalidBaseURL
    case httpStatus(Int)
}

// MARK: - Torznab parser

/// Minimal Torznab RSS parser. Extracts the fields ButterBar ranks on —
/// title, link/magnet, seeders/leechers, size, info hash — and ignores
/// everything else. Implemented with the stock `XMLParser` (no third-party
/// dependency).
struct TorznabItem: Equatable {
    var title: String = ""
    var link: String?
    var guid: String?
    var magnetURI: String?
    var seeders: Int?
    var leechers: Int?
    var sizeBytes: Int64?
    var infoHash: String?
}

enum TorznabXMLParser {
    static func parse(data: Data) -> [TorznabItem] {
        let delegate = TorznabParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.parse()
        return delegate.items
    }
}

private final class TorznabParserDelegate: NSObject, XMLParserDelegate {
    var items: [TorznabItem] = []
    private var currentItem: TorznabItem?
    private var currentElement: String?
    private var currentText: String = ""

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attrs: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        if elementName == "item" {
            currentItem = TorznabItem()
            return
        }

        guard currentItem != nil else { return }

        // Torznab extended attributes ride on <torznab:attr name="..." value="..."/>
        // (and occasionally <newznab:attr> — same shape). Namespaces are stripped
        // because shouldProcessNamespaces is off, so both arrive as "attr".
        if elementName == "torznab:attr" || elementName == "newznab:attr" || elementName == "attr" {
            guard let name = attrs["name"]?.lowercased(), let value = attrs["value"] else { return }
            applyAttr(name: name, value: value)
            return
        }

        // <enclosure url="..." length="..."/> — preferred torrent/magnet URL.
        if elementName == "enclosure" {
            if let url = attrs["url"], currentItem?.magnetURI == nil, currentItem?.link == nil {
                if url.lowercased().hasPrefix("magnet:") {
                    currentItem?.magnetURI = url
                } else {
                    currentItem?.link = url
                }
            }
            if currentItem?.sizeBytes == nil, let len = attrs["length"], let size = Int64(len) {
                currentItem?.sizeBytes = size
            }
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) {
            currentText += s
        }
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        defer { currentElement = nil; currentText = "" }
        guard var item = currentItem else { return }
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "item":
            items.append(item)
            currentItem = nil
            return
        case "title":
            if item.title.isEmpty { item.title = trimmed }
        case "link":
            if item.link == nil, !trimmed.isEmpty {
                if trimmed.lowercased().hasPrefix("magnet:") {
                    item.magnetURI = item.magnetURI ?? trimmed
                } else {
                    item.link = trimmed
                }
            }
        case "guid":
            if item.guid == nil, !trimmed.isEmpty { item.guid = trimmed }
        case "size":
            if item.sizeBytes == nil, let s = Int64(trimmed) { item.sizeBytes = s }
        default:
            break
        }

        currentItem = item
    }

    private func applyAttr(name: String, value: String) {
        guard var item = currentItem else { return }
        switch name {
        case "seeders":
            item.seeders = Int(value) ?? item.seeders
        case "peers", "leechers":
            // Torznab exposes peers (total) on some indexers and leechers on
            // others. Treat both as the leecher count — SourceCandidate needs
            // leechers, not the combined figure.
            item.leechers = Int(value) ?? item.leechers
        case "size":
            item.sizeBytes = Int64(value) ?? item.sizeBytes
        case "infohash":
            item.infoHash = value
        case "magneturl":
            if item.magnetURI == nil { item.magnetURI = value }
        case "downloadvolumefactor", "uploadvolumefactor", "category":
            break
        default:
            break
        }
        currentItem = item
    }
}
