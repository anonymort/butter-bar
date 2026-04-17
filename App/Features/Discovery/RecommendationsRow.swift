import SwiftUI
import MetadataDomain

// MARK: - Recommendations row
//
// Horizontally-scrolling carousel of poster cards. Mirrors the chrome
// #13's home rows will use; until #13 lands, this is the canonical pattern
// inside the Discovery feature folder. Empty list renders nothing — the
// section header is suppressed alongside the cards so we don't show a
// dangling "You might also like" with no follow-on.

struct RecommendationsRow: View {
    let recommendations: [MediaItem]
    let posterURL: (String) -> URL
    let onSelect: (MediaItem) -> Void

    var body: some View {
        if recommendations.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("You might also like")
                    .font(BrandTypography.bodyEmphasis)
                    .foregroundStyle(BrandColors.cocoa)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(recommendations, id: \.id) { item in
                            RecommendationCard(item: item, posterURL: posterURL) {
                                onSelect(item)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct RecommendationCard: View {
    let item: MediaItem
    let posterURL: (String) -> URL
    let onTap: () -> Void

    private let posterWidth: CGFloat = 140
    private let posterHeight: CGFloat = 210

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    // Soft butter placeholder (matches AC for image placeholders).
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BrandColors.butter.opacity(0.18))
                        .frame(width: posterWidth, height: posterHeight)

                    if let path = posterPath {
                        AsyncImage(url: posterURL(path)) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: posterWidth, height: posterHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                            default:
                                EmptyView()
                            }
                        }
                    }
                }
                Text(displayTitle)
                    .font(BrandTypography.caption)
                    .foregroundStyle(BrandColors.cocoa)
                    .lineLimit(2)
                    .frame(width: posterWidth, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String {
        switch item {
        case .movie(let m): return m.title
        case .show(let s): return s.name
        }
    }

    private var posterPath: String? {
        switch item {
        case .movie(let m): return m.posterPath
        case .show(let s): return s.posterPath
        }
    }
}
