import EngineInterface
import Foundation
import LibraryDomain
import os

/// Pure decision: should the resume prompt be offered?
///
/// See `docs/design/player-state-foundation.md § D7 — Resume prompt seam`
/// and `§ Resume-prompt seam tests`.
///
/// The two predicates are intentionally redundant — `WatchStatus` carries
/// the user-meaningful signal ("you were 23 minutes in") and
/// `resumeByteOffset` carries the operationally meaningful signal (what
/// AVPlayer actually seeks to). Both must hold for an honest prompt.
///
/// If they disagree, the prompt is suppressed silently and the disagreement
/// is logged — these are invariant violations the engine guarantees do
/// not happen. Defensive only; never crashes.
enum ResumePromptDecision {

    private static let log = Logger(
        subsystem: "com.butterbar.app",
        category: "ResumePromptDecision"
    )

    static func shouldOffer(watchStatus: WatchStatus,
                            descriptor: StreamDescriptorDTO) -> Bool {
        let hasProgressStatus: Bool
        switch watchStatus {
        case .inProgress, .reWatching:
            hasProgressStatus = true
        case .unwatched, .watched:
            hasProgressStatus = false
        }
        let hasResumeOffset = descriptor.resumeByteOffset > 0

        switch (hasProgressStatus, hasResumeOffset) {
        case (true, true):
            return true
        case (false, false):
            return false
        case (true, false):
            // .inProgress / .reWatching but no engine-side resume offset.
            log.warning("Resume prompt suppressed: watchStatus has progress but resumeByteOffset == 0 (invariant violation)")
            return false
        case (false, true):
            // No history (or .watched) but engine reports a non-zero offset.
            log.warning("Resume prompt suppressed: watchStatus has no progress but resumeByteOffset > 0 (invariant violation or fresh re-watch)")
            return false
        }
    }
}
