import XCTest
import EngineInterface
@testable import ButterBar

@MainActor
final class LibraryViewModelContinueWatchingTests: XCTestCase {

    private func makeVM() -> LibraryViewModel {
        let vm = LibraryViewModel(client: EngineClient())
        vm.skipRefresh = true
        return vm
    }

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

    private func history(torrentID: String, fileIndex: Int = 0,
                         resume: Int64, lastPlayed: Int64,
                         completed: Bool = false, completedAt: Int64? = nil) -> PlaybackHistoryDTO {
        PlaybackHistoryDTO(
            torrentID: torrentID as NSString,
            fileIndex: Int32(fileIndex),
            resumeByteOffset: resume,
            lastPlayedAt: lastPlayed,
            totalWatchedSeconds: 0,
            completed: completed,
            completedAt: completedAt.map { NSNumber(value: $0) }
        )
    }

    // MARK: - Empty / hidden

    func testEmptyWhenNoTorrents() {
        let vm = makeVM()
        XCTAssertTrue(vm.continueWatching.isEmpty)
    }

    func testEmptyWhenNoHistoryRows() {
        let vm = makeVM()
        vm.torrents = [torrent("t1", name: "A", total: 1_000_000)]
        XCTAssertTrue(vm.continueWatching.isEmpty)
    }

    func testWatchedRowExcluded() {
        let vm = makeVM()
        vm.torrents = [torrent("t1", name: "A", total: 1_000_000)]
        vm.playbackHistory["t1#0"] = history(
            torrentID: "t1",
            resume: 0,
            lastPlayed: 1_000,
            completed: true,
            completedAt: 1_000
        )
        XCTAssertTrue(vm.continueWatching.isEmpty,
                      ".watched row must be excluded from continue-watching")
    }

    func testUnwatchedRowExcluded() {
        // resumeByteOffset = 0 with no completion → unwatched.
        let vm = makeVM()
        vm.torrents = [torrent("t1", name: "A", total: 1_000_000)]
        vm.playbackHistory["t1#0"] = history(torrentID: "t1", resume: 0, lastPlayed: 1_000)
        XCTAssertTrue(vm.continueWatching.isEmpty)
    }

    // MARK: - Inclusion + sort

    func testInProgressIncluded() {
        let vm = makeVM()
        vm.torrents = [torrent("t1", name: "Movie", total: 1_000_000)]
        vm.playbackHistory["t1#0"] = history(torrentID: "t1", resume: 250_000, lastPlayed: 1_000)

        let items = vm.continueWatching
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].isReWatching)
        XCTAssertEqual(items[0].progressBytes, 250_000)
        XCTAssertEqual(items[0].totalBytes, 1_000_000)
    }

    func testReWatchingIncluded() {
        let vm = makeVM()
        vm.torrents = [torrent("t2", name: "Show", total: 5_000_000)]
        vm.playbackHistory["t2#0"] = history(
            torrentID: "t2",
            resume: 1_500_000,
            lastPlayed: 2_000,
            completed: true,
            completedAt: 1_000
        )

        let items = vm.continueWatching
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isReWatching)
        XCTAssertEqual(items[0].progressBytes, 1_500_000)
    }

    func testSortByLastPlayedDescending() {
        let vm = makeVM()
        vm.torrents = [
            torrent("t1", name: "Older", total: 1_000_000),
            torrent("t2", name: "Newer", total: 1_000_000),
            torrent("t3", name: "Middle", total: 1_000_000),
        ]
        vm.playbackHistory["t1#0"] = history(torrentID: "t1", resume: 100, lastPlayed: 1_000)
        vm.playbackHistory["t2#0"] = history(torrentID: "t2", resume: 200, lastPlayed: 9_000)
        vm.playbackHistory["t3#0"] = history(torrentID: "t3", resume: 300, lastPlayed: 5_000)

        let items = vm.continueWatching
        XCTAssertEqual(items.map(\.id), ["t2#0", "t3#0", "t1#0"])
    }

    // MARK: - Projection regenerates on map mutation

    func testProjectionUpdatesAfterPlaybackHistoryMutation() {
        let vm = makeVM()
        vm.torrents = [torrent("t1", name: "A", total: 1_000_000)]

        XCTAssertTrue(vm.continueWatching.isEmpty)

        vm.playbackHistory["t1#0"] = history(torrentID: "t1", resume: 100, lastPlayed: 1_000)
        XCTAssertEqual(vm.continueWatching.count, 1)

        // Simulate a mark-watched event echo: move to .watched.
        vm.playbackHistory["t1#0"] = history(
            torrentID: "t1",
            resume: 0,
            lastPlayed: 2_000,
            completed: true,
            completedAt: 2_000
        )
        XCTAssertTrue(vm.continueWatching.isEmpty,
                      "after mark-watched echo, item must drop out of continue-watching")
    }

    // MARK: - Preview fixture sanity

    func testPreviewFixtureExposesInProgressAndReWatching() {
        let vm = LibraryViewModel.previewWithContinueWatching
        let items = vm.continueWatching
        XCTAssertEqual(items.count, 2, "expected exactly 2 items (Cosmos reWatching + General inProgress)")
        // Sorted desc by lastPlayedAt: General (1_700_000_500_000) first.
        XCTAssertEqual(items[0].torrent.torrentID as String, "ghi789")
        XCTAssertFalse(items[0].isReWatching)
        XCTAssertEqual(items[1].torrent.torrentID as String, "abc123")
        XCTAssertTrue(items[1].isReWatching)
    }
}
