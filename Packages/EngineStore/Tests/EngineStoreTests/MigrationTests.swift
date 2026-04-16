import XCTest
import GRDB
@testable import EngineStore

final class MigrationTests: XCTestCase {

    // MARK: - Migration runs cleanly

    func testMigrationRunsOnFreshDatabase() throws {
        // If this throws, the migration itself is broken.
        let queue = try EngineDatabase.openInMemory()

        // Verify all three tables exist by querying sqlite_master.
        try queue.read { db in
            let tables = try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
            )
            XCTAssertTrue(tables.contains("playback_history"), "playback_history table missing")
            XCTAssertTrue(tables.contains("pinned_files"), "pinned_files table missing")
            XCTAssertTrue(tables.contains("settings"), "settings table missing")
        }
    }

    // MARK: - Idempotency

    func testMigrationIsIdempotent() throws {
        // GRDB's DatabaseMigrator tracks applied migrations in `grdb_migrations`.
        // Running migrate() twice must not throw or apply V1 a second time.
        let queue = try DatabaseQueue()

        var migrator = DatabaseMigrator()
        migrator.registerMigration(V1Migration.identifier) { db in
            try V1Migration.perform(db)
        }

        try migrator.migrate(queue)
        // Running again must be a no-op, not a "table already exists" error.
        try migrator.migrate(queue)

        try queue.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM grdb_migrations"
            )
            // Exactly one migration should be recorded, not two.
            XCTAssertEqual(count, 1, "migration recorded more than once")
        }
    }

    // MARK: - Schema version recorded

    func testSchemaVersionRecordedInMigrationsTable() throws {
        let queue = try EngineDatabase.openInMemory()

        try queue.read { db in
            let identifier = try String.fetchOne(
                db,
                sql: "SELECT identifier FROM grdb_migrations WHERE identifier = 'v1'"
            )
            XCTAssertEqual(identifier, "v1", "v1 migration not recorded in grdb_migrations")
        }
    }

    // MARK: - V2 (A26 — completed_at column)

    func testV2AddsCompletedAtColumn() throws {
        let queue = try EngineDatabase.openInMemory()

        try queue.read { db in
            let columns = try Row.fetchAll(
                db,
                sql: "PRAGMA table_info(playback_history)"
            ).compactMap { $0["name"] as String? }
            XCTAssertTrue(columns.contains("completed_at"),
                          "playback_history.completed_at column missing after V2 migration")
        }
    }

    func testV2IsIdempotent() throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration(V1Migration.identifier) { db in
            try V1Migration.perform(db)
        }
        migrator.registerMigration(V2Migration.identifier) { db in
            try V2Migration.perform(db)
        }
        try migrator.migrate(queue)
        try migrator.migrate(queue) // re-run; must be no-op

        try queue.read { db in
            let count = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM grdb_migrations WHERE identifier = ?",
                arguments: [V2Migration.identifier]
            )
            XCTAssertEqual(count, 1, "V2 migration recorded more than once")
        }
    }

    func testV2UpgradesV1OnlyDatabasePreservingRows() throws {
        // Build a V1-only DB, insert a row, then apply V2 and verify the row
        // survives with completed_at == NULL.
        let queue = try DatabaseQueue()
        var v1Migrator = DatabaseMigrator()
        v1Migrator.registerMigration(V1Migration.identifier) { db in
            try V1Migration.perform(db)
        }
        try v1Migrator.migrate(queue)

        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO playback_history
                (torrent_id, file_index, resume_byte_offset, last_played_at, total_watched_seconds, completed)
                VALUES ('legacy-row', 0, 1024, 1700000000000, 0, 1)
                """)
        }

        // Upgrade to V2.
        var fullMigrator = DatabaseMigrator()
        fullMigrator.registerMigration(V1Migration.identifier) { db in
            try V1Migration.perform(db)
        }
        fullMigrator.registerMigration(V2Migration.identifier) { db in
            try V2Migration.perform(db)
        }
        try fullMigrator.migrate(queue)

        try queue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM playback_history WHERE torrent_id = ?",
                arguments: ["legacy-row"]
            )
            XCTAssertNotNil(row, "legacy row lost during V2 upgrade")
            XCTAssertEqual(row?["resume_byte_offset"] as Int64?, 1024)
            XCTAssertEqual(row?["completed"] as Int64?, 1)
            XCTAssertNil(row?["completed_at"] as Int64?,
                         "legacy row should have NULL completed_at after V2 upgrade")
        }
    }
}
