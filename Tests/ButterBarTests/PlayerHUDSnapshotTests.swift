import XCTest
import SwiftUI
import SnapshotTesting
import EngineInterface
@testable import ButterBar

// MARK: - PlayerHUDSnapshotTests
//
// Tests `StreamHealthHUD` in isolation — no AVPlayer required.
// Snapshot baselines live alongside this file in
// __Snapshots__/PlayerHUDSnapshotTests/.
//
// First run: set record: .all to write baselines.
// Subsequent runs diff against the committed PNGs.
//
// Colour scheme is pinned to dark (per spec — player is always dark).

@MainActor
final class PlayerHUDSnapshotTests: XCTestCase {

    // HUD is rendered at a fixed width that matches a compact player window.
    private let snapshotSize = CGSize(width: 480, height: 80)

    // MARK: - Healthy tier

    func testHUDHealthyTier() {
        let view = StreamHealthHUD(health: .healthy)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
            .background(Color.black)

        assertSnapshot(
            of: view,
            as: .image(layout: .fixed(width: snapshotSize.width, height: snapshotSize.height)),
            named: "dark-healthy"
        )
    }

    // MARK: - Marginal tier

    func testHUDMarginalTier() {
        let view = StreamHealthHUD(health: .marginal)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
            .background(Color.black)

        assertSnapshot(
            of: view,
            as: .image(layout: .fixed(width: snapshotSize.width, height: snapshotSize.height)),
            named: "dark-marginal"
        )
    }

    // MARK: - Starving tier

    func testHUDStarvingTier() {
        let view = StreamHealthHUD(health: .starving)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
            .background(Color.black)

        assertSnapshot(
            of: view,
            as: .image(layout: .fixed(width: snapshotSize.width, height: snapshotSize.height)),
            named: "dark-starving"
        )
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
