import XCTest
import EngineInterface
import LibraryDomain
@testable import ButterBar

/// Covers the seven cases enumerated in
/// `docs/design/player-state-foundation.md § Resume-prompt seam tests`.
///
/// `ResumePromptDecision.shouldOffer(...)` returns `true` iff:
///   - `watchStatus ∈ {.inProgress, .reWatching}`, AND
///   - `descriptor.resumeByteOffset > 0`.
/// All other combinations are `false`. Disagreement combinations
/// (matrix invariant violations) are logged but never crash.
final class ResumePromptDecisionTests: XCTestCase {

    // MARK: - Fixtures

    private func descriptor(resume: Int64) -> StreamDescriptorDTO {
        StreamDescriptorDTO(
            streamID: "test-stream" as NSString,
            loopbackURL: "http://127.0.0.1:1/stream/test-stream" as NSString,
            contentType: "video/mp4",
            contentLength: 10_000,
            resumeByteOffset: resume
        )
    }

    private let completedAt = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Honest "no prompt" cases

    func test_watched_offset0_returnsFalse() {
        let result = ResumePromptDecision.shouldOffer(
            watchStatus: .watched(completedAt: completedAt),
            descriptor: descriptor(resume: 0)
        )
        XCTAssertFalse(result)
    }

    func test_unwatched_offset0_returnsFalse() {
        let result = ResumePromptDecision.shouldOffer(
            watchStatus: .unwatched,
            descriptor: descriptor(resume: 0)
        )
        XCTAssertFalse(result)
    }

    // MARK: - Honest "offer prompt" cases

    func test_inProgress_offsetGreaterThan0_returnsTrue() {
        let result = ResumePromptDecision.shouldOffer(
            watchStatus: .inProgress(progressBytes: 4_000, totalBytes: 10_000),
            descriptor: descriptor(resume: 4_000)
        )
        XCTAssertTrue(result)
    }

    func test_reWatching_offsetGreaterThan0_returnsTrue() {
        let result = ResumePromptDecision.shouldOffer(
            watchStatus: .reWatching(progressBytes: 2_500,
                                     totalBytes: 10_000,
                                     previouslyCompletedAt: completedAt),
            descriptor: descriptor(resume: 2_500)
        )
        XCTAssertTrue(result)
    }

    // MARK: - Disagreement (invariant violations) — return false, never crash

    func test_inProgress_offset0_returnsFalse_invariantViolation() {
        let result = ResumePromptDecision.shouldOffer(
            watchStatus: .inProgress(progressBytes: 4_000, totalBytes: 10_000),
            descriptor: descriptor(resume: 0)
        )
        XCTAssertFalse(result)
    }

    func test_unwatched_offsetGreaterThan0_returnsFalse_invariantViolation() {
        let result = ResumePromptDecision.shouldOffer(
            watchStatus: .unwatched,
            descriptor: descriptor(resume: 1_500)
        )
        XCTAssertFalse(result)
    }

    func test_watched_offsetGreaterThan0_returnsFalse() {
        // Per design doc: a watched file with a non-zero offset is a re-watch
        // about to start. AVPlayer should start from the beginning, no prompt.
        let result = ResumePromptDecision.shouldOffer(
            watchStatus: .watched(completedAt: completedAt),
            descriptor: descriptor(resume: 1_500)
        )
        XCTAssertFalse(result)
    }
}
