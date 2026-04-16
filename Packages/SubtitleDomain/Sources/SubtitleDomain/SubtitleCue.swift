import CoreMedia
import Foundation

/// A single timed subtitle cue. Immutable; parsed once at ingestion.
/// See `docs/design/subtitle-foundation.md` § Type sketch.
public struct SubtitleCue: Equatable, Sendable {
    /// 1-based index per SRT spec. Used only for diagnostics — do not rely
    /// on this for ordering or lookup.
    public let index: Int
    public let startTime: CMTime
    public let endTime: CMTime
    /// Plain text. Light tag stripping (`<i>`, `<b>`, `<u>`) and entity
    /// decoding (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`) are applied
    /// by the parser.
    public let text: String

    public init(index: Int, startTime: CMTime, endTime: CMTime, text: String) {
        self.index = index
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
    }
}
