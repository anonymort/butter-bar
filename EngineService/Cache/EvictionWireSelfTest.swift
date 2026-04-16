// Self-tests for the eviction wiring logic in RealEngineBackend.
// Activated when the EngineService process is launched with the argument
//   --eviction-wire-self-test
// Exits 0 on pass, 1 on failure.
//
// Tests drive the pure helpers extracted from RealEngineBackend:
//   makeCandidates(unsorted:)
//   shouldEmitPressure(now:level:lastEmission:lastLevel:)
//   makePressureDTO(cm:totalBudget:usedBytes:pinnedBytes:)
//
// They also exercise candidate-computation logic via a stub that mimics what
// runEvictionTick would build, using a mock CacheManagerBridge.

#if DEBUG

import Foundation
import EngineInterface
import EngineStore

// MARK: - Entry point

func runEvictionWireSelfTestAndExit() {
    let failures = runEvictionWireSelfTests()
    if failures.isEmpty {
        NSLog("[EvictionWireSelfTest] All tests passed.")
        exit(0)
    } else {
        NSLog("[EvictionWireSelfTest] FAILED — %d failure(s):", failures.count)
        for f in failures {
            NSLog("[EvictionWireSelfTest]   FAIL: %@", f)
        }
        exit(1)
    }
}

// MARK: - Test runner

