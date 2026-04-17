import EngineInterface
import PlayerDomain
import SwiftUI

// MARK: - PlayerOverlay
//
// Floating chrome above the video, per issue #24 + `06-brand.md § Window
// chrome` and `§ Liquid Glass`. Three zones:
//
// - Top bar: title (when known), close, fullscreen toggle.
// - Centre: large play / pause / buffering indicator, gated by `PlayerState`.
// - Bottom bar: scrub bar, subtitle / audio entry-points (placeholders for
//   #22 / #23), StreamHealthHUD inset for tier + secondary stats.
//
// Visibility is decided by the caller (`PlayerView`) using `mayAutoHide`
// against the current state; this view simply renders whatever it is told to.
// Liquid Glass material is applied to the top and bottom rows only — never
// to the centre play affordance, which floats free over the video.

struct PlayerOverlay: View {

    let state: PlayerState
    let health: StreamHealthDTO?
    let title: String?
    let currentSeconds: Double
    let durationSeconds: Double
    let isFullscreen: Bool

    let onPlay: () -> Void
    let onPause: () -> Void
    let onClose: () -> Void
    let onToggleFullscreen: () -> Void
    let onScrub: (Double) -> Void
    /// Placeholder hooks for #22 / #23. Default to no-ops; #22/#23 will pass
    /// real handlers when they wire the picker chrome.
    var onOpenSubtitlePicker: () -> Void = {}
    var onOpenAudioPicker: () -> Void = {}

    private var controls: PlayerOverlayPolicy.ControlSet {
        PlayerOverlayPolicy.controls(for: state)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .overlayChromeSurface()
                .padding(.horizontal, 12)
                .padding(.top, 12)

            Spacer(minLength: 0)

            centreLayer

            Spacer(minLength: 0)

            bottomBar
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlayChromeSurface()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Don't intercept hover/click on transparent regions between zones —
        // that lets the video hover-to-show behaviour in PlayerView keep
        // working.
        .allowsHitTesting(true)
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            if controls.showsClose {
                overlayButton(
                    systemImage: "xmark",
                    label: "Close player",
                    action: onClose
                )
            }

            if let title, !title.isEmpty {
                Text(title)
                    .brandBodyEmphasis()
                    .foregroundStyle(BrandColors.cocoa)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                // Reserve the title slot so the trailing controls don't jump.
                Color.clear.frame(height: 1)
            }

            Spacer()

            if controls.showsFullscreen {
                overlayButton(
                    systemImage: isFullscreen
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right",
                    label: isFullscreen ? "Exit full screen" : "Enter full screen",
                    action: onToggleFullscreen
                )
            }
        }
    }

    // MARK: - Centre layer

    @ViewBuilder
    private var centreLayer: some View {
        if controls.showsBufferingIndicator, let reason = controls.bufferingReason {
            bufferingIndicator(reason: reason)
        } else {
            switch controls.centre {
            case .hidden:
                EmptyView()
            case .play:
                centrePrimaryButton(systemImage: "play.fill",
                                    label: "Play",
                                    action: onPlay)
            case .pause:
                centrePrimaryButton(systemImage: "pause.fill",
                                    label: "Pause",
                                    action: onPause)
            }
        }
    }

    private func centrePrimaryButton(systemImage: String,
                                     label: String,
                                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(BrandColors.cocoa)
                .frame(width: 72, height: 72)
                .background(
                    Circle()
                        .fill(BrandColors.butter)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Buffering chrome: calm, no spinner per `06-brand.md § Motion`. Reason
    /// copy supplied by `PlayerOverlayPolicy.bufferingCopy`.
    private func bufferingIndicator(reason: BufferingReason) -> some View {
        VStack(spacing: 10) {
            // A pulsing buffer-coloured pill rather than an Apple spinner.
            // The HUD already carries the live "n s ready" value — this is the
            // calm headline so the user knows we know what's going on.
            Capsule()
                .fill(BrandColors.butter)
                .frame(width: 96, height: 4)
                .opacity(0.8)

            Text(PlayerOverlayPolicy.bufferingCopy(for: reason))
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoa)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlayChromeSurface()
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            PlayerScrubBar(
                currentSeconds: currentSeconds,
                durationSeconds: durationSeconds,
                isEnabled: controls.scrubEnabled,
                onScrub: onScrub
            )

            HStack(spacing: 12) {
                if controls.showsHealthHUD, let health {
                    StreamHealthHUD(health: health)
                }

                Spacer(minLength: 0)

                if controls.showsTrackPickerEntries {
                    overlayButton(
                        systemImage: "captions.bubble",
                        label: "Subtitles",
                        action: onOpenSubtitlePicker,
                        // #22 wires the real picker; entry-point is disabled
                        // until then to avoid implying functionality we don't
                        // ship yet (per brand voice: don't suggest features
                        // we cannot deliver).
                        enabled: false
                    )
                    overlayButton(
                        systemImage: "speaker.wave.2",
                        label: "Audio track",
                        action: onOpenAudioPicker,
                        enabled: false
                    )
                }
            }
        }
    }

    // MARK: - Buttons

    private func overlayButton(systemImage: String,
                               label: String,
                               action: @escaping () -> Void,
                               enabled: Bool = true) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(enabled ? BrandColors.cocoa : BrandColors.cocoaFaint)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Surface modifier

private extension View {
    /// Liquid Glass surface for chrome rows. Glass only on the chrome —
    /// never on the video underneath (per `06-brand.md § Liquid Glass`).
    func overlayChromeSurface() -> some View {
        self
            .glassEffect(.regular.tint(BrandColors.butter).interactive())
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Overlay — playing") {
    PlayerOverlay(
        state: .playing,
        health: StreamHealthDTO(
            streamID: "preview",
            secondsBufferedAhead: 28.0,
            downloadRateBytesPerSec: 3_400_000,
            requiredBitrateBytesPerSec: nil,
            peerCount: 6,
            outstandingCriticalPieces: 0,
            recentStallCount: 0,
            tier: "healthy"
        ),
        title: "Big Buck Bunny",
        currentSeconds: 184,
        durationSeconds: 596,
        isFullscreen: false,
        onPlay: {},
        onPause: {},
        onClose: {},
        onToggleFullscreen: {},
        onScrub: { _ in }
    )
    .frame(width: 960, height: 540)
    .background(BrandColors.videoLetterbox)
    .preferredColorScheme(.dark)
}

#Preview("Overlay — buffering (engine starving)") {
    PlayerOverlay(
        state: .buffering(reason: .engineStarving),
        health: StreamHealthDTO(
            streamID: "preview",
            secondsBufferedAhead: 2.0,
            downloadRateBytesPerSec: 80_000,
            requiredBitrateBytesPerSec: nil,
            peerCount: 1,
            outstandingCriticalPieces: 4,
            recentStallCount: 2,
            tier: "starving"
        ),
        title: "Big Buck Bunny",
        currentSeconds: 184,
        durationSeconds: 596,
        isFullscreen: false,
        onPlay: {},
        onPause: {},
        onClose: {},
        onToggleFullscreen: {},
        onScrub: { _ in }
    )
    .frame(width: 960, height: 540)
    .background(BrandColors.videoLetterbox)
    .preferredColorScheme(.dark)
}
