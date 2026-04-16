import XCTest
import EngineInterface
@testable import LibraryDomain

/// Covers every row in the derivation matrix in
/// `docs/design/watch-state-foundation.md` § "Derivation matrix".
final class WatchStatusDerivationTests: XCTestCase {

    // MARK: - Test fixtures

    private let total: Int64 = 1_000_000_000
    private let watchedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeView(completed: Bool, completedAt: Date?, resume: Int64) -> PlaybackHistorySnapshotView {
        PlaybackHistorySnapshotView(
            resumeByteOffset: resume,
            completed: completed,
            completedAt: completedAt
        )
    }

    // MARK: - Matrix rows

    func test_rowAbsent_isUnwatched() {
        XCTAssertEqual(WatchStatus.from(history: nil, totalBytes: total), .unwatched)
    }

    func test_completedFalse_completedAtNil_resumeZero_isUnwatched() {
        let view = makeView(completed: false, completedAt: nil, resume: 0)
        XCTAssertEqual(WatchStatus.from(snapshot: view, totalBytes: total), .unwatched)
    }

    func test_completedFalse_completedAtNil_resumePositive_isInProgress() {
        let view = makeView(completed: false, completedAt: nil, resume: 250_000_000)
        XCTAssertEqual(
            WatchStatus.from(snapshot: view, totalBytes: total),
            .inProgress(progressBytes: 250_000_000, totalBytes: total)
        )
    }

    func test_completedTrue_completedAtSet_resumeZero_isWatched() {
        let view = makeView(completed: true, completedAt: watchedDate, resume: 0)
        XCTAssertEqual(
            WatchStatus.from(snapshot: view, totalBytes: total),
            .watched(completedAt: watchedDate)
        )
    }

    func test_completedTrue_completedAtSet_resumePositive_isReWatching() {
        let view = makeView(completed: true, completedAt: watchedDate, resume: 100_000_000)
        XCTAssertEqual(
            WatchStatus.from(snapshot: view, totalBytes: total),
            .reWatching(progressBytes: 100_000_000,
                        totalBytes: total,
                        previouslyCompletedAt: watchedDate)
        )
    }

    // MARK: - Invariant violations

    func test_completedTrue_completedAtNil_isWatchedFromEpoch() {
        // Defensive fallback per the design doc — caller logs the violation.
        let view = makeView(completed: true, completedAt: nil, resume: 50_000_000)
        XCTAssertEqual(
            WatchStatus.from(snapshot: view, totalBytes: total),
            .watched(completedAt: Date(timeIntervalSince1970: 0))
        )
    }

    func test_completedFalse_completedAtSet_resumeZero_isUnwatched() {
        // Defensive: stale completedAt is ignored when completed=false.
        let view = makeView(completed: false, completedAt: watchedDate, resume: 0)
        XCTAssertEqual(WatchStatus.from(snapshot: view, totalBytes: total), .unwatched)
    }

    func test_completedFalse_completedAtSet_resumePositive_isInProgress() {
        let view = makeView(completed: false, completedAt: watchedDate, resume: 250_000_000)
        XCTAssertEqual(
            WatchStatus.from(snapshot: view, totalBytes: total),
            .inProgress(progressBytes: 250_000_000, totalBytes: total)
        )
    }

    // MARK: - DTO bridge

    func test_dtoBridge_completedAtRoundTrips() {
        // Mirror what the engine writes: completedAt as unix-ms in NSNumber.
        let dto = PlaybackHistoryDTO(
            torrentID: "ph-bridge",
            fileIndex: 0,
            resumeByteOffset: 0,
            lastPlayedAt: 0,
            totalWatchedSeconds: 0,
            completed: true,
            completedAt: NSNumber(value: 1_700_000_000_000) // ms == 1_700_000_000 s
        )
        let status = WatchStatus.from(history: dto, totalBytes: total)
        guard case .watched(let when) = status else {
            return XCTFail("expected .watched, got \(status)")
        }
        XCTAssertEqual(when.timeIntervalSince1970, 1_700_000_000.0, accuracy: 0.001)
    }
}
