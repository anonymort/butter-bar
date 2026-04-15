// PlannerReplayTests.swift — Fixture-driven deterministic replay tests for DefaultPiecePlanner.
//
// For each of the 4 fixtures in TestFixtures/traces/: loads the trace, runs the planner,
// and asserts the emitted action sequence matches TestFixtures/expected/.
//
// These tests are the primary acceptance gate for T-PLANNER-CORE.

import XCTest
import Foundation
@testable import PlannerCore
import TestFixtures

final class PlannerReplayTests: XCTestCase {

    // MARK: - Fixture replay

    func testFrontMoovMP4() throws {
        try runFixture(named: "front-moov-mp4-001")
    }

    func testBackMoovMP4() throws {
        try runFixture(named: "back-moov-mp4-001")
    }

    func testMkvCues() throws {
        try runFixture(named: "mkv-cues-001")
    }

    func testImmediateSeek() throws {
        try runFixture(named: "immediate-seek-001")
    }

    // MARK: - Core runner

    private func runFixture(named name: String) throws {
        let trace = try loadTrace(named: name)
        let expected = try loadExpected(named: name)

        XCTAssertEqual(trace.assetID, expected.traceID,
                       "Trace assetID must match expected traceID")

        // Build the fake session.
        let session = FakeTorrentSession(
            pieceLength: trace.pieceLength,
            fileByteRange: ByteRange(start: trace.fileByteRange.start, end: trace.fileByteRange.end),
            availabilitySchedule: trace.availabilitySchedule.map {
                AvailabilityEntry(tMs: $0.tMs, havePieces: $0.havePieces)
            },
            downloadRateSchedule: trace.downloadRateSchedule.map {
                ScalarEntry(tMs: $0.tMs, value: $0.bytesPerSec)
            },
            peerCountSchedule: trace.peerCountSchedule.map {
                ScalarEntry(tMs: $0.tMs, value: Int64($0.count))
            }
        )

        let planner = DefaultPiecePlanner()
        var collected: [(tMs: Int, action: PlannerAction)] = []

        for event in trace.events {
            session.step(to: event.tMs)
            let plannerEvent = plannerEvent(from: event)
            let actions = planner.handle(event: plannerEvent, at: Instant(event.tMs), session: session)
            for action in actions {
                collected.append((tMs: event.tMs, action: action))
            }
        }

        // Convert expected actions to PlannerActions for comparison.
        let expectedActions = expected.actions.flatMap { ea -> [(tMs: Int, action: PlannerAction)] in
            guard let pa = plannerAction(from: ea.kind) else { return [] }
            return [(tMs: ea.tMs, action: pa)]
        }

        // Build a readable diff.
        XCTAssertEqual(
            collected.count, expectedActions.count,
            "[\(name)] Action count mismatch.\nActual:\n\(describe(collected))\nExpected:\n\(describe(expectedActions))"
        )

        for (i, (actual, exp)) in zip(collected, expectedActions).enumerated() {
            XCTAssertEqual(actual.tMs, exp.tMs,
                           "[\(name)] Action \(i): timestamp mismatch (\(actual.tMs) vs \(exp.tMs))")
            XCTAssertEqual(actual.action, exp.action,
                           "[\(name)] Action \(i) at t=\(actual.tMs):\nActual:   \(actual.action)\nExpected: \(exp.action)")
        }
    }

    // MARK: - Fixture loading (delegates to TestFixtures.FixtureLoader)

    private func loadTrace(named name: String) throws -> Trace {
        try FixtureLoader.loadTrace(named: name)
    }

    private func loadExpected(named name: String) throws -> ExpectedActions {
        try FixtureLoader.loadExpected(named: name)
    }

    // MARK: - Type mapping: Trace → PlannerCore

    private func plannerEvent(from traceEvent: TraceEvent) -> PlayerEvent {
        switch traceEvent.kind {
        case .head:
            return .head
        case .get(let requestID, let rangeStart, let rangeEnd):
            return .get(requestID: requestID, range: ByteRange(start: rangeStart, end: rangeEnd))
        case .cancel(let requestID):
            return .cancel(requestID: requestID)
        }
    }

    // MARK: - Type mapping: ExpectedActions → PlannerAction

    private func plannerAction(from kind: ExpectedActionKind) -> PlannerAction? {
        switch kind {
        case .setDeadlines(let pieces):
            let pds = pieces.map { p in
                PieceDeadline(
                    piece: p.piece,
                    deadlineMs: p.deadlineMs,
                    priority: mapPriority(p.priority)
                )
            }
            return .setDeadlines(pds)

        case .clearDeadlinesExcept(let pieces):
            return .clearDeadlinesExcept(pieces: pieces)

        case .waitForRange(let requestID, let maxWaitMs):
            return .waitForRange(requestID: requestID, maxWaitMs: maxWaitMs)

        case .failRange(let requestID, let reason):
            return .failRange(requestID: requestID, reason: mapFailReason(reason))

        case .emitHealth(let h):
            let tier: StreamHealth.Tier
            switch h.tier {
            case .healthy: tier = .healthy
            case .marginal: tier = .marginal
            case .starving: tier = .starving
            }
            let health = StreamHealth(
                secondsBufferedAhead: h.secondsBufferedAhead,
                downloadRateBytesPerSec: h.downloadRateBytesPerSec,
                requiredBitrateBytesPerSec: h.requiredBitrateBytesPerSec,
                peerCount: h.peerCount,
                outstandingCriticalPieces: h.outstandingCriticalPieces,
                recentStallCount: h.recentStallCount,
                tier: tier
            )
            return .emitHealth(health)
        }
    }

    private func mapPriority(_ p: PiecePriority) -> PieceDeadline.Priority {
        switch p {
        case .critical: return .critical
        case .readahead: return .readahead
        case .background: return .background
        }
    }

    private func mapFailReason(_ r: TestFixtures.FailReason) -> PlannerCore.FailReason {
        switch r {
        case .rangeOutOfBounds: return .rangeOutOfBounds
        case .waitTimedOut: return .waitTimedOut
        case .streamClosed: return .streamClosed
        }
    }

    // MARK: - Debug helper

    private func describe(_ actions: [(tMs: Int, action: PlannerAction)]) -> String {
        actions.map { "  t=\($0.tMs): \($0.action)" }.joined(separator: "\n")
    }
}
