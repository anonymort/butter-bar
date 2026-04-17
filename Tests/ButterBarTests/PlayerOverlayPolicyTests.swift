import XCTest
import EngineInterface
import PlayerDomain
@testable import ButterBar

// MARK: - PlayerOverlayPolicyTests
//
// Pure unit tests for `PlayerOverlayPolicy`. No SwiftUI rendering — the
// snapshot suite covers visual fidelity. These tests guard the AC table in
// issue #24: which controls are visible per `PlayerState`, and which states
// allow the auto-hide timer to fire.

final class PlayerOverlayPolicyTests: XCTestCase {

    // MARK: - Auto-hide policy

    func testAutoHideOnlyEnabledWhilePlaying() {
        XCTAssertTrue(PlayerOverlayPolicy.mayAutoHide(in: .playing))

        // Every other state pins the chrome visible.
        XCTAssertFalse(PlayerOverlayPolicy.mayAutoHide(in: .closed))
        XCTAssertFalse(PlayerOverlayPolicy.mayAutoHide(in: .open))
        XCTAssertFalse(PlayerOverlayPolicy.mayAutoHide(in: .paused))
        XCTAssertFalse(PlayerOverlayPolicy.mayAutoHide(
            in: .buffering(reason: .openingStream)))
        XCTAssertFalse(PlayerOverlayPolicy.mayAutoHide(
            in: .buffering(reason: .engineStarving)))
        XCTAssertFalse(PlayerOverlayPolicy.mayAutoHide(
            in: .buffering(reason: .playerRebuffering)))
        XCTAssertFalse(PlayerOverlayPolicy.mayAutoHide(
            in: .error(.playbackFailed)))
    }

    // MARK: - Centre affordance per state

    func testCentreAffordance_open_isPlay() {
        XCTAssertEqual(PlayerOverlayPolicy.controls(for: .open).centre, .play)
    }

    func testCentreAffordance_playing_isPause() {
        XCTAssertEqual(PlayerOverlayPolicy.controls(for: .playing).centre, .pause)
    }

    func testCentreAffordance_paused_isPlay() {
        XCTAssertEqual(PlayerOverlayPolicy.controls(for: .paused).centre, .play)
    }

    func testCentreAffordance_buffering_isHidden() {
        // Buffering: greyed / hidden play/pause per AC.
        for reason: BufferingReason in [.openingStream, .engineStarving, .playerRebuffering] {
            XCTAssertEqual(
                PlayerOverlayPolicy.controls(for: .buffering(reason: reason)).centre,
                .hidden,
                "buffering(\(reason)) should hide the centre play/pause"
            )
        }
    }

    func testCentreAffordance_error_isHidden() {
        XCTAssertEqual(
            PlayerOverlayPolicy.controls(for: .error(.playbackFailed)).centre,
            .hidden
        )
    }

    func testCentreAffordance_closed_isHidden() {
        XCTAssertEqual(PlayerOverlayPolicy.controls(for: .closed).centre, .hidden)
    }

    // MARK: - Buffering indicator

    func testBufferingIndicatorVisibleOnlyDuringBuffering() {
        XCTAssertFalse(PlayerOverlayPolicy.controls(for: .open).showsBufferingIndicator)
        XCTAssertFalse(PlayerOverlayPolicy.controls(for: .playing).showsBufferingIndicator)
        XCTAssertFalse(PlayerOverlayPolicy.controls(for: .paused).showsBufferingIndicator)
        XCTAssertFalse(PlayerOverlayPolicy.controls(for: .closed).showsBufferingIndicator)
        XCTAssertFalse(PlayerOverlayPolicy.controls(for: .error(.playbackFailed)).showsBufferingIndicator)

        for reason: BufferingReason in [.openingStream, .engineStarving, .playerRebuffering] {
            let set = PlayerOverlayPolicy.controls(for: .buffering(reason: reason))
            XCTAssertTrue(set.showsBufferingIndicator)
            XCTAssertEqual(set.bufferingReason, reason)
        }
    }

    // MARK: - Close affordance always available except where AC permits

