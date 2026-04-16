import AVFoundation
import EngineInterface
import SwiftUI

// MARK: - PlayerView

/// Full-screen player view. Dark by default regardless of system appearance.
///
/// Wraps `AVPlayerView` (via `AVPlayerViewRepresentable`) and floats
/// `StreamHealthHUD` over the video at the bottom-centre of the frame.
///
/// The HUD appears on mouse movement and auto-hides after 3 seconds of
/// inactivity. On first appearance the HUD is visible until the first
/// mouse movement that starts the timer.
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
            Color.black
                .ignoresSafeArea()

            if let player = viewModel.player {
                AVPlayerViewRepresentable(player: player)
                    .ignoresSafeArea()
            }

            // Error overlay — only shown if player initialisation failed.
            if let errorMessage = viewModel.error {
                errorOverlay(errorMessage)
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
        }
        .onDisappear {
            hideTask?.cancel()
            viewModel.close()
        }
    }

    // MARK: - HUD visibility

    private func showHUD() {
        hudVisible = true
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
