import CoreMedia
import Foundation
import SubtitleDomain
import XCTest
@testable import ButterBar

// MARK: - SubtitleIngestorTests

@MainActor
final class SubtitleIngestorTests: XCTestCase {

    // MARK: - Happy path

    func testHappyPath_UTF8_SRT_WithBCP47Filename() async throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,000
        Hello world

        2
        00:00:04,000 --> 00:00:06,000
        Goodbye world
        """
        let url = try writeTempSRT(content: srt, name: "Movie.en.srt")
        nonisolated(unsafe) let provider = makeProvider(url: url)

        let result = await SubtitleIngestor.ingest(from: provider)
        guard case .success(let track) = result else {
            XCTFail("Expected success, got \(result)")
            return
        }
        XCTAssertEqual(track.language, "en")
        XCTAssertTrue(track.id.hasPrefix("sidecar-"))
        guard case .sidecar(_, let format, let cues) = track.source else {
            XCTFail("Expected sidecar source")
            return
        }
        XCTAssertEqual(format, .srt)
        XCTAssertEqual(cues.count, 2)
    }

    func testHappyPath_ptBRLanguage() async throws {
        let srt = "1\n00:00:01,000 --> 00:00:03,000\nOlá\n"
        let url = try writeTempSRT(content: srt, name: "Movie.pt-BR.srt")
        nonisolated(unsafe) let provider = makeProvider(url: url)

        let result = await SubtitleIngestor.ingest(from: provider)
        guard case .success(let track) = result else {
            XCTFail("Expected success")
            return
        }
        XCTAssertEqual(track.language, "pt-BR")
    }

    // MARK: - Unsupported format

    func testNonSRTExtension_returnsUnsupportedFormat() async throws {
        let url = try writeTempFile(content: "WEBVTT\n", name: "Movie.vtt")
        nonisolated(unsafe) let provider = makeProvider(url: url)

        let result = await SubtitleIngestor.ingest(from: provider)
        guard case .failure(let error) = result else {
            XCTFail("Expected failure")
            return
        }
        if case .unsupportedFormat = error { /* correct */ } else {
            XCTFail("Expected .unsupportedFormat, got \(error)")
        }
    }

    // MARK: - File unavailable

    func testMissingFile_returnsFileUnavailable() async {
        // URL that points to nothing on disk.
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).srt")
        nonisolated(unsafe) let provider = makeProvider(url: url)

        let result = await SubtitleIngestor.ingest(from: provider)
        guard case .failure(let error) = result else {
            XCTFail("Expected failure")
            return
        }
        if case .fileUnavailable = error { /* correct */ } else {
            XCTFail("Expected .fileUnavailable, got \(error)")
        }
    }

    // MARK: - Malformed SRT

    func testMalformedSRT_returnsDecoding() async throws {
        let url = try writeTempSRT(content: "THIS IS NOT VALID SRT DATA AT ALL", name: "Bad.en.srt")
        nonisolated(unsafe) let provider = makeProvider(url: url)

        let result = await SubtitleIngestor.ingest(from: provider)
        guard case .failure(let error) = result else {
            XCTFail("Expected failure")
            return
        }
        if case .decoding = error { /* correct */ } else {
            XCTFail("Expected .decoding, got \(error)")
        }
    }

    // MARK: - Language sniffing

    func testSniffLanguage_simpleCode() {
        XCTAssertEqual(SubtitleIngestor.sniffLanguage(from: "Movie.en.srt"), "en")
    }

    func testSniffLanguage_regionTag() {
        XCTAssertEqual(SubtitleIngestor.sniffLanguage(from: "Movie.pt-BR.srt"), "pt-BR")
    }

    func testSniffLanguage_noLanguageToken() {
        XCTAssertNil(SubtitleIngestor.sniffLanguage(from: "Movie.srt"))
    }

    func testSniffLanguage_longPrimaryTag_returnsNil() {
        // "English" has 7 chars — primary subtag must be 2–3 per BCP-47.
        XCTAssertNil(SubtitleIngestor.sniffLanguage(from: "Movie.English.srt"))
    }

    func testSniffLanguage_zhHans() {
        XCTAssertEqual(SubtitleIngestor.sniffLanguage(from: "Movie.zh-Hans.srt"), "zh-Hans")
    }

    func testSniffLanguage_noExtension() {
        XCTAssertNil(SubtitleIngestor.sniffLanguage(from: "Movie"))
    }

    // MARK: - Helpers

    private func writeTempSRT(content: String, name: String) throws -> URL {
        try writeTempFile(content: content, name: name)
    }

    private func writeTempFile(content: String, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Creates an `NSItemProvider` that vends the given URL directly.
    private func makeProvider(url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerObject(url as NSURL, visibility: .all)
        return provider
    }
}
