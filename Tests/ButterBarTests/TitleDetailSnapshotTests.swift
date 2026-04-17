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

// MARK: - TitleDetailSnapshotTests
//
// Light + dark snapshots cover: movie variant, show variant,
// recommendations row populated and empty, loading state, error state, and
// the "in your library" badge. Baselines live in
// `__Snapshots__/TitleDetailSnapshotTests/`.
//
// Provider is the local SnapshotProvider — only the `imageURL` surface is
// exercised; no async fetch happens because the view model is seeded with
// `.loaded` directly via the preview factories.

@MainActor
final class TitleDetailSnapshotTests: XCTestCase {

    private let snapshotSize = CGSize(width: 900, height: 1200)
    private let provider = SnapshotProvider()

    // MARK: - Movie variant

    func testMovieVariantLight() {
        let vm = TitleDetailViewModel.previewLoadedMovie(
            provider: provider,
            recommendations: SamplePreviewData.recommendations,
            cast: SamplePreviewData.cast
        )
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "movie-variant-light")
    }

    func testMovieVariantDark() {
        let vm = TitleDetailViewModel.previewLoadedMovie(
            provider: provider,
            recommendations: SamplePreviewData.recommendations,
            cast: SamplePreviewData.cast
        )
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "movie-variant-dark")
    }

    // MARK: - Show variant

    func testShowVariantLight() {
        let vm = TitleDetailViewModel.previewLoadedShow(
            provider: provider,
            recommendations: SamplePreviewData.recommendations,
            cast: SamplePreviewData.cast
        )
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "show-variant-light")
    }

    func testShowVariantDark() {
        let vm = TitleDetailViewModel.previewLoadedShow(
            provider: provider,
            recommendations: SamplePreviewData.recommendations,
            cast: SamplePreviewData.cast
        )
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "show-variant-dark")
    }

    // MARK: - Recommendations empty

    func testRecommendationsEmptyLight() {
        let vm = TitleDetailViewModel.previewLoadedMovie(
            provider: provider,
            recommendations: [],
            cast: SamplePreviewData.cast
        )
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "recs-empty-light")
    }

    func testRecommendationsEmptyDark() {
        let vm = TitleDetailViewModel.previewLoadedMovie(
            provider: provider,
            recommendations: [],
            cast: SamplePreviewData.cast
        )
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "recs-empty-dark")
    }

    // MARK: - Loading state

    func testLoadingLight() {
        let vm = TitleDetailViewModel.previewLoading(provider: provider)
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loading-light")
    }

    func testLoadingDark() {
        let vm = TitleDetailViewModel.previewLoading(provider: provider)
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "loading-dark")
    }

    // MARK: - Error state

    func testErrorLight() {
        let vm = TitleDetailViewModel.previewError(provider: provider)
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "error-light")
    }

    func testErrorDark() {
        let vm = TitleDetailViewModel.previewError(provider: provider)
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "error-dark")
    }

    // MARK: - In your library badge

    func testInYourLibraryLight() {
        let vm = TitleDetailViewModel.previewLoadedMovie(
            provider: provider,
            recommendations: SamplePreviewData.recommendations,
            cast: SamplePreviewData.cast,
            libraryMatch: SamplePreviewData.libraryMatch
        )
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .light)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "in-library-light")
    }

    func testInYourLibraryDark() {
        let vm = TitleDetailViewModel.previewLoadedMovie(
            provider: provider,
            recommendations: SamplePreviewData.recommendations,
            cast: SamplePreviewData.cast,
            libraryMatch: SamplePreviewData.libraryMatch
        )
        let view = TitleDetailView(viewModel: vm)
            .environment(\.colorScheme, .dark)
            .frame(width: snapshotSize.width, height: snapshotSize.height)
        assertSnapshot(of: hosted(view, size: snapshotSize), as: .image,
                       named: "in-library-dark")
    }
}

// MARK: - Snapshot provider — image-URL only.

private final class SnapshotProvider: MetadataProvider, @unchecked Sendable {
    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem] { [] }
    func popular(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func topRated(media: TrendingMedia) async throws -> [MediaItem] { [] }
    func searchMulti(query: String) async throws -> [MediaItem] { [] }
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
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return URL(string: "https://image.tmdb.org/t/p")!
            .appendingPathComponent(size.rawValue)
            .appendingPathComponent(trimmed)
    }
}
