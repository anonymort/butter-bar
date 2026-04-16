/// Bidirectional mapping between XPC DTOs and internal domain types.
/// This is the ONE place where DTO↔domain conversion happens.
/// Neither the app nor the planner should import this module directly —
/// it lives in the engine process, invoked only at the XPC boundary.

import Foundation
import EngineInterface
import PlannerCore

// MARK: - TorrentSummary ↔ TorrentSummaryDTO

extension TorrentSummaryDTO {
    public convenience init(from domain: TorrentSummary) {
        self.init(
            torrentID: domain.torrentID as NSString,
            name: domain.name as NSString,
            totalBytes: domain.totalBytes,
            progressQ16: Int32(domain.progress.clamped(to: 0.0...1.0) * 65536),
            state: domain.state.rawValue as NSString,
            peerCount: Int32(clamping: domain.peerCount),
            downRateBytesPerSec: domain.downRateBytesPerSec,
            upRateBytesPerSec: domain.upRateBytesPerSec,
            errorMessage: domain.errorMessage.map { $0 as NSString }
        )
    }
}

extension TorrentSummary {
    public init(from dto: TorrentSummaryDTO) {
        self.init(
            torrentID: dto.torrentID as String,
            name: dto.name as String,
            totalBytes: dto.totalBytes,
            progress: Double(dto.progressQ16) / 65536.0,
            state: TorrentState(rawValue: dto.state as String) ?? .error,
            peerCount: Int(dto.peerCount),
            downRateBytesPerSec: dto.downRateBytesPerSec,
            upRateBytesPerSec: dto.upRateBytesPerSec,
            errorMessage: dto.errorMessage.map { $0 as String }
        )
    }
}

// MARK: - TorrentFile ↔ TorrentFileDTO

extension TorrentFileDTO {
    public convenience init(from domain: TorrentFile) {
        self.init(
            fileIndex: Int32(clamping: domain.fileIndex),
            path: domain.path as NSString,
            sizeBytes: domain.sizeBytes,
            mimeTypeHint: domain.mimeTypeHint.map { $0 as NSString },
            isPlayableByAVFoundation: domain.isPlayableByAVFoundation
        )
    }
}

extension TorrentFile {
    public init(from dto: TorrentFileDTO) {
        self.init(
            fileIndex: Int(dto.fileIndex),
            path: dto.path as String,
            sizeBytes: dto.sizeBytes,
            mimeTypeHint: dto.mimeTypeHint.map { $0 as String },
            isPlayableByAVFoundation: dto.isPlayableByAVFoundation
        )
    }
}

// MARK: - StreamDescriptor ↔ StreamDescriptorDTO

extension StreamDescriptorDTO {
    public convenience init(from domain: StreamDescriptor) {
        self.init(
            streamID: domain.streamID as NSString,
            loopbackURL: domain.loopbackURL as NSString,
            contentType: domain.contentType as NSString,
            contentLength: domain.contentLength,
            resumeByteOffset: domain.resumeByteOffset
        )
    }
}

extension StreamDescriptor {
    public init(from dto: StreamDescriptorDTO) {
        self.init(
            streamID: dto.streamID as String,
            loopbackURL: dto.loopbackURL as String,
            contentType: dto.contentType as String,
            contentLength: dto.contentLength,
            resumeByteOffset: dto.resumeByteOffset
        )
    }
}

// MARK: - ByteRangeValue ↔ ByteRangeDTO

extension ByteRangeDTO {
    public convenience init(from domain: ByteRangeValue) {
        self.init(startByte: domain.start, endByte: domain.end)
    }
}

extension ByteRangeValue {
    public init(from dto: ByteRangeDTO) {
        self.init(start: dto.startByte, end: dto.endByte)
    }
}

// MARK: - ByteRangeValue ↔ PlannerCore.ByteRange

extension ByteRangeValue {
    /// Bridge to the PlannerCore domain type.
    public init(from byteRange: ByteRange) {
        self.init(start: byteRange.start, end: byteRange.end)
    }

    /// Bridge to the PlannerCore domain type.
    public func asByteRange() -> ByteRange {
        ByteRange(start: start, end: end)
    }
}

// MARK: - FileAvailability ↔ FileAvailabilityDTO

extension FileAvailabilityDTO {
    public convenience init(from domain: FileAvailability) {
        self.init(
            torrentID: domain.torrentID as NSString,
            fileIndex: Int32(clamping: domain.fileIndex),
            availableRanges: domain.availableRanges.map { ByteRangeDTO(from: $0) }
        )
    }
}

