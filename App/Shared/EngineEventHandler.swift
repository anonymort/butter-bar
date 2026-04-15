import Combine
import Foundation
import EngineInterface

/// Receives engine-pushed XPC events and re-publishes them as Combine subjects.
///
/// XPC delivers callbacks on an arbitrary internal queue. All `EngineEvents`
/// methods are `nonisolated` — they must not touch actor-isolated state.
/// Downstream observers on the `@Published` properties receive values on that
/// same XPC queue; callers that update SwiftUI must hop to the main actor.
///
/// Retained by `EngineClient`; re-used across interruptions (the same handler
/// object is re-subscribed after an engine restart so no publisher subscriptions
/// are broken). Replaced entirely on full invalidation + reconnect.
public final class EngineEventHandler: NSObject, EngineEvents, @unchecked Sendable {

    // MARK: Subjects

    /// Fires whenever the engine emits an updated `TorrentSummaryDTO`.
    public let torrentUpdatedSubject = PassthroughSubject<TorrentSummaryDTO, Never>()

    /// Fires whenever byte-range availability changes for a file.
    public let fileAvailabilityChangedSubject = PassthroughSubject<FileAvailabilityDTO, Never>()

    /// Fires whenever stream health tier or metrics change.
    public let streamHealthChangedSubject = PassthroughSubject<StreamHealthDTO, Never>()

    /// Fires whenever the cache disk-pressure level changes.
    public let diskPressureChangedSubject = PassthroughSubject<DiskPressureDTO, Never>()

    // MARK: EngineEvents conformance

    public func torrentUpdated(_ snapshot: TorrentSummaryDTO) {
        torrentUpdatedSubject.send(snapshot)
    }

    public func fileAvailabilityChanged(_ update: FileAvailabilityDTO) {
        fileAvailabilityChangedSubject.send(update)
    }

    public func streamHealthChanged(_ update: StreamHealthDTO) {
        streamHealthChangedSubject.send(update)
    }

    public func diskPressureChanged(_ update: DiskPressureDTO) {
        diskPressureChangedSubject.send(update)
    }
}
