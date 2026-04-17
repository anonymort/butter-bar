import AVFoundation
import Combine
import EngineInterface
import Foundation
import LibraryDomain
import PlayerDomain

// MARK: - PlayerViewModel

/// Bridges `EngineClient` and AVKit to the SwiftUI player view, driving every
/// state change through `PlayerStateMachine` (Phase 3 foundation, design at
/// `docs/design/player-state-foundation.md`).
///
/// Owns `AVPlayer` lifetime. Publishes `state: PlayerState` (the canonical
/// state-machine projection) and `health: StreamHealthDTO?` (kept as a
/// separate surface for `StreamHealthHUD` which renders the full DTO, not
/// just the tier — `PlayerState` carries no DTO).
///
/// Engine event projection lives here, not in the state machine. The machine
/// never imports `EngineInterface` or AVKit; it only sees `PlayerEvent` values.
@MainActor
final class PlayerViewModel: ObservableObject {

    // MARK: Published

    /// Canonical state-machine projection. The view renders chrome from this.
    @Published private(set) var state: PlayerState = .closed

    /// Full health DTO for the HUD. Carried alongside `state` because the
    /// HUD needs `secondsBufferedAhead`, peer count, etc. — fields the
    /// state machine deliberately doesn't carry.
    @Published private(set) var health: StreamHealthDTO?

    /// Current playback time in seconds, observed from `AVPlayer` via a
    /// periodic time observer. Drives the scrub bar in `PlayerOverlay`.
    /// `0` until the asset reports a sensible time.
    @Published private(set) var currentSeconds: Double = 0

    /// Asset duration in seconds, observed from `AVPlayerItem.duration`.
    /// `0` until the asset reports a finite duration.
    @Published private(set) var durationSeconds: Double = 0

    /// Resume-prompt offer (#19). Non-nil iff the resume prompt should be
    /// shown to the user. Cleared by the user's choice (continue / start over)
    /// or by an explicit dismiss. Fired at most once per VM lifetime per
    /// design `docs/design/player-state-foundation.md § Risks` — the
    /// `hasOfferedResume` flag below gates re-entry.
    @Published private(set) var resumePromptOffer: ResumePromptOffer?

    // MARK: Internal

    /// Strong reference — released in `close()`.
    private(set) var player: AVPlayer?

    // MARK: Private

    private let streamDescriptor: StreamDescriptorDTO
    private let engineClient: EngineClient
    /// Async closure that returns the current playback-history snapshot.
    /// Defaults to `engineClient.listPlaybackHistory()` in production; tests
    /// inject a fake to drive the resume-prompt seam without standing up
    /// a real XPC connection.
    private let historyProvider: () async throws -> [PlaybackHistoryDTO]
    private let now: () -> Date
    /// Identity of the file behind this stream. Optional because preview /
    /// snapshot tests construct a VM without an underlying torrent. When
    /// `nil`, the resume-prompt lookup is skipped (no history to query).
    private let torrentID: String?
    private let fileIndex: Int32?
    private var healthSubscription: AnyCancellable?
    private var reconnectSubscription: AnyCancellable?
    private var avPlayerObservers = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()
    private var periodicTimeObserver: Any?
    private var isClosed = false
    private var hasPriorEvents = false   // edge detection for disconnect/reconnect
    /// Gate so the resume prompt fires at most once per VM lifetime, even if
    /// the state machine briefly re-enters `.open` (design § Risks).
    private var hasOfferedResume = false
    /// AVPlayerItem the resume seek (if any) was scheduled against. Held so
    /// "Start over" can override the prepared seek by replacing it with `.zero`.
    private weak var primaryItem: AVPlayerItem?

    // MARK: - Init

