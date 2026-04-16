import XCTest
@testable import LibraryDomain

/// Covers every cell in the transition matrix in
/// `docs/design/watch-state-foundation.md` § "Transition matrix".
final class WatchStateMachineTests: XCTestCase {

    // MARK: - Fixtures

    private let total: Int64 = 1_000_000_000
    private let now = Date(timeIntervalSince1970: 1_700_000_500)
    private let earlier = Date(timeIntervalSince1970: 1_700_000_100)
    /// 95% of total; threshold per spec 05.
    private var threshold: Int64 { total * 95 / 100 }

    // MARK: - From .unwatched

    func test_unwatched_streamOpened_isInProgressZero() {
        let next = WatchStateMachine.apply(
            .streamOpened(totalBytes: total),
            to: .unwatched,
            now: now
        )
        XCTAssertEqual(next, .inProgress(progressBytes: 0, totalBytes: total))
    }

    func test_unwatched_progress_isInProgressAtBytes() {
        let next = WatchStateMachine.apply(
            .progress(bytes: 100, totalBytes: total),
            to: .unwatched,
            now: now
        )
        XCTAssertEqual(next, .inProgress(progressBytes: 100, totalBytes: total))
    }

    func test_unwatched_streamClosed_zeroBytes_stays() {
        let next = WatchStateMachine.apply(
            .streamClosed(finalBytes: 0, totalBytes: total),
            to: .unwatched,
            now: now
        )
        XCTAssertEqual(next, .unwatched)
    }

    func test_unwatched_streamClosed_belowThreshold_isInProgress() {
        let next = WatchStateMachine.apply(
            .streamClosed(finalBytes: 100, totalBytes: total),
            to: .unwatched,
            now: now
        )
        XCTAssertEqual(next, .inProgress(progressBytes: 100, totalBytes: total))
    }

    func test_unwatched_streamClosed_atThreshold_isWatchedNow() {
        let next = WatchStateMachine.apply(
            .streamClosed(finalBytes: threshold, totalBytes: total),
            to: .unwatched,
            now: now
        )
        XCTAssertEqual(next, .watched(completedAt: now))
    }

    func test_unwatched_manuallyMarkedWatched_isWatchedAtMarkTime() {
        let mark = Date(timeIntervalSince1970: 999)
        let next = WatchStateMachine.apply(
            .manuallyMarkedWatched(at: mark),
            to: .unwatched,
            now: now
        )
        XCTAssertEqual(next, .watched(completedAt: mark))
    }

    func test_unwatched_manuallyMarkedUnwatched_idempotent() {
        let next = WatchStateMachine.apply(
            .manuallyMarkedUnwatched,
            to: .unwatched,
            now: now
        )
        XCTAssertEqual(next, .unwatched)
    }

    // MARK: - From .inProgress

