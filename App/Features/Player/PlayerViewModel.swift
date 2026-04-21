import AVFoundation
import Combine
import CoreMedia
import EngineInterface
import Foundation
import LibraryDomain
import MetadataDomain
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

    /// Last-known engine tier captured before a transition into `.error(_)`.
    /// Used by `PlayerErrorChrome` to surface a calm context hint on
    /// `.playbackFailed` when the engine was already starving when playback
    /// stopped. `nil` if no health event has ever been observed.
    @Published private(set) var lastKnownTier: StreamHealthTier?

    /// Whether the buffering chrome should show its long-buffering secondary
    /// line. Decided against an injected clock per
    /// `PlayerCopy.shouldShowLongStarvingLine` — published so the view can
    /// react when the threshold is crossed. Resets to `false` whenever the
    /// state leaves `.buffering(.engineStarving)`.
    @Published private(set) var showLongBufferingSecondary: Bool = false

    /// Subtitle controller for this playback session. UI binds to this.
    @Published private(set) var subtitleController: SubtitleController

    /// Quiet one-line transient message for non-fatal playback orchestration
    /// outcomes, e.g. when auto-play cannot find the next episode locally.
    @Published private(set) var transientMessage: String?

    // MARK: Internal

    /// Strong reference — released in `close()`.
    private(set) var player: AVPlayer?

    // MARK: Private

    private var streamDescriptor: StreamDescriptorDTO
    private let engineClient: EngineClient
    /// Async closure that returns the current playback-history snapshot.
    /// Defaults to `engineClient.listPlaybackHistory()` in production; tests
    /// inject a fake to drive the resume-prompt seam without standing up
    /// a real XPC connection.
    private let historyProvider: () async throws -> [PlaybackHistoryDTO]
    /// Async closure that opens a stream by `(torrentID, fileIndex)`. Defaults
    /// to `engineClient.openStream` in production; tests inject a fake so the
    /// retry path (#26) can be exercised without standing up a real XPC
    /// connection.
    private let streamOpener: (String, Int32) async throws -> StreamDescriptorDTO
    private let now: () -> Date
    /// Identity of the file behind this stream. Optional because preview /
    /// snapshot tests construct a VM without an underlying torrent. When
    /// `nil`, the resume-prompt lookup is skipped (no history to query).
    private var torrentID: String?
    private var fileIndex: Int32?
    private var currentEpisode: Episode?
    private let currentShow: Show?
    private let resolveNextEpisode: @Sendable (Episode) async -> (torrentID: String, fileIndex: Int32)?
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
    /// Wall-clock instant the current `.buffering(.engineStarving)` interval
    /// started, used to drive `showLongBufferingSecondary` against the
    /// injected `now` clock. `nil` while not in `.engineStarving`.
    private var engineStarvingStartedAt: Date?
    /// Long-running task that flips `showLongBufferingSecondary` to `true`
    /// once the threshold elapses. Cancelled on every state transition out
    /// of `.engineStarving`.
    private var longBufferingTask: Task<Void, Never>?
    /// In-flight retry. Held so a re-entry of retry while one is pending is
    /// a no-op (the state machine already moved us back to
    /// `.buffering(.openingStream)` — a second openStream call would race).
    private var retryTask: Task<Void, Never>?
    private var nextEpisodeTask: Task<Void, Never>?
    private var transientMessageTask: Task<Void, Never>?
    /// Token returned by `addPeriodicTimeObserver` for subtitle ticks — must
    /// be removed on close, separately from `periodicTimeObserver`.
    private var subtitleTimeObserver: Any?

    // MARK: - Init

    init(streamDescriptor: StreamDescriptorDTO,
         engineClient: EngineClient,
         torrentID: String? = nil,
         fileIndex: Int32? = nil,
         currentEpisode: Episode? = nil,
         currentShow: Show? = nil,
         resolveNextEpisode: ((@Sendable (Episode) async -> (torrentID: String, fileIndex: Int32)?))? = nil,
         historyProvider: (() async throws -> [PlaybackHistoryDTO])? = nil,
         streamOpener: ((String, Int32) async throws -> StreamDescriptorDTO)? = nil,
         now: @escaping () -> Date = Date.init,
         preferenceStore: SubtitlePreferenceStore = SubtitlePreferenceStore()) {
        self.streamDescriptor = streamDescriptor
        self.engineClient = engineClient
        self.torrentID = torrentID
        self.fileIndex = fileIndex
        self.currentEpisode = currentEpisode
        self.currentShow = currentShow
        self.historyProvider = historyProvider ?? { try await engineClient.listPlaybackHistory() }
        self.streamOpener = streamOpener ?? { tid, idx in
            try await engineClient.openStream(tid as NSString, fileIndex: NSNumber(value: idx))
        }
        self.resolveNextEpisode = resolveNextEpisode ?? Self.libraryResolver(
            engineClient: engineClient,
            show: currentShow
        )
        self.now = now
        self.subtitleController = SubtitleController(preferenceStore: preferenceStore)

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

        // When the item is ready, refresh embedded subtitle tracks. Stored
        // in `avPlayerObservers` so it survives the `cancellables.removeAll()`
        // call in `resolveResumeStartOver` (which targets the resume-seek
        // subscription).
        item.publisher(for: \.status)
            .filter { $0 == .readyToPlay }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                self?.subtitleController.refreshEmbeddedTracks(from: item)
            }
            .store(in: &avPlayerObservers)

        // Wire 4 Hz time observer so the subtitle overlay stays in sync.
        // The block fires on the main queue (queue: .main); we use
        // MainActor.assumeIsolated to satisfy the Swift 6 concurrency checker.
        let tickInterval = CMTime(value: 1, timescale: 4)
        subtitleTimeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: tickInterval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.subtitleController.tick(currentTime: time)
            }
        }

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

    func openNextEpisode(_ episode: Episode) {
        nextEpisodeTask?.cancel()
        transientMessage = nil
        nextEpisodeTask = Task { [weak self, resolveNextEpisode, streamOpener] in
            guard let resolution = await resolveNextEpisode(episode) else {
                await MainActor.run {
                    self?.showTransientMessage("Next episode not in library")
                }
                return
            }
            do {
                let descriptor = try await streamOpener(resolution.torrentID, resolution.fileIndex)
                await MainActor.run {
                    self?.applyNextEpisodeDescriptor(
                        descriptor,
                        torrentID: resolution.torrentID,
                        fileIndex: resolution.fileIndex,
                        episode: episode
                    )
                }
            } catch {
                await MainActor.run {
                    self?.showTransientMessage("Next episode could not start")
                }
            }
        }
    }

    // MARK: - Event handling

    /// Apply a `PlayerEvent` through the state machine and perform the side
    /// effects implied by the resulting transition. The state machine is
    /// pure; this method is where AVPlayer / engine-client calls happen.
    private func handle(_ event: PlayerEvent) {
        let previous = state

        // Capture the last-known engine tier *before* the transition — once
        // the state machine moves us into `.error(_)` the published health
        // DTO may continue to update, but the tier we want is the one that
        // was true when playback stopped.
        if case .engineHealthChanged(let tier) = event {
            lastKnownTier = tier
        }

        let next = PlayerStateMachine.apply(event, to: previous, now: now())
        state = next

        if let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: previous, to: next),
            playheadSeconds: currentSeconds,
            durationSeconds: durationSeconds,
            episode: currentEpisode
        ) {
            EndOfEpisodeDetector.publisher.send(signal)
        }

        updateLongBufferingTracking(previous: previous, next: next)

        // Side effects keyed off (event, previous → next) edges.
        switch (previous, event, next) {

        case (_, .userTappedClose, .closed):
            performClose()

        case (.error, .userTappedRetry, .buffering(.openingStream)):
            // Re-issue openStream with the original (torrentID, fileIndex)
            // captured at first open. Per design § D6 reconnect alone never
            // triggers this — only an explicit user retry does.
            performRetry()

        case (_, .userTappedPlay, .playing):
            player?.play()

        case (_, .userTappedPause, .paused):
            player?.pause()

        default:
            break
        }
    }

    /// Internal seam used by `PlayerRetryPathTests` to drive the VM into a
    /// known state without standing up XPC or AVKit. Marked `internal` so
    /// `@testable import ButterBar` can reach it; not part of any public API.
    func injectEventForTesting(_ event: PlayerEvent) {
        handle(event)
    }

    /// Re-issue `engine.openStream(torrentID, fileIndex)` through the
    /// injected `streamOpener`. Result is projected back through the state
    /// machine as `.engineReturnedDescriptor` (success) or
    /// `.engineReturnedOpenError(_)` (failure), matching the original-open
    /// flow exactly so the user sees the same chrome regardless of whether
    /// it's the first attempt or a retry.
    private func performRetry() {
        guard let torrentID, let fileIndex else {
            // No identity captured at construction → nothing to re-issue.
            // The state machine has already moved to `.buffering(.openingStream)`;
            // the user is left in a defensible "loading" state rather than a
            // crashed view. Real call sites always have identity (#19's
            // PlayerView init), so this branch only fires in tests / previews.
            return
        }

        retryTask?.cancel()
        retryTask = Task { [weak self, streamOpener] in
            do {
                let dto = try await streamOpener(torrentID, fileIndex)
                guard let self else { return }
                await MainActor.run {
                    self.applyRetryDescriptor(dto)
                }
            } catch {
                guard let self else { return }
                let code = Self.engineCode(from: error)
                await MainActor.run {
                    self.handle(.engineReturnedOpenError(code))
                }
            }
        }
    }

    /// Apply a freshly-opened descriptor from a retry. Replaces the
    /// underlying `AVPlayer` so the new loopback URL is consumed, then
    /// projects `.engineReturnedDescriptor` so the state machine moves
    /// `.buffering(.openingStream) → .open`.
    private func applyRetryDescriptor(_ dto: StreamDescriptorDTO) {
        // Tear down the old AVPlayer observers — the old item is gone.
        avPlayerObservers.removeAll()
        if let token = periodicTimeObserver {
            player?.removeTimeObserver(token)
            periodicTimeObserver = nil
        }
        // Also tear down the subtitle time observer; it will be re-wired on the
        // new player below. Without this, the observer points at the dead player.
        if let token = subtitleTimeObserver {
            player?.removeTimeObserver(token)
            subtitleTimeObserver = nil
        }

        guard let url = URL(string: dto.loopbackURL as String) else {
            handle(.engineReturnedOpenError(.streamOpenFailed))
            return
        }
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer
        self.primaryItem = item

        handle(.engineReturnedDescriptor)
        bindAVPlayerObservers(player: avPlayer, item: item)

        // Re-wire readyToPlay → refreshEmbeddedTracks (removed with avPlayerObservers above).
        item.publisher(for: \.status)
            .filter { $0 == .readyToPlay }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                self?.subtitleController.refreshEmbeddedTracks(from: item)
            }
            .store(in: &avPlayerObservers)

        // Re-wire the 4 Hz subtitle tick observer for the new player.
        let tickInterval = CMTime(value: 1, timescale: 4)
        subtitleTimeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: tickInterval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.subtitleController.tick(currentTime: time)
            }
        }
    }

    private func applyNextEpisodeDescriptor(_ dto: StreamDescriptorDTO,
                                            torrentID: String,
                                            fileIndex: Int32,
                                            episode: Episode) {
        let previousStreamID = streamDescriptor.streamID as String
        avPlayerObservers.removeAll()
        if let token = periodicTimeObserver {
            player?.removeTimeObserver(token)
            periodicTimeObserver = nil
        }
        if let observer = subtitleTimeObserver {
            player?.removeTimeObserver(observer)
            subtitleTimeObserver = nil
        }
        player?.pause()

        self.streamDescriptor = dto
        self.torrentID = torrentID
        self.fileIndex = fileIndex
        self.currentEpisode = episode
        self.currentSeconds = 0
        self.durationSeconds = 0
        self.resumePromptOffer = nil
        self.hasOfferedResume = true
        self.isClosed = false
        self.health = nil
        self.subtitleController = SubtitleController()

        Task { try? await engineClient.closeStream(previousStreamID as NSString) }

        guard let url = URL(string: dto.loopbackURL as String) else {
            handle(.engineReturnedOpenError(.streamOpenFailed))
            return
        }
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer
        self.primaryItem = item

        state = .closed
        // Reset stale buffering indicators so they do not bleed into the
        // new episode. This direct assignment bypasses the state machine
        // transition that normally resets these via updateLongBufferingTracking.
        showLongBufferingSecondary = false
        engineStarvingStartedAt = nil
        longBufferingTask?.cancel()
        longBufferingTask = nil
        handle(.userRequestedOpen)
        handle(.engineReturnedDescriptor)
        bindAVPlayerObservers(player: avPlayer, item: item)
        play()
        Task { await self.subscribeToHealth() }
    }

    /// Best-effort extraction of an `EngineErrorCode` from a thrown error.
    /// Falls back to `.streamOpenFailed` so the user still sees brand-voice
    /// copy rather than a raw NSError description.
    private static func engineCode(from error: Error) -> EngineErrorCode {
        if case let EngineClientError.serviceError(nsError) = error,
           nsError.domain == EngineErrorDomain,
           let code = EngineErrorCode(rawValue: nsError.code) {
            return code
        }
        let nsError = error as NSError
        if nsError.domain == EngineErrorDomain,
           let code = EngineErrorCode(rawValue: nsError.code) {
            return code
        }
        return .streamOpenFailed
    }

    private func showTransientMessage(_ message: String) {
        transientMessageTask?.cancel()
        transientMessage = message
        transientMessageTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            await MainActor.run {
                self?.transientMessage = nil
            }
        }
    }

    private static func libraryResolver(
        engineClient: EngineClient,
        show: Show?
    ) -> (@Sendable (Episode) async -> (torrentID: String, fileIndex: Int32)?) {
        { episode in
            guard let show else { return nil }
            let torrents = (try? await engineClient.listTorrents()) ?? []
            for torrent in torrents {
                let torrentID = torrent.torrentID as String
                let files = (try? await engineClient.listFiles(torrentID as NSString)) ?? []
                for file in files where file.isPlayableByAVFoundation {
                    let parsed = TitleNameParser.parse(file.path as String)
                    guard parsed.season == episode.seasonNumber,
                          parsed.episode == episode.episodeNumber else {
                        continue
                    }
                    let ranked = MatchRanker.rank(parsed: parsed, candidates: [.show(show)])
                    guard let top = ranked.first,
                          top.confidence >= MatchRanker.defaultThreshold else {
                        continue
                    }
                    return (torrentID: torrentID, fileIndex: file.fileIndex)
                }
            }
            return nil
        }
    }

    /// Drive `showLongBufferingSecondary` and the timer that flips it.
    /// Pure-ish: only mutates VM state, no I/O.
    private func updateLongBufferingTracking(previous: PlayerState,
                                             next: PlayerState) {
        let wasStarving = previous == .buffering(reason: .engineStarving)
        let isStarving = next == .buffering(reason: .engineStarving)

        if isStarving && !wasStarving {
            // Entered starving — start the threshold timer.
            engineStarvingStartedAt = now()
            scheduleLongBufferingFlip()
        } else if !isStarving && wasStarving {
            // Left starving — reset.
            engineStarvingStartedAt = nil
            longBufferingTask?.cancel()
            longBufferingTask = nil
            showLongBufferingSecondary = false
        }
    }

    private func scheduleLongBufferingFlip() {
        longBufferingTask?.cancel()
        let threshold = PlayerCopy.longStarvingThreshold
        longBufferingTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(threshold))
            } catch {
                return
            }
            await MainActor.run {
                guard let self else { return }
                // Re-check: only flip if still starving when the deadline
                // lands — the state may have recovered while we slept.
                if let started = self.engineStarvingStartedAt,
                   PlayerCopy.shouldShowLongStarvingLine(
                    bufferingStartedAt: started,
                    now: self.now()) {
                    self.showLongBufferingSecondary = true
                }
            }
        }
    }

    private func performClose() {
        isClosed = true
        healthSubscription?.cancel()
        reconnectSubscription?.cancel()
        retryTask?.cancel()
        nextEpisodeTask?.cancel()
        transientMessageTask?.cancel()
        longBufferingTask?.cancel()
        retryTask = nil
        nextEpisodeTask = nil
        transientMessageTask = nil
        longBufferingTask = nil
        avPlayerObservers.removeAll()
        healthSubscription = nil
        reconnectSubscription = nil
        cancellables.removeAll()
        if let token = periodicTimeObserver {
            player?.removeTimeObserver(token)
            periodicTimeObserver = nil
        }
        if let observer = subtitleTimeObserver {
            player?.removeTimeObserver(observer)
            subtitleTimeObserver = nil
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

        NotificationCenter.default.publisher(
            for: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self else { return }
            guard let signal = EndOfEpisodeDetector.detect(
                stateTransition: (from: .playing, to: .closed),
                playheadSeconds: self.durationSeconds,
                durationSeconds: self.durationSeconds,
                episode: self.currentEpisode
            ) else { return }
            EndOfEpisodeDetector.publisher.send(signal)
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
            MainActor.assumeIsolated {
                guard let self else { return }
                if cmtime.isNumeric, cmtime.seconds.isFinite, cmtime.seconds >= 0 {
                    self.currentSeconds = cmtime.seconds
                }
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
