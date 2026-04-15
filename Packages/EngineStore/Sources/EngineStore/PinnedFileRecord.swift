import GRDB

/// A row in the `pinned_files` table.
///
/// Represents a file the user has explicitly marked "keep." Pinned files are
/// never evicted from the piece cache regardless of LRU position.
public struct PinnedFileRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "pinned_files"

    // Map Swift camelCase properties to the SQL snake_case column names.
    enum CodingKeys: String, CodingKey {
        case torrentId = "torrent_id"
        case fileIndex = "file_index"
        case pinnedAt = "pinned_at"
    }

    /// Torrent info-hash or stable identifier, as assigned by libtorrent.
    public var torrentId: String

    /// Zero-based index of the file within the torrent's file list.
    public var fileIndex: Int

    /// Unix milliseconds when the file was pinned by the user.
    public var pinnedAt: Int64

    public init(torrentId: String, fileIndex: Int, pinnedAt: Int64) {
        self.torrentId = torrentId
        self.fileIndex = fileIndex
        self.pinnedAt = pinnedAt
    }
}