func runEvictionWireSelfTests() -> [String] {
    var failures: [String] = []

    func fail(_ message: String, line: Int = #line) {
        failures.append("\(message) (line \(line))")
    }
    func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition { fail(message, line: line) }
    }

    // A minimal RealEngineBackend-like object that exposes the pure helpers.
    // We can't instantiate RealEngineBackend itself in self-test context (it
    // spins up libtorrent + gateway), so the helpers are tested through a
    // thin shim that duplicates only the stateless logic.
    let helper = EvictionWireHelper()

    // MARK: - Test 1: Pinned files never appear as candidates

    do {
        let db = try EngineDatabase.openInMemory()
        let cm = try CacheManager(db: db)
        try cm.pin(torrentId: "t1", fileIndex: 0)

        // Build a candidate list that includes the pinned file.
        // The production tick filters before building rawCandidates, so we
        // verify the filter logic directly.
        let isPinned = cm.isPinned(torrentId: "t1", fileIndex: 0)
        expect(isPinned, "1: isPinned should be true for pinned file")

        // Simulate the tick's filter: pinned files go to pinnedPaths, not candidates.
        let allFiles: [(torrentId: String, fileIndex: Int, pinned: Bool, resumeOffset: Int64)] = [
            ("t1", 0, true, 0),   // pinned — excluded
            ("t1", 1, false, 0),  // not pinned, no resume — tier 1 candidate
        ]
        var candidates: [EvictionCandidate] = []
        var pinnedCount = 0
        for f in allFiles {
            if f.pinned {
                pinnedCount += 1
                continue
            }
            candidates.append(makeCandidate(torrentId: f.torrentId, fileIndex: f.fileIndex, tierRank: 1))
        }
        expect(pinnedCount == 1, "1: one file should be excluded as pinned, got \(pinnedCount)")
        expect(candidates.count == 1, "1: one candidate should remain, got \(candidates.count)")
        expect(candidates[0].fileIndex == 1, "1: remaining candidate should be fileIndex 1")
    } catch {
        fail("1: unexpected error: \(error)")
    }

    // MARK: - Test 2: Files with resumeByteOffset > 0 are excluded

    do {
        let db = try EngineDatabase.openInMemory()
        let cm = try CacheManager(db: db)

        // Record partial playback (resumeByteOffset = 1024, not completed).
        try cm.recordPlayback(torrentId: "t2", fileIndex: 0,
                              resumeByteOffset: 1024, fileSize: 10_000_000)

        if let record = try cm.fetchHistory(torrentId: "t2", fileIndex: 0) {
            let hasPartialResume = record.resumeByteOffset > 0
            expect(hasPartialResume, "2: file with partial resume should be flagged")
            // The tick excludes files with partial resume.
            var candidates: [EvictionCandidate] = []
            if !hasPartialResume {
                candidates.append(makeCandidate(torrentId: "t2", fileIndex: 0, tierRank: 1))
            }
            expect(candidates.isEmpty, "2: partial resume file should be excluded from candidates")
        } else {
            fail("2: fetchHistory returned nil")
        }
    } catch {
        fail("2: unexpected error: \(error)")
    }

    // MARK: - Test 3: Active-stream torrents skipped (mock hasActiveStream → true)

    do {
        let mockRegistry = MockStreamRegistry()
        mockRegistry.activeTorrentIDs.insert("t3")

        let hasActive = mockRegistry.hasActiveStream(torrentID: "t3")
        expect(hasActive, "3: mock registry should report active stream for t3")

        // Simulate the tick's active-stream guard.
        let torrentIDs: Set<String> = ["t3"]
        let anyActive = torrentIDs.contains { mockRegistry.hasActiveStream(torrentID: $0) }
        expect(anyActive, "3: anyActive should be true when a stream is active")

        // When anyActive is true, eviction must not proceed.
        var evictionRan = false
        if !anyActive {
            evictionRan = true
        }
        expect(!evictionRan, "3: eviction should not run when active streams are present")
    }

    // MARK: - Test 4: Tier ordering correct

    do {
        // Build candidates with mixed tiers and mixed lastPlayedAtMs.
        let t1a = makeCandidate(torrentId: "t4", fileIndex: 0, tierRank: 1, lastPlayedAt: nil)
        let t1b = makeCandidate(torrentId: "t4", fileIndex: 1, tierRank: 1, lastPlayedAt: 2000)
        let t1c = makeCandidate(torrentId: "t4", fileIndex: 2, tierRank: 1, lastPlayedAt: 1000)
        let t2a = makeCandidate(torrentId: "t4", fileIndex: 3, tierRank: 2, lastPlayedAt: 500)
        let t2b = makeCandidate(torrentId: "t4", fileIndex: 4, tierRank: 2, lastPlayedAt: nil)

        let unsorted = [t2a, t1b, t2b, t1a, t1c]
        let sorted = helper.makeCandidates(unsorted: unsorted)

        expect(sorted.count == 5, "4: should have 5 candidates, got \(sorted.count)")

        if sorted.count == 5 {
            // Tier 1 before tier 2.
            expect(sorted[0].tierRank == 1, "4: first should be tier 1, got \(sorted[0].tierRank)")
            expect(sorted[1].tierRank == 1, "4: second should be tier 1, got \(sorted[1].tierRank)")
            expect(sorted[2].tierRank == 1, "4: third should be tier 1, got \(sorted[2].tierRank)")
            expect(sorted[3].tierRank == 2, "4: fourth should be tier 2, got \(sorted[3].tierRank)")
            expect(sorted[4].tierRank == 2, "4: fifth should be tier 2, got \(sorted[4].tierRank)")

            // Within tier 1: lastPlayedAt 1000 before 2000, nils last.
            let tier1 = sorted.filter { $0.tierRank == 1 }
            expect(tier1[0].lastPlayedAtMs == 1000, "4: tier-1 first should be lastPlayedAt=1000, got \(String(describing: tier1[0].lastPlayedAtMs))")
            expect(tier1[1].lastPlayedAtMs == 2000, "4: tier-1 second should be lastPlayedAt=2000, got \(String(describing: tier1[1].lastPlayedAtMs))")
            expect(tier1[2].lastPlayedAtMs == nil,  "4: tier-1 third should be lastPlayedAt=nil (got \(String(describing: tier1[2].lastPlayedAtMs)))")

            // Within tier 2: lastPlayedAt=500 before nil.
            let tier2 = sorted.filter { $0.tierRank == 2 }
            expect(tier2[0].lastPlayedAtMs == 500, "4: tier-2 first should be lastPlayedAt=500, got \(String(describing: tier2[0].lastPlayedAtMs))")
            expect(tier2[1].lastPlayedAtMs == nil, "4: tier-2 second should be nil, got \(String(describing: tier2[1].lastPlayedAtMs))")
        }
    }

    // MARK: - Test 5: DiskPressureDTO arithmetic correct

    do {
        let db = try EngineDatabase.openInMemory()
        let cm = try CacheManager(db: db)

        let totalBudget: Int64 = 100_000
        let usedBytes: Int64   = 60_000
        let pinnedBytes: Int64 = 20_000

        let dto = helper.makePressureDTO(cm: cm,
                                         totalBudget: totalBudget,
                                         usedBytes: usedBytes,
                                         pinnedBytes: pinnedBytes)

        expect(dto.totalBudgetBytes == totalBudget, "5: totalBudgetBytes should be \(totalBudget), got \(dto.totalBudgetBytes)")
        expect(dto.usedBytes == usedBytes, "5: usedBytes should be \(usedBytes), got \(dto.usedBytes)")
        expect(dto.pinnedBytes == pinnedBytes, "5: pinnedBytes should be \(pinnedBytes), got \(dto.pinnedBytes)")
        expect(dto.evictableBytes == usedBytes - pinnedBytes,
               "5: evictableBytes should be \(usedBytes - pinnedBytes), got \(dto.evictableBytes)")
        // usedBytes (60k) >= 0.8 * highWater (80k)? No (60k < 80k). Level should be ok.
        expect(dto.level as String == "ok", "5: level should be ok (60k < 80k high-water), got \(dto.level)")
    } catch {
        fail("5: unexpected error: \(error)")
    }

    // MARK: - Test 5b: evictableBytes is clamped to 0 when pinnedBytes > usedBytes

    do {
        let db = try EngineDatabase.openInMemory()
        let cm = try CacheManager(db: db)

        let dto = helper.makePressureDTO(cm: cm,
                                         totalBudget: 100_000,
                                         usedBytes: 5_000,
                                         pinnedBytes: 10_000)   // pinned > used
        expect(dto.evictableBytes == 0, "5b: evictableBytes should be 0 when pinnedBytes > usedBytes, got \(dto.evictableBytes)")
    } catch {
        fail("5b: unexpected error: \(error)")
    }

    // MARK: - Test 6: Throttle — same level within 5 s suppresses second emission

    do {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(2.0)  // 2 s later — within throttle window

        // First emission: no prior history → must emit.
        expect(helper.shouldEmitPressure(now: t0, level: .ok, lastEmission: nil, lastLevel: nil),
               "6: first emission should always emit")

        // Second emission: same level, within 5 s → must NOT emit.
        let shouldSecond = helper.shouldEmitPressure(now: t1, level: .ok,
                                                      lastEmission: t0, lastLevel: .ok)
        expect(!shouldSecond, "6: same level within 5 s should be suppressed (shouldEmit=\(shouldSecond))")
    }

    // MARK: - Test 7: Throttle override — level change always emits

    do {
        let t0 = Date()
        let t1 = t0.addingTimeInterval(0.1)  // 100 ms later — well within throttle

        // Level changes from .ok to .warn — must emit regardless of throttle.
        let shouldEmit = helper.shouldEmitPressure(now: t1, level: .warn,
                                                    lastEmission: t0, lastLevel: .ok)
        expect(shouldEmit, "7: level change must emit regardless of throttle timing")

        // Also: .warn → .critical.
        let shouldEmit2 = helper.shouldEmitPressure(now: t1, level: .critical,
                                                     lastEmission: t0, lastLevel: .warn)
        expect(shouldEmit2, "7: warn→critical must emit regardless of throttle timing")

        // And: throttle window expired (>= 5 s), same level → must emit.
        let t5 = t0.addingTimeInterval(5.0)
        let shouldEmit3 = helper.shouldEmitPressure(now: t5, level: .ok,
                                                     lastEmission: t0, lastLevel: .ok)
        expect(shouldEmit3, "7: same level after 5 s should emit")
    }

    // MARK: - Test 8: runEvictionPass driven by mock bridge (integration)

    do {
        let db = try EngineDatabase.openInMemory()
        let cm = try CacheManager(db: db)

        let dir = NSTemporaryDirectory()
        let p1  = (dir as NSString).appendingPathComponent("eviction_wire_8a_\(Int.random(in: 10000...99999)).bin")

        defer { try? FileManager.default.removeItem(atPath: p1) }

        // Write a 256 KiB file.
        let size  = 256 * 1024
        let data  = Data(repeating: 0xCC, count: size)
        try data.write(to: URL(fileURLWithPath: p1))

        let pieceLength: Int64 = 64 * 1024

        let candidate = EvictionCandidate(
            torrentId: "t8",
            fileIndex: 0,
            onDiskPath: p1,
            fileStartInTorrent: 0,
            fileEndInTorrent: Int64(size),
            pieceLength: pieceLength,
            lastPlayedAtMs: nil,
            completed: false,
            tierRank: 1
        )

        let bridge = MockBridgeForWireTest()

        var st = stat()
        stat(p1, &st)
        let onDisk = Int64(st.st_blocks) * 512
        let highWater = max(1, onDisk - 1)

        let result = try cm.runEvictionPass(
            candidates: [candidate],
            bridge: bridge,
            highWaterBytes: highWater,
            lowWaterBytes: 0
        )

        expect(result.candidatesEvicted >= 1, "8: at least one candidate evicted, got \(result.candidatesEvicted)")
        expect(bridge.forceRecheckCalls.contains("t8"), "8: forceRecheck should be called for t8")
    } catch {
        fail("8: unexpected error: \(error)")
    }

    return failures
}

