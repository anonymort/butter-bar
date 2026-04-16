import EngineInterface
import XCTest
@testable import PlayerDomain

/// Drives the `PlayerStateMachine` through every cell of the transition
/// matrix in `docs/design/player-state-foundation.md § Transition matrix`.
///
/// The matrix is 8 states × 14 event families. Many cells are explicit
/// no-ops or invariant violations (`inv`) — each is asserted explicitly
/// because silent drops are bugs. Tests are grouped by source state.
///
/// `now` is fixed: the v1 state machine is `now`-insensitive (no
/// transition stamps a timestamp), but the parameter exists so future
/// transitions can stamp without a refactor.
final class PlayerStateMachineTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func apply(_ event: PlayerEvent,
                       to state: PlayerState) -> PlayerState {
        PlayerStateMachine.apply(event, to: state, now: now)
    }

    // MARK: - From .closed

    func test_closed_userRequestedOpen_transitionsToBufferingOpeningStream() {
        XCTAssertEqual(apply(.userRequestedOpen, to: .closed),
                       .buffering(reason: .openingStream))
    }

    func test_closed_engineReturnedDescriptor_invariantStaysClosed() {
        XCTAssertEqual(apply(.engineReturnedDescriptor, to: .closed), .closed)
    }

    func test_closed_engineReturnedOpenError_invariantStaysClosed() {
        XCTAssertEqual(apply(.engineReturnedOpenError(.streamOpenFailed),
                             to: .closed), .closed)
    }

    func test_closed_userTappedPlay_invariantStaysClosed() {
        XCTAssertEqual(apply(.userTappedPlay, to: .closed), .closed)
    }

    func test_closed_userTappedPause_invariantStaysClosed() {
        XCTAssertEqual(apply(.userTappedPause, to: .closed), .closed)
    }

    func test_closed_userTappedClose_idempotentClosed() {
        XCTAssertEqual(apply(.userTappedClose, to: .closed), .closed)
    }

    func test_closed_userTappedRetry_invariantStaysClosed() {
        XCTAssertEqual(apply(.userTappedRetry, to: .closed), .closed)
    }

    func test_closed_avPlayerBeganPlaying_invariantStaysClosed() {
        XCTAssertEqual(apply(.avPlayerBeganPlaying, to: .closed), .closed)
    }

    func test_closed_avPlayerStalled_invariantStaysClosed() {
        XCTAssertEqual(apply(.avPlayerStalled, to: .closed), .closed)
    }

    func test_closed_avPlayerResumed_invariantStaysClosed() {
        XCTAssertEqual(apply(.avPlayerResumed, to: .closed), .closed)
    }

    func test_closed_avPlayerFailed_invariantStaysClosed() {
        XCTAssertEqual(apply(.avPlayerFailed, to: .closed), .closed)
    }

    func test_closed_engineHealthChanged_noopStaysClosed() {
        for tier in StreamHealthTier.allCases {
            XCTAssertEqual(apply(.engineHealthChanged(tier), to: .closed),
                           .closed,
                           "tier=\(tier)")
        }
    }

    func test_closed_engineDisconnected_staysClosed() {
        XCTAssertEqual(apply(.engineDisconnected, to: .closed), .closed)
    }

    func test_closed_engineReconnected_staysClosed() {
        XCTAssertEqual(apply(.engineReconnected, to: .closed), .closed)
    }

    // MARK: - From .open

    func test_open_userRequestedOpen_invariantStaysOpen() {
        XCTAssertEqual(apply(.userRequestedOpen, to: .open), .open)
    }

    func test_open_engineReturnedDescriptor_idempotentOpen() {
        XCTAssertEqual(apply(.engineReturnedDescriptor, to: .open), .open)
    }

    func test_open_engineReturnedOpenError_invariantStaysOpen() {
        XCTAssertEqual(apply(.engineReturnedOpenError(.streamOpenFailed),
                             to: .open), .open)
    }

    func test_open_userTappedPlay_transitionsToPlaying() {
        XCTAssertEqual(apply(.userTappedPlay, to: .open), .playing)
    }

    func test_open_userTappedPause_transitionsToPaused() {
        XCTAssertEqual(apply(.userTappedPause, to: .open), .paused)
    }

    func test_open_userTappedClose_transitionsToClosed() {
        XCTAssertEqual(apply(.userTappedClose, to: .open), .closed)
    }

    func test_open_userTappedRetry_invariantStaysOpen() {
        XCTAssertEqual(apply(.userTappedRetry, to: .open), .open)
    }

    func test_open_avPlayerBeganPlaying_transitionsToPlaying() {
        XCTAssertEqual(apply(.avPlayerBeganPlaying, to: .open), .playing)
    }

    func test_open_avPlayerStalled_transitionsToPlayerRebuffering() {
        XCTAssertEqual(apply(.avPlayerStalled, to: .open),
                       .buffering(reason: .playerRebuffering))
    }

    func test_open_avPlayerResumed_idempotentOpen() {
        XCTAssertEqual(apply(.avPlayerResumed, to: .open), .open)
    }

    func test_open_avPlayerFailed_transitionsToPlaybackFailed() {
        XCTAssertEqual(apply(.avPlayerFailed, to: .open),
                       .error(.playbackFailed))
    }

    func test_open_engineHealthStarving_transitionsToBufferingEngineStarving() {
        XCTAssertEqual(apply(.engineHealthChanged(.starving), to: .open),
                       .buffering(reason: .engineStarving))
    }

    func test_open_engineHealthNonStarving_idempotentOpen() {
        XCTAssertEqual(apply(.engineHealthChanged(.healthy), to: .open), .open)
        XCTAssertEqual(apply(.engineHealthChanged(.marginal), to: .open), .open)
    }

    func test_open_engineDisconnected_transitionsToError() {
        XCTAssertEqual(apply(.engineDisconnected, to: .open),
                       .error(.xpcDisconnected))
    }

    func test_open_engineReconnected_noAutoResumeStaysOpen() {
        XCTAssertEqual(apply(.engineReconnected, to: .open), .open)
    }

    // MARK: - From .playing

    func test_playing_userRequestedOpen_invariantStaysPlaying() {
        XCTAssertEqual(apply(.userRequestedOpen, to: .playing), .playing)
    }

    func test_playing_engineReturnedDescriptor_invariantStaysPlaying() {
        XCTAssertEqual(apply(.engineReturnedDescriptor, to: .playing), .playing)
    }

    func test_playing_engineReturnedOpenError_invariantStaysPlaying() {
        XCTAssertEqual(apply(.engineReturnedOpenError(.streamOpenFailed),
                             to: .playing), .playing)
    }

    func test_playing_userTappedPlay_idempotentPlaying() {
        XCTAssertEqual(apply(.userTappedPlay, to: .playing), .playing)
    }

    func test_playing_userTappedPause_transitionsToPaused() {
        XCTAssertEqual(apply(.userTappedPause, to: .playing), .paused)
    }

    func test_playing_userTappedClose_transitionsToClosed() {
        XCTAssertEqual(apply(.userTappedClose, to: .playing), .closed)
    }

    func test_playing_userTappedRetry_invariantStaysPlaying() {
        XCTAssertEqual(apply(.userTappedRetry, to: .playing), .playing)
    }

    func test_playing_avPlayerBeganPlaying_idempotentPlaying() {
        XCTAssertEqual(apply(.avPlayerBeganPlaying, to: .playing), .playing)
    }

    func test_playing_avPlayerStalled_transitionsToPlayerRebuffering() {
        XCTAssertEqual(apply(.avPlayerStalled, to: .playing),
                       .buffering(reason: .playerRebuffering))
    }

    func test_playing_avPlayerResumed_idempotentPlaying() {
        XCTAssertEqual(apply(.avPlayerResumed, to: .playing), .playing)
    }

    func test_playing_avPlayerFailed_transitionsToPlaybackFailed() {
        XCTAssertEqual(apply(.avPlayerFailed, to: .playing),
                       .error(.playbackFailed))
    }

    func test_playing_engineHealthStarving_transitionsToBufferingEngineStarving() {
        XCTAssertEqual(apply(.engineHealthChanged(.starving), to: .playing),
                       .buffering(reason: .engineStarving))
    }

    func test_playing_engineHealthNonStarving_idempotentPlaying() {
        XCTAssertEqual(apply(.engineHealthChanged(.healthy), to: .playing),
                       .playing)
        XCTAssertEqual(apply(.engineHealthChanged(.marginal), to: .playing),
                       .playing)
    }

    func test_playing_engineDisconnected_transitionsToError() {
        XCTAssertEqual(apply(.engineDisconnected, to: .playing),
                       .error(.xpcDisconnected))
    }

    func test_playing_engineReconnected_noAutoResumeStaysPlaying() {
        XCTAssertEqual(apply(.engineReconnected, to: .playing), .playing)
    }

    // MARK: - From .paused

    func test_paused_userRequestedOpen_invariantStaysPaused() {
        XCTAssertEqual(apply(.userRequestedOpen, to: .paused), .paused)
    }

    func test_paused_engineReturnedDescriptor_invariantStaysPaused() {
        XCTAssertEqual(apply(.engineReturnedDescriptor, to: .paused), .paused)
    }

    func test_paused_engineReturnedOpenError_invariantStaysPaused() {
        XCTAssertEqual(apply(.engineReturnedOpenError(.streamOpenFailed),
                             to: .paused), .paused)
    }

    func test_paused_userTappedPlay_transitionsToPlaying() {
        XCTAssertEqual(apply(.userTappedPlay, to: .paused), .playing)
    }

    func test_paused_userTappedPause_idempotentPaused() {
        XCTAssertEqual(apply(.userTappedPause, to: .paused), .paused)
    }

    func test_paused_userTappedClose_transitionsToClosed() {
        XCTAssertEqual(apply(.userTappedClose, to: .paused), .closed)
    }

    func test_paused_userTappedRetry_invariantStaysPaused() {
        XCTAssertEqual(apply(.userTappedRetry, to: .paused), .paused)
    }

    func test_paused_avPlayerBeganPlaying_idempotentPaused() {
        // Spurious AVPlayer rate during paused — no-op.
        XCTAssertEqual(apply(.avPlayerBeganPlaying, to: .paused), .paused)
    }

    func test_paused_avPlayerStalled_idempotentPaused() {
        XCTAssertEqual(apply(.avPlayerStalled, to: .paused), .paused)
    }

    func test_paused_avPlayerResumed_idempotentPaused() {
        XCTAssertEqual(apply(.avPlayerResumed, to: .paused), .paused)
    }

    func test_paused_avPlayerFailed_transitionsToPlaybackFailed() {
        XCTAssertEqual(apply(.avPlayerFailed, to: .paused),
                       .error(.playbackFailed))
    }

    func test_paused_engineHealthChanged_idempotentPaused() {
        // Engine starvation suppressed while paused — health is HUD-visible
        // but does not transition state.
        for tier in StreamHealthTier.allCases {
            XCTAssertEqual(apply(.engineHealthChanged(tier), to: .paused),
                           .paused, "tier=\(tier)")
        }
    }

    func test_paused_engineDisconnected_transitionsToError() {
        XCTAssertEqual(apply(.engineDisconnected, to: .paused),
                       .error(.xpcDisconnected))
    }

    func test_paused_engineReconnected_idempotentPaused() {
        XCTAssertEqual(apply(.engineReconnected, to: .paused), .paused)
    }

    // MARK: - From .buffering(.openingStream)

    private var bufOpen: PlayerState { .buffering(reason: .openingStream) }

    func test_bufOpen_userRequestedOpen_idempotent() {
        XCTAssertEqual(apply(.userRequestedOpen, to: bufOpen), bufOpen)
    }

    func test_bufOpen_engineReturnedDescriptor_transitionsToOpen() {
        XCTAssertEqual(apply(.engineReturnedDescriptor, to: bufOpen), .open)
    }

    func test_bufOpen_engineReturnedOpenError_transitionsToError() {
        XCTAssertEqual(apply(.engineReturnedOpenError(.streamOpenFailed),
                             to: bufOpen),
                       .error(.streamOpenFailed(.streamOpenFailed)))
    }

    func test_bufOpen_engineReturnedOpenError_carriesCode() {
        // Different EngineErrorCode propagates correctly.
        XCTAssertEqual(apply(.engineReturnedOpenError(.bookmarkInvalid),
                             to: bufOpen),
                       .error(.streamOpenFailed(.bookmarkInvalid)))
    }

    func test_bufOpen_userTappedPlay_invariant() {
        XCTAssertEqual(apply(.userTappedPlay, to: bufOpen), bufOpen)
    }

    func test_bufOpen_userTappedPause_invariant() {
        XCTAssertEqual(apply(.userTappedPause, to: bufOpen), bufOpen)
    }

    func test_bufOpen_userTappedClose_transitionsToClosed() {
        XCTAssertEqual(apply(.userTappedClose, to: bufOpen), .closed)
    }

    func test_bufOpen_userTappedRetry_invariant() {
        XCTAssertEqual(apply(.userTappedRetry, to: bufOpen), bufOpen)
    }

    func test_bufOpen_avPlayer_invariants() {
        XCTAssertEqual(apply(.avPlayerBeganPlaying, to: bufOpen), bufOpen)
        XCTAssertEqual(apply(.avPlayerStalled, to: bufOpen), bufOpen)
        XCTAssertEqual(apply(.avPlayerResumed, to: bufOpen), bufOpen)
        XCTAssertEqual(apply(.avPlayerFailed, to: bufOpen), bufOpen)
    }

    func test_bufOpen_engineHealthChanged_idempotent() {
        for tier in StreamHealthTier.allCases {
            XCTAssertEqual(apply(.engineHealthChanged(tier), to: bufOpen),
                           bufOpen, "tier=\(tier)")
        }
    }

    func test_bufOpen_engineDisconnected_transitionsToError() {
        XCTAssertEqual(apply(.engineDisconnected, to: bufOpen),
                       .error(.xpcDisconnected))
    }

    func test_bufOpen_engineReconnected_staysBuffering() {
        XCTAssertEqual(apply(.engineReconnected, to: bufOpen), bufOpen)
    }

    // MARK: - From .buffering(.engineStarving)

    private var bufEngine: PlayerState { .buffering(reason: .engineStarving) }

    func test_bufEngine_userRequestedOpen_invariant() {
        XCTAssertEqual(apply(.userRequestedOpen, to: bufEngine), bufEngine)
    }

    func test_bufEngine_engineReturnedDescriptor_invariant() {
        XCTAssertEqual(apply(.engineReturnedDescriptor, to: bufEngine), bufEngine)
    }

    func test_bufEngine_engineReturnedOpenError_invariant() {
        XCTAssertEqual(apply(.engineReturnedOpenError(.streamOpenFailed),
                             to: bufEngine), bufEngine)
    }

    func test_bufEngine_userTappedPlay_idempotent() {
        XCTAssertEqual(apply(.userTappedPlay, to: bufEngine), bufEngine)
    }

    func test_bufEngine_userTappedPause_transitionsToPaused() {
        XCTAssertEqual(apply(.userTappedPause, to: bufEngine), .paused)
    }

    func test_bufEngine_userTappedClose_transitionsToClosed() {
        XCTAssertEqual(apply(.userTappedClose, to: bufEngine), .closed)
    }

    func test_bufEngine_userTappedRetry_invariant() {
        XCTAssertEqual(apply(.userTappedRetry, to: bufEngine), bufEngine)
    }

    func test_bufEngine_avPlayerBeganPlaying_raceAcceptToPlaying() {
        // AVPlayer began before engine sent the recovered tier — accept.
        XCTAssertEqual(apply(.avPlayerBeganPlaying, to: bufEngine), .playing)
    }

    func test_bufEngine_avPlayerStalled_swapsToPlayerRebuffering() {
        XCTAssertEqual(apply(.avPlayerStalled, to: bufEngine),
                       .buffering(reason: .playerRebuffering))
    }

    func test_bufEngine_avPlayerResumed_idempotent() {
        XCTAssertEqual(apply(.avPlayerResumed, to: bufEngine), bufEngine)
    }

    func test_bufEngine_avPlayerFailed_transitionsToPlaybackFailed() {
        XCTAssertEqual(apply(.avPlayerFailed, to: bufEngine),
                       .error(.playbackFailed))
    }

    func test_bufEngine_engineHealthStarving_idempotent() {
        XCTAssertEqual(apply(.engineHealthChanged(.starving), to: bufEngine),
                       bufEngine)
    }

    func test_bufEngine_engineHealthRecovered_transitionsToPlaying() {
        XCTAssertEqual(apply(.engineHealthChanged(.healthy), to: bufEngine),
                       .playing)
        XCTAssertEqual(apply(.engineHealthChanged(.marginal), to: bufEngine),
                       .playing)
    }

    func test_bufEngine_engineDisconnected_transitionsToError() {
        XCTAssertEqual(apply(.engineDisconnected, to: bufEngine),
                       .error(.xpcDisconnected))
    }

    func test_bufEngine_engineReconnected_staysBuffering() {
        XCTAssertEqual(apply(.engineReconnected, to: bufEngine), bufEngine)
    }

    // MARK: - From .buffering(.playerRebuffering)

    private var bufPlayer: PlayerState {
        .buffering(reason: .playerRebuffering)
    }

    func test_bufPlayer_userRequestedOpen_invariant() {
        XCTAssertEqual(apply(.userRequestedOpen, to: bufPlayer), bufPlayer)
    }

    func test_bufPlayer_engineReturnedDescriptor_invariant() {
        XCTAssertEqual(apply(.engineReturnedDescriptor, to: bufPlayer),
                       bufPlayer)
    }

    func test_bufPlayer_engineReturnedOpenError_invariant() {
        XCTAssertEqual(apply(.engineReturnedOpenError(.streamOpenFailed),
                             to: bufPlayer), bufPlayer)
    }

    func test_bufPlayer_userTappedPlay_idempotent() {
        XCTAssertEqual(apply(.userTappedPlay, to: bufPlayer), bufPlayer)
    }

    func test_bufPlayer_userTappedPause_transitionsToPaused() {
        XCTAssertEqual(apply(.userTappedPause, to: bufPlayer), .paused)
    }

    func test_bufPlayer_userTappedClose_transitionsToClosed() {
        XCTAssertEqual(apply(.userTappedClose, to: bufPlayer), .closed)
    }

    func test_bufPlayer_userTappedRetry_invariant() {
        XCTAssertEqual(apply(.userTappedRetry, to: bufPlayer), bufPlayer)
    }

    func test_bufPlayer_avPlayerBeganPlaying_transitionsToPlaying() {
        XCTAssertEqual(apply(.avPlayerBeganPlaying, to: bufPlayer), .playing)
    }

    func test_bufPlayer_avPlayerStalled_idempotent() {
        XCTAssertEqual(apply(.avPlayerStalled, to: bufPlayer), bufPlayer)
    }

    func test_bufPlayer_avPlayerResumed_transitionsToPlaying() {
        XCTAssertEqual(apply(.avPlayerResumed, to: bufPlayer), .playing)
    }

    func test_bufPlayer_avPlayerFailed_transitionsToPlaybackFailed() {
        XCTAssertEqual(apply(.avPlayerFailed, to: bufPlayer),
                       .error(.playbackFailed))
    }

    func test_bufPlayer_engineHealthStarving_swapsToEngineStarving() {
        // Engine wins precedence; reason swap.
        XCTAssertEqual(apply(.engineHealthChanged(.starving), to: bufPlayer),
                       .buffering(reason: .engineStarving))
    }

    func test_bufPlayer_engineHealthNonStarving_stays() {
        XCTAssertEqual(apply(.engineHealthChanged(.healthy), to: bufPlayer),
                       bufPlayer)
        XCTAssertEqual(apply(.engineHealthChanged(.marginal), to: bufPlayer),
                       bufPlayer)
    }

    func test_bufPlayer_engineDisconnected_transitionsToError() {
        XCTAssertEqual(apply(.engineDisconnected, to: bufPlayer),
                       .error(.xpcDisconnected))
    }

    func test_bufPlayer_engineReconnected_staysBuffering() {
        XCTAssertEqual(apply(.engineReconnected, to: bufPlayer), bufPlayer)
    }

    // MARK: - From .error(_)

    private var errDisc: PlayerState { .error(.xpcDisconnected) }
    private var errFail: PlayerState {
        .error(.streamOpenFailed(.streamOpenFailed))
    }
    private var errPlay: PlayerState { .error(.playbackFailed) }

    func test_error_userRequestedOpen_invariant() {
        XCTAssertEqual(apply(.userRequestedOpen, to: errDisc), errDisc)
    }

    func test_error_engineReturnedDescriptor_invariant() {
        XCTAssertEqual(apply(.engineReturnedDescriptor, to: errDisc), errDisc)
    }

    func test_error_engineReturnedOpenError_invariant() {
        XCTAssertEqual(apply(.engineReturnedOpenError(.streamOpenFailed),
                             to: errDisc), errDisc)
    }

    func test_error_userTappedPlay_invariant() {
        XCTAssertEqual(apply(.userTappedPlay, to: errDisc), errDisc)
    }

    func test_error_userTappedPause_invariant() {
        XCTAssertEqual(apply(.userTappedPause, to: errDisc), errDisc)
    }

    func test_error_userTappedClose_transitionsToClosed() {
        XCTAssertEqual(apply(.userTappedClose, to: errDisc), .closed)
        XCTAssertEqual(apply(.userTappedClose, to: errFail), .closed)
        XCTAssertEqual(apply(.userTappedClose, to: errPlay), .closed)
    }

    func test_error_userTappedRetry_transitionsToBufferingOpeningStream() {
        XCTAssertEqual(apply(.userTappedRetry, to: errDisc),
                       .buffering(reason: .openingStream))
        XCTAssertEqual(apply(.userTappedRetry, to: errFail),
                       .buffering(reason: .openingStream))
        XCTAssertEqual(apply(.userTappedRetry, to: errPlay),
                       .buffering(reason: .openingStream))
    }

    func test_error_avPlayer_invariants() {
        XCTAssertEqual(apply(.avPlayerBeganPlaying, to: errDisc), errDisc)
        XCTAssertEqual(apply(.avPlayerStalled, to: errDisc), errDisc)
        XCTAssertEqual(apply(.avPlayerResumed, to: errDisc), errDisc)
        XCTAssertEqual(apply(.avPlayerFailed, to: errDisc), errDisc)
    }

    func test_error_engineHealthChanged_idempotent() {
        for tier in StreamHealthTier.allCases {
            XCTAssertEqual(apply(.engineHealthChanged(tier), to: errDisc),
                           errDisc, "tier=\(tier)")
        }
    }

    func test_error_engineDisconnected_idempotent() {
        XCTAssertEqual(apply(.engineDisconnected, to: errDisc), errDisc)
    }

    func test_error_engineReconnected_noAutoResume() {
        // Per design § D6 — reconnect does not auto-recover.
        XCTAssertEqual(apply(.engineReconnected, to: errDisc), errDisc)
    }

    // MARK: - Determinism

    func test_determinism_replayProducesSameTrajectory() {
        // A canonical "open → play → stall → recover → close" trajectory.
        let events: [PlayerEvent] = [
            .userRequestedOpen,
            .engineReturnedDescriptor,
            .userTappedPlay,
            .avPlayerBeganPlaying,
            .avPlayerStalled,
            .avPlayerResumed,
            .userTappedClose
        ]

        func play() -> [PlayerState] {
            var s: PlayerState = .closed
            var trajectory: [PlayerState] = [s]
            for e in events {
                s = PlayerStateMachine.apply(e, to: s, now: now)
                trajectory.append(s)
            }
            return trajectory
        }

        let first = play()
        let second = play()
        XCTAssertEqual(first, second)

        // Spot-check a few key transitions.
        XCTAssertEqual(first[1], .buffering(reason: .openingStream),
                       "after userRequestedOpen")
        XCTAssertEqual(first[2], .open, "after engineReturnedDescriptor")
        XCTAssertEqual(first[3], .playing, "after userTappedPlay")
        XCTAssertEqual(first[5], .buffering(reason: .playerRebuffering),
                       "after avPlayerStalled")
        XCTAssertEqual(first[6], .playing, "after avPlayerResumed")
        XCTAssertEqual(first[7], .closed, "after userTappedClose")
    }
}
