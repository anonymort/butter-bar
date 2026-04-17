import Foundation
import EngineInterface
import MetadataDomain

/// Projection of an in-progress or re-watching file for the library's
/// "Continue watching" row (#35, enriched by #17). Stable `Identifiable` id
/// derived from `(torrentID, fileIndex)` so SwiftUI diffing is consistent
/// across `playbackHistoryChanged` updates.
///
/// Two layers of identity:
/// - **Source-of-truth** fields (`torrent`, `progressBytes`, `lastPlayedAtMillis`,
///   etc.) come straight from the engine. Required.
/// - **Match** fields (`media`, `posterPath`, `episodeDesignator`) are
///   populated by `LibraryMetadataResolver` (#17) when a TMDB match clears
///   the confidence threshold. All optional — unmatched files still render
///   with the raw torrent name as fallback (per design § D9).
struct ContinueWatchingItem: Identifiable, Equatable {
    let torrent: TorrentSummaryDTO
    let fileIndex: Int
    let progressBytes: Int64
    let totalBytes: Int64
    /// Unix milliseconds; drives sort order in the row.
    let lastPlayedAtMillis: Int64
    /// Distinguishes `.inProgress` (false) from `.reWatching` (true) so the
    /// row UI can show the right copy ("Continue" vs "Re-watching").
    let isReWatching: Bool

    // MARK: - #17 metadata (populated by `LibraryMetadataResolver`)

    /// Matched TMDB item, if the ranker cleared the confidence threshold.
    let media: MediaItem?
    /// TMDB poster path (e.g. `/abc123.jpg`); combine with `MetadataProvider.imageURL`.
    /// Mirrors the matched `media`; lifted out so the view doesn't need to
    /// switch over `MediaItem` to render the card.
    let posterPath: String?
    /// "S01E04" or similar; nil for movies and unmatched files.
    let episodeDesignator: String?

    init(torrent: TorrentSummaryDTO,
         fileIndex: Int,
         progressBytes: Int64,
         totalBytes: Int64,
         lastPlayedAtMillis: Int64,
         isReWatching: Bool,
         media: MediaItem? = nil,
         posterPath: String? = nil,
         episodeDesignator: String? = nil) {
        self.torrent = torrent
        self.fileIndex = fileIndex
        self.progressBytes = progressBytes
        self.totalBytes = totalBytes
        self.lastPlayedAtMillis = lastPlayedAtMillis
        self.isReWatching = isReWatching
        self.media = media
        self.posterPath = posterPath
        self.episodeDesignator = episodeDesignator
    }

    var id: String {
        "\(torrent.torrentID as String)#\(fileIndex)"
    }

    /// 0.0 ... 1.0 fraction. Returns 0 when totalBytes is non-positive.
    var progressFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(progressBytes) / Double(totalBytes)
    }

    /// Title to display on the card. Prefers the matched TMDB title; falls
    /// back to the raw torrent name. Per `06-brand.md § Voice` — quiet
    /// fallback, never apologetic. Used directly by the card view; tests
    /// assert this projection rather than re-deriving the precedence rule.
    var displayTitle: String {
        if let media {
            switch media {
            case .movie(let m): return m.title
            case .show(let s): return s.name
            }
        }
        return torrent.name as String
    }

    static func == (lhs: ContinueWatchingItem, rhs: ContinueWatchingItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.progressBytes == rhs.progressBytes &&
        lhs.lastPlayedAtMillis == rhs.lastPlayedAtMillis &&
        lhs.isReWatching == rhs.isReWatching &&
        lhs.media == rhs.media &&
        lhs.posterPath == rhs.posterPath &&
        lhs.episodeDesignator == rhs.episodeDesignator
    }
}
