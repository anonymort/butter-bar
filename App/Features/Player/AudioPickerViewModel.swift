import AVFoundation
import Combine
import Foundation
import PlayerDomain

// MARK: - AudioPickerViewModel
//
// Pure observable wrapping the audible `AVMediaSelectionGroup` for the current
// `AVPlayerItem` (issue #23). The picker UI binds to `tracks` and calls
// `select(_:)` on row tap. Audio changes are silent to `PlayerStateMachine`
// per AC — the picker observes `PlayerState` only to disable itself when the
// player is `.closed` or `.error(_)`.
//
// AVPlayerItem can't be cleanly constructed without a real asset, so the view
// model depends on a small `AudioMediaSelectionProviding` seam. Production
// wires it to `AVPlayerItem`; tests substitute a fake.

@MainActor
final class AudioPickerViewModel: ObservableObject {

    @Published private(set) var tracks: [AudioTrack] = []

    /// Picker is disabled in lifecycle terminal states. Observe but don't
    /// drive — picker never emits `PlayerEvent`s per AC.
    let isDisabled: Bool

    private let provider: AudioMediaSelectionProviding?

    init(provider: AudioMediaSelectionProviding?, state: PlayerState) {
        self.provider = provider
        self.isDisabled = Self.disabled(in: state)
        refreshTracks()
    }

    /// Apply the user's selection and refresh `tracks` so the current-flag is
    /// up to date. The view dismisses itself after calling this.
    func select(_ track: AudioTrack) {
        provider?.select(optionID: track.id)
        refreshTracks()
    }

    // MARK: - Private

    private func refreshTracks() {
        guard let provider else {
            tracks = []
            return
        }
        let options = provider.options
        // Single-track assets surface as an empty list per AC — the view then
        // renders the calm "Only one audio track available." copy. We do not
        // emit a single row because the user has nothing meaningful to pick.
        guard options.count > 1 else {
            tracks = []
            return
        }
        let currentID = provider.currentSelectionID
        tracks = options.map { option in
            AudioTrack(
                id: option.id,
                displayName: option.displayName,
                channelHint: option.channelHint,
                isCurrent: option.id == currentID
            )
        }
    }

    private static func disabled(in state: PlayerState) -> Bool {
        switch state {
        case .closed, .error:
            return true
        case .open, .playing, .paused, .buffering:
            return false
        }
    }
}

// MARK: - AudioTrack

/// One row in the audio picker. Stable across reorder; the view diffs by `id`.
struct AudioTrack: Identifiable, Equatable {
    let id: String
    let displayName: String
    /// Channel layout hint (e.g. "5.1", "Stereo") when derivable from
    /// `commonMetadata` or display name. `nil` when unknown — the row simply
    /// omits the hint pill rather than guessing.
    let channelHint: String?
    let isCurrent: Bool
}

// MARK: - AudioMediaSelectionProviding

/// Seam over `AVPlayerItem`'s audible media selection group. Production uses
/// `AVPlayerItemAudioProvider` (below); tests substitute a fake.
///
/// Main-actor isolated because the production implementation calls into
/// `AVPlayerItem` (which must be touched from the main actor under Swift 6
/// strict concurrency), and the view model itself is `@MainActor`.
@MainActor
protocol AudioMediaSelectionProviding: AnyObject {
    var options: [AudioMediaOption] { get }
    var currentSelectionID: String? { get }
    func select(optionID: String)
}

/// DTO surfaced by `AudioMediaSelectionProviding`. Decoupled from
/// `AVMediaSelectionOption` so the view model and tests don't carry an AVKit
/// dependency in their type signatures.
struct AudioMediaOption: Equatable {
    let id: String
    let displayName: String
    let channelHint: String?
}

// MARK: - AVPlayerItem adapter

/// Production adapter: reads the audible `AVMediaSelectionGroup` from an
/// `AVPlayerItem` and applies selection via `AVPlayerItem.select(_:in:)`.
@MainActor
final class AVPlayerItemAudioProvider: AudioMediaSelectionProviding {

    private let item: AVPlayerItem
    private let group: AVMediaSelectionGroup

    /// Returns `nil` if the asset has no audible selection group at all
    /// (e.g. before the asset's mediaSelectionGroup keys finish loading).
    /// Callers should reconstruct after `mediaSelectionGroup(for:)` becomes
    /// non-nil.
    init?(item: AVPlayerItem) {
        guard let group = item.asset.mediaSelectionGroup(
            forMediaCharacteristic: .audible
        ) else {
            return nil
        }
        self.item = item
        self.group = group
    }

    var options: [AudioMediaOption] {
        group.options.map { option in
            AudioMediaOption(
                id: Self.stableID(for: option),
                displayName: Self.label(for: option),
                channelHint: Self.channelHint(for: option)
            )
        }
    }

    var currentSelectionID: String? {
        guard let selected = item.currentMediaSelection.selectedMediaOption(
            in: group
        ) else { return nil }
        return Self.stableID(for: selected)
    }

    func select(optionID: String) {
        guard let option = group.options.first(where: {
            Self.stableID(for: $0) == optionID
        }) else { return }
        item.select(option, in: group)
    }

    // MARK: - Option projection

    /// Stable identifier per option. `extendedLanguageTag` is not unique on
    /// assets that ship two English tracks (e.g. stereo + 5.1), so combine
    /// it with the displayName to disambiguate.
    private static func stableID(for option: AVMediaSelectionOption) -> String {
        let tag = option.extendedLanguageTag ?? "und"
        return "\(tag)|\(option.displayName)"
    }

    /// Human-readable language label. `displayName` already localises BCP-47
    /// tags via the system; fall back to the raw tag if absent.
    private static func label(for option: AVMediaSelectionOption) -> String {
        let name = option.displayName
        return name.isEmpty ? (option.extendedLanguageTag ?? "Unknown") : name
    }

    /// Channel layout hint. Tries `commonMetadata` first, then falls back to a
    /// substring scan of `displayName` (some assets bake "Stereo" / "5.1" into
    /// the option name). Returns `nil` rather than guessing when neither
    /// signal is present — the row simply omits the hint per brand voice
    /// (concrete or silent, never speculative).
    private static func channelHint(for option: AVMediaSelectionOption) -> String? {
        // commonMetadata is rarely populated for audio options on most assets,
        // but check it anyway — if a publisher has set it, it's authoritative.
        for item in option.commonMetadata {
            if item.commonKey == .commonKeyFormat,
               let value = item.stringValue,
               !value.isEmpty {
                return value
            }
        }
        // Fallback: scan the displayName for known tokens.
        let name = option.displayName
        let knownHints = ["7.1.4", "7.1.2", "5.1.4", "5.1.2",
                          "Atmos", "7.1", "5.1", "Stereo", "Mono"]
        for hint in knownHints where name.localizedCaseInsensitiveContains(hint) {
            return hint
        }
        return nil
    }
}
