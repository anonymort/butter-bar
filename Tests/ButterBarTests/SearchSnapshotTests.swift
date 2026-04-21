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

// MARK: - SearchSnapshotTests
//
// Light + dark snapshots cover all five SearchViewState cases: idle, loading,
// loaded, noResults, error. States are seeded via _setStateForTesting(_:).
// Baselines live in `__Snapshots__/SearchSnapshotTests/`.

@MainActor
final class SearchSnapshotTests: XCTestCase {

    private let snapshotSize = CGSize(width: 800, height: 900)
    private let fakeProvider = SearchSnapshotFakeProvider()

    private func makeView(_ vm: SearchViewModel) -> some View {
        SearchView(viewModel: vm, provider: fakeProvider, onSelect: { _ in })
            .frame(width: snapshotSize.width, height: snapshotSize.height)
    }

    // MARK: - Idle state

    func testIdleLight() {
        let vm = SearchViewModel(provider: fakeProvider)
        let view = makeView(vm).environment(\.colorScheme, .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "idle-light")
    }

    func testIdleDark() {
        let vm = SearchViewModel(provider: fakeProvider)
        let view = makeView(vm).environment(\.colorScheme, .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "idle-dark")
    }

    // MARK: - Loading state

    func testLoadingLight() {
        let vm = SearchViewModel(provider: fakeProvider)
        vm._setStateForTesting(.loading(query: "inception"))
        let view = makeView(vm).environment(\.colorScheme, .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loading-light")
    }

    func testLoadingDark() {
        let vm = SearchViewModel(provider: fakeProvider)
        vm._setStateForTesting(.loading(query: "inception"))
        let view = makeView(vm).environment(\.colorScheme, .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loading-dark")
    }

    // MARK: - Loaded state

    func testLoadedLight() {
        let vm = SearchViewModel(provider: fakeProvider)
        vm._setStateForTesting(.loaded(query: "inception", results: SearchSnapshotFakeProvider.sampleResults))
        let view = makeView(vm).environment(\.colorScheme, .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loaded-light")
    }

    func testLoadedDark() {
        let vm = SearchViewModel(provider: fakeProvider)
        vm._setStateForTesting(.loaded(query: "inception", results: SearchSnapshotFakeProvider.sampleResults))
        let view = makeView(vm).environment(\.colorScheme, .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loaded-dark")
    }

    // MARK: - No results state

    func testNoResultsLight() {
        let vm = SearchViewModel(provider: fakeProvider)
        vm._setStateForTesting(.noResults(query: "xyznotfound"))
        let view = makeView(vm).environment(\.colorScheme, .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "no-results-light")
    }

    func testNoResultsDark() {
        let vm = SearchViewModel(provider: fakeProvider)
        vm._setStateForTesting(.noResults(query: "xyznotfound"))
        let view = makeView(vm).environment(\.colorScheme, .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "no-results-dark")
    }

    // MARK: - Error state

    func testErrorLight() {
        let vm = SearchViewModel(provider: fakeProvider)
        vm._setStateForTesting(.error(query: "inception"))
        let view = makeView(vm).environment(\.colorScheme, .light)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "error-light")
    }

    func testErrorDark() {
        let vm = SearchViewModel(provider: fakeProvider)
        vm._setStateForTesting(.error(query: "inception"))
        let view = makeView(vm).environment(\.colorScheme, .dark)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "error-dark")
    }
}

// MARK: - Fake provider for snapshot tests

private final class SearchSnapshotFakeProvider: MetadataProvider, @unchecked Sendable {

    static let sampleResults: [MediaItem] = [
        .movie(Movie(
            id: MediaID(provider: .tmdb, id: 27205),
            title: "Inception",
            originalTitle: "Inception",
            releaseYear: 2010,
            runtimeMinutes: 148,
            overview: "A thief who steals corporate secrets through dream-sharing technology is given the inverse task of planting an idea into the mind of a CEO.",
            genres: [],
            posterPath: "/poster.jpg",
            backdropPath: nil,
            voteAverage: 8.4,
            popularity: 80.5
        )),
        .show(Show(
            id: MediaID(provider: .tmdb, id: 1399),
            name: "Game of Thrones",
            originalName: "Game of Thrones",
            firstAirYear: 2011,
            overview: "Seven noble families fight for control of the mythical land of Westeros.",
            genres: [],
            posterPath: "/poster2.jpg",
            backdropPath: nil,
            voteAverage: 9.3,
            popularity: 369.6
        )),
    ]

    func searchMulti(query: String) async throws -> [MediaItem] { [] }
    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] { [] }
    func popular(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func topRated(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func movieDetail(id: MediaID) async throws -> Movie { throw MetadataProviderError.notFound }
    func showDetail(id: MediaID) async throws -> Show { throw MetadataProviderError.notFound }
    func seasonDetail(showID: MediaID, season: Int) async throws -> Season { throw MetadataProviderError.notFound }
    func recommendations(for id: MediaID) async throws -> [MediaItem] { [] }
    func imageURL(path: String, size: TMDBImageSize) -> URL { URL(string: "https://example.invalid")! }
}
