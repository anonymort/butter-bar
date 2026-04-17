import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
import MetadataDomain
@testable import ButterBar

/// Snapshot baselines for `UpNextOverlay` light + dark per
/// `06-brand.md § Test obligations`. Calm copy register — no
/// "Starting in 3… 2… 1…" — and brand tokens only.
@MainActor
final class UpNextOverlaySnapshotTests: XCTestCase {

    private let snapshotSize = CGSize(width: 480, height: 320)

    private func render<V: View>(_ view: V, colorScheme: ColorScheme) -> NSImage {
        let renderer = ImageRenderer(
            content: view
                .environment(\.colorScheme, colorScheme)
                .frame(width: snapshotSize.width, height: snapshotSize.height)
        )
        renderer.proposedSize = ProposedViewSize(snapshotSize)
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            XCTFail("Could not render SwiftUI snapshot image")
            return NSImage(size: snapshotSize)
        }
        return NSImage(cgImage: cgImage, size: snapshotSize)
    }

    private var sampleEpisode: Episode {
        Episode(
            id: MediaID(provider: .tmdb, id: 99),
            showID: MediaID(provider: .tmdb, id: 42),
            seasonNumber: 2,
            episodeNumber: 5,
            name: "The Bear Necessities",
            overview: "Carmy stretches every dish on the new tasting menu.",
            stillPath: "/sample.jpg",
            runtimeMinutes: 32,
            airDate: nil
        )
    }

    private func snapshotView(secondsRemaining: Int,
                              colorScheme: ColorScheme) -> some View {
        let offer = NextEpisodeOffer(next: sampleEpisode, artworkURL: nil)
        return ZStack {
            BrandColors.videoLetterbox
            UpNextOverlay(
                offer: offer,
                secondsRemaining: secondsRemaining,
                onPlayNow: {},
                onCancel: {}
            )
        }
    }

    // MARK: - Mid-countdown

    func testUpNext_midCountdown_dark() {
        assertSnapshot(
            of: render(snapshotView(secondsRemaining: 7, colorScheme: .dark),
                       colorScheme: .dark),
            as: .image,
            named: "dark-mid"
        )
    }

    func testUpNext_midCountdown_light() {
        assertSnapshot(
            of: render(snapshotView(secondsRemaining: 7, colorScheme: .light),
                       colorScheme: .light),
            as: .image,
            named: "light-mid"
        )
    }

    // MARK: - One second left (lower-bound rendering)

    func testUpNext_oneSecondLeft_dark() {
        assertSnapshot(
            of: render(snapshotView(secondsRemaining: 1, colorScheme: .dark),
                       colorScheme: .dark),
            as: .image,
            named: "dark-final"
        )
    }

    func testUpNext_oneSecondLeft_light() {
        assertSnapshot(
            of: render(snapshotView(secondsRemaining: 1, colorScheme: .light),
                       colorScheme: .light),
            as: .image,
            named: "light-final"
        )
    }
}
