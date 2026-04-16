import CoreMedia
import XCTest
@testable import SubtitleDomain

final class SubtitleCueTests: XCTestCase {

    func test_equatable_sameFieldsCompareEqual() {
        let a = SubtitleCue(
            index: 1,
            startTime: CMTime(value: 1000, timescale: 1000),
            endTime: CMTime(value: 2000, timescale: 1000),
            text: "Hello"
        )
        let b = SubtitleCue(
            index: 1,
            startTime: CMTime(value: 1000, timescale: 1000),
            endTime: CMTime(value: 2000, timescale: 1000),
            text: "Hello"
        )
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentTextComparesUnequal() {
        let a = SubtitleCue(
            index: 1,
            startTime: CMTime(value: 1000, timescale: 1000),
            endTime: CMTime(value: 2000, timescale: 1000),
            text: "Hello"
        )
        let b = SubtitleCue(
            index: 1,
            startTime: CMTime(value: 1000, timescale: 1000),
            endTime: CMTime(value: 2000, timescale: 1000),
            text: "Goodbye"
        )
        XCTAssertNotEqual(a, b)
    }

    func test_cmtimeOrdering_startBeforeEnd() {
        let cue = SubtitleCue(
            index: 1,
            startTime: CMTime(value: 1000, timescale: 1000),
            endTime: CMTime(value: 2000, timescale: 1000),
            text: "ok"
        )
        XCTAssertLessThan(cue.startTime, cue.endTime)
    }

    func test_sendable_crossActor() async {
        // Regression guard for `Sendable` conformance: if this compiles
        // with Swift 6 strict concurrency, the type is Sendable.
        let cue = SubtitleCue(
            index: 1,
            startTime: .zero,
            endTime: CMTime(value: 1000, timescale: 1000),
            text: "a"
        )
        let copy = await Task.detached { cue }.value
        XCTAssertEqual(cue, copy)
    }
}
