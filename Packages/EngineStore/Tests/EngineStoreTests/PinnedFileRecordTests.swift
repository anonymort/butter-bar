import XCTest
import GRDB
@testable import EngineStore

final class PinnedFileRecordTests: XCTestCase {

    private var queue: DatabaseQueue!

    override func setUpWithError() throws {
        queue = try EngineDatabase.openInMemory()
    }

    // MARK: - Round-trip

    func testRoundTripInsertFetch() throws {
        let record = PinnedFileRecord(
            torrentId: "torrent-aaa",
            fileIndex: 3,
            pinnedAt: 1_700_000_005_000
        )

        try queue.write { db in try record.insert(db) }

        let fetched = try queue.read { db in
            try PinnedFileRecord.fetchOne(
                db,
                sql: "SELECT * FROM pinned_files WHERE torrent_id = ? AND file_index = ?",
                arguments: ["torrent-aaa", 3]
            )
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.torrentId, "torrent-aaa")
        XCTAssertEqual(fetched?.fileIndex, 3)
        XCTAssertEqual(fetched?.pinnedAt, 1_700_000_005_000)
    }

    // MARK: - Multiple pinned files for the same torrent

    func testMultipleFilesForSameTorrent() throws {
        let pin0 = PinnedFileRecord(torrentId: "torrent-bbb", fileIndex: 0, pinnedAt: 1_700_000_006_000)
        let pin1 = PinnedFileRecord(torrentId: "torrent-bbb", fileIndex: 1, pinnedAt: 1_700_000_007_000)

        try queue.write { db in
            try pin0.insert(db)
            try pin1.insert(db)
        }

        let all = try queue.read { db in
            try PinnedFileRecord.fetchAll(
                db,
                sql: "SELECT * FROM pinned_files WHERE torrent_id = ? ORDER BY file_index",
                arguments: ["torrent-bbb"]
            )
        }

        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].fileIndex, 0)
        XCTAssertEqual(all[1].fileIndex, 1)
    }

    // MARK: - Delete (unpin)

    func testDeleteRemovesRow() throws {
        let record = PinnedFileRecord(torrentId: "torrent-ccc", fileIndex: 0, pinnedAt: 1_700_000_008_000)

        try queue.write { db in try record.insert(db) }
        _ = try queue.write { db in try record.delete(db) }

        let fetched = try queue.read { db in
            try PinnedFileRecord.fetchOne(
                db,
                sql: "SELECT * FROM pinned_files WHERE torrent_id = ? AND file_index = ?",
                arguments: ["torrent-ccc", 0]
            )
        }

        XCTAssertNil(fetched)
    }
}
