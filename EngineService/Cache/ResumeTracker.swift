// ResumeTracker: in-session high-water-mark tracking for resume-byte-offset.
//
// Threading model:
//   - `updateServedByte` is called from the gateway queue (byte-serving path).
//   - `flushIfNeeded` and `flush` are called from plannerQueue (tick path / stop).
//   - `_lastServedByte` is protected by `os_unfair_lock` so both queues can
//     access it without a data race.
//   - All DB writes happen inside `flush`/`flushIfNeeded`, which run on plannerQueue
//     and therefore are already serialised (one write at a time).

import Foundation
import os.lock

/// Tracks the highest byte offset served to the player and periodically
/// persists it to the database via `CacheManager.recordPlayback`.
///
/// Not thread-safe on its own — see threading notes above.
final class ResumeTracker {

    // MARK: - Injected dependencies

    private let cacheManager: CacheManager
    private let torrentId: String
    private let fileIndex: Int
    private let fileSize: Int64

    // MARK: - Time source (injectable for tests)

    /// Returns the current time. Defaults to `DispatchTime.now()`.
    /// Tests replace this with a controllable closure to avoid sleeping.
    let now: () -> DispatchTime

    // MARK: - Internal state

    // Protected by `lock` — read/written from both gateway and planner queues.
    private var lock = os_unfair_lock()
    private var _lastServedByte: Int64 = 0

    // Written/read only from plannerQueue — no lock needed.
    // Stores the absolute time at which the next flush becomes due.
    // Compared using DispatchTime's native >= (Mach time units, not nanoseconds).
    private var nextFlushDeadline: DispatchTime

    private static let flushIntervalNs: UInt64 = 15_000_000_000   // 15 s in nanoseconds

    // MARK: - Init

    init(cacheManager: CacheManager,
         torrentId: String,
         fileIndex: Int,
         fileSize: Int64,
         now: @escaping () -> DispatchTime = { .now() }) {
        self.cacheManager = cacheManager
        self.torrentId = torrentId
        self.fileIndex = fileIndex
        self.fileSize = fileSize
        self.now = now
        // First flush is due 15 s from now.
        self.nextFlushDeadline = now() + .nanoseconds(Int(Self.flushIntervalNs))
    }

    // MARK: - Public API

    /// Update the in-memory high-water mark. Safe to call from any queue.
    func updateServedByte(_ offset: Int64) {
        os_unfair_lock_lock(&lock)
        if offset > _lastServedByte {
            _lastServedByte = offset
        }
        os_unfair_lock_unlock(&lock)
    }

    /// Flush to DB only if 15 seconds have elapsed since the last flush.
    /// Must be called from plannerQueue.
    func flushIfNeeded() {
        guard now() >= nextFlushDeadline else { return }
        flush()
    }

    /// Unconditional flush — writes current high-water mark to DB.
    /// Must be called from plannerQueue (or any serial context that owns CacheManager).
    func flush() {
        let byte = readLastServedByte()
        do {
            try cacheManager.recordPlayback(
                torrentId: torrentId,
                fileIndex: fileIndex,
                resumeByteOffset: byte,
                fileSize: fileSize
            )
        } catch {
            NSLog("[ResumeTracker] recordPlayback failed: %@", "\(error)")
        }
        nextFlushDeadline = now() + .nanoseconds(Int(Self.flushIntervalNs))
    }

    // MARK: - Private

    private func readLastServedByte() -> Int64 {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _lastServedByte
    }
}
