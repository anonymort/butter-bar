import SwiftUI
import MetadataDomain

/// Horizontally-scrolling carousel for one Home row. Renders the row title,
/// then a state-appropriate body: shimmer placeholders while loading, the
/// poster cards when loaded, a calm one-liner on failure or empty.
///
/// Tap → navigates via the `onSelect` closure. Detail page is #15; this row
/// just emits the selected `MediaItem` and lets the parent route.
struct MediaCarouselRow: View {

    let title: String
    let state: HomeRowState
    let provider: MetadataProvider
    let onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .brandBodyEmphasis()
                .foregroundStyle(BrandColors.cocoa)
                .padding(.horizontal, 16)

            content
                .animation(.easeInOut(duration: 0.2), value: state.isLoaded)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            shimmerRow
        case .loaded(let items):
            cardsRow(items)
        case .failed:
            quietMessage("We can't reach the catalogue right now.")
        case .empty:
            quietMessage("Nothing here yet.")
        }
    }

    private func cardsRow(_ items: [MediaItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items, id: \.id) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        PosterCard(item: item, provider: provider)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// Shimmer = three muted placeholder cards. Calm, no spinner per
    /// `06-brand.md § Motion`.
    private var shimmerRow: some View {
        HStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(BrandColors.creamRaised)
                        .frame(width: 132, height: 198)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(BrandColors.creamRaised)
                        .frame(width: 100, height: 12)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private func quietMessage(_ text: String) -> some View {
        Text(text)
            .brandCaption()
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
    }
}