extension FileAvailability {
    public init(from dto: FileAvailabilityDTO) {
        self.init(
            torrentID: dto.torrentID as String,
            fileIndex: Int(dto.fileIndex),
            availableRanges: dto.availableRanges.map { ByteRangeValue(from: $0) }
        )
    }
}

// MARK: - StreamHealth ↔ StreamHealthDTO
//
// StreamHealth (PlannerCore) carries health metrics only. StreamHealthDTO carries an
// additional streamID for transport routing. The streamID must be supplied separately
// when converting domain → DTO; it is discarded when converting DTO → domain.

extension StreamHealthDTO {
    /// Construct a DTO from a domain health snapshot, attaching the stream context.
    public convenience init(streamID: String, from domain: StreamHealth) {
        let tier = StreamHealthTier(rawValue: domain.tier.rawValue) ?? .starving
        self.init(
            streamID: streamID as NSString,
            secondsBufferedAhead: domain.secondsBufferedAhead,
            downloadRateBytesPerSec: domain.downloadRateBytesPerSec,
            requiredBitrateBytesPerSec: domain.requiredBitrateBytesPerSec.map { NSNumber(value: $0) },
            peerCount: Int32(clamping: domain.peerCount),
            outstandingCriticalPieces: Int32(clamping: domain.outstandingCriticalPieces),
            recentStallCount: Int32(clamping: domain.recentStallCount),
            tier: tier
        )
    }
}

extension StreamHealth {
    /// Extract health metrics from the DTO, discarding the streamID transport field.
    public init(from dto: StreamHealthDTO) {
        self.init(
            secondsBufferedAhead: dto.secondsBufferedAhead,
            downloadRateBytesPerSec: dto.downloadRateBytesPerSec,
            requiredBitrateBytesPerSec: dto.requiredBitrateBytesPerSec.map { $0.int64Value },
            peerCount: Int(dto.peerCount),
            outstandingCriticalPieces: Int(dto.outstandingCriticalPieces),
            recentStallCount: Int(dto.recentStallCount),
            tier: StreamHealth.Tier(rawValue: dto.tierValue.rawValue) ?? .starving
        )
    }
}

// MARK: - DiskPressure ↔ DiskPressureDTO

extension DiskPressureDTO {
    public convenience init(from domain: DiskPressure) {
        self.init(
            totalBudgetBytes: domain.totalBudgetBytes,
            usedBytes: domain.usedBytes,
            pinnedBytes: domain.pinnedBytes,
            evictableBytes: domain.evictableBytes,
            level: domain.level.rawValue as NSString
        )
    }
}

extension DiskPressure {
    public init(from dto: DiskPressureDTO) {
        self.init(
            totalBudgetBytes: dto.totalBudgetBytes,
            usedBytes: dto.usedBytes,
            pinnedBytes: dto.pinnedBytes,
            evictableBytes: dto.evictableBytes,
            level: DiskPressureLevel(rawValue: dto.level as String) ?? .critical
        )
    }
}

// MARK: - PlaybackHistorySnapshot ↔ PlaybackHistoryDTO (A26)

extension PlaybackHistoryDTO {
    public convenience init(from domain: PlaybackHistorySnapshot) {
        self.init(
            torrentID: domain.torrentID as NSString,
            fileIndex: Int32(clamping: domain.fileIndex),
            resumeByteOffset: domain.resumeByteOffset,
            lastPlayedAt: domain.lastPlayedAtMillis,
            totalWatchedSeconds: domain.totalWatchedSeconds,
            completed: domain.completed,
            completedAt: domain.completedAtMillis.map { NSNumber(value: $0) }
        )
    }
}

extension PlaybackHistorySnapshot {
    public init(from dto: PlaybackHistoryDTO) {
        self.init(
            torrentID: dto.torrentID as String,
            fileIndex: Int(dto.fileIndex),
            resumeByteOffset: dto.resumeByteOffset,
            lastPlayedAtMillis: dto.lastPlayedAt,
            totalWatchedSeconds: dto.totalWatchedSeconds,
            completed: dto.completed,
            completedAtMillis: dto.completedAt?.int64Value
        )
    }
}

// MARK: - Helpers

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension Int32 {
    /// Saturating narrowing from Int to Int32.
    init(clamping value: Int) {
        if value > Int(Int32.max) {
            self = Int32.max
        } else if value < Int(Int32.min) {
            self = Int32.min
        } else {
            self = Int32(value)
        }
    }
}
