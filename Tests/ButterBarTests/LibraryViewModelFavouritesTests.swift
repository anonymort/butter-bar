import XCTest
import EngineInterface
@testable import ButterBar

@MainActor
final class LibraryViewModelFavouritesTests: XCTestCase {

    private func makeVM() -> LibraryViewModel {
        let vm = LibraryViewModel(client: EngineClient())
        vm.skipRefresh = true
        return vm
    }

    private func torrent(_ id: String, name: String) -> TorrentSummaryDTO {
        TorrentSummaryDTO(
            torrentID: id as NSString,
            name: name as NSString,
            totalBytes: 1_000_000,
            progressQ16: 0,
            state: "seeding",
            peerCount: 0,
            downRateBytesPerSec: 0,
            upRateBytesPerSec: 0,
            errorMessage: nil
        )
    }

    private func favourite(_ torrentID: String, fileIndex: Int = 0,
                           favouritedAt: Int64 = 1_700_000_000_000) -> FavouriteDTO {
        FavouriteDTO(
            torrentID: torrentID as NSString,
            fileIndex: Int32(fileIndex),
            favouritedAt: favouritedAt
        )
    }

    // MARK: - isFavourite

    func testIsFavourite_falseWhenAbsent() {
        let vm = makeVM()
        XCTAssertFalse(vm.isFavourite(torrentID: "t1", fileIndex: 0))
    }

    func testIsFavourite_trueWhenPresent() {
        let vm = makeVM()
        vm.favourites["t1#0"] = favourite("t1")
        XCTAssertTrue(vm.isFavourite(torrentID: "t1", fileIndex: 0))
        XCTAssertFalse(vm.isFavourite(torrentID: "t1", fileIndex: 1),
                       "different fileIndex must not be considered favourited")
    }

    // MARK: - displayedTorrents

    func testDisplayedTorrents_passThroughWhenFavouritesOnlyOff() {
        let vm = makeVM()
        vm.torrents = [torrent("t1", name: "A"), torrent("t2", name: "B")]
        XCTAssertEqual(vm.displayedTorrents.count, 2)
    }

    func testDisplayedTorrents_filtersWhenFavouritesOnlyOn() {
        let vm = makeVM()
        vm.torrents = [torrent("t1", name: "A"), torrent("t2", name: "B"), torrent("t3", name: "C")]
        vm.favourites["t1#0"] = favourite("t1")
        vm.favourites["t3#0"] = favourite("t3")
        vm.favouritesOnly = true

        let ids = vm.displayedTorrents.map { $0.torrentID as String }
        XCTAssertEqual(Set(ids), ["t1", "t3"],
                       "favouritesOnly must include only favourited torrents")
    }

    func testDisplayedTorrents_emptyWhenNoFavouritesAndOnlyFlag() {
        let vm = makeVM()
        vm.torrents = [torrent("t1", name: "A")]
        vm.favouritesOnly = true
        XCTAssertTrue(vm.displayedTorrents.isEmpty)
    }

    // MARK: - Preview fixture

    func testPreviewFixtureExposesFavourites() {
        let vm = LibraryViewModel.previewWithFavourites
        XCTAssertTrue(vm.isFavourite(torrentID: "abc123", fileIndex: 0))
        XCTAssertTrue(vm.isFavourite(torrentID: "def456", fileIndex: 0))
        XCTAssertFalse(vm.isFavourite(torrentID: "ghi789", fileIndex: 0))
    }
}