    func testCloseAlwaysAvailable() {
        // The close affordance is the user's only escape hatch. It must be
        // present in every renderable state.
        let states: [PlayerState] = [
            .closed, .open, .playing, .paused,
            .buffering(reason: .openingStream),
            .buffering(reason: .engineStarving),
            .buffering(reason: .playerRebuffering),
            .error(.playbackFailed),
            .error(.xpcDisconnected),
        ]
        for state in states {
            XCTAssertTrue(
                PlayerOverlayPolicy.controls(for: state).showsClose,
                "close should be visible in \(state)"
            )
        }
    }

    // MARK: - Fullscreen / HUD / picker entries

    func testFullscreenAndPickersHiddenInClosedAndError() {
        for state: PlayerState in [.closed, .error(.playbackFailed)] {
            let set = PlayerOverlayPolicy.controls(for: state)
            XCTAssertFalse(set.showsFullscreen, "fullscreen should hide in \(state)")
            XCTAssertFalse(set.showsHealthHUD, "HUD should hide in \(state)")
            XCTAssertFalse(set.showsTrackPickerEntries, "picker entries should hide in \(state)")
        }
    }

    func testFullscreenAndPickersVisibleInLivePlaybackStates() {
        let states: [PlayerState] = [
            .open, .playing, .paused,
            .buffering(reason: .openingStream),
            .buffering(reason: .engineStarving),
            .buffering(reason: .playerRebuffering),
        ]
        for state in states {
            let set = PlayerOverlayPolicy.controls(for: state)
            XCTAssertTrue(set.showsFullscreen, "fullscreen should show in \(state)")
            XCTAssertTrue(set.showsHealthHUD, "HUD should show in \(state)")
            XCTAssertTrue(set.showsTrackPickerEntries, "picker entries should show in \(state)")
        }
    }

    // MARK: - Scrub enabled iff playback can be seeked

    func testScrubDisabledWhileBufferingOrErrorOrClosed() {
        XCTAssertFalse(PlayerOverlayPolicy.controls(for: .closed).scrubEnabled)
        XCTAssertFalse(PlayerOverlayPolicy.controls(for: .error(.playbackFailed)).scrubEnabled)
        for reason: BufferingReason in [.openingStream, .engineStarving, .playerRebuffering] {
            XCTAssertFalse(
                PlayerOverlayPolicy.controls(for: .buffering(reason: reason)).scrubEnabled,
                "scrub should disable while buffering(\(reason))"
            )
        }
    }

    func testScrubEnabledInOpenPlayingPaused() {
        XCTAssertTrue(PlayerOverlayPolicy.controls(for: .open).scrubEnabled)
        XCTAssertTrue(PlayerOverlayPolicy.controls(for: .playing).scrubEnabled)
        XCTAssertTrue(PlayerOverlayPolicy.controls(for: .paused).scrubEnabled)
    }

    // MARK: - Buffering copy is brand-voice (calm, British English, no "!")

    func testBufferingCopyIsCalmAndPunctuationCompliant() {
        for reason: BufferingReason in [.openingStream, .engineStarving, .playerRebuffering] {
            let copy = PlayerOverlayPolicy.bufferingCopy(for: reason)
            XCTAssertFalse(copy.contains("!"),
                           "Brand voice forbids exclamation marks except in genuine errors: \(copy)")
            XCTAssertFalse(copy.isEmpty)
        }
    }

    // MARK: - Format helper

    func testTimeFormatHandlesShortAndLongDurations() {
        XCTAssertEqual(PlayerScrubBar.format(seconds: 0), "0:00")
        XCTAssertEqual(PlayerScrubBar.format(seconds: 9), "0:09")
        XCTAssertEqual(PlayerScrubBar.format(seconds: 65), "1:05")
        XCTAssertEqual(PlayerScrubBar.format(seconds: 3600), "1:00:00")
        XCTAssertEqual(PlayerScrubBar.format(seconds: 3661), "1:01:01")
    }

    func testTimeFormatRejectsNonFiniteAndNegative() {
        XCTAssertEqual(PlayerScrubBar.format(seconds: -5), "0:00")
        XCTAssertEqual(PlayerScrubBar.format(seconds: .nan), "0:00")
        XCTAssertEqual(PlayerScrubBar.format(seconds: .infinity), "0:00")
    }
}
