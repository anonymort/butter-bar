import SwiftUI
import MetadataDomain

// MARK: - TitleDetailView
//
// Phase 4 detail surface. Renders a `MediaItem` (movie | show) with full
// metadata, cast, recommendations, and (when applicable) an "in your
// library" indicator. States: loading shimmer, error + retry, loaded.
// All colour through brand tokens (`06-brand.md`); no system colours.

struct TitleDetailView: View {

    @ObservedObject var viewModel: TitleDetailViewModel
    /// Tap-through navigation for recommendation cards. Caller wires up the
    /// route (typically pushing another `TitleDetailView`).
    var onSelectRecommendation: (MediaItem) -> Void = { _ in }
    /// Tap-through to the matched library file (route to LibraryView /
    /// PlayerView). Caller decides; defaults to no-op.
    var onOpenLibraryMatch: (LibraryMatch) -> Void = { _ in }
    /// Show variant primary affordance. Routes to the season/episode
    /// selector once #16 lands; until then it shows a placeholder modal.
    var onBrowseSeasons: (Show) -> Void = { _ in }
    /// Movie variant primary affordance. Provider integration is Module 6
    /// (p1); v1 opens a placeholder modal explaining the gap.
    var onFindTorrent: (Movie) -> Void = { _ in }

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BrandColors.surfaceBase.ignoresSafeArea())
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            TitleDetailLoadingView()
        case .error:
            TitleDetailErrorView { Task { await viewModel.retry() } }
        case .loaded(let detail, _):
            loaded(detail)
        }
    }

    @ViewBuilder
    private func loaded(_ detail: TitleDetail) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            BackdropHeader(detail: detail, viewModel: viewModel)

            VStack(alignment: .leading, spacing: 20) {
                if let match = detail.libraryMatch {
                    InYourLibraryBadge(match: match, onTap: { onOpenLibraryMatch(match) })
                }

                primaryCTA(for: detail)

                synopsisSection(detail.overview)

                if !detail.genres.isEmpty {
                    GenreChipRow(genres: detail.genres)
                }

                if !detail.cast.isEmpty {
                    CastChipRow(cast: detail.cast,
                                imageURL: { viewModel.castProfileURL($0) })
                }

                RecommendationsRow(
                    recommendations: detail.recommendations,
                    posterURL: { viewModel.recommendationPosterURL($0) },
                    onSelect: onSelectRecommendation
                )
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private func primaryCTA(for detail: TitleDetail) -> some View {
        switch detail.item {
        case .movie(let movie):
            Button {
                onFindTorrent(movie)
            } label: {
                Label("Find a torrent", systemImage: "magnifyingglass")
                    .font(BrandTypography.bodyEmphasis)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .foregroundStyle(BrandColors.cocoa)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BrandColors.butter)
                    )
            }
            .buttonStyle(.plain)
        case .show(let show):
            Button {
                onBrowseSeasons(show)
            } label: {
                Label("Browse seasons", systemImage: "rectangle.stack")
                    .font(BrandTypography.bodyEmphasis)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .foregroundStyle(BrandColors.cocoa)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BrandColors.butter)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func synopsisSection(_ overview: String) -> some View {
        // Synopsis as-is from TMDB; if absent show calm fallback string per
        // brand voice — not "N/A" or "Description unavailable".
        let text = overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No synopsis available."
            : overview
        return Text(text)
            .font(BrandTypography.bodyRegular)
            .foregroundStyle(BrandColors.cocoa)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Backdrop header

private struct BackdropHeader: View {

    let detail: TitleDetail
    @ObservedObject var viewModel: TitleDetailViewModel

    private let backdropHeight: CGFloat = 360

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            // Soft warm gradient so the title overlay reads cleanly without
            // black scrim. Top of the gradient is transparent, bottom is the
            // surface base — keeps the warm palette intact.
            LinearGradient(
                stops: [
                    .init(color: BrandColors.surfaceBase.opacity(0.0), location: 0.0),
                    .init(color: BrandColors.surfaceBase.opacity(0.85), location: 0.85),
                    .init(color: BrandColors.surfaceBase, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            titleOverlay
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: backdropHeight)
        .clipped()
    }

    @ViewBuilder
    private var backdrop: some View {
        // Brand-tokenised soft butter placeholder (also the fallback when
        // there is no backdrop on the metadata record).
        Rectangle()
            .fill(BrandColors.butter.opacity(0.18))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let path = detail.backdropPath {
                    AsyncImage(url: viewModel.backdropURL(path)) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                // 400 ms cross-fade per brand spec § Motion.
                                .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                        default:
                            EmptyView()
                        }
                    }
                }
            }
    }

    private var titleOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.displayTitle)
                .brandDisplay()
                .foregroundStyle(BrandColors.cocoa)
                .lineLimit(2)
            metadataLine
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 14) {
            if let year = detail.year {
                Text(verbatim: String(year))
                    .brandMonospacedNumeric()
                    .foregroundStyle(BrandColors.cocoaSoft)
            }
            if let runtime = detail.runtimeMinutes {
                Text(formatRuntime(runtime))
                    .brandMonospacedNumeric()
                    .foregroundStyle(BrandColors.cocoaSoft)
            }
            if let rating = detail.voteAverage {
                Text(String(format: "%.1f", rating))
                    .brandMonospacedNumeric()
                    .foregroundStyle(BrandColors.cocoaSoft)
            }
        }
    }

    private func formatRuntime(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }
}

// MARK: - In your library badge

private struct InYourLibraryBadge: View {
    let match: LibraryMatch
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BrandColors.tierHealthy)
                VStack(alignment: .leading, spacing: 2) {
                    Text("In your library")
                        .font(BrandTypography.caption)
                        .foregroundStyle(BrandColors.cocoa)
                    Text(match.displayName)
                        .font(BrandTypography.caption)
                        .foregroundStyle(BrandColors.cocoaSoft)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BrandColors.surfaceRaised)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Loading shimmer
//
// Calm shimmer over the layout shape per brand voice — never a spinner.
// We render the same skeleton as the loaded state so the page does not
// jump on first paint.

private struct TitleDetailLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ShimmerBlock()
                .frame(maxWidth: .infinity)
                .frame(height: 360)

            VStack(alignment: .leading, spacing: 16) {
                ShimmerBlock()
                    .frame(width: 220, height: 18)
                ShimmerBlock()
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                ShimmerBlock()
                    .frame(maxWidth: .infinity)
                    .frame(height: 14)
                ShimmerBlock()
                    .frame(width: 280, height: 14)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
    }
}

private struct ShimmerBlock: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(BrandColors.butter.opacity(0.18))
    }
}

// MARK: - Error state

private struct TitleDetailErrorView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("We can't load this title right now.")
                .font(BrandTypography.bodyEmphasis)
                .foregroundStyle(BrandColors.cocoa)
                .multilineTextAlignment(.center)
            Button(action: onRetry) {
                Text("Retry")
                    .font(BrandTypography.bodyRegular)
                    .foregroundStyle(BrandColors.cocoa)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BrandColors.butter.opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
        .padding(.horizontal, 28)
    }
}
