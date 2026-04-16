import EngineInterface

// Retroactive @unchecked Sendable conformances for XPC DTOs.
//
// All DTO types are final NSObject subclasses with only immutable `let` properties.
// They are decoded fresh by the XPC runtime on each call — no shared mutable state.
// Swift 6 strict concurrency cannot verify this automatically because NSObject is
// not declared Sendable in the SDK, so we assert it here with @unchecked.
//
// If EngineInterface ever adds `@unchecked Sendable` conformances to the DTOs
// directly, this file can be deleted.

extension TorrentSummaryDTO: @unchecked @retroactive Sendable {}
extension TorrentFileDTO: @unchecked @retroactive Sendable {}
extension StreamDescriptorDTO: @unchecked @retroactive Sendable {}
extension FileAvailabilityDTO: @unchecked @retroactive Sendable {}
extension StreamHealthDTO: @unchecked @retroactive Sendable {}
extension DiskPressureDTO: @unchecked @retroactive Sendable {}
extension ByteRangeDTO: @unchecked @retroactive Sendable {}
extension PlaybackHistoryDTO: @unchecked @retroactive Sendable {}
extension FavouriteDTO: @unchecked @retroactive Sendable {}
extension FavouriteChangeDTO: @unchecked @retroactive Sendable {}
