import Foundation

/// Quality tier of a torrent source. Higher raw values correspond to higher
/// quality so that `>` comparisons produce intuitive results.
public enum SourceQuality: Int, Comparable, Hashable, Sendable, Codable, CaseIterable {
    case cam      = 1
    case ts       = 2
    case dvdRip   = 3
    case webDL    = 4
    case bluRay   = 5
    case remux    = 6
    case unknown  = 0

    public static func < (lhs: SourceQuality, rhs: SourceQuality) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Ranking weight used by `SourceCandidate.rank`. Separate from `rawValue`
    /// so the ordering can be tuned without breaking `Comparable` or Codable.
    public var rank: Int {
        switch self {
        case .remux:   return 7
        case .bluRay:  return 6
        case .webDL:   return 5
        case .dvdRip:  return 4
        case .unknown: return 3
        case .ts:      return 2
        case .cam:     return 1
        }
    }
}

/// A single torrent result returned by a `MediaProvider` for a given title.
///
/// Either `magnetURI` or `torrentURL` must be non-nil for the source to be
/// actionable. Providers should prefer `magnetURI` where available.
public struct SourceCandidate: Equatable, Hashable, Sendable, Codable {
    /// Stable identifier composed from provider name + info hash,
    /// e.g. `"yts:abc123..."`.
    public let id: String

    /// 40-char hex SHA-1 or 64-char hex SHA-256 info hash.
    public let infoHash: String

    /// Preferred addition method. Nil when only a torrent file URL is available.
    public let magnetURI: String?

    /// Fallback when no magnet link is available.
    public let torrentURL: URL?

    /// Raw title as returned by the provider — not necessarily clean.
    public let title: String

    public let quality: SourceQuality
    public let seeders: Int
    public let leechers: Int

    /// `nil` when the provider does not report file size.
    public let sizeBytes: Int64?

    /// Name of the `MediaProvider` that returned this candidate.
    public let providerName: String

    /// Composite ranking score for pipeline sorting (descending).
    ///
    /// Formula: `quality.rank × 1_000_000 + min(seeders, 9999) × 100 + (sizeBytes != nil ? 1 : 0)`
    ///
    /// Quality dominates; within the same quality tier, seeder count breaks
    /// ties; size presence breaks the final tie.
    public var rank: Int {
        quality.rank * 1_000_000 + min(seeders, 9_999) * 100 + (sizeBytes != nil ? 1 : 0)
    }

    public init(
        id: String,
        infoHash: String,
        magnetURI: String?,
        torrentURL: URL?,
        title: String,
        quality: SourceQuality,
        seeders: Int,
        leechers: Int,
        sizeBytes: Int64?,
        providerName: String
    ) {
        self.id = id
        self.infoHash = infoHash
        self.magnetURI = magnetURI
        self.torrentURL = torrentURL
        self.title = title
        self.quality = quality
        self.seeders = seeders
        self.leechers = leechers
        self.sizeBytes = sizeBytes
        self.providerName = providerName
    }
}
