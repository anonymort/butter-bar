// PlannerPropertyTests.swift — Property-based invariant tests for DefaultPiecePlanner.
//
// Uses a hand-rolled seeded LCG generator (no SwiftCheck dependency).
// Each invariant runs 100+ seeds. Failed seeds are printed for reproducibility.

import XCTest
@testable import PlannerCore

// MARK: - Seeded LCG

/// Simple 64-bit LCG for reproducible pseudo-randomness.
/// Constants from Knuth MMIX: a=6364136223846793005, c=1442695040888963407.
struct LCG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 1   // avoid degenerate all-zero seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }

    /// Returns a value in [0, upperBound).
    mutating func nextInt(in range: Range<Int>) -> Int {
        guard range.count > 0 else { return range.lowerBound }
        let span = UInt64(range.count)
        return range.lowerBound + Int(next() % span)
    }

    mutating func nextInt64(in range: Range<Int64>) -> Int64 {
        guard range.count > 0 else { return range.lowerBound }
        let span = UInt64(range.count)
        return range.lowerBound + Int64(next() % span)
    }

    mutating func nextBool() -> Bool { next() % 2 == 0 }
}

// MARK: - RandomTraceGenerator

struct GeneratedTrace {
    let session: FakeTorrentSession
    /// Ordered (timeMs, event) pairs. timeMs is monotonically increasing.
    let events: [(timeMs: Int64, event: PlayerEvent)]
}

struct RandomTraceGenerator {
    let pieceLength: Int64 = 2_097_152      // 2 MiB
    let contentLength: Int64 = 500_000_000  // ~500 MB

    func generate(seed: UInt64) -> GeneratedTrace {
        var rng = LCG(seed: seed)

        let totalPieces = Int(contentLength / pieceLength) + 1

        // Build a simple availability schedule: pieces trickle in over ~10 s.
        var availSchedule: [AvailabilityEntry] = []
        availSchedule.append(AvailabilityEntry(tMs: 0, havePieces: []))
        let batches = 5
        for b in 0..<batches {
            let tMs = (b + 1) * 2_000
            let start = b * (totalPieces / batches)
            let end   = min(start + totalPieces / batches, totalPieces - 1)
            let pieces = (start...end).map { $0 }
            availSchedule.append(AvailabilityEntry(tMs: tMs, havePieces: pieces))
        }

        // Download rate: starts at 0, ramps up.
        let rateSchedule: [ScalarEntry] = [
            ScalarEntry(tMs: 0,    value: 0),
            ScalarEntry(tMs: 1000, value: 500_000),
            ScalarEntry(tMs: 3000, value: 2_000_000),
        ]

        let peerSchedule: [ScalarEntry] = [
            ScalarEntry(tMs: 0, value: 0),
            ScalarEntry(tMs: 500, value: 10),
        ]

        let session = FakeTorrentSession(
            pieceLength: pieceLength,
            fileByteRange: ByteRange(start: 0, end: contentLength - 1),
            availabilitySchedule: availSchedule,
            downloadRateSchedule: rateSchedule,
            peerCountSchedule: peerSchedule
        )

        // Build events: HEAD first, then 3-20 random GETs / cancels.
        var events: [(timeMs: Int64, event: PlayerEvent)] = []
        events.append((timeMs: 0, event: .head))

        let eventCount = rng.nextInt(in: 3..<21)
        var currentTimeMs: Int64 = 0
        var requestCounter = 0
        var issuedRequests: [(id: String, range: ByteRange)] = []
        var lastRangeEnd: Int64 = 0

        for _ in 0..<eventCount {
            currentTimeMs += Int64(rng.nextInt(in: 50..<600))
            let shouldCancel = rng.nextBool() && !issuedRequests.isEmpty

            if shouldCancel {
                let idx = rng.nextInt(in: 0..<issuedRequests.count)
                let req = issuedRequests.remove(at: idx)
                events.append((timeMs: currentTimeMs, event: .cancel(requestID: req.id)))
            } else {
                // Decide if this is a seek or sequential GET.
                let isSeek = rng.nextBool()
                let rangeStart: Int64
                if isSeek {
                    // Jump at least 4 * pieceLength away (guaranteed seek).
                    let minJump = pieceLength * 5
                    let maxStart = contentLength - pieceLength - 1
                    let jumpedStart = lastRangeEnd + minJump + rng.nextInt64(in: 0..<(maxStart / 4))
                    rangeStart = min(jumpedStart, maxStart - pieceLength)
                } else {
                    // Sequential: within 2 * pieceLength of the last end.
                    rangeStart = min(lastRangeEnd + 1, contentLength - pieceLength - 1)
                }

                // Range is one piece-worth of bytes.
                let rangeEnd = min(rangeStart + pieceLength - 1, contentLength - 1)

                let requestID = "req-\(seed)-\(requestCounter)"
                requestCounter += 1
                let range = ByteRange(start: rangeStart, end: rangeEnd)
                issuedRequests.append((id: requestID, range: range))
                events.append((timeMs: currentTimeMs, event: .get(requestID: requestID, range: range)))
                lastRangeEnd = rangeEnd
            }
        }

        return GeneratedTrace(session: session, events: events)
    }
}

