import GRDB

/// A row in the `favourites` table.
///
/// Mirrors `PinnedFileRecord` shape: per-file grain `(torrent_id, file_index)`,
/// with a single `favourited_at` unix-millisecond timestamp. Title-level
/// favouriting is deferred — see #36 § Out of scope.
public struct FavouriteRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "favourites"

    enum CodingKeys: String, CodingKey {
        case torrentId = "torrent_id"
        case fileIndex = "file_index"
        case favouritedAt = "favourited_at"
    }

    /// Torrent info-hash or stable identifier, as assigned by libtorrent.
    public var torrentId: String

    /// Zero-based index of the file within the torrent's file list.
    public var fileIndex: Int

    /// Unix milliseconds when the file was favourited.
    public var favouritedAt: Int64

    public init(torrentId: String, fileIndex: Int, favouritedAt: Int64) {
        self.torrentId = torrentId
        self.fileIndex = fileIndex
        self.favouritedAt = favouritedAt
    }
}
