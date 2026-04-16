import XCTest
@testable import SubtitleDomain

final class SubtitleTextDecoderTests: XCTestCase {

    func test_decodesPlainUTF8() {
        let data = Data("1\n00:00:01,000 --> 00:00:02,000\nhello\n".utf8)
        let result = SubtitleTextDecoder.decode(data)
        guard case .success(let text) = result else {
            return XCTFail("expected .success, got \(result)")
        }
        XCTAssertTrue(text.contains("hello"))
        XCTAssertFalse(text.contains("\u{FEFF}"))
    }

    func test_decodesUTF8WithBOM_stripsBOM() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("hello".utf8))
        let result = SubtitleTextDecoder.decode(data)
        guard case .success(let text) = result else {
            return XCTFail("expected .success, got \(result)")
        }
        XCTAssertEqual(text, "hello", "BOM must be stripped, not kept in the string.")
    }

    func test_decodesWindowsCP1252_smartQuotes() {
        // 0x93 and 0x94 are Windows-1252 smart quotes; not valid UTF-8.
        let bytes: [UInt8] = [0x93, 0x68, 0x69, 0x94] // "hi"
        let data = Data(bytes)
        let result = SubtitleTextDecoder.decode(data)
        guard case .success(let text) = result else {
            return XCTFail("expected .success, got \(result)")
        }
        XCTAssertTrue(text.contains("hi"))
        // The smart quotes should decode to curly-quote characters.
        XCTAssertTrue(text.contains("\u{201C}") || text.contains("\u{201D}"),
                      "CP1252 smart quotes should decode to curly-quote characters.")
    }

    func test_decodesISO8859_1_fallback() {
        // Plain Latin-1 bytes: 0xE9 == 'é'. Invalid in UTF-8, and
        // differently interpreted in CP1252 (0xE9 is also 'é' in both,
        // so this case is really just a sanity check that we don't
        // reject it).
        let bytes: [UInt8] = [0x68, 0xE9, 0x6C, 0x6C, 0x6F] // "héllo"
        let data = Data(bytes)
        let result = SubtitleTextDecoder.decode(data)
        guard case .success(let text) = result else {
            return XCTFail("expected .success, got \(result)")
        }
        XCTAssertTrue(text.contains("é"))
    }

    func test_rejectsBinaryData_decoding() {
        // Lots of NULs and random control bytes.
        let bytes: [UInt8] = Array(repeating: 0x00, count: 20) + [0xFF, 0xFE, 0xFD] + Array(repeating: 0x01, count: 20)
        let data = Data(bytes)
        let result = SubtitleTextDecoder.decode(data)
        guard case .failure(let err) = result else {
            return XCTFail("expected .failure, got \(result)")
        }
        if case .decoding = err {} else {
            XCTFail("expected .decoding, got \(err)")
        }
    }

    func test_emptyData_succeedsAsEmptyString() {
        let result = SubtitleTextDecoder.decode(Data())
        guard case .success(let text) = result else {
            return XCTFail("expected .success, got \(result)")
        }
        XCTAssertEqual(text, "")
    }

    // MARK: - Heuristic unit

    func test_isLikelyText_allASCII_passes() {
        let data = Data("hello world".utf8)
        XCTAssertTrue(SubtitleTextDecoder.isLikelyText(data))
    }

    func test_isLikelyText_mostlyNULs_rejects() {
        let data = Data(Array(repeating: UInt8(0), count: 100))
        XCTAssertFalse(SubtitleTextDecoder.isLikelyText(data))
    }

    func test_hasUTF8BOM_detectsBOM() {
        let withBom = Data([0xEF, 0xBB, 0xBF, 0x61])
        XCTAssertTrue(SubtitleTextDecoder.hasUTF8BOM(withBom))

        let withoutBom = Data("a".utf8)
        XCTAssertFalse(SubtitleTextDecoder.hasUTF8BOM(withoutBom))
    }
}
