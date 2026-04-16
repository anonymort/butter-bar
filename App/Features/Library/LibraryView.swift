import SwiftUI
import EngineInterface

// MARK: - LibraryView

struct LibraryView: View {

    @ObservedObject var viewModel: LibraryViewModel

    @State private var searchQuery: String = ""
    @State private var selectedTorrentID: String?
    @State private var fileSheetState: FileSheetState?

    var body: some View {
        Group {
            if viewModel.torrents.isEmpty && viewModel.loadError == nil {
                emptyState
            } else {
                torrentList
            }
        }
        .background(BrandColors.surfaceBase)
        .searchable(text: $searchQuery, placement: .toolbar, prompt: "Filter")
        .task { await viewModel.refresh() }
        .sheet(item: $fileSheetState) { state in
            FileSelectionSheet(
                torrentName: state.torrentName,
                files: state.files,
                onSelect: { _ in fileSheetState = nil }
            )
        }
        .animation(.easeInOut(duration: 0.25), value: filteredTorrents.count)
    }

    // MARK: - Filtered data

    private var filteredTorrents: [TorrentSummaryDTO] {
        guard !searchQuery.isEmpty else { return viewModel.torrents }
        return viewModel.torrents.filter {
            (($0.name as String)).localizedStandardContains(searchQuery)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("Add a magnet link to begin.")
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoa)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var torrentList: some View {
        // Use a mapped id (String) so the selection binding type matches.
        List(selection: $selectedTorrentID) {
            ForEach(filteredTorrents, id: \.torrentID) { torrent in
                TorrentRow(torrent: torrent)
                    .tag(torrent.torrentID as String)
                    .contentShape(Rectangle())
                    .onTapGesture { handleRowTap(torrent) }
                    .listRowBackground(BrandColors.surfaceBase)
                    .listRowSeparatorTint(BrandColors.cocoaFaint)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BrandColors.surfaceBase)
        .overlay {
            if !viewModel.torrents.isEmpty && filteredTorrents.isEmpty {
                noResultsOverlay
            }
        }
        .overlay(alignment: .bottom) {
            if let error = viewModel.loadError {
                errorBanner(error)
            }
        }
    }

    private var noResultsOverlay: some View {
        VStack {
            Text("No torrents match that filter.")
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoaSoft)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text("Could not load library: \(message)")
            .brandCaption()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BrandColors.creamRaised)
    }

    // MARK: - Actions

    private func handleRowTap(_ torrent: TorrentSummaryDTO) {
        selectedTorrentID = torrent.torrentID as String
        Task {
            do {
                let files = try await viewModel.listFiles(torrentID: torrent.torrentID)
                if files.count > 1 {
                    fileSheetState = FileSheetState(torrentName: torrent.name as String, files: files)
                }
                // Single-file: row is selected; no sheet.
            } catch {
                // Non-fatal — engine may not support file listing yet.
                // Silently ignore; user can retry.
            }
        }
    }
}

// MARK: - FileSheetState

private struct FileSheetState: Identifiable {
    let id = UUID()
    let torrentName: String
    let files: [TorrentFileDTO]
}

// MARK: - TorrentRow

private struct TorrentRow: View {
    let torrent: TorrentSummaryDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(torrent.name as String)
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoa)
                .lineLimit(1)

            HStack(spacing: 8) {
                Text(formattedSize)
                    .brandCaption()
                Text("·")
                    .brandCaption()
                Text(formattedPeers)
                    .brandCaption()
                Text("·")
                    .brandCaption()
                Text(formattedProgress)
                    .brandMonospacedNumeric()
                    .font(.system(size: 12))
                    .foregroundStyle(BrandColors.cocoaSoft)
                if torrent.downRateBytesPerSec > 0 {
                    Text("·")
                        .brandCaption()
                    Text(formattedDownRate)
                        .brandMonospacedNumeric()
                        .font(.system(size: 12))
                        .foregroundStyle(BrandColors.cocoaSoft)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: Formatters

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: torrent.totalBytes, countStyle: .file)
    }

    private var formattedPeers: String {
        let count = Int(torrent.peerCount)
        return count == 1 ? "1 peer" : "\(count) peers"
    }

    private var formattedProgress: String {
        // progressQ16: 65536 = 100%
        let percent = Int(torrent.progressQ16) * 100 / 65_536
        return "\(percent)%"
    }

    private var formattedDownRate: String {
        ByteCountFormatter.string(fromByteCount: torrent.downRateBytesPerSec, countStyle: .file) + "/s"
    }
}

// MARK: - Previews

#Preview("Library — light") {
    LibraryView(viewModel: .previewWithData)
        .preferredColorScheme(.light)
        .frame(width: 480, height: 400)
}

#Preview("Library — dark") {
    LibraryView(viewModel: .previewWithData)
        .preferredColorScheme(.dark)
        .frame(width: 480, height: 400)
}

#Preview("Library — empty, light") {
    LibraryView(viewModel: .previewEmpty)
        .preferredColorScheme(.light)
        .frame(width: 480, height: 400)
}

#Preview("Library — empty, dark") {
    LibraryView(viewModel: .previewEmpty)
        .preferredColorScheme(.dark)
        .frame(width: 480, height: 400)
}
