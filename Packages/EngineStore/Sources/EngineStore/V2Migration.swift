import GRDB

/// Adds the `playback_history.completed_at` column for the Epic #5 Phase 1
/// foundation (#34). See spec 05 rev 5 § Schema and addendum A26.
///
/// Additive and backward-compatible: existing rows get `NULL` for the new
/// column and the engine fills it on the next completion. Idempotent via
/// GRDB's named-migration tracking (identifier `v2_add_completed_at`).
///
/// Independent of the unrelated `v2_add_favourites` migration (TASKS.md
/// Phase 8); migrations apply in registration order, neither blocks the
/// other.
enum V2Migration {
    static let identifier = "v2_add_completed_at"

    static func perform(_ db: Database) throws {
        try db.execute(sql: """
            ALTER TABLE playback_history
            ADD COLUMN completed_at INTEGER
            """)
    }
}
