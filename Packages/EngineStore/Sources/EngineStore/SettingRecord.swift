import GRDB

/// A row in the `settings` table.
///
/// Engine-wide key/value store. `value` is always JSON-encoded so callers can
/// store scalars, arrays, or objects under the same column without schema churn.
/// Keys are short, namespaced strings (e.g. `"cache.highWaterBytes"`).
public struct SettingRecord: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "settings"

    // Map Swift camelCase property to the SQL snake_case column name.
    enum CodingKeys: String, CodingKey {
        case key
        case value
        case updatedAt = "updated_at"
    }

    /// Stable, namespaced string key. Acts as the primary key.
    public var key: String

    /// JSON-encoded value. Never empty; use `"null"` for an explicit null.
    public var value: String

    /// Unix milliseconds of the last write.
    public var updatedAt: Int64

    public init(key: String, value: String, updatedAt: Int64) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}
