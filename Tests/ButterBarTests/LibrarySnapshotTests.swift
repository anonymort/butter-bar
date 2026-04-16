import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
@testable import ButterBar

// Helper: wrap a SwiftUI view in an NSHostingView sized for snapshotting.
// The macOS snapshot API takes an NSView, not a SwiftUI View.
@MainActor
private func hosted<V: View>(_ view: V, size: CGSize) -> NSHostingView<V> {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    return host
}

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
            of: hosted(view, size: snapshotSize),
            as: .image,
            named: "light-populated"
        )
    }

    // MARK: - Populated (dark)

    func testLibraryViewDarkPopulated() {
        let view = LibraryView(viewModel: .previewWithData)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: hosted(view, size: snapshotSize),
            as: .image,
            named: "dark-populated"
        )
    }

    // MARK: - Empty (light)

    func testLibraryViewLightEmpty() {
        let view = LibraryView(viewModel: .previewEmpty)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: hosted(view, size: snapshotSize),
            as: .image,
            named: "light-empty"
        )
    }

    // MARK: - Empty (dark)

    func testLibraryViewDarkEmpty() {
        let view = LibraryView(viewModel: .previewEmpty)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: hosted(view, size: snapshotSize),
            as: .image,
            named: "dark-empty"
        )
    }

    // MARK: - Watch state (#37) — badges visible

    func testLibraryViewLightWatchState() {
        let view = LibraryView(viewModel: .previewWithWatchState)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: hosted(view, size: snapshotSize),
            as: .image,
            named: "light-watch-state"
        )
    }

    func testLibraryViewDarkWatchState() {
        let view = LibraryView(viewModel: .previewWithWatchState)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: hosted(view, size: snapshotSize),
            as: .image,
            named: "dark-watch-state"
        )
    }

    // MARK: - Continue watching (#35)

    func testLibraryViewLightContinueWatching() {
        let view = LibraryView(viewModel: .previewWithContinueWatching)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: hosted(view, size: snapshotSize),
            as: .image,
            named: "light-continue-watching"
        )
    }

    func testLibraryViewDarkContinueWatching() {
        let view = LibraryView(viewModel: .previewWithContinueWatching)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: hosted(view, size: snapshotSize),
            as: .image,
            named: "dark-continue-watching"
        )
    }

    // MARK: - Favourites (#36)

    func testLibraryViewLightFavourites() {
        let view = LibraryView(viewModel: .previewWithFavourites)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: hosted(view, size: snapshotSize),
            as: .image,
            named: "light-favourites"
        )
    }

    func testLibraryViewDarkFavourites() {
        let view = LibraryView(viewModel: .previewWithFavourites)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)

        assertSnapshot(
            of: hosted(view, size: snapshotSize),
            as: .image,
            named: "dark-favourites"
        )
    }
}
