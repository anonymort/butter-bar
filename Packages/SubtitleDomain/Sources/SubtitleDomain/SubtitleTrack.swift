import Foundation

/// Unified subtitle track — either an AVKit embedded track or a parsed
/// sidecar. UI (`SubtitleSelectionMenu`, #29) and the language resolver
/// (`LanguagePreferenceResolver`) range over `[SubtitleTrack]` uniformly.
public struct SubtitleTrack: Equatable, Identifiable, Sendable {
    /// Stable within a playback session — scope is "per stream open",
    /// not persistent across app launches.
    public let id: String
    public let source: SubtitleSource
    /// BCP-47 tag (e.g. `"en"`, `"pt-BR"`, `"zh-Hans"`). `nil` when the
    /// track carries no language metadata.
    public let language: String?
    /// Human-readable label for the UI. The ingestor and the AVKit
    /// mapping pick the right shape per source.
    public let label: String

    public init(id: String,
                source: SubtitleSource,
                language: String?,
                label: String) {
        self.id = id
        self.source = source
        self.language = language
        self.label = label
    }
}
