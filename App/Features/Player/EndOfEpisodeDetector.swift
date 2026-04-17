import Combine
import Foundation
import MetadataDomain
import PlayerDomain

// MARK: - EndOfEpisodeSignal

/// Emitted by `EndOfEpisodeDetector` when an episode reaches its natural end.
/// Consumed by #21 (next-episode auto-play with grace period).
public struct EndOfEpisodeSignal: Equatable, Sendable {
    public let episode: Episode

    public init(episode: Episode) {
        self.episode = episode
    }
}

// MARK: - EndOfEpisodeDetector
//
// Pure detector that observes `PlayerState` transitions plus episode metadata
// and emits an `EndOfEpisodeSignal` when an episode reaches its natural end.
//
// Per the issue #20 AC and `docs/design/player-state-foundation.md § Out of
// scope`, this is a sibling observer of `PlayerState`, not a new state in
// the foundation. The detector does not write watch state — Phase 1's
// `CacheManager` byte-threshold path owns that (spec 05 rev 5, addendum A26).
//
// Trigger (all must hold):
//   1. The transition is `.playing → .closed`.
//   2. The asset is identified as an `Episode` (`episode != nil`).
//   3. Playhead is within `threshold` seconds of asset end.
//
// The publisher hook below lets #21 subscribe; for now it is unwired.

public enum EndOfEpisodeDetector {

    /// Default threshold: how close to the asset's end a `.playing → .closed`
    /// edge must be to count as a natural episode end. 30 s is permissive
    /// enough to absorb credit-roll variance for typical scripted TV.
    public static let defaultThresholdSeconds: Double = 30

    /// Pure decision function. Returns a non-nil signal iff the inputs match
    /// the trigger conditions documented above.
    ///
    /// - Parameters:
    ///   - stateTransition: `(from, to)` pair from the `PlayerState` machine.
    ///   - playheadSeconds: Current playhead in seconds at the moment of the
    ///     transition.
    ///   - durationSeconds: Asset duration in seconds. Must be `> 0`.
    ///   - episode: The `Episode` this asset represents, or `nil` if the
    ///     asset is a movie / unknown / extras.
    ///   - threshold: Tunable proximity-to-end window. Defaults to
    ///     `defaultThresholdSeconds`.
    public static func detect(
        stateTransition: (from: PlayerState, to: PlayerState),
        playheadSeconds: Double,
        durationSeconds: Double,
        episode: Episode?,
        threshold: Double = defaultThresholdSeconds
    ) -> EndOfEpisodeSignal? {
        guard let episode else { return nil }
        guard stateTransition.from == .playing, stateTransition.to == .closed else {
            return nil
        }
        guard durationSeconds > 0 else { return nil }
        let remaining = durationSeconds - playheadSeconds
        guard remaining <= threshold else { return nil }
        return EndOfEpisodeSignal(episode: episode)
    }

    // MARK: - Telemetry hook
    //
    // Shared `PassthroughSubject` for #21's consumer to subscribe to. The
    // detector itself stays pure; whoever drives state transitions calls
    // `detect(...)` and forwards a non-nil result through `publisher.send(_:)`.

    /// Subscribe to receive `EndOfEpisodeSignal` events as the
    /// `PlayerViewModel` (or another driver) projects them. `PassthroughSubject`
    /// is internally thread-safe; the `nonisolated(unsafe)` opt-out lets the
    /// shared instance live as a static `let` under Swift 6 strict concurrency.
    nonisolated(unsafe) public static let publisher = PassthroughSubject<EndOfEpisodeSignal, Never>()
}
