import CoreMedia
import Foundation
import SubtitleDomain
import XCTest
@testable import ButterBar

// MARK: - SubtitleControllerTests

/// Unit tests for `SubtitleController`. All tests use in-memory state only —
/// no AVPlayer, no disk I/O from the controller itself.
@MainActor
final class SubtitleControllerTests: XCTestCase {

    // MARK: - Ingest: success path

    func testIngest_validSRT_addsToSessionSidecarsAndTracks() async throws {
        let srt = "1\n00:00:01,000 --> 00:00:03,000\nHello\n"
        let url = try writeTempSRT(content: srt, name: "Movie.en.srt")
        let controller = makeController()

        nonisolated(unsafe) let provider = makeProvider(url: url)
        controller.ingestSidecar(provider)
        // ingestSidecar is async internally — wait for the Task to settle.
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(controller.sessionSidecars.count, 1)
        XCTAssertEqual(controller.tracks.count, 1)
        XCTAssertNil(controller.activeError)
    }

    // MARK: - Ingest: failure path

    func testIngest_badFile_setsActiveError_doesNotAddTrack() async throws {
        let url = URL(fileURLWithPath: "/tmp/missing-\(UUID().uuidString).srt")
        let controller = makeController()

        nonisolated(unsafe) let provider = makeProvider(url: url)
        controller.ingestSidecar(provider)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertNotNil(controller.activeError)
        XCTAssertEqual(controller.tracks.count, 0)
        XCTAssertEqual(controller.sessionSidecars.count, 0)
    }

    // MARK: - Tick: no selection

    func testTick_noSelection_currentCueRemainsNil() {
        let controller = makeController()
        controller.tick(currentTime: CMTime(seconds: 2, preferredTimescale: 600))
        XCTAssertNil(controller.currentCue)
    }

    // MARK: - Tick: sidecar selected — cue lookup

    func testTick_withSidecarSelection_returnsCoveringCue() throws {
        let controller = makeController()
        let cues = [
            SubtitleCue(index: 1, startTime: CMTime(seconds: 1, preferredTimescale: 600), endTime: CMTime(seconds: 3, preferredTimescale: 600), text: "Hello"),
            SubtitleCue(index: 2, startTime: CMTime(seconds: 4, preferredTimescale: 600), endTime: CMTime(seconds: 6, preferredTimescale: 600), text: "Goodbye"),
        ]
        let track = SubtitleTrack(
            id: "sidecar-test",
            source: .sidecar(url: URL(fileURLWithPath: "/tmp/test.srt"), format: .srt, cues: cues),
            language: "en",
            label: "test"
        )
        // Directly set selection to bypass AVPlayer activation.
        controller.selectTrack(track)

        controller.tick(currentTime: CMTime(seconds: 2, preferredTimescale: 600))
        XCTAssertEqual(controller.currentCue?.text, "Hello")

        controller.tick(currentTime: CMTime(seconds: 5, preferredTimescale: 600))
        XCTAssertEqual(controller.currentCue?.text, "Goodbye")
    }

    func testTick_pastEnd_clearsCue() throws {
        let controller = makeController()
        let cues = [
            SubtitleCue(index: 1, startTime: CMTime(seconds: 1, preferredTimescale: 600), endTime: CMTime(seconds: 3, preferredTimescale: 600), text: "Hello"),
        ]
        let track = SubtitleTrack(
            id: "sidecar-test2",
            source: .sidecar(url: URL(fileURLWithPath: "/tmp/test2.srt"), format: .srt, cues: cues),
            language: "en",
            label: "test2"
        )
        controller.selectTrack(track)
        controller.tick(currentTime: CMTime(seconds: 2, preferredTimescale: 600))
        XCTAssertNotNil(controller.currentCue)

        controller.tick(currentTime: CMTime(seconds: 10, preferredTimescale: 600))
        XCTAssertNil(controller.currentCue)
    }

    // MARK: - Preference store interaction

    func testManualSelection_writesPreference() throws {
        let defaults = UserDefaults(suiteName: "SubtitleControllerTests-\(UUID().uuidString)")!
        let store = SubtitlePreferenceStore(defaults: defaults)
        let controller = makeController(store: store)

        let track = makeSidecarTrack(language: "fr")
        controller.selectTrack(track)

        // Sidecar activation is synchronous.
        XCTAssertEqual(store.load(), "fr")
    }

    func testSelectNil_writesOff() throws {
        let defaults = UserDefaults(suiteName: "SubtitleControllerTests-\(UUID().uuidString)")!
        let store = SubtitlePreferenceStore(defaults: defaults)
        let controller = makeController(store: store)

        controller.selectTrack(nil)
        XCTAssertEqual(store.load(), "off")
    }

    func testEmbeddedSelectionFailureClearsSelectionAndSetsError() {
        let controller = makeController()
        let previous = makeSidecarTrack(language: "en")
        let embedded = SubtitleTrack(
            id: "embedded-en",
            source: .embedded(identifier: "en"),
            language: "en",
            label: "English"
        )
        controller._setTracksForTesting([previous, embedded], selection: previous)

        controller.applyEmbeddedSelectionResult(didActivate: false, track: embedded)

        XCTAssertNil(controller.selection)
        XCTAssertEqual(controller.activeError, .systemTrackFailed(reason: "System track activation failed"))
    }

    // MARK: - Auto-pick failure does NOT set activeError

    func testAutoPick_noMatchingTrack_doesNotSetActiveError() async throws {
        let defaults = UserDefaults(suiteName: "SubtitleControllerTests-autoPick-\(UUID().uuidString)")!
        defaults.set("de", forKey: SubtitlePreferenceStore.key)
        let store = SubtitlePreferenceStore(defaults: defaults)
        let controller = makeController(store: store)

        // Give it a sidecar track with no language — resolver will find no match.
        let srt = "1\n00:00:01,000 --> 00:00:03,000\nHello\n"
        let url = try writeTempSRT(content: srt, name: "Movie.srt")  // no lang token
        nonisolated(unsafe) let provider = makeProvider(url: url)
        controller.ingestSidecar(provider)
        try await Task.sleep(for: .milliseconds(200))

        // Auto-pick found no match for "de" → no banner.
        XCTAssertNil(controller.activeError)
        XCTAssertNil(controller.selection)
    }

    // MARK: - Helpers

    private func makeController(store: SubtitlePreferenceStore? = nil) -> SubtitleController {
        let s = store ?? SubtitlePreferenceStore(
            defaults: UserDefaults(suiteName: "SubtitleControllerTests-default-\(UUID().uuidString)")!
        )
        return SubtitleController(preferenceStore: s)
    }

    private func makeSidecarTrack(language: String?) -> SubtitleTrack {
        let cues = [SubtitleCue(index: 1, startTime: .zero, endTime: CMTime(seconds: 10, preferredTimescale: 600), text: "Test")]
        return SubtitleTrack(
            id: "sidecar-\(UUID().uuidString)",
            source: .sidecar(url: URL(fileURLWithPath: "/tmp/test.srt"), format: .srt, cues: cues),
            language: language,
            label: "test"
        )
    }

    private func writeTempSRT(content: String, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeProvider(url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerObject(url as NSURL, visibility: .all)
        return provider
    }
}
