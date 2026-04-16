import Foundation
import EngineInterface

/// Engine-side XPC server. Conforms to `EngineXPC` and is exported on every
/// incoming connection. Delegates to the shared `EngineXPCBackend` instance,
/// which is either `RealEngineBackend` (default) or `FakeEngineBackend`
/// (when `--fake-backend` is passed at launch).
@objc final class EngineXPCServer: NSObject, EngineXPC {

    private let backend: any EngineXPCBackend

    init(backend: any EngineXPCBackend) {
        self.backend = backend
    }

    // MARK: - Torrent lifecycle

    func addMagnet(_ magnet: String,
                   reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void) {
        do {
            let dto = try backend.addMagnet(magnet)
            reply(dto, nil)
        } catch {
            reply(nil, error as NSError)
        }
    }

    func addTorrentFile(_ bookmarkData: NSData,
                        reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void) {
        do {
            let dto = try backend.addTorrentFile(bookmarkData)
            reply(dto, nil)
        } catch {
            reply(nil, error as NSError)
        }
    }

    /// Returns the list of all known torrents.
    func listTorrents(_ reply: @escaping ([TorrentSummaryDTO]) -> Void) {
        reply(backend.listTorrents())
    }

    func removeTorrent(_ torrentID: NSString,
                       deleteData: Bool,
                       reply: @escaping (NSError?) -> Void) {
        backend.removeTorrent(torrentID as String, deleteData: deleteData)
        reply(nil)
    }

    // MARK: - File selection

    func listFiles(_ torrentID: NSString,
                   reply: @escaping ([TorrentFileDTO], NSError?) -> Void) {
        do {
            let fileDTOs = try backend.listFiles(for: torrentID as String)
            reply(fileDTOs, nil)
        } catch {
            reply([], error as NSError)
        }
    }

    func setWantedFiles(_ torrentID: NSString,
                        fileIndexes: [NSNumber],
                        reply: @escaping (NSError?) -> Void) {
        do {
            try backend.setWantedFiles(torrentID: torrentID as String,
                                       fileIndexes: fileIndexes.map { $0.intValue })
            reply(nil)
        } catch {
            reply(error as NSError)
        }
    }

    // MARK: - Stream lifecycle

    func openStream(_ torrentID: NSString,
                    fileIndex: NSNumber,
                    reply: @escaping (StreamDescriptorDTO?, NSError?) -> Void) {
        do {
            let descriptor = try backend.openStream(torrentID: torrentID as String,
                                                    fileIndex: fileIndex.intValue)
            reply(descriptor, nil)
        } catch {
            reply(nil, error as NSError)
        }
    }

    func closeStream(_ streamID: NSString,
                     reply: @escaping () -> Void) {
        backend.closeStream(streamID as String)
        reply()
    }

    // MARK: - Event subscription

    func subscribe(_ client: EngineEvents,
                   reply: @escaping (NSError?) -> Void) {
        if let proxy = client as? EngineEvents & NSObjectProtocol {
            backend.subscribe(client: proxy)
        }
        reply(nil)
    }
}
