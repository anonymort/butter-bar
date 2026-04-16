#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Error domain for all TorrentBridge errors.
FOUNDATION_EXPORT NSErrorDomain const TorrentBridgeErrorDomain;

/// Error codes in TorrentBridgeErrorDomain.
typedef NS_ERROR_ENUM(TorrentBridgeErrorDomain, TorrentBridgeError) {
    TorrentBridgeErrorTorrentNotFound  = 1,
    TorrentBridgeErrorInvalidMagnet    = 2,
    TorrentBridgeErrorFileNotFound     = 3,
    TorrentBridgeErrorReadError        = 4,
    TorrentBridgeErrorMetadataNotReady = 5,
    TorrentBridgeErrorInvalidArgument  = 6,
};

/// Narrow ObjC++ wrapper over a single lt::session.
///
/// All libtorrent session calls are serialised on an internal queue.
/// Foundation types only cross the boundary — no libtorrent types are exposed.
@interface TorrentBridge : NSObject

// MARK: - Lifecycle

/// Creates an lt::session with streaming-optimised settings.
- (instancetype)init;

/// Pauses the session, requests resume data, and tears down libtorrent.
/// Safe to call multiple times; subsequent calls are no-ops.
- (void)shutdown;

// MARK: - Torrent management

/// Adds a magnet link. Returns a stable torrentID (UUID) on success.
- (nullable NSString *)addMagnet:(NSString *)magnet error:(NSError **)error;

/// Adds a .torrent file from the local filesystem. Returns a stable torrentID on success.
- (nullable NSString *)addTorrentFileAtPath:(NSString *)path error:(NSError **)error;

/// Removes a torrent. Pass deleteData:YES to also delete downloaded files.
- (void)removeTorrent:(NSString *)torrentID deleteData:(BOOL)deleteData;

// MARK: - File info

/// Returns an array of file-info dicts for the given torrent.
/// Each dict: @{ @"path": NSString, @"size": NSNumber (int64), @"index": NSNumber (int) }
/// Returns nil if the torrent is unknown or metadata is not yet available.
- (nullable NSArray<NSDictionary *> *)listFiles:(NSString *)torrentID error:(NSError **)error;

/// Sets the download priority for a single file.
/// priority follows libtorrent's download_priority_t range (0 = ignore, 1–7 = active).
- (BOOL)setFilePriority:(NSString *)torrentID
             fileIndex:(int)fileIndex
              priority:(int)priority
                 error:(NSError **)error;

// MARK: - Piece state

/// Returns an array of piece indices (NSNumber int) that are fully downloaded.
- (nullable NSArray<NSNumber *> *)havePieces:(NSString *)torrentID error:(NSError **)error;

/// Sets a time-based download deadline on a single piece (milliseconds from now).
- (BOOL)setPieceDeadline:(NSString *)torrentID
                  piece:(int)piece
             deadlineMs:(int)deadlineMs
                  error:(NSError **)error;

/// Clears deadlines on all pieces except those in exceptPieces.
/// Uses reset_piece_deadline() for each piece not in the exception set.
- (BOOL)clearPieceDeadlines:(NSString *)torrentID
               exceptPieces:(NSArray<NSNumber *> *)exceptPieces
                      error:(NSError **)error;

/// Requests libtorrent to re-verify the entire torrent against what's on disk.
/// Equivalent to `lt::torrent_handle::force_recheck()`. This is a heavy operation:
/// libtorrent will disconnect all peers, read every existing file, and re-hash
/// every piece. Completion is asynchronous — observe via `torrent_checked_alert`
/// or by polling `statusSnapshot` for the `checkingFiles` state to clear.
///
/// Side effects (per libtorrent torrent_handle.hpp:664-672):
///   - Resume-data state is reset; libtorrent treats the torrent as having no
///     resume data after the call.
///   - All peers are disconnected before checking begins.
///   - The torrent stops announcing to the tracker during the check.
///   - The torrent is placed at the end of the session queue (last queue position).
///
/// Calling while the torrent is already in `checkingFiles` or `checkingResumeData`
/// state may restart the check; exact behaviour is libtorrent-internal.
///
/// Used as the cache-eviction fallback path (see `05-cache-policy.md` § Fallback).
/// Not intended for streaming-hot-path use.
- (BOOL)forceRecheck:(NSString *)torrentID
               error:(NSError **)error;

