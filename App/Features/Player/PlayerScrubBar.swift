import SwiftUI

// MARK: - PlayerScrubBar
//
// Bottom scrub control: current-time label (left), scrub track, remaining-time
// label (right). All time displays are monospaced per `06-brand.md § Typography`
// so values don't jitter as they tick.
//
// Scrub interaction is invisible to `PlayerStateMachine` (per issue #24 AC:
// "Scrub bar drag → AVPlayer seek (no `PlayerEvent`)"). The view emits seek
// requests via the `onScrub` closure; the caller forwards to `AVPlayer.seek`.
//
// Time values are bound through `currentSeconds` and `durationSeconds`. When
// `durationSeconds <= 0` (asset duration not yet known), the track renders
// inert and labels collapse to placeholders.

struct PlayerScrubBar: View {

    let currentSeconds: Double
    let durationSeconds: Double
    let isEnabled: Bool
    /// Called as the user drags. Receives target seconds.
    let onScrub: (Double) -> Void

    @State private var dragSeconds: Double?

    var body: some View {
        HStack(spacing: 12) {
            timeLabel(displayedCurrent)
                .frame(minWidth: 56, alignment: .leading)

            track

            timeLabel(displayedRemaining)
                .frame(minWidth: 56, alignment: .trailing)
        }
    }

    // MARK: - Track

    private var track: some View {
        GeometryReader { geo in
            let progress = clampedProgress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BrandColors.cocoaFaint.opacity(0.6))
                    .frame(height: 3)

                Capsule()
                    .fill(BrandColors.butter)
                    .frame(width: max(0, geo.size.width * progress), height: 3)

                if durationSeconds > 0 {
                    Circle()
                        .fill(BrandColors.butter)
                        .frame(width: 12, height: 12)
                        .offset(x: max(0, geo.size.width * progress) - 6)
                        .opacity(isEnabled ? 1 : 0.6)
                }
            }
            .frame(height: 12)
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, durationSeconds > 0 else { return }
                        let ratio = max(0, min(1, value.location.x / max(1, geo.size.width)))
                        dragSeconds = ratio * durationSeconds
                    }
                    .onEnded { value in
                        guard isEnabled, durationSeconds > 0 else { return }
                        let ratio = max(0, min(1, value.location.x / max(1, geo.size.width)))
                        let target = ratio * durationSeconds
                        dragSeconds = nil
                        onScrub(target)
                    }
            )
            .animation(.easeInOut(duration: 0.2), value: progress)
        }
        .frame(height: 16)
    }

    // MARK: - Labels

    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .brandCaptionMonospacedNumeric()
            .foregroundStyle(BrandColors.cocoa)
    }

    // MARK: - Derived values

    /// Use the in-flight drag value during a scrub for snappy feedback;
    /// otherwise the player's authoritative `currentSeconds`.
    private var displayedSeconds: Double { dragSeconds ?? currentSeconds }

    private var clampedProgress: Double {
        guard durationSeconds > 0 else { return 0 }
        return max(0, min(1, displayedSeconds / durationSeconds))
    }

    private var displayedCurrent: String {
        durationSeconds > 0 ? Self.format(seconds: displayedSeconds) : "—:—"
    }

    private var displayedRemaining: String {
        guard durationSeconds > 0 else { return "—:—" }
        let remaining = max(0, durationSeconds - displayedSeconds)
        return "−" + Self.format(seconds: remaining)
    }

    /// `m:ss` under one hour, `h:mm:ss` otherwise. Stable width because of
    /// `.monospacedDigit()` on the caption font.
    static func format(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
