import XCTest
import Combine
import EngineInterface
import MetadataDomain
@testable import ButterBar

// MARK: - NextEpisodeCoordinatorTests
//
// Tests the lookup + countdown logic of `NextEpisodeCoordinator` (#21):
//   - Same-season next-episode lookup
//   - Cross-season hand-off when the show schema carries the next season
//   - "No next episode" path when last in season AND no further season
//   - Metadata fetch failure path (no surface, no crash)
//   - Cancel path: surface dismisses, no `openStream` is fired
//   - Auto-play path: countdown completes, `openStream` is invoked once
//
// The coordinator subscribes to `EndOfEpisodeDetector.publisher`, so each
// test feeds the signal through that subject and awaits the published
// state via short polls. The clock is injected so countdown tests do not
// wait real wall time.

@MainActor
final class NextEpisodeCoordinatorTests: XCTestCase {

    // MARK: - Fixtures

    private let showID = MediaID(provider: .tmdb, id: 42)

    private func episode(season: Int, ep: Int, id: Int64 = 0) -> Episode {
        Episode(
            id: MediaID(provider: .tmdb, id: id == 0 ? Int64(season * 1000 + ep) : id),
            showID: showID,
            seasonNumber: season,
            episodeNumber: ep,
            name: "S\(season)E\(ep)",
            overview: "",
            stillPath: "/s\(season)e\(ep).jpg",
            runtimeMinutes: 45,
            airDate: nil
        )
    }

    private func season(_ n: Int, episodes: [Episode]) -> Season {
        Season(showID: showID,
               seasonNumber: n,
               name: "Season \(n)",
               overview: "",
               posterPath: nil,
               airDate: nil,
               episodes: episodes)
    }

    private func show(seasons: [Season]) -> Show {
        Show(id: showID,
             name: "Test Show",
             originalName: "Test Show",
             firstAirYear: 2020,
             lastAirYear: nil,
             status: .returning,
             overview: "",
             genres: [],
             posterPath: nil,
             backdropPath: nil,
             voteAverage: nil,
             popularity: nil,
             seasons: seasons)
    }

    // MARK: - Helpers