/// Writes `data` to the torrent's storage as piece `piece` and schedules a hash
/// check. If `overwriteExisting` is YES, libtorrent will overwrite any bytes
/// already on disk for that piece (mapped to `add_piece_flags_t::overwrite_existing`).
/// The hash check result is documented to arrive asynchronously via
/// `piece_finished_alert` (pass) or `hash_failed_alert` (fail).
///
/// **NOT used by cache eviction in libtorrent 2.0.12.** Probe run #3 (2026-04-16)
/// empirically disproved the addPiece/hash-fail hot path: neither alert fires
/// after `addPiece(zeros, overwrite_existing)` at any file priority. Eviction
/// uses `F_PUNCHHOLE` + `forceRecheck` instead (spec 05 rev 4, addendum A24).
/// This method is retained as a general libtorrent wrapper for future use.
///
/// `data` length must equal `piece_size(piece)` for the target piece — NOT
/// uniformly `pieceLength:`, because the last piece of a torrent is typically
/// shorter. The bridge validates this and returns `TorrentBridgeErrorInvalidArgument`
/// on mismatch.
///
/// Caller constraints:
///   - Calling while the torrent is in `checkingFiles` state is unsupported by
///     libtorrent (per torrent_handle.hpp:286-287); the caller (CacheManager) must
///     ensure this state is not active.
///   - With `overwriteExisting: YES` on a piece that is actively being downloaded
///     from peers, libtorrent docs (torrent_handle.hpp:266-270) note that in-flight
///     blocks may not be replaced. For the eviction use case this is not a concern
///     (we target fully-downloaded pieces), but direct callers should be aware.
- (BOOL)addPiece:(NSString *)torrentID
           piece:(int)piece
            data:(NSData *)data
overwriteExisting:(BOOL)overwriteExisting
           error:(NSError **)error;

// MARK: - Status

/// Returns a snapshot of the torrent's current status.
/// Dict keys: @"name" (NSString), @"state" (NSString), @"progress" (NSNumber float),
///            @"downloadRate" (NSNumber int64), @"uploadRate" (NSNumber int64),
///            @"peerCount" (NSNumber int), @"totalBytes" (NSNumber int64).
- (nullable NSDictionary *)statusSnapshot:(NSString *)torrentID error:(NSError **)error;

/// Returns the piece length in bytes, or 0 if the torrent is not found / metadata not ready.
- (int64_t)pieceLength:(NSString *)torrentID;

/// Fills *start and *end with the byte range [start, end) of fileIndex within the torrent.
/// Returns NO and sets error on failure.
- (BOOL)fileByteRange:(NSString *)torrentID
            fileIndex:(int)fileIndex
                start:(int64_t *)start
                  end:(int64_t *)end
                error:(NSError **)error;

// MARK: - Byte reading

/// Reads bytes from an already-downloaded region of a file via the sparse on-disk data.
/// Returns nil on error (e.g. piece not yet downloaded, I/O failure).
- (nullable NSData *)readBytes:(NSString *)torrentID
                     fileIndex:(int)fileIndex
                        offset:(int64_t)offset
                        length:(int64_t)length
                         error:(NSError **)error;

// MARK: - Alert subscription

/// Registers a callback that is invoked (on an internal serial queue) for every alert.
/// Alert dict: @{ @"type": NSString, @"torrentID": NSString (if applicable), @"message": NSString,
///                @"pieceIndex": NSNumber (int, only for hash_failed_alert and piece_finished_alert) }
/// Pass nil to clear the callback.
- (void)subscribeAlerts:(nullable void (^)(NSDictionary *alert))callback;

// MARK: - Test helpers

#if DEBUG
/// Creates a v1 .torrent from all files under sourceDir and writes it to outputPath.
/// Returns the outputPath on success. Used by the self-test only.
+ (nullable NSString *)createTestTorrent:(NSString *)sourceDir
                              outputPath:(NSString *)outputPath
                                   error:(NSError **)error;
#endif

@end

NS_ASSUME_NONNULL_END
