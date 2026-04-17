import AVFoundation
import Combine
import CoreMedia
import Foundation
import SubtitleDomain

// MARK: - SubtitleController

/// Observable controller for subtitle state within a single playback session.
///
/// Owns the track list, current selection, sidecar cue rendering, and the
/// error channel. Lives on the main actor — all published mutations are
/// therefore safe to bind directly in SwiftUI.
///
/// Sidecar tracks are session-scoped (design doc D5): they are not persisted
/// across app launches. The controller is created fresh for each stream open.
@MainActor
final class SubtitleController: ObservableObject {

    // MARK: - Published

    /// Unified list: embedded tracks first (stable order from AVKit),
    /// sidecars appended in ingestion order.
    @Published private(set) var tracks: [SubtitleTrack] = []

    /// The currently active track, or `nil` for "Off".
    @Published private(set) var selection: SubtitleTrack?

    /// Session-scoped sidecar tracks only. Subset of `tracks`.
    @Published private(set) var sessionSidecars: [SubtitleTrack] = []

    /// The cue currently covering the player's position, or `nil`.
    @Published private(set) var currentCue: SubtitleCue?

    /// The most recent load or activation error. Cleared on the next
    /// successful action. Auto-dismissed by the banner (#32) after 6 s.
    @Published var activeError: SubtitleLoadError?

    // MARK: - Private state

    private let preferenceStore: SubtitlePreferenceStore
    /// Weak reference — set after the player item is ready.
    private weak var playerItem: AVPlayerItem?

    // MARK: - Init

    init(preferenceStore: SubtitlePreferenceStore = SubtitlePreferenceStore()) {
        self.preferenceStore = preferenceStore
    }

    // MARK: - Embedded track refresh

    /// Called once the `AVPlayerItem` is ready to play. Enumerates the
    /// `.legible` media selection group and builds embedded `SubtitleTrack`
    /// values. Applies the stored language preference if one exists.
    func refreshEmbeddedTracks(from avPlayerItem: AVPlayerItem?) {
        playerItem = avPlayerItem
        guard let item = avPlayerItem,
              let asset = item.asset as? AVURLAsset else {
            return
        }

        Task {
            guard let group = try? await asset.loadMediaSelectionGroup(for: .legible) else {
                return
            }
            let embedded: [SubtitleTrack] = group.options.map { option in
                let lang = option.locale?.identifier
                    .replacingOccurrences(of: "_", with: "-")
                let label = option.displayName
                return SubtitleTrack(
                    id: "embedded-\(option.mediaType.rawValue)-\(option.locale?.identifier ?? UUID().uuidString)",
                    source: .embedded(identifier: option.locale?.identifier ?? option.displayName),
                    language: lang,
                    label: label
                )
            }
            // Merge embedded into track list, keeping sidecars at the end.
            tracks = embedded + sessionSidecars
            applyPreferenceIfNeeded()
        }
    }

    // MARK: - Sidecar ingestion

    /// Ingests an SRT file from an `NSItemProvider`. On success the track is
    /// added to `sessionSidecars` and `tracks`. On failure `activeError` is
    /// set and no track is added (design doc § Fallback matrix row 1–3).
    func ingestSidecar(_ itemProvider: NSItemProvider) {
        // NSItemProvider is not Sendable; we capture it with nonisolated(unsafe)
        // here because it is only accessed through the async SubtitleIngestor
        // pipeline which performs a single loadObject call before discarding it.
        nonisolated(unsafe) let provider = itemProvider
        Task {
            let result = await SubtitleIngestor.ingest(from: provider)
            switch result {
            case .success(let track):
                sessionSidecars.append(track)
                // Embedded tracks come first, sidecars appended after.
                let embedded = tracks.filter {
                    if case .embedded = $0.source { return true }
                    return false
                }
                tracks = embedded + sessionSidecars
            case .failure(let error):
                activeError = error
            }
        }
    }

    // MARK: - Track selection

    /// Sets the active track. For `.embedded` tracks, activates the
    /// corresponding `AVMediaSelectionOption` on the player item. For
    /// `.sidecar` tracks, the overlay handles rendering via `currentCue`.
    /// Passing `nil` selects "Off".
    ///
    /// On user selection the preference is persisted (#30).
    func selectTrack(_ track: SubtitleTrack?) {
        if let track {
            activateTrack(track)
        } else {
            deactivateAll()
            selection = nil
            preferenceStore.save("off")
        }
    }

    // MARK: - Cue tick

