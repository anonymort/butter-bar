import AVFoundation
import AppKit
import EngineInterface
import PlayerDomain
import SwiftUI

// MARK: - PlayerView

/// Full-screen player view. Dark by default regardless of system appearance.
///
/// Wraps `AVPlayerView` (via `AVPlayerViewRepresentable`) and floats the
/// `PlayerOverlay` chrome (issue #24) above the video. The overlay handles
/// the top bar (title, close, fullscreen), the centre play/pause/buffering
/// affordance, and the bottom bar (scrub + tier HUD + picker entry-points).
///
/// Visibility policy:
/// - The overlay is always visible during `.open`, `.paused`, `.buffering(_)`,
///   and `.error(_)` per `PlayerOverlayPolicy.mayAutoHide`.
/// - During `.playing`, the overlay auto-hides 3 s after the pointer goes
///   idle and reappears on any pointer movement.
struct PlayerView: View {

    @StateObject private var viewModel: PlayerViewModel
    @State private var overlayVisible: Bool = true
    @State private var hideTask: Task<Void, Never>?
    @State private var isFullscreen: Bool = false

    /// Auto-hide delay after pointer idle while `.playing`. Injected so tests
    /// don't have to wait three real seconds.
    private let autoHideDelay: Duration

    init(streamDescriptor: StreamDescriptorDTO,
         engineClient: EngineClient,
         autoHideDelay: Duration = .seconds(3)) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(
            streamDescriptor: streamDescriptor,
            engineClient: engineClient
        ))
        self.autoHideDelay = autoHideDelay
    }

    var body: some View {
        ZStack {
            // Solid black behind the video — always dark regardless of system theme.
            BrandColors.videoLetterbox
                .ignoresSafeArea()

            if let player = viewModel.player {
                AVPlayerViewRepresentable(player: player)
                    .ignoresSafeArea()
            }

            // Chrome overlay — issue #24.
            PlayerOverlay(
                state: viewModel.state,
                health: viewModel.health,
                title: streamTitle,
                currentSeconds: viewModel.currentSeconds,
                durationSeconds: viewModel.durationSeconds,
                isFullscreen: isFullscreen,
                onPlay: { viewModel.play() },
                onPause: { viewModel.pause() },
                onClose: { viewModel.close() },
                onToggleFullscreen: toggleFullscreen,
                onScrub: { seconds in viewModel.seek(toSeconds: seconds) }
            )
            .opacity(effectiveOverlayOpacity)
            .animation(.easeInOut(duration: 0.2), value: effectiveOverlayOpacity)
            .allowsHitTesting(effectiveOverlayOpacity > 0)

            // Error overlay — derived from PlayerState per Phase 3 design.
            // #26 will replace this minimal text with brand-compliant
            // per-error-case chrome and a Retry affordance.
            if case .error(let err) = viewModel.state {
                errorOverlay(displayMessage(for: err))
            }
        }
        // Dark colour scheme enforced regardless of system appearance.
        .preferredColorScheme(.dark)
        // Track mouse movement to reset the auto-hide timer.
        .onContinuousHover { phase in
            switch phase {
            case .active:
                showOverlay()
            case .ended:
                break
            }
        }
        .onAppear {
            viewModel.play()
            scheduleHide(for: viewModel.state)
        }
        .onChange(of: viewModel.state) { _, newState in
            // Re-evaluate auto-hide policy whenever state changes — leaving
            // `.playing` should pin the chrome immediately, entering it
            // should restart the countdown.
            if PlayerOverlayPolicy.mayAutoHide(in: newState) {
                scheduleHide(for: newState)
            } else {
                hideTask?.cancel()
                overlayVisible = true
            }
        }
        .onDisappear {
            hideTask?.cancel()
            viewModel.close()
        }
    }

    // MARK: - Title

    private var streamTitle: String? {
        // The descriptor doesn't carry a human title in v1; fall back to nil
        // so the top bar reserves the slot without rendering a placeholder.
        nil
    }

    // MARK: - Overlay visibility

    /// Force-on whenever the policy says we cannot auto-hide. This keeps the
    /// chrome correct even if `overlayVisible` was left `false` from a prior
    /// `.playing` interval.
    private var effectiveOverlayOpacity: Double {
        if !PlayerOverlayPolicy.mayAutoHide(in: viewModel.state) { return 1 }
        return overlayVisible ? 1 : 0
    }

    private func showOverlay() {
        overlayVisible = true
        scheduleHide(for: viewModel.state)
    }

    /// Cancels any pending hide task. Starts a new countdown only if the
    /// current state allows auto-hiding.
    private func scheduleHide(for state: PlayerState) {
        hideTask?.cancel()
        guard PlayerOverlayPolicy.mayAutoHide(in: state) else {
            overlayVisible = true
            return
        }
        let delay = autoHideDelay
        hideTask = Task {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return  // cancelled — do nothing
            }
            await MainActor.run { overlayVisible = false }
        }
    }

    // MARK: - Fullscreen

    private func toggleFullscreen() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        window.toggleFullScreen(nil)
        // `toggleFullScreen` is async; observe the resulting style mask shortly
        // after to refresh the icon. A one-frame delay is enough.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isFullscreen = window.styleMask.contains(.fullScreen)
        }
    }

    // MARK: - Error overlay

    /// Map a `PlayerError` to interim display copy. #26 owns the final
    /// brand-voice copy + retry chrome; this is the minimal seam.
    private func displayMessage(for error: PlayerError) -> String {
        switch error {
        case .streamOpenFailed(let code):
            return "We couldn't open this stream (engine code \(code.rawValue))."
        case .xpcDisconnected:
            return "We lost contact with the engine."
        case .playbackFailed:
            return "Playback couldn't continue."
        case .streamLost:
            return "The stream is no longer available."
        }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 8) {
            Text("Playback unavailable")
                .brandBodyEmphasis()
                .foregroundStyle(BrandColors.cocoa)
            Text(message)
                .brandCaption()
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(BrandColors.cocoa.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Previews

#Preview("Player — dark (no live stream)") {
    // Preview without a live engine — shows black background with error state.
    PlayerView(
        streamDescriptor: StreamDescriptorDTO(
            streamID: "preview-stream",
            loopbackURL: "http://127.0.0.1:9999/stream/preview-stream",
            contentType: "video/mp4",
            contentLength: 0
        ),
        engineClient: EngineClient()
    )
    .frame(width: 960, height: 540)
}
