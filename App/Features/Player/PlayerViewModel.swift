import AVFoundation
import Combine
import EngineInterface
import Foundation
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

    // MARK: Internal

    /// Strong reference — released in `close()`.
    private(set) var player: AVPlayer?

    // MARK: Private

    private let streamDescriptor: StreamDescriptorDTO
    private let engineClient: EngineClient
    private let now: () -> Date
    private var healthSubscription: AnyCancellable?
    private var reconnectSubscription: AnyCancellable?
    private var avPlayerObservers = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()
    private var isClosed = false
    private var hasPriorEvents = false   // edge detection for disconnect/reconnect

    // MARK: - Init

    init(streamDescriptor: StreamDescriptorDTO,
         engineClient: EngineClient,
         now: @escaping () -> Date = Date.init) {
        self.streamDescriptor = streamDescriptor
        self.engineClient = engineClient
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

        handle(.engineReturnedDescriptor)

        // Resume seek if a prior byte offset was persisted.
        if streamDescriptor.resumeByteOffset > 0 {
            scheduleResumeSeek(player: avPlayer, item: item)
        }

        bindAVPlayerObservers(player: avPlayer, item: item)

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
    }

    // MARK: - Private helpers

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
