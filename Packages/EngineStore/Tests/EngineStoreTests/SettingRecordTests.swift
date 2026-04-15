import XCTest
import GRDB
@testable import EngineStore

final class SettingRecordTests: XCTestCase {

    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try EngineDatabase.openInMemory()
    }

    // MARK: - Round-trip

    func testRoundTripInsertFetch() throws {
        let record = SettingRecord(
            key: "cache.highWaterBytes",
            value: "53687091200",
            updatedAt: 1_700_000_009_000
        )

        try queue.write { db in try record.insert(db) }

        let fetched = try queue.read { db in
            try SettingRecord.fetchOne(
                db,
                sql: "SELECT * FROM settings WHERE key = ?",
                arguments: ["cache.highWaterBytes"]
            )
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.key, "cache.highWaterBytes")
        XCTAssertEqual(fetched?.value, "53687091200")
        XCTAssertEqual(fetched?.updatedAt, 1_700_000_009_000)
    }

    // MARK: - JSON-encoded value round-trip

    func testJsonEncodedValueRoundTrip() throws {
        // `value` stores arbitrary JSON — verify a compound object survives intact.
        let json = #"{"highWater":53687091200,"lowWater":42949672960}"#
        let record = SettingRecord(key: "cache.budgets", value: json, updatedAt: 1_700_000_010_000)

        try queue.write { db in try record.insert(db) }

        let fetched = try queue.read { db in
            try SettingRecord.fetchOne(
                db,
                sql: "SELECT * FROM settings WHERE key = ?",
                arguments: ["cache.budgets"]
            )
        }

        XCTAssertEqual(fetched?.value, json)
    }

    // MARK: - Primary key upsert (update via save)

    func testSaveUpdatesExistingKey() throws {
        var record = SettingRecord(
            key: "cache.lowWaterBytes",
            value: "42949672960",
            updatedAt: 1_700_000_011_000
        )

        try queue.write { db in try record.insert(db) }

        record.value = "32212254720"
        record.updatedAt = 1_700_000_012_000

        try queue.write { db in try record.save(db) }

        let count = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM settings WHERE key = ?",
                             arguments: ["cache.lowWaterBytes"])
        }
        XCTAssertEqual(count, 1, "save() should upsert, not duplicate the row")

        let fetched = try queue.read { db in
            try SettingRecord.fetchOne(
                db,
                sql: "SELECT * FROM settings WHERE key = ?",
                arguments: ["cache.lowWaterBytes"]
            )
        }
        XCTAssertEqual(fetched?.value, "32212254720")
        XCTAssertEqual(fetched?.updatedAt, 1_700_000_012_000)
    }

    // MARK: - Multiple keys coexist

    func testMultipleKeysCoexist() throws {
        let keys = ["a", "b", "c"]
        try queue.write { db in
            for (i, key) in keys.enumerated() {
                try SettingRecord(key: key, value: "\(i)", updatedAt: Int64(i)).insert(db)
            }
        }

        let all = try queue.read { db in
            try SettingRecord.fetchAll(db, sql: "SELECT * FROM settings ORDER BY key")
        }

        XCTAssertEqual(all.count, 3)
    }
}