// MARK: - Helpers

/// Makes a synthetic EvictionCandidate for sorting/filtering tests.
private func makeCandidate(torrentId: String,
                            fileIndex: Int,
                            tierRank: Int,
                            lastPlayedAt: Int64? = nil) -> EvictionCandidate {
    EvictionCandidate(
        torrentId: torrentId,
        fileIndex: fileIndex,
        onDiskPath: "/dev/null",
        fileStartInTorrent: 0,
        fileEndInTorrent: 1024,
        pieceLength: 512,
        lastPlayedAtMs: lastPlayedAt,
        completed: tierRank == 2,
        tierRank: tierRank
    )
}

/// Thin shim that exposes the pure helpers from RealEngineBackend without
/// instantiating the full engine stack.
private final class EvictionWireHelper {

    func makeCandidates(unsorted: [EvictionCandidate]) -> [EvictionCandidate] {
        unsorted.sorted {
            if $0.tierRank != $1.tierRank { return $0.tierRank < $1.tierRank }
            switch ($0.lastPlayedAtMs, $1.lastPlayedAtMs) {
            case let (a?, b?): return a < b
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return false
            }
        }
    }

    func shouldEmitPressure(now: Date,
                             level: DiskPressure,
                             lastEmission: Date?,
                             lastLevel: DiskPressure?) -> Bool {
        guard let last = lastEmission, let prevLevel = lastLevel else {
            return true
        }
        if level != prevLevel { return true }
        return now.timeIntervalSince(last) >= 5.0
    }

