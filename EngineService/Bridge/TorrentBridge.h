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

// MARK: - Status

/// Returns a snapshot of the torrent's current status.
/// Dict keys: @"state" (NSString), @"progress" (NSNumber float),
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
/// Alert dict: @{ @"type": NSString, @"torrentID": NSString (if applicable), @"message": NSString }
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
