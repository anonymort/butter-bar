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
    @State private var showingAudioPicker: Bool = false

    /// Auto-hide delay after pointer idle while `.playing`. Injected so tests
    /// don't have to wait three real seconds.
    private let autoHideDelay: Duration

    init(streamDescriptor: StreamDescriptorDTO,
         engineClient: EngineClient,
         torrentID: String? = nil,
         fileIndex: Int32? = nil,
         autoHideDelay: Duration = .seconds(3)) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(
            streamDescriptor: streamDescriptor,
            engineClient: engineClient,
            torrentID: torrentID,
            fileIndex: fileIndex
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

            // Chrome overlay — issue #24. Audio picker entry point wired in #23.
            PlayerOverlay(
                state: viewModel.state,
                health: viewModel.health,
                title: streamTitle,
                currentSeconds: viewModel.currentSeconds,
                durationSeconds: viewModel.durationSeconds,
                isFullscreen: isFullscreen,
                showLongBufferingSecondary: viewModel.showLongBufferingSecondary,
                onPlay: { viewModel.play() },
                onPause: { viewModel.pause() },
                onClose: { viewModel.close() },
                onToggleFullscreen: toggleFullscreen,
                onScrub: { seconds in viewModel.seek(toSeconds: seconds) },
                onOpenAudioPicker: { showingAudioPicker = true }
            )
            .opacity(effectiveOverlayOpacity)
            .animation(.easeInOut(duration: 0.2), value: effectiveOverlayOpacity)
            .allowsHitTesting(effectiveOverlayOpacity > 0)
            .sheet(isPresented: $showingAudioPicker) {
                AudioPickerView(
                    viewModel: AudioPickerViewModel(
                        provider: viewModel.player?.currentItem.flatMap {
                            AVPlayerItemAudioProvider(item: $0)
                        },
                        state: viewModel.state
                    ),
                    onDismiss: { showingAudioPicker = false }
                )
            }

            // Error chrome — distinct surface per `PlayerError` case (#26).
            // Sits above the overlay so the user's recovery path is
            // unambiguous. `lastKnownTier` is captured by the VM so the
            // .playbackFailed surface can include a calm context hint.
            if case .error(let err) = viewModel.state {
                PlayerErrorChrome(
                    error: err,
                    lastKnownTier: viewModel.lastKnownTier,
                    onRetry: { viewModel.retry() },
                    onClose: { viewModel.close() }
                )
                .transition(.opacity)
            }

            // Resume prompt overlay (#19). Renders only while the VM has
            // an active offer; user choice / dismiss clears it through the
            // VM's resolve methods. Sits above the chrome overlay so the
            // user's first decision is visually unambiguous.
            if let offer = viewModel.resumePromptOffer {
                ResumePromptView(
                    offer: offer,
                    onContinue: { viewModel.resolveResumeContinue() },
                    onStartOver: { viewModel.resolveResumeStartOver() },
                    onDismiss: { viewModel.dismissResumePrompt() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.resumePromptOffer)
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
            // Defer playback start to the VM so the resume-prompt seam (#19)
            // can fire first. The VM auto-plays once the resume decision
            // settles with no prompt; if a prompt is shown the user's choice
            // routes through resolveResumeContinue / resolveResumeStartOver.
            viewModel.requestAutoPlayWhenReady()
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
