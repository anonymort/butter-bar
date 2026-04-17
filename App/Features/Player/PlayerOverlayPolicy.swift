import PlayerDomain

// MARK: - PlayerOverlayPolicy
//
// Pure decision logic for the player overlay chrome. Lives outside the SwiftUI
// view so it is unit-testable without an `ImageRenderer` round-trip.
//
// Two responsibilities, both keyed off `PlayerState`:
//
// 1. `controls(for:)` — which affordances are visible / enabled per state.
//    Mirrors the AC table in issue #24.
// 2. `mayAutoHide(in:)` — whether the chrome is allowed to fade after the
//    pointer goes idle. Only `.playing` opts in; every other state pins the
//    chrome on (per AC: "Always visible during .open, .paused, .buffering(_),
//    .error(_)").

enum PlayerOverlayPolicy {

    /// Set of control affordances rendered for a given `PlayerState`.
    struct ControlSet: Equatable {
        /// Centre primary affordance: play, pause, or hidden.
        var centre: CentreAffordance
        /// Whether scrub bar interaction is enabled (vs. read-only display).
        var scrubEnabled: Bool
        /// Whether buffering progress chrome is shown (centre overlay).
        var showsBufferingIndicator: Bool
        /// `BufferingReason` for buffering copy. `nil` outside `.buffering(_)`.
        var bufferingReason: BufferingReason?
        /// Whether the close button is shown.
        var showsClose: Bool
        /// Whether the fullscreen toggle is shown.
        var showsFullscreen: Bool
        /// Whether the StreamHealth tier / stats HUD is shown.
        var showsHealthHUD: Bool
        /// Whether subtitle and audio picker entry-points are shown.
        /// (#22 / #23 wire the actual pickers — this overlay only renders the
        /// disabled placeholder buttons.)
        var showsTrackPickerEntries: Bool
    }

    enum CentreAffordance: Equatable {
        case hidden
        case play
        case pause
    }

    /// AC table: which control set is appropriate for each state.
    static func controls(for state: PlayerState) -> ControlSet {
        switch state {
        case .closed:
            // Window is going away. Nothing useful to render — keep just the
            // close affordance so a stuck `.closed` view can still be dismissed.
            return ControlSet(
                centre: .hidden,
                scrubEnabled: false,
                showsBufferingIndicator: false,
                bufferingReason: nil,
                showsClose: true,
                showsFullscreen: false,
                showsHealthHUD: false,
                showsTrackPickerEntries: false
            )

        case .open:
            // Descriptor in hand, awaiting user intent. Play affordance prominent.
            return ControlSet(
                centre: .play,
                scrubEnabled: true,
                showsBufferingIndicator: false,
                bufferingReason: nil,
                showsClose: true,
                showsFullscreen: true,
                showsHealthHUD: true,
                showsTrackPickerEntries: true
            )

        case .playing:
            // Pause affordance. Full controls — but `mayAutoHide` allows fade.
            return ControlSet(
                centre: .pause,
                scrubEnabled: true,
                showsBufferingIndicator: false,
                bufferingReason: nil,
                showsClose: true,
                showsFullscreen: true,
                showsHealthHUD: true,
                showsTrackPickerEntries: true
            )

        case .paused:
            // User intent. Play affordance, controls pinned visible.
            return ControlSet(
                centre: .play,
                scrubEnabled: true,
                showsBufferingIndicator: false,
                bufferingReason: nil,
                showsClose: true,
                showsFullscreen: true,
                showsHealthHUD: true,
                showsTrackPickerEntries: true
            )

        case .buffering(let reason):
            // Calm progress chrome. Play/pause hidden — the user has no useful
            // action while we are waiting on bytes (see AC: "play/pause greyed").
            return ControlSet(
                centre: .hidden,
                scrubEnabled: false,
                showsBufferingIndicator: true,
                bufferingReason: reason,
                showsClose: true,
                showsFullscreen: true,
                showsHealthHUD: true,
                showsTrackPickerEntries: true
            )

        case .error:
            // #26 owns the error chrome. Overlay surfaces only the close
            // affordance; the error layer renders above the overlay.
            return ControlSet(
                centre: .hidden,
                scrubEnabled: false,
                showsBufferingIndicator: false,
                bufferingReason: nil,
                showsClose: true,
                showsFullscreen: false,
                showsHealthHUD: false,
                showsTrackPickerEntries: false
            )
        }
    }

    /// Auto-hide is enabled in `.playing` only. Every other state pins the
    /// chrome visible so the user is never left with a paused frame and no
    /// way to act on it.
    static func mayAutoHide(in state: PlayerState) -> Bool {
        if case .playing = state { return true }
        return false
    }

    /// Reason-aware copy per design § D2 (buffering reasons) and brand §
    /// Voice (calm, concrete, British English).
    ///
    /// Forwarder retained for the existing `PlayerOverlayPolicyTests` suite
    /// — the canonical strings live in `PlayerCopy.swift` per #26's
    /// single-audit-surface rule. New call sites should reference
    /// `PlayerCopy.bufferingPrimary(for:)` directly.
    static func bufferingCopy(for reason: BufferingReason) -> String {
        PlayerCopy.bufferingPrimary(for: reason)
    }
}
