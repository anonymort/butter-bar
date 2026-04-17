import SubtitleDomain
import SwiftUI

// MARK: - SubtitleErrorBanner

/// Single-line error banner rendered on the HUD glass surface.
///
/// Auto-dismisses after 6 seconds. Dismissable by tap.
/// One banner at a time — new errors replace the existing one.
/// Voice per `06-brand.md` § Voice: calm, no exclamation marks.
///
/// Copy (design doc D9):
///   .decoding          → "Couldn't read <filename>. The file may be damaged."
///   .fileUnavailable   → "Couldn't open that subtitle file."
///   .unsupportedFormat → "That subtitle format isn't supported."
///   .systemTrackFailed → "Couldn't enable that subtitle track."
struct SubtitleErrorBanner: View {

    @ObservedObject var controller: SubtitleController

    var body: some View {
        if let error = controller.activeError {
            HStack(spacing: 8) {
                Text(copy(for: error))
                    .brandCaption()
                    .foregroundStyle(BrandColors.cocoa)
                    .lineLimit(1)

                Spacer()

                Button {
                    controller.activeError = nil
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(BrandColors.cocoaSoft)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 16)
            // Auto-dismiss after 6 seconds. Task is re-created whenever the
            // error identity changes (new error replaces old timer).
            .task(id: error) {
                try? await Task.sleep(for: .seconds(6))
                // Only clear if this error is still the active one.
                if controller.activeError == error {
                    controller.activeError = nil
                }
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.25)))
        }
    }

    // MARK: - Copy

    private func copy(for error: SubtitleLoadError) -> String {
        switch error {
        case .decoding(let reason):
            // Extract filename from reason if present, else use generic copy.
            let filename = extractFilename(from: reason)
            if let filename {
                return "Couldn't read \(filename). The file may be damaged."
            } else {
                return "Couldn't read that subtitle file. The file may be damaged."
            }
        case .fileUnavailable:
            return "Couldn't open that subtitle file."
        case .unsupportedFormat:
            return "That subtitle format isn't supported."
        case .systemTrackFailed:
            return "Couldn't enable that subtitle track."
        }
    }

    /// Attempts to extract a bare filename from a diagnostic reason string.
    /// Returns `nil` if the reason doesn't look like it contains a filename.
    private func extractFilename(from reason: String) -> String? {
        // Heuristic: last path-like token with an extension.
        let tokens = reason.split(separator: " ")
        return tokens.compactMap { token -> String? in
            let s = String(token)
            return s.contains(".") ? s : nil
        }.last
    }
}
