import EngineInterface
import Foundation
import PlayerDomain

// MARK: - PlayerCopy
//
// Single source of every user-facing string in the player chrome. Keeping
// every string here is the single audit surface required by issue #26 AC
// ("every copy string in this PR appears in a single `PlayerCopy.swift` file
// ... so it can be audited against `06-brand.md` in one place"). Voice
// conventions (calm, concrete, British English, no exclamation marks, no
// system jargon) are enforced both by review and by the
// `PlayerCopyVoiceTests` regex pass.
//
// Conventions:
// - Title (`errorTitle`): one short clause stating the situation. No verbs of
//   blame, no "Sorry,". The user knows something is wrong; tell them what.
// - Body (`errorBody`): one sentence telling them what to do, plus an
//   optional second sentence of context. Calm tone. Mentions Retry only when
//   it is the obvious next step.
// - The engine error code itself is rendered separately by the chrome view
//   in a small monospaced strip (`engineCodeDetail`) so support handoff has
//   a stable token to grep for.
//
// All strings are British English.

enum PlayerCopy {

    // MARK: - Error chrome

    /// Headline for the error overlay. One short clause per `06-brand.md §
    /// Voice` — no exclamation marks, no system jargon, no "ERROR".
    static func errorTitle(for error: PlayerError) -> String {
        switch error {
        case .streamOpenFailed(let code):
            return streamOpenFailedTitle(for: code)
        case .xpcDisconnected:
            return "Lost contact with the engine"
        case .playbackFailed:
            return "Playback couldn't continue"
        case .streamLost:
            // Per AC: same surface as `.xpcDisconnected` for v1 (case is
            // currently unreachable per design O1; surface is in place for
            // when the engine-initiated-close event lands).
            return "Lost contact with the engine"
        }
    }

    /// Supporting copy under the title. One sentence telling the user what
    /// will happen if they tap Retry. Optional second sentence of context.
    static func errorBody(for error: PlayerError) -> String {
        switch error {
        case .streamOpenFailed(let code):
            return streamOpenFailedBody(for: code)
        case .xpcDisconnected:
            return "Tap retry to reconnect."
        case .playbackFailed:
            return "Tap retry to start the stream again."
        case .streamLost:
            return "Tap retry to reconnect."
        }
    }

    /// Optional secondary hint shown beneath the body for `.playbackFailed`
    /// when the last-known engine tier is `.starving`. Calmer than implying
    /// blame on the network — this just lets the user know the engine was
    /// already struggling at the moment playback stopped.
    static func playbackFailedTierHint(for tier: StreamHealthTier?) -> String? {
        guard tier == .starving else { return nil }
        return "The engine was struggling for peers when this happened."
    }

    /// Monospaced detail strip rendered under the body so support requests
    /// have a stable identifier. Format mirrors the XPC contract:
    /// `engine code: <raw>·<symbolic>` — short enough for the overlay,
    /// verbose enough that copy/paste survives a screenshot OCR.
    static func engineCodeDetail(for code: EngineErrorCode) -> String {
        "engine code: \(code.rawValue) · \(symbolicName(of: code))"
    }

    // MARK: - Buffering chrome

    /// Primary line under the buffering pill. Short, calm, concrete.
    static func bufferingPrimary(for reason: BufferingReason) -> String {
        switch reason {
        case .openingStream:
            return "Loading…"
        case .engineStarving:
            return "Looking for peers…"
        case .playerRebuffering:
            return "Re-buffering…"
        }
    }

    /// Secondary line surfaced when `.engineStarving` persists past the
    /// threshold. Per AC: "Still trying — your network or this torrent's
    /// peers may be slow." Hedged, calm, no blame.
    static let bufferingLongStarvingSecondary =
        "Still trying — your network or this torrent's peers may be slow."

    /// How long `.buffering(.engineStarving)` must persist before the
    /// secondary line appears. Per AC: "≥ 30 s ... Tunable threshold in
    /// one file." This is that one file.
    static let longStarvingThreshold: TimeInterval = 30

    /// Pure decision so the threshold is tested with an injected clock
    /// rather than a real-time `Task.sleep`.
    static func shouldShowLongStarvingLine(bufferingStartedAt started: Date?,
                                           now: Date) -> Bool {
        guard let started else { return false }
        return now.timeIntervalSince(started) >= longStarvingThreshold
    }

    // MARK: - Buttons

    /// Action label on every error surface. "Try again" is gentler than
    /// "Retry" and doesn't read as a verb of blame; both work, "Retry" is
    /// shorter and aligns with the `userTappedRetry` event vocabulary the
    /// rest of the system already uses.
    static let retryButtonLabel = "Retry"

    /// Action label on every error surface that allows escape.
    static let closeButtonLabel = "Close"

    // MARK: - Per-EngineErrorCode copy

    /// Title varies by `EngineErrorCode` so the user gets a useful headline.
    /// Fallback ("Something went wrong opening this stream") covers any
    /// codes we don't have a stronger story for yet.
    private static func streamOpenFailedTitle(for code: EngineErrorCode) -> String {
        switch code {
        case .torrentNotFound:
            return "We can't find this torrent"
        case .fileIndexOutOfRange:
            return "We can't find this file in the torrent"
        case .invalidInput:
            return "Something about this stream looks wrong"
        case .bookmarkInvalid:
            return "Lost track of where this file lives"
        case .storageError:
            return "Couldn't read or write the cache"
        case .engineShuttingDown:
            return "The engine is restarting"
        case .streamNotFound:
            return "This stream is no longer available"
        case .notImplemented:
            return "We can't handle this stream yet"
        case .streamOpenFailed:
            return "Something went wrong opening this stream"
        @unknown default:
            return "Something went wrong opening this stream"
        }
    }

    private static func streamOpenFailedBody(for code: EngineErrorCode) -> String {
        switch code {
        case .torrentNotFound:
            return "Tap retry to look again."
        case .fileIndexOutOfRange:
            return "Tap retry, then pick a different file if this one keeps failing."
        case .invalidInput:
            return "Tap retry. If it keeps failing, the source may need to be re-added."
        case .bookmarkInvalid:
            return "Tap retry. You may need to re-grant access to the file's location."
        case .storageError:
            return "Tap retry. If it keeps failing, the cache may be full or read-only."
        case .engineShuttingDown:
            return "Tap retry once it's back up."
        case .streamNotFound:
            return "Tap retry to open it fresh."
        case .notImplemented:
            return "Tap retry. If it keeps failing, this format isn't supported yet."
        case .streamOpenFailed:
            return "Tap retry to try again."
        @unknown default:
            return "Tap retry to try again."
        }
    }

    /// Stable symbolic name for the monospaced detail strip. Doesn't depend
    /// on `String(describing:)` so renames in the enum can't accidentally
    /// change support log output without going through this file.
    private static func symbolicName(of code: EngineErrorCode) -> String {
        switch code {
        case .notImplemented:        return "notImplemented"
        case .invalidInput:          return "invalidInput"
        case .torrentNotFound:       return "torrentNotFound"
        case .fileIndexOutOfRange:   return "fileIndexOutOfRange"
        case .streamNotFound:        return "streamNotFound"
        case .streamOpenFailed:      return "streamOpenFailed"
        case .bookmarkInvalid:       return "bookmarkInvalid"
        case .storageError:          return "storageError"
        case .engineShuttingDown:    return "engineShuttingDown"
        @unknown default:            return "unknown"
        }
    }
}
