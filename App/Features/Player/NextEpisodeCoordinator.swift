import Combine
import Foundation
import MetadataDomain

// MARK: - NextEpisodeOffer

/// Data backing the "Up next" surface. Carries the next episode and an
/// optional artwork URL (the coordinator resolves `stillPath` through the
/// metadata provider's `imageURL(path:size:)`).
struct NextEpisodeOffer: Equatable {
    let next: Episode
    let artworkURL: URL?
}

// MARK: - CountdownClock

/// Minimal clock seam. Production uses `WallClock` (real time, real
/// `Task.sleep`); tests inject `TestClock` so countdowns run instantly.
///
/// The contract is intentionally narrow: schedule a one-shot fire after
/// `seconds` and return a cancellation handle. `cancel()` must be safe to
/// call from any actor; the closure always lands on the main actor.
protocol CountdownClock: AnyObject {
    /// Schedule `fire` to run on the main actor after `seconds`. Returns a
    /// cancellation handle whose only side effect is invalidating the
    /// pending fire.
    func schedule(after seconds: TimeInterval, fire: @escaping @MainActor () -> Void) -> CountdownHandle
}

/// Opaque cancellation handle for a scheduled countdown.
final class CountdownHandle {
    private let cancelImpl: () -> Void
    init(_ cancelImpl: @escaping () -> Void) { self.cancelImpl = cancelImpl }
    func cancel() { cancelImpl() }
}

/// Production clock — real time via `Task.sleep`.
final class WallClock: CountdownClock {
    func schedule(after seconds: TimeInterval, fire: @escaping @MainActor () -> Void) -> CountdownHandle {
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            } catch {
                return // cancelled
            }
            await fire()
        }
        return CountdownHandle { task.cancel() }
    }
}

/// Test clock — fires on `advance(by:)` if the elapsed virtual time meets
/// or exceeds the scheduled deadline. Multiple pending fires are supported
/// but the coordinator only ever schedules one at a time.
final class TestClock: CountdownClock, @unchecked Sendable {
    private struct Pending {
        let deadline: TimeInterval
        let fire: @MainActor () -> Void
        var cancelled: Bool
    }

    private var now: TimeInterval = 0
    private var pendings: [UUID: Pending] = [:]

    func schedule(after seconds: TimeInterval, fire: @escaping @MainActor () -> Void) -> CountdownHandle {
        let id = UUID()
        pendings[id] = Pending(deadline: now + seconds, fire: fire, cancelled: false)
        return CountdownHandle { [weak self] in
            self?.pendings[id]?.cancelled = true
        }
    }

    /// Advance virtual time. Any pending fire whose deadline is now in the
    /// past dispatches synchronously to the main actor.
    func advance(by seconds: TimeInterval) {
        now += seconds
        let due = pendings.filter { !$0.value.cancelled && $0.value.deadline <= now }
        for (id, p) in due {
            pendings.removeValue(forKey: id)
            // Hop to main actor so the coordinator's @Published mutations
            // happen where the runtime expects.
            Task { @MainActor in p.fire() }
        }
    }
}

// MARK: - NextEpisodeCoordinator

/// Owns the "Up next" surface lifecycle (#21). Subscribes to
/// `EndOfEpisodeDetector.publisher`, resolves the next episode through the
/// injected `MetadataProvider`, and runs the user-cancellable grace
/// countdown that ends in `openStream(nextEpisode)`.
///
/// Lifetime: one instance per top-level player host (e.g. `PlayerView`).
/// A fresh `PlayerViewModel` is constructed for the next episode by the
/// `openStream` closure — the coordinator never mutates the previous VM.
@MainActor
final class NextEpisodeCoordinator: ObservableObject {

    // MARK: Tunables

    /// Default grace period before the next episode auto-plays. Tunable
    /// here per AC ("tunable constant in one file"). 10 s matches the
    /// register set by mainstream streamers and stays inside the calm
    /// brand voice.
    static let defaultCountdownSeconds: TimeInterval = 10

    // MARK: Published

    /// Non-nil while the "Up next" surface is on screen. The view binds to
    /// this and renders `UpNextOverlay`.
    @Published private(set) var offer: NextEpisodeOffer?

    /// Whole seconds left in the grace period — drives the countdown
    /// indicator. `0` means the auto-play has fired (or the surface is
    /// dismissed).
    @Published private(set) var secondsRemaining: Int = 0

    // MARK: Dependencies

    private let metadata: MetadataProvider
    private let countdownSeconds: TimeInterval
    private let clock: CountdownClock
    /// Hand-off to the host. The closure typically constructs a fresh
    /// `PlayerViewModel` against `engine.openStream(...)`.
    private let openStream: (Episode) -> Void

    // MARK: Internal

    private var subscription: AnyCancellable?
    private var fireHandle: CountdownHandle?
    private var tickHandle: CountdownHandle?
    private var lookupTask: Task<Void, Never>?

    // MARK: - Init

