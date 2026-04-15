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

    return failures
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
