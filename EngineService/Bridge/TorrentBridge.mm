// Silence Boost/libtorrent deprecation warnings that originate in system headers.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#import "TorrentBridge.h"

#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/alert.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/file_storage.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/hex.hpp>
#include <libtorrent/create_torrent.hpp>
#include <libtorrent/bencode.hpp>

#include <unordered_map>
#include <string>
#include <vector>
#include <memory>
#include <fstream>

#pragma clang diagnostic pop

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

NSErrorDomain const TorrentBridgeErrorDomain = @"com.butterbar.engine";

static NSInteger const kPollIntervalMs = 250; // alert poll cadence

// ---------------------------------------------------------------------------
// Internal C++ state wrapped in a plain struct to avoid ObjC ARC / C++ mix issues
// ---------------------------------------------------------------------------

struct BridgeState {
    lt::session session;
    std::unordered_map<std::string, lt::torrent_handle> handles; // UUID → handle

    explicit BridgeState(lt::settings_pack p) : session(std::move(p)) {}
};

// ---------------------------------------------------------------------------
// @implementation TorrentBridge
// ---------------------------------------------------------------------------

@implementation TorrentBridge {
    BridgeState *_state;          // heap-allocated C++ state; nil after shutdown
    dispatch_queue_t _queue;      // serial queue serialising all lt:: calls
    dispatch_source_t _pollTimer; // fires every kPollIntervalMs on _queue
    void (^_alertCallback)(NSDictionary *);
    BOOL _didShutdown;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    _queue = dispatch_queue_create("com.butterbar.engine.bridge", DISPATCH_QUEUE_SERIAL);
    _didShutdown = NO;

    // Build session settings optimised for streaming / deadline-driven download.
    lt::settings_pack p;
    p.set_int(lt::settings_pack::alert_mask,
              lt::alert_category::status     |
              lt::alert_category::error      |
              lt::alert_category::piece_progress |
              lt::alert_category::storage);
    p.set_bool(lt::settings_pack::enable_dht, true);
    p.set_bool(lt::settings_pack::enable_lsd, true);
    p.set_int(lt::settings_pack::connections_limit, 200);
    // Disable sequential download — we use deadlines instead.
    p.set_bool(lt::settings_pack::close_redundant_connections, true);

    _state = new BridgeState(std::move(p));

    [self _startAlertPolling];
    return self;
}

- (void)dealloc {
    [self shutdown];
}

// MARK: - Lifecycle

- (void)shutdown {
    dispatch_sync(_queue, ^{
        if (_didShutdown) return;
        _didShutdown = YES;

        if (_pollTimer) {
            dispatch_source_cancel(_pollTimer);
            _pollTimer = nil;
        }

        if (_state) {
            // Ask all torrents to save resume data and pause.
            _state->session.pause();
            delete _state;
            _state = nil;
        }
    });
}

// MARK: - Torrent management

- (nullable NSString *)addMagnet:(NSString *)magnet error:(NSError **)error {
    __block NSString *torrentID = nil;
    __block NSError *addError = nil;

    dispatch_sync(_queue, ^{
        if (![self _assertAliveWithError:&addError]) return;

        lt::error_code ec;
        lt::add_torrent_params params = lt::parse_magnet_uri(
            std::string(magnet.UTF8String), ec);

        if (ec) {
            addError = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                          code:TorrentBridgeErrorInvalidMagnet
                                      userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithUTF8String:ec.message().c_str()]
            }];
            return;
        }

        // Use a UUID as the stable torrentID.
        NSString *uuid = [[NSUUID UUID] UUIDString];
        std::string key = uuid.UTF8String;

        // Save to a temp directory by default; callers can change save_path
        // by removing and re-adding. This keeps the API surface small.
        params.save_path = [NSTemporaryDirectory() UTF8String];

        lt::error_code addEc;
        lt::torrent_handle handle = _state->session.add_torrent(std::move(params), addEc);
        if (addEc || !handle.is_valid()) {
            addError = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                          code:TorrentBridgeErrorInvalidMagnet
                                      userInfo:@{
                NSLocalizedDescriptionKey: addEc.message().empty()
                    ? @"Failed to add magnet torrent"
                    : [NSString stringWithUTF8String:addEc.message().c_str()]
            }];
            return;
        }

        _state->handles[key] = handle;
        torrentID = uuid;
    });

    if (error) *error = addError;
    return torrentID;
}

