import Foundation
import EngineInterface

/// Projection of an in-progress or re-watching file for the library's
/// "Continue watching" row (#35). Stable `Identifiable` id derived from
/// `(torrentID, fileIndex)` so SwiftUI diffing is consistent across
/// `playbackHistoryChanged` updates.
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

    var id: String {
        "\(torrent.torrentID as String)#\(fileIndex)"
    }

    /// 0.0 ... 1.0 fraction. Returns 0 when totalBytes is non-positive.
    var progressFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(progressBytes) / Double(totalBytes)
    }

    static func == (lhs: ContinueWatchingItem, rhs: ContinueWatchingItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.progressBytes == rhs.progressBytes &&
        lhs.lastPlayedAtMillis == rhs.lastPlayedAtMillis &&
        lhs.isReWatching == rhs.isReWatching
    }
}
