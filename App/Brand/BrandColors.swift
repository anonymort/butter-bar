// BrandColors — all semantic colour tokens from 06-brand.md.
// Token → hex mapping lives here; UI code references tokens only.
import SwiftUI

enum BrandColors {

    // MARK: - Core palette

    /// Primary brand colour. Logo, healthy tier accent, primary buttons, glass tint.
    static let butter     = Color(light: "#F5C84B", dark: "#E5B83B")
    /// Hover/pressed state of `butter`. Carved play symbol in the logo.
    static let butterDeep = Color(light: "#C9971F", dark: "#B8861A")

    /// Surface background. Warm dark in dark mode — not pure black.
    static let cream      = Color(light: "#FAF6EC", dark: "#2A2620")
    /// Cards, sheets, raised surfaces under glass.
    static let creamRaised = Color(light: "#FFFDF5", dark: "#332E26")

    /// Primary text. Warm dark / warm off-white — not pure black or white.
    static let cocoa      = Color(light: "#2A1F12", dark: "#F1ECE0")
    /// Secondary text, captions, metadata.
    static let cocoaSoft  = Color(light: "#5A4A35", dark: "#C2B8A5")
    /// Tertiary text, disabled states, dividers.
    static let cocoaFaint = Color(light: "#9C8E78", dark: "#7A6F5C")

    // MARK: - Tier colours (StreamHealth)
    // Mapping is fixed per 06-brand.md § Tier colours. Do not substitute.

    /// Healthy tier — muted olive-green (not system green).
    static let tierHealthy  = Color(light: "#7BA05B", dark: "#8FB36F")
    /// Marginal tier — same family as butter, distinguishable.
    static let tierMarginal = Color(light: "#E5B83B", dark: "#F5C84B")
    /// Starving tier — warm terracotta (not system red — this is a recoverable state).
    static let tierStarving = Color(light: "#C25A3D", dark: "#D46B4E")

    // MARK: - Surface tokens

    /// Window background.
    static let surfaceBase    = cream
    /// Cards, sheets, content panels under glass chrome.
    static let surfaceRaised  = creamRaised
    /// Modal scrims, popovers without glass treatment.
    static let surfaceOverlay: Color = cocoa.opacity(0.4)
}
