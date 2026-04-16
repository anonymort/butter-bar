import EngineInterface
import Foundation

/// One stream's playback state inside a `PlayerViewModel`.
///
/// Six cases per the Phase 3 design (`docs/design/player-state-foundation.md`
/// § D2). The pre-open "loading" phase folds into `.buffering(.openingStream)`
/// rather than a 7th `.opening` case — the surface a user sees ("we're waiting
/// on bytes") is the same in both situations; the internal `BufferingReason`
/// distinguishes for telemetry, copy, and tests.
///
/// Carries no `streamID` / `torrentID` / `fileIndex` — identity is owned by
/// the calling `PlayerViewModel`, mirroring `WatchStatus` (Phase 1).
public enum PlayerState: Equatable, Sendable {
    /// Initial and terminal — no descriptor, no AVPlayer attached.
    case closed
    /// Descriptor in hand, AVPlayer attached, rate is 0. The resume-prompt
    /// window. Distinct from `.paused`: `.paused` implies user intent.
    case open
    /// `AVPlayer.rate > 0` and engine tier is not `.starving`.
    case playing
    /// `AVPlayer.rate == 0` because the user paused.
    case paused
    /// Three distinct gates that all render as "we are waiting on bytes".
    case buffering(reason: BufferingReason)
    /// Recoverable from the model's perspective via retry; terminal from
    /// this stream's perspective.
    case error(PlayerError)
}

/// Why we are buffering. See `docs/design/player-state-foundation.md § D2`.
public enum BufferingReason: Equatable, Sendable {
    /// Awaiting the engine's `openStream` reply (replaces a separate
    /// `.opening` state).
    case openingStream
    /// `StreamHealthTier == .starving`.
    case engineStarving
    /// `AVPlayerItem.isPlaybackBufferEmpty == true`.
    case playerRebuffering
}

/// Errors that drive `PlayerState.error(_)`. See design § D2.
public enum PlayerError: Equatable, Sendable {
    /// `engine.openStream` reply contained an `NSError`.
    case streamOpenFailed(EngineErrorCode)
    /// `EngineClient` lost the XPC connection.
    case xpcDisconnected
    /// `AVPlayerItem.status == .failed`.
    case playbackFailed
    /// Engine has stopped serving this stream without telling us. Reserved
    /// for design § Open questions O1; not reachable in v1.
    case streamLost
}