    init(streamDescriptor: StreamDescriptorDTO,
         engineClient: EngineClient,
         torrentID: String? = nil,
         fileIndex: Int32? = nil,
         historyProvider: (() async throws -> [PlaybackHistoryDTO])? = nil,
         now: @escaping () -> Date = Date.init) {
        self.streamDescriptor = streamDescriptor
        self.engineClient = engineClient
        self.torrentID = torrentID
        self.fileIndex = fileIndex
        self.historyProvider = historyProvider ?? { try await engineClient.listPlaybackHistory() }
        self.now = now

        // Project the (already-completed) open through the state machine so
        // every consumer sees state move .closed → .buffering(.openingStream)
        // → .open (or → .error on URL failure).
        handle(.userRequestedOpen)

        guard let url = URL(string: streamDescriptor.loopbackURL as String) else {
            handle(.engineReturnedOpenError(.streamOpenFailed))
            return
        }

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer
        self.primaryItem = item

        handle(.engineReturnedDescriptor)

        // Resume seek if a prior byte offset was persisted.
        if streamDescriptor.resumeByteOffset > 0 {
            scheduleResumeSeek(player: avPlayer, item: item)
        }

        bindAVPlayerObservers(player: avPlayer, item: item)

        // Evaluate the resume-prompt seam (#19). Fires at most once per VM
        // lifetime; the lookup is async because it traverses XPC. Triggered
        // here rather than on every `.open` re-entry so brief stalls do not
        // re-flash the prompt. Skipped when no identity was supplied
        // (preview / snapshot / legacy call sites) so the VM does not even
        // queue the Task.
        if torrentID != nil, fileIndex != nil {
            Task { await self.evaluateResumePromptOffer() }
        } else {
            // No identity → no prompt is possible. Mark the gate so any
            // later `requestAutoPlayWhenReady()` call plays immediately.
            hasOfferedResume = true
        }

        // Re-bind to the active events stream whenever EngineClient reconnects.
        reconnectSubscription = NotificationCenter.default.publisher(
            for: EngineClient.eventsDidChangeNotification,
            object: engineClient
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            Task { await self?.handleReconnectNotification() }
        }

        // Subscribe to the current health stream.
        Task { await self.subscribeToHealth() }
    }

    // MARK: - Public controls (project user actions to events)

    func play() {
        handle(.userTappedPlay)
    }

    func pause() {
        handle(.userTappedPause)
    }

    /// Pauses, closes the stream with the engine, and releases the player.
    /// Safe to call multiple times — subsequent calls are no-ops.
    func close() {
        guard !isClosed else { return }
        handle(.userTappedClose)
    }

    func retry() {
        handle(.userTappedRetry)
    }

    /// Seek the underlying `AVPlayer`. Invisible to the state machine per
    /// design § D5 (scrub does not produce a `PlayerEvent`).
    func seek(toSeconds seconds: Double) {
        guard let player else { return }
        let target = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        player.seek(to: target,
                    toleranceBefore: .zero,
                    toleranceAfter: CMTime(seconds: 1, preferredTimescale: 600))
    }

    // MARK: - Resume prompt (#19)

    /// User chose "Continue from where you stopped". The existing
    /// `scheduleResumeSeek` path is already armed for `streamDescriptor.resumeByteOffset > 0`;
    /// just clear the prompt and project the play tap.
    func resolveResumeContinue() {
        resumePromptOffer = nil
        play()
    }

    /// User chose "Start from the beginning". Seek the AVPlayer to `.zero`
    /// to override the prepared resume seek, then project the play tap.
    func resolveResumeStartOver() {
        resumePromptOffer = nil
        // Cancel the pending resume seek subscription so it cannot land
        // after the user-driven .zero seek (would otherwise race).
        cancellables.removeAll()
        if let item = primaryItem {
            item.seek(to: .zero, completionHandler: nil)
        } else {
            player?.seek(to: .zero)
        }
        play()
    }

    /// User dismissed the prompt (Esc, click-outside, or explicit dismiss).
    /// No event projected — the player stays in `.open` for the user to act.
    func dismissResumePrompt() {
        resumePromptOffer = nil
    }

    // MARK: - Event handling

    /// Apply a `PlayerEvent` through the state machine and perform the side
    /// effects implied by the resulting transition. The state machine is
    /// pure; this method is where AVPlayer / engine-client calls happen.
    private func handle(_ event: PlayerEvent) {
        let previous = state
        let next = PlayerStateMachine.apply(event, to: previous, now: now())
        state = next

        // Side effects keyed off (event, previous → next) edges.
        switch (previous, event, next) {

        case (_, .userTappedClose, .closed):
            performClose()

        case (.error, .userTappedRetry, .buffering(.openingStream)):
            // Reissue openStream via the existing path — handled by the
            // caller that originally constructed this VM. For v1 we surface
            // the retry intent on `state`; the calling view re-creates a
            // fresh PlayerViewModel against the same descriptor. (Direct
            // engine.openStream re-issue from inside the VM is deferred —
            // see #26 for the full retry plumbing.)
            break

        case (_, .userTappedPlay, .playing):
            player?.play()

        case (_, .userTappedPause, .paused):
            player?.pause()

        default:
            break
        }
    }

