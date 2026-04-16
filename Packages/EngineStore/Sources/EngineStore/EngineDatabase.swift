import GRDB

/// Opens (or creates) the engine's SQLite database and runs pending migrations.
///
/// Call `EngineDatabase.open(at:)` once at engine startup. In tests, call
/// `EngineDatabase.openInMemory()` for a fresh, isolated database per test.
public enum EngineDatabase {
    /// Opens a persistent database at `path`, creating it if necessary.
    ///
    /// Runs any unapplied migrations before returning. Throws on I/O or
    /// migration error — the engine should treat either as fatal at startup.
    public static func open(at path: String) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: path)
        try migrate(queue)
        return queue
    }

    /// Opens a fresh in-memory database and runs migrations.
    ///
    /// Intended for unit tests only. Each call produces an independent database.
    public static func openInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try migrate(queue)
        return queue
    }

    // MARK: - Private

    private static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(V1Migration.identifier) { db in
            try V1Migration.perform(db)
        }
        migrator.registerMigration(V2Migration.identifier) { db in
            try V2Migration.perform(db)
        }
        migrator.registerMigration(V2FavouritesMigration.identifier) { db in
            try V2FavouritesMigration.perform(db)
        }
        try migrator.migrate(queue)
    }
}
