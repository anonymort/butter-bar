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
    /// Behaviour matches spec 05 rev 5 § Update rules and addendum A26:
    /// - If `resumeByteOffset >= 0.95 * fileSize`, the row's `completed` flips
    ///   to `true`; the byte offset is reset to 0 (matches the historical
    ///   on-completion-reset behaviour); `completed_at` is set to `now`.
    /// - During a re-watch (`completed` already `true` at row entry, byte
    ///   offset advancing): `completed` stays `true`, `completed_at` is
    ///   preserved, `resumeByteOffset` tracks current progress.
    /// - On re-completion during a re-watch (byte criterion fires again):
    ///   `completed_at` is updated to `now` (most-recent-wins per A26).
    /// - `lastPlayedAt` is always set to `now`.
    /// - `totalWatchedSeconds` is preserved across upserts.
    ///
    /// Returns the record actually written so callers can emit
    /// `playbackHistoryChanged` with up-to-date data.
    @discardableResult
    public func recordPlayback(
        torrentId: String,
        fileIndex: Int,
        resumeByteOffset: Int64,
        fileSize: Int64,
        nowMillis: Int64? = nil
    ) throws -> PlaybackHistoryRecord {
        let now = nowMillis ?? Int64(Date().timeIntervalSince1970 * 1000)
        // Use integer-arithmetic threshold to match LibraryDomain's
        // WatchThreshold helper exactly. fileSize <= 0 → never complete.
        let isCompleteThisTick = fileSize > 0 &&
            resumeByteOffset.multipliedReportingOverflow(by: 100).0 >=
            fileSize.multipliedReportingOverflow(by: 95).0

        return try db.write { conn -> PlaybackHistoryRecord in
            let existing = try PlaybackHistoryRecord
                .filter(Column("torrent_id") == torrentId && Column("file_index") == fileIndex)
                .fetchOne(conn)

            let wasCompleted = existing?.completed ?? false
            // Completion sticks until manual mark-unwatched per A26.
            let nowCompleted = wasCompleted || isCompleteThisTick

            // completed_at update rule per A26 most-recent-wins:
            //   - new completion (was=false, now=true) → now
            //   - re-completion during re-watch (was=true, isCompleteThisTick=true) → now
            //   - in-progress re-watch (was=true, !isCompleteThisTick) → preserve existing
            //   - never completed → nil
            let newCompletedAt: Int64?
            if isCompleteThisTick {
                newCompletedAt = now
            } else {
                newCompletedAt = existing?.completedAt
            }

            // Reset byte offset when the byte criterion fires; otherwise track current.
            let newOffset = isCompleteThisTick ? 0 : resumeByteOffset

            var record = PlaybackHistoryRecord(
                torrentId: torrentId,
                fileIndex: fileIndex,
                resumeByteOffset: newOffset,
                lastPlayedAt: now,
                totalWatchedSeconds: existing?.totalWatchedSeconds ?? 0,
                completed: nowCompleted,
                completedAt: newCompletedAt
            )
            try record.save(conn)
            return record
        }
    }

    /// Manually mark a file as watched (A26 + #34 design § Engine write rules).
    /// Inserts the row when absent. Always sets `(completed=1, completed_at=now,
    /// resume_byte_offset=0, last_played_at=now)`. Returns the written record.
    @discardableResult
    public func markWatched(
        torrentId: String,
        fileIndex: Int,
        nowMillis: Int64? = nil
    ) throws -> PlaybackHistoryRecord {
        let now = nowMillis ?? Int64(Date().timeIntervalSince1970 * 1000)
        return try db.write { conn -> PlaybackHistoryRecord in
            let existing = try PlaybackHistoryRecord
                .filter(Column("torrent_id") == torrentId && Column("file_index") == fileIndex)
                .fetchOne(conn)
            var record = PlaybackHistoryRecord(
                torrentId: torrentId,
                fileIndex: fileIndex,
                resumeByteOffset: 0,
                lastPlayedAt: now,
                totalWatchedSeconds: existing?.totalWatchedSeconds ?? 0,
                completed: true,
                completedAt: now
            )
            try record.save(conn)
            return record
        }
    }

    /// Manually mark a file as unwatched (A26 + #34 design § Engine write rules).
    /// Sets `(completed=0, completed_at=NULL, resume_byte_offset=0)`; preserves
    /// `last_played_at` so library ordering does not jump. No-op (returns nil)
    /// if the row does not exist — there is nothing to clear.
    @discardableResult
    public func markUnwatched(
        torrentId: String,
        fileIndex: Int
    ) throws -> PlaybackHistoryRecord? {
        try db.write { conn -> PlaybackHistoryRecord? in
            guard var record = try PlaybackHistoryRecord
                .filter(Column("torrent_id") == torrentId && Column("file_index") == fileIndex)
                .fetchOne(conn) else {
                return nil
            }
            record.completed = false
            record.completedAt = nil
            record.resumeByteOffset = 0
            // last_played_at intentionally preserved.
            try record.save(conn)
            return record
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
        _ = try db.write { conn in
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