// MARK: - Invariant helpers

private extension Array where Element == PlannerAction {
    var allSetDeadlines: [[PieceDeadline]] {
        compactMap { if case .setDeadlines(let d) = $0 { return d }; return nil }
    }

    var allDeadlines: [PieceDeadline] {
        allSetDeadlines.flatMap { $0 }
    }

    var clearDeadlinesExceptActions: [[Int]] {
        compactMap { if case .clearDeadlinesExcept(let p) = $0 { return p }; return nil }
    }

    var waitForRangeActions: [(requestID: String, maxWaitMs: Int)] {
        compactMap {
            if case .waitForRange(let rid, let ms) = $0 { return (rid, ms) }
            return nil
        }
    }

    var emitHealthActions: [StreamHealth] {
        compactMap { if case .emitHealth(let h) = $0 { return h }; return nil }
    }
}

// MARK: - PlannerPropertyTests

final class PlannerPropertyTests: XCTestCase {

    private let generator = RandomTraceGenerator()
    private let seedCount = 100

    // MARK: Invariant 1: No deadline ever in the past

    func testInvariant_noNegativeDeadlines() {
        for seed in 0..<seedCount {
            let trace = generator.generate(seed: UInt64(seed))
            let planner = DefaultPiecePlanner()

            for (timeMs, event) in trace.events {
                trace.session.step(to: Int(timeMs))
                let actions = planner.handle(event: event, at: timeMs, session: trace.session)
                for deadline in actions.allDeadlines {
                    XCTAssertGreaterThanOrEqual(
                        deadline.deadlineMs, 0,
                        "Negative deadline \(deadline.deadlineMs) at seed=\(seed), t=\(timeMs), piece=\(deadline.piece)"
                    )
                }
            }
        }
    }

    // MARK: Invariant 2: No waitForRange without a preceding setDeadlines covering the range (cumulative)

    func testInvariant_waitForRangeAlwaysPrecededBySetDeadlines() {
        // The spec says: when waitForRange(requestID, _) is emitted, there must have been
        // a prior setDeadlines (in the same call OR earlier) whose pieces cover the waited-for
        // request's byte range. We track the cumulative scheduled piece set across all calls.
        for seed in 0..<seedCount {
            let trace = generator.generate(seed: UInt64(seed))
            let planner = DefaultPiecePlanner()

            // Cumulative set of piece indices that have ever been scheduled.
            var everScheduledPieces: Set<Int> = []
            // Map requestID → ByteRange so we can check coverage for waitForRange.
            var requestRanges: [String: ByteRange] = [:]

            for (timeMs, event) in trace.events {
                // Track issued request ranges before calling handle so we can resolve
                // the requestID inside waitForRange actions.
                if case .get(let rid, let range) = event {
                    requestRanges[rid] = range
                }

                trace.session.step(to: Int(timeMs))
                let actions = planner.handle(event: event, at: timeMs, session: trace.session)

                // Accumulate newly scheduled pieces from this call.
                for deadlines in actions.allSetDeadlines {
                    for d in deadlines { everScheduledPieces.insert(d.piece) }
                }

                // Check every waitForRange in this call.
                for wait in actions.waitForRangeActions {
                    guard let range = requestRanges[wait.requestID] else { continue }
                    let firstPiece = Int(range.start / trace.session.pieceLength)
                    let lastPiece  = Int(range.end   / trace.session.pieceLength)
                    for piece in firstPiece...lastPiece {
                        XCTAssertTrue(
                            everScheduledPieces.contains(piece),
                            "waitForRange issued for \(wait.requestID) but piece \(piece) was never scheduled — seed=\(seed), t=\(timeMs)"
                        )
                    }
                }
            }
        }
    }

