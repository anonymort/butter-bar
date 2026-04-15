// CacheManager: glue layer between the engine's in-memory state and GRDB.
//
// Owns two concerns:
//   1. Playback history — upserts resume offsets and completion flags.
//   2. Pinned files — persists the pinned set and maintains an in-memory
//      mirror so callers never pay a DB hit for hot-path pin checks.
//
// Threading: all public methods are synchronous and must be called from a
// single queue (or with external serialisation). The DatabaseQueue handles
// its own internal locking; the in-memory `_pinnedKeys` set is not
// thread-safe on its own.

import Foundation
import GRDB
import EngineStore

/// Lightweight key for a pinned file. Used as the element type of the
/// in-memory pinned set. Value-typed and Hashable so Set operations are O(1).
public struct PinnedKey: Hashable, Sendable {
    public let torrentId: String
    public let fileIndex: Int

    public init(torrentId: String, fileIndex: Int) {
        self.torrentId = torrentId
        self.fileIndex = fileIndex
    }
}

/// Read/write helpers for `playback_history` and `pinned_files`, backed by a
/// GRDB `DatabaseQueue` supplied at init.
///
/// On init the full pinned set is loaded into memory so `isPinned` is always
/// a pure Set lookup with no I/O.
public final class CacheManager {

    // MARK: - Init

    private let db: DatabaseQueue
    private var _pinnedKeys: Set<PinnedKey>

    /// Creates a `CacheManager` and immediately loads the pinned set from the
    /// database. Throws if the initial fetch fails (treat as fatal at startup).
    public init(db: DatabaseQueue) throws {
        self.db = db
        self._pinnedKeys = try db.read { conn in
            let rows = try PinnedFileRecord.fetchAll(conn)
            return Set(rows.map { PinnedKey(torrentId: $0.torrentId, fileIndex: $0.fileIndex) })
        }
    }

    // MARK: - Playback history

    /// Upserts a playback_history row.
    ///
    /// - If `resumeByteOffset >= 0.95 * fileSize`, the row is marked
    ///   `completed = true` and the offset is reset to 0 (per spec A6).
    /// - `lastPlayedAt` is always set to the current time (unix ms).
    public func recordPlayback(
        torrentId: String,
        fileIndex: Int,
        resumeByteOffset: Int64,
        fileSize: Int64
    ) throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let threshold = Int64(Double(fileSize) * 0.95)
        let isComplete = resumeByteOffset >= threshold
        let offset: Int64 = isComplete ? 0 : resumeByteOffset

        var record = PlaybackHistoryRecord(
            torrentId: torrentId,
            fileIndex: fileIndex,
            resumeByteOffset: offset,
            lastPlayedAt: now,
            totalWatchedSeconds: 0,
            completed: isComplete
        )

        try db.write { conn in
            // Upsert: if a row already exists, preserve totalWatchedSeconds.
            if let existing = try PlaybackHistoryRecord
                .filter(Column("torrent_id") == torrentId && Column("file_index") == fileIndex)
                .fetchOne(conn) {
                record.totalWatchedSeconds = existing.totalWatchedSeconds
            }
            try record.save(conn)
        }
    }

    /// Fetches a single playback_history row, or `nil` if none exists.
    public func fetchHistory(torrentId: String, fileIndex: Int) throws -> PlaybackHistoryRecord? {
        try db.read { conn in
            try PlaybackHistoryRecord
                .filter(Column("torrent_id") == torrentId && Column("file_index") == fileIndex)
                .fetchOne(conn)
        }
    }

    /// Fetches all playback_history rows ordered by `lastPlayedAt DESC`.
    public func fetchAllHistory() throws -> [PlaybackHistoryRecord] {
        try db.read { conn in
            try PlaybackHistoryRecord
                .order(Column("last_played_at").desc)
                .fetchAll(conn)
        }
    }

    // MARK: - Pinned files

    /// Inserts a pinned_files row and adds the key to the in-memory set.
    /// No-ops silently if the file is already pinned (GRDB save handles
    /// the primary-key conflict via replace).
    public func pin(torrentId: String, fileIndex: Int) throws {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let record = PinnedFileRecord(torrentId: torrentId, fileIndex: fileIndex, pinnedAt: now)
        try db.write { conn in
            try record.save(conn)
        }
        _pinnedKeys.insert(PinnedKey(torrentId: torrentId, fileIndex: fileIndex))
    }

    /// Deletes a pinned_files row and removes the key from the in-memory set.
    /// No-ops if the file was not pinned.
    public func unpin(torrentId: String, fileIndex: Int) throws {
        try db.write { conn in
            try PinnedFileRecord
                .filter(Column("torrent_id") == torrentId && Column("file_index") == fileIndex)
                .deleteAll(conn)
        }
        _pinnedKeys.remove(PinnedKey(torrentId: torrentId, fileIndex: fileIndex))
    }

    /// Returns `true` if the file is currently pinned. No DB hit.
    public func isPinned(torrentId: String, fileIndex: Int) -> Bool {
        _pinnedKeys.contains(PinnedKey(torrentId: torrentId, fileIndex: fileIndex))
    }

    /// Returns the full in-memory pinned set. No DB hit.
    public func allPinnedKeys() -> Set<PinnedKey> {
        _pinnedKeys
    }
}
