// Self-tests for ResumeTracker.
// Activated when the EngineService process is launched with the argument
//   --resume-tracker-self-test
// Exits 0 on pass, 1 on failure.
//
// Uses EngineDatabase.openInMemory() for full isolation. The time source is
// injectable via `ResumeTracker.now` so we can test the 15-second throttle
// without sleeping.

#if DEBUG

import Foundation
import EngineStore

// MARK: - Self-test entry point

/// Runs all ResumeTracker self-tests. Returns a list of failure messages.
/// An empty array means all tests passed.
func runResumeTrackerSelfTests() -> [String] {
    var failures: [String] = []

    func fail(_ message: String, line: Int = #line) {
        failures.append("\(message) (line \(line))")
    }
    func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition { fail(message, line: line) }
    }

    // MARK: - 1. Basic tracking: update → flush → DB has offset

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)
        let tracker = ResumeTracker(cacheManager: cache,
                                    torrentId: "t1", fileIndex: 0,
                                    fileSize: 10_000_000)

        tracker.updateServedByte(500_000)
        tracker.flush()

        if let record = try cache.fetchHistory(torrentId: "t1", fileIndex: 0) {
            expect(record.resumeByteOffset == 500_000,
                   "1: expected offset 500_000, got \(record.resumeByteOffset)")
            expect(!record.completed, "1: should not be completed at 5%")
        } else {
            fail("1: no history record found after flush")
        }
    } catch {
        fail("1: unexpected error: \(error)")
    }

    // MARK: - 2. 15-second throttle: flushIfNeeded should NOT write before 15 s,
    //            then SHOULD write after advancing the time source.

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        // Fake clock starts at a fixed offset so lastFlushTime is also fake.
        var fakeNowNs: UInt64 = 1_000_000_000   // 1 s uptime (arbitrary non-zero)
        let fakeNow: () -> DispatchTime = { DispatchTime(uptimeNanoseconds: fakeNowNs) }

        let tracker = ResumeTracker(cacheManager: cache,
                                    torrentId: "t2", fileIndex: 0,
                                    fileSize: 10_000_000,
                                    now: fakeNow)

        tracker.updateServedByte(100_000)

        // Advance only 5 seconds — should NOT flush.
        fakeNowNs += 5_000_000_000
        tracker.flushIfNeeded()

        let recordBefore = try cache.fetchHistory(torrentId: "t2", fileIndex: 0)
        expect(recordBefore == nil, "2: DB should be empty before 15 s elapsed (got a record)")

        // Advance past 15 seconds total — should flush now.
        fakeNowNs += 11_000_000_000   // total 16 s elapsed since init
        tracker.flushIfNeeded()

        if let record = try cache.fetchHistory(torrentId: "t2", fileIndex: 0) {
            expect(record.resumeByteOffset == 100_000,
                   "2: expected offset 100_000 after throttle window, got \(record.resumeByteOffset)")
        } else {
            fail("2: no history record after 16 s elapsed")
        }
    } catch {
        fail("2: unexpected error: \(error)")
    }

    // MARK: - 3. Completion detection: offset >= 95% → completed=true, offset reset to 0

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)
        let fileSize: Int64 = 10_000_000
        let tracker = ResumeTracker(cacheManager: cache,
                                    torrentId: "t3", fileIndex: 0,
                                    fileSize: fileSize)

        // 96% through — above the threshold.
        let offset = Int64(Double(fileSize) * 0.96)
        tracker.updateServedByte(offset)
        tracker.flush()

        if let record = try cache.fetchHistory(torrentId: "t3", fileIndex: 0) {
            expect(record.completed, "3: should be marked completed at 96%")
            expect(record.resumeByteOffset == 0,
                   "3: offset should be reset to 0 on completion, got \(record.resumeByteOffset)")
        } else {
            fail("3: no history record after completion flush")
        }
    } catch {
        fail("3: unexpected error: \(error)")
    }

    // MARK: - 4. Stream-close flush: calling flush() before 15 s still writes

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)

        // Freeze the clock at a fixed time so flushIfNeeded never triggers.
        let frozenNs: UInt64 = 2_000_000_000
        let tracker = ResumeTracker(cacheManager: cache,
                                    torrentId: "t4", fileIndex: 1,
                                    fileSize: 5_000_000,
                                    now: { DispatchTime(uptimeNanoseconds: frozenNs) })

        tracker.updateServedByte(200_000)

        // Verify flushIfNeeded does nothing (0 s elapsed since time is frozen).
        tracker.flushIfNeeded()
        let noRecord = try cache.fetchHistory(torrentId: "t4", fileIndex: 1)
        expect(noRecord == nil, "4: DB should be empty before explicit flush")

        // Stream-close flush — unconditional.
        tracker.flush()

        if let record = try cache.fetchHistory(torrentId: "t4", fileIndex: 1) {
            expect(record.resumeByteOffset == 200_000,
                   "4: expected offset 200_000 from stream-close flush, got \(record.resumeByteOffset)")
        } else {
            fail("4: no history record after stream-close flush")
        }
    } catch {
        fail("4: unexpected error: \(error)")
    }

    // MARK: - 5. High-water mark: updates 1000 → 500 → 2000 result in 2000

    do {
        let db = try EngineDatabase.openInMemory()
        let cache = try CacheManager(db: db)
        let tracker = ResumeTracker(cacheManager: cache,
                                    torrentId: "t5", fileIndex: 0,
                                    fileSize: 10_000_000)

        tracker.updateServedByte(1_000)
        tracker.updateServedByte(500)    // lower — should be ignored
        tracker.updateServedByte(2_000)
        tracker.flush()

        if let record = try cache.fetchHistory(torrentId: "t5", fileIndex: 0) {
            expect(record.resumeByteOffset == 2_000,
                   "5: high-water mark should be 2_000, got \(record.resumeByteOffset)")
        } else {
            fail("5: no history record after flush")
        }
    } catch {
        fail("5: unexpected error: \(error)")
    }

    return failures
}

/// Entry point called from main.swift when --resume-tracker-self-test is passed.
func runResumeTrackerSelfTestAndExit() {
    let failures = runResumeTrackerSelfTests()
    if failures.isEmpty {
        NSLog("[ResumeTrackerSelfTest] All tests passed.")
        exit(0)
    } else {
        NSLog("[ResumeTrackerSelfTest] FAILED — %d failure(s):", failures.count)
        for f in failures {
            NSLog("[ResumeTrackerSelfTest]   FAIL: %@", f)
        }
        exit(1)
    }
}

#endif // DEBUG