    /// Spin until `condition` returns true or `timeout` seconds elapse.
    /// Used because the coordinator does its lookup in a `Task` after the
    /// signal arrives.
    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 1.0,
                           _ condition: () -> Bool) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for: \(description)")
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000) // 5 ms
        }
    }

    // MARK: - Lookup: same-season next episode

    func testFindsNextEpisodeInSameSeason() async {
        let s1 = season(1, episodes: [episode(season: 1, ep: 1),
                                      episode(season: 1, ep: 2),
                                      episode(season: 1, ep: 3)])
        let provider = NextEpisodeFakeProvider()
        provider.seasonHandler = { [s1] _, n in
            XCTAssertEqual(n, 1)
            return s1
        }

        let coord = NextEpisodeCoordinator(
            metadata: provider,
            countdownSeconds: 0.05,
            clock: TestClock(),
            openStream: { _ in }
        )

        // Episode 2 just finished → expect Episode 3 to be offered.
        EndOfEpisodeDetector.publisher.send(EndOfEpisodeSignal(episode: episode(season: 1, ep: 2)))

        await waitUntil("offer surfaces") { coord.offer != nil }
        XCTAssertEqual(coord.offer?.next.episodeNumber, 3)
        XCTAssertEqual(coord.offer?.next.seasonNumber, 1)
    }

    // MARK: - Lookup: cross-season hand-off

    func testFindsFirstEpisodeOfNextSeasonWhenAtEndOfCurrent() async {
        let s1 = season(1, episodes: [episode(season: 1, ep: 1),
                                      episode(season: 1, ep: 2)])
        let s2First = episode(season: 2, ep: 1)
        let s2 = season(2, episodes: [s2First])
        let provider = NextEpisodeFakeProvider()
        provider.seasonHandler = { _, n in
            switch n {
            case 1: return s1
            case 2: return s2
            default: throw MetadataProviderError.notFound
            }
        }
        let showValue = show(seasons: [s1, s2])
        provider.showHandler = { _ in showValue }

        let coord = NextEpisodeCoordinator(
            metadata: provider,
            countdownSeconds: 0.05,
            clock: TestClock(),
            openStream: { _ in }
        )

        EndOfEpisodeDetector.publisher.send(EndOfEpisodeSignal(episode: episode(season: 1, ep: 2)))

        await waitUntil("cross-season offer surfaces") { coord.offer != nil }
        XCTAssertEqual(coord.offer?.next.seasonNumber, 2)
        XCTAssertEqual(coord.offer?.next.episodeNumber, 1)
    }

    // MARK: - Lookup: no next episode

    func testNoSurfaceWhenLastEpisodeAndNoFurtherSeason() async {
        let s1 = season(1, episodes: [episode(season: 1, ep: 1)])
        let provider = NextEpisodeFakeProvider()
        provider.seasonHandler = { _, _ in s1 }
        let showValue = show(seasons: [s1])
        provider.showHandler = { _ in showValue }

        var openCalls = 0
        let coord = NextEpisodeCoordinator(
            metadata: provider,
            countdownSeconds: 0.02,
            clock: TestClock(),
            openStream: { _ in openCalls += 1 }
        )

        EndOfEpisodeDetector.publisher.send(EndOfEpisodeSignal(episode: episode(season: 1, ep: 1)))

        // Give it a moment to attempt + abandon the lookup.
        try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
        XCTAssertNil(coord.offer)
        XCTAssertEqual(openCalls, 0)
    }

    // MARK: - Lookup: metadata error

    func testNoSurfaceWhenMetadataLookupFails() async {
        let provider = NextEpisodeFakeProvider()
        provider.seasonHandler = { _, _ in throw MetadataProviderError.transport }

        let coord = NextEpisodeCoordinator(
            metadata: provider,
            countdownSeconds: 0.02,
            clock: TestClock(),
            openStream: { _ in }
        )

        EndOfEpisodeDetector.publisher.send(EndOfEpisodeSignal(episode: episode(season: 1, ep: 1)))

        try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
        XCTAssertNil(coord.offer)
    }

    // MARK: - Cancel: dismiss before countdown completes

    func testCancelDismissesSurfaceWithoutOpeningStream() async {
        let s1 = season(1, episodes: [episode(season: 1, ep: 1),
                                      episode(season: 1, ep: 2)])
        let provider = NextEpisodeFakeProvider()
        provider.seasonHandler = { _, _ in s1 }

        var openCalls = 0
        let clock = TestClock()
        let coord = NextEpisodeCoordinator(
            metadata: provider,
            countdownSeconds: 10,
            clock: clock,
            openStream: { _ in openCalls += 1 }
        )

        EndOfEpisodeDetector.publisher.send(EndOfEpisodeSignal(episode: episode(season: 1, ep: 1)))
        await waitUntil("offer surfaces") { coord.offer != nil }

        coord.cancel()

        XCTAssertNil(coord.offer)
        // Even if we advance past the countdown, openStream must not fire.
        clock.advance(by: 60)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(openCalls, 0)
    }

    // MARK: - Auto-play: countdown completes

    func testCountdownCompletionFiresOpenStream() async {
        let s1 = season(1, episodes: [episode(season: 1, ep: 1),
                                      episode(season: 1, ep: 2)])
        let provider = NextEpisodeFakeProvider()
        provider.seasonHandler = { _, _ in s1 }

        var openedEpisodes: [Episode] = []
        let clock = TestClock()
        let coord = NextEpisodeCoordinator(
            metadata: provider,
            countdownSeconds: 10,
            clock: clock,
            openStream: { ep in openedEpisodes.append(ep) }
        )

        EndOfEpisodeDetector.publisher.send(EndOfEpisodeSignal(episode: episode(season: 1, ep: 1)))
        await waitUntil("offer surfaces") { coord.offer != nil }

        clock.advance(by: 10)
        await waitUntil("open fires") { openedEpisodes.count == 1 }
        XCTAssertEqual(openedEpisodes.first?.episodeNumber, 2)
        XCTAssertNil(coord.offer, "Surface dismisses after auto-play fires")
    }

    // MARK: - Play now: user accepts immediately

    func testPlayNowFiresOpenStreamImmediately() async {
        let s1 = season(1, episodes: [episode(season: 1, ep: 1),
                                      episode(season: 1, ep: 2)])
        let provider = NextEpisodeFakeProvider()
        provider.seasonHandler = { _, _ in s1 }

        var openedEpisodes: [Episode] = []
        let coord = NextEpisodeCoordinator(
            metadata: provider,
            countdownSeconds: 10,
            clock: TestClock(),
            openStream: { ep in openedEpisodes.append(ep) }
        )

        EndOfEpisodeDetector.publisher.send(EndOfEpisodeSignal(episode: episode(season: 1, ep: 1)))
        await waitUntil("offer surfaces") { coord.offer != nil }

        coord.playNow()
        await waitUntil("open fires") { openedEpisodes.count == 1 }
        XCTAssertEqual(openedEpisodes.first?.episodeNumber, 2)
    }

    // MARK: - Host wiring: PlayerViewModel resolver handoff

    func testPlayerViewModelOpenNextUsesResolverAndStreamOpener() async {
        let next = episode(season: 1, ep: 2)
        var opened: [(String, Int32)] = []
        let vm = PlayerViewModel(
            streamDescriptor: descriptor(id: "one"),
            engineClient: EngineClient(),
            currentEpisode: episode(season: 1, ep: 1),
            currentShow: show(seasons: [season(1, episodes: [next])]),
            resolveNextEpisode: { episode in
                XCTAssertEqual(episode, next)
                return (torrentID: "torrent-next", fileIndex: 4)
            },
            historyProvider: { [] },
            streamOpener: { torrentID, fileIndex in
                opened.append((torrentID, fileIndex))
                return self.descriptor(id: "two")
            }
        )

        vm.openNextEpisode(next)

        await waitUntil("next episode opened") { opened.count == 1 }
        XCTAssertEqual(opened.first?.0, "torrent-next")
        XCTAssertEqual(opened.first?.1, 4)
        XCTAssertNil(vm.transientMessage)
    }

    func testPlayerViewModelOpenNextShowsCalmMessageWhenMissing() async {
        let next = episode(season: 1, ep: 2)
        let vm = PlayerViewModel(
            streamDescriptor: descriptor(id: "one"),
            engineClient: EngineClient(),
            resolveNextEpisode: { _ in nil },
            historyProvider: { [] },
            streamOpener: { _, _ in XCTFail("openStream should not run"); return self.descriptor(id: "unused") }
        )

        vm.openNextEpisode(next)

        await waitUntil("missing message surfaces") { vm.transientMessage == "Next episode not in library" }
    }

    private func descriptor(id: String) -> StreamDescriptorDTO {
        StreamDescriptorDTO(
            streamID: id as NSString,
            loopbackURL: "http://127.0.0.1:9999/\(id)" as NSString,
            contentType: "video/mp4" as NSString,
            contentLength: 1000,
            resumeByteOffset: 0
        )
    }
}