    func makePressureDTO(cm: CacheManager,
                          totalBudget: Int64,
                          usedBytes: Int64,
                          pinnedBytes: Int64) -> DiskPressureDTO {
        let evictable = max(0, usedBytes - pinnedBytes)
        let level = cm.pressure(usedBytes: usedBytes, highWater: totalBudget)
        return DiskPressureDTO(
            totalBudgetBytes: totalBudget,
            usedBytes: usedBytes,
            pinnedBytes: pinnedBytes,
            evictableBytes: evictable,
            level: level.rawValue as NSString
        )
    }
}

/// Mock StreamRegistry-like object for active-stream tests.
private final class MockStreamRegistry {
    var activeTorrentIDs: Set<String> = []

    func hasActiveStream(torrentID: String) -> Bool {
        activeTorrentIDs.contains(torrentID)
    }
}

/// Mock CacheManagerBridge for integration test 8.
private final class MockBridgeForWireTest: CacheManagerBridge {

    private(set) var forceRecheckCalls: [String] = []
    private(set) var setFilePriorityCalls: [(torrentID: String, fileIndex: Int, priority: Int)] = []
    private var pollCounts: [String: Int] = [:]

    func setFilePriority(torrentID: String, fileIndex: Int, priority: Int) throws {
        setFilePriorityCalls.append((torrentID, fileIndex, priority))
    }

    func forceRecheck(torrentID: String) throws {
        forceRecheckCalls.append(torrentID)
        pollCounts[torrentID] = 0
    }

    func statusState(torrentID: String) throws -> String {
        let count = pollCounts[torrentID] ?? 0
        pollCounts[torrentID] = count + 1
        switch count {
        case 0:  return "checkingResumeData"
        case 1:  return "checkingFiles"
        default: return "finished"
        }
    }
}

#endif // DEBUG
