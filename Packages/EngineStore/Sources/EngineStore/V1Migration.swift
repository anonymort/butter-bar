import GRDB

/// Encapsulates the v1 schema migration steps.
///
/// Creates three tables:
/// - `playback_history`: per-file resume offsets and watch state.
/// - `pinned_files`: user-kept files that are never evicted from cache.
/// - `settings`: engine-wide key/value store (JSON-encoded values).
///
/// All timestamps are unix milliseconds (INTEGER). The schema matches
/// `05-cache-policy.md` § Schema and addendum A7 verbatim.
///
/// Usage: register via `DatabaseMigrator.registerMigration(V1Migration.identifier)`.
enum V1Migration {
    static let identifier = "v1"

    static func perform(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE playback_history (
                torrent_id TEXT NOT NULL,
                file_index INTEGER NOT NULL,
                resume_byte_offset INTEGER NOT NULL,
                last_played_at INTEGER NOT NULL,
                total_watched_seconds REAL NOT NULL DEFAULT 0,
                completed INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (torrent_id, file_index)
            )
            """)

        try db.execute(sql: """
            CREATE TABLE pinned_files (
                torrent_id TEXT NOT NULL,
                file_index INTEGER NOT NULL,
                pinned_at INTEGER NOT NULL,
                PRIMARY KEY (torrent_id, file_index)
            )
            """)

        try db.execute(sql: """
            CREATE TABLE settings (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            )
            """)
    }
}
