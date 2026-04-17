import SwiftUI
import MetadataDomain

struct SearchView: View {
    @ObservedObject var viewModel: SearchViewModel
    let provider: MetadataProvider
    let onSelect: (MediaItem) -> Void

    var body: some View {
        ScrollView {
            content
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BrandColors.surfaceBase)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .loading:
            loadingRows
        case .loaded(_, let results):
            resultList(results)
        case .noResults(let query):
            quietMessage("Nothing matched '\(query)'.")
        case .error:
            quietMessage("We can't reach the catalogue right now.")
        }
    }

    private var loadingRows: some View {
        VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                SearchLoadingRow()
            }
        }
    }

    private func resultList(_ results: [MediaItem]) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(results, id: \.id) { item in
                Button {
                    onSelect(item)
                } label: {
                    SearchResultRow(item: item, provider: provider)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quietMessage(_ text: String) -> some View {
        Text(text)
            .brandBodyRegular()
            .foregroundStyle(BrandColors.cocoaSoft)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
    }
}

private struct SearchResultRow: View {
    let item: MediaItem
    let provider: MetadataProvider

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            poster
                .frame(width: 72, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .brandBodyEmphasis()
                        .foregroundStyle(BrandColors.cocoa)
                        .lineLimit(1)
                    if let year {
                        Text(String(year))
                            .brandCaptionMonospacedNumeric()
                            .foregroundStyle(BrandColors.cocoaSoft)
                    }
                    Text(kindLabel)
                        .brandCaption()
                        .foregroundStyle(BrandColors.cocoa)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(BrandColors.butter.opacity(0.18))
                        .clipShape(Capsule())
                }

                Text(overview.isEmpty ? "No synopsis available." : overview)
                    .brandCaption()
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(BrandColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var poster: some View {
        if let posterPath {
            AsyncImage(url: provider.imageURL(path: posterPath, size: .w154)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(BrandColors.butter.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(BrandColors.cocoaFaint.opacity(0.35), lineWidth: 0.5)
            )
    }

    private var title: String {
        switch item {
        case .movie(let movie): return movie.title
        case .show(let show): return show.name
        }
    }

    private var year: Int? {
        switch item {
        case .movie(let movie): return movie.releaseYear
        case .show(let show): return show.firstAirYear
        }
    }

    private var kindLabel: String {
        switch item {
        case .movie: return "Movie"
        case .show: return "Show"
        }
    }

    private var overview: String {
        switch item {
        case .movie(let movie): return movie.overview
        case .show(let show): return show.overview
        }
    }

    private var posterPath: String? {
        switch item {
        case .movie(let movie): return movie.posterPath
        case .show(let show): return show.posterPath
        }
    }
}

private struct SearchLoadingRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BrandColors.creamRaised)
                .frame(width: 72, height: 108)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(BrandColors.creamRaised)
                    .frame(width: 220, height: 16)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(BrandColors.creamRaised)
                    .frame(width: 320, height: 12)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(BrandColors.creamRaised)
                    .frame(width: 280, height: 12)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(BrandColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .redacted(reason: .placeholder)
    }
}
