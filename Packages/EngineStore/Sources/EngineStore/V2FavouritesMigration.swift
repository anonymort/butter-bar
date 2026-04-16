import GRDB

/// Adds the `favourites` table for Epic #5 #36. See spec 07 § 4 (Watch state
/// and local library — favourites required feature) and `TASKS.md` Phase 8
/// `T-STORE-FAVOURITES`.
///
/// Independent of `v2_add_completed_at` (A26) — both are additive,
/// named GRDB migrations and apply in registration order. Either can land
/// first.
enum V2FavouritesMigration {
    static let identifier = "v2_add_favourites"

    static func perform(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE favourites (
                torrent_id TEXT NOT NULL,
                file_index INTEGER NOT NULL,
                favourited_at INTEGER NOT NULL,
                PRIMARY KEY (torrent_id, file_index)
            )
            """)
    }
}
