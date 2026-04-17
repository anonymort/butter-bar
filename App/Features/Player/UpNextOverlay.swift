import SwiftUI

/// "Up next" surface (#21). Calm copy register per `06-brand.md § Voice` —
/// no breathless countdown phrasing, just the next title and the seconds
/// left before it auto-plays. Brand tokens only; no system colours.
///
/// The view is purely presentational. The `NextEpisodeCoordinator` owns
/// the offer + countdown state and the cancel / play-now callbacks.
struct UpNextOverlay: View {

    let offer: NextEpisodeOffer
    let secondsRemaining: Int
    let onPlayNow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        // Sit in the bottom-trailing corner so it never covers the closing
        // frames of the credits. The user can still see the asset playing
        // out underneath.
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                panel
                    .padding(24)
            }
        }
        .onExitCommand { onCancel() }
    }

    // MARK: - Panel

    private var panel: some View {
        HStack(alignment: .top, spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 6) {
                Text("Up next")
                    .brandCaption()
                    .textCase(.uppercase)
                    .tracking(0.6)

                Text(offer.next.name)
                    .brandBodyEmphasis()
                    .foregroundStyle(BrandColors.cocoa)
                    .lineLimit(2)

                Text(episodeNumberLabel)
                    .brandCaption()

                countdownLabel
                    .padding(.top, 4)

                buttons
                    .padding(.top, 8)
            }
            .frame(maxWidth: 220, alignment: .leading)
        }
        .padding(14)
        .background(BrandColors.creamRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: BrandColors.cocoa.opacity(0.35),
                radius: 16, x: 0, y: 6)
        .frame(width: 360)
    }

    // MARK: - Pieces

    private var artwork: some View {
        Group {
            if let url = offer.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        BrandColors.cocoa.opacity(0.15)
                    }
                }
            } else {
                BrandColors.cocoa.opacity(0.15)
            }
        }
        .frame(width: 100, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var episodeNumberLabel: String {
        // Concrete numbers per brand voice ("Numbers when we have them").
        // British "·" mid-dot separator matches existing HUD copy register.
        let s = offer.next.seasonNumber
        let e = offer.next.episodeNumber
        return "Season \(s) · Episode \(e)"
    }

    /// Calm countdown phrasing: "Plays in 7 s". Singular `1 s` keeps the
    /// monospaced cell width stable. No "Starting in 3… 2… 1…".
    private var countdownLabel: some View {
        HStack(spacing: 4) {
            Text("Plays in")
                .brandCaption()
            Text("\(max(secondsRemaining, 0)) s")
                .brandCaptionMonospacedNumeric()
                .foregroundStyle(BrandColors.cocoaSoft)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button(action: onCancel) {
                Text("Cancel")
                    .brandBodyRegular()
                    .foregroundStyle(BrandColors.cocoa)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(BrandColors.creamRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(BrandColors.cocoaFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Button(action: onPlayNow) {
                Text("Play now")
                    .brandBodyEmphasis()
                    .foregroundStyle(BrandColors.cocoa)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(BrandColors.butter)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .keyboardShortcut(.defaultAction)
        }
    }
}
