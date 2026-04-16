import CoreMedia
import XCTest
@testable import SubtitleDomain

final class SRTParserTests: XCTestCase {

    // MARK: - Happy paths

    func test_parsesSingleCue() {
        let srt = """
        1
        00:00:01,000 --> 00:00:04,500
        Hello, world.
        """
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].index, 1)
        XCTAssertEqual(cues[0].text, "Hello, world.")
        XCTAssertEqual(cues[0].startTime, CMTime(value: 1_000, timescale: 1_000))
        XCTAssertEqual(cues[0].endTime, CMTime(value: 4_500, timescale: 1_000))
    }

    func test_parsesMultipleCues_preservesOrder() {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        First.

        2
        00:00:03,000 --> 00:00:04,000
        Second.

        3
        00:00:05,000 --> 00:00:06,000
        Third.
        """
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues.map(\.text), ["First.", "Second.", "Third."])
        XCTAssertEqual(cues.map(\.index), [1, 2, 3])
    }

    func test_acceptsCRLFLineEndings() {
        let srt = "1\r\n00:00:01,000 --> 00:00:02,000\r\nLine one.\r\n"
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].text, "Line one.")
    }

    func test_acceptsDotAsMillisecondSeparator() {
        // Some wild SRT files use '.' instead of ',' for ms.
        let srt = """
        1
        00:00:01.500 --> 00:00:02.750
        ok
        """
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues[0].startTime, CMTime(value: 1_500, timescale: 1_000))
        XCTAssertEqual(cues[0].endTime, CMTime(value: 2_750, timescale: 1_000))
    }

    func test_stripsHTMLTags_italicBoldUnderline() {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        <i>italic</i> <b>bold</b> <u>underline</u>
        """
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues[0].text, "italic bold underline")
    }

    func test_decodesHTMLEntities() {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        Tom &amp; Jerry &lt;3 &quot;friends&quot;
        """
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues[0].text, "Tom & Jerry <3 \"friends\"")
    }

    func test_preservesMultiLineCueText() {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        Line A
        Line B
        """
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues[0].text, "Line A\nLine B")
    }

    func test_preservesOverlappingCues_inOrder() {
        // Cue 2 starts before cue 1 ends — perfectly legal in SRT.
        let srt = """
        1
        00:00:01,000 --> 00:00:05,000
        Long cue.

        2
        00:00:03,000 --> 00:00:04,000
        Short cue inside it.
        """
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues.map(\.text), ["Long cue.", "Short cue inside it."])
    }

    func test_preservesTimelineGaps() {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        First.

        2
        00:00:10,000 --> 00:00:11,000
        Much later.
        """
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues[1].startTime, CMTime(value: 10_000, timescale: 1_000))
    }

    // MARK: - Recoverable slips

    func test_missingIndexLine_usesOrdinal() {
        // No index line — block starts directly with the timecode.
        let srt = """
        00:00:01,000 --> 00:00:02,000
        no index

        00:00:03,000 --> 00:00:04,000
        still no index
        """
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues.map(\.index), [1, 2])
        XCTAssertEqual(cues.map(\.text), ["no index", "still no index"])
    }

    func test_extraTrailingBlankLines_absorbed() {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000
        ok



        """
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues.count, 1)
    }

    func test_trailingWhitespaceOnTimecode_tolerated() {
        let srt = "1\n00:00:01,000 --> 00:00:02,000   \nok\n"
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues[0].text, "ok")
    }

    func test_cuePositionHintsAfterTimecode_ignored() {
        // Wild-SRT variant: "--> HH:MM:SS,mmm X1:... X2:... Y1:... Y2:..."
        let srt = """
        1
        00:00:01,000 --> 00:00:02,000 X1:100 X2:200 Y1:100 Y2:200
        ok
        """
        let cues = expectSuccess(SRTParser.parse(srt))
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].endTime, CMTime(value: 2_000, timescale: 1_000))
    }

    // MARK: - Unrecoverable shape

    func test_emptyInput_returnsEmptyArray_notError() {
        let cues = expectSuccess(SRTParser.parse(""))
        XCTAssertTrue(cues.isEmpty)
    }

    func test_whitespaceOnlyInput_returnsEmptyArray() {
        let cues = expectSuccess(SRTParser.parse("   \n\n   \n"))
        XCTAssertTrue(cues.isEmpty)
    }

    func test_badTimecode_returnsDecodingError() {
        let srt = """
        1
        00:00:XX,000 --> 00:00:02,000
        bad
        """
        let result = SRTParser.parse(srt)
        guard case .failure(let err) = result else {
            return XCTFail("expected .failure, got \(result)")
        }
        if case .decoding = err {} else {
            XCTFail("expected .decoding, got \(err)")
        }
    }

    func test_blockWithoutTimecode_returnsDecodingError() {
        let srt = """
        1
        no timecode here
        still no timecode
        """
        let result = SRTParser.parse(srt)
        guard case .failure(let err) = result else {
            return XCTFail("expected .failure, got \(result)")
        }
        if case .decoding = err {} else {
            XCTFail("expected .decoding, got \(err)")
        }
    }

    func test_malformedMinutes_returnsDecodingError() {
        let srt = """
        1
        00:99:01,000 --> 00:00:02,000
        bad minutes
        """
        let result = SRTParser.parse(srt)
        guard case .failure = result else {
            return XCTFail("expected .failure (minutes ≥ 60), got \(result)")
        }
    }

    // MARK: - Helpers

    private func expectSuccess(_ result: Result<[SubtitleCue], SubtitleLoadError>,
                               file: StaticString = #filePath,
                               line: UInt = #line) -> [SubtitleCue] {
        switch result {
        case .success(let cues):
            return cues
        case .failure(let err):
            XCTFail("expected .success, got \(err)", file: file, line: line)
            return []
        }
    }
}
