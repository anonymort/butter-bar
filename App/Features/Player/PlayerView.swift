import AVFoundation
import EngineInterface
import PlayerDomain
import SwiftUI

// MARK: - PlayerView

/// Full-screen player view. Dark by default regardless of system appearance.
///
/// Wraps `AVPlayerView` (via `AVPlayerViewRepresentable`) and floats
/// `StreamHealthHUD` over the video at the bottom-centre of the frame.
///
/// The HUD is visible on first appearance and auto-hides after 3 seconds of
/// inactivity — even if the mouse never moves. Mouse movement resets the
/// 3-second timer (existing behaviour).
struct PlayerView: View {

    @StateObject private var viewModel: PlayerViewModel
    @State private var hudVisible: Bool = true
    @State private var hideTask: Task<Void, Never>?

    init(streamDescriptor: StreamDescriptorDTO, engineClient: EngineClient) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(
            streamDescriptor: streamDescriptor,
            engineClient: engineClient
        ))
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

            // Error overlay — derived from PlayerState per Phase 3 design.
            // #26 will replace this minimal text with brand-compliant
            // per-error-case chrome and a Retry affordance.
            if case .error(let err) = viewModel.state {
                errorOverlay(displayMessage(for: err))
            }

            // HUD overlay — floats at bottom centre, 24 pt margin.
            if let health = viewModel.health {
                VStack {
                    Spacer()
                    StreamHealthHUD(health: health)
                        .padding(.bottom, 24)
                }
                .opacity(hudVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: hudVisible)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        // Dark colour scheme enforced regardless of system appearance.
        .preferredColorScheme(.dark)
        // Track mouse movement to show/hide HUD.
        .onContinuousHover { phase in
            switch phase {
            case .active:
                showHUD()
            case .ended:
                break
            }
        }
        .onAppear {
            viewModel.play()
            scheduleHide()
        }
        .onDisappear {
            hideTask?.cancel()
            viewModel.close()
        }
    }

    // MARK: - HUD visibility

    private func showHUD() {
        hudVisible = true
        scheduleHide()
    }

    /// Cancels any pending hide task and starts a new 3-second countdown.
    /// Called both from `.onAppear` (initial timer) and from `showHUD()` (reset on hover).
    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return  // cancelled — do nothing
            }
            await MainActor.run { hudVisible = false }
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
