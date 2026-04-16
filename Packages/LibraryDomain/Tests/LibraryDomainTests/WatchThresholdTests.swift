import XCTest
@testable import LibraryDomain

final class WatchThresholdTests: XCTestCase {

    func testZeroTotalIsNeverComplete() {
        XCTAssertFalse(WatchThreshold.isComplete(progress: 0, total: 0))
        XCTAssertFalse(WatchThreshold.isComplete(progress: 1_000, total: 0))
    }

    func testNegativeTotalIsNeverComplete() {
        XCTAssertFalse(WatchThreshold.isComplete(progress: 100, total: -10))
    }

    func testExactlyAtThresholdIsComplete() {
        // 95 / 100 == 0.95
        XCTAssertTrue(WatchThreshold.isComplete(progress: 95, total: 100))
    }

    func testJustBelowThresholdIsNotComplete() {
        // 94 / 100 == 0.94 < 0.95
        XCTAssertFalse(WatchThreshold.isComplete(progress: 94, total: 100))
    }

    func testWayBelowThreshold() {
        XCTAssertFalse(WatchThreshold.isComplete(progress: 0, total: 1_000_000))
        XCTAssertFalse(WatchThreshold.isComplete(progress: 1_000, total: 1_000_000))
    }

    func testFullyComplete() {
        XCTAssertTrue(WatchThreshold.isComplete(progress: 1_000_000, total: 1_000_000))
    }

    func testLargeFileBoundary() {
        // 4 GB file: 0.95 * 4_294_967_296 == 4_080_218_931.2.
        // Integer formula `progress * 100 >= total * 95` is exact: smallest
        // integer that passes is ceil(total * 95 / 100) = 4_080_218_932.
        let total: Int64 = 4_294_967_296
        let boundary: Int64 = (total * 95 + 99) / 100   // ceil division
        XCTAssertTrue(WatchThreshold.isComplete(progress: boundary, total: total))
        XCTAssertFalse(WatchThreshold.isComplete(progress: boundary - 1, total: total))
    }
}
