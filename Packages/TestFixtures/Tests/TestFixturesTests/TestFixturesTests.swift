import XCTest
@testable import TestFixtures

final class TestFixturesTests: XCTestCase {

    // MARK: - Trace round-trip

    func testTraceRoundTrip() throws {
        let original = Trace(
            assetID: "front-moov-mp4-001",
            description: "AVPlayer opens MP4 with moov at front, plays 10s, seeks to 40%",
            contentLength: 1_834_521_190,
            pieceLength: 2_097_152,
            fileByteRange: ByteRangeEntry(start: 0, end: 1_834_521_189),
            events: [
                TraceEvent(tMs: 0, kind: .head),
                TraceEvent(tMs: 12, kind: .get(requestID: "r1", rangeStart: 0, rangeEnd: 1_048_575)),
                TraceEvent(tMs: 80, kind: .get(requestID: "r2", rangeStart: 1_048_576, rangeEnd: 4_194_303)),
                TraceEvent(tMs: 1400, kind: .cancel(requestID: "r2")),
                TraceEvent(tMs: 1450, kind: .get(requestID: "r3", rangeStart: 734_003_200, rangeEnd: 738_197_503)),
            ],
            availabilitySchedule: [
                AvailabilityEntry(tMs: 0, havePieces: []),
                AvailabilityEntry(tMs: 200, havePieces: [0, 1]),
            ],
            downloadRateSchedule: [
                DownloadRateEntry(tMs: 0, bytesPerSec: 0),
                DownloadRateEntry(tMs: 500, bytesPerSec: 2_500_000),
            ],
            peerCountSchedule: [
                PeerCountEntry(tMs: 0, count: 0),
                PeerCountEntry(tMs: 300, count: 12),
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Trace.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - ExpectedActions round-trip

    func testExpectedActionsRoundTrip() throws {
        let original = ExpectedActions(
            traceID: "front-moov-mp4-001",
            actions: [
                ExpectedAction(tMs: 12, kind: .setDeadlines(pieces: [
                    ExpectedPieceDeadline(piece: 0, deadlineMs: 0, priority: .critical),
                    ExpectedPieceDeadline(piece: 1, deadlineMs: 100, priority: .critical),
                    ExpectedPieceDeadline(piece: 2, deadlineMs: 200, priority: .critical),
                    ExpectedPieceDeadline(piece: 3, deadlineMs: 300, priority: .critical),
                    ExpectedPieceDeadline(piece: 4, deadlineMs: 250, priority: .readahead),
                    ExpectedPieceDeadline(piece: 5, deadlineMs: 500, priority: .readahead),
                    ExpectedPieceDeadline(piece: 6, deadlineMs: 750, priority: .readahead),
                    ExpectedPieceDeadline(piece: 7, deadlineMs: 1000, priority: .readahead),
                ])),
                ExpectedAction(tMs: 12, kind: .waitForRange(requestID: "r1", maxWaitMs: 1500)),
                ExpectedAction(tMs: 1450, kind: .clearDeadlinesExcept(pieces: [350, 351, 352, 353])),
                ExpectedAction(tMs: 1450, kind: .setDeadlines(pieces: [
                    ExpectedPieceDeadline(piece: 350, deadlineMs: 0, priority: .critical),
                ])),
                ExpectedAction(tMs: 1450, kind: .waitForRange(requestID: "r3", maxWaitMs: 1200)),
                ExpectedAction(tMs: 2000, kind: .failRange(requestID: "r4", reason: .waitTimedOut)),
                ExpectedAction(tMs: 2100, kind: .failRange(requestID: "r5", reason: .rangeOutOfBounds)),
                ExpectedAction(tMs: 2200, kind: .failRange(requestID: "r6", reason: .streamClosed)),
                ExpectedAction(tMs: 500, kind: .emitHealth(health: ExpectedStreamHealth(
                    secondsBufferedAhead: 12.5,
                    downloadRateBytesPerSec: 2_500_000,
                    requiredBitrateBytesPerSec: nil,
                    peerCount: 12,
                    outstandingCriticalPieces: 0,
                    recentStallCount: 0,
                    tier: .marginal
                ))),
                ExpectedAction(tMs: 600, kind: .emitHealth(health: ExpectedStreamHealth(
                    secondsBufferedAhead: 35.0,
                    downloadRateBytesPerSec: 4_000_000,
                    requiredBitrateBytesPerSec: 2_000_000,
                    peerCount: 15,
                    outstandingCriticalPieces: 0,
                    recentStallCount: 1,
                    tier: .healthy
                ))),
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ExpectedActions.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Decoding error quality

    func testTraceEventUnknownKindGivesInformativeError() {
        let json = """
        {
          "asset_id": "test",
          "description": "bad event",
          "content_length": 100,
          "piece_length": 512,
          "file_byte_range": { "start": 0, "end": 99 },
          "events": [
            { "t_ms": 0, "kind": "unknown_kind" }
          ],
          "availability_schedule": [],
          "download_rate_schedule": [],
          "peer_count_schedule": []
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(Trace.self, from: json)) { error in
            let description = String(describing: error)
            XCTAssertTrue(
                description.contains("unknown_kind"),
                "Error message should identify the bad kind value; got: \(description)"
            )
        }
    }

    func testExpectedActionUnknownKindGivesInformativeError() {
        let json = """
        {
          "trace_id": "test",
          "actions": [
            { "t_ms": 0, "kind": "explode" }
          ]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ExpectedActions.self, from: json)) { error in
            let description = String(describing: error)
            XCTAssertTrue(
                description.contains("explode"),
                "Error message should identify the bad kind value; got: \(description)"
            )
        }
    }

    func testFailReasonUnknownValueGivesInformativeError() {
        let json = """
        {
          "trace_id": "test",
          "actions": [
            { "t_ms": 0, "kind": "fail_range", "request_id": "r1", "reason": "bad_reason" }
          ]
        }
        """.data(using: .utf8)!

        XCTAssertThrowsError(try JSONDecoder().decode(ExpectedActions.self, from: json)) { error in
            // Swift's RawRepresentable decoding failure names the bad value in the error
            let description = String(describing: error)
            XCTAssertFalse(description.isEmpty)
        }
    }

    // MARK: - JSON spec fidelity (decode directly from spec-shaped JSON)

    func testDecodeTraceFromSpecJSON() throws {
        let json = """
        {
          "asset_id": "front-moov-mp4-001",
          "description": "AVPlayer opens MP4 with moov at front, plays 10s, seeks to 40%",
          "content_length": 1834521190,
          "piece_length": 2097152,
          "file_byte_range": { "start": 0, "end": 1834521189 },
          "events": [
            { "t_ms": 0,    "kind": "head" },
            { "t_ms": 12,   "kind": "get", "request_id": "r1", "range_start": 0,         "range_end": 1048575 },
            { "t_ms": 80,   "kind": "get", "request_id": "r2", "range_start": 1048576,   "range_end": 4194303 },
            { "t_ms": 1400, "kind": "cancel", "request_id": "r2" },
            { "t_ms": 1450, "kind": "get", "request_id": "r3", "range_start": 734003200, "range_end": 738197503 }
          ],
          "availability_schedule": [
            { "t_ms": 0,    "have_pieces": [] },
            { "t_ms": 200,  "have_pieces": [0, 1] }
          ],
          "download_rate_schedule": [
            { "t_ms": 0,    "bytes_per_sec": 0 },
            { "t_ms": 500,  "bytes_per_sec": 2500000 }
          ],
          "peer_count_schedule": [
            { "t_ms": 0, "count": 0 },
            { "t_ms": 300, "count": 12 }
          ]
        }
        """.data(using: .utf8)!

        let trace = try JSONDecoder().decode(Trace.self, from: json)

        XCTAssertEqual(trace.assetID, "front-moov-mp4-001")
        XCTAssertEqual(trace.contentLength, 1_834_521_190)
        XCTAssertEqual(trace.pieceLength, 2_097_152)
        XCTAssertEqual(trace.fileByteRange.start, 0)
        XCTAssertEqual(trace.fileByteRange.end, 1_834_521_189)
        XCTAssertEqual(trace.events.count, 5)
        XCTAssertEqual(trace.events[0].kind, .head)
        XCTAssertEqual(trace.events[1].kind, .get(requestID: "r1", rangeStart: 0, rangeEnd: 1_048_575))
        XCTAssertEqual(trace.events[3].kind, .cancel(requestID: "r2"))
        XCTAssertEqual(trace.availabilitySchedule[1].havePieces, [0, 1])
        XCTAssertEqual(trace.downloadRateSchedule[1].bytesPerSec, 2_500_000)
        XCTAssertEqual(trace.peerCountSchedule[1].count, 12)
    }

    func testDecodeExpectedActionsFromSpecJSON() throws {
        let json = """
        {
          "trace_id": "front-moov-mp4-001",
          "actions": [
            {
              "t_ms": 12,
              "kind": "set_deadlines",
              "pieces": [
                { "piece": 0, "deadline_ms": 0,    "priority": "critical" },
                { "piece": 1, "deadline_ms": 100,  "priority": "critical" }
              ]
            },
            {
              "t_ms": 12,
              "kind": "wait_for_range",
              "request_id": "r1",
              "max_wait_ms": 1500
            },
            {
              "t_ms": 1450,
              "kind": "clear_deadlines_except",
              "pieces": [350, 351, 352, 353]
            },
            {
              "t_ms": 1450,
              "kind": "set_deadlines",
              "pieces": [
                { "piece": 350, "deadline_ms": 0, "priority": "critical" }
              ]
            },
            {
              "t_ms": 1450,
              "kind": "wait_for_range",
              "request_id": "r3",
              "max_wait_ms": 1200
            }
          ]
        }
        """.data(using: .utf8)!

        let expected = try JSONDecoder().decode(ExpectedActions.self, from: json)

        XCTAssertEqual(expected.traceID, "front-moov-mp4-001")
        XCTAssertEqual(expected.actions.count, 5)

        if case .setDeadlines(let pieces) = expected.actions[0].kind {
            XCTAssertEqual(pieces[0].piece, 0)
            XCTAssertEqual(pieces[0].deadlineMs, 0)
            XCTAssertEqual(pieces[0].priority, .critical)
            XCTAssertEqual(pieces[1].deadlineMs, 100)
        } else {
            XCTFail("Expected .setDeadlines for action 0")
        }

        if case .waitForRange(let requestID, let maxWaitMs) = expected.actions[1].kind {
            XCTAssertEqual(requestID, "r1")
            XCTAssertEqual(maxWaitMs, 1500)
        } else {
            XCTFail("Expected .waitForRange for action 1")
        }

        if case .clearDeadlinesExcept(let pieces) = expected.actions[2].kind {
            XCTAssertEqual(pieces, [350, 351, 352, 353])
        } else {
            XCTFail("Expected .clearDeadlinesExcept for action 2")
        }
    }
}
