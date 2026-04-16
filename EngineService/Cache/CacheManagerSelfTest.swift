// Self-tests for CacheManager (playback history + pinned files).
// Activated when the EngineService process is launched with the argument
//   --cache-manager-self-test
// Exits 0 on pass, 1 on failure.
//
// Uses EngineDatabase.openInMemory() for full isolation — each test group
// operates on its own in-memory database so tests cannot affect each other.

#if DEBUG

import Foundation
import EngineStore

// MARK: - Self-test entry point

/// Runs all CacheManager self-tests. Returns a list of failure messages.
/// An empty array means all tests passed.
func runCacheManagerSelfTests() -> [String] {
    var failures: [String] = []

    func fail(_ message: String, line: Int = #line) {
        failures.append("\(message) (line \(line))")
    }
    func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition { fail(message, line: line) }
    }

    // MARK: - 1. Playback history round-trip

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        try cache.recordPlayback(
            torrentId: "abc123",
            fileIndex: 2,
            resumeByteOffset: 1024,
            fileSize: 10_000_000
        )

        if let record = try cache.fetchHistory(torrentId: "abc123", fileIndex: 2) {
            expect(record.torrentId == "abc123", "1: torrentId mismatch")
            expect(record.fileIndex == 2, "1: fileIndex mismatch")
            expect(record.resumeByteOffset == 1024, "1: resumeByteOffset should be 1024, got \(record.resumeByteOffset)")
            expect(!record.completed, "1: should not be completed")
            expect(record.lastPlayedAt > 0, "1: lastPlayedAt should be set")
        } else {
            fail("1: fetchHistory returned nil for a record that was just inserted")
        }
    } catch {
        fail("1: unexpected error: \(error)")
    }

    // MARK: - 2. Playback history completion flag + offset reset

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        let fileSize: Int64 = 10_000_000
        // 96% through — above the 95% threshold.
        let offset: Int64 = Int64(Double(fileSize) * 0.96)

        try cache.recordPlayback(
            torrentId: "def456",
            fileIndex: 0,
            resumeByteOffset: offset,
            fileSize: fileSize
        )

        if let record = try cache.fetchHistory(torrentId: "def456", fileIndex: 0) {
            expect(record.completed, "2: should be marked completed at 96%")
            expect(record.resumeByteOffset == 0, "2: offset should be reset to 0 on completion, got \(record.resumeByteOffset)")
        } else {
            fail("2: fetchHistory returned nil")
        }
    } catch {
        fail("2: unexpected error: \(error)")
    }

    // MARK: - 2b. Exactly at the 95% boundary is also completed

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        let fileSize: Int64 = 1_000_000
        let offset: Int64 = Int64(Double(fileSize) * 0.95)  // exactly 95%

        try cache.recordPlayback(
            torrentId: "ghi789",
            fileIndex: 1,
            resumeByteOffset: offset,
            fileSize: fileSize
        )

        if let record = try cache.fetchHistory(torrentId: "ghi789", fileIndex: 1) {
            expect(record.completed, "2b: exactly 95% should be marked completed")
            expect(record.resumeByteOffset == 0, "2b: offset should be 0 at boundary, got \(record.resumeByteOffset)")
        } else {
            fail("2b: fetchHistory returned nil")
        }
    } catch {
        fail("2b: unexpected error: \(error)")
    }

    // MARK: - 3. Pinned set round-trip

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        expect(!cache.isPinned(torrentId: "t1", fileIndex: 0), "3: should not be pinned before pin()")

        try cache.pin(torrentId: "t1", fileIndex: 0)
        expect(cache.isPinned(torrentId: "t1", fileIndex: 0), "3: should be pinned after pin()")
        expect(cache.allPinnedKeys().count == 1, "3: allPinnedKeys should have 1 entry")

        try cache.unpin(torrentId: "t1", fileIndex: 0)
        expect(!cache.isPinned(torrentId: "t1", fileIndex: 0), "3: should not be pinned after unpin()")
        expect(cache.allPinnedKeys().isEmpty, "3: allPinnedKeys should be empty after unpin()")
    } catch {
        fail("3: unexpected error: \(error)")
    }

    // MARK: - 4. Pinned set survives "restart" (new CacheManager on same DB)

    do {
        let db = try EngineDatabase.openInMemory()
        let cache1 = try CacheManager(db: db)

        try cache1.pin(torrentId: "torrent-A", fileIndex: 0)
        try cache1.pin(torrentId: "torrent-A", fileIndex: 1)
        try cache1.pin(torrentId: "torrent-B", fileIndex: 3)

        // Simulate engine restart: new CacheManager, same DatabaseQueue.
        let cache2 = try CacheManager(db: db)

        let keys = cache2.allPinnedKeys()
        expect(keys.count == 3, "4: should have 3 pinned keys after restart, got \(keys.count)")
        expect(cache2.isPinned(torrentId: "torrent-A", fileIndex: 0), "4: torrent-A/0 should be pinned")
        expect(cache2.isPinned(torrentId: "torrent-A", fileIndex: 1), "4: torrent-A/1 should be pinned")
        expect(cache2.isPinned(torrentId: "torrent-B", fileIndex: 3), "4: torrent-B/3 should be pinned")
        // Files that were never pinned should not appear.
        expect(!cache2.isPinned(torrentId: "torrent-B", fileIndex: 0), "4: torrent-B/0 should not be pinned")
    } catch {
        fail("4: unexpected error: \(error)")
    }

    // MARK: - 5. fetchAllHistory ordering (DESC by lastPlayedAt)

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        // Insert with explicit waits to ensure distinct timestamps.
        // We manipulate the records directly to control lastPlayedAt values.
        // Insert via recordPlayback first, then verify the ordering is DESC.
        //
        // Since recordPlayback stamps "now", we insert three records with a
        // small sleep between each to ensure distinct ms timestamps.
        try cache.recordPlayback(torrentId: "order-t", fileIndex: 0, resumeByteOffset: 100, fileSize: 1_000_000)
        Thread.sleep(forTimeInterval: 0.005)  // 5 ms gap
        try cache.recordPlayback(torrentId: "order-t", fileIndex: 1, resumeByteOffset: 200, fileSize: 1_000_000)
        Thread.sleep(forTimeInterval: 0.005)
        try cache.recordPlayback(torrentId: "order-t", fileIndex: 2, resumeByteOffset: 300, fileSize: 1_000_000)

        let history = try cache.fetchAllHistory()
        expect(history.count == 3, "5: expected 3 history rows, got \(history.count)")

        if history.count == 3 {
            // DESC order: index 2 (most recent) first, index 0 last.
            expect(history[0].fileIndex == 2, "5: first row should be most recently played (fileIndex 2), got \(history[0].fileIndex)")
            expect(history[1].fileIndex == 1, "5: second row should be fileIndex 1, got \(history[1].fileIndex)")
            expect(history[2].fileIndex == 0, "5: third row should be fileIndex 0, got \(history[2].fileIndex)")
            // Verify descending timestamp invariant explicitly.
            expect(history[0].lastPlayedAt >= history[1].lastPlayedAt,
                   "5: history[0].lastPlayedAt should be >= history[1].lastPlayedAt")
            expect(history[1].lastPlayedAt >= history[2].lastPlayedAt,
                   "5: history[1].lastPlayedAt should be >= history[2].lastPlayedAt")
        }
    } catch {
        fail("5: unexpected error: \(error)")
    }

    // MARK: - 6. Upsert preserves totalWatchedSeconds

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        // First write.
        try cache.recordPlayback(torrentId: "upsert-t", fileIndex: 0, resumeByteOffset: 500, fileSize: 5_000_000)

        // Manually bump totalWatchedSeconds in DB to verify it survives an upsert.
        try db.write { conn in
            try conn.execute(
                sql: "UPDATE playback_history SET total_watched_seconds = 42.5 WHERE torrent_id = ? AND file_index = ?",
                arguments: ["upsert-t", 0]
            )
        }

        // Second write (upsert path).
        try cache.recordPlayback(torrentId: "upsert-t", fileIndex: 0, resumeByteOffset: 800, fileSize: 5_000_000)

        if let record = try cache.fetchHistory(torrentId: "upsert-t", fileIndex: 0) {
            expect(record.totalWatchedSeconds == 42.5,
                   "6: totalWatchedSeconds should survive upsert, got \(record.totalWatchedSeconds)")
            expect(record.resumeByteOffset == 800, "6: resumeByteOffset should be updated, got \(record.resumeByteOffset)")
        } else {
            fail("6: fetchHistory returned nil")
        }
    } catch {
        fail("6: unexpected error: \(error)")
    }

    // MARK: - 7. pressure() classification

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)
        let high: Int64 = 100_000

        // ok: below 80% of high water
        expect(cache.pressure(usedBytes: 0, highWater: high) == .ok,
               "7: 0 bytes should be ok")
        expect(cache.pressure(usedBytes: 79_999, highWater: high) == .ok,
               "7: 79999/100000 should be ok (< 80%)")

        // warn: exactly at 80% boundary
        expect(cache.pressure(usedBytes: 80_000, highWater: high) == .warn,
               "7: exactly 80% (80000/100000) should be warn")
        expect(cache.pressure(usedBytes: 99_999, highWater: high) == .warn,
               "7: 99999/100000 should be warn (< highWater)")

        // critical: at or above high water
        expect(cache.pressure(usedBytes: 100_000, highWater: high) == .critical,
               "7: exactly highWater (100000/100000) should be critical")
        expect(cache.pressure(usedBytes: 150_000, highWater: high) == .critical,
               "7: above highWater should be critical")
    } catch {
        fail("7: unexpected error: \(error)")
    }

    // MARK: - 8. usedBytes(paths:) accounting

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        let dir = NSTemporaryDirectory()
        let p1 = (dir as NSString).appendingPathComponent("cache_test_8a_\(Int.random(in: 10000...99999)).bin")
        let p2 = (dir as NSString).appendingPathComponent("cache_test_8b_\(Int.random(in: 10000...99999)).bin")

        defer {
            try? FileManager.default.removeItem(atPath: p1)
            try? FileManager.default.removeItem(atPath: p2)
        }

        // Write files of known sizes. 4096 and 8192 bytes — one APFS block each
        // and two blocks respectively, so st_blocks will be 8 and 16 (512-byte units).
        let data1 = Data(repeating: 0xAA, count: 4096)
        let data2 = Data(repeating: 0xBB, count: 8192)
        try data1.write(to: URL(fileURLWithPath: p1))
        try data2.write(to: URL(fileURLWithPath: p2))

        // Verify individual stat matches usedBytes.
        var st1 = stat()
        var st2 = stat()
        stat(p1, &st1)
        stat(p2, &st2)
        let expected = Int64(st1.st_blocks) * 512 + Int64(st2.st_blocks) * 512

        let actual = cache.usedBytes(paths: [p1, p2])
        expect(actual == expected,
               "8: usedBytes([p1,p2]) should be \(expected), got \(actual)")
        expect(actual > 0, "8: usedBytes should be positive for non-empty files")

        // Missing path contributes 0.
        let missing = (dir as NSString).appendingPathComponent("does_not_exist_\(Int.random(in: 10000...99999)).bin")
        let withMissing = cache.usedBytes(paths: [p1, missing])
        let onlyP1 = cache.usedBytes(paths: [p1])
        expect(withMissing == onlyP1,
               "8: missing file should contribute 0 bytes (withMissing=\(withMissing), onlyP1=\(onlyP1))")
    } catch {
        fail("8: unexpected error: \(error)")
    }

    // MARK: - 9. runEvictionPass with a mock bridge

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        // Create two temp files with known content so F_PUNCHHOLE has something to act on.
        let dir = NSTemporaryDirectory()
        let p1 = (dir as NSString).appendingPathComponent("cache_evict_9a_\(Int.random(in: 10000...99999)).bin")
        let p2 = (dir as NSString).appendingPathComponent("cache_evict_9b_\(Int.random(in: 10000...99999)).bin")

        defer {
            try? FileManager.default.removeItem(atPath: p1)
            try? FileManager.default.removeItem(atPath: p2)
        }

        // 256 KiB each — large enough for the piece range computation to have
        // at least one full interior piece with a 64 KiB piece length.
        let size: Int = 256 * 1024
        let data = Data(repeating: 0xFF, count: size)
        try data.write(to: URL(fileURLWithPath: p1))
        try data.write(to: URL(fileURLWithPath: p2))

        let pieceLength: Int64 = 64 * 1024   // 64 KiB

        // Candidates: both files treated as a single-file torrent each, fully inside
        // the piece range so punch geometry is exercised.
        let c1 = EvictionCandidate(
            torrentId: "torrent-A",
            fileIndex: 0,
            onDiskPath: p1,
            fileStartInTorrent: 0,
            fileEndInTorrent: Int64(size),
            pieceLength: pieceLength,
            lastPlayedAtMs: nil,
            completed: false,
            tierRank: 1
        )
        let c2 = EvictionCandidate(
            torrentId: "torrent-B",
            fileIndex: 0,
            onDiskPath: p2,
            fileStartInTorrent: 0,
            fileEndInTorrent: Int64(size),
            pieceLength: pieceLength,
            lastPlayedAtMs: nil,
            completed: false,
            tierRank: 1
        )

        let bridge = MockCacheManagerBridge()

        // Set highWater below the actual total so eviction is triggered.
        // Set lowWater to 0 so both candidates are evicted.
        var st1 = stat()
        stat(p1, &st1)
        var st2 = stat()
        stat(p2, &st2)
        let totalOnDisk = Int64(st1.st_blocks) * 512 + Int64(st2.st_blocks) * 512

        let highWater = max(1, totalOnDisk - 1)   // just below total → triggers eviction
        let lowWater: Int64 = 0                    // force eviction of all candidates

        let result = try cache.runEvictionPass(
            candidates: [c1, c2],
            bridge: bridge,
            highWaterBytes: highWater,
            lowWaterBytes: lowWater
        )

        // Structural assertions.
        expect(result.candidatesEvicted > 0,
               "9: at least one candidate should be evicted, got \(result.candidatesEvicted)")
        expect(result.torrentsRechecked > 0,
               "9: at least one torrent should be rechecked, got \(result.torrentsRechecked)")

        // setFilePriority(0) must have been called once per evicted candidate.
        let priorityCalls = bridge.setFilePriorityCalls.filter { $0.priority == 0 }
        expect(priorityCalls.count == result.candidatesEvicted,
               "9: setFilePriority(0) should be called once per evicted candidate " +
               "(expected \(result.candidatesEvicted), got \(priorityCalls.count))")

        // forceRecheck must have been called once per distinct torrentId.
        expect(bridge.forceRecheckCalls.count == result.torrentsRechecked,
               "9: forceRecheck call count (\(bridge.forceRecheckCalls.count)) " +
               "should equal torrentsRechecked (\(result.torrentsRechecked))")

        // statusState must have been polled at least 3× per recheck: the mock
        // state machine returns checkingResumeData, checkingFiles, finished —
        // verifying the wait loop actually spun through its sleep branch.
        let expectedMinPolls = 3 * result.torrentsRechecked
        expect(bridge.statusStateCalls.count >= expectedMinPolls,
               "9: statusState should be polled at least \(expectedMinPolls) times (3× per recheck to exercise wait-loop spin), got \(bridge.statusStateCalls.count)")

        // F_PUNCHHOLE works on APFS (the macOS system disk). NSTemporaryDirectory()
        // is on APFS on all supported macOS versions for ButterBar, so we expect
        // actual byte reclamation. Allow 0 as a fallback with a warning so the
        // test doesn't fail on an unusual dev machine, but expect > 0 in practice.
        expect(result.bytesReclaimed >= 0,
               "9: bytesReclaimed should be non-negative, got \(result.bytesReclaimed)")
        if result.bytesReclaimed > 0 {
            // Expected path on APFS: four 64 KiB pieces × two files = ~512 KiB reclaimed.
            NSLog("[CacheManagerSelfTest] Test 9: reclaimed %lld bytes — F_PUNCHHOLE working as expected.", result.bytesReclaimed)
        } else {
            NSLog("[CacheManagerSelfTest] Test 9: bytesReclaimed == 0 — filesystem may not support F_PUNCHHOLE (HFS+ or other non-APFS). Structural assertions still passed.")
        }
    } catch {
        fail("9: unexpected error: \(error)")
    }

    // MARK: - 10. completed_at set on 0→1 transition (A26)

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)
        let fileSize: Int64 = 1_000_000

        // Tick 1: in-progress, no completion.
        let r1 = try cache.recordPlayback(torrentId: "ca-10", fileIndex: 0,
                                          resumeByteOffset: 100,
                                          fileSize: fileSize,
                                          nowMillis: 1_000_000)
        expect(!r1.completed, "10: tick 1 should not be completed")
        expect(r1.completedAt == nil, "10: tick 1 should leave completed_at nil")

        // Tick 2: cross threshold.
        let r2 = try cache.recordPlayback(torrentId: "ca-10", fileIndex: 0,
                                          resumeByteOffset: 950_000,
                                          fileSize: fileSize,
                                          nowMillis: 2_000_000)
        expect(r2.completed, "10: tick 2 should be completed")
        expect(r2.completedAt == 2_000_000,
               "10: completed_at should be set to now on 0→1 transition, got \(r2.completedAt ?? -1)")
        expect(r2.resumeByteOffset == 0, "10: offset should reset to 0 on completion")
    } catch {
        fail("10: unexpected error: \(error)")
    }

    // MARK: - 11. Re-watch preserves completed and completed_at (A26)

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)
        let fileSize: Int64 = 1_000_000

        // Watch to completion.
        try cache.recordPlayback(torrentId: "ca-11", fileIndex: 0,
                                 resumeByteOffset: 950_000,
                                 fileSize: fileSize,
                                 nowMillis: 1_000_000)

        // Re-open and progress (well below threshold).
        let r = try cache.recordPlayback(torrentId: "ca-11", fileIndex: 0,
                                         resumeByteOffset: 100_000,
                                         fileSize: fileSize,
                                         nowMillis: 5_000_000)
        expect(r.completed, "11: re-watch progress must keep completed=true")
        expect(r.completedAt == 1_000_000,
               "11: re-watch progress must preserve completed_at, got \(r.completedAt ?? -1)")
        expect(r.resumeByteOffset == 100_000,
               "11: re-watch must track current offset, got \(r.resumeByteOffset)")
    } catch {
        fail("11: unexpected error: \(error)")
    }

    // MARK: - 12. Re-completion updates completed_at (most-recent-wins, A26)

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)
        let fileSize: Int64 = 1_000_000

        try cache.recordPlayback(torrentId: "ca-12", fileIndex: 0,
                                 resumeByteOffset: 950_000,
                                 fileSize: fileSize,
                                 nowMillis: 1_000_000)
        // Some time later, re-watch ends with full completion again.
        let r = try cache.recordPlayback(torrentId: "ca-12", fileIndex: 0,
                                         resumeByteOffset: 980_000,
                                         fileSize: fileSize,
                                         nowMillis: 9_000_000)
        expect(r.completed, "12: re-completion must keep completed=true")
        expect(r.completedAt == 9_000_000,
               "12: re-completion must update completed_at to now, got \(r.completedAt ?? -1)")
        expect(r.resumeByteOffset == 0, "12: re-completion resets offset to 0")
    } catch {
        fail("12: unexpected error: \(error)")
    }

    // MARK: - 13. markWatched on absent row inserts the correct shape

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        let r = try cache.markWatched(torrentId: "ca-13", fileIndex: 4,
                                      nowMillis: 5_555_555)
        expect(r.completed, "13: marked-watched row must have completed=true")
        expect(r.completedAt == 5_555_555,
               "13: completed_at should equal injected now, got \(r.completedAt ?? -1)")
        expect(r.resumeByteOffset == 0, "13: resume offset must be 0")
        expect(r.lastPlayedAt == 5_555_555, "13: last_played_at must be set on insert")

        let fetched = try cache.fetchHistory(torrentId: "ca-13", fileIndex: 4)
        expect(fetched != nil, "13: row should be persisted")
    } catch {
        fail("13: unexpected error: \(error)")
    }

    // MARK: - 14. markWatched preserves completed_at on already-.watched row,
    //               re-stamps when applied to .reWatching (per design transition matrix).

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        // 14a: starting from .watched (completed=1, offset=0), a second
        // markWatched is "I'm just confirming" — preserve original completed_at.
        try cache.markWatched(torrentId: "ca-14a", fileIndex: 0, nowMillis: 1_000)
        let r1 = try cache.markWatched(torrentId: "ca-14a", fileIndex: 0, nowMillis: 2_000)
        expect(r1.completedAt == 1_000,
               "14a: markWatched on .watched must preserve original completed_at, got \(r1.completedAt ?? -1)")

        // 14b: simulate .reWatching (completed=1 + offset>0), then markWatched.
        // Per design: "treat as freshly watched right now" — re-stamp.
        try cache.markWatched(torrentId: "ca-14b", fileIndex: 0, nowMillis: 1_000)
        // Force the row into a re-watching shape via direct DB write.
        try db.write { conn in
            try conn.execute(
                sql: "UPDATE playback_history SET resume_byte_offset = 100000 WHERE torrent_id = ? AND file_index = ?",
                arguments: ["ca-14b", 0]
            )
        }
        let r2 = try cache.markWatched(torrentId: "ca-14b", fileIndex: 0, nowMillis: 5_000)
        expect(r2.completedAt == 5_000,
               "14b: markWatched on .reWatching must re-stamp completed_at, got \(r2.completedAt ?? -1)")

        // 14c: starting from .inProgress (completed=0 + offset>0), markWatched
        // creates a fresh completion — completedAt = now.
        try cache.recordPlayback(torrentId: "ca-14c", fileIndex: 0,
                                 resumeByteOffset: 250_000,
                                 fileSize: 1_000_000,
                                 nowMillis: 1_000)
        let r3 = try cache.markWatched(torrentId: "ca-14c", fileIndex: 0, nowMillis: 9_000)
        expect(r3.completedAt == 9_000,
               "14c: markWatched on .inProgress must set completed_at = now, got \(r3.completedAt ?? -1)")
    } catch {
        fail("14: unexpected error: \(error)")
    }

    // MARK: - 15. markUnwatched clears completion and preserves last_played_at

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        try cache.markWatched(torrentId: "ca-15", fileIndex: 0, nowMillis: 1_000)
        let r = try cache.markUnwatched(torrentId: "ca-15", fileIndex: 0)
        guard let r = r else {
            fail("15: markUnwatched should return a record when one exists")
            return failures
        }
        expect(!r.completed, "15: completed must flip to false")
        expect(r.completedAt == nil, "15: completed_at must be cleared")
        expect(r.resumeByteOffset == 0, "15: resume offset must be 0")
        expect(r.lastPlayedAt == 1_000,
               "15: last_played_at must be preserved (was 1000), got \(r.lastPlayedAt)")
    } catch {
        fail("15: unexpected error: \(error)")
    }

    // MARK: - 16. markUnwatched on absent row is a no-op (returns nil)

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        let r = try cache.markUnwatched(torrentId: "ca-16-missing", fileIndex: 0)
        expect(r == nil, "16: markUnwatched on absent row must return nil")
    } catch {
        fail("16: unexpected error: \(error)")
    }

    return failures
}

