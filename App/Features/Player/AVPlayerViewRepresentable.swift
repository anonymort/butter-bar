import AVKit
import SwiftUI

// MARK: - AVPlayerViewRepresentable

/// Wraps `AVPlayerView` (AppKit) for use in SwiftUI via `NSViewRepresentable`.
struct AVPlayerViewRepresentable: NSViewRepresentable {

    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // Only update if the player instance changed; avoids unnecessary churn.
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
