import Foundation

/// Picks a track from a list given a BCP-47 preference string. Pure
/// function — no clocks, no I/O, no globals. See
/// `docs/design/subtitle-foundation.md` § D8 and § Resolution matrix.
///
/// The resolver **partitions internally** by source type (embedded vs
/// sidecar) and always tries embedded first, regardless of caller input
/// order. Callers pass the tracks they have; they do not need to sort.
public enum LanguagePreferenceResolver {

    public static func pick(from tracks: [SubtitleTrack],
                            preferred: String?) -> SubtitleTrack? {
        guard let preferred else { return nil }
        if preferred.caseInsensitiveCompare("off") == .orderedSame {
            return nil
        }

        var embedded: [SubtitleTrack] = []
        var sidecars: [SubtitleTrack] = []
        for track in tracks {
            switch track.source {
            case .embedded:
                embedded.append(track)
            case .sidecar:
                sidecars.append(track)
            }
        }

        if let hit = firstMatch(in: embedded, preferred: preferred) {
            return hit
        }
        return firstMatch(in: sidecars, preferred: preferred)
    }

    // MARK: - Internals

    private static func firstMatch(in tracks: [SubtitleTrack],
                                   preferred: String) -> SubtitleTrack? {
        let prefPrimary = primarySubtag(of: preferred)
        return tracks.first { track in
            guard let lang = track.language else { return false }
            return primarySubtag(of: lang).caseInsensitiveCompare(prefPrimary) == .orderedSame
        }
    }

    /// Returns the primary (first) subtag of a BCP-47 tag, preserving the
    /// caller's casing. `"en-US"` → `"en"`, `"pt-BR"` → `"pt"`,
    /// `"zh-Hans"` → `"zh"`. Comparisons are done case-insensitively at
    /// the call site.
    internal static func primarySubtag(of tag: String) -> String {
        if let dash = tag.firstIndex(of: "-") {
            return String(tag[..<dash])
        }
        return tag
    }
}