    func test_inProgress_streamOpened_idempotent() {
        let start: WatchStatus = .inProgress(progressBytes: 250, totalBytes: total)
        let next = WatchStateMachine.apply(
            .streamOpened(totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, start)
    }

    func test_inProgress_progress_takesMaxBytes() {
        let start: WatchStatus = .inProgress(progressBytes: 250, totalBytes: total)
        let nextHigher = WatchStateMachine.apply(
            .progress(bytes: 999, totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(nextHigher, .inProgress(progressBytes: 999, totalBytes: total))

        // A late progress event with stale bytes must NOT regress.
        let nextStale = WatchStateMachine.apply(
            .progress(bytes: 100, totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(nextStale, start)
    }

    func test_inProgress_streamClosed_atThreshold_isWatchedNow() {
        let start: WatchStatus = .inProgress(progressBytes: 250, totalBytes: total)
        let next = WatchStateMachine.apply(
            .streamClosed(finalBytes: threshold, totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, .watched(completedAt: now))
    }

    func test_inProgress_streamClosed_belowThreshold_keepsProgressMax() {
        let start: WatchStatus = .inProgress(progressBytes: 500, totalBytes: total)
        let next = WatchStateMachine.apply(
            .streamClosed(finalBytes: 250, totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, .inProgress(progressBytes: 500, totalBytes: total))
    }

    func test_inProgress_manuallyMarkedWatched_isWatchedAtMarkTime() {
        let mark = Date(timeIntervalSince1970: 999)
        let next = WatchStateMachine.apply(
            .manuallyMarkedWatched(at: mark),
            to: .inProgress(progressBytes: 100, totalBytes: total),
            now: now
        )
        XCTAssertEqual(next, .watched(completedAt: mark))
    }

    func test_inProgress_manuallyMarkedUnwatched_isUnwatched() {
        let next = WatchStateMachine.apply(
            .manuallyMarkedUnwatched,
            to: .inProgress(progressBytes: 100, totalBytes: total),
            now: now
        )
        XCTAssertEqual(next, .unwatched)
    }

    // MARK: - From .watched

    func test_watched_streamOpened_isReWatchingZeroPreservingPrevious() {
        let start: WatchStatus = .watched(completedAt: earlier)
        let next = WatchStateMachine.apply(
            .streamOpened(totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, .reWatching(progressBytes: 0,
                                          totalBytes: total,
                                          previouslyCompletedAt: earlier))
    }

    func test_watched_progress_defensivelyEntersReWatching() {
        let start: WatchStatus = .watched(completedAt: earlier)
        let next = WatchStateMachine.apply(
            .progress(bytes: 100, totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, .reWatching(progressBytes: 100,
                                          totalBytes: total,
                                          previouslyCompletedAt: earlier))
    }

    func test_watched_streamClosed_zeroBytes_idempotent() {
        let start: WatchStatus = .watched(completedAt: earlier)
        let next = WatchStateMachine.apply(
            .streamClosed(finalBytes: 0, totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, start)
    }

    func test_watched_manuallyMarkedWatched_keepsOriginalDate() {
        let start: WatchStatus = .watched(completedAt: earlier)
        let later = Date(timeIntervalSince1970: 999_999)
        let next = WatchStateMachine.apply(
            .manuallyMarkedWatched(at: later),
            to: start,
            now: now
        )
        XCTAssertEqual(next, .watched(completedAt: earlier),
                       "manual mark on an already-watched row preserves original W")
    }

    func test_watched_manuallyMarkedUnwatched_isUnwatched() {
        let next = WatchStateMachine.apply(
            .manuallyMarkedUnwatched,
            to: .watched(completedAt: earlier),
            now: now
        )
        XCTAssertEqual(next, .unwatched)
    }

    // MARK: - From .reWatching

    func test_reWatching_streamOpened_idempotent() {
        let start: WatchStatus = .reWatching(progressBytes: 250,
                                              totalBytes: total,
                                              previouslyCompletedAt: earlier)
        let next = WatchStateMachine.apply(
            .streamOpened(totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, start)
    }

    func test_reWatching_progress_takesMaxAndPreservesPrevious() {
        let start: WatchStatus = .reWatching(progressBytes: 250,
                                              totalBytes: total,
                                              previouslyCompletedAt: earlier)
        let next = WatchStateMachine.apply(
            .progress(bytes: 999, totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, .reWatching(progressBytes: 999,
                                          totalBytes: total,
                                          previouslyCompletedAt: earlier))
    }

    func test_reWatching_streamClosed_atThreshold_replacesWWithNow() {
        let start: WatchStatus = .reWatching(progressBytes: 250,
                                              totalBytes: total,
                                              previouslyCompletedAt: earlier)
        let next = WatchStateMachine.apply(
            .streamClosed(finalBytes: threshold, totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, .watched(completedAt: now),
                       "re-completion replaces the completedAt with now (A26 most-recent-wins)")
    }

    func test_reWatching_streamClosed_belowThreshold_persistsRewatch() {
        let start: WatchStatus = .reWatching(progressBytes: 500,
                                              totalBytes: total,
                                              previouslyCompletedAt: earlier)
        let next = WatchStateMachine.apply(
            .streamClosed(finalBytes: 250, totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, .reWatching(progressBytes: 500,
                                          totalBytes: total,
                                          previouslyCompletedAt: earlier))
    }

    func test_reWatching_manuallyMarkedWatched_replacesWWithMarkTime() {
        let start: WatchStatus = .reWatching(progressBytes: 250,
                                              totalBytes: total,
                                              previouslyCompletedAt: earlier)
        let mark = Date(timeIntervalSince1970: 999_999)
        let next = WatchStateMachine.apply(
            .manuallyMarkedWatched(at: mark),
            to: start,
            now: now
        )
        XCTAssertEqual(next, .watched(completedAt: mark),
                       "mark-watched on re-watch re-stamps to the new mark time")
    }

    func test_reWatching_manuallyMarkedUnwatched_isUnwatched() {
        let next = WatchStateMachine.apply(
            .manuallyMarkedUnwatched,
            to: .reWatching(progressBytes: 250,
                            totalBytes: total,
                            previouslyCompletedAt: earlier),
            now: now
        )
        XCTAssertEqual(next, .unwatched)
    }

    // MARK: - Threshold edges

    func test_thresholdEdge_oneByteShortStaysInProgress() {
        let start: WatchStatus = .inProgress(progressBytes: 0, totalBytes: total)
        let next = WatchStateMachine.apply(
            .streamClosed(finalBytes: threshold - 1, totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, .inProgress(progressBytes: threshold - 1, totalBytes: total))
    }

    func test_thresholdEdge_exactlyAtCompletes() {
        let start: WatchStatus = .inProgress(progressBytes: 0, totalBytes: total)
        let next = WatchStateMachine.apply(
            .streamClosed(finalBytes: threshold, totalBytes: total),
            to: start,
            now: now
        )
        XCTAssertEqual(next, .watched(completedAt: now))
    }
}