// MARK: - Test doubles

/// Local fake `MetadataProvider` for the coordinator tests. Mirrors the
/// shape of `MetadataDomain`'s `FakeMetadataProvider` but lives inside the
/// app test target so we don't need to expose the package-test fake.
final class NextEpisodeFakeProvider: MetadataProvider, @unchecked Sendable {
    var seasonHandler: (@Sendable (MediaID, Int) async throws -> Season)?
    var showHandler: (@Sendable (MediaID) async throws -> Show)?

    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] { [] }
    func popular(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func topRated(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func searchMulti(query: String) async throws -> [MediaItem] { [] }
    func movieDetail(id: MediaID) async throws -> Movie {
        throw MetadataProviderError.notFound
    }
    func showDetail(id: MediaID) async throws -> Show {
        if let h = showHandler { return try await h(id) }
        throw MetadataProviderError.notFound
    }
    func seasonDetail(showID: MediaID, season: Int) async throws -> Season {
        if let h = seasonHandler { return try await h(showID, season) }
        throw MetadataProviderError.notFound
    }
    func recommendations(for id: MediaID) async throws -> [MediaItem] { [] }
    func imageURL(path: String, size: TMDBImageSize) -> URL {
        URL(string: "https://example.invalid/\(size.rawValue)\(path)")!
    }
}
