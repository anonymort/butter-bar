import XCTest
@testable import PlannerCore

/// Tests for FakeTorrentSession using the example schedules from spec 04 § Trace format.
final class FakeTorrentSessionTests: XCTestCase {

    // MARK: - Shared fixture

    /// Builds the example session from spec 04 § Trace format.
    private func makeSession() -> FakeTorrentSession {
        FakeTorrentSession(
            pieceLength: 2_097_152,  // 2 MiB
            fileByteRange: ByteRange(start: 0, end: 1_834_521_189),
            availabilitySchedule: [
                AvailabilityEntry(tMs: 0,   havePieces: []),
                AvailabilityEntry(tMs: 200, havePieces: [0, 1]),
                AvailabilityEntry(tMs: 600, havePieces: [2, 3, 4]),
            ],
            downloadRateSchedule: [
                ScalarEntry(tMs: 0,   value: 0),
                ScalarEntry(tMs: 500, value: 2_500_000),
            ],
            peerCountSchedule: [
                ScalarEntry(tMs: 0,   value: 0),
                ScalarEntry(tMs: 300, value: 12),
            ]
        )
    }

    // MARK: - Static metadata

    func testPieceLength() {
        XCTAssertEqual(makeSession().pieceLength, 2_097_152)
    }

    func testFileByteRange() {
        let session = makeSession()
        XCTAssertEqual(session.fileByteRange.start, 0)
        XCTAssertEqual(session.fileByteRange.end, 1_834_521_189)
    }

    // MARK: - Availability (havePieces) — cumulative additions

    func testInitialStateAtT0_noPieces() {
        // At t=0 the schedule entry has an empty have_pieces list.
        let session = makeSession()
        XCTAssertTrue(session.havePieces().isEmpty)
    }

    func testBeforeFirstEntry_noPieces() {
        // At t=100, which is before the t=200 entry, no pieces should be available.
        let session = makeSession()
        session.step(to: 100)
        XCTAssertTrue(session.havePieces().isEmpty)
    }

    func testAtT200_pieces0And1Appear() {
        let session = makeSession()
        session.step(to: 200)
        XCTAssertEqual(session.havePieces(), BitSet([0, 1]))
    }

    func testBetweenEntries_previousPiecesRetained() {
        // At t=400 (between the 200 and 600 entries), only pieces 0 and 1 exist.
        let session = makeSession()
        session.step(to: 400)
        XCTAssertEqual(session.havePieces(), BitSet([0, 1]))
    }

    func testAtT600_pieces0Through4Present() {
        // Cumulative: pieces from t=200 plus pieces from t=600.
        let session = makeSession()
        session.step(to: 600)
        XCTAssertEqual(session.havePieces(), BitSet([0, 1, 2, 3, 4]))
    }

    func testBeyondLastEntry_allPiecesRetained() {
        // Stepping past all schedule entries should not drop pieces.
        let session = makeSession()
        session.step(to: 9_999)
        XCTAssertEqual(session.havePieces(), BitSet([0, 1, 2, 3, 4]))
    }

    func testStepMultipleTimes_accumulatesCorrectly() {
        // Multiple small steps should yield the same result as one large step.
        let session = makeSession()
        session.step(to: 100)
        session.step(to: 300)
        session.step(to: 600)
        XCTAssertEqual(session.havePieces(), BitSet([0, 1, 2, 3, 4]))
    }

    func testStepBackwardIsNoOp() {
        // Stepping backward must not lose pieces.
        let session = makeSession()
        session.step(to: 600)
        let piecesAfterForward = session.havePieces()
        session.step(to: 100)  // no-op
        XCTAssertEqual(session.havePieces(), piecesAfterForward)
    }

    // MARK: - Download rate schedule

    func testDownloadRate_beforeFirstEntry_isZero() {
        // The only entry at or before t=0 has bytes_per_sec = 0.
        let session = makeSession()
        XCTAssertEqual(session.downloadRateBytesPerSec(), 0)
    }

    func testDownloadRate_atT499_stillZero() {
        let session = makeSession()
        session.step(to: 499)
        XCTAssertEqual(session.downloadRateBytesPerSec(), 0)
    }

    func testDownloadRate_atT500_jumpsTo2_5MB() {
        let session = makeSession()
        session.step(to: 500)
        XCTAssertEqual(session.downloadRateBytesPerSec(), 2_500_000)
    }

    func testDownloadRate_pastLastEntry_holdsAtLastValue() {
        let session = makeSession()
        session.step(to: 10_000)
        XCTAssertEqual(session.downloadRateBytesPerSec(), 2_500_000)
    }

    // MARK: - Peer count schedule

    func testPeerCount_atT0_isZero() {
        XCTAssertEqual(makeSession().peerCount(), 0)
    }

    func testPeerCount_atT299_isZero() {
        let session = makeSession()
        session.step(to: 299)
        XCTAssertEqual(session.peerCount(), 0)
    }

    func testPeerCount_atT300_is12() {
        let session = makeSession()
        session.step(to: 300)
        XCTAssertEqual(session.peerCount(), 12)
    }

    func testPeerCount_pastLastEntry_holdsAt12() {
        let session = makeSession()
        session.step(to: 5_000)
        XCTAssertEqual(session.peerCount(), 12)
    }

    // MARK: - Cross-schedule coherence

    func testAllFieldsAtT600() {
        // At t=600: all five pieces present, rate = 2.5 MB/s, peers = 12.
        let session = makeSession()
        session.step(to: 600)
        XCTAssertEqual(session.havePieces(), BitSet([0, 1, 2, 3, 4]))
        XCTAssertEqual(session.downloadRateBytesPerSec(), 2_500_000)
        XCTAssertEqual(session.peerCount(), 12)
    }

    func testAllFieldsAtT250() {
        // At t=250: pieces 0 & 1 available, rate = 0 (still before 500 ms entry), peers = 0 (before 300 ms entry).
        let session = makeSession()
        session.step(to: 250)
        XCTAssertEqual(session.havePieces(), BitSet([0, 1]))
        XCTAssertEqual(session.downloadRateBytesPerSec(), 0)
        XCTAssertEqual(session.peerCount(), 0)
    }

    func testAllFieldsAtT350() {
        // At t=350: pieces 0 & 1 available, rate = 0 (before 500 ms), peers = 12 (after 300 ms).
        let session = makeSession()
        session.step(to: 350)
        XCTAssertEqual(session.havePieces(), BitSet([0, 1]))
        XCTAssertEqual(session.downloadRateBytesPerSec(), 0)
        XCTAssertEqual(session.peerCount(), 12)
    }
}
