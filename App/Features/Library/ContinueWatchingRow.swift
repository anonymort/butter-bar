import SwiftUI
import EngineInterface

/// "Continue watching" row in the library (#35). Horizontal scroll of cards;
/// each card represents one `ContinueWatchingItem`. Tapping a card opens the
/// player via the supplied `onOpen` closure — the existing engine
/// `StreamDescriptorDTO.resumeByteOffset` (shipped under T-CACHE-RESUME)
/// handles the AVPlayer seek, so we don't need to pass byte data along.
///
/// Brand compliance per `06-brand.md`:
/// - No `.glassEffect` — cards sit in the page-flow surface, not floating chrome.
/// - Brand tokens only (`surfaceBase`, `cocoa`, `cocoaSoft`, `cocoaFaint`, `butter`).
/// - `.easeInOut` motion tied to `items.count` for the fade-in on first populate.
struct ContinueWatchingRow: View {
    let items: [ContinueWatchingItem]
    /// Called when the user taps a card. v1 always opens file index 0 — the
    /// item carries `fileIndex` for forward-compat.
    let onOpen: (ContinueWatchingItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue watching")
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoa)
                .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        ContinueWatchingCard(item: item)
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
}

// MARK: - ContinueWatchingCard

private struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.torrent.name as String)
                .brandBodyRegular()
                .foregroundStyle(BrandColors.cocoa)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            ProgressBar(fraction: item.progressFraction)
                .frame(height: 3)

            HStack(spacing: 6) {
                Text(label)
                    .brandCaption()
                    .foregroundStyle(BrandColors.cocoaSoft)
                Text("·")
                    .brandCaption()
                Text("\(Int(item.progressFraction * 100))%")
                    .brandCaptionMonospacedNumeric()
                    .foregroundStyle(BrandColors.cocoaSoft)
            }
        }
        .padding(12)
        .frame(width: 220)
        .background(BrandColors.creamRaised)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var label: String {
        item.isReWatching ? "Re-watching" : "Continue"
    }
}

// MARK: - ProgressBar

/// Slim, brand-compliant progress bar. Uses `butter` for fill on a
/// `cocoaFaint` track — both brand tokens. No system tints.
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BrandColors.cocoaFaint)
                Capsule()
                    .fill(BrandColors.butter)
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
    .frame(width: 800, height: 120)
    .background(BrandColors.surfaceBase)
    .preferredColorScheme(.light)
}

#Preview("Continue watching — dark") {
    ContinueWatchingRow(
        items: ContinueWatchingItem.samples,
        onOpen: { _ in }
    )
    .frame(width: 800, height: 120)
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
                isReWatching: false
            ),
        ]
    }
}
