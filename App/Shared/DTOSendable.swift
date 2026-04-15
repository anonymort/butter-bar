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

extension TorrentSummaryDTO: @unchecked Sendable {}
extension TorrentFileDTO: @unchecked Sendable {}
extension StreamDescriptorDTO: @unchecked Sendable {}
extension FileAvailabilityDTO: @unchecked Sendable {}
extension StreamHealthDTO: @unchecked Sendable {}
extension DiskPressureDTO: @unchecked Sendable {}
extension ByteRangeDTO: @unchecked Sendable {}
