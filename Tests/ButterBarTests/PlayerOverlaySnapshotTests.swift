import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
import EngineInterface
import PlayerDomain
@testable import ButterBar

// Render a SwiftUI view at a fixed size for macOS snapshot capture.
@MainActor
private func rendered<V: View>(_ view: V, size: CGSize, colorScheme: ColorScheme) -> NSImage {
    let renderer = ImageRenderer(
        content: view
            .environment(\.colorScheme, colorScheme)
            .frame(width: size.width, height: size.height)
    )
    renderer.proposedSize = ProposedViewSize(size)
    renderer.scale = 2

    guard let cgImage = renderer.cgImage else {
        XCTFail("Could not render SwiftUI snapshot image")
        return NSImage(size: size)
    }
    return NSImage(cgImage: cgImage, size: size)
}

// MARK: - PlayerOverlaySnapshotTests
//
// One snapshot per `PlayerState` value, in both colour schemes. Per
// `06-brand.md § Test obligations`. Baselines committed under
// __Snapshots__/PlayerOverlaySnapshotTests/.
//
// Note: snapshots are CI-advisory (`continue-on-error: true` in ci.yml) — a
// pixel diff between local and the hosted runner won't fail the merge.

@MainActor
final class PlayerOverlaySnapshotTests: XCTestCase {

    private let snapshotSize = CGSize(width: 960, height: 540)

    // MARK: - Helpers

    private func overlay(state: PlayerState,
                         health: StreamHealthDTO? = .healthy,
                         currentSeconds: Double = 184,
                         durationSeconds: Double = 596) -> some View {
        ZStack {
            // Solid backdrop simulating the video. Use letterbox black so the
            // overlay rendering is faithful to the production composition.
            BrandColors.videoLetterbox
            PlayerOverlay(
                state: state,
                health: health,
                title: "Big Buck Bunny",
                currentSeconds: currentSeconds,
                durationSeconds: durationSeconds,
                isFullscreen: false,
                onPlay: {},
                onPause: {},
                onClose: {},
                onToggleFullscreen: {},
                onScrub: { _ in }
            )
        }
    }

    private func snapshot(_ state: PlayerState,
                          health: StreamHealthDTO?,
                          named: String,
                          colorScheme: ColorScheme) {
        let view = overlay(state: state, health: health)
        assertSnapshot(
            of: rendered(view, size: snapshotSize, colorScheme: colorScheme),
            as: .image,
            named: named
        )
    }

    // MARK: - .closed

    func testOverlayClosed_dark() {
        snapshot(.closed, health: nil, named: "dark-closed", colorScheme: .dark)
    }
    func testOverlayClosed_light() {
        snapshot(.closed, health: nil, named: "light-closed", colorScheme: .light)
    }

    // MARK: - .open

    func testOverlayOpen_dark() {
        snapshot(.open, health: .healthy, named: "dark-open", colorScheme: .dark)
    }
    func testOverlayOpen_light() {
        snapshot(.open, health: .healthy, named: "light-open", colorScheme: .light)
    }

    // MARK: - .playing

    func testOverlayPlaying_dark() {
        snapshot(.playing, health: .healthy, named: "dark-playing", colorScheme: .dark)
    }
    func testOverlayPlaying_light() {
        snapshot(.playing, health: .healthy, named: "light-playing", colorScheme: .light)
    }

    // MARK: - .paused

    func testOverlayPaused_dark() {
        snapshot(.paused, health: .marginal, named: "dark-paused", colorScheme: .dark)
    }
    func testOverlayPaused_light() {
        snapshot(.paused, health: .marginal, named: "light-paused", colorScheme: .light)
    }

    // MARK: - .buffering(_) — one snapshot per reason

    func testOverlayBufferingOpening_dark() {
        snapshot(.buffering(reason: .openingStream),
                 health: .marginal,
                 named: "dark-buffering-openingStream",
                 colorScheme: .dark)
    }
    func testOverlayBufferingOpening_light() {
        snapshot(.buffering(reason: .openingStream),
                 health: .marginal,
                 named: "light-buffering-openingStream",
                 colorScheme: .light)
    }

    func testOverlayBufferingStarving_dark() {
        snapshot(.buffering(reason: .engineStarving),
                 health: .starving,
                 named: "dark-buffering-engineStarving",
                 colorScheme: .dark)
    }
    func testOverlayBufferingStarving_light() {
        snapshot(.buffering(reason: .engineStarving),
                 health: .starving,
                 named: "light-buffering-engineStarving",
                 colorScheme: .light)
    }

    func testOverlayBufferingRebuffering_dark() {
        snapshot(.buffering(reason: .playerRebuffering),
                 health: .marginal,
                 named: "dark-buffering-playerRebuffering",
                 colorScheme: .dark)
    }
    func testOverlayBufferingRebuffering_light() {
        snapshot(.buffering(reason: .playerRebuffering),
                 health: .marginal,
                 named: "light-buffering-playerRebuffering",
                 colorScheme: .light)
    }

    // MARK: - .error

    func testOverlayError_dark() {
        snapshot(.error(.playbackFailed),
                 health: nil,
                 named: "dark-error",
                 colorScheme: .dark)
    }
    func testOverlayError_light() {
        snapshot(.error(.playbackFailed),
                 health: nil,
                 named: "light-error",
                 colorScheme: .light)
    }
}

// MARK: - StreamHealthDTO test fixtures
//
// Local copies (deliberately not shared with PlayerHUDSnapshotTests' fileprivate
// extension to avoid coupling the two test files; same shape, different IDs).

private extension StreamHealthDTO {
    static var healthy: StreamHealthDTO {
        StreamHealthDTO(
            streamID: "overlay-healthy",
            secondsBufferedAhead: 28.0,
            downloadRateBytesPerSec: 3_400_000,
            requiredBitrateBytesPerSec: nil,
            peerCount: 6,
            outstandingCriticalPieces: 0,
            recentStallCount: 0,
            tier: "healthy"
        )
    }
    static var marginal: StreamHealthDTO {
        StreamHealthDTO(
            streamID: "overlay-marginal",
            secondsBufferedAhead: 11.0,
            downloadRateBytesPerSec: 900_000,
            requiredBitrateBytesPerSec: nil,
            peerCount: 3,
            outstandingCriticalPieces: 0,
            recentStallCount: 1,
            tier: "marginal"
        )
    }
    static var starving: StreamHealthDTO {
        StreamHealthDTO(
            streamID: "overlay-starving",
            secondsBufferedAhead: 2.0,
            downloadRateBytesPerSec: 80_000,
            requiredBitrateBytesPerSec: nil,
            peerCount: 1,
            outstandingCriticalPieces: 4,
            recentStallCount: 2,
            tier: "starving"
        )
    }
}