- (nullable NSString *)addTorrentFileAtPath:(NSString *)path error:(NSError **)error {
    __block NSString *torrentID = nil;
    __block NSError *addError = nil;

    dispatch_sync(_queue, ^{
        if (![self _assertAliveWithError:&addError]) return;

        lt::error_code ec;
        auto ti = std::make_shared<lt::torrent_info>(std::string(path.UTF8String), ec);
        if (ec) {
            addError = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                          code:TorrentBridgeErrorFileNotFound
                                      userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithUTF8String:ec.message().c_str()]
            }];
            return;
        }

        NSString *uuid = [[NSUUID UUID] UUIDString];
        std::string key = uuid.UTF8String;

        lt::add_torrent_params params;
        params.ti = ti;
        params.save_path = [NSTemporaryDirectory() UTF8String];

        lt::error_code addEc;
        lt::torrent_handle handle = _state->session.add_torrent(std::move(params), addEc);
        if (addEc || !handle.is_valid()) {
            addError = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                          code:TorrentBridgeErrorFileNotFound
                                      userInfo:@{
                NSLocalizedDescriptionKey: addEc.message().empty()
                    ? @"Failed to add torrent file"
                    : [NSString stringWithUTF8String:addEc.message().c_str()]
            }];
            return;
        }

        _state->handles[key] = handle;
        torrentID = uuid;
    });

    if (error) *error = addError;
    return torrentID;
}

- (void)removeTorrent:(NSString *)torrentID deleteData:(BOOL)deleteData {
    dispatch_async(_queue, ^{
        if (self->_didShutdown || !self->_state) return;
        auto it = self->_state->handles.find(std::string(torrentID.UTF8String));
        if (it == self->_state->handles.end()) return;

        lt::remove_flags_t flags = {};
        if (deleteData) flags |= lt::session::delete_files;
        self->_state->session.remove_torrent(it->second, flags);
        self->_state->handles.erase(it);
    });
}

// MARK: - File info

- (nullable NSArray<NSDictionary *> *)listFiles:(NSString *)torrentID error:(NSError **)error {
    __block NSArray<NSDictionary *> *result = nil;
    __block NSError *opError = nil;

    dispatch_sync(_queue, ^{
        lt::torrent_handle h;
        if (![self _handle:torrentID into:&h error:&opError]) return;

        auto ti = h.torrent_file();
        if (!ti) {
            opError = [self _metadataNotReadyError];
            return;
        }

        const lt::file_storage &fs = ti->files();
        int n = fs.num_files();
        NSMutableArray *files = [NSMutableArray arrayWithCapacity:n];
        for (int i = 0; i < n; ++i) {
            lt::file_index_t idx(i);
            std::string fp = fs.file_path(idx);
            int64_t sz = fs.file_size(idx);
            [files addObject:@{
                @"path":  [NSString stringWithUTF8String:fp.c_str()],
                @"size":  @((int64_t)sz),
                @"index": @(i),
            }];
        }
        result = [files copy];
    });

    if (error) *error = opError;
    return result;
}