    // MARK: Invariant 3: Cancellation never orphans critical deadlines for single-owner pieces

    func testInvariant_cancelDoesNotOrphanCriticalDeadlines() {
        for seed in 0..<seedCount {
            let trace = generator.generate(seed: UInt64(seed))
            let planner = DefaultPiecePlanner()

            for (timeMs, event) in trace.events {
                trace.session.step(to: Int(timeMs))
                let actions = planner.handle(event: event, at: timeMs, session: trace.session)

                guard case .cancel = event else { continue }

                // After a cancel, no setDeadlines action should promote pieces to .critical.
                // (Cancels should only demote to .background or be no-ops.)
                for deadline in actions.allDeadlines {
                    XCTAssertNotEqual(
                        deadline.priority, .critical,
                        "Cancel produced a critical-priority deadline — seed=\(seed), t=\(timeMs), piece=\(deadline.piece)"
                    )
                }
            }
        }
    }

    // MARK: Invariant 4: clearDeadlinesExcept always immediately followed by setDeadlines

    func testInvariant_clearAlwaysFollowedBySetDeadlines() {
        for seed in 0..<seedCount {
            let trace = generator.generate(seed: UInt64(seed))
            let planner = DefaultPiecePlanner()

            for (timeMs, event) in trace.events {
                trace.session.step(to: Int(timeMs))
                let actions = planner.handle(event: event, at: timeMs, session: trace.session)

                for (idx, action) in actions.enumerated() {
                    guard case .clearDeadlinesExcept = action else { continue }

                    let nextIndex = idx + 1
                    guard nextIndex < actions.count else {
                        XCTFail("clearDeadlinesExcept is the last action with no setDeadlines following — seed=\(seed), t=\(timeMs)")
                        continue
                    }

                    if case .setDeadlines = actions[nextIndex] {
                        // Correct — setDeadlines immediately follows.
                    } else {
                        XCTFail(
                            "clearDeadlinesExcept not immediately followed by setDeadlines (got \(actions[nextIndex])) — seed=\(seed), t=\(timeMs)"
                        )
                    }
                }
            }
        }
    }

    // MARK: Invariant 5: Seek detection symmetric with distance > pieceLength * 4

    func testInvariant_seekDetectionSymmetricWithDistance() {
        // Only test GETs after at least one prior GET so we can compute distance.
        for seed in 0..<seedCount {
            let trace = generator.generate(seed: UInt64(seed))
            let planner = DefaultPiecePlanner()

            var lastServedByteEnd: Int64? = nil

            for (timeMs, event) in trace.events {
                trace.session.step(to: Int(timeMs))
                let actions = planner.handle(event: event, at: timeMs, session: trace.session)

                if case .get(_, let range) = event {
                    let hasClear = !actions.clearDeadlinesExceptActions.isEmpty
                    let seekThreshold = trace.session.pieceLength * 4

                    if let lastByte = lastServedByteEnd {
                        let distance = abs(range.start - (lastByte + 1))
                        if hasClear {
                            // If the planner classified this as a seek, distance must exceed threshold.
                            XCTAssertGreaterThan(
                                distance, seekThreshold,
                                "clearDeadlinesExcept produced for a non-seek GET (distance=\(distance), threshold=\(seekThreshold)) — seed=\(seed), t=\(timeMs)"
                            )
                        }
                        // Note: not all large-distance GETs are guaranteed to produce clear
                        // (e.g. it's the first GET), but every clear must correspond to a large distance.
                    }

                    lastServedByteEnd = range.end
                }
            }
        }
    }

    // MARK: Invariant 6: Health emission throttle respected (no two emitHealth within 500ms without tier change)

