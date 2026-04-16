import Foundation

/// Events that drive the `WatchStateMachine`. Mirrors the engine's write
/// triggers (stream open, periodic progress, stream close, manual toggles).
public enum WatchEvent: Equatable, Sendable {
    case streamOpened(totalBytes: Int64)
    case progress(bytes: Int64, totalBytes: Int64)
    case streamClosed(finalBytes: Int64, totalBytes: Int64)
    case manuallyMarkedWatched(at: Date)
    case manuallyMarkedUnwatched
}

/// Pure-function state machine for watch-state transitions. Mirrors the
/// engine's persistence path so the app can preview the result of a user
/// action without round-tripping through the engine. Tests cover the full
/// event × status matrix in `docs/design/watch-state-foundation.md`.
///
/// `now` is injected — never read from the system clock — so all transitions
/// are deterministic. No I/O, no `DispatchQueue`, no randomness.
public enum WatchStateMachine {

    /// Apply `event` to `status`, producing the new status as of `now`.
    public static func apply(_ event: WatchEvent,
                             to status: WatchStatus,
                             now: Date) -> WatchStatus {
        switch (status, event) {

        // MARK: streamOpened

        case let (.unwatched, .streamOpened(total)):
            return .inProgress(progressBytes: 0, totalBytes: total)

        case (.inProgress, .streamOpened):
            return status // idempotent — opening again from in-progress

        case let (.watched(when), .streamOpened(total)):
            return .reWatching(progressBytes: 0,
                               totalBytes: total,
                               previouslyCompletedAt: when)

        case (.reWatching, .streamOpened):
            return status // idempotent

        // MARK: progress

        case let (.unwatched, .progress(bytes, total)):
            return .inProgress(progressBytes: bytes, totalBytes: total)

        case let (.inProgress(p, _), .progress(bytes, total)):
            return .inProgress(progressBytes: max(p, bytes), totalBytes: total)

        case let (.watched(when), .progress(bytes, total)):
            // Invariant: progress without an opened stream is unexpected.
            // Defensive: treat as the start of a re-watch.
            return .reWatching(progressBytes: bytes,
                               totalBytes: total,
                               previouslyCompletedAt: when)

        case let (.reWatching(p, _, when), .progress(bytes, total)):
            return .reWatching(progressBytes: max(p, bytes),
                               totalBytes: total,
                               previouslyCompletedAt: when)

        // MARK: streamClosed

        case let (.unwatched, .streamClosed(bytes, total)):
            if bytes == 0 { return .unwatched }
            if WatchThreshold.isComplete(progress: bytes, total: total) {
                return .watched(completedAt: now)
            }
            return .inProgress(progressBytes: bytes, totalBytes: total)

        case let (.inProgress(p, _), .streamClosed(bytes, total)):
            if WatchThreshold.isComplete(progress: bytes, total: total) {
                return .watched(completedAt: now)
            }
            return .inProgress(progressBytes: max(p, bytes), totalBytes: total)

        case let (.watched(when), .streamClosed(bytes, _)):
            // Closed without progress — preserve original watch.
            if bytes == 0 { return .watched(completedAt: when) }
            return .watched(completedAt: when) // defensive idempotence

        case let (.reWatching(p, _, when), .streamClosed(bytes, total)):
            if WatchThreshold.isComplete(progress: bytes, total: total) {
                // Re-completion — `completed_at` updates per A26 most-recent-wins.
                return .watched(completedAt: now)
            }
            return .reWatching(progressBytes: max(p, bytes),
                               totalBytes: total,
                               previouslyCompletedAt: when)

        // MARK: manuallyMarkedWatched

        case (.unwatched, .manuallyMarkedWatched(let now)),
             (.inProgress, .manuallyMarkedWatched(let now)):
            return .watched(completedAt: now)

        case let (.watched(when), .manuallyMarkedWatched):
            return .watched(completedAt: when) // idempotent — keeps original W

        case (.reWatching, .manuallyMarkedWatched(let now)):
            return .watched(completedAt: now) // re-stamp per design § Notes

        // MARK: manuallyMarkedUnwatched

        case (_, .manuallyMarkedUnwatched):
            return .unwatched
        }
    }
}
