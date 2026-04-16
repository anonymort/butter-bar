import Foundation

/// The XPC protocol exported by the app (client) side for engine-pushed events.
/// The engine holds a proxy of this protocol and calls methods on it.
/// Each method's parameter is a versioned DTO (per spec 03 § Protocols).
@objc public protocol EngineEvents {
    func torrentUpdated(_ snapshot: TorrentSummaryDTO)
    func fileAvailabilityChanged(_ update: FileAvailabilityDTO)
    func streamHealthChanged(_ update: StreamHealthDTO)
    func diskPressureChanged(_ update: DiskPressureDTO)

    /// Emitted exactly once per `playback_history` row write (15 s tick during
    /// playback, stream close, or manual mark-watched / mark-unwatched).
    /// See spec 05 § Update rules and addendum A26.
    func playbackHistoryChanged(_ update: PlaybackHistoryDTO)
}
