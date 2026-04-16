import Foundation

/// Subtitle container format. Used for diagnostics and ingestion branching.
///
/// v1 scope (per design doc § D2):
/// - Sidecar: `.srt` only. Other sidecar formats surface as
///   `SubtitleLoadError.unsupportedFormat`.
/// - Embedded: `.webVTT` / `.movText` / `.closedCaption` are exposed by
///   AVKit's `.legible` selection group; we do not distinguish them in
///   the UI.
public enum SubtitleFormat: String, Equatable, Sendable, CaseIterable {
    case srt
    case webVTT
    case movText
    case closedCaption
}
