import SwiftUI
import EngineInterface
import LibraryDomain

// MARK: - LibraryView

struct LibraryView: View {

    @ObservedObject var viewModel: LibraryViewModel

    @State private var searchQuery: String = ""
    @State private var selectedTorrentID: String?
    @State private var fileSheetState: FileSheetState?
    /// Wraps `StreamDescriptorDTO` with a stable `Identifiable` id so we can
    /// use `.sheet(item:)` without making `StreamDescriptorDTO` itself `Identifiable`.
    @State private var activeStream: ActiveStream?

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $viewModel.favouritesOnly) {
                    Image(systemName: viewModel.favouritesOnly ? "heart.fill" : "heart")
                        .foregroundStyle(
                            viewModel.favouritesOnly ? BrandColors.butter : BrandColors.cocoaSoft
                        )
                }
                .toggleStyle(.button)
                .help(viewModel.favouritesOnly ? "Showing favourites only" : "Show favourites only")
            }
        }
        .task { await viewModel.start() }
        // File selection sheet (multi-file torrents).
        .sheet(item: $fileSheetState) { state in
            FileSelectionSheet(
                torrentName: state.torrentName,
                files: state.files,
                onSelect: { fileIndex in
                    fileSheetState = nil
                    openStream(torrentID: state.torrentID, fileIndex: fileIndex)
                }
            )
        }
        // Player sheet — presented when a stream is successfully opened.
        .sheet(item: $activeStream) { stream in
            PlayerView(
                streamDescriptor: stream.descriptor,
                engineClient: viewModel.engineClient
            )
            .frame(minWidth: 640, minHeight: 360)
            .onDisappear {
                // PlayerView.onDisappear calls close() on the view model;
                // clear the active stream state so the sheet binding is released.
                activeStream = nil
            }
        }
        .animation(.easeInOut(duration: 0.25), value: filteredTorrents.count)
    }

    // MARK: - Filtered data

    private var filteredTorrents: [TorrentSummaryDTO] {
        // displayedTorrents applies the favouritesOnly filter (#36).
        let base = viewModel.displayedTorrents
        guard !searchQuery.isEmpty else { return base }
        return base.filter {
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
            // #35 — Continue watching row, hidden when projection is empty
            // (no in-progress / re-watching items). Rendered as a list section
            // with a transparent background so it blends with the surrounding
            // surface.
            if !viewModel.continueWatching.isEmpty {
                Section {
                    ContinueWatchingRow(
                        items: viewModel.continueWatching,
                        onOpen: { item in
                            openStream(
                                torrentID: item.torrent.torrentID as String,
                                fileIndex: Int32(item.fileIndex)
                            )
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(BrandColors.surfaceBase)
                    .listRowSeparator(.hidden)
                }
            }

            Section {
                ForEach(filteredTorrents, id: \.torrentID) { torrent in
                    TorrentRow(
                        torrent: torrent,
                        watchStatus: viewModel.watchStatus(
                            torrentID: torrent.torrentID as String,
                            fileIndex: 0,
                            totalBytes: torrent.totalBytes
                        ),
                        isFavourite: viewModel.isFavourite(
                            torrentID: torrent.torrentID as String,
                            fileIndex: 0
                        ),
                        onToggleFavourite: {
                            Task {
                                await viewModel.toggleFavourite(
                                    torrentID: torrent.torrentID as String,
                                    fileIndex: 0
                                )
                            }
                        }
                    )
                    .tag(torrent.torrentID as String)
                    .contentShape(Rectangle())
                    .onTapGesture { handleRowTap(torrent) }
                    .contextMenu {
                        watchStateMenuItems(for: torrent)
                    }
                    .listRowBackground(BrandColors.surfaceBase)
                    .listRowSeparatorTint(BrandColors.cocoaFaint)
                }
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
        Text("No torrents match that filter.")
            .brandBodyRegular()
            .foregroundStyle(BrandColors.cocoaSoft)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
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
                let files = try await viewModel.listFiles(torrentID: torrent.torrentID as String)
                if files.count > 1 {
                    fileSheetState = FileSheetState(
                        torrentID: torrent.torrentID as String,
                        torrentName: torrent.name as String,
                        files: files
                    )
                } else {
                    // Single-file torrent: open stream directly at index 0.
                    openStream(torrentID: torrent.torrentID as String, fileIndex: 0)
                }
            } catch {
                viewModel.loadError = "Could not load files: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Watch state context menu (#37)

    /// Build the mark-watched / mark-unwatched menu items for a torrent.
    /// v1 limitation: targets file index 0. Multi-file mark-watched is a
    /// follow-up; documented in #37 PR body.
    @ViewBuilder
    private func watchStateMenuItems(for torrent: TorrentSummaryDTO) -> some View {
        let id = torrent.torrentID as String
        let status = viewModel.watchStatus(
            torrentID: id,
            fileIndex: 0,
            totalBytes: torrent.totalBytes
        )
        switch status {
        case .unwatched:
            Button("Mark as watched") {
                Task { await viewModel.markWatched(torrentID: id, fileIndex: 0) }
            }
        case .inProgress:
            Button("Mark as watched") {
                Task { await viewModel.markWatched(torrentID: id, fileIndex: 0) }
            }
            Button("Mark as unwatched") {
                Task { await viewModel.markUnwatched(torrentID: id, fileIndex: 0) }
            }
        case .watched:
            Button("Mark as unwatched") {
                Task { await viewModel.markUnwatched(torrentID: id, fileIndex: 0) }
            }
        case .reWatching:
            Button("Mark as watched") {
                Task { await viewModel.markWatched(torrentID: id, fileIndex: 0) }
            }
            Button("Mark as unwatched") {
                Task { await viewModel.markUnwatched(torrentID: id, fileIndex: 0) }
            }
        }
    }

    /// Calls `openStream` on the engine and, on success, presents the player sheet.
    private func openStream(torrentID: String, fileIndex: Int32) {
        Task {
            do {
                let descriptor = try await viewModel.engineClient.openStream(
                    torrentID as NSString,
                    fileIndex: NSNumber(value: fileIndex)
                )
                activeStream = ActiveStream(descriptor: descriptor)
            } catch {
                viewModel.loadError = "Could not open stream: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - ActiveStream

/// Stable `Identifiable` wrapper for `StreamDescriptorDTO` — required for
/// `.sheet(item:)` which needs `Identifiable` conformance.
struct ActiveStream: Identifiable {
    let id = UUID()
    let descriptor: StreamDescriptorDTO
}

// MARK: - FileSheetState

private struct FileSheetState: Identifiable {
    let id = UUID()
    let torrentID: String
    let torrentName: String
    let files: [TorrentFileDTO]
}

// MARK: - TorrentRow

private struct TorrentRow: View {
    let torrent: TorrentSummaryDTO
    /// Watch status of file index 0 for this torrent. Drives the badge.
    let watchStatus: WatchStatus
    /// Favourite state of file index 0 for this torrent (#36).
    let isFavourite: Bool
    /// Tapped when the user clicks the heart icon.
    let onToggleFavourite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(torrent.name as String)
                    .brandBodyRegular()
                    .foregroundStyle(BrandColors.cocoa)
                    .lineLimit(1)
                if let badge = watchBadge {
                    Text(badge)
                        .brandCaption()
                        .foregroundStyle(BrandColors.cocoaSoft)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BrandColors.cocoaFaint)
                        .clipShape(Capsule())
                }
                Spacer(minLength: 4)
                Button(action: onToggleFavourite) {
                    Image(systemName: isFavourite ? "heart.fill" : "heart")
                        .foregroundStyle(
                            isFavourite ? BrandColors.butter : BrandColors.cocoaSoft
                        )
                }
                .buttonStyle(.plain)
                .help(isFavourite ? "Remove from favourites" : "Add to favourites")
                .accessibilityLabel(isFavourite ? "Favourited" : "Not favourited")
            }

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
                    .brandCaptionMonospacedNumeric()
                    .foregroundStyle(BrandColors.cocoaSoft)
                if torrent.downRateBytesPerSec > 0 {
                    Text("·")
                        .brandCaption()
                    Text(formattedDownRate)
                        .brandCaptionMonospacedNumeric()
                        .foregroundStyle(BrandColors.cocoaSoft)
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// Calm, factual badge per `06-brand.md § Voice`. Nil for unwatched/in-progress
    /// because the existing download progress already speaks for itself.
    private var watchBadge: String? {
        switch watchStatus {
        case .unwatched, .inProgress:
            return nil
        case .watched:
            return "Watched"
        case .reWatching(let p, let t, _):
            guard t > 0 else { return "Re-watching" }
            let pct = Int((Double(p) / Double(t)) * 100)
            return "Re-watching · \(pct)%"
        }
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

// #37 — watch state badges visible

#Preview("Library — watch state, light") {
    LibraryView(viewModel: .previewWithWatchState)
        .preferredColorScheme(.light)
        .frame(width: 480, height: 400)
}

#Preview("Library — watch state, dark") {
    LibraryView(viewModel: .previewWithWatchState)
        .preferredColorScheme(.dark)
        .frame(width: 480, height: 400)
}

// #35 — Continue watching row visible

#Preview("Library — continue watching, light") {
    LibraryView(viewModel: .previewWithContinueWatching)
        .preferredColorScheme(.light)
        .frame(width: 800, height: 500)
}

#Preview("Library — continue watching, dark") {
    LibraryView(viewModel: .previewWithContinueWatching)
        .preferredColorScheme(.dark)
        .frame(width: 800, height: 500)
}

// #36 — Favourites toggle visible

#Preview("Library — favourites, light") {
    LibraryView(viewModel: .previewWithFavourites)
        .preferredColorScheme(.light)
        .frame(width: 800, height: 500)
}

#Preview("Library — favourites, dark") {
    LibraryView(viewModel: .previewWithFavourites)
        .preferredColorScheme(.dark)
        .frame(width: 800, height: 500)
}