- (BOOL)setFilePriority:(NSString *)torrentID
             fileIndex:(int)fileIndex
              priority:(int)priority
                 error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *opError = nil;

    dispatch_sync(_queue, ^{
        lt::torrent_handle h;
        if (![self _handle:torrentID into:&h error:&opError]) return;

        auto ti = h.torrent_file();
        if (!ti) { opError = [self _metadataNotReadyError]; return; }
        if (fileIndex < 0 || fileIndex >= ti->files().num_files()) {
            opError = [self _fileNotFoundError:fileIndex];
            return;
        }
        h.file_priority(lt::file_index_t(fileIndex),
                        lt::download_priority_t(static_cast<std::uint8_t>(priority)));
        ok = YES;
    });

    if (error) *error = opError;
    return ok;
}

// MARK: - Piece state

- (nullable NSArray<NSNumber *> *)havePieces:(NSString *)torrentID error:(NSError **)error {
    __block NSArray<NSNumber *> *result = nil;
    __block NSError *opError = nil;

    dispatch_sync(_queue, ^{
        lt::torrent_handle h;
        if (![self _handle:torrentID into:&h error:&opError]) return;

        lt::torrent_status st = h.status(lt::torrent_handle::query_pieces);
        NSMutableArray *pieces = [NSMutableArray array];
        if (st.pieces.size() > 0) {
            for (int i = 0; i < (int)st.pieces.size(); ++i) {
                if (st.pieces.get_bit(lt::piece_index_t(i))) {
                    [pieces addObject:@(i)];
                }
            }
        }
        result = [pieces copy];
    });

    if (error) *error = opError;
    return result;
}

- (BOOL)setPieceDeadline:(NSString *)torrentID
                  piece:(int)piece
             deadlineMs:(int)deadlineMs
                  error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *opError = nil;

    dispatch_sync(_queue, ^{
        lt::torrent_handle h;
        if (![self _handle:torrentID into:&h error:&opError]) return;
        h.set_piece_deadline(lt::piece_index_t(piece), deadlineMs);
        ok = YES;
    });

    if (error) *error = opError;
    return ok;
}

- (BOOL)clearPieceDeadlines:(NSString *)torrentID
               exceptPieces:(NSArray<NSNumber *> *)exceptPieces
                      error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *opError = nil;

    dispatch_sync(_queue, ^{
        lt::torrent_handle h;
        if (![self _handle:torrentID into:&h error:&opError]) return;

        auto ti = h.torrent_file();
        if (!ti) { opError = [self _metadataNotReadyError]; return; }

        // Build a fast lookup set for the exception list.
        std::unordered_map<int, bool> except;
        for (NSNumber *p in exceptPieces) {
            except[[p intValue]] = true;
        }

        int numPieces = ti->num_pieces();
        for (int i = 0; i < numPieces; ++i) {
            if (except.find(i) == except.end()) {
                h.reset_piece_deadline(lt::piece_index_t(i));
            }
        }
        ok = YES;
    });

    if (error) *error = opError;
    return ok;
}

- (BOOL)forceRecheck:(NSString *)torrentID
               error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *opError = nil;

    dispatch_sync(_queue, ^{
        lt::torrent_handle h;
        if (![self _handle:torrentID into:&h error:&opError]) return;
        h.force_recheck();
        ok = YES;
    });

    if (error) *error = opError;
    return ok;
}

- (BOOL)addPiece:(NSString *)torrentID
           piece:(int)piece
            data:(NSData *)data