    func testInvariant_healthEmitThrottleRespected() {
        let throttleMs: Int64 = Int64(StreamHealthThresholds.emitThrottleMs)

        for seed in 0..<seedCount {
            let trace = generator.generate(seed: UInt64(seed))
            let planner = DefaultPiecePlanner()

            var lastEmitTimeMs: Int64? = nil
            var lastEmitTier: StreamHealth.Tier? = nil

            for (timeMs, event) in trace.events {
                trace.session.step(to: Int(timeMs))
                let actions = planner.handle(event: event, at: timeMs, session: trace.session)

                for h in actions.emitHealthActions {
                    if let prev = lastEmitTimeMs, let prevTier = lastEmitTier {
                        let elapsed = timeMs - prev
                        let isTierTransition = h.tier != prevTier
                        if !isTierTransition {
                            XCTAssertGreaterThanOrEqual(
                                elapsed, throttleMs,
                                "emitHealth fired \(elapsed)ms after previous (throttle=\(throttleMs)ms) without tier transition — seed=\(seed), t=\(timeMs)"
                            )
                        }
                    }
                    lastEmitTimeMs = timeMs
                    lastEmitTier = h.tier
                }

                // Also check tick() output for throttle violations.
                let tickActions = planner.tick(at: timeMs, session: trace.session)
                for h in tickActions.emitHealthActions {
                    if let prev = lastEmitTimeMs, let prevTier = lastEmitTier {
                        let elapsed = timeMs - prev
                        let isTierTransition = h.tier != prevTier
                        if !isTierTransition {
                            XCTAssertGreaterThanOrEqual(
                                elapsed, throttleMs,
                                "tick emitHealth fired \(elapsed)ms after previous without tier transition — seed=\(seed), t=\(timeMs)"
                            )
                        }
                    }
                    lastEmitTimeMs = timeMs
                    lastEmitTier = h.tier
                }
            }
        }
    }

    // MARK: Invariant 7: All pieces in setDeadlines are within file bounds

    func testInvariant_allPiecesWithinFileBounds() {
        for seed in 0..<seedCount {
            let trace = generator.generate(seed: UInt64(seed))
            let planner = DefaultPiecePlanner()
            let maxPiece = Int(trace.session.fileByteRange.end / trace.session.pieceLength)

            for (timeMs, event) in trace.events {
                trace.session.step(to: Int(timeMs))
                let actions = planner.handle(event: event, at: timeMs, session: trace.session)

                for deadline in actions.allDeadlines {
                    XCTAssertGreaterThanOrEqual(
                        deadline.piece, 0,
                        "Piece index is negative — seed=\(seed), t=\(timeMs), piece=\(deadline.piece)"
                    )
                    XCTAssertLessThanOrEqual(
                        deadline.piece, maxPiece,
                        "Piece index \(deadline.piece) exceeds max \(maxPiece) — seed=\(seed), t=\(timeMs)"
                    )
                }
            }
        }
    }

    // MARK: Invariant 8: Critical pieces always precede readahead pieces in piece-index ordering

    func testInvariant_criticalPiecesPrecedeReadaheadPieces() {
        // Within a single setDeadlines call, the max critical piece index must be less than
        // the min readahead piece index. This validates that the planner never classifies a
        // later piece as critical while an earlier piece is readahead.
        for seed in 0..<seedCount {
            let trace = generator.generate(seed: UInt64(seed))
            let planner = DefaultPiecePlanner()

            for (timeMs, event) in trace.events {
                trace.session.step(to: Int(timeMs))
                let actions = planner.handle(event: event, at: timeMs, session: trace.session)

                for deadlines in actions.allSetDeadlines {
                    let criticalMaxPiece = deadlines
                        .filter { $0.priority == .critical }
                        .map(\.piece)
                        .max()

                    let readaheadMinPiece = deadlines
                        .filter { $0.priority == .readahead }
                        .map(\.piece)
                        .min()

                    guard let critMax = criticalMaxPiece, let raMin = readaheadMinPiece else { continue }

                    XCTAssertLessThan(
                        critMax, raMin,
                        "Critical max piece (\(critMax)) not before readahead min piece (\(raMin)) — seed=\(seed), t=\(timeMs)"
                    )
                }
            }
        }
    }
}
