import Foundation
import PlannerCore

/// Adapts TorrentBridge to the PlannerCore TorrentSessionView protocol.
/// Each instance is scoped to a specific torrent + file combination.
///
/// `pieceLength` and `fileByteRange` are cached on init — both are stable
/// once metadata is available, so there is no need to re-query per planner tick.
final class RealTorrentSession: TorrentSessionView {
    private let bridge: TorrentBridge
    private let torrentID: String
    private let fileIndex: Int

    // Cached at init; stable for the torrent's lifetime.
    let pieceLength: Int64
    let fileByteRange: ByteRange

    /// Throws `TorrentBridgeErrorMetadataNotReady` (code 5) if metadata is unavailable.
    init(bridge: TorrentBridge, torrentID: String, fileIndex: Int) throws {
        self.bridge = bridge
        self.torrentID = torrentID
        self.fileIndex = fileIndex

        let pl = bridge.pieceLength(torrentID)
        guard pl > 0 else {
            throw NSError(
                domain: TorrentBridgeErrorDomain,
                code: Int(TorrentBridgeError.metadataNotReady.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "Torrent metadata not ready"]
            )
        }
        self.pieceLength = pl

        var start: Int64 = 0
        var end: Int64 = 0
        try bridge.fileByteRange(torrentID, fileIndex: Int32(fileIndex), start: &start, end: &end)
        self.fileByteRange = ByteRange(start: start, end: end)
    }

    func havePieces() -> BitSet {
        guard let pieces = try? bridge.havePieces(torrentID) else { return [] }
        return Set(pieces.map { $0.intValue })
    }

    func downloadRateBytesPerSec() -> Int64 {
        guard let snapshot = try? bridge.statusSnapshot(torrentID),
              let rate = snapshot["downloadRate"] as? NSNumber else { return 0 }
        return rate.int64Value
    }

    func peerCount() -> Int {
        guard let snapshot = try? bridge.statusSnapshot(torrentID),
              let count = snapshot["peerCount"] as? NSNumber else { return 0 }
        return count.intValue
    }
}
