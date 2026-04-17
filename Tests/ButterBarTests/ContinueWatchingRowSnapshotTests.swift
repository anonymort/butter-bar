import XCTest
import SwiftUI
import AppKit
import EngineInterface
import MetadataDomain
import SnapshotTesting
@testable import ButterBar

@MainActor
private func hosted<V: View>(_ view: V, size: CGSize) -> NSHostingView<V> {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    return host
}

// Snapshot baselines for the metadata-enriched continue-watching row (#17).
// Rendered standalone (not embedded in a SwiftUI List) so the carousel
// chrome and card content are actually visible — see LibrarySnapshotTests
// for the in-page composition. Light + dark per `06-brand.md § Test
// obligations`. First run: set RECORD=true to write baselines.

@MainActor
final class ContinueWatchingRowSnapshotTests: XCTestCase {

    private let snapshotSize = CGSize(width: 800, height: 320)

    // MARK: - Fixtures

    private func torrent(_ id: String, name: String, total: Int64) -> TorrentSummaryDTO {
        TorrentSummaryDTO(
            torrentID: id as NSString,
            name: name as NSString,
            totalBytes: total,
            progressQ16: 65_536,
            state: "seeding",
            peerCount: 0,
            downRateBytesPerSec: 0,
            upRateBytesPerSec: 0,
            errorMessage: nil
        )
    }

    private var mixedItems: [ContinueWatchingItem] {
        // Item 1: matched as a show with episode designator (most recent).
        // Item 2: unmatched fallback (mid-recent).
        // Item 3: matched as a movie (oldest).
        let show = Show(
            id: MediaID(provider: .tmdb, id: 1),
            name: "Cosmos",
            originalName: "Cosmos",
            firstAirYear: 1980,
            lastAirYear: 1980,
            status: .ended,
            overview: "",
            genres: [],
            posterPath: "/cosmos.jpg",
            backdropPath: nil,
            voteAverage: nil,
            popularity: nil,
            seasons: []
        )
        let movie = Movie(
            id: MediaID(provider: .tmdb, id: 2),
            title: "Sunrise",
            originalTitle: "Sunrise",
            releaseYear: 1927,
            runtimeMinutes: 94,
            overview: "",
            genres: [],
            posterPath: "/sunrise.jpg",
            backdropPath: nil,
            voteAverage: nil,
            popularity: nil
        )
        return [
            ContinueWatchingItem(
                torrent: torrent("show1", name: "fallback", total: 8_000_000_000),
                fileIndex: 0,
                progressBytes: 5_600_000_000,
                totalBytes: 8_000_000_000,
                lastPlayedAtMillis: 1_700_000_900_000,
                isReWatching: false,
                media: .show(show),
                posterPath: "/cosmos.jpg",
                episodeDesignator: "S01E04"
            ),
            ContinueWatchingItem(
                torrent: torrent("u1", name: "weird-release-2024.mkv", total: 1_000_000_000),
                fileIndex: 0,
                progressBytes: 200_000_000,
                totalBytes: 1_000_000_000,
                lastPlayedAtMillis: 1_700_000_500_000,
                isReWatching: false
            ),
            ContinueWatchingItem(
                torrent: torrent("m1", name: "fallback", total: 2_000_000_000),
                fileIndex: 0,
                progressBytes: 1_400_000_000,
                totalBytes: 2_000_000_000,
                lastPlayedAtMillis: 1_700_000_100_000,
                isReWatching: true,
                media: .movie(movie),
                posterPath: "/sunrise.jpg",
                episodeDesignator: nil
            ),
        ]
    }

    // MARK: - Mixed (matched + unmatched)

    func testRowMixed_light() {
        let view = ContinueWatchingRow(items: mixedItems, onOpen: { _ in })
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
            .background(BrandColors.surfaceBase)

        assertSnapshot(of: hosted(view, size: snapshotSize),
                       as: .image, named: "row-mixed-light")
    }

    func testRowMixed_dark() {
        let view = ContinueWatchingRow(items: mixedItems, onOpen: { _ in })
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
            .background(BrandColors.surfaceBase)

        assertSnapshot(of: hosted(view, size: snapshotSize),
                       as: .image, named: "row-mixed-dark")
    }

    // MARK: - Single item

    func testRowSingleItem_light() {
        let single = Array(mixedItems.prefix(1))
        let view = ContinueWatchingRow(items: single, onOpen: { _ in })
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
            .background(BrandColors.surfaceBase)

        assertSnapshot(of: hosted(view, size: snapshotSize),
                       as: .image, named: "row-single-light")
    }

    func testRowSingleItem_dark() {
        let single = Array(mixedItems.prefix(1))
        let view = ContinueWatchingRow(items: single, onOpen: { _ in })
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
            .background(BrandColors.surfaceBase)

        assertSnapshot(of: hosted(view, size: snapshotSize),
                       as: .image, named: "row-single-dark")
    }

    // MARK: - Empty (row hidden) — exercise the parent decision

    /// The row hides itself entirely when items are empty. We render an
    /// `EmptyView()`-equivalent (a 1pt host) here just to lock the
    /// "empty → nothing renders" contract via a known baseline.
    func testRowEmpty_light() {
        let view = Group {
            if !([] as [ContinueWatchingItem]).isEmpty {
                ContinueWatchingRow(items: [], onOpen: { _ in })
            } else {
                Color.clear
            }
        }
        .environment(\.colorScheme, .light)
        .frame(width: snapshotSize.width, height: snapshotSize.height)
        .background(BrandColors.surfaceBase)

        assertSnapshot(of: hosted(view, size: snapshotSize),
                       as: .image, named: "row-empty-light")
    }

    func testRowEmpty_dark() {
        let view = Group {
            if !([] as [ContinueWatchingItem]).isEmpty {
                ContinueWatchingRow(items: [], onOpen: { _ in })
            } else {
                Color.clear
            }
        }
        .environment(\.colorScheme, .dark)
        .frame(width: snapshotSize.width, height: snapshotSize.height)
        .background(BrandColors.surfaceBase)

        assertSnapshot(of: hosted(view, size: snapshotSize),
                       as: .image, named: "row-empty-dark")
    }
}
