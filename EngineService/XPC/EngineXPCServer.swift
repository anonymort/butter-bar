import Foundation
import EngineInterface

/// Engine-side XPC server. Conforms to `EngineXPC` and is exported on every
/// incoming connection. Delegates to `FakeEngineBackend` which holds all in-memory
/// state and drives synthetic event emission.
@objc final class EngineXPCServer: NSObject, EngineXPC {

    private let backend = FakeEngineBackend()

    // MARK: - Torrent lifecycle

    func addMagnet(_ magnet: String,
                   reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void) {
        let dto = backend.addMagnet(magnet)
        reply(dto, nil)
    }

    func addTorrentFile(_ bookmarkData: NSData,
                        reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void) {
        let dto = backend.addTorrentFile(bookmarkData)
        reply(dto, nil)
    }

    /// Returns the in-memory list of all added torrents.
    func listTorrents(_ reply: @escaping ([TorrentSummaryDTO]) -> Void) {
        reply(backend.listTorrents())
    }

    func removeTorrent(_ torrentID: NSString,
                       deleteData: Bool,
                       reply: @escaping (NSError?) -> Void) {
        backend.removeTorrent(torrentID as String)
        reply(nil)
    }

    // MARK: - File selection

    func listFiles(_ torrentID: NSString,
                   reply: @escaping ([TorrentFileDTO], NSError?) -> Void) {
        if let fileDTOs = backend.listFiles(for: torrentID as String) {
            reply(fileDTOs, nil)
        } else {
            reply([], notFoundError("torrent \(torrentID)"))
        }
    }

    func setWantedFiles(_ torrentID: NSString,
                        fileIndexes: [NSNumber],
                        reply: @escaping (NSError?) -> Void) {
        // No-op: fake backend downloads everything.
        reply(nil)
    }

    // MARK: - Stream lifecycle

    func openStream(_ torrentID: NSString,
                    fileIndex: NSNumber,
                    reply: @escaping (StreamDescriptorDTO?, NSError?) -> Void) {
        if let descriptor = backend.openStream(torrentID: torrentID as String,
                                               fileIndex: fileIndex.intValue) {
            reply(descriptor, nil)
        } else {
            reply(nil, notFoundError("torrent \(torrentID)"))
        }
    }

    func closeStream(_ streamID: NSString,
                     reply: @escaping () -> Void) {
        backend.closeStream(streamID as String)
        reply()
    }

    // MARK: - Event subscription

    /// Retains the client proxy weakly via the backend. Starts the 2-second progress timer.
    func subscribe(_ client: EngineEvents,
                   reply: @escaping (NSError?) -> Void) {
        if let proxy = client as? EngineEvents & NSObjectProtocol {
            backend.subscribe(client: proxy)
        }
        reply(nil)
    }

    // MARK: - Private

    private func notFoundError(_ what: String) -> NSError {
        NSError(
            domain: EngineErrorDomain,
            code: EngineErrorCode.torrentNotFound.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "\(what) not found"]
        )
    }
}
