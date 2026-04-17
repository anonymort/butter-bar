import XCTest
import EngineInterface
import MetadataDomain
@testable import ButterBar

@MainActor
final class LibraryMetadataResolverTests: XCTestCase {

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

    private func history(torrentID: String, fileIndex: Int = 0,
                         resume: Int64, lastPlayed: Int64,
                         completed: Bool = false,
                         completedAt: Int64? = nil) -> PlaybackHistoryDTO {
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

    private func movie(_ title: String, year: Int = 2010, posterPath: String = "/movie.jpg") -> MediaItem {
        .movie(Movie(
            id: MediaID(provider: .tmdb, id: 1),
            title: title,
            originalTitle: title,
            releaseYear: year,
            runtimeMinutes: 100,
            overview: "",
            genres: [],
            posterPath: posterPath,
            backdropPath: nil,
            voteAverage: nil,
            popularity: nil
        ))
    }

    private func show(_ name: String, firstYear: Int = 2010, posterPath: String = "/show.jpg") -> MediaItem {
        .show(Show(
            id: MediaID(provider: .tmdb, id: 2),
            name: name,
            originalName: name,
            firstAirYear: firstYear,
            lastAirYear: nil,
            status: .returning,
            overview: "",
            genres: [],
            posterPath: posterPath,
            backdropPath: nil,
            voteAverage: nil,
            popularity: nil,
            seasons: []
        ))
    }

    private func makeResolver(
        provider: StubProvider,
        clock: @escaping () -> Date = { Date(timeIntervalSince1970: 1_000_000) },
        threshold: Double = LibraryMetadataResolver.defaultThreshold,
        maxItems: Int = LibraryMetadataResolver.defaultMaxItems,
        ttl: TimeInterval = MetadataCacheTTL.matchResult
    ) -> LibraryMetadataResolver {
        LibraryMetadataResolver(
            provider: provider,
            clock: clock,
            threshold: threshold,
            maxItems: maxItems,
            ttl: ttl
        )
    }

    // MARK: - Filter behaviour

    func testWatchedAndUnwatchedExcluded() async {
        let provider = StubProvider()
        let resolver = makeResolver(provider: provider)

        let torrents = [
            torrent("watched", name: "watched.mkv", total: 1_000),
            torrent("unwatched", name: "unwatched.mkv", total: 1_000),
        ]
        let history = [
            history(torrentID: "watched", resume: 0, lastPlayed: 1, completed: true, completedAt: 1),
            history(torrentID: "unwatched", resume: 0, lastPlayed: 2),
        ]
        let items = await resolver.resolve(
            history: history,
            torrents: torrents,
            fileNameLookup: { _, _ in nil }
        )

        XCTAssertTrue(items.isEmpty,
                      "watched + unwatched rows must not appear in continue-watching")
        XCTAssertEqual(provider.searchCalls.count, 0,
                       "no metadata search should fire when nothing passes the filter")
    }

    func testInProgressAndReWatchingIncluded() async {
        let provider = StubProvider()
        let resolver = makeResolver(provider: provider)

        let torrents = [
            torrent("ip", name: "Inception (2010).mkv", total: 1_000),
            torrent("rw", name: "Inception (2010).mkv", total: 1_000),
        ]
        let history = [
            history(torrentID: "ip", resume: 200, lastPlayed: 1),
            history(torrentID: "rw", resume: 300, lastPlayed: 2,
                    completed: true, completedAt: 1),
        ]
        let items = await resolver.resolve(
            history: history,
            torrents: torrents,
            fileNameLookup: { _, _ in nil }
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.id).sorted(), ["ip#0", "rw#0"])
    }

    // MARK: - Parser / ranker integration

    func testTopMatchAttachedWhenConfidenceAboveThreshold() async {
        let provider = StubProvider()
        provider.searchHandler = { _ in [self.movie("Inception", year: 2010)] }
        let resolver = makeResolver(provider: provider)

        let t = torrent("t1", name: "fallback name", total: 1_000)
        let history = [history(torrentID: "t1", resume: 100, lastPlayed: 1)]
        let items = await resolver.resolve(
            history: history,
            torrents: [t],
            fileNameLookup: { _, _ in "Inception.2010.1080p.BluRay.x264-FOO.mkv" }
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertNotNil(items[0].media, "matched item must carry the MediaItem")
        XCTAssertEqual(items[0].displayTitle, "Inception")
        XCTAssertEqual(items[0].posterPath, "/movie.jpg")
    }

    func testThresholdGatingDropsLowConfidenceMatch() async {
        let provider = StubProvider()
        // Match candidate is wildly different from the parsed title; ranker
        // should score below 0.6.
        provider.searchHandler = { _ in [self.movie("Casablanca", year: 1942)] }
        let resolver = makeResolver(provider: provider, threshold: 0.6)

        let t = torrent("t1", name: "Inception (2010).mkv", total: 1_000)
        let history = [history(torrentID: "t1", resume: 100, lastPlayed: 1)]
        let items = await resolver.resolve(
            history: history,
            torrents: [t],
            fileNameLookup: { _, _ in "Inception.2010.mkv" }
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].media,
                     "candidate below threshold must NOT attach to the item")
        XCTAssertEqual(items[0].displayTitle, "Inception (2010).mkv",
                       "fallback to the raw torrent name (per AC: 'Untitled torrent file' policy — render, do not drop)")
    }

