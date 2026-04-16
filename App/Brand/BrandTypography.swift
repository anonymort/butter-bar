// BrandTypography — font tokens from 06-brand.md.
// All View modifier extensions; apply via e.g. `.brandDisplay()`.
// Colour is applied separately via `.foregroundStyle(BrandColors.cocoa)` —
// typography tokens define font only.
import SwiftUI

enum BrandTypography {
    /// SF Pro Display, weight 600, tracking -0.02em (approx -0.8 pt at 40pt).
    /// Used for large headers and the wordmark.
    static let display: Font = .system(.largeTitle, design: .default, weight: .semibold)

    /// SF Pro Text, weight 400. Standard body and UI text.
    static let bodyRegular: Font = .system(.body, design: .default, weight: .regular)

    /// SF Pro Text, weight 500. Emphasis within body copy.
    static let bodyEmphasis: Font = .system(.body, design: .default, weight: .medium)

    /// SF Pro Text with monospaced digits. Prevents jitter on rates, durations, byte counts.
    static let monospacedNumeric: Font = Font.body.monospacedDigit()

    /// SF Pro Text 12pt, weight 400. Captions and metadata.
    /// Pair with `.foregroundStyle(BrandColors.cocoaSoft)`.
    static let caption: Font = .system(size: 12, weight: .regular, design: .default)
}

// MARK: - View modifiers

extension View {
    /// SF Pro Display semibold with negative tracking (-0.02em at 34pt = -0.68pt).
    func brandDisplay() -> some View {
        self.font(BrandTypography.display)
            .tracking(-0.68)
    }

    /// SF Pro Text regular body weight.
    func brandBodyRegular() -> some View {
        self.font(BrandTypography.bodyRegular)
    }

    /// SF Pro Text medium (emphasis) body weight.
    func brandBodyEmphasis() -> some View {
        self.font(BrandTypography.bodyEmphasis)
    }

    /// SF Pro Text monospaced-digit body. For rates, durations, byte counts.
    func brandMonospacedNumeric() -> some View {
        self.font(BrandTypography.monospacedNumeric)
    }

    /// SF Pro Text 12pt regular caption.
    /// Also applies `cocoaSoft` foreground colour — captions are always secondary.
    func brandCaption() -> some View {
        self.font(BrandTypography.caption)
            .foregroundStyle(BrandColors.cocoaSoft)
    }
}
