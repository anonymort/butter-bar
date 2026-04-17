import SwiftUI
import MetadataDomain

/// Sheet route for a selected discovery item. The name is retained to avoid
/// churn in the Xcode project, but the route now hosts the real title detail
/// page and season selector.
struct DetailRouteStub: View {
    let item: MediaItem
    let provider: MetadataProvider
    let engineClient: EngineClient

    @StateObject private var viewModel: TitleDetailViewModel
    @State private var selectedShow: Show?
    @State private var findTorrentMovie: Movie?

    init(item: MediaItem,
         provider: MetadataProvider,
         engineClient: EngineClient) {
        self.item = item
        self.provider = provider
        self.engineClient = engineClient
        let kind: TitleDetailViewModel.Kind
        switch item {
        case .movie:
            kind = .movie
        case .show:
            kind = .show
        }
        _viewModel = StateObject(wrappedValue: TitleDetailViewModel(
            id: item.id,
            kind: kind,
            provider: provider
        ))
    }

    var body: some View {
        TitleDetailView(
            viewModel: viewModel,
            onSelectRecommendation: { _ in },
            onOpenLibraryMatch: { _ in },
            onBrowseSeasons: { selectedShow = $0 },
            onFindTorrent: { findTorrentMovie = $0 }
        )
        .sheet(item: $selectedShow) { show in
            SeasonEpisodeSelectorView(
                viewModel: SeasonEpisodeSelectorViewModel(
                    show: show,
                    provider: provider,
                    engineClient: engineClient
                )
            )
            .frame(minWidth: 720, minHeight: 560)
        }
        .sheet(item: $findTorrentMovie) { movie in
            FindTorrentMoviePlaceholder(movie: movie)
                .frame(minWidth: 320, minHeight: 180)
        }
    }
}

private struct FindTorrentMoviePlaceholder: View {
    let movie: Movie
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find a torrent")
                .brandBodyEmphasis()
                .foregroundStyle(BrandColors.cocoa)
            Text("Source search is not wired yet for \(movie.title).")
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoaSoft)
            Spacer()
            Button("Close") { dismiss() }
                .buttonStyle(.plain)
                .brandBodyEmphasis()
                .foregroundStyle(BrandColors.butterDeep)
        }
        .padding(20)
        .background(BrandColors.surfaceRaised)
    }
}
