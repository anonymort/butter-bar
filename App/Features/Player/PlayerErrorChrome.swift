import EngineInterface
import PlayerDomain
import SwiftUI

// MARK: - PlayerErrorChrome
//
// Error overlay rendered above the video when `PlayerState == .error(_)`.
// One layout per `PlayerError` case driven by `PlayerCopy`. Brand-compliant
// per `06-brand.md § Window chrome` / `§ Voice` — calm copy, no system
// colours, no exclamation marks. The engine error code (when applicable) is
// rendered in a small monospaced detail strip so support handoff has a
// stable token to grep for.
//
// Two affordances on every surface: Retry and Close. Both are required by
// issue #26 AC. The Close button uses the calm secondary treatment so the
// Retry button reads as the primary action without screaming.
//
// Hosted by `PlayerView` and laid above `PlayerOverlay` so the user's
// recovery path is visually unambiguous.

struct PlayerErrorChrome: View {

    let error: PlayerError
    /// Last-known engine tier captured by the VM before entering `.error(_)`.
    /// Used only by `.playbackFailed` to surface a calm context hint when
    /// the engine was already starving at the moment playback stopped.
    let lastKnownTier: StreamHealthTier?
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // Soft scrim so the video underneath doesn't compete for the
            // user's eye. `cocoa` (warm dark) at low opacity stays inside
            // the brand palette.
            BrandColors.cocoa
                .opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                // Click-outside is intentionally not bound — the user must
                // pick Retry or Close so the resolution path is explicit.

            panel
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(PlayerCopy.errorTitle(for: error))
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(PlayerCopy.errorTitle(for: error))
                .brandBodyEmphasis()
                .foregroundStyle(BrandColors.cocoa)
                .fixedSize(horizontal: false, vertical: true)

            Text(PlayerCopy.errorBody(for: error))
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoaSoft)
                .fixedSize(horizontal: false, vertical: true)

            if case .playbackFailed = error,
               let hint = PlayerCopy.playbackFailedTierHint(for: lastKnownTier) {
                Text(hint)
                    .brandCaption()
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let code = engineErrorCode {
                Text(PlayerCopy.engineCodeDetail(for: code))
                    .brandCaptionMonospacedNumeric()
                    .foregroundStyle(BrandColors.cocoaFaint)
                    .padding(.top, 2)
            }

            actions
                .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 360)
        .background(BrandColors.creamRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: BrandColors.cocoa.opacity(0.35),
                radius: 18, x: 0, y: 8)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Text(PlayerCopy.closeButtonLabel)
                    .brandBodyRegular()
                    .foregroundStyle(BrandColors.cocoa)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(BrandColors.cream)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel(PlayerCopy.closeButtonLabel)

            Button(action: onRetry) {
                Text(PlayerCopy.retryButtonLabel)
                    .brandBodyEmphasis()
                    .foregroundStyle(BrandColors.cocoa)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .background(BrandColors.butter)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel(PlayerCopy.retryButtonLabel)
        }
    }

    /// Engine error code, when one applies. Only `.streamOpenFailed(_)`
    /// carries one in v1; the others render no monospaced detail strip.
    private var engineErrorCode: EngineErrorCode? {
        if case .streamOpenFailed(let code) = error { return code }
        return nil
    }
}

// MARK: - PlayerBufferingChrome
//
// Reason-aware buffering overlay used by `PlayerOverlay`. Lives next to the
// error chrome because both are #26's responsibility and share the calm
// progress register. Driven by `PlayerCopy` so the audit surface stays one
// file. The long-buffering secondary line is decided by the caller via
// `PlayerCopy.shouldShowLongStarvingLine`; this view just renders.

struct PlayerBufferingChrome: View {

    let reason: BufferingReason
    /// Whether to surface the secondary "still trying — your network or
    /// this torrent's peers may be slow" line. Decided upstream by
    /// `PlayerCopy.shouldShowLongStarvingLine` against an injected clock.
    var showLongBufferingSecondary: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            // Calm pulsing pill rather than an Apple spinner per
            // `06-brand.md § Motion` — no system progress chrome.
            Capsule()
                .fill(BrandColors.butter)
                .frame(width: 96, height: 4)
                .opacity(0.8)

            Text(PlayerCopy.bufferingPrimary(for: reason))
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoa)
                .fixedSize(horizontal: false, vertical: true)

            if showSecondary {
                Text(PlayerCopy.bufferingLongStarvingSecondary)
                    .brandCaption()
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(BrandColors.creamRaised.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var showSecondary: Bool {
        // Per AC: the long-buffering line is only meaningful for
        // `.engineStarving`. The two other reasons resolve quickly enough
        // that a "still trying" line would imply a stalled state we don't
        // actually know we're in.
        showLongBufferingSecondary && reason == .engineStarving
    }

    private var accessibilityLabel: String {
        var label = PlayerCopy.bufferingPrimary(for: reason)
        if showSecondary {
            label += ". " + PlayerCopy.bufferingLongStarvingSecondary
        }
        return label
    }
}

// MARK: - Previews

#Preview("Error — streamOpenFailed (torrentNotFound) — dark") {
    ZStack {
        BrandColors.videoLetterbox
        PlayerErrorChrome(
            error: .streamOpenFailed(.torrentNotFound),
            lastKnownTier: nil,
            onRetry: {},
            onClose: {}
        )
    }
    .frame(width: 960, height: 540)
    .preferredColorScheme(.dark)
}

#Preview("Error — playbackFailed (starving hint) — dark") {
    ZStack {
        BrandColors.videoLetterbox
        PlayerErrorChrome(
            error: .playbackFailed,
            lastKnownTier: .starving,
            onRetry: {},
            onClose: {}
        )
    }
    .frame(width: 960, height: 540)
    .preferredColorScheme(.dark)
}

#Preview("Error — xpcDisconnected — light") {
    ZStack {
        BrandColors.videoLetterbox
        PlayerErrorChrome(
            error: .xpcDisconnected,
            lastKnownTier: nil,
            onRetry: {},
            onClose: {}
        )
    }
    .frame(width: 960, height: 540)
    .preferredColorScheme(.light)
}

#Preview("Buffering — engineStarving (long secondary) — dark") {
    ZStack {
        BrandColors.videoLetterbox
        PlayerBufferingChrome(reason: .engineStarving,
                              showLongBufferingSecondary: true)
    }
    .frame(width: 960, height: 540)
    .preferredColorScheme(.dark)
}
