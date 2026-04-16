import Foundation

/// Versioned XPC projection of a `playback_history` row (spec 05 rev 5,
/// addendum A26). Carries every column on the table so the app can derive
/// `WatchStatus` without re-querying the engine.
///
/// `completedAt` is `nil` until the file's first completion or after a
/// manual mark-unwatched. `totalWatchedSeconds` stays at 0 in v1 (column
/// reserved for v1.1).
@objc(PlaybackHistoryDTO)
public final class PlaybackHistoryDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32
    public let torrentID: NSString
    public let fileIndex: Int32
    public let resumeByteOffset: Int64
    public let lastPlayedAt: Int64
    public let totalWatchedSeconds: Double
    public let completed: Bool
    /// Unix milliseconds of the most recent completion; `nil` if never completed.
    public let completedAt: NSNumber?

    public init(
        torrentID: NSString,
        fileIndex: Int32,
        resumeByteOffset: Int64,
        lastPlayedAt: Int64,
        totalWatchedSeconds: Double,
        completed: Bool,
        completedAt: NSNumber?
    ) {
        self.schemaVersion = 1
        self.torrentID = torrentID
        self.fileIndex = fileIndex
        self.resumeByteOffset = resumeByteOffset
        self.lastPlayedAt = lastPlayedAt
        self.totalWatchedSeconds = totalWatchedSeconds
        self.completed = completed
        self.completedAt = completedAt
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(torrentID, forKey: "torrentID")
        coder.encode(fileIndex, forKey: "fileIndex")
        coder.encode(resumeByteOffset, forKey: "resumeByteOffset")
        coder.encode(lastPlayedAt, forKey: "lastPlayedAt")
        coder.encode(totalWatchedSeconds, forKey: "totalWatchedSeconds")
        coder.encode(completed, forKey: "completed")
        coder.encode(completedAt, forKey: "completedAt")
    }

    public required init?(coder: NSCoder) {
        schemaVersion = coder.decodeInt32(forKey: "schemaVersion")
        guard let torrentID = coder.decodeObject(of: NSString.self, forKey: "torrentID") else { return nil }
        fileIndex = coder.decodeInt32(forKey: "fileIndex")
        resumeByteOffset = coder.decodeInt64(forKey: "resumeByteOffset")
        lastPlayedAt = coder.decodeInt64(forKey: "lastPlayedAt")
        totalWatchedSeconds = coder.decodeDouble(forKey: "totalWatchedSeconds")
        completed = coder.decodeBool(forKey: "completed")
        completedAt = coder.decodeObject(of: NSNumber.self, forKey: "completedAt")
        self.torrentID = torrentID
    }
}