    // MARK: - Unmatched fallback (don't drop the row)

    func testUnmatchedRowStillAppears() async {
        let provider = StubProvider()
        // Provider returns no candidates at all.
        provider.searchHandler = { _ in [] }
        let resolver = makeResolver(provider: provider)

        let t = torrent("t1", name: "weird-release.mkv", total: 1_000)
        let history = [history(torrentID: "t1", resume: 100, lastPlayed: 1)]
        let items = await resolver.resolve(
            history: history,
            torrents: [t],
            fileNameLookup: { _, _ in "weird-release.mkv" }
        )

        XCTAssertEqual(items.count, 1, "unmatched row MUST still render (per AC)")
        XCTAssertNil(items[0].media)
        XCTAssertEqual(items[0].displayTitle, "weird-release.mkv")
    }

    func testProviderErrorRendersUnmatchedRow() async {
        let provider = StubProvider()
        provider.searchHandler = { _ in throw MetadataProviderError.transport }
        let resolver = makeResolver(provider: provider)

        let t = torrent("t1", name: "Inception (2010).mkv", total: 1_000)
        let history = [history(torrentID: "t1", resume: 100, lastPlayed: 1)]
        let items = await resolver.resolve(
            history: history,
            torrents: [t],
            fileNameLookup: { _, _ in "Inception.2010.mkv" }
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].media,
                     "transport failure must degrade to unmatched, not crash")
    }

    // MARK: - Sort + cap

    func testSortByLastPlayedDescending() async {
        let provider = StubProvider()
        let resolver = makeResolver(provider: provider)

        let torrents = [
            torrent("a", name: "a", total: 1_000),
            torrent("b", name: "b", total: 1_000),
            torrent("c", name: "c", total: 1_000),
        ]
        let history = [
            history(torrentID: "a", resume: 1, lastPlayed: 1_000),
            history(torrentID: "b", resume: 1, lastPlayed: 9_000),
            history(torrentID: "c", resume: 1, lastPlayed: 5_000),
        ]
        let items = await resolver.resolve(
            history: history,
            torrents: torrents,
            fileNameLookup: { _, _ in nil }
        )

        XCTAssertEqual(items.map(\.id), ["b#0", "c#0", "a#0"])
    }

    func testCapAtMaxItems() async {
        let provider = StubProvider()
        let resolver = makeResolver(provider: provider, maxItems: 10)

        let torrents = (0..<15).map { torrent("t\($0)", name: "name\($0)", total: 1_000) }
        let historyRows = (0..<15).map { history(torrentID: "t\($0)", resume: 1, lastPlayed: Int64($0)) }
        let items = await resolver.resolve(
            history: historyRows,
            torrents: torrents,
            fileNameLookup: { _, _ in nil }
        )

        XCTAssertEqual(items.count, 10, "cap at 10 (per AC)")
        // Sorted desc by lastPlayed: highest 10 are t14..t5.
        XCTAssertEqual(items.first?.id, "t14#0")
        XCTAssertEqual(items.last?.id, "t5#0")
    }

    func testCapAppliedBeforeMetadataLookup() async {
        // Ensures sort+cap happens before the search loop — the resolver
        // must not search 100 candidates and then truncate.
        let provider = StubProvider()
        let resolver = makeResolver(provider: provider, maxItems: 3)

        let torrents = (0..<20).map { torrent("t\($0)", name: "name\($0)", total: 1_000) }
        let historyRows = (0..<20).map { history(torrentID: "t\($0)", resume: 1, lastPlayed: Int64($0)) }
        _ = await resolver.resolve(
            history: historyRows,
            torrents: torrents,
            fileNameLookup: { tid, _ in "lookup-\(tid)" }
        )

        XCTAssertEqual(provider.searchCalls.count, 3,
                       "metadata lookups must be bounded by the cap, not the input size")
    }

    // MARK: - Cache (30-day TTL)

    func testMatchResultCachedWithinTTL() async {
        let provider = StubProvider()
        provider.searchHandler = { _ in [self.movie("Inception", year: 2010)] }

        var now = Date(timeIntervalSince1970: 1_000_000)
        let resolver = makeResolver(provider: provider, clock: { now })

        let t = torrent("t1", name: "fallback", total: 1_000)
        let h = [history(torrentID: "t1", resume: 100, lastPlayed: 1)]

        _ = await resolver.resolve(history: h, torrents: [t],
                                   fileNameLookup: { _, _ in "Inception.2010.mkv" })
        _ = await resolver.resolve(history: h, torrents: [t],
                                   fileNameLookup: { _, _ in "Inception.2010.mkv" })
        XCTAssertEqual(provider.searchCalls.count, 1,
                       "second resolve within TTL must hit the cache, not re-search")

        // Advance past the 30-day TTL.
        now = Date(timeIntervalSince1970: 1_000_000 + 31 * 24 * 60 * 60)
        _ = await resolver.resolve(history: h, torrents: [t],
                                   fileNameLookup: { _, _ in "Inception.2010.mkv" })
        XCTAssertEqual(provider.searchCalls.count, 2,
                       "after TTL expiry, the resolver must re-search")
    }

    func testNegativeMatchAlsoCached() async {
        // No candidates → unmatched. The next resolve should still hit the
        // cache so we don't burn a network call per render.
        let provider = StubProvider()
        provider.searchHandler = { _ in [] }
        let resolver = makeResolver(provider: provider)

        let t = torrent("t1", name: "weird.mkv", total: 1_000)
        let h = [history(torrentID: "t1", resume: 100, lastPlayed: 1)]

        _ = await resolver.resolve(history: h, torrents: [t],
                                   fileNameLookup: { _, _ in "weird.mkv" })
        _ = await resolver.resolve(history: h, torrents: [t],
                                   fileNameLookup: { _, _ in "weird.mkv" })
        XCTAssertEqual(provider.searchCalls.count, 1,
                       "negative matches must be cached too")
    }

    func testInvalidateDropsCacheEntry() async {
        let provider = StubProvider()
        provider.searchHandler = { _ in [self.movie("Inception", year: 2010)] }
        let resolver = makeResolver(provider: provider)

        let t = torrent("t1", name: "fallback", total: 1_000)
        let h = [history(torrentID: "t1", resume: 100, lastPlayed: 1)]

        _ = await resolver.resolve(history: h, torrents: [t],
                                   fileNameLookup: { _, _ in "Inception.2010.mkv" })
        resolver.invalidate(fileName: "Inception.2010.mkv")
        _ = await resolver.resolve(history: h, torrents: [t],
                                   fileNameLookup: { _, _ in "Inception.2010.mkv" })

        XCTAssertEqual(provider.searchCalls.count, 2,
                       "invalidate must force a re-search on next resolve")
    }

    // MARK: - Episode designator

    func testShowMatchProducesEpisodeDesignator() async {
        let provider = StubProvider()
        provider.searchHandler = { _ in [self.show("Game of Thrones", firstYear: 2011)] }
        let resolver = makeResolver(provider: provider)

        let t = torrent("t1", name: "fallback", total: 1_000)
        let h = [history(torrentID: "t1", resume: 100, lastPlayed: 1)]
        let items = await resolver.resolve(
            history: h, torrents: [t],
            fileNameLookup: { _, _ in "Game.of.Thrones.S01E04.1080p.BluRay.x264.mkv" }
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].episodeDesignator, "S01E04")
    }

    func testMovieMatchHasNoEpisodeDesignator() async {
        let provider = StubProvider()
        provider.searchHandler = { _ in [self.movie("Inception", year: 2010)] }
        let resolver = makeResolver(provider: provider)

        let t = torrent("t1", name: "fallback", total: 1_000)
        let h = [history(torrentID: "t1", resume: 100, lastPlayed: 1)]
        let items = await resolver.resolve(
            history: h, torrents: [t],
            fileNameLookup: { _, _ in "Inception.2010.mkv" }
        )

        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].episodeDesignator,
                     "movies do not get an episode designator")
    }
}

// MARK: - StubProvider
//
// Minimal MetadataProvider for app-side tests. Mirrors the in-package
// FakeMetadataProvider but is defined here because the test target lives
// in a different test bundle and the package-test fake isn't visible.

private final class StubProvider: MetadataProvider, @unchecked Sendable {

    var searchCalls: [String] = []

    var searchHandler: ((String) throws -> [MediaItem])?

    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] { [] }
    func popular(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func topRated(media: TrendingMedia) async throws -> [MediaItem] { [] }

    func searchMulti(query: String) async throws -> [MediaItem] {
        searchCalls.append(query)
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
