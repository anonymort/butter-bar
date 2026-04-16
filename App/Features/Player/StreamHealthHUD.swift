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
    private var bufferLabel: some View {
        Text(formattedBuffer)
            .brandCaptionMonospacedNumeric()
            .foregroundStyle(BrandColors.cocoaSoft)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: 0.8), value: health.secondsBufferedAhead)
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

/// Applies the correct floating glass surface to the HUD on macOS 26+,
/// with a `cocoa` 60% opacity fallback for pre-Tahoe SDK builds.
///
/// Concern: `.glassEffect(.regular.interactive())` is macOS 26+. The
/// fallback (`.ultraThinMaterial` + opaque tint) approximates the effect
/// but will not pick up tint from the video underneath. Since the v1
/// deployment target is macOS 26 (Xcode 26 SDK), the fallback path
/// should not ship, but is kept so the project builds cleanly if the
/// SDK is temporarily downgraded during development.
private extension View {
    @ViewBuilder
    func hudSurface() -> some View {
        if #available(macOS 26, *) {
            // Glass picks up tint from underlying video content, per spec 06.
            self
                .glassEffect(.regular.interactive())
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            // Pre-Tahoe fallback — does not reach production in v1.
            self
                .background(BrandColors.cocoa.opacity(0.6))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
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
