import SwiftUI
import MetadataDomain

struct SeasonEpisodeSelectorView: View {
    @ObservedObject var viewModel: SeasonEpisodeSelectorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var torrentEpisode: Episode?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(BrandColors.cocoaFaint.opacity(0.3))
            seasonPicker
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            content
        }
        .background(BrandColors.surfaceBase)
        .task { await viewModel.load() }
        .sheet(item: $torrentEpisode) { episode in
            FindTorrentPlaceholder(episode: episode)
                .frame(minWidth: 320, minHeight: 180)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.show.name)
                    .brandBodyEmphasis()
                    .foregroundStyle(BrandColors.cocoa)
                Text("Episodes")
                    .brandCaption()
            }
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(BrandTypography.caption)
                    .foregroundStyle(BrandColors.cocoaSoft)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close episode selector")
        }
        .padding(20)
    }

    private var seasonPicker: some View {
        Picker("Season", selection: Binding(
            get: { viewModel.selectedSeasonNumber },
            set: { season in Task { await viewModel.selectSeason(season) } }
        )) {
            ForEach(viewModel.seasons, id: \.seasonNumber) { season in
                Text(season.name).tag(season.seasonNumber)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            loadingRows
        case .error:
            VStack(spacing: 12) {
                Text("We can't reach the catalogue right now.")
                    .brandBodyRegular()
                    .foregroundStyle(BrandColors.cocoaSoft)
                Button("Retry") { Task { await viewModel.retry() } }
                    .buttonStyle(.plain)
                    .brandBodyEmphasis()
                    .foregroundStyle(BrandColors.butterDeep)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.episodeRows) { row in
                        EpisodeSelectorRow(
                            row: row,
                            stillURL: { viewModel.posterURL($0) },
                            onFindTorrent: { torrentEpisode = row.episode }
                        )
                    }
                }
                .padding(20)
            }
        }
    }

    private var loadingRows: some View {
        VStack(spacing: 12) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BrandColors.surfaceRaised)
                    .frame(height: 118)
                    .redacted(reason: .placeholder)
            }
        }
        .padding(20)
    }
}

private struct EpisodeSelectorRow: View {
    let row: EpisodeRow
    let stillURL: (String) -> URL
    let onFindTorrent: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            still
                .frame(width: 132, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(String(format: "%02d", row.episode.episodeNumber))
                        .brandCaptionMonospacedNumeric()
                        .foregroundStyle(BrandColors.cocoaSoft)
                    Text(row.episode.name)
                        .brandBodyEmphasis()
                        .foregroundStyle(BrandColors.cocoa)
                        .lineLimit(1)
                    if let label = row.badge.label {
                        Text(label)
                            .brandCaption()
                            .foregroundStyle(BrandColors.cocoa)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(BrandColors.butter.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                    if let runtime = row.episode.runtimeMinutes {
                        Text("\(runtime)m")
                            .brandCaptionMonospacedNumeric()
                            .foregroundStyle(BrandColors.cocoaSoft)
                    }
                }

                Text(row.episode.overview.isEmpty ? "No synopsis available." : row.episode.overview)
                    .brandCaption()
                    .lineLimit(2)

                Button("Find a torrent", action: onFindTorrent)
                    .buttonStyle(.plain)
                    .brandCaption()
                    .foregroundStyle(BrandColors.butterDeep)
            }
        }
        .padding(12)
        .background(BrandColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var still: some View {
        if let path = row.episode.stillPath {
            AsyncImage(url: stillURL(path)) { phase in
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
    }
}

private struct FindTorrentPlaceholder: View {
    let episode: Episode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find a torrent")
                .brandBodyEmphasis()
                .foregroundStyle(BrandColors.cocoa)
            Text("Source search is not wired yet for Season \(episode.seasonNumber), Episode \(episode.episodeNumber).")
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
