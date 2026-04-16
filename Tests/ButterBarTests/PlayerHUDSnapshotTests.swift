import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
import EngineInterface
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

// MARK: - PlayerHUDSnapshotTests
//
// Tests `StreamHealthHUD` in isolation — no AVPlayer required.
// Snapshot baselines live alongside this file in
// __Snapshots__/PlayerHUDSnapshotTests/.
//
// First run: set record: .all to write baselines.
// Subsequent runs diff against the committed PNGs.
//
// Both colour schemes are covered (per spec 06 § Test obligations: "Snapshot
// tests for tier colour rendering at all three tiers in both light and dark
// modes"). The player window is always dark in production, but the HUD is
// tested in both modes to verify the light/dark tier colour variants render
// correctly as standalone components.

@MainActor
final class PlayerHUDSnapshotTests: XCTestCase {

    // HUD is rendered at a fixed width that matches a compact player window.
    private let snapshotSize = CGSize(width: 480, height: 80)

    private func snapshotView(health: StreamHealthDTO, colorScheme: ColorScheme) -> some View {
        ZStack {
            if colorScheme == .dark {
                Color.black
            } else {
                BrandColors.cream
            }
            StreamHealthHUD(health: health)
        }
    }

    // MARK: - Healthy tier

    func testHUDHealthyTier() {
        let view = snapshotView(health: .healthy, colorScheme: .dark)

        assertSnapshot(
            of: rendered(view, size: snapshotSize, colorScheme: .dark),
            as: .image,
            named: "dark-healthy"
        )
    }

    // MARK: - Marginal tier

    func testHUDMarginalTier() {
        let view = snapshotView(health: .marginal, colorScheme: .dark)

        assertSnapshot(
            of: rendered(view, size: snapshotSize, colorScheme: .dark),
            as: .image,
            named: "dark-marginal"
        )
    }

    // MARK: - Starving tier

    func testHUDStarvingTier() {
        let view = snapshotView(health: .starving, colorScheme: .dark)

        assertSnapshot(
            of: rendered(view, size: snapshotSize, colorScheme: .dark),
            as: .image,
            named: "dark-starving"
        )
    }

    // MARK: - Light mode variants
    //
    // Per spec 06 § Test obligations, tier colour rendering must be verified
    // in both modes. Background is `cream` in light mode (matches what the
    // HUD would sit on if ever composed into a light-scheme surface).

    func testHUDHealthyTier_lightMode() {
        let view = snapshotView(health: .healthy, colorScheme: .light)

        assertSnapshot(
            of: rendered(view, size: snapshotSize, colorScheme: .light),
            as: .image,
            named: "light-healthy"
        )
    }

    func testHUDMarginalTier_lightMode() {
        let view = snapshotView(health: .marginal, colorScheme: .light)

        assertSnapshot(
            of: rendered(view, size: snapshotSize, colorScheme: .light),
            as: .image,
            named: "light-marginal"
        )
    }

    func testHUDStarvingTier_lightMode() {
        let view = snapshotView(health: .starving, colorScheme: .light)

        assertSnapshot(
            of: rendered(view, size: snapshotSize, colorScheme: .light),
            as: .image,
            named: "light-starving"
        )
    }
}

@MainActor
final class PlayerViewModelReconnectTests: XCTestCase {

    func testEventsDidChangeNotificationIsDeliveredOnMainThread() async {
        let engineClient = EngineClient()
        let notificationExpectation = expectation(description: "eventsDidChange notification")
        let observer = NotificationCenter.default.addObserver(
            forName: EngineClient.eventsDidChangeNotification,
            object: engineClient,
            queue: nil
        ) { _ in
            XCTAssertTrue(Thread.isMainThread, "eventsDidChange should be delivered on main thread")
            notificationExpectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await engineClient._replaceEventHandlerForTesting(EngineEventHandler())
        await fulfillment(of: [notificationExpectation], timeout: 1.0)
    }

    func testPlayerViewModelResubscribesAfterEngineReconnect() async throws {
        let engineClient = EngineClient()
        let streamID = "stream-reconnect-1"
        let descriptor = StreamDescriptorDTO(
            streamID: streamID as NSString,
            loopbackURL: "http://127.0.0.1:52100/stream/\(streamID)" as NSString,
            contentType: "video/mp4",
            contentLength: 10_000
        )
        let viewModel = PlayerViewModel(streamDescriptor: descriptor, engineClient: engineClient)

        let firstHandler = EngineEventHandler()
        await engineClient._replaceEventHandlerForTesting(firstHandler)
        try await Task.sleep(for: .milliseconds(50))

        firstHandler.streamHealthChanged(
            StreamHealthDTO(
                streamID: streamID as NSString,
                secondsBufferedAhead: 12,
                downloadRateBytesPerSec: 500_000,
                requiredBitrateBytesPerSec: nil,
                peerCount: 4,
                outstandingCriticalPieces: 0,
                recentStallCount: 0,
                tier: "healthy"
            )
        )
        try await assertEventually("initial health should arrive") {
            (viewModel.health?.tier as String?) == "healthy"
        }

        let secondHandler = EngineEventHandler()
        await engineClient._replaceEventHandlerForTesting(secondHandler)
        try await Task.sleep(for: .milliseconds(50))

        secondHandler.streamHealthChanged(
            StreamHealthDTO(
                streamID: streamID as NSString,
                secondsBufferedAhead: 2,
                downloadRateBytesPerSec: 90_000,
                requiredBitrateBytesPerSec: nil,
                peerCount: 1,
                outstandingCriticalPieces: 3,
                recentStallCount: 3,
                tier: "starving"
            )
        )
        try await assertEventually("health should resume from replacement handler") {
            (viewModel.health?.tier as String?) == "starving"
        }

        firstHandler.streamHealthChanged(
            StreamHealthDTO(
                streamID: streamID as NSString,
                secondsBufferedAhead: 6,
                downloadRateBytesPerSec: 200_000,
                requiredBitrateBytesPerSec: nil,
                peerCount: 2,
                outstandingCriticalPieces: 1,
                recentStallCount: 1,
                tier: "marginal"
            )
        )
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.health?.tier as String?, "starving")
    }

    private func assertEventually(
        _ message: String,
        timeout: Duration = .seconds(1),
        poll: Duration = .milliseconds(10),
        condition: @escaping () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: poll)
        }
        XCTFail("Timed out: \(message)")
    }
}

// MARK: - StreamHealthDTO test fixtures

private extension StreamHealthDTO {

    static var healthy: StreamHealthDTO {
        StreamHealthDTO(
            streamID: "test-healthy",
            secondsBufferedAhead: 42.0,
            downloadRateBytesPerSec: 4_300_000,
            requiredBitrateBytesPerSec: nil,
            peerCount: 8,
            outstandingCriticalPieces: 0,
            recentStallCount: 0,
            tier: "healthy"
        )
    }

    static var marginal: StreamHealthDTO {
        StreamHealthDTO(
            streamID: "test-marginal",
            secondsBufferedAhead: 14.0,
            downloadRateBytesPerSec: 1_100_000,
            requiredBitrateBytesPerSec: nil,
            peerCount: 3,
            outstandingCriticalPieces: 0,
            recentStallCount: 1,
            tier: "marginal"
        )
    }

    static var starving: StreamHealthDTO {
        StreamHealthDTO(
            streamID: "test-starving",
            secondsBufferedAhead: 4.0,
            downloadRateBytesPerSec: 200_000,
            requiredBitrateBytesPerSec: nil,
            peerCount: 1,
            outstandingCriticalPieces: 3,
            recentStallCount: 4,
            tier: "starving"
        )
    }
}
