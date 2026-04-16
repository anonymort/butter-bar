import SwiftUI
import EngineInterface

// MARK: - StreamHealthHUD

/// Floating overlay displaying stream health tier, buffer readahead, download
/// rate, and peer count. Appears on mouse movement; auto-hides after 3 seconds.
///
/// Design rules (06-brand.md):
/// - Tier colour is always paired with a text label (colour is never the sole signal).
/// - HUD surface uses `.glassEffect(.regular.interactive())` on macOS 26+.
/// - All animations use `.easeInOut` only — no spring physics.
/// - Tier colour strip: 4 pt left-edge accent inside the HUD row.
struct StreamHealthHUD: View {

    let health: StreamHealthDTO

    var body: some View {
        hudContent
            .hudSurface()
    }

    // MARK: - HUD content

    private var hudContent: some View {
        HStack(spacing: 16) {
            tierStrip
            statsRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Tier strip

    /// 4 pt colour strip at the left edge, per 06-brand.md § HUD.
    private var tierStrip: some View {
        Rectangle()
            .fill(tierColour)
            .frame(width: 4)
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.4), value: health.tier as String)
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 16) {
            tierLabel
            bufferLabel
            rateLabel
            peerLabel
        }
    }

    /// Tier text label — required so colour is not the sole signal (accessibility).
    private var tierLabel: some View {
        Text(tierDisplayName)
            .brandBodyEmphasis()
            .foregroundStyle(tierColour)
            .animation(.easeInOut(duration: 0.4), value: health.tier as String)
    }

    /// "12 s ready" — buffer-ahead value animates continuously across 800 ms.
    /// Below the text, a 2 pt fill bar represents buffer fill proportional to
    /// `bufferFillRatio` (capped at 60 s ceiling; v1 default).
    private var bufferLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(formattedBuffer)
                .brandCaptionMonospacedNumeric()
                .foregroundStyle(BrandColors.cocoaSoft)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.8), value: health.secondsBufferedAhead)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(BrandColors.cocoaFaint)
                    Rectangle()
                        .fill(BrandColors.butter)
                        .frame(width: geo.size.width * bufferFillRatio)
                }
            }
            .frame(height: 2)
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.8), value: bufferFillRatio)
        }
    }

    /// Fill ratio for the buffer indicator, capped at 60 s (v1 default ceiling).
    private var bufferFillRatio: Double {
        min(health.secondsBufferedAhead, 60) / 60
    }

    /// "4.2 MB/s"
    private var rateLabel: some View {
        Text(formattedRate)
            .brandCaptionMonospacedNumeric()
            .foregroundStyle(BrandColors.cocoaSoft)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.25), value: health.downloadRateBytesPerSec)
    }

    /// "4 peers" / "1 peer"
    private var peerLabel: some View {
        Text(formattedPeers)
            .brandCaptionMonospacedNumeric()
            .foregroundStyle(BrandColors.cocoaSoft)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.25), value: health.peerCount)
    }

    // MARK: - Formatters

    private var tierColour: Color {
        switch health.tier as String {
        case "healthy":  return BrandColors.tierHealthy
        case "marginal": return BrandColors.tierMarginal
        case "starving": return BrandColors.tierStarving
        default:         return BrandColors.tierStarving
        }
    }

    /// British English tier names per 06-brand.md § Voice.
    private var tierDisplayName: String {
        switch health.tier as String {
        case "healthy":  return "Healthy"
        case "marginal": return "Marginal"
        case "starving": return "Starving"
        default:         return "Unknown"
        }
    }

    private var formattedBuffer: String {
        let seconds = Int(health.secondsBufferedAhead)
        return "\(seconds) s ready"
    }

    private var formattedRate: String {
        let bytes = health.downloadRateBytesPerSec
        if bytes >= 1_000_000 {
            let mb = Double(bytes) / 1_000_000.0
            return String(format: "%.1f MB/s", mb)
        } else if bytes >= 1_000 {
            let kb = Double(bytes) / 1_000.0
            return String(format: "%.0f KB/s", kb)
        } else {
            return "\(bytes) B/s"
        }
    }

    private var formattedPeers: String {
        let count = Int(health.peerCount)
        return count == 1 ? "1 peer" : "\(count) peers"
    }
}

// MARK: - HUD surface modifier

private extension View {
    func hudSurface() -> some View {
        // Explicit butter tint keeps the glass surface warm rather than
        // inheriting generic Apple-default chroma (spec 06 § Colour palette).
        self
            .tint(BrandColors.butter)
            .glassEffect(.regular.interactive())
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Previews

#Preview("HUD — healthy, dark") {
    StreamHealthHUD(health: StreamHealthDTO(
        streamID: "preview",
        secondsBufferedAhead: 42.0,
        downloadRateBytesPerSec: 4_300_000,
        requiredBitrateBytesPerSec: nil,
        peerCount: 8,
        outstandingCriticalPieces: 0,
        recentStallCount: 0,
        tier: "healthy"
    ))
    .preferredColorScheme(.dark)
    .padding()
    .background(Color.black)
}

#Preview("HUD — marginal, dark") {
    StreamHealthHUD(health: StreamHealthDTO(
        streamID: "preview",
        secondsBufferedAhead: 14.0,
        downloadRateBytesPerSec: 1_100_000,
        requiredBitrateBytesPerSec: nil,
        peerCount: 3,
        outstandingCriticalPieces: 0,
        recentStallCount: 1,
        tier: "marginal"
    ))
    .preferredColorScheme(.dark)
    .padding()
    .background(Color.black)
}

#Preview("HUD — starving, dark") {
    StreamHealthHUD(health: StreamHealthDTO(
        streamID: "preview",
        secondsBufferedAhead: 4.0,
        downloadRateBytesPerSec: 200_000,
        requiredBitrateBytesPerSec: nil,
        peerCount: 1,
        outstandingCriticalPieces: 3,
        recentStallCount: 4,
        tier: "starving"
    ))
    .preferredColorScheme(.dark)
    .padding()
    .background(Color.black)
}
