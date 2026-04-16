import Foundation
import EngineInterface

/// App-side projection of a file's watch state, derived from a
/// `PlaybackHistoryDTO` row plus the file's `totalBytes`. See spec 05 rev 5,
/// addendum A26, and `docs/design/watch-state-foundation.md`.
public enum WatchStatus: Equatable, Sendable {
    /// File has never been opened, or has been manually marked unwatched.
    case unwatched
    /// File is partway through; never previously completed.
    case inProgress(progressBytes: Int64, totalBytes: Int64)
    /// File was completed; not currently being re-watched.
    /// `completedAt` reflects the most recent completion (most-recent-wins per A26).
    case watched(completedAt: Date)
    /// File was previously completed and is now being watched again.
    /// `previouslyCompletedAt` is the row's `completed_at` snapshot at the
    /// moment this status was derived. May be replaced by `now` if the
    /// re-watch crosses the threshold again.
    case reWatching(progressBytes: Int64,
                    totalBytes: Int64,
                    previouslyCompletedAt: Date)
}

public extension WatchStatus {

    /// Project a row from the engine into a status for the UI.
    /// `nil` row → `.unwatched`. Defensive fallbacks are documented per the
    /// derivation matrix in `docs/design/watch-state-foundation.md`.
    static func from(history: PlaybackHistoryDTO?, totalBytes: Int64) -> WatchStatus {
        guard let dto = history else { return .unwatched }
        return from(snapshot: PlaybackHistorySnapshotView(dto: dto), totalBytes: totalBytes)
    }

    /// Internal derivation entry point used by tests with a synthetic snapshot,
    /// and by the `from(history:totalBytes:)` overload above.
    static func from(snapshot: PlaybackHistorySnapshotView,
                     totalBytes: Int64) -> WatchStatus {
        let progress = snapshot.resumeByteOffset
        switch (snapshot.completed, snapshot.completedAt, progress) {
        case (false, nil, 0):
            return .unwatched
        case (false, nil, let p) where p > 0:
            return .inProgress(progressBytes: p, totalBytes: totalBytes)
        case (true, let when?, 0):
            return .watched(completedAt: when)
        case (true, let when?, let p) where p > 0:
            return .reWatching(progressBytes: p,
                               totalBytes: totalBytes,
                               previouslyCompletedAt: when)
        case (true, nil, _):
            // Invariant violation: completed=true requires completedAt.
            // Defensive: treat as freshly watched at epoch — caller should log.
            return .watched(completedAt: Date(timeIntervalSince1970: 0))
        case (false, _?, let p):
            // Invariant violation: completed=false should clear completedAt.
            // Defensive: ignore the stale timestamp and use byte-offset semantics.
            return p > 0
                ? .inProgress(progressBytes: p, totalBytes: totalBytes)
                : .unwatched
        default:
            return .unwatched
        }
    }
}

/// View struct over the DTO that hides the NSNumber? layer. Lets the
/// derivation function pattern-match on plain Swift types.
public struct PlaybackHistorySnapshotView: Equatable, Sendable {
    public let resumeByteOffset: Int64
    public let completed: Bool
    public let completedAt: Date?

    public init(resumeByteOffset: Int64, completed: Bool, completedAt: Date?) {
        self.resumeByteOffset = resumeByteOffset
        self.completed = completed
        self.completedAt = completedAt
    }

    public init(dto: PlaybackHistoryDTO) {
        self.resumeByteOffset = dto.resumeByteOffset
        self.completed = dto.completed
        self.completedAt = dto.completedAt.map {
            Date(timeIntervalSince1970: TimeInterval($0.int64Value) / 1000.0)
        }
    }
}
