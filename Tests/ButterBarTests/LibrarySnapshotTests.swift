import XCTest
import SwiftUI
import SnapshotTesting
@testable import ButterBar

// MARK: - LibrarySnapshotTests
//
// Snapshot baselines live alongside this file in
// __Snapshots__/LibrarySnapshotTests/.
//
// First run: set RECORD=true (or set record: .all below) to write baselines.
// Subsequent runs diff against the committed PNGs.
//
// Color scheme is pinned per-test via .environment(\.colorScheme, _) so tests
// are stable regardless of the host machine's system appearance.

@MainActor
final class LibrarySnapshotTests: XCTestCase {

    // 800 × 600 matches a typical compact library window.
    private let snapshotSize = CGSize(width: 800, height: 600)

    // MARK: - Populated (light)

    func testLibraryViewLightPopulated() {
        let view = LibraryView(viewModel: .previewWithData)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: view,
            as: .image(layout: .fixed(width: snapshotSize.width, height: snapshotSize.height)),
            named: "light-populated"
        )
    }

    // MARK: - Populated (dark)

    func testLibraryViewDarkPopulated() {
        let view = LibraryView(viewModel: .previewWithData)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: view,
            as: .image(layout: .fixed(width: snapshotSize.width, height: snapshotSize.height)),
            named: "dark-populated"
        )
    }

    // MARK: - Empty (light)

    func testLibraryViewLightEmpty() {
        let view = LibraryView(viewModel: .previewEmpty)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: view,
            as: .image(layout: .fixed(width: snapshotSize.width, height: snapshotSize.height)),
            named: "light-empty"
        )
    }

    // MARK: - Empty (dark)

    func testLibraryViewDarkEmpty() {
        let view = LibraryView(viewModel: .previewEmpty)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: view,
            as: .image(layout: .fixed(width: snapshotSize.width, height: snapshotSize.height)),
            named: "dark-empty"
        )
    }
}
