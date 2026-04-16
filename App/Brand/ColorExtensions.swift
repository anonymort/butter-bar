import SwiftUI
import AppKit

extension Color {
    /// Creates a `Color` that resolves to different values in light and dark appearances.
    /// `light` and `dark` are 6-digit hex strings with optional leading `#`, e.g. `"#F5C84B"`.
    init(light lightHex: String, dark darkHex: String) {
        self.init(NSColor(light: lightHex, dark: darkHex))
    }
}

private extension NSColor {
    convenience init(light lightHex: String, dark darkHex: String) {
        self.init(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua:
                return NSColor(hex: darkHex)
            default:
                return NSColor(hex: lightHex)
            }
        }
    }

    convenience init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt64(cleaned, radix: 16) ?? 0
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(sRGBRed: r, green: g, blue: b, alpha: 1.0)
    }
}
