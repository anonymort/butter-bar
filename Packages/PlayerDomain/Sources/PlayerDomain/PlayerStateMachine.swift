import EngineInterface
import Foundation

/// Pure-function state machine for the player view-model. Mirrors the Phase 1
/// `WatchStateMachine` discipline (addendum A3 / Phase 3 design § D4):
///
/// - Deterministic: same `(state, event, now)` always yields the same result.
/// - Pure: no clocks (`now` injected), no I/O, no `DispatchQueue`, no
///   `Combine`, no randomness, no internal mutable state.
/// - Side-effect free: applying an event returns a new `PlayerState`; the
///   calling `PlayerViewModel` is responsible for any actual XPC / AVKit
///   calls implied by the transition.
///
/// Tests exercise every cell of the transition matrix in
/// `docs/design/player-state-foundation.md § Transition matrix`.
public enum PlayerStateMachine {

    /// Apply `event` to `state`, producing the new state as of `now`.
    public static func apply(_ event: PlayerEvent,
                             to state: PlayerState,
                             now: Date) -> PlayerState {
        switch (state, event) {

        // MARK: - .closed

        case (.closed, .userRequestedOpen):
            return .buffering(reason: .openingStream)
        case (.closed, _):
            // Every other event is either an invariant violation or a no-op.
            // Per design § Transition matrix all stay `.closed`.
            return .closed

        // MARK: - .open

        case (.open, .userTappedPlay),
             (.open, .avPlayerBeganPlaying):
            return .playing
        case (.open, .userTappedPause):
            return .paused
        case (.open, .userTappedClose):
            return .closed
        case (.open, .avPlayerStalled):
            return .buffering(reason: .playerRebuffering)
        case (.open, .avPlayerFailed):
            return .error(.playbackFailed)
        case (.open, .engineHealthChanged(let tier)):
            return tier == .starving
                ? .buffering(reason: .engineStarving)
                : .open
        case (.open, .engineDisconnected):
            return .error(.xpcDisconnected)
        case (.open, _):
            // Idempotent / invariant: userRequestedOpen, engineReturnedDescriptor,
            // engineReturnedOpenError, userTappedRetry, avPlayerResumed,
            // engineReconnected (no auto-resume per D6).
            return .open

        // MARK: - .playing

        case (.playing, .userTappedPause):
            return .paused
        case (.playing, .userTappedClose):
            return .closed
        case (.playing, .avPlayerStalled):
            return .buffering(reason: .playerRebuffering)
        case (.playing, .avPlayerFailed):
            return .error(.playbackFailed)
        case (.playing, .engineHealthChanged(let tier)):
            return tier == .starving
                ? .buffering(reason: .engineStarving)
                : .playing
        case (.playing, .engineDisconnected):
            return .error(.xpcDisconnected)
        case (.playing, _):
            // Idempotent / invariant: userRequestedOpen, engineReturned*,
            // userTappedPlay, userTappedRetry, avPlayerBeganPlaying,
            // avPlayerResumed, engineReconnected.
            return .playing

        // MARK: - .paused

        case (.paused, .userTappedPlay):
            return .playing
        case (.paused, .userTappedClose):
            return .closed
        case (.paused, .avPlayerFailed):
            return .error(.playbackFailed)
        case (.paused, .engineDisconnected):
            return .error(.xpcDisconnected)
        case (.paused, _):
            // Idempotent / invariant: every other event leaves paused
            // unchanged (engine starvation suppressed while paused — health
            // visible in HUD only; spurious AVPlayer signals ignored).
            return .paused

        // MARK: - .buffering(.openingStream)

        case (.buffering(.openingStream), .engineReturnedDescriptor):
            return .open
        case (.buffering(.openingStream), .engineReturnedOpenError(let code)):
            return .error(.streamOpenFailed(code))
        case (.buffering(.openingStream), .userTappedClose):
            return .closed
        case (.buffering(.openingStream), .engineDisconnected):
            return .error(.xpcDisconnected)
        case (.buffering(.openingStream), _):
            // All else (idempotent open, invariant user/avPlayer events,
            // engineHealth no-op pre-open, reconnect stays buffering).
            return .buffering(reason: .openingStream)

        // MARK: - .buffering(.engineStarving)

        case (.buffering(.engineStarving), .userTappedPause):
            return .paused
        case (.buffering(.engineStarving), .userTappedClose):
            return .closed
        case (.buffering(.engineStarving), .avPlayerBeganPlaying):
            // Race: AVPlayer began before engine sent the recovered tier.
            // Accept — AVPlayer rate is ground truth.
            return .playing
        case (.buffering(.engineStarving), .avPlayerStalled):
            // Reason swap: player-side stall while engine still starving.
            return .buffering(reason: .playerRebuffering)
        case (.buffering(.engineStarving), .avPlayerFailed):
            return .error(.playbackFailed)
        case (.buffering(.engineStarving), .engineHealthChanged(let tier)):
            return tier == .starving
                ? .buffering(reason: .engineStarving)
                : .playing
        case (.buffering(.engineStarving), .engineDisconnected):
            return .error(.xpcDisconnected)
        case (.buffering(.engineStarving), _):
            return .buffering(reason: .engineStarving)

        // MARK: - .buffering(.playerRebuffering)

        case (.buffering(.playerRebuffering), .userTappedPause):
            return .paused
        case (.buffering(.playerRebuffering), .userTappedClose):
            return .closed
        case (.buffering(.playerRebuffering), .avPlayerBeganPlaying),
             (.buffering(.playerRebuffering), .avPlayerResumed):
            return .playing
        case (.buffering(.playerRebuffering), .avPlayerFailed):
            return .error(.playbackFailed)
        case (.buffering(.playerRebuffering), .engineHealthChanged(let tier)):
            // Engine wins precedence: starving overrides player-rebuffering.
            return tier == .starving
                ? .buffering(reason: .engineStarving)
                : .buffering(reason: .playerRebuffering)
        case (.buffering(.playerRebuffering), .engineDisconnected):
            return .error(.xpcDisconnected)
        case (.buffering(.playerRebuffering), _):
            return .buffering(reason: .playerRebuffering)

        // MARK: - .error(_)

        case (.error, .userTappedClose):
            return .closed
        case (.error, .userTappedRetry):
            return .buffering(reason: .openingStream)
        case (.error, _):
            // Per design § D6 — reconnect does NOT auto-recover; every other
            // event is invariant or idempotent against the existing error.
            return state
        }
    }
}
