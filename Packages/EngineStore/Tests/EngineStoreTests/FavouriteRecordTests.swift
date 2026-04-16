import XCTest
import GRDB
@testable import EngineStore

final class FavouriteRecordTests: XCTestCase {

    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try EngineDatabase.openInMemory()
    }

    func testRoundTripInsertFetch() throws {
        let record = FavouriteRecord(
            torrentId: "fav-1",
            fileIndex: 3,
            favouritedAt: 1_700_000_111_000
        )
        try queue.write { db in try record.insert(db) }

        let fetched = try queue.read { db in
            try FavouriteRecord.fetchOne(
                db,
                sql: "SELECT * FROM favourites WHERE torrent_id = ? AND file_index = ?",
                arguments: ["fav-1", 3]
            )
        }

        XCTAssertEqual(fetched?.torrentId, "fav-1")
        XCTAssertEqual(fetched?.fileIndex, 3)
        XCTAssertEqual(fetched?.favouritedAt, 1_700_000_111_000)
    }

    func testPrimaryKeyConflictReplacesRow() throws {
        // GRDB's default PersistableRecord.save uses INSERT OR ABORT for new
        // rows. For an upsert pattern callers must call .save() which falls
        // back to UPDATE if INSERT throws on PK conflict. Verify that
        // saving an updated row replaces the timestamp without throwing.
        let r1 = FavouriteRecord(torrentId: "fav-2", fileIndex: 0,
                                 favouritedAt: 1_700_000_001_000)
        try queue.write { db in try r1.insert(db) }

        let r2 = FavouriteRecord(torrentId: "fav-2", fileIndex: 0,
                                 favouritedAt: 1_700_000_999_000)
        try queue.write { db in try r2.save(db) }

        let fetched = try queue.read { db in
            try FavouriteRecord.fetchOne(
                db,
                sql: "SELECT * FROM favourites WHERE torrent_id = ? AND file_index = ?",
                arguments: ["fav-2", 0]
            )
        }
        XCTAssertEqual(fetched?.favouritedAt, 1_700_000_999_000)
    }

    func testDeleteRemovesRow() throws {
        let record = FavouriteRecord(torrentId: "fav-3", fileIndex: 0,
                                     favouritedAt: 1_700_000_002_000)
        try queue.write { db in try record.insert(db) }

        try queue.write { db in
            _ = try FavouriteRecord
                .filter(Column("torrent_id") == "fav-3" && Column("file_index") == 0)
                .deleteAll(db)
        }

        let fetched = try queue.read { db in
            try FavouriteRecord.fetchOne(
                db,
                sql: "SELECT * FROM favourites WHERE torrent_id = ? AND file_index = ?",
                arguments: ["fav-3", 0]
            )
        }
        XCTAssertNil(fetched)
    }

    func testTableExistsAfterMigration() throws {
        try queue.read { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'favourites'"
            )
            XCTAssertEqual(tables, ["favourites"])
        }
    }
}

// MARK: - Migration ordering / idempotency

final class V2FavouritesMigrationTests: XCTestCase {

    func testFavouritesMigrationIdempotent() throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration(V1Migration.identifier) { db in
            try V1Migration.perform(db)
        }
        migrator.registerMigration(V2FavouritesMigration.identifier) { db in
            try V2FavouritesMigration.perform(db)
        }
        try migrator.migrate(queue)
        try migrator.migrate(queue) // re-run; must be no-op

        try queue.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM grdb_migrations WHERE identifier = ?",
                arguments: [V2FavouritesMigration.identifier]
            )
            XCTAssertEqual(count, 1, "favourites migration recorded more than once")
        }
    }

    func testFavouritesMigrationIndependentOfCompletedAt() throws {
        // Apply only V1 + favourites (skip v2_add_completed_at) and verify
        // both succeed. This proves the two named migrations are independent.
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration(V1Migration.identifier) { db in
            try V1Migration.perform(db)
        }
        migrator.registerMigration(V2FavouritesMigration.identifier) { db in
            try V2FavouritesMigration.perform(db)
        }
        try migrator.migrate(queue)

        try queue.read { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
            XCTAssertTrue(tables.contains("favourites"))
            XCTAssertTrue(tables.contains("playback_history"))
            // Verify completed_at column is NOT present (v2_add_completed_at skipped).
            let columns = try Row.fetchAll(
                db,
                sql: "PRAGMA table_info(playback_history)"
            ).compactMap { $0["name"] as String? }
            XCTAssertFalse(columns.contains("completed_at"),
                           "completed_at must not exist when only favourites migration is applied")
        }
    }

    func testFreshDatabaseGetsAllMigrations() throws {
        // EngineDatabase.openInMemory registers all three; verify they all apply.
        let queue = try EngineDatabase.openInMemory()
        try queue.read { db in
            let recorded = try String.fetchAll(
                db,
                sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier"
            )
            XCTAssertEqual(recorded, ["v1", "v2_add_completed_at", "v2_add_favourites"])
        }
    }
}
