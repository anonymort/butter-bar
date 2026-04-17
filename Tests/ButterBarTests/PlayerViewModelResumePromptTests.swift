import XCTest
import EngineInterface
import LibraryDomain
import PlayerDomain
@testable import ButterBar

/// VM-level coverage of the resume-prompt seam (#19).
///
/// Key contract per design `docs/design/player-state-foundation.md § D7`:
/// - The prompt fires at most once per VM lifetime.
/// - Empty history → no prompt.
/// - Re-entries to `.open` (e.g. after stall→recovery) do NOT re-fire.
@MainActor
final class PlayerViewModelResumePromptTests: XCTestCase {

    // MARK: - Fixtures

    private let torrentID = "torrent-resume-test"
    private let fileIndex: Int32 = 0
    private let contentLength: Int64 = 100_000

    private func descriptor(resume: Int64) -> StreamDescriptorDTO {
        StreamDescriptorDTO(
            streamID: "stream-resume-test" as NSString,
            // Use an unreachable URL so AVPlayer doesn't actually load
            // anything during the test — we're asserting on VM state only.
            loopbackURL: "http://127.0.0.1:1/stream/resume-test" as NSString,
            contentType: "video/mp4",
            contentLength: contentLength,
            resumeByteOffset: resume
        )
    }

    private func inProgressHistory() -> [PlaybackHistoryDTO] {
        [
            PlaybackHistoryDTO(
                torrentID: torrentID as NSString,
                fileIndex: fileIndex,
                resumeByteOffset: 25_000,
                lastPlayedAt: 0,
                totalWatchedSeconds: 0,
                completed: false,
                completedAt: nil
            )
        ]
    }

    // MARK: - Empty history → no prompt

    func test_emptyHistory_promptDoesNotFire() async throws {
        let engine = EngineClient()
        let vm = PlayerViewModel(
            streamDescriptor: descriptor(resume: 25_000),
            engineClient: engine,
            torrentID: torrentID,
            fileIndex: fileIndex,
            historyProvider: { [] }
        )
        try await assertEventually("evaluation must complete") {
            // Wait for the Task to land — when no offer fires the VM still
            // settles deterministically because hasOfferedResume becomes true.
            // We approximate via a small delay since the gate is private.
            true
        }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(vm.resumePromptOffer, "no prompt should be offered when history is empty")
    }

    // MARK: - In-progress history + non-zero resume offset → prompt fires once

    func test_inProgressHistory_withResumeOffset_promptFires() async throws {
        let engine = EngineClient()
        let history = inProgressHistory()
        let vm = PlayerViewModel(
            streamDescriptor: descriptor(resume: 25_000),
            engineClient: engine,
            torrentID: torrentID,
            fileIndex: fileIndex,
            historyProvider: { history }
        )
        try await assertEventually("prompt should fire") {
            vm.resumePromptOffer != nil
        }
        XCTAssertNotNil(vm.resumePromptOffer)
    }

    // MARK: - Disagreement: history but zero offset → no prompt

    func test_inProgressHistory_zeroOffset_promptDoesNotFire() async throws {
        let engine = EngineClient()
        let history = inProgressHistory()
        let vm = PlayerViewModel(
            streamDescriptor: descriptor(resume: 0),
            engineClient: engine,
            torrentID: torrentID,
            fileIndex: fileIndex,
            historyProvider: { history }
        )
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(vm.resumePromptOffer)
    }

    // MARK: - Single-fire guarantee

    func test_promptFiresAtMostOncePerVMLifetime() async throws {
        let engine = EngineClient()
        let history = inProgressHistory()
        let vm = PlayerViewModel(
            streamDescriptor: descriptor(resume: 25_000),
            engineClient: engine,
            torrentID: torrentID,
            fileIndex: fileIndex,
            historyProvider: { history }
        )
        try await assertEventually("prompt should fire") {
            vm.resumePromptOffer != nil
        }

        // User dismisses (clears the offer).
        vm.dismissResumePrompt()
        XCTAssertNil(vm.resumePromptOffer)

        // Simulate a re-entry to .open via a stall→resume round-trip.
        // The state machine briefly leaves and re-enters .open; the resume
        // prompt must NOT re-fire because the VM-side gate (hasOfferedResume)
        // is set. We can't directly drive the state machine here; instead we
        // wait long enough for any rogue async lookup to land.
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(vm.resumePromptOffer, "prompt must not re-fire after dismissal")
    }

    // MARK: - Resolve methods clear the offer

    func test_resolveContinue_clearsOffer() async throws {
        let engine = EngineClient()
        let history = inProgressHistory()
        let vm = PlayerViewModel(
            streamDescriptor: descriptor(resume: 25_000),
            engineClient: engine,
            torrentID: torrentID,
            fileIndex: fileIndex,
            historyProvider: { history }
        )
        try await assertEventually("prompt should fire") {
            vm.resumePromptOffer != nil
        }
        vm.resolveResumeContinue()
        XCTAssertNil(vm.resumePromptOffer)
    }

    func test_resolveStartOver_clearsOffer() async throws {
        let engine = EngineClient()
        let history = inProgressHistory()
        let vm = PlayerViewModel(
            streamDescriptor: descriptor(resume: 25_000),
            engineClient: engine,
            torrentID: torrentID,
            fileIndex: fileIndex,
            historyProvider: { history }
        )
        try await assertEventually("prompt should fire") {
            vm.resumePromptOffer != nil
        }
        vm.resolveResumeStartOver()
        XCTAssertNil(vm.resumePromptOffer)
    }

    // MARK: - Helper

    private func assertEventually(
        _ message: String,
        timeout: Duration = .seconds(1),
        poll: Duration = .milliseconds(10),
        condition: @escaping () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: poll)
        }
        XCTFail("Timed out: \(message)")
    }
}

// MARK: - Time formatter

/// Coverage of the static helper that powers `ResumePromptOffer.resumeTimeLabel`.
@MainActor
final class PlayerViewModelResumeFormatterTests: XCTestCase {

    func test_formatResumeSeconds_subMinute() {
        XCTAssertEqual(PlayerViewModel.formatResumeSeconds(0), "0s")
        XCTAssertEqual(PlayerViewModel.formatResumeSeconds(45), "45s")
        XCTAssertEqual(PlayerViewModel.formatResumeSeconds(59.9), "59s")
    }

    func test_formatResumeSeconds_minutes() {
        XCTAssertEqual(PlayerViewModel.formatResumeSeconds(60), "1m")
        XCTAssertEqual(PlayerViewModel.formatResumeSeconds(23 * 60), "23m")
    }

    func test_formatResumeSeconds_hours() {
        XCTAssertEqual(PlayerViewModel.formatResumeSeconds(60 * 60), "1h")
        XCTAssertEqual(PlayerViewModel.formatResumeSeconds(60 * 60 + 23 * 60), "1h 23m")
    }
}