    init(metadata: MetadataProvider,
         countdownSeconds: TimeInterval = NextEpisodeCoordinator.defaultCountdownSeconds,
         clock: CountdownClock = WallClock(),
         openStream: @escaping (Episode) -> Void) {
        self.metadata = metadata
        self.countdownSeconds = countdownSeconds
        self.clock = clock
        self.openStream = openStream

        subscription = EndOfEpisodeDetector.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signal in
                self?.handle(signal)
            }
    }

    deinit {
        // Combine subscription and clock handles all hold weak refs back
        // to the coordinator; explicit cancellation here keeps lingering
        // tests deterministic. (Cannot touch @MainActor isolated state from
        // deinit, so just drop the references — the handles release naturally.)
    }

    // MARK: - Public actions

    /// User tapped "Cancel". Dismiss the surface and abandon any pending
    /// auto-play. Player remains in `.closed`; no `openStream` is invoked.
    func cancel() {
        teardownPending()
        offer = nil
        secondsRemaining = 0
    }

    /// User tapped "Play now". Cancel the countdown and immediately fire
    /// the open path. The surface dismisses synchronously so the host can
    /// hand off to a fresh `PlayerViewModel` without a perceived gap.
    func playNow() {
        guard let next = offer?.next else { return }
        teardownPending()
        offer = nil
        secondsRemaining = 0
        openStream(next)
    }

    // MARK: - Signal handling

    private func handle(_ signal: EndOfEpisodeSignal) {
        // If a previous offer is still on screen (rare but possible when
        // the user lets one auto-play stack into another), drop it before
        // starting the new lookup so state stays single-tenant.
        teardownPending()
        offer = nil

        let finished = signal.episode
        lookupTask = Task { [weak self] in
            guard let self else { return }
            let next = await self.lookupNextEpisode(after: finished)
            guard let next else { return }
            await MainActor.run {
                self.present(next: next)
            }
        }
    }

    /// Resolve the next episode for `finished`. Same season first; if that
    /// is exhausted, consult `showDetail` and pick the first episode of
    /// the next season. Any provider error returns `nil` — the player
    /// will close normally per AC.
    private func lookupNextEpisode(after finished: Episode) async -> Episode? {
        do {
            let season = try await metadata.seasonDetail(showID: finished.showID,
                                                         season: finished.seasonNumber)
            // Sort defensively — TMDB usually returns sorted but the
            // schema doesn't guarantee it.
            let sorted = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
            if let next = sorted.first(where: { $0.episodeNumber > finished.episodeNumber }) {
                return next
            }
        } catch {
            return nil
        }

        // End of season — try the next season via showDetail.
        do {
            let show = try await metadata.showDetail(id: finished.showID)
            let nextSeasons = show.seasons
                .filter { $0.seasonNumber > finished.seasonNumber }
                .sorted { $0.seasonNumber < $1.seasonNumber }
            for nextSeason in nextSeasons {
                // The show's `seasons` may be lazily populated without
                // episode lists. Hydrate via seasonDetail when empty.
                let episodes: [Episode]
                if !nextSeason.episodes.isEmpty {
                    episodes = nextSeason.episodes
                } else {
                    let hydrated = try await metadata.seasonDetail(
                        showID: finished.showID,
                        season: nextSeason.seasonNumber
                    )
                    episodes = hydrated.episodes
                }
                if let first = episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber }).first {
                    return first
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    // MARK: - Surface presentation + countdown

    private func present(next: Episode) {
        let artworkURL = next.stillPath.map { metadata.imageURL(path: $0, size: .w300) }
        offer = NextEpisodeOffer(next: next, artworkURL: artworkURL)
        secondsRemaining = Int(countdownSeconds.rounded(.up))
        scheduleTick()
        scheduleAutoPlay(next: next)
    }

    /// Schedule the auto-play fire at the end of the grace period. A
    /// single deadline through the injected clock keeps tests deterministic.
    private func scheduleAutoPlay(next: Episode) {
        fireHandle?.cancel()
        fireHandle = clock.schedule(after: countdownSeconds) { [weak self] in
            guard let self, self.offer?.next == next else { return }
            self.offer = nil
            self.secondsRemaining = 0
            self.openStream(next)
        }
    }

    /// Tick the countdown indicator once a second so the user sees the
    /// number decrement. Re-schedules itself; cancelled by `teardownPending`.
    private func scheduleTick() {
        tickHandle?.cancel()
        guard secondsRemaining > 0 else { return }
        tickHandle = clock.schedule(after: 1) { [weak self] in
            guard let self, self.offer != nil else { return }
            if self.secondsRemaining > 0 {
                self.secondsRemaining -= 1
            }
            self.scheduleTick()
        }
    }

    private func teardownPending() {
        fireHandle?.cancel()
        fireHandle = nil
        tickHandle?.cancel()
        tickHandle = nil
        lookupTask?.cancel()
        lookupTask = nil
    }
}
