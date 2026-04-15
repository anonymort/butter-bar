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
}