    /// Called at ~4 Hz by `AVPlayer`'s periodic time observer. Binary-searches
    /// the selected sidecar's cue list to find the cue active at `currentTime`.
    /// No-ops if the selection is `nil` or an embedded track.
    func tick(currentTime: CMTime) {
        guard let track = selection else {
            currentCue = nil
            return
        }
        guard case .sidecar(_, _, let cues) = track.source else {
            // Embedded — AVKit owns rendering; clear our overlay.
            currentCue = nil
            return
        }
        currentCue = cue(in: cues, at: currentTime)
    }

    // MARK: - Private helpers

    /// Applies the stored preference at stream open (design doc D8).
    /// Auto-pick failures are logged, not bannered.
    private func applyPreferenceIfNeeded() {
        let pref = preferenceStore.load()
        guard let resolved = LanguagePreferenceResolver.pick(from: tracks, preferred: pref) else {
            // nil pref, "off", or no match → leave Off. No banner.
            return
        }
        // Auto-pick: attempt activation but suppress banner on failure.
        activateTrack(resolved, suppressBanner: true)
    }

    /// Activates `track`, writing the preference unless `suppressBanner` is true.
    private func activateTrack(_ track: SubtitleTrack, suppressBanner: Bool = false) {
        switch track.source {
        case .embedded(let identifier):
            guard let item = playerItem,
                  let asset = item.asset as? AVURLAsset else {
                if !suppressBanner {
                    activeError = .systemTrackFailed(reason: "No player item available")
                    // selection already nil — do not set
                }
                return
            }
            Task {
                guard let group = try? await asset.loadMediaSelectionGroup(for: .legible) else {
                    if !suppressBanner {
                        activeError = .systemTrackFailed(reason: "No legible group")
                        // design doc § Fallback matrix row 4: revert to nil
                    }
                    return
                }
                let option = group.options.first {
                    ($0.locale?.identifier ?? $0.displayName) == identifier
                }
                guard let option else {
                    if !suppressBanner {
                        activeError = .systemTrackFailed(reason: "Option not found for \(identifier)")
                        // Don't set selection — it stays nil
                    }
                    return
                }
                item.select(option, in: group)
                let selected = item.currentMediaSelection.selectedMediaOption(in: group)
                applyEmbeddedSelectionResult(
                    didActivate: selected === option,
                    track: track,
                    suppressBanner: suppressBanner
                )
            }

        case .sidecar:
            // Deactivate any active AVKit legible track first.
            deactivateEmbedded()
            selection = track
            currentCue = nil
            if !suppressBanner {
                preferenceStore.save(track.language ?? "off")
            }
        }
    }

    /// Deactivates all subtitle rendering: clears AVKit selection and sidecar cue.
    private func deactivateAll() {
        deactivateEmbedded()
        currentCue = nil
    }

    private func deactivateEmbedded() {
        guard let item = playerItem,
              let asset = item.asset as? AVURLAsset else { return }
        Task {
            if let group = try? await asset.loadMediaSelectionGroup(for: .legible) {
                item.selectMediaOptionAutomatically(in: group)
            }
        }
    }

    func applyEmbeddedSelectionResult(didActivate: Bool,
                                      track: SubtitleTrack,
                                      suppressBanner: Bool = false) {
        if didActivate {
            selection = track
            activeError = nil
            if !suppressBanner {
                preferenceStore.save(track.language ?? "off")
            }
        } else {
            selection = nil
            currentCue = nil
            if !suppressBanner {
                activeError = .systemTrackFailed(reason: "System track activation failed")
            }
        }
    }

    func _setTracksForTesting(_ tracks: [SubtitleTrack],
                              selection: SubtitleTrack? = nil) {
        self.tracks = tracks
        self.sessionSidecars = tracks.filter {
            if case .sidecar = $0.source { return true }
            return false
        }
        self.selection = selection
    }

    /// Binary-searches `cues` (sorted by startTime) for the cue covering `time`.
    private func cue(in cues: [SubtitleCue], at time: CMTime) -> SubtitleCue? {
        guard !cues.isEmpty else { return nil }
        let seconds = time.seconds
        // Binary search: find last cue with startTime <= time
        var lo = 0
        var hi = cues.count - 1
        var candidate: SubtitleCue?
        while lo <= hi {
            let mid = (lo + hi) / 2
            let cue = cues[mid]
            if cue.startTime.seconds <= seconds {
                candidate = cue
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        guard let c = candidate,
              c.endTime.seconds > seconds else { return nil }
        return c
    }
}