overwriteExisting:(BOOL)overwriteExisting
           error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *opError = nil;

    dispatch_sync(_queue, ^{
        lt::torrent_handle h;
        if (![self _handle:torrentID into:&h error:&opError]) return;

        auto ti = h.torrent_file();
        if (!ti) { opError = [self _metadataNotReadyError]; return; }

        if (piece < 0 || piece >= ti->num_pieces()) {
            opError = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                          code:TorrentBridgeErrorFileNotFound
                                      userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"Piece index %d out of range (num_pieces=%d)",
                    piece, ti->num_pieces()]
            }];
            return;
        }

        // Validate data length against the exact piece size. The last piece is
        // typically shorter than the rest; libtorrent's behaviour is undefined if
        // the buffer length is wrong (torrent_info::piece_size is authoritative).
        int expectedSize = ti->piece_size(lt::piece_index_t(piece));
        if ((int)data.length != expectedSize) {
            opError = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                          code:TorrentBridgeErrorInvalidArgument
                                      userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"addPiece data length %lu does not match piece size %d for piece %d",
                    (unsigned long)data.length, expectedSize, piece]
            }];
            return;
        }

        // libtorrent's std::vector overload is async (non-blocking). Copy the
        // bytes once here; libtorrent owns the vector from this point.
        std::vector<char> buf(
            static_cast<const char *>(data.bytes),
            static_cast<const char *>(data.bytes) + data.length
        );

        lt::add_piece_flags_t flags = {};
        if (overwriteExisting) flags |= lt::torrent_handle::overwrite_existing;

        h.add_piece(lt::piece_index_t(piece), std::move(buf), flags);
        ok = YES;
    });

    if (error) *error = opError;
    return ok;
}

// MARK: - Status

- (nullable NSDictionary *)statusSnapshot:(NSString *)torrentID error:(NSError **)error {
    __block NSDictionary *result = nil;
    __block NSError *opError = nil;

    dispatch_sync(_queue, ^{
        lt::torrent_handle h;
        if (![self _handle:torrentID into:&h error:&opError]) return;

        lt::torrent_status st = h.status();
        NSString *stateStr = [TorrentBridge _stateStringFrom:st.state];
        NSString *nameStr = torrentID;

        if (auto ti = h.torrent_file()) {
            const std::string name = ti->name();
            if (!name.empty()) {
                nameStr = [NSString stringWithUTF8String:name.c_str()];
            }
        }

        result = @{
            @"name":         nameStr,
            @"state":        stateStr,
            @"progress":     @((float)st.progress),
            @"downloadRate": @((int64_t)st.download_rate),
            @"uploadRate":   @((int64_t)st.upload_rate),
            @"peerCount":    @((int)st.num_peers),
            @"totalBytes":   @((int64_t)st.total_wanted),
        };
    });

    if (error) *error = opError;
    return result;
}

- (int64_t)pieceLength:(NSString *)torrentID {
    __block int64_t length = 0;
    dispatch_sync(_queue, ^{
        if (_didShutdown || !_state) return;
        auto it = _state->handles.find(std::string(torrentID.UTF8String));
        if (it == _state->handles.end()) return;
        auto ti = it->second.torrent_file();
        if (!ti) return;
        length = (int64_t)ti->piece_length();
    });
    return length;
}

- (BOOL)fileByteRange:(NSString *)torrentID
            fileIndex:(int)fileIndex
                start:(int64_t *)start
                  end:(int64_t *)end
                error:(NSError **)error {
    __block BOOL ok = NO;
    __block NSError *opError = nil;
    __block int64_t startOut = 0, endOut = 0;

    dispatch_sync(_queue, ^{
        lt::torrent_handle h;
        if (![self _handle:torrentID into:&h error:&opError]) return;

        auto ti = h.torrent_file();
        if (!ti) { opError = [self _metadataNotReadyError]; return; }

        const lt::file_storage &fs = ti->files();
        if (fileIndex < 0 || fileIndex >= fs.num_files()) {
            opError = [self _fileNotFoundError:fileIndex];
            return;
        }
        lt::file_index_t idx(fileIndex);
        // file_offset() is the byte offset of the file's first byte within
        // the torrent's contiguous piece space.
        startOut = (int64_t)fs.file_offset(idx);
        endOut   = startOut + (int64_t)fs.file_size(idx);
        ok = YES;
    });

    if (ok) {
        if (start) *start = startOut;
        if (end)   *end   = endOut;
    }
    if (error) *error = opError;
    return ok;
}

// MARK: - Byte reading

