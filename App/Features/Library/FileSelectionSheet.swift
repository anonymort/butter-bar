import SwiftUI
import EngineInterface

// MARK: - FileSelectionSheet

/// Presented for multi-file torrents. Lists files; dismisses on selection.
struct FileSelectionSheet: View {

    let torrentName: String
    let files: [TorrentFileDTO]
    /// Called with the chosen file index when the user selects a file.
    let onSelect: (Int32) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .background(BrandColors.cocoaFaint)
            fileList
        }
        .frame(minWidth: 480, minHeight: 300)
        .background(BrandColors.surfaceRaised)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Select a file")
                .brandBodyEmphasis()
                .foregroundStyle(BrandColors.cocoa)
            Text(torrentName)
                .brandCaption()
                .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var fileList: some View {
        List(files, id: \.fileIndex) { file in
            FileRow(file: file) {
                onSelect(file.fileIndex)
                dismiss()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BrandColors.surfaceRaised)
        .animation(.easeInOut(duration: 0.25), value: files.count)
    }
}

// MARK: - FileRow

private struct FileRow: View {
    let file: TorrentFileDTO
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .brandBodyRegular()
                    .foregroundStyle(BrandColors.cocoa)
                    .lineLimit(2)
                Text(formattedSize)
                    .brandCaption()
            }
            Spacer()
            Button("Select") {
                onSelect()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(BrandColors.butter)
            .brandBodyRegular()
        }
        .padding(.vertical, 6)
        .listRowBackground(BrandColors.surfaceRaised)
        .listRowSeparatorTint(BrandColors.cocoaFaint)
    }

    // Use last path component for display; fall back to full path.
    private var displayName: String {
        let p = file.path as String
        return p.split(separator: "/").last.map(String.init) ?? p
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file)
    }
}

// MARK: - Previews

#Preview("File selection — light") {
    FileSelectionSheet(
        torrentName: "Cosmos: A Personal Voyage (1980)",
        files: [
            TorrentFileDTO(fileIndex: 0, path: "Cosmos/Episode01.mkv", sizeBytes: 1_200_000_000, mimeTypeHint: "video/x-matroska", isPlayableByAVFoundation: true),
            TorrentFileDTO(fileIndex: 1, path: "Cosmos/Episode02.mkv", sizeBytes: 1_100_000_000, mimeTypeHint: "video/x-matroska", isPlayableByAVFoundation: true),
            TorrentFileDTO(fileIndex: 2, path: "Cosmos/Subtitles.srt",  sizeBytes: 48_000,        mimeTypeHint: "text/plain",         isPlayableByAVFoundation: false),
        ],
        onSelect: { _ in }
    )
    .preferredColorScheme(.light)
}

#Preview("File selection — dark") {
    FileSelectionSheet(
        torrentName: "Cosmos: A Personal Voyage (1980)",
        files: [
            TorrentFileDTO(fileIndex: 0, path: "Cosmos/Episode01.mkv", sizeBytes: 1_200_000_000, mimeTypeHint: "video/x-matroska", isPlayableByAVFoundation: true),
            TorrentFileDTO(fileIndex: 1, path: "Cosmos/Episode02.mkv", sizeBytes: 1_100_000_000, mimeTypeHint: "video/x-matroska", isPlayableByAVFoundation: true),
        ],
        onSelect: { _ in }
    )
    .preferredColorScheme(.dark)
}
