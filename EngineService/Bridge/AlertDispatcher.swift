import Foundation
import EngineInterface

/// Subscribes to TorrentBridge alerts and dispatches typed events to the XPC client proxy.
///
/// Thread safety: TorrentBridge delivers callbacks on its own internal serial queue.
/// XPC proxy calls are safe from any thread, so no additional synchronisation is needed here.
final class AlertDispatcher {

    private let bridge: TorrentBridge
    // Weak to avoid retaining the XPC proxy beyond the connection's lifetime.
    private weak var clientProxy: (EngineEvents & NSObjectProtocol)?

    init(bridge: TorrentBridge) {
        self.bridge = bridge
    }

    /// Registers the XPC client proxy that receives pushed events.
    func setClient(_ client: (EngineEvents & NSObjectProtocol)?) {
        clientProxy = client
    }

    /// Starts consuming alerts from the bridge. Call once after the bridge is initialised.
    func startListening() {
        bridge.subscribeAlerts { [weak self] dict in
            guard let self else { return }
            self.handleAlert(TorrentAlert.from(dict as NSDictionary))
        }
    }

    /// Clears the alert subscription.
    func stopListening() {
        bridge.subscribeAlerts(nil)
    }

    // MARK: - Private

    private func handleAlert(_ alert: TorrentAlert) {
        guard let proxy = clientProxy else { return }

        switch alert {
        case .stateChanged(let torrentID, _),
             .statsUpdated(let torrentID),
             .torrentFinished(let torrentID),
             .metadataReceived(let torrentID):
            emitTorrentUpdated(torrentID: torrentID, to: proxy)

        case .pieceFinished(let torrentID, _):
            emitTorrentUpdated(torrentID: torrentID, to: proxy)
            emitFileAvailabilityChanged(torrentID: torrentID, to: proxy)

        case .hashFailed(let torrentID, let pieceIndex):
            emitTorrentUpdated(torrentID: torrentID, to: proxy)
            if let pieceIndex {
                NSLog("[AlertDispatcher] hash failed for %@ piece %d", torrentID, pieceIndex)
            } else {
                NSLog("[AlertDispatcher] hash failed for %@ with no pieceIndex", torrentID)
            }

        case .error(let torrentID, let message):
            if let id = torrentID {
                emitTorrentUpdated(torrentID: id, to: proxy)
            }
            NSLog("[AlertDispatcher] torrent error: %@", message)

        case .unknown:
            // Unhandled alert types are intentionally ignored.
            break
        }
    }

    private func emitTorrentUpdated(torrentID: String, to proxy: EngineEvents) {
        guard let snapshot = try? bridge.statusSnapshot(torrentID) else {
            NSLog("[AlertDispatcher] statusSnapshot failed for %@", torrentID)
            return
        }

        let progress = (snapshot["progress"] as? NSNumber)?.floatValue ?? 0
        let name = (snapshot["name"] as? NSString) ?? (torrentID as NSString)
        let dto = TorrentSummaryDTO(
            torrentID: torrentID as NSString,
            name: name,
            totalBytes: (snapshot["totalBytes"] as? NSNumber)?.int64Value ?? 0,
            progressQ16: Int32(min(progress * 65536, 65536)),
            state: (snapshot["state"] as? NSString) ?? ("unknown" as NSString),
            peerCount: Int32((snapshot["peerCount"] as? NSNumber)?.intValue ?? 0),
            downRateBytesPerSec: (snapshot["downloadRate"] as? NSNumber)?.int64Value ?? 0,
            upRateBytesPerSec: (snapshot["uploadRate"] as? NSNumber)?.int64Value ?? 0,
            errorMessage: nil
        )
        proxy.torrentUpdated(dto)
    }

    private func emitFileAvailabilityChanged(torrentID: String, to proxy: EngineEvents) {
        let havePiecesArray: [NSNumber]
        do {
            havePiecesArray = try bridge.havePieces(torrentID)
        } catch {
            NSLog("[AlertDispatcher] havePieces failed for %@", torrentID)
            return
        }

        let pieceLength = bridge.pieceLength(torrentID)
        guard pieceLength > 0 else {
            NSLog("[AlertDispatcher] pieceLength unavailable for %@", torrentID)
            return
        }

        let havePieces = havePiecesArray.map { $0.intValue }

        let files: [NSDictionary]
        do {
            files = try bridge.listFiles(torrentID) as? [NSDictionary] ?? []
        } catch {
            NSLog("[AlertDispatcher] listFiles failed for %@", torrentID)
            return
        }

        for file in files {
            guard let fileIndex = (file["index"] as? NSNumber)?.int32Value else { continue }

            var fileStart: Int64 = 0
            var fileEnd:   Int64 = 0
            do {
                try bridge.fileByteRange(torrentID, fileIndex: fileIndex, start: &fileStart, end: &fileEnd)
            } catch {
                NSLog("[AlertDispatcher] fileByteRange failed for %@ file %d", torrentID, fileIndex)
                continue
            }

            let ranges = PieceByteMapping.availableRanges(
                havePieces: havePieces,
                pieceLength: pieceLength,
                fileStart: fileStart,
                fileEnd: fileEnd
            )

            let dto = FileAvailabilityDTO(
                torrentID: torrentID as NSString,
                fileIndex: fileIndex,
                availableRanges: ranges
            )
            proxy.fileAvailabilityChanged(dto)
        }
    }
}