- (nullable NSData *)readBytes:(NSString *)torrentID
                     fileIndex:(int)fileIndex
                        offset:(int64_t)offset
                        length:(int64_t)length
                         error:(NSError **)error {
    __block NSData *result = nil;
    __block NSError *opError = nil;

    dispatch_sync(_queue, ^{
        lt::torrent_handle h;
        if (![self _handle:torrentID into:&h error:&opError]) return;

        auto ti = h.torrent_file();
        if (!ti) { opError = [self _metadataNotReadyError]; return; }

        const lt::file_storage &fs = ti->files();
        if (fileIndex < 0 || fileIndex >= fs.num_files()) {
            opError = [self _fileNotFoundError:fileIndex];
            return;
        }

        // Build the absolute path to the file on disk.
        lt::torrent_status st = h.status(lt::torrent_handle::query_save_path);
        lt::file_index_t idx(fileIndex);
        std::string filePath = fs.file_path(idx, st.save_path);

        // Open and read directly from the sparse file.
        // Bytes that haven't been downloaded yet will read as zeros on most
        // filesystems, but the gateway layer is responsible for checking
        // havePieces() before calling this.
        std::ifstream ifs(filePath, std::ios::binary);
        if (!ifs) {
            opError = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                          code:TorrentBridgeErrorReadError
                                      userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"Cannot open file for reading: %s", filePath.c_str()]
            }];
            return;
        }

        ifs.seekg(offset, std::ios::beg);
        if (!ifs) {
            opError = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                          code:TorrentBridgeErrorReadError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Seek failed" }];
            return;
        }

        NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)length];
        ifs.read(static_cast<char *>(data.mutableBytes), length);
        if (ifs.fail() && !ifs.eof()) {
            opError = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                          code:TorrentBridgeErrorReadError
                                      userInfo:@{ NSLocalizedDescriptionKey: @"Read failed" }];
            return;
        }
        // Trim to actual bytes read.
        std::streamsize bytesRead = ifs.gcount();
        data.length = (NSUInteger)bytesRead;
        result = [data copy];
    });

    if (error) *error = opError;
    return result;
}

// MARK: - Alert subscription

- (void)subscribeAlerts:(nullable void (^)(NSDictionary *))callback {
    dispatch_async(_queue, ^{
        self->_alertCallback = [callback copy];
    });
}

// MARK: - Private helpers

- (void)_startAlertPolling {
    _pollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_pollTimer,
                              dispatch_time(DISPATCH_TIME_NOW,
                                            kPollIntervalMs * NSEC_PER_MSEC),
                              kPollIntervalMs * NSEC_PER_MSEC,
                              5 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(self->_pollTimer, ^{
        [self _drainAlerts];
    });
    dispatch_resume(_pollTimer);
}

- (void)_drainAlerts {
    if (self->_didShutdown || !self->_state) return;

    std::vector<lt::alert *> alerts;
    self->_state->session.pop_alerts(&alerts);

    if (!self->_alertCallback || alerts.empty()) return;

    for (lt::alert *a : alerts) {
        NSString *typeStr   = [NSString stringWithUTF8String:a->what()];
        NSString *msgStr    = [NSString stringWithUTF8String:a->message().c_str()];
        NSMutableDictionary *dict = [@{
            @"type":    typeStr,
            @"message": msgStr,
        } mutableCopy];

        // Attach torrentID when the alert carries a handle.
        if (auto *ta = lt::alert_cast<lt::torrent_alert>(a)) {
            lt::torrent_handle th = ta->handle;
            if (th.is_valid()) {
                for (auto &kv : self->_state->handles) {
                    if (kv.second == th) {
                        dict[@"torrentID"] = [NSString stringWithUTF8String:kv.first.c_str()];
                        break;
                    }
                }
            }
        }

        // Attach pieceIndex for hash_failed_alert and piece_finished_alert so
        // probes and eviction logic can identify which piece was affected.
        if (auto *hfa = lt::alert_cast<lt::hash_failed_alert>(a)) {
            dict[@"pieceIndex"] = @((int)hfa->piece_index);
        } else if (auto *pfa = lt::alert_cast<lt::piece_finished_alert>(a)) {
            dict[@"pieceIndex"] = @((int)pfa->piece_index);
        }

        self->_alertCallback([dict copy]);
    }
}

