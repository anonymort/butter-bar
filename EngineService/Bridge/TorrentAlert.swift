import Foundation

/// Typed representation of libtorrent alerts relevant to the engine.
enum TorrentAlert {
    /// Torrent state changed (downloading, seeding, etc.)
    case stateChanged(torrentID: String, newState: String)
    /// Torrent stats updated (periodic from libtorrent)
    case statsUpdated(torrentID: String)
    /// A piece finished downloading
    case pieceFinished(torrentID: String, pieceIndex: Int?)
    /// A piece failed hash validation
    case hashFailed(torrentID: String, pieceIndex: Int?)
    /// Torrent metadata received (magnet resolved)
    case metadataReceived(torrentID: String)
    /// Torrent finished downloading all pieces
    case torrentFinished(torrentID: String)
    /// An error occurred
    case error(torrentID: String?, message: String)
    /// Unknown/unhandled alert type
    case unknown(type: String, message: String)

    /// Parse from the NSDictionary delivered by TorrentBridge.subscribeAlerts.
    static func from(_ dict: NSDictionary) -> TorrentAlert {
        let type = dict["type"] as? String ?? "unknown"
        let torrentID = dict["torrentID"] as? String
        let message = dict["message"] as? String ?? ""

        switch type {
        case "state_changed_alert":
            return .stateChanged(torrentID: torrentID ?? "", newState: message)
        case "stats_alert", "status_notification_alert":
            return .statsUpdated(torrentID: torrentID ?? "")
        case "piece_finished_alert":
            return .pieceFinished(torrentID: torrentID ?? "", pieceIndex: pieceIndex(from: dict))
        case "hash_failed_alert":
            return .hashFailed(torrentID: torrentID ?? "", pieceIndex: pieceIndex(from: dict))
        case "metadata_received_alert":
            return .metadataReceived(torrentID: torrentID ?? "")
        case "torrent_finished_alert":
            return .torrentFinished(torrentID: torrentID ?? "")
        case _ where type.contains("error"):
            return .error(torrentID: torrentID, message: message)
        default:
            return .unknown(type: type, message: message)
        }
    }

    private static func pieceIndex(from dict: NSDictionary) -> Int? {
        if let number = dict["pieceIndex"] as? NSNumber {
            return number.intValue
        }
        return dict["pieceIndex"] as? Int
    }
}
