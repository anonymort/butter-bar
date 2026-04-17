import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
import EngineInterface
import PlayerDomain
@testable import ButterBar

/// Snapshot baselines for the buffering chrome — one per `BufferingReason`
/// in light + dark, plus the long-buffering secondary line. Per
/// `06-brand.md § Test obligations` and issue #26 AC.
@MainActor
final class PlayerBufferingChromeTests: XCTestCase {

    private let snapshotSize = CGSize(width: 960, height: 540)

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

    private func chrome(reason: BufferingReason,
                        showLongSecondary: Bool = false) -> some View {
        ZStack {
            BrandColors.videoLetterbox
            PlayerBufferingChrome(
                reason: reason,
                showLongBufferingSecondary: showLongSecondary
            )
        }
    }

    private func snap(_ name: String, view: some View, colorScheme: ColorScheme) {
        assertSnapshot(
            of: render(view, colorScheme: colorScheme),
            as: .image,
            named: name
        )
    }

    // MARK: - One snapshot per reason × scheme

    func testBuffering_openingStream_dark() {
        snap("dark-openingStream",
             view: chrome(reason: .openingStream),
             colorScheme: .dark)
    }
    func testBuffering_openingStream_light() {
        snap("light-openingStream",
             view: chrome(reason: .openingStream),
             colorScheme: .light)
    }
    func testBuffering_engineStarving_dark() {
        snap("dark-engineStarving",
             view: chrome(reason: .engineStarving),
             colorScheme: .dark)
    }
    func testBuffering_engineStarving_light() {
        snap("light-engineStarving",
             view: chrome(reason: .engineStarving),
             colorScheme: .light)
    }
    func testBuffering_playerRebuffering_dark() {
        snap("dark-playerRebuffering",
             view: chrome(reason: .playerRebuffering),
             colorScheme: .dark)
    }
    func testBuffering_playerRebuffering_light() {
        snap("light-playerRebuffering",
             view: chrome(reason: .playerRebuffering),
             colorScheme: .light)
    }

    // MARK: - Long-buffering secondary line

    func testBuffering_engineStarving_longSecondary_dark() {
        snap("dark-engineStarving-long",
             view: chrome(reason: .engineStarving, showLongSecondary: true),
             colorScheme: .dark)
    }
    func testBuffering_engineStarving_longSecondary_light() {
        snap("light-engineStarving-long",
             view: chrome(reason: .engineStarving, showLongSecondary: true),
             colorScheme: .light)
    }
}

// MARK: - Long-buffering threshold (pure logic, no snapshots)

/// The 30-second threshold for surfacing the secondary line lives in
/// `PlayerCopy.longStarvingThreshold`. The decision is exposed through
/// `PlayerCopy.shouldShowLongStarvingLine(bufferingStartedAt:now:)` so it
/// can be tested with an injected clock.
@MainActor
final class PlayerLongBufferingThresholdTests: XCTestCase {

    func test_noBufferingStart_returnsFalse() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertFalse(
            PlayerCopy.shouldShowLongStarvingLine(bufferingStartedAt: nil, now: now)
        )
    }

    func test_belowThreshold_returnsFalse() {
        let started = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = started.addingTimeInterval(PlayerCopy.longStarvingThreshold - 1)
        XCTAssertFalse(
            PlayerCopy.shouldShowLongStarvingLine(bufferingStartedAt: started, now: now)
        )
    }

    func test_atThreshold_returnsTrue() {
        let started = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = started.addingTimeInterval(PlayerCopy.longStarvingThreshold)
        XCTAssertTrue(
            PlayerCopy.shouldShowLongStarvingLine(bufferingStartedAt: started, now: now)
        )
    }

    func test_aboveThreshold_returnsTrue() {
        let started = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = started.addingTimeInterval(PlayerCopy.longStarvingThreshold + 30)
        XCTAssertTrue(
            PlayerCopy.shouldShowLongStarvingLine(bufferingStartedAt: started, now: now)
        )
    }
}
