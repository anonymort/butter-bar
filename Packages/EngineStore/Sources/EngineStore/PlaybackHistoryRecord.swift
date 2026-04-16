import GRDB

/// A row in the `playback_history` table.
///
/// Tracks per-file watch state. `resumeByteOffset` is the last byte
/// successfully served by the gateway — not a time-accurate seek point
/// (see addendum A6). `totalWatchedSeconds` stays at 0 in v1; it will be
/// populated via XPC in v1.1 once the watched-seconds reporting path exists.
///
/// `completedAt` (A26) is the unix-ms timestamp of the most recent completion,
/// set on every `completed` 0 → 1 transition (incl. re-completions during
/// re-watches). `nil` until the file is completed for the first time, or
/// after a manual mark-unwatched.
public struct PlaybackHistoryRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "playback_history"

    // Map Swift camelCase properties to the SQL snake_case column names.
    enum CodingKeys: String, CodingKey {
        case torrentId = "torrent_id"
        case fileIndex = "file_index"
        case resumeByteOffset = "resume_byte_offset"
        case lastPlayedAt = "last_played_at"
        case totalWatchedSeconds = "total_watched_seconds"
        case completed
        case completedAt = "completed_at"
    }

    /// Torrent info-hash or stable identifier, as assigned by libtorrent.
    public var torrentId: String

    /// Zero-based index of the file within the torrent's file list.
    public var fileIndex: Int

    /// Last byte offset successfully served to the player (unix bytes, not time).
    /// Reset to 0 when `completed` transitions to `true`.
    public var resumeByteOffset: Int64

    /// Unix milliseconds when this file was last opened for playback.
    public var lastPlayedAt: Int64

    /// Cumulative seconds of video watched; populated from CMTime observations in v1.1.
    public var totalWatchedSeconds: Double

    /// `true` when `resumeByteOffset >= 0.95 * file_size` at stream close,
    /// or set explicitly by manual mark-watched.
    /// Stored as INTEGER (0/1) by GRDB's Codable bridge.
    public var completed: Bool

    /// Unix milliseconds of the most recent completion. `nil` until first
    /// completion; cleared by manual mark-unwatched. See A26.
    public var completedAt: Int64?

    public init(
        torrentId: String,
        fileIndex: Int,
        resumeByteOffset: Int64,
        lastPlayedAt: Int64,
        totalWatchedSeconds: Double = 0,
        completed: Bool = false,
        completedAt: Int64? = nil
    ) {
        self.torrentId = torrentId
        self.fileIndex = fileIndex
        self.resumeByteOffset = resumeByteOffset
        self.lastPlayedAt = lastPlayedAt
        self.totalWatchedSeconds = totalWatchedSeconds
        self.completed = completed
        self.completedAt = completedAt
    }
}
