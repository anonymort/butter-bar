import Foundation

/// Where a subtitle track comes from. Cues live in the `.sidecar` payload
/// because they're inseparable from sidecar tracks and absent from
/// embedded ones — see `docs/design/subtitle-foundation.md` § D3.
public enum SubtitleSource: Equatable, Sendable {
    /// AVKit-surfaced legible track. `identifier` is an opaque handle the
    /// app layer maps back to `AVMediaSelectionOption` at selection time.
    case embedded(identifier: String)
    /// User-provided sidecar file, parsed into cues at ingestion.
    case sidecar(url: URL, format: SubtitleFormat, cues: [SubtitleCue])
}
