import Foundation

/// Surfaced via the fallback banner (#32) when ingestion or activation
/// fails. Each case carries a short reason string suitable for diagnostic
/// logging — user-facing copy lives in `SubtitleErrorBanner` (#32) and
/// follows the voice rules in `06-brand.md` § Voice.
public enum SubtitleLoadError: Error, Equatable, Sendable {
    /// File couldn't be read (missing, permissions, non-file URL).
    case fileUnavailable(reason: String)
    /// Bytes couldn't be decoded to text, or the parser couldn't recover
    /// any valid cues.
    case decoding(reason: String)
    /// File extension or container format is not supported in v1.
    case unsupportedFormat(reason: String)
    /// AVKit embedded track activation failed at runtime.
    case systemTrackFailed(reason: String)
}
