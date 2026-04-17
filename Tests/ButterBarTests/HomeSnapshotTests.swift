import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
import MetadataDomain
@testable import ButterBar

@MainActor
private func hosted<V: View>(_ view: V, size: CGSize) -> NSHostingView<V> {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    return host
}

/// Snapshot baselines live alongside this file in
/// `__Snapshots__/HomeSnapshotTests/`.
///
/// First run: set the `record:` parameter to `.all` to write baselines.
/// Subsequent runs diff against committed PNGs.
///
/// These cases mirror the AC: full home (all rows populated), partial (one
/// empty row), error (one failed row), cold cache (loading shimmer).
@MainActor
final class HomeSnapshotTests: XCTestCase {

    private let snapshotSize = CGSize(width: 900, height: 700)

    // MARK: - Helpers

    private func provider() -> MetadataProvider { SnapshotFakeProvider() }

    private func fullyLoadedVM() -> HomeViewModel {
        let vm = HomeViewModel(provider: provider())
        for kind in HomeRowKind.allCases where kind != .continueWatching {
            vm._setRowState(kind, .loaded(SampleData.items(for: kind)))
        }
        return vm
    }

    private func partialVM() -> HomeViewModel {
        let vm = fullyLoadedVM()
        vm._setRowState(.popularShows, .empty)
        return vm
    }

    private func errorVM() -> HomeViewModel {
        let vm = fullyLoadedVM()
        vm._setRowState(.trendingShows, .failed)
        return vm
    }

    private func loadingVM() -> HomeViewModel {
        // Default initial state: every data row is .loading.
        HomeViewModel(provider: provider())
    }

    private func makeView(_ vm: HomeViewModel, colorScheme: ColorScheme) -> some View {
        let dummy = Binding<MediaItem?>(get: { nil }, set: { _ in })
        return HomeView(viewModel: vm, provider: provider(), selectedItem: dummy)
            .environment(\.colorScheme, colorScheme)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
    }

    // MARK: - Full

    func testHomeLightFull() {
        let view = makeView(fullyLoadedVM(), colorScheme: .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image, named: "light-full")
    }

    func testHomeDarkFull() {
        let view = makeView(fullyLoadedVM(), colorScheme: .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image, named: "dark-full")
    }

    // MARK: - Partial (one row empty)

    func testHomeLightPartial() {
        let view = makeView(partialVM(), colorScheme: .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image, named: "light-partial")
    }

    func testHomeDarkPartial() {
        let view = makeView(partialVM(), colorScheme: .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image, named: "dark-partial")
    }

    // MARK: - Error (one failed row)

    func testHomeLightError() {
        let view = makeView(errorVM(), colorScheme: .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image, named: "light-error")
    }

    func testHomeDarkError() {
        let view = makeView(errorVM(), colorScheme: .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image, named: "dark-error")
    }

    // MARK: - Loading (cold cache shimmer)

    func testHomeLightLoading() {
        let view = makeView(loadingVM(), colorScheme: .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image, named: "light-loading")
    }

    func testHomeDarkLoading() {
        let view = makeView(loadingVM(), colorScheme: .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image, named: "dark-loading")
    }
}

// MARK: - Sample data

private enum SampleData {
    static func items(for kind: HomeRowKind) -> [MediaItem] {
        switch kind {
        case .trendingMovies, .popularMovies, .topRatedMovies:
            return [
                .movie(movie(id: 1, title: "Cosmos", year: 1980)),
                .movie(movie(id: 2, title: "Night of the Living Dead", year: 1968)),
                .movie(movie(id: 3, title: "The General", year: 1926)),
                .movie(movie(id: 4, title: "Metropolis", year: 1927)),
            ]
        case .trendingShows, .popularShows, .topRatedShows:
            return [
                .show(show(id: 11, name: "Planet Earth", year: 2006)),
                .show(show(id: 12, name: "The Wire", year: 2002)),
                .show(show(id: 13, name: "Twin Peaks", year: 1990)),
            ]
        case .continueWatching:
            return []
        }
    }

    private static func movie(id: Int64, title: String, year: Int) -> Movie {
        Movie(id: MediaID(provider: .tmdb, id: id),
              title: title,
              originalTitle: title,
              releaseYear: year,
              runtimeMinutes: 120,
              overview: "",
              genres: [],
              posterPath: nil,        // forces brand placeholder rendering — no live image fetch
              backdropPath: nil,
              voteAverage: nil,
              popularity: nil)
    }

    private static func show(id: Int64, name: String, year: Int) -> Show {
        Show(id: MediaID(provider: .tmdb, id: id),
             name: name,
             originalName: name,
             firstAirYear: year,
             lastAirYear: nil,
             status: .ended,
             overview: "",
             genres: [],
             posterPath: nil,         // ditto
             backdropPath: nil,
             voteAverage: nil,
             popularity: nil,
             seasons: [])
    }
}

// MARK: - Snapshot-only fake provider

private final class SnapshotFakeProvider: MetadataProvider, @unchecked Sendable {
    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] { [] }
    func popular(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func topRated(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func searchMulti(query: String) async throws -> [MediaItem] { [] }
    func movieDetail(id: MediaID) async throws -> Movie {
        Movie(id: id, title: "", originalTitle: "", releaseYear: nil, runtimeMinutes: nil,
              overview: "", genres: [], posterPath: nil, backdropPath: nil,
              voteAverage: nil, popularity: nil)
    }
    func showDetail(id: MediaID) async throws -> Show {
        Show(id: id, name: "", originalName: "", firstAirYear: nil, lastAirYear: nil,
             status: .ended, overview: "", genres: [], posterPath: nil, backdropPath: nil,
             voteAverage: nil, popularity: nil, seasons: [])
    }
    func seasonDetail(showID: MediaID, season: Int) async throws -> Season {
        Season(showID: showID, seasonNumber: season, name: "", overview: "",
               posterPath: nil, airDate: nil, episodes: [])
    }
    func recommendations(for id: MediaID) async throws -> [MediaItem] { [] }
    func imageURL(path: String, size: TMDBImageSize) -> URL {
        URL(string: "https://example.invalid/\(size.rawValue)\(path)")!
    }
}
