// TorrentAlert.swift is compiled directly into this test target (no module import needed).
// It lives at EngineService/Bridge/TorrentAlert.swift and is referenced via the
// ButterBarTests Sources build phase in project.pbxproj.

import XCTest

final class TorrentAlertParsingTests: XCTestCase {

    // MARK: - piece_finished_alert: dict-based pieceIndex

    func testPieceFinished_readsPieceIndexFromDict() {
        let dict: NSDictionary = [
            "type": "piece_finished_alert",
            "torrentID": "abc-123",
            "message": "piece finished",
            "pieceIndex": NSNumber(value: 42),
        ]
        let alert = TorrentAlert.from(dict)
        guard case .pieceFinished(let tid, let idx) = alert else {
            XCTFail("Expected .pieceFinished, got \(alert)")
            return
        }
        XCTAssertEqual(tid, "abc-123")
        XCTAssertEqual(idx, 42)
    }

    func testPieceFinished_pieceIndexZero() {
        let dict: NSDictionary = [
            "type": "piece_finished_alert",
            "torrentID": "t-zero",
            "message": "piece finished",
            "pieceIndex": NSNumber(value: 0),
        ]
        if case .pieceFinished(_, let idx) = TorrentAlert.from(dict) {
            XCTAssertEqual(idx, 0)
        } else {
            XCTFail("Expected .pieceFinished")
        }
    }

    func testPieceFinished_largeIndex() {
        let dict: NSDictionary = [
            "type": "piece_finished_alert",
            "torrentID": "t-large",
            "message": "piece finished",
            "pieceIndex": NSNumber(value: 99_999),
        ]
        if case .pieceFinished(_, let idx) = TorrentAlert.from(dict) {
            XCTAssertEqual(idx, 99_999)
        } else {
            XCTFail("Expected .pieceFinished")
        }
    }

    func testPieceFinished_missingPieceIndexReturnsNil() {
        // pieceIndex absent — bridge contract violation; keep absence explicit.
        let dict: NSDictionary = [
            "type": "piece_finished_alert",
            "torrentID": "t-missing",
            "message": "piece finished",
        ]
        if case .pieceFinished(_, let idx) = TorrentAlert.from(dict) {
            XCTAssertNil(idx)
        } else {
            XCTFail("Expected .pieceFinished")
        }
    }

    // MARK: - hash_failed_alert: typed pieceIndex

    func testHashFailed_readsPieceIndexFromDict() {
        let dict: NSDictionary = [
            "type": "hash_failed_alert",
            "torrentID": "t-hash",
            "message": "hash failed",
            "pieceIndex": NSNumber(value: 17),
        ]
        let alert = TorrentAlert.from(dict)
        guard case .hashFailed(let tid, let idx) = alert else {
            XCTFail("Expected .hashFailed, got \(alert)")
            return
        }
        XCTAssertEqual(tid, "t-hash")
        XCTAssertEqual(idx, 17)
    }

    func testHashFailed_missingPieceIndexReturnsNil() {
        let dict: NSDictionary = [
            "type": "hash_failed_alert",
            "torrentID": "t-hash-missing",
            "message": "hash failed",
        ]
        if case .hashFailed(_, let idx) = TorrentAlert.from(dict) {
            XCTAssertNil(idx)
        } else {
            XCTFail("Expected .hashFailed")
        }
    }

    // MARK: - Other alert types unaffected

    func testStateChanged_unaffected() {
        let dict: NSDictionary = [
            "type": "state_changed_alert",
            "torrentID": "t-x",
            "message": "downloading",
        ]
        if case .stateChanged(let tid, let state) = TorrentAlert.from(dict) {
            XCTAssertEqual(tid, "t-x")
            XCTAssertEqual(state, "downloading")
        } else {
            XCTFail("Expected .stateChanged")
        }
    }

    func testUnknown_unaffected() {
        let dict: NSDictionary = [
            "type": "some_unknown_alert",
            "message": "whatever",
        ]
        if case .unknown(let type, _) = TorrentAlert.from(dict) {
            XCTAssertEqual(type, "some_unknown_alert")
        } else {
            XCTFail("Expected .unknown")
        }
    }
}
