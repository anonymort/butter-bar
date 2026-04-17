import SwiftUI

/// Data driving the resume prompt overlay. Carries an optional displayable
/// resume time — `nil` when the AVPlayer asset duration is not yet known
/// when the prompt fires (per AC: never block on duration).
struct ResumePromptOffer: Equatable {
    /// Displayable resume time, e.g. "23m" or "1h 12m". `nil` if duration
    /// is not yet known.
    let resumeTimeLabel: String?
}

/// Floating glass panel offering "Continue from {time}" / "Start from the
/// beginning". Brand-compliant per `06-brand.md § Window chrome` and
/// `§ Voice` — calm copy, monospaced numerals on the time, no system colours.
///
/// The view is purely presentational: it owns no state. Dismissal is
/// surfaced through the `onDismiss` callback (Esc key, click-outside, or an
/// explicit dismiss control). Hosted by `PlayerView` and rendered when
/// `viewModel.resumePromptOffer != nil`.
struct ResumePromptView: View {

    let offer: ResumePromptOffer
    let onContinue: () -> Void
    let onStartOver: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Click-outside dismissal scrim. Solid cocoa at low opacity —
            // not a system material — so it stays inside the brand palette.
            BrandColors.cocoa
                .opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            panel
        }
        .onExitCommand { onDismiss() }
    }

    // MARK: - Panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick up where you left off?")
                .brandBodyEmphasis()
                .foregroundStyle(BrandColors.cocoa)

            Text("You stopped partway through this file.")
                .brandCaption()

            VStack(spacing: 8) {
                Button(action: onContinue) {
                    Text(continueLabel)
                        .foregroundStyle(BrandColors.cocoa)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(BrandColors.butter)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .keyboardShortcut(.defaultAction)

                Button(action: onStartOver) {
                    Text("Start from the beginning")
                        .brandBodyRegular()
                        .foregroundStyle(BrandColors.cocoa)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .background(BrandColors.creamRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(BrandColors.creamRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: BrandColors.cocoa.opacity(0.35),
                radius: 18, x: 0, y: 8)
    }

    // MARK: - Copy

    /// Continue label. When the resume time is unknown (asset duration not
    /// yet ready) we drop the time stamp rather than block — per AC.
    /// Uses `AttributedString` so the time segment carries the monospaced-digit
    /// font (per `06-brand.md § Voice`: "monospaced numerals for time") while
    /// the surrounding copy stays in the body-emphasis face.
    private var continueLabel: AttributedString {
        guard let time = offer.resumeTimeLabel else {
            var plain = AttributedString("Continue")
            plain.font = BrandTypography.bodyEmphasis
            return plain
        }
        var prefix = AttributedString("Continue from ")
        prefix.font = BrandTypography.bodyEmphasis
        var timePart = AttributedString(time)
        timePart.font = BrandTypography.monospacedNumeric
        prefix.append(timePart)
        return prefix
    }
}
