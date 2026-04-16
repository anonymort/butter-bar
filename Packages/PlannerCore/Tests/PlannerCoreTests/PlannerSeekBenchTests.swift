// PlannerSeekBenchTests.swift — XCTest performance bench for DefaultPiecePlanner replay.
//
// Measures wall-clock time for replaying each of the 4 trace fixtures through the planner.
// Catches planner-side regressions (accidental O(N²), allocation storms) without any real
// network dependency.
//
// XCTest stores a baseline with stddev once accepted in Xcode UI. For headless CI the raw
// numbers are captured by PlannerSeekBenchRecorder.
//
// To run: swift test --package-path Packages/PlannerCore --filter PlannerSeekBench

import XCTest
@testable import PlannerCore
import TestFixtures

final class PlannerSeekBenchTests: XCTestCase {

    func test_seekBench_frontMoovMp4() throws {
        let trace = try FixtureLoader.loadTrace(named: "front-moov-mp4-001")
        measure(metrics: [XCTClockMetric()]) {
            replayTrace(trace)
        }
    }

    func test_seekBench_backMoovMp4() throws {
        let trace = try FixtureLoader.loadTrace(named: "back-moov-mp4-001")
        measure(metrics: [XCTClockMetric()]) {
            replayTrace(trace)
        }
    }

    func test_seekBench_mkvCues() throws {
        let trace = try FixtureLoader.loadTrace(named: "mkv-cues-001")
        measure(metrics: [XCTClockMetric()]) {
            replayTrace(trace)
        }
    }

    func test_seekBench_immediateSeek() throws {
        let trace = try FixtureLoader.loadTrace(named: "immediate-seek-001")
        measure(metrics: [XCTClockMetric()]) {
            replayTrace(trace)
        }
    }

    // MARK: - Helpers

    /// Replays all events through a fresh planner + fresh session each time.
    /// Both are created inside the measure block so each iteration is independent.
    private func replayTrace(_ trace: Trace) {
        let session = makeSession(from: trace)
        let planner = DefaultPiecePlanner()
        for event in trace.events {
            session.step(to: event.tMs)
            let plannerEvent = playerEvent(from: event)
            _ = planner.handle(event: plannerEvent, at: Instant(event.tMs), session: session)
        }
    }

    private func makeSession(from trace: Trace) -> FakeTorrentSession {
        FakeTorrentSession(
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
    }

    private func playerEvent(from traceEvent: TraceEvent) -> PlayerEvent {
        switch traceEvent.kind {
        case .head:
            return .head
        case .get(let requestID, let rangeStart, let rangeEnd):
            return .get(requestID: requestID, range: ByteRange(start: rangeStart, end: rangeEnd))
        case .cancel(let requestID):
            return .cancel(requestID: requestID)
        }
    }
}
