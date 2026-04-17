import Foundation

// MARK: - SubtitlePreferenceStore

/// Thin `UserDefaults` wrapper for the subtitle language preference.
///
/// Values:
///   - A BCP-47 string (e.g. `"en"`, `"pt-BR"`) — preferred language.
///   - `"off"` — user has explicitly disabled subtitles.
///   - `nil` (key absent) — no preference set yet.
///
/// All accesses run on the main actor so callers in `SubtitleController`
/// don't need to hop.
@MainActor
final class SubtitlePreferenceStore {

    static let key = "subtitles.preferredLanguage"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns the stored preference, or `nil` if none has been set.
    func load() -> String? {
        defaults.string(forKey: SubtitlePreferenceStore.key)
    }

    /// Persists a BCP-47 language string or `"off"`.
    /// Passing `nil` removes the key (no preference).
    func save(_ language: String?) {
        if let language {
            defaults.set(language, forKey: SubtitlePreferenceStore.key)
        } else {
            defaults.removeObject(forKey: SubtitlePreferenceStore.key)
        }
    }

    /// Removes the preference key — equivalent to `save(nil)`.
    func clear() {
        defaults.removeObject(forKey: SubtitlePreferenceStore.key)
    }
}
