// CacheEviction.swift — types and protocol for cache eviction.
//
// All types here are consumed by CacheManager (eviction extension in
// CacheManager.swift). The CacheManagerBridge protocol lets tests inject a
// mock without referencing the real ObjC++ bridge.

import Foundation

// MARK: - EvictionCandidate

/// Single-file eviction candidate. The caller (RealEngineBackend) computes these
/// from libtorrent's torrent list + playback history, filtered to exclude the
/// pinned set.
public struct EvictionCandidate: Sendable {
    public let torrentId: String
    public let fileIndex: Int
    /// Absolute path to the sparse file on disk.
    public let onDiskPath: String
    /// Byte offset of this file's start within the torrent (from bridge.fileByteRange).
    public let fileStartInTorrent: Int64
    /// Exclusive byte offset of this file's end within the torrent.
    public let fileEndInTorrent: Int64
    public let pieceLength: Int64
    /// nil if no playback history exists for this file.
    public let lastPlayedAtMs: Int64?
    /// true when resumeByteOffset >= 0.95 * fileSize (spec 05 § completed column).
    public let completed: Bool
    /// Eviction priority tier 1–4 per spec 05 § Eviction order.
    public let tierRank: Int

    public init(
        torrentId: String,
        fileIndex: Int,
        onDiskPath: String,
        fileStartInTorrent: Int64,
        fileEndInTorrent: Int64,
        pieceLength: Int64,
        lastPlayedAtMs: Int64?,
        completed: Bool,
        tierRank: Int
    ) {
        self.torrentId = torrentId
        self.fileIndex = fileIndex
        self.onDiskPath = onDiskPath
        self.fileStartInTorrent = fileStartInTorrent
        self.fileEndInTorrent = fileEndInTorrent
        self.pieceLength = pieceLength
        self.lastPlayedAtMs = lastPlayedAtMs
        self.completed = completed
        self.tierRank = tierRank
    }
}

// MARK: - CacheManagerBridge

/// The slice of TorrentBridge that CacheManager needs for eviction.
/// A protocol so tests can inject a mock without the real ObjC++ bridge.
public protocol CacheManagerBridge: AnyObject {
    func setFilePriority(torrentID: String, fileIndex: Int, priority: Int) throws
    func forceRecheck(torrentID: String) throws
    /// Returns the torrent's current libtorrent state string.
    /// Expected values include: "downloading", "finished", "checkingFiles",
    /// "checkingResumeData", "seeding", "allocating", "checkingFastResume".
    func statusState(torrentID: String) throws -> String
}

// MARK: - TorrentBridgeCacheAdapter

/// Adapts the real ObjC++ TorrentBridge to CacheManagerBridge.
/// The real bridge's statusSnapshot returns an NSDictionary; this extracts "state".
public final class TorrentBridgeCacheAdapter: CacheManagerBridge {
    private let bridge: TorrentBridge

    public init(bridge: TorrentBridge) {
        self.bridge = bridge
    }

    public func setFilePriority(torrentID: String, fileIndex: Int, priority: Int) throws {
        try bridge.setFilePriority(torrentID, fileIndex: Int32(fileIndex), priority: Int32(priority))
    }

    public func forceRecheck(torrentID: String) throws {
        try bridge.forceRecheck(torrentID)
    }

    public func statusState(torrentID: String) throws -> String {
        let snapshot = try bridge.statusSnapshot(torrentID) as NSDictionary?
        guard let snap = snapshot,
              let state = snap["state"] as? String else {
            // No snapshot or no state key. The most common cause is the
            // torrent having been removed; torrentNotFound is the honest code.
            throw NSError(
                domain: TorrentBridgeErrorDomain,
                code: Int(TorrentBridgeError.torrentNotFound.rawValue),
                userInfo: [NSLocalizedDescriptionKey: "statusSnapshot missing or malformed for \(torrentID)"]
            )
        }
        return state
    }
}

// MARK: - DiskPressure

/// Pressure classification per spec 05 § Disk pressure signalling.
public enum DiskPressure: String, Sendable {
    case ok
    case warn
    case critical
}

// MARK: - EvictionPassResult

/// Result of a single runEvictionPass call.
public struct EvictionPassResult: Sendable {
    public let candidatesEvicted: Int
    public let torrentsRechecked: Int
    public let bytesReclaimed: Int64
    public let usedBytesAfter: Int64
    public let pressureBefore: DiskPressure
    public let pressureAfter: DiskPressure
    public let durationSeconds: Double
    /// Non-fatal per-candidate failure messages.
    public let errors: [String]
}
