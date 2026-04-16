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

    // MARK: Watch state (A26 — Epic #5 Phase 1 foundation)

    /// Returns every row from `playback_history`. Empty when the table is empty.
    /// Used by the library to derive `WatchStatus` for every known file.
    func listPlaybackHistory(_ reply: @escaping ([PlaybackHistoryDTO]) -> Void)

    /// Manually mark a file as watched (`true`) or unwatched (`false`).
    /// See spec 05 § Update rules and `docs/design/watch-state-foundation.md`
    /// § Engine write rules.
    /// - Mark-watched: `(completed=1, completed_at=now, resume_byte_offset=0)`.
    /// - Mark-unwatched: `(completed=0, completed_at=NULL, resume_byte_offset=0)`;
    ///   `last_played_at` preserved.
    /// Inserts the row when absent.
    func setWatchedState(_ torrentID: NSString,
                         fileIndex: NSNumber,
                         watched: Bool,
                         reply: @escaping (NSError?) -> Void)

    // MARK: Favourites (#36, T-STORE-FAVOURITES)

    /// Returns every row from `favourites`. Empty when the table is empty.
    func listFavourites(_ reply: @escaping ([FavouriteDTO]) -> Void)

    /// Set or clear the favourite flag for `(torrentID, fileIndex)`.
    /// `isFavourite=true` upserts a row with `favourited_at = now`;
    /// `isFavourite=false` deletes the row. Both fire exactly one
    /// `favouritesChanged` event.
    func setFavourite(_ torrentID: NSString,
                      fileIndex: NSNumber,
                      isFavourite: Bool,
                      reply: @escaping (NSError?) -> Void)

    // MARK: Event subscription

    func subscribe(_ client: EngineEvents,
                   reply: @escaping (NSError?) -> Void)
}
