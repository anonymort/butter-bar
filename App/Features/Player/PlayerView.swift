import AVFoundation
import AppKit
import EngineInterface
import MetadataDomain
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
    @StateObject private var nextEpisodeCoordinator: NextEpisodeCoordinator
    @State private var overlayVisible: Bool = true
    @State private var hideTask: Task<Void, Never>?
    @State private var isFullscreen: Bool = false
    @State private var showingAudioPicker: Bool = false
    @State private var showingSubtitlePicker: Bool = false
    @State private var isDropTargeted: Bool = false
    @FocusState private var hasKeyboardFocus: Bool

    /// Auto-hide delay after pointer idle while `.playing`. Injected so tests
    /// don't have to wait three real seconds.
    private let autoHideDelay: Duration

    init(streamDescriptor: StreamDescriptorDTO,
         engineClient: EngineClient,
         torrentID: String? = nil,
         fileIndex: Int32? = nil,
         currentEpisode: Episode? = nil,
         currentShow: Show? = nil,
         metadataProvider: MetadataProvider? = nil,
         autoHideDelay: Duration = .seconds(3)) {
        let provider: MetadataProvider = metadataProvider ?? TMDBProvider(
            config: .init(bearerToken: TMDBSecrets.tmdbAccessToken)
        )
        let vm = PlayerViewModel(
            streamDescriptor: streamDescriptor,
            engineClient: engineClient,
            torrentID: torrentID,
            fileIndex: fileIndex,
            currentEpisode: currentEpisode,
            currentShow: currentShow
        )
        _viewModel = StateObject(wrappedValue: vm)
        _nextEpisodeCoordinator = StateObject(wrappedValue: NextEpisodeCoordinator(
            metadata: provider,
            openStream: { episode in
                Task { @MainActor in vm.openNextEpisode(episode) }
            }
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

            // Subtitle overlay — cue text centred in the lower third. Sits
            // above the video but below the chrome and resume prompt.
            SubtitleOverlay(controller: viewModel.subtitleController)

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
                onOpenSubtitlePicker: { showingSubtitlePicker = true },
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
            .sheet(isPresented: $showingSubtitlePicker) {
                SubtitlePickerView(
                    viewModel: SubtitlePickerViewModel(
                        controller: viewModel.subtitleController,
                        state: viewModel.state
                    ),
                    onDismiss: { showingSubtitlePicker = false }
                )
            }

            // Subtitle error banner. Visibility tracks
            // the chrome overlay so the controls hide together with the HUD.
            VStack(spacing: 8) {
                Spacer()
                SubtitleErrorBanner(controller: viewModel.subtitleController)
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .center)
            .opacity(effectiveOverlayOpacity)
            .animation(.easeInOut(duration: 0.2), value: effectiveOverlayOpacity)
            .allowsHitTesting(effectiveOverlayOpacity > 0)

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

            if let offer = nextEpisodeCoordinator.offer {
                UpNextOverlay(
                    offer: offer,
                    secondsRemaining: nextEpisodeCoordinator.secondsRemaining,
                    onPlayNow: { nextEpisodeCoordinator.playNow() },
                    onCancel: { nextEpisodeCoordinator.cancel() }
                )
                .transition(.opacity)
            }

            if let message = viewModel.transientMessage {
                transientBanner(message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.resumePromptOffer)
        // SRT drag-and-drop: accept .fileURL drops over the player.
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                viewModel.subtitleController.ingestSidecar(provider)
            }
            return true
        }
        // Dark colour scheme enforced regardless of system appearance.
        .preferredColorScheme(.dark)
        .focusable()
        .focused($hasKeyboardFocus)
        .onKeyPress(.space) {
            handleKeyboardShortcut(.playPause)
        }
        .onKeyPress(.leftArrow) {
            handleKeyboardShortcut(.seekBackward)
        }
        .onKeyPress(.rightArrow) {
            handleKeyboardShortcut(.seekForward)
        }
        .onKeyPress("f") {
            handleKeyboardShortcut(.toggleFullscreen)
        }
        .onKeyPress(.escape) {
            handleKeyboardShortcut(.escape)
        }
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
            hasKeyboardFocus = true
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

    private func exitFullscreen() {
        guard isFullscreen else { return }
        toggleFullscreen()
    }

    private func handleKeyboardShortcut(_ shortcut: PlayerKeyboardShortcut) -> KeyPress.Result {
        guard shortcut.isEnabled(in: viewModel.state) else { return .ignored }
        switch shortcut {
        case .playPause:
            if viewModel.state == .paused {
                viewModel.play()
            } else {
                viewModel.pause()
            }
        case .seekBackward:
            viewModel.seek(toSeconds: max(0, viewModel.currentSeconds - 10))
        case .seekForward:
            let target = viewModel.currentSeconds + 10
            if viewModel.durationSeconds > 0 {
                viewModel.seek(toSeconds: min(viewModel.durationSeconds, target))
            } else {
                viewModel.seek(toSeconds: target)
            }
        case .toggleFullscreen:
            toggleFullscreen()
        case .escape:
            if isFullscreen {
                exitFullscreen()
            } else {
                viewModel.close()
            }
        }
        return .handled
    }

    private func transientBanner(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .brandCaption()
                .foregroundStyle(BrandColors.cocoa)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(BrandColors.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.bottom, 96)
        }
    }

}

enum PlayerKeyboardShortcut: Equatable {
    case playPause
    case seekBackward
    case seekForward
    case toggleFullscreen
    case escape

    func isEnabled(in state: PlayerState) -> Bool {
        switch state {
        case .playing, .paused, .buffering:
            return true
        case .closed, .open, .error:
            return false
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
