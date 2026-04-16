/// Domain types used internally by EngineService. These are plain Swift value types —
/// no NSObject, no NSSecureCoding, no @objc. They never cross the XPC boundary directly;
/// Mapping.swift converts them to/from DTOs at the boundary.

// MARK: - TorrentSummary

public struct TorrentSummary: Sendable, Hashable {
    public let torrentID: String
    public let name: String
    public let totalBytes: Int64
    /// 0.0...1.0
    public let progress: Double
    public let state: TorrentState
    public let peerCount: Int
    public let downRateBytesPerSec: Int64
    public let upRateBytesPerSec: Int64
    public let errorMessage: String?

    public init(
        torrentID: String,
        name: String,
        totalBytes: Int64,
        progress: Double,
        state: TorrentState,
        peerCount: Int,
        downRateBytesPerSec: Int64,
        upRateBytesPerSec: Int64,
        errorMessage: String?
    ) {
        self.torrentID = torrentID
        self.name = name
        self.totalBytes = totalBytes
        self.progress = progress
        self.state = state
        self.peerCount = peerCount
        self.downRateBytesPerSec = downRateBytesPerSec
        self.upRateBytesPerSec = upRateBytesPerSec
        self.errorMessage = errorMessage
    }
}

public enum TorrentState: String, Sendable, Hashable, CaseIterable {
    case queued
    case checking
    case downloading
    case seeding
    case error
}

// MARK: - TorrentFile

public struct TorrentFile: Sendable, Hashable {
    public let fileIndex: Int
    public let path: String
    public let sizeBytes: Int64
    public let mimeTypeHint: String?
    public let isPlayableByAVFoundation: Bool

    public init(
        fileIndex: Int,
        path: String,
        sizeBytes: Int64,
        mimeTypeHint: String?,
        isPlayableByAVFoundation: Bool
    ) {
        self.fileIndex = fileIndex
        self.path = path
        self.sizeBytes = sizeBytes
        self.mimeTypeHint = mimeTypeHint
        self.isPlayableByAVFoundation = isPlayableByAVFoundation
    }
}

// MARK: - StreamDescriptor

public struct StreamDescriptor: Sendable, Hashable {
    public let streamID: String
    public let loopbackURL: String
    public let contentType: String
    public let contentLength: Int64
    /// Last byte offset successfully served to the player during a prior session, or 0 if no
    /// prior play history. See spec 05 § Resume offset persistence.
    public let resumeByteOffset: Int64

    public init(
        streamID: String,
        loopbackURL: String,
        contentType: String,
        contentLength: Int64,
        resumeByteOffset: Int64 = 0
    ) {
        self.streamID = streamID
        self.loopbackURL = loopbackURL
        self.contentType = contentType
        self.contentLength = contentLength
        self.resumeByteOffset = resumeByteOffset
    }
}

// MARK: - FileAvailability

public struct FileAvailability: Sendable, Hashable {
    public let torrentID: String
    public let fileIndex: Int
    /// Fully downloaded byte ranges, coalesced, inclusive on both ends.
    public let availableRanges: [ByteRangeValue]

    public init(torrentID: String, fileIndex: Int, availableRanges: [ByteRangeValue]) {
        self.torrentID = torrentID
        self.fileIndex = fileIndex
        self.availableRanges = availableRanges
    }
}

/// Plain-value byte range used in domain types.
/// Mirrors PlannerCore.ByteRange but avoids a cross-module dependency for consumers
/// that only need domain types. Mapping.swift bridges between the two.
public struct ByteRangeValue: Sendable, Hashable {
    /// Inclusive start byte.
    public let start: Int64
    /// Inclusive end byte.
    public let end: Int64

    public init(start: Int64, end: Int64) {
        self.start = start
        self.end = end
    }
}

// MARK: - DiskPressure

public struct DiskPressure: Sendable, Hashable {
    public let totalBudgetBytes: Int64
    public let usedBytes: Int64
    public let pinnedBytes: Int64
    public let evictableBytes: Int64
    public let level: DiskPressureLevel

    public init(
        totalBudgetBytes: Int64,
        usedBytes: Int64,
        pinnedBytes: Int64,
        evictableBytes: Int64,
        level: DiskPressureLevel
    ) {
        self.totalBudgetBytes = totalBudgetBytes
        self.usedBytes = usedBytes
        self.pinnedBytes = pinnedBytes
        self.evictableBytes = evictableBytes
        self.level = level
    }
}

public enum DiskPressureLevel: String, Sendable, Hashable, CaseIterable {
    case ok
    case warn
    case critical
}

// MARK: - PlaybackHistorySnapshot (A26)

/// Engine-internal projection of a `playback_history` row. Crosses the XPC
/// boundary as `PlaybackHistoryDTO`. See spec 05 rev 5 § Schema and addendum
/// A26.
public struct PlaybackHistorySnapshot: Sendable, Hashable {
    public let torrentID: String
    public let fileIndex: Int
    public let resumeByteOffset: Int64
    public let lastPlayedAtMillis: Int64
    public let totalWatchedSeconds: Double
    public let completed: Bool
    /// Unix milliseconds of the most recent completion; `nil` if never completed.
    public let completedAtMillis: Int64?

    public init(
        torrentID: String,
        fileIndex: Int,
        resumeByteOffset: Int64,
        lastPlayedAtMillis: Int64,
        totalWatchedSeconds: Double,
        completed: Bool,
        completedAtMillis: Int64?
    ) {
        self.torrentID = torrentID
        self.fileIndex = fileIndex
        self.resumeByteOffset = resumeByteOffset
        self.lastPlayedAtMillis = lastPlayedAtMillis
        self.totalWatchedSeconds = totalWatchedSeconds
        self.completed = completed
        self.completedAtMillis = completedAtMillis
    }
}
