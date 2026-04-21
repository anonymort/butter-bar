import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
import MetadataDomain
import EngineInterface
@testable import ButterBar

@MainActor
private func hosted<V: View>(_ view: V, size: CGSize) -> NSHostingView<V> {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    return host
}

// MARK: - SeasonEpisodeSelectorSnapshotTests
//
// Light + dark snapshots cover: loading, loaded (mixed badges), specials season,
// empty episode list, and error states. States are seeded via fake providers and
// _setWatchStateForTesting. Baselines live in `__Snapshots__/SeasonEpisodeSelectorSnapshotTests/`.

@MainActor
final class SeasonEpisodeSelectorSnapshotTests: XCTestCase {

    private let snapshotSize = CGSize(width: 480, height: 640)
    private let showID = MediaID(provider: .tmdb, id: 99)

    private func makeView(
        _ vm: SeasonEpisodeSelectorViewModel
    ) -> some View {
        SeasonEpisodeSelectorView(viewModel: vm)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
    }

    // MARK: - Loading state
    //
    // VM is created but load() is never called, so state stays .loading.

    func testLoadingLight() {
        let show = makeShow(seasons: [season(1, episodes: [episode(1, 1)])])
        let vm = SeasonEpisodeSelectorViewModel(show: show, provider: SelectorFakeProvider())
        let view = makeView(vm).environment(\.colorScheme, .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loading-light")
    }

    func testLoadingDark() {
        let show = makeShow(seasons: [season(1, episodes: [episode(1, 1)])])
        let vm = SeasonEpisodeSelectorViewModel(show: show, provider: SelectorFakeProvider())
        let view = makeView(vm).environment(\.colorScheme, .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loading-dark")
    }

    // MARK: - Loaded — mixed watch badges
    //
    // Three episodes: one .watched, one .inProgress, one .unwatched.
    // Watch state is injected via _setWatchStateForTesting after load().

    func testLoadedMixedBadgesLight() async {
        let vm = try! await makeLoadedVMWithMixedBadges()
        let view = makeView(vm).environment(\.colorScheme, .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loaded-mixed-badges-light")
    }

    func testLoadedMixedBadgesDark() async {
        let vm = try! await makeLoadedVMWithMixedBadges()
        let view = makeView(vm).environment(\.colorScheme, .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loaded-mixed-badges-dark")
    }

    // MARK: - Loaded — specials season
    //
    // Show has season 0 labelled "Specials" and season 1. Specials is selected.

    func testLoadedSpecialsLight() async {
        let vm = await makeLoadedVMWithSpecials()
        let view = makeView(vm).environment(\.colorScheme, .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loaded-specials-light")
    }

    func testLoadedSpecialsDark() async {
        let vm = await makeLoadedVMWithSpecials()
        let view = makeView(vm).environment(\.colorScheme, .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loaded-specials-dark")
    }

    // MARK: - Loaded — empty episode list

    func testLoadedEmptyLight() async {
        let vm = await makeLoadedVMWithEmptySeason()
        let view = makeView(vm).environment(\.colorScheme, .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loaded-empty-light")
    }

    func testLoadedEmptyDark() async {
        let vm = await makeLoadedVMWithEmptySeason()
        let view = makeView(vm).environment(\.colorScheme, .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loaded-empty-dark")
    }

    // MARK: - Error state

    func testErrorLight() async {
        let vm = await makeErrorVM()
        let view = makeView(vm).environment(\.colorScheme, .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "error-light")
    }

    func testErrorDark() async {
        let vm = await makeErrorVM()
        let view = makeView(vm).environment(\.colorScheme, .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "error-dark")
    }

    // MARK: - VM factories

    private func makeLoadedVMWithMixedBadges() async throws -> SeasonEpisodeSelectorViewModel {
        let eps = [episode(1, 1), episode(1, 2), episode(1, 3)]
        let show = makeShow(seasons: [season(1, episodes: eps)])
        let provider = SelectorFakeProvider()
        provider.seasons[1] = season(1, episodes: eps)
        let vm = SeasonEpisodeSelectorViewModel(show: show, provider: provider)
        await vm.load()

        // Episode 1 → watched, episode 2 → in-progress, episode 3 → unwatched
        let files: [LibraryFile] = [
            LibraryFile(torrentID: "t1", fileIndex: 0, displayName: "Test.Show.S01E01.mkv"),
            LibraryFile(torrentID: "t1", fileIndex: 1, displayName: "Test.Show.S01E02.mkv"),
        ]
        let historyEntries: [PlaybackHistoryDTO] = [
            historyEntry(torrentID: "t1", fileIndex: 0, resume: 0, completed: true),
            historyEntry(torrentID: "t1", fileIndex: 1, resume: 500, completed: false),
        ]
        vm._setWatchStateForTesting(history: historyEntries, files: files)
        return vm
    }

    private func makeLoadedVMWithSpecials() async -> SeasonEpisodeSelectorViewModel {
        let specials = [episode(0, 1), episode(0, 2)]
        let regular = [episode(1, 1)]
        let show = makeShow(seasons: [season(0, episodes: specials), season(1, episodes: regular)])
        let provider = SelectorFakeProvider()
        provider.seasons[0] = season(0, episodes: specials)
        provider.seasons[1] = season(1, episodes: regular)
        let vm = SeasonEpisodeSelectorViewModel(show: show, provider: provider)
        await vm.load()
        await vm.selectSeason(0)
        return vm
    }

    private func makeLoadedVMWithEmptySeason() async -> SeasonEpisodeSelectorViewModel {
        let show = makeShow(seasons: [season(1, episodes: [])])
        let provider = SelectorFakeProvider()
        provider.seasons[1] = season(1, episodes: [])
        let vm = SeasonEpisodeSelectorViewModel(show: show, provider: provider)
        await vm.load()
        return vm
    }

    private func makeErrorVM() async -> SeasonEpisodeSelectorViewModel {
        let show = makeShow(seasons: [season(1, episodes: [episode(1, 1)])])
        let provider = SelectorThrowingProvider()
        let vm = SeasonEpisodeSelectorViewModel(show: show, provider: provider)
        await vm.load()
        return vm
    }

    // MARK: - Data factories

    private func makeShow(seasons: [Season]) -> Show {
        Show(id: showID, name: "Test Show", originalName: "Test Show",
             firstAirYear: 2020, lastAirYear: nil, status: .returning,
             overview: "A test show.", genres: [], posterPath: nil,
             backdropPath: nil, voteAverage: nil, popularity: nil,
             seasons: seasons)
    }

    private func season(_ number: Int, episodes: [Episode]) -> Season {
        Season(showID: showID, seasonNumber: number,
               name: number == 0 ? "Specials" : "Season \(number)",
               overview: "", posterPath: nil, airDate: nil, episodes: episodes)
    }

    private func episode(_ seasonNum: Int, _ number: Int) -> Episode {
        Episode(id: MediaID(provider: .tmdb, id: Int64(seasonNum * 100 + number)),
                showID: showID, seasonNumber: seasonNum, episodeNumber: number,
                name: "Episode \(number)", overview: "Overview for episode \(number).",
                stillPath: nil, runtimeMinutes: 45, airDate: nil)
    }

    private func historyEntry(torrentID: String, fileIndex: Int32,
                               resume: Int64, completed: Bool) -> PlaybackHistoryDTO {
        PlaybackHistoryDTO(torrentID: torrentID as NSString, fileIndex: fileIndex,
                           resumeByteOffset: resume, lastPlayedAt: 1,
                           totalWatchedSeconds: 0, completed: completed,
                           completedAt: completed ? NSNumber(value: 1) : nil)
    }
}

// MARK: - Fake providers

private final class SelectorFakeProvider: MetadataProvider, @unchecked Sendable {
    var seasons: [Int: Season] = [:]

    func seasonDetail(showID: MediaID, season: Int) async throws -> Season {
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

private final class SelectorThrowingProvider: MetadataProvider, @unchecked Sendable {
    func seasonDetail(showID: MediaID, season: Int) async throws -> Season {
        throw MetadataProviderError.transport
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
