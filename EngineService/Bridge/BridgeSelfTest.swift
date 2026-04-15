// Self-test exercising every TorrentBridge method.
// Activated when the EngineService process is launched with the argument
//   --bridge-self-test
// Run via the built EngineService product with that argument, or as a unit test
// driver. Exits 0 on pass, 1 on failure.

// NOTE: Swift imports ObjC `NSError **` parameters as `throws`. All TorrentBridge
// methods that take an `error:` parameter are called with `try` here.

#if DEBUG

import Foundation

/// Runs all TorrentBridge self-tests and returns a list of failure messages.
/// An empty array means all tests passed.
func runBridgeSelfTests() -> [String] {
    var failures: [String] = []

    func fail(_ message: String, line: Int = #line) {
        failures.append("\(message) (line \(line))")
    }
    func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition { fail(message, line: line) }
    }

    // MARK: - Set up a temp directory with a small test file

    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("BridgeSelfTest-\(UUID().uuidString)", isDirectory: true)
    let sourceDir = tmpDir.appendingPathComponent("source", isDirectory: true)
    let torrentPath = tmpDir.appendingPathComponent("test.torrent").path

    do {
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        // ~32 KB so we get at least a couple of pieces.
        let testFilePath = sourceDir.appendingPathComponent("testfile.bin")
        let data = Data(repeating: 0xAB, count: 32 * 1024)
        try data.write(to: testFilePath)
    } catch {
        failures.append("Setup failed: \(error)")
        return failures
    }

    defer {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Create a .torrent using the test helper

    do {
        let createdPath = try TorrentBridge.createTestTorrent(
            sourceDir.path,
            outputPath: torrentPath
        )
        expect(createdPath == torrentPath, "createTestTorrent should return outputPath")
        expect(FileManager.default.fileExists(atPath: torrentPath), ".torrent file should exist")
    } catch {
        fail("createTestTorrent threw: \(error)")
        return failures
    }

    // MARK: - Lifecycle: init

    let bridge = TorrentBridge()

    // MARK: - Alert subscription

    bridge.subscribeAlerts { _ in }

    // MARK: - addTorrentFileAtPath

    let torrentID: String
    do {
        let tid = try bridge.addTorrentFile(atPath: torrentPath)
        torrentID = tid
    } catch {
        fail("addTorrentFileAtPath threw: \(error)")
        bridge.shutdown()
        return failures
    }

    // MARK: - listFiles

    do {
        let files = try bridge.listFiles(torrentID)
        expect(files.count == 1, "listFiles should return 1 file, got \(files.count)")
        if let first = files.first {
            expect(first["path"] is String, "file entry should have String path")
            expect(first["size"] is NSNumber, "file entry should have NSNumber size")
            expect(first["index"] is NSNumber, "file entry should have NSNumber index")
            let sz = (first["size"] as? NSNumber)?.int64Value ?? 0
            expect(sz == 32 * 1024, "file size should be 32768, got \(sz)")
        }
    } catch {
        fail("listFiles threw: \(error)")
    }

    // MARK: - statusSnapshot

    do {
        let snap = try bridge.statusSnapshot(torrentID)
        expect(snap["state"] is String, "snapshot should have String state")
        expect(snap["progress"] is NSNumber, "snapshot should have NSNumber progress")
        expect(snap["downloadRate"] is NSNumber, "snapshot should have NSNumber downloadRate")
        expect(snap["uploadRate"] is NSNumber, "snapshot should have NSNumber uploadRate")
        expect(snap["peerCount"] is NSNumber, "snapshot should have NSNumber peerCount")
        expect(snap["totalBytes"] is NSNumber, "snapshot should have NSNumber totalBytes")
    } catch {
        fail("statusSnapshot threw: \(error)")
    }

    // MARK: - pieceLength

    let pl = bridge.pieceLength(torrentID)
    expect(pl > 0, "pieceLength should be > 0, got \(pl)")

    // MARK: - havePieces

    do {
        let pieces = try bridge.havePieces(torrentID)
        // May be empty early on — just verify we get an array back.
        _ = pieces
    } catch {
        fail("havePieces threw: \(error)")
    }

    // MARK: - setPieceDeadline
    // ObjC BOOL+NSError** bridges to Swift as throws-void.

    do {
        try bridge.setPieceDeadline(torrentID, piece: 0, deadlineMs: 500)
    } catch {
        fail("setPieceDeadline threw: \(error)")
    }

    // MARK: - clearPieceDeadlines

    do {
        try bridge.clearPieceDeadlines(torrentID, exceptPieces: [0])
    } catch {
        fail("clearPieceDeadlines threw: \(error)")
    }

    // MARK: - fileByteRange

    do {
        var startByte: Int64 = -1
        var endByte: Int64 = -1
        try bridge.fileByteRange(torrentID, fileIndex: 0, start: &startByte, end: &endByte)
        expect(startByte == 0, "fileByteRange start should be 0, got \(startByte)")
        expect(endByte == 32 * 1024, "fileByteRange end should be 32768, got \(endByte)")
    } catch {
        fail("fileByteRange threw: \(error)")
    }

    // MARK: - setFilePriority

    do {
        try bridge.setFilePriority(torrentID, fileIndex: 0, priority: 7)
    } catch {
        fail("setFilePriority threw: \(error)")
    }

    // MARK: - Error path: unknown torrentID

    do {
        _ = try bridge.statusSnapshot("not-a-real-id")
        fail("statusSnapshot with bogus ID should throw")
    } catch let err as NSError {
        expect(err.domain == TorrentBridgeErrorDomain, "error domain should be TorrentBridgeErrorDomain")
    }

    // MARK: - removeTorrent

    bridge.removeTorrent(torrentID, deleteData: false)

    // Brief yield to let the async remove propagate.
    Thread.sleep(forTimeInterval: 0.05)

    do {
        _ = try bridge.statusSnapshot(torrentID)
        fail("statusSnapshot after removeTorrent should throw")
    } catch {
        // expected
    }

    // MARK: - shutdown

    bridge.shutdown()

    do {
        _ = try bridge.addMagnet("magnet:?xt=urn:btih:0000")
        fail("addMagnet after shutdown should throw")
    } catch {
        // expected
    }

    return failures
}

/// Entry point called from main.swift when --bridge-self-test is passed.
func runBridgeSelfTestAndExit() {
    let failures = runBridgeSelfTests()
    if failures.isEmpty {
        NSLog("[BridgeSelfTest] All tests passed.")
        exit(0)
    } else {
        NSLog("[BridgeSelfTest] FAILED — %d failure(s):", failures.count)
        for f in failures {
            NSLog("[BridgeSelfTest]   FAIL: %@", f)
        }
        exit(1)
    }
}

#endif // DEBUG
