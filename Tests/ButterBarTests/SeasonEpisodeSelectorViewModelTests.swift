import XCTest
import EngineInterface
import MetadataDomain
@testable import ButterBar

@MainActor
final class SeasonEpisodeSelectorViewModelTests: XCTestCase {
    private let showID = MediaID(provider: .tmdb, id: 42)

    func testDefaultsToMostRecentSeasonWithEpisodes() async {
        let show = makeShow(seasons: [season(1, episodes: [episode(1, 1)]), season(2, episodes: [episode(2, 1)])])
        let provider = SeasonFakeProvider()
        provider.seasons[2] = season(2, episodes: [episode(2, 1)])
        let vm = SeasonEpisodeSelectorViewModel(show: show, provider: provider)

        await vm.load()

        XCTAssertEqual(vm.selectedSeasonNumber, 2)
        XCTAssertEqual(vm.episodeRows.map { $0.episode.episodeNumber }, [1])
    }

    func testLazyFetchesSeasonOncePerSelection() async {
        let show = makeShow(seasons: [season(1, episodes: [])])
        let provider = SeasonFakeProvider()
        provider.seasons[1] = season(1, episodes: [episode(1, 1), episode(1, 2)])
        let vm = SeasonEpisodeSelectorViewModel(show: show, provider: provider)

        await vm.load()
        await vm.selectSeason(1)

        XCTAssertEqual(provider.seasonCalls, [1])
        XCTAssertEqual(vm.episodeRows.count, 2)
    }

    func testWatchBadgeDerivedFromHistoryAndParsedLibraryFile() async {
        let show = makeShow(seasons: [season(2, episodes: [episode(2, 1)])])
        let provider = SeasonFakeProvider()
        provider.seasons[2] = season(2, episodes: [episode(2, 1)])
        let history = [history(torrentID: "t1", fileIndex: 3, resume: 0, completed: true)]
        let files = [file(index: 3, path: "Test.Show.S02E01.1080p.mkv")]
        let vm = SeasonEpisodeSelectorViewModel(
            show: show,
            provider: provider,
            historyProvider: { history },
            torrentProvider: { [self.torrent("t1")] },
            fileProvider: { _ in files }
        )

        await vm.load()

        XCTAssertEqual(vm.episodeRows.first?.badge, .watched)
        XCTAssertEqual(vm.episodeRows.first?.match?.torrentID, "t1")
    }

    func testPlaybackHistorySubscriptionUpdatesBadge() async {
        let events = EngineEventHandler()
        let show = makeShow(seasons: [season(1, episodes: [episode(1, 1)])])
        let provider = SeasonFakeProvider()
        provider.seasons[1] = season(1, episodes: [episode(1, 1)])
        let files = [file(index: 0, path: "Test.Show.S01E01.mkv")]
        let vm = SeasonEpisodeSelectorViewModel(
            show: show,
            provider: provider,
            historyProvider: { [] },
            torrentProvider: { [self.torrent("t1")] },
            fileProvider: { _ in files },
            eventsProvider: { events }
        )

        await vm.load()
        XCTAssertEqual(vm.episodeRows.first?.badge, .unwatched)

        events.playbackHistoryChangedSubject.send(history(torrentID: "t1", fileIndex: 0, resume: 100, completed: false))
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(vm.episodeRows.first?.badge, .inProgress)
    }

    private func makeShow(seasons: [Season]) -> Show {
        Show(id: showID, name: "Test Show", originalName: "Test Show", firstAirYear: 2020,
             lastAirYear: nil, status: .returning, overview: "", genres: [],
             posterPath: nil, backdropPath: nil, voteAverage: nil, popularity: nil,
             seasons: seasons)
    }

    private func season(_ number: Int, episodes: [Episode]) -> Season {
        Season(showID: showID, seasonNumber: number, name: number == 0 ? "Specials" : "Season \(number)",
               overview: "", posterPath: nil, airDate: nil, episodes: episodes)
    }

    private func episode(_ season: Int, _ number: Int) -> Episode {
        Episode(id: MediaID(provider: .tmdb, id: Int64(season * 100 + number)), showID: showID,
                seasonNumber: season, episodeNumber: number, name: "Episode \(number)",
                overview: "", stillPath: nil, runtimeMinutes: 45, airDate: nil)
    }

    private func torrent(_ id: String) -> TorrentSummaryDTO {
        TorrentSummaryDTO(torrentID: id as NSString, name: "Test Show" as NSString,
                          totalBytes: 1_000, progressQ16: 0, state: "seeding",
                          peerCount: 0, downRateBytesPerSec: 0,
                          upRateBytesPerSec: 0, errorMessage: nil)
    }

    private func file(index: Int32, path: String) -> TorrentFileDTO {
        TorrentFileDTO(fileIndex: index, path: path as NSString, sizeBytes: 100,
                       mimeTypeHint: "video/mp4" as NSString, isPlayableByAVFoundation: true)
    }

    private func history(torrentID: String, fileIndex: Int32, resume: Int64, completed: Bool) -> PlaybackHistoryDTO {
        PlaybackHistoryDTO(torrentID: torrentID as NSString, fileIndex: fileIndex,
                           resumeByteOffset: resume, lastPlayedAt: 1,
                           totalWatchedSeconds: 0, completed: completed,
                           completedAt: completed ? NSNumber(value: 1) : nil)
    }
}

private final class SeasonFakeProvider: MetadataProvider, @unchecked Sendable {
    var seasons: [Int: Season] = [:]
    var seasonCalls: [Int] = []

    func seasonDetail(showID: MediaID, season: Int) async throws -> Season {
        seasonCalls.append(season)
        if let value = seasons[season] { return value }
        throw MetadataProviderError.notFound
    }

    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] { [] }
    func popular(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func topRated(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func searchMulti(query: String) async throws -> [MediaItem] { [] }
    func movieDetail(id: MediaID) async throws -> Movie { throw MetadataProviderError.notFound }
    func showDetail(id: MediaID) async throws -> Show { throw MetadataProviderError.notFound }
    func recommendations(for id: MediaID) async throws -> [MediaItem] { [] }
    func imageURL(path: String, size: TMDBImageSize) -> URL { URL(string: "https://example.invalid")! }
}