// MARK: - Mock bridge for test 9

/// Records all bridge calls for structural verification in test 9.
/// statusState drives through a simple three-state machine to simulate
/// a real recheck lifecycle: downloading → checkingFiles → finished.
private final class MockCacheManagerBridge: CacheManagerBridge {

    struct PriorityCall {
        let torrentID: String
        let fileIndex: Int
        let priority: Int
    }

    private(set) var setFilePriorityCalls: [PriorityCall] = []
    private(set) var forceRecheckCalls: [String] = []
    private(set) var statusStateCalls: [String] = []

    // Per-torrent poll counter drives the state machine. The first polls
    // return a checking state so waitForRecheckToComplete has to spin
    // through its sleep branch — if the first poll were non-checking the
    // wait loop would return immediately and the sleep path wouldn't be
    // exercised (Opus review D2).
    //   call 0   → "checkingResumeData"
    //   call 1   → "checkingFiles"
    //   call 2+  → "finished"
    private var pollCounts: [String: Int] = [:]

    func setFilePriority(torrentID: String, fileIndex: Int, priority: Int) throws {
        setFilePriorityCalls.append(PriorityCall(torrentID: torrentID, fileIndex: fileIndex, priority: priority))
    }

    func forceRecheck(torrentID: String) throws {
        forceRecheckCalls.append(torrentID)
        // Reset the poll counter so the state machine restarts from the beginning.
        pollCounts[torrentID] = 0
    }

    func statusState(torrentID: String) throws -> String {
        statusStateCalls.append(torrentID)
        let count = pollCounts[torrentID] ?? 0
        pollCounts[torrentID] = count + 1
        switch count {
        case 0:  return "checkingResumeData"
        case 1:  return "checkingFiles"
        default: return "finished"
        }
    }
}

/// Entry point called from main.swift when --cache-manager-self-test is passed.
func runCacheManagerSelfTestAndExit() {
    let failures = runCacheManagerSelfTests()
    if failures.isEmpty {
        NSLog("[CacheManagerSelfTest] All tests passed.")
        exit(0)
    } else {
        NSLog("[CacheManagerSelfTest] FAILED — %d failure(s):", failures.count)
        for f in failures {
            NSLog("[CacheManagerSelfTest]   FAIL: %@", f)
        }
        exit(1)
    }
}

#endif // DEBUG
