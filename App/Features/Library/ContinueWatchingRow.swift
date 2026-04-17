import SwiftUI
import EngineInterface
import MetadataDomain

/// "Continue watching" row in the library (#35, enriched by #17). Horizontal
/// scroll of poster cards; each card represents one `ContinueWatchingItem`.
/// Tapping a card opens the player via the supplied `onOpen` closure — the
/// existing engine `StreamDescriptorDTO.resumeByteOffset` (shipped under
/// T-CACHE-RESUME) handles the AVPlayer seek.
///
/// Brand compliance per `06-brand.md`:
/// - No `.glassEffect` — cards sit in the page-flow surface, not floating chrome.
/// - Brand tokens only (`surfaceBase`, `cocoa`, `cocoaSoft`, `cocoaFaint`,
///   `creamRaised`, `butter`, `tierMarginal`).
/// - Progress bar uses `tierMarginal` per § Tier colours — calm and warm.
/// - Image placeholder is the brand-tokenized soft butter rounded rect.
/// - Episode designators use monospaced numerals per § Typography.
struct ContinueWatchingRow: View {
    let items: [ContinueWatchingItem]
    /// Optional metadata provider for poster URL resolution. Tests and
    /// snapshot factories may pass `nil`; in that case posters fall back
    /// to the placeholder. Production code injects the same provider used
    /// by `LibraryMetadataResolver`.
    let imageURLBuilder: ((String) -> URL)?
    /// Called when the user taps a card. v1 always opens file index 0 — the
    /// item carries `fileIndex` for forward-compat.
    let onOpen: (ContinueWatchingItem) -> Void

    init(items: [ContinueWatchingItem],
         imageURLBuilder: ((String) -> URL)? = nil,
         onOpen: @escaping (ContinueWatchingItem) -> Void) {
        self.items = items
        self.imageURLBuilder = imageURLBuilder
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue watching")
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoa)
                .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        ContinueWatchingCard(
                            item: item,
                            posterURL: posterURL(for: item)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen(item) }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.25), value: items.count)
    }

    private func posterURL(for item: ContinueWatchingItem) -> URL? {
        guard let path = item.posterPath, let builder = imageURLBuilder else {
            return nil
        }
        return builder(path)
    }
}

// MARK: - ContinueWatchingCard

private struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem
    let posterURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PosterView(url: posterURL)
                .frame(width: 156, height: 234)  // 2:3 portrait poster

            Text(item.displayTitle)
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoa)
                .lineLimit(2)
                .frame(width: 156, alignment: .leading)

            if let designator = item.episodeDesignator {
                Text(designator)
                    .brandCaptionMonospacedNumeric()
                    .foregroundStyle(BrandColors.cocoaSoft)
            } else {
                Text(label)
                    .brandCaption()
                    .foregroundStyle(BrandColors.cocoaSoft)
            }

            ProgressBar(fraction: item.progressFraction)
                .frame(width: 156, height: 3)
        }
    }

    private var label: String {
        item.isReWatching ? "Re-watching" : "Continue"
    }
}

// MARK: - PosterView

/// Brand-tokenized poster slot. Renders the AsyncImage when a URL is
/// supplied, otherwise the soft butter placeholder rect. The placeholder
/// is the same shape callers see during fetch, so empty states and loading
/// states share their visual rhythm.
private struct PosterView: View {
    let url: URL?

    var body: some View {
        ZStack {
            placeholder
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty, .failure:
                        // Empty / failed → keep the placeholder visible.
                        EmptyView()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .transition(.opacity)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }

    /// Soft butter rounded rect — brand placeholder per #11. Lives in this
    /// file (rather than ImageCache) because placeholder rendering is a UI
    /// concern; the cache layer only speaks bytes.
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(BrandColors.creamRaised)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(BrandColors.cocoaFaint.opacity(0.4), lineWidth: 1)
            }
    }
}

// MARK: - ProgressBar

/// Slim, brand-compliant progress bar. Uses `tierMarginal` for fill on a
/// `cocoaFaint` track per `06-brand.md § Tier colours` and AC ("calm and
/// warm, not safety-yellow").
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BrandColors.cocoaFaint)
                Capsule()
                    .fill(BrandColors.tierMarginal)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
    }
}

// MARK: - Previews

#Preview("Continue watching — light") {
    ContinueWatchingRow(
        items: ContinueWatchingItem.samples,
        onOpen: { _ in }
    )
    .frame(width: 800, height: 320)
    .background(BrandColors.surfaceBase)
    .preferredColorScheme(.light)
}

#Preview("Continue watching — dark") {
    ContinueWatchingRow(
        items: ContinueWatchingItem.samples,
        onOpen: { _ in }
    )
    .frame(width: 800, height: 320)
    .background(BrandColors.surfaceBase)
    .preferredColorScheme(.dark)
}

// MARK: - Preview samples

extension ContinueWatchingItem {
    static var samples: [ContinueWatchingItem] {
        [
            ContinueWatchingItem(
                torrent: TorrentSummaryDTO(
                    torrentID: "abc123",
                    name: "Cosmos: A Personal Voyage (1980)",
                    totalBytes: 8_589_934_592,
                    progressQ16: 65_536,
                    state: "seeding",
                    peerCount: 14,
                    downRateBytesPerSec: 0,
                    upRateBytesPerSec: 0,
                    errorMessage: nil
                ),
                fileIndex: 0,
                progressBytes: 3_006_477_107,
                totalBytes: 8_589_934_592,
                lastPlayedAtMillis: 1_700_000_000_000,
                isReWatching: true
            ),
            ContinueWatchingItem(
                torrent: TorrentSummaryDTO(
                    torrentID: "xyz789",
                    name: "Sunrise: A Song of Two Humans (1927)",
                    totalBytes: 2_147_483_648,
                    progressQ16: 65_536,
                    state: "seeding",
                    peerCount: 3,
                    downRateBytesPerSec: 0,
                    upRateBytesPerSec: 0,
                    errorMessage: nil
                ),
                fileIndex: 0,
                progressBytes: 1_073_741_824,
                totalBytes: 2_147_483_648,
                lastPlayedAtMillis: 1_700_000_500_000,
                isReWatching: false,
                episodeDesignator: "S01E04"
            ),
        ]
    }
}