/// Returns YES if the bridge is alive, otherwise sets an NSError and returns NO.
- (BOOL)_assertAliveWithError:(NSError **)error {
    if (_didShutdown || !_state) {
        if (error) {
            *error = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                         code:TorrentBridgeErrorTorrentNotFound
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"TorrentBridge has been shut down"
            }];
        }
        return NO;
    }
    return YES;
}

/// Looks up the handle for torrentID into *out. Returns YES on success.
- (BOOL)_handle:(NSString *)torrentID
           into:(lt::torrent_handle *)out
          error:(NSError **)error {
    if (![self _assertAliveWithError:error]) return NO;

    auto it = _state->handles.find(std::string(torrentID.UTF8String));
    if (it == _state->handles.end()) {
        if (error) {
            *error = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                         code:TorrentBridgeErrorTorrentNotFound
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"No torrent with ID %@", torrentID]
            }];
        }
        return NO;
    }
    *out = it->second;
    return YES;
}

- (NSError *)_metadataNotReadyError {
    return [NSError errorWithDomain:TorrentBridgeErrorDomain
                               code:TorrentBridgeErrorMetadataNotReady
                           userInfo:@{
        NSLocalizedDescriptionKey: @"Torrent metadata not yet available"
    }];
}

- (NSError *)_fileNotFoundError:(int)fileIndex {
    return [NSError errorWithDomain:TorrentBridgeErrorDomain
                               code:TorrentBridgeErrorFileNotFound
                           userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:
            @"File index %d out of range", fileIndex]
    }];
}

+ (NSString *)_stateStringFrom:(lt::torrent_status::state_t)state {
    switch (state) {
        case lt::torrent_status::checking_files:      return @"checkingFiles";
        case lt::torrent_status::downloading_metadata: return @"downloadingMetadata";
        case lt::torrent_status::downloading:          return @"downloading";
        case lt::torrent_status::finished:             return @"finished";
        case lt::torrent_status::seeding:              return @"seeding";
        case lt::torrent_status::checking_resume_data: return @"checkingResumeData";
        default:                                       return @"unknown";
    }
}

// MARK: - Test helpers

#if DEBUG

+ (nullable NSString *)createTestTorrent:(NSString *)sourceDir
                              outputPath:(NSString *)outputPath
                                   error:(NSError **)error {
    lt::file_storage fs;
    // add_files has no error_code overload; it silently skips unreadable entries.
    lt::add_files(fs, std::string(sourceDir.UTF8String));

    if (fs.num_files() == 0) {
        if (error) {
            *error = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                         code:TorrentBridgeErrorFileNotFound
                                     userInfo:@{
                NSLocalizedDescriptionKey: @"No files found in source directory"
            }];
        }
        return nil;
    }

    lt::create_torrent ct(fs);

    // Hash all pieces synchronously (fine for small test files).
    lt::error_code ec;
    lt::set_piece_hashes(ct, std::string(sourceDir.UTF8String), ec);
    if (ec) {
        if (error) {
            *error = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                         code:TorrentBridgeErrorReadError
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithUTF8String:ec.message().c_str()]
            }];
        }
        return nil;
    }

    std::vector<char> buf = ct.generate_buf();
    std::ofstream out(outputPath.UTF8String, std::ios::binary);
    if (!out) {
        if (error) {
            *error = [NSError errorWithDomain:TorrentBridgeErrorDomain
                                         code:TorrentBridgeErrorReadError
                                     userInfo:@{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:
                    @"Cannot write torrent file: %@", outputPath]
            }];
        }
        return nil;
    }
    out.write(buf.data(), static_cast<std::streamsize>(buf.size()));
    return outputPath;
}

#endif // DEBUG

@end