    private func performClose() {
        isClosed = true
        healthSubscription?.cancel()
        reconnectSubscription?.cancel()
        avPlayerObservers.removeAll()
        healthSubscription = nil
        reconnectSubscription = nil
        cancellables.removeAll()
        if let token = periodicTimeObserver {
            player?.removeTimeObserver(token)
            periodicTimeObserver = nil
        }
        player?.pause()
        player = nil
        let streamID = streamDescriptor.streamID as String
        Task {
            try? await engineClient.closeStream(streamID as NSString)
        }
    }

    // MARK: - Engine event projection

    /// Subscribe to StreamHealth events for this stream.
    private func subscribeToHealth() async {
        guard let events = await engineClient.events else {
            // events became nil — disconnect edge.
            if hasPriorEvents {
                hasPriorEvents = false
                await MainActor.run { self.handle(.engineDisconnected) }
            }
            return
        }
        guard !isClosed else { return }
        let targetID = streamDescriptor.streamID as String

        // hasPriorEvents transitions detect reconnect on next call; first
        // successful subscribe simply records the events handle.
        let wasConnected = hasPriorEvents
        hasPriorEvents = true

        if !wasConnected && state == .error(.xpcDisconnected) {
            // Reconnected from a disconnected error state: project the
            // reconnect signal but per design D6 the state machine will
            // not auto-resume — user must tap Retry.
            handle(.engineReconnected)
        }

        healthSubscription?.cancel()
        healthSubscription = events.streamHealthChangedSubject
            .filter { ($0.streamID as String) == targetID }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dto in
                guard let self else { return }
                self.health = dto
                self.handle(.engineHealthChanged(dto.tierValue))
            }
    }

    private func handleReconnectNotification() async {
        // Edge: events went nil → valid OR valid → nil. Inspect.
        let events = await engineClient.events
        if events == nil {
            if hasPriorEvents {
                hasPriorEvents = false
                handle(.engineDisconnected)
            }
        } else {
            await subscribeToHealth()
        }
    }

    // MARK: - AVPlayer observation

    private func bindAVPlayerObservers(player: AVPlayer, item: AVPlayerItem) {
        // timeControlStatus → playing/stalled/paused projection
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .playing:
                    self.handle(.avPlayerBeganPlaying)
                case .waitingToPlayAtSpecifiedRate:
                    self.handle(.avPlayerStalled)
                case .paused:
                    // Don't project: user-initiated pause is driven via
                    // `userTappedPause`; KVO `.paused` would double-fire.
                    break
                @unknown default:
                    break
                }
            }
            .store(in: &avPlayerObservers)

        item.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] empty in
                if empty { self?.handle(.avPlayerStalled) }
            }
            .store(in: &avPlayerObservers)

        item.publisher(for: \.isPlaybackLikelyToKeepUp)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] keepUp in
                if keepUp { self?.handle(.avPlayerResumed) }
            }
            .store(in: &avPlayerObservers)

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .failed { self?.handle(.avPlayerFailed) }
            }
            .store(in: &avPlayerObservers)

        // Asset duration arrives some time after `readyToPlay`. Republish
        // through `durationSeconds` so the scrub bar can render once it is
        // known.
        item.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cmtime in
                guard let self else { return }
                if cmtime.isNumeric, cmtime.seconds.isFinite, cmtime.seconds > 0 {
                    self.durationSeconds = cmtime.seconds
                }
            }
            .store(in: &avPlayerObservers)

        // Periodic time observer for scrub-bar progress. 200 ms cadence is
        // smooth enough for the eased fill animation without busying the
        // main thread.
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] cmtime in
            guard let self else { return }
            if cmtime.isNumeric, cmtime.seconds.isFinite, cmtime.seconds >= 0 {
                self.currentSeconds = cmtime.seconds
            }
        }
    }

    // MARK: - Private helpers

    /// Evaluate the resume prompt seam (#19). Looks up the playback history
    /// row for `(torrentID, fileIndex)`, derives `WatchStatus`, and asks
    /// `ResumePromptDecision` whether to offer. Fires the prompt at most
    /// once per VM lifetime.
    private func evaluateResumePromptOffer() async {
        guard !hasOfferedResume else { return }
        // Mark the gate now so concurrent re-entries (e.g. retry) cannot
        // double-fire even if the await below suspends.
        hasOfferedResume = true

        guard let torrentID, let fileIndex else { return }

        let history: [PlaybackHistoryDTO]
        do {
            history = try await historyProvider()
        } catch {
            // Defensive: if history can't be loaded the user just starts
            // afresh. No prompt — log and return.
            NSLog("[PlayerViewModel] resume prompt: listPlaybackHistory failed: %@",
                  error.localizedDescription)
            return
        }

        let row = history.first { dto in
            (dto.torrentID as String) == torrentID && dto.fileIndex == fileIndex
        }
        let totalBytes = streamDescriptor.contentLength
        let status = WatchStatus.from(history: row, totalBytes: totalBytes)

        guard ResumePromptDecision.shouldOffer(watchStatus: status,
                                               descriptor: streamDescriptor) else {
            // No prompt warranted — autoplay if the caller is waiting on
            // the decision before starting playback.
            startPlaybackIfPending()
            return
        }

        let label = displayableResumeLabel()
        resumePromptOffer = ResumePromptOffer(resumeTimeLabel: label)
    }

    /// Set to `true` by `requestAutoPlayWhenReady()` to indicate the view
    /// would like the VM to start playback as soon as the resume-prompt
    /// decision has settled. The VM uses this flag instead of letting the
    /// view race the prompt evaluation.
    private var pendingAutoPlay = false

    /// Called by the view on appear to express "play once the resume
    /// decision is made". If the decision has already settled with no
    /// prompt to show, plays immediately.
    func requestAutoPlayWhenReady() {
        if hasOfferedResume && resumePromptOffer == nil {
            // Decision already made and nothing to ask the user — play.
            play()
        } else {
            pendingAutoPlay = true
        }
    }

    private func startPlaybackIfPending() {
        guard pendingAutoPlay else { return }
        pendingAutoPlay = false
        play()
    }

    /// Best-effort displayable resume label derived from
    /// `resumeByteOffset / contentLength × duration` — same math the resume
    /// seek uses (see `scheduleResumeSeek`). Returns `nil` if duration is
    /// not yet known so the prompt renders "Continue" rather than blocking.
    private func displayableResumeLabel() -> String? {
        guard streamDescriptor.contentLength > 0 else { return nil }
        guard let item = primaryItem,
              item.duration.isNumeric,
              item.duration.seconds > 0 else { return nil }
        let ratio = Double(streamDescriptor.resumeByteOffset)
            / Double(streamDescriptor.contentLength)
        let seconds = item.duration.seconds * ratio
        return Self.formatResumeSeconds(seconds)
    }

    /// Format seconds as a calm, monospaced-friendly label per
    /// `06-brand.md § Voice` ("12 seconds buffered" register — concrete,
    /// short). Examples: `0s`, `45s`, `12m`, `1h 23m`.
    static func formatResumeSeconds(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        if total < 60 {
            return "\(total)s"
        }
        let minutes = total / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        if remMin == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remMin)m"
    }

    /// Once the asset duration is available, seeks to the byte-ratio–derived time.
    /// This is a best-effort approximation; the planner and gateway handle actual
    /// piece scheduling from the correct offset.
    private func scheduleResumeSeek(player: AVPlayer, item: AVPlayerItem) {
        item.publisher(for: \.status)
            .filter { $0 == .readyToPlay }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak player, weak item] _ in
                guard let self,
                      let player,
                      let item,
                      item.duration.isNumeric,
                      item.duration.seconds > 0,
                      self.streamDescriptor.contentLength > 0
                else { return }

                let ratio = Double(self.streamDescriptor.resumeByteOffset)
                    / Double(self.streamDescriptor.contentLength)
                let seekSeconds = item.duration.seconds * ratio
                let seekTime = CMTime(seconds: seekSeconds, preferredTimescale: 600)
                player.seek(to: seekTime,
                            toleranceBefore: .zero,
                            toleranceAfter: CMTime(seconds: 5, preferredTimescale: 600))
            }
            .store(in: &cancellables)
    }
}
