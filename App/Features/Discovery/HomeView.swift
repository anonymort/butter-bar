import SwiftUI
import MetadataDomain

/// Home landing surface (#13). Vertically stacks Continue Watching plus the
/// six TMDB-backed carousels per `discovery-metadata-foundation.md § D11`.
/// Each carousel loads independently so a single row failure doesn't blank
/// the whole page.
struct HomeView: View {

    @ObservedObject var viewModel: HomeViewModel
    let provider: MetadataProvider
    /// Bound by `ContentView` to push a `DetailRouteStub` (or, post-#15, the
    /// real detail page).
    @Binding var selectedItem: MediaItem?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.rows, id: \.kind) { row in
                    if viewModel.shouldRender(row.kind) {
                        MediaCarouselRow(
                            title: row.kind.title,
                            state: row.state,
                            provider: provider,
                            onSelect: { selectedItem = $0 }
                        )
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .background(BrandColors.surfaceBase)
        .task { await viewModel.load() }
    }
}
