import Foundation

/// The XPC protocol exported by the app (client) side for engine-pushed events.
/// The engine holds a proxy of this protocol and calls methods on it.
/// Each method's parameter is a versioned DTO (per spec 03 § Protocols).
@objc public protocol EngineEvents {
    func torrentUpdated(_ snapshot: TorrentSummaryDTO)
    func fileAvailabilityChanged(_ update: FileAvailabilityDTO)
    func streamHealthChanged(_ update: StreamHealthDTO)
    func diskPressureChanged(_ update: DiskPressureDTO)
}
