import XCTest
import EngineInterface
import LibraryDomain
@testable import ButterBar

/// Unit tests for `LibraryViewModel`'s watch-state surface.
///
/// These exercise pure projection logic — `watchStatus(torrentID:fileIndex:totalBytes:)`
/// against the in-memory `playbackHistory` map — and the key formula. The
/// async `markWatched` / `markUnwatched` methods route through `EngineClient`
/// (which would require an XPC mock); they're verified end-to-end via the
/// existing `XPCPlaybackHistoryTests` in the EngineInterface package.
@MainActor
final class LibraryViewModelWatchStateTests: XCTestCase {

    private func makeVM() -> LibraryViewModel {
        let vm = LibraryViewModel(client: EngineClient())
        vm.skipRefresh = true
        return vm
    }

    // MARK: - Key stability

    func testKeyFormulaIsStable() {
        XCTAssertEqual(LibraryViewModel.key(for: "abc123", fileIndex: 0), "abc123#0")
        XCTAssertEqual(LibraryViewModel.key(for: "abc123", fileIndex: 42), "abc123#42")
    }

    // MARK: - watchStatus derivation

    func testUnknownTorrentReturnsUnwatched() {
        let vm = makeVM()
        let s = vm.watchStatus(torrentID: "missing", fileIndex: 0, totalBytes: 1_000_000)
        XCTAssertEqual(s, .unwatched)
    }

    func testInProgressDerivedFromMap() {
        let vm = makeVM()
        vm.playbackHistory["t1#0"] = PlaybackHistoryDTO(
            torrentID: "t1",
            fileIndex: 0,
            resumeByteOffset: 250_000,
            lastPlayedAt: 1_700_000_000_000,
            totalWatchedSeconds: 0,
            completed: false,
            completedAt: nil
        )
        let s = vm.watchStatus(torrentID: "t1", fileIndex: 0, totalBytes: 1_000_000)
        XCTAssertEqual(s, .inProgress(progressBytes: 250_000, totalBytes: 1_000_000))
    }

    func testWatchedDerivedFromMap() {
        let vm = makeVM()
        let when = Int64(1_700_000_300_000)
        vm.playbackHistory["t2#1"] = PlaybackHistoryDTO(
            torrentID: "t2",
            fileIndex: 1,
            resumeByteOffset: 0,
            lastPlayedAt: when,
            totalWatchedSeconds: 0,
            completed: true,
            completedAt: NSNumber(value: when)
        )
        let s = vm.watchStatus(torrentID: "t2", fileIndex: 1, totalBytes: 5_000_000)
        guard case .watched(let date) = s else {
            return XCTFail("expected .watched, got \(s)")
        }
        XCTAssertEqual(date.timeIntervalSince1970, TimeInterval(when) / 1000.0, accuracy: 0.001)
    }

    func testReWatchingDerivedFromMap() {
        let vm = makeVM()
        let originalWhen = Int64(1_699_000_000_000)
        vm.playbackHistory["t3#0"] = PlaybackHistoryDTO(
            torrentID: "t3",
            fileIndex: 0,
            resumeByteOffset: 100_000,
            lastPlayedAt: 1_700_000_400_000,
            totalWatchedSeconds: 0,
            completed: true,
            completedAt: NSNumber(value: originalWhen)
        )
        let s = vm.watchStatus(torrentID: "t3", fileIndex: 0, totalBytes: 1_000_000)
        guard case .reWatching(let p, let t, let prev) = s else {
            return XCTFail("expected .reWatching, got \(s)")
        }
        XCTAssertEqual(p, 100_000)
        XCTAssertEqual(t, 1_000_000)
        XCTAssertEqual(prev.timeIntervalSince1970, TimeInterval(originalWhen) / 1000.0, accuracy: 0.001)
    }

    // MARK: - Preview fixture sanity

    func testPreviewWithWatchStateExposesAllThreeStates() {
        let vm = LibraryViewModel.previewWithWatchState
        // Cosmos: reWatching
        let cosmos = vm.watchStatus(torrentID: "abc123", fileIndex: 0, totalBytes: 8_589_934_592)
        if case .reWatching = cosmos {} else {
            XCTFail("expected .reWatching for Cosmos, got \(cosmos)")
        }
        // Night of the Living Dead: watched
        let night = vm.watchStatus(torrentID: "def456", fileIndex: 0, totalBytes: 734_003_200)
        if case .watched = night {} else {
            XCTFail("expected .watched for Night of the Living Dead, got \(night)")
        }
        // The General: no playback history → unwatched
        let general = vm.watchStatus(torrentID: "ghi789", fileIndex: 0, totalBytes: 1_073_741_824)
        XCTAssertEqual(general, .unwatched)
    }
}
