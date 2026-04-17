import SwiftUI
import MetadataDomain

/// Movies sidebar destination (#13). Simple grid of poster cards drawn from
/// `MetadataProvider.popular(.movie)`. Genre filters / sort controls are p2
/// per the issue scope; this v1 surface intentionally stays minimal.
struct MoviesGridView: View {

    let provider: MetadataProvider
    @Binding var selectedItem: MediaItem?

    @State private var state: HomeRowState = .loading

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollView {
            content
                .padding(16)
        }
        .background(BrandColors.surfaceBase)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            shimmer
        case .loaded(let items):
            grid(items)
        case .failed:
            quietMessage("We can't reach the catalogue right now.")
        case .empty:
            quietMessage("Nothing here yet.")
        }
    }

    private func grid(_ items: [MediaItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(items, id: \.id) { item in
                Button {
                    selectedItem = item
                } label: {
                    PosterCard(item: item, provider: provider)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var shimmer: some View {
        LazyVGrid(columns: columns, spacing: 24) {
            ForEach(0..<12, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrandColors.creamRaised)
                    .frame(height: 198)
            }
        }
    }

    private func quietMessage(_ text: String) -> some View {
        Text(text)
            .brandCaption()
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
    }

    private func load() async {
        do {
            let items = try await provider.popular(media: .movie)
            state = items.isEmpty ? .empty : .loaded(items)
        } catch {
            state = .failed
        }
    }
}
