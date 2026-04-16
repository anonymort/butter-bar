import XCTest
import GRDB
@testable import EngineStore

final class PlaybackHistoryRecordTests: XCTestCase {

    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try EngineDatabase.openInMemory()
    }

    // MARK: - Round-trip

    func testRoundTripInsertFetch() throws {
        let record = PlaybackHistoryRecord(
            torrentId: "abc123",
            fileIndex: 0,
            resumeByteOffset: 1_048_576,
            lastPlayedAt: 1_700_000_000_000
        )

        try queue.write { db in try record.insert(db) }

        let fetched = try queue.read { db in
            try PlaybackHistoryRecord.fetchOne(
                db,
                sql: "SELECT * FROM playback_history WHERE torrent_id = ? AND file_index = ?",
                arguments: ["abc123", 0]
            )
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.torrentId, "abc123")
        XCTAssertEqual(fetched?.fileIndex, 0)
        XCTAssertEqual(fetched?.resumeByteOffset, 1_048_576)
        XCTAssertEqual(fetched?.lastPlayedAt, 1_700_000_000_000)
    }

    // MARK: - Default values

    func testDefaultTotalWatchedSecondsIsZero() throws {
        let record = PlaybackHistoryRecord(
            torrentId: "def456",
            fileIndex: 1,
            resumeByteOffset: 0,
            lastPlayedAt: 1_700_000_001_000
            // totalWatchedSeconds and completed use defaults
        )

        try queue.write { db in try record.insert(db) }

        let fetched = try queue.read { db in
            try PlaybackHistoryRecord.fetchOne(
                db,
                sql: "SELECT * FROM playback_history WHERE torrent_id = ? AND file_index = ?",
                arguments: ["def456", 1]
            )
        }

        XCTAssertEqual(fetched?.totalWatchedSeconds, 0.0)
        XCTAssertEqual(fetched?.completed, false)
    }

    func testExplicitNonDefaultValues() throws {
        let record = PlaybackHistoryRecord(
            torrentId: "ghi789",
            fileIndex: 2,
            resumeByteOffset: 0,
            lastPlayedAt: 1_700_000_002_000,
            totalWatchedSeconds: 3723.5,
            completed: true
        )

        try queue.write { db in try record.insert(db) }

        let fetched = try queue.read { db in
            try PlaybackHistoryRecord.fetchOne(
                db,
                sql: "SELECT * FROM playback_history WHERE torrent_id = ? AND file_index = ?",
                arguments: ["ghi789", 2]
            )
        }

        XCTAssertEqual(fetched?.totalWatchedSeconds, 3723.5)
        XCTAssertEqual(fetched?.completed, true)
    }

    // MARK: - completedAt round-trip (A26)

    func testCompletedAtNilByDefault() throws {
        let record = PlaybackHistoryRecord(
            torrentId: "ca-nil",
            fileIndex: 0,
            resumeByteOffset: 0,
            lastPlayedAt: 1_700_000_010_000
        )

        try queue.write { db in try record.insert(db) }

        let fetched = try queue.read { db in
            try PlaybackHistoryRecord.fetchOne(
                db,
                sql: "SELECT * FROM playback_history WHERE torrent_id = ?",
                arguments: ["ca-nil"]
            )
        }
        XCTAssertNil(fetched?.completedAt)
    }

    func testCompletedAtRoundTripsWhenSet() throws {
        let record = PlaybackHistoryRecord(
            torrentId: "ca-set",
            fileIndex: 1,
            resumeByteOffset: 9_500_000,
            lastPlayedAt: 1_700_000_011_000,
            completed: true,
            completedAt: 1_700_000_012_345
        )

        try queue.write { db in try record.insert(db) }

        let fetched = try queue.read { db in
            try PlaybackHistoryRecord.fetchOne(
                db,
                sql: "SELECT * FROM playback_history WHERE torrent_id = ?",
                arguments: ["ca-set"]
            )
        }
        XCTAssertEqual(fetched?.completedAt, 1_700_000_012_345)
        XCTAssertEqual(fetched?.completed, true)
    }

    func testCompletedAtUpdatesViaSave() throws {
        var record = PlaybackHistoryRecord(
            torrentId: "ca-update",
            fileIndex: 0,
            resumeByteOffset: 9_500_000,
            lastPlayedAt: 1_700_000_013_000,
            completed: true,
            completedAt: 1_700_000_013_001
        )
        try queue.write { db in try record.insert(db) }

        record.completedAt = 1_700_000_999_999 // most-recent-completion-wins
        try queue.write { db in try record.save(db) }

        let fetched = try queue.read { db in
            try PlaybackHistoryRecord.fetchOne(
                db,
                sql: "SELECT * FROM playback_history WHERE torrent_id = ?",
                arguments: ["ca-update"]
            )
        }
        XCTAssertEqual(fetched?.completedAt, 1_700_000_999_999)
    }

    // MARK: - Upsert (update existing row)

    func testUpsertUpdatesExistingRow() throws {
        var record = PlaybackHistoryRecord(
            torrentId: "jkl012",
            fileIndex: 0,
            resumeByteOffset: 500_000,
            lastPlayedAt: 1_700_000_003_000
        )

        try queue.write { db in try record.insert(db) }

        record.resumeByteOffset = 1_000_000
        record.lastPlayedAt = 1_700_000_004_000

        try queue.write { db in try record.save(db) }

        let fetched = try queue.read { db in
            try PlaybackHistoryRecord.fetchOne(
                db,
                sql: "SELECT * FROM playback_history WHERE torrent_id = ? AND file_index = ?",
                arguments: ["jkl012", 0]
            )
        }

        XCTAssertEqual(fetched?.resumeByteOffset, 1_000_000)
        XCTAssertEqual(fetched?.lastPlayedAt, 1_700_000_004_000)
    }
}
