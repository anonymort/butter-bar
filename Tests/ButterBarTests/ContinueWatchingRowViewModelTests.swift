import XCTest
import EngineInterface
import MetadataDomain
@testable import ButterBar

/// Behaviour tests for the LibraryViewModel surface that drives the
/// continue-watching row (#17). Asserts the view-model contract — live
/// update on playbackHistoryChanged, empty-state hides the row, and
/// the metadata-enriched projection round-trips through the resolver.
@MainActor
final class ContinueWatchingRowViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func torrent(_ id: String, name: String, total: Int64 = 1_000_000) -> TorrentSummaryDTO {
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

    private func history(torrentID: String, resume: Int64, lastPlayed: Int64,
                         completed: Bool = false, completedAt: Int64? = nil) -> PlaybackHistoryDTO {
        PlaybackHistoryDTO(
            torrentID: torrentID as NSString,
            fileIndex: 0,
            resumeByteOffset: resume,
            lastPlayedAt: lastPlayed,
            totalWatchedSeconds: 0,
            completed: completed,
            completedAt: completedAt.map { NSNumber(value: $0) }
        )
    }

    private func makeVM(provider: StubProvider = StubProvider()) -> LibraryViewModel {
        let resolver = LibraryMetadataResolver(
            provider: provider,
            clock: { Date(timeIntervalSince1970: 1_000_000) }
        )
        let vm = LibraryViewModel(client: EngineClient(), metadataResolver: resolver)
        vm.skipRefresh = true
        return vm
    }

    // MARK: - Empty state hides row

    func testEmptyDisplayWhenNoHistory() async {
        let vm = makeVM()
        vm.torrents = [torrent("t1", name: "A")]
        await vm.refreshContinueWatching()

        XCTAssertTrue(vm.displayContinueWatching.isEmpty,
                      "with no in-progress rows, displayContinueWatching is empty so LibraryView hides the row entirely")
    }

    func testEmptyDisplayWhenAllRowsAreWatched() async {
        let vm = makeVM()
        vm.torrents = [torrent("t1", name: "A")]
        vm.playbackHistory["t1#0"] = history(torrentID: "t1", resume: 0, lastPlayed: 1,
                                             completed: true, completedAt: 1)
        await vm.refreshContinueWatching()

        XCTAssertTrue(vm.displayContinueWatching.isEmpty)
    }

    // MARK: - Resolver-backed enrichment populates the row

    func testEnrichedItemPopulatedFromResolver() async {
        let provider = StubProvider()
        provider.searchHandler = { _ in
            [.movie(Movie(
                id: MediaID(provider: .tmdb, id: 1),
                title: "Inception",
                originalTitle: "Inception",
                releaseYear: 2010,
                runtimeMinutes: 100,
                overview: "",
                genres: [],
                posterPath: "/inception.jpg",
                backdropPath: nil,
                voteAverage: nil,
                popularity: nil
            ))]
        }
        let vm = makeVM(provider: provider)
        // The torrent name is what `LibraryMetadataResolver`'s file lookup
        // falls back to (the resolver in this VM uses the engine listFiles
        // closure; with `skipRefresh = true` we never connect, so the
        // closure's `try? await client.listFiles` returns nil and the
        // resolver falls back to `torrent.name`). Use a recognizable
        // title here so the parser/ranker produces a positive match.
        vm.torrents = [torrent("t1", name: "Inception.2010.1080p.BluRay.x264.mkv")]
        vm.playbackHistory["t1#0"] = history(torrentID: "t1", resume: 250_000, lastPlayed: 1)

        await vm.refreshContinueWatching()

        XCTAssertEqual(vm.displayContinueWatching.count, 1)
        XCTAssertEqual(vm.displayContinueWatching[0].displayTitle, "Inception")
        XCTAssertEqual(vm.displayContinueWatching[0].posterPath, "/inception.jpg")
    }

    // MARK: - Live update on history mutation

    func testLiveUpdateAfterHistoryMutation() async {
        let vm = makeVM()
        vm.torrents = [torrent("t1", name: "A")]
        await vm.refreshContinueWatching()
        XCTAssertTrue(vm.displayContinueWatching.isEmpty)

        // Simulate the engine echoing a new in-progress row (the
        // production sink does this synchronously; here we mutate +
        // re-resolve directly to keep the test deterministic).
        vm.playbackHistory["t1#0"] = history(torrentID: "t1", resume: 250_000, lastPlayed: 2)
        await vm.refreshContinueWatching()
        XCTAssertEqual(vm.displayContinueWatching.count, 1)

        // Mark-watched echo: should remove the item.
        vm.playbackHistory["t1#0"] = history(torrentID: "t1", resume: 0, lastPlayed: 3,
                                             completed: true, completedAt: 3)
        await vm.refreshContinueWatching()
        XCTAssertTrue(vm.displayContinueWatching.isEmpty,
                      "post mark-watched, the enriched row must drop out")
    }

    // MARK: - Display fallback when resolver is absent

    func testDisplayFallsBackToRawProjectionWithoutResolver() {
        // Snapshot/preview paths construct VMs without a resolver. The
        // raw projection still drives the row.
        let vm = LibraryViewModel(client: EngineClient())
        vm.skipRefresh = true
        vm.torrents = [torrent("t1", name: "A")]
        vm.playbackHistory["t1#0"] = history(torrentID: "t1", resume: 100, lastPlayed: 1)

        XCTAssertEqual(vm.displayContinueWatching.count, 1,
                       "without a resolver, displayContinueWatching mirrors the synchronous projection")
        XCTAssertNil(vm.displayContinueWatching[0].media,
                     "no enrichment without a resolver — raw item only")
    }
}

// MARK: - StubProvider (duplicated locally to keep the file standalone)

private final class StubProvider: MetadataProvider, @unchecked Sendable {

    var searchHandler: ((String) throws -> [MediaItem])?

    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] { [] }
    func popular(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func topRated(media: TrendingMedia) async throws -> [MediaItem] { [] }

    func searchMulti(query: String) async throws -> [MediaItem] {
        if let handler = searchHandler {
            return try handler(query)
        }
        return []
    }

    func movieDetail(id: MediaID) async throws -> Movie {
        throw MetadataProviderError.notFound
    }
    func showDetail(id: MediaID) async throws -> Show {
        throw MetadataProviderError.notFound
    }
    func seasonDetail(showID: MediaID, season: Int) async throws -> Season {
        throw MetadataProviderError.notFound
    }
    func recommendations(for id: MediaID) async throws -> [MediaItem] { [] }

    func imageURL(path: String, size: TMDBImageSize) -> URL {
        URL(string: "https://example.com/img/\(size.rawValue)\(path)")!
    }
}
