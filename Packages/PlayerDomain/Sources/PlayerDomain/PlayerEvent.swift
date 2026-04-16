import EngineInterface
import Foundation

/// Inputs to the `PlayerStateMachine`. Projected from engine events, AVKit
/// signals, and user actions by the calling `PlayerViewModel` per design
/// `docs/design/player-state-foundation.md § D5`.
///
/// The machine never imports AVKit and never inspects a `StreamHealthDTO`
/// directly — projection happens at the VM, the typed event arrives here.
public enum PlayerEvent: Equatable, Sendable {

    // MARK: - User actions

    /// User asked to open the file (e.g. tapped a row in the library).
    case userRequestedOpen
    /// User tapped the play button in the overlay.
    case userTappedPlay
    /// User tapped the pause button in the overlay.
    case userTappedPause
    /// User tapped close / dismissed the player window.
    case userTappedClose
    /// User tapped "Retry" from an error state (#26).
    case userTappedRetry

    // MARK: - Engine signals

    /// `engine.openStream` reply with a non-nil descriptor.
    /// The descriptor itself is held by the VM; the machine only needs to
    /// know the open succeeded.
    case engineReturnedDescriptor
    /// `engine.openStream` reply with a non-nil `NSError`.
    case engineReturnedOpenError(EngineErrorCode)
    /// `EngineEvents.streamHealthChanged(dto)` filtered to this stream.
    /// Tier converted to the typed enum at the mapping layer.
    case engineHealthChanged(StreamHealthTier)
    /// `EngineClient.events` went `valid → nil` (edge-triggered).
    case engineDisconnected
    /// `EngineClient.events` went `nil → valid` (edge-triggered).
    case engineReconnected

    // MARK: - AVKit signals

    /// `AVPlayer.timeControlStatus` rose to `.playing`.
    case avPlayerBeganPlaying
    /// `AVPlayerItem.isPlaybackBufferEmpty` rose edge.
    case avPlayerStalled
    /// `AVPlayerItem.isPlaybackLikelyToKeepUp` rose edge after a stall.
    case avPlayerResumed
    /// `AVPlayerItem.status` → `.failed`.
    case avPlayerFailed
}
