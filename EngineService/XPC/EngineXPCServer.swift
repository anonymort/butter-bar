import Foundation
import EngineInterface

/// Engine-side XPC server. Conforms to `EngineXPC` and is exported on every
/// incoming connection. All unimplemented methods return `.notImplemented`.
/// `listTorrents` returns an empty array per addendum A2.
/// `subscribe` retains the client proxy weakly; the engine survives client death.
@objc final class EngineXPCServer: NSObject, EngineXPC {

    // Weak so the engine does not keep the remote client alive.
    // Re-validated on every emission attempt.
    private weak var clientProxy: (EngineEvents & NSObjectProtocol)?

    // MARK: - Torrent lifecycle

    func addMagnet(_ magnet: String,
                   reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void) {
        reply(nil, notImplementedError("addMagnet"))
    }

    func addTorrentFile(_ bookmarkData: NSData,
                        reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void) {
        reply(nil, notImplementedError("addTorrentFile"))
    }

    /// Per addendum A2: returns a valid empty array rather than an error,
    /// so the app can safely use this as the initial state before any torrents exist.
    func listTorrents(_ reply: @escaping ([TorrentSummaryDTO]) -> Void) {
        reply([])
    }

    func removeTorrent(_ torrentID: NSString,
                       deleteData: Bool,
                       reply: @escaping (NSError?) -> Void) {
        reply(notImplementedError("removeTorrent"))
    }

    // MARK: - File selection

    func listFiles(_ torrentID: NSString,
                   reply: @escaping ([TorrentFileDTO], NSError?) -> Void) {
        reply([], notImplementedError("listFiles"))
    }

    func setWantedFiles(_ torrentID: NSString,
                        fileIndexes: [NSNumber],
                        reply: @escaping (NSError?) -> Void) {
        reply(notImplementedError("setWantedFiles"))
    }

    // MARK: - Stream lifecycle

    func openStream(_ torrentID: NSString,
                    fileIndex: NSNumber,
                    reply: @escaping (StreamDescriptorDTO?, NSError?) -> Void) {
        reply(nil, notImplementedError("openStream"))
    }

    func closeStream(_ streamID: NSString,
                     reply: @escaping () -> Void) {
        reply()
    }

    // MARK: - Event subscription

    /// Retains the client proxy weakly and returns nil error (success).
    /// No events are emitted in the skeleton — the proxy is stored for future use.
    func subscribe(_ client: EngineEvents,
                   reply: @escaping (NSError?) -> Void) {
        // NSXPCConnection delivers the proxy as an NSObject subclass at runtime.
        clientProxy = client as? EngineEvents & NSObjectProtocol
        reply(nil)
    }

    // MARK: - Private

    private func notImplementedError(_ method: String) -> NSError {
        NSError(
            domain: EngineErrorDomain,
            code: EngineErrorCode.notImplemented.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "\(method) is not implemented"]
        )
    }
}
