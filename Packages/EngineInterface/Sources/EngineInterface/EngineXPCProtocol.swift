import Foundation

/// The XPC protocol exported by the engine service.
/// All parameters and reply arguments are @objc-safe types.
/// Request methods take raw NSString/NSNumber parameters (no schemaVersion — per A1).
@objc public protocol EngineXPC {

    // MARK: Torrent lifecycle

    func addMagnet(_ magnet: String,
                   reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void)

    func addTorrentFile(_ bookmarkData: NSData,
                        reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void)

    func listTorrents(_ reply: @escaping ([TorrentSummaryDTO]) -> Void)

    func removeTorrent(_ torrentID: NSString,
                       deleteData: Bool,
                       reply: @escaping (NSError?) -> Void)

    // MARK: File selection

    func listFiles(_ torrentID: NSString,
                   reply: @escaping ([TorrentFileDTO], NSError?) -> Void)

    func setWantedFiles(_ torrentID: NSString,
                        fileIndexes: [NSNumber],
                        reply: @escaping (NSError?) -> Void)

    // MARK: Stream lifecycle

    func openStream(_ torrentID: NSString,
                    fileIndex: NSNumber,
                    reply: @escaping (StreamDescriptorDTO?, NSError?) -> Void)

    func closeStream(_ streamID: NSString,
                     reply: @escaping () -> Void)

    // MARK: Event subscription

    func subscribe(_ client: EngineEvents,
                   reply: @escaping (NSError?) -> Void)
}
