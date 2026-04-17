import SubtitleDomain
import SwiftUI

// MARK: - SubtitleOverlay

/// Renders the currently active subtitle cue centred in the lower third of
/// the player frame. Hidden when `currentCue` is `nil`.
///
/// Typography from `BrandTypography`. Text floats with a soft shadow rather
/// than a hard background fill, matching the calm overlay aesthetic.
///
/// For embedded tracks, `currentCue` is always `nil` (AVKit renders them
/// directly). The overlay is only active for sidecar tracks.
struct SubtitleOverlay: View {

    @ObservedObject var controller: SubtitleController

    var body: some View {
        if let cue = controller.currentCue {
            GeometryReader { proxy in
                VStack {
                    Spacer()
                    // Position in the lower third.
                    Text(cue.text)
                        .brandBodyRegular()
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                        .frame(maxWidth: proxy.size.width * 0.85)
                    Spacer()
                        .frame(height: proxy.size.height * 0.12)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .allowsHitTesting(false)
            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        }
    }
}
