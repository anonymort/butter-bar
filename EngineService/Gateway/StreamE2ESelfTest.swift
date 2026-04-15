// End-to-end stream self-test.
// Activated when the EngineService process is launched with the argument
//   --stream-e2e-self-test
// Exits 0 on pass, 1 on failure.
//
// Exercises the full path from TorrentBridge through PiecePlanner and
// StreamRegistry to GatewayListener and back, using real URLSession HTTP
// round-trips against the loopback gateway. No external network access required.
//
// Test file: a 256 KB file of sequential bytes (0x00..0xFF repeating) created
// in a temp directory and seeded immediately by libtorrent (local source).

#if DEBUG

import Foundation
import Network

// MARK: - Self-test entry point

/// Runs all Stream E2E self-tests and returns a list of failure messages.
/// An empty array means all tests passed.
func runStreamE2ESelfTests() -> [String] {
    var failures: [String] = []

    func fail(_ message: String, line: Int = #line) {
        failures.append("\(message) (line \(line))")
    }
    func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition { fail(message, line: line) }
    }

    // MARK: - 1. Create a 256 KB synthetic file with sequential byte pattern

    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("StreamE2ESelfTest-\(UUID().uuidString)", isDirectory: true)
    let sourceDir = tmpDir.appendingPathComponent("source", isDirectory: true)
    let torrentPath = tmpDir.appendingPathComponent("test.torrent").path
    let fileSize = 256 * 1024  // 256 KB — small enough to complete fast, large enough for multiple pieces.

    // Sequential pattern: byte at position i is UInt8(i & 0xFF).
    // This lets us verify exact bytes at arbitrary offsets without storing the full content.
    let fileData: Data = {
        var d = Data(count: fileSize)
        for i in 0..<fileSize { d[i] = UInt8(i & 0xFF) }
        return d
    }()

    do {
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = sourceDir.appendingPathComponent("stream-test.bin")
        try fileData.write(to: fileURL)
    } catch {
        failures.append("Setup failed: \(error)")
        return failures
    }

    defer {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - 2. Create .torrent from the temp file

    do {
        _ = try TorrentBridge.createTestTorrent(sourceDir.path, outputPath: torrentPath)
    } catch {
        fail("createTestTorrent threw: \(error)")
        return failures
    }

    let bridge = TorrentBridge()
    defer { bridge.shutdown() }

    let torrentID: String
    do {
        torrentID = try bridge.addTorrentFile(atPath: torrentPath)
    } catch {
        fail("addTorrentFileAtPath threw: \(error)")
        return failures
    }

    NSLog("[StreamE2ESelfTest] torrent added: %@", torrentID)

    // MARK: - 3. Wait for metadata (listFiles returns results)

    var fileCount = 0
    let metaWaitStart = Date()
    let metaWaitLimit: TimeInterval = 30.0

    while Date().timeIntervalSince(metaWaitStart) < metaWaitLimit {
        if let f = try? bridge.listFiles(torrentID), !f.isEmpty {
            fileCount = f.count
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    guard fileCount > 0 else {
        fail("Timed out waiting for metadata (listFiles returned empty)")
        return failures
    }

    NSLog("[StreamE2ESelfTest] metadata ready, files: %d", fileCount)

    // MARK: - 4. Wait for all pieces to be downloaded

    let pieceLength = bridge.pieceLength(torrentID)
    guard pieceLength > 0 else {
        fail("pieceLength is 0 — metadata not ready")
        return failures
    }

    let expectedPieceCount = Int((Int64(fileSize) + pieceLength - 1) / pieceLength)
    var havePiecesArray: [NSNumber] = []
    let pieceWaitStart = Date()
    let pieceWaitLimit: TimeInterval = 30.0

    while Date().timeIntervalSince(pieceWaitStart) < pieceWaitLimit {
        if let pieces = try? bridge.havePieces(torrentID) {
            havePiecesArray = pieces
            if pieces.count >= expectedPieceCount { break }
        }
        Thread.sleep(forTimeInterval: 0.1)
    }

    guard havePiecesArray.count >= expectedPieceCount else {
        fail("Timed out waiting for all pieces; have \(havePiecesArray.count)/\(expectedPieceCount)")
        return failures
    }

    NSLog("[StreamE2ESelfTest] all %d pieces available", expectedPieceCount)

    // MARK: - 5. Set up GatewayListener and StreamRegistry

    var listenerPort: UInt16 = 0
    let listenerReady = DispatchSemaphore(value: 0)
    let gatewayListener: GatewayListener

    do {
        gatewayListener = try GatewayListener()
    } catch {
        fail("GatewayListener init threw: \(error)")
        return failures
    }
    defer { gatewayListener.stop() }

    let registry = StreamRegistry()
    let streamID = "e2e-\(UUID().uuidString)"
    let contentLength = Int64(fileSize)

    do {
        try registry.createStream(
            streamID: streamID,
            contentType: "application/octet-stream",
            contentLength: contentLength,
            bridge: bridge,
            torrentID: torrentID,
            fileIndex: 0
        )
    } catch {
        fail("createStream threw: \(error)")
        return failures
    }
    defer { registry.closeStream(streamID) }

    gatewayListener.requestHandler = { request in
        registry.handleRequest(request) ?? HTTPRangeResponse.notFound()
    }
    gatewayListener.onReady = { port in
        listenerPort = port
        listenerReady.signal()
    }
    gatewayListener.start()

    let portWait = listenerReady.wait(timeout: .now() + .seconds(10))
    guard portWait == .success else {
        fail("GatewayListener did not become ready within 10 seconds")
        return failures
    }

    NSLog("[StreamE2ESelfTest] GatewayListener ready on port %d", listenerPort)

    let baseURL = URL(string: "http://127.0.0.1:\(listenerPort)/stream/\(streamID)")!

    // MARK: - 6. Test: HEAD → 200, correct Content-Length

    nonisolated(unsafe) var headResponse: HTTPURLResponse?
    let headSem = DispatchSemaphore(value: 0)
    var headReq = URLRequest(url: baseURL)
    headReq.httpMethod = "HEAD"
    URLSession.shared.dataTask(with: headReq) { _, resp, _ in
        headResponse = resp as? HTTPURLResponse
        headSem.signal()
    }.resume()
    headSem.wait()

    expect(headResponse?.statusCode == 200,
           "HEAD: expected 200, got \(headResponse?.statusCode ?? -1)")
    let clHeader = headResponse?.allHeaderFields["Content-Length"] as? String
    expect(clHeader == "\(contentLength)",
           "HEAD: Content-Length should be \(contentLength), got \(clHeader ?? "nil")")
    NSLog("[StreamE2ESelfTest] Test 6 (HEAD) %@", (headResponse?.statusCode == 200) ? "PASS" : "FAIL")

    // MARK: - 7. Test: GET bytes=0-1023 → 206, correct body

    nonisolated(unsafe) var getResp1: HTTPURLResponse?
    nonisolated(unsafe) var getData1: Data?
    let getSem1 = DispatchSemaphore(value: 0)
    var getReq1 = URLRequest(url: baseURL)
    getReq1.httpMethod = "GET"
    getReq1.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
    URLSession.shared.dataTask(with: getReq1) { data, resp, _ in
        getResp1 = resp as? HTTPURLResponse
        getData1 = data
        getSem1.signal()
    }.resume()
    getSem1.wait()

    expect(getResp1?.statusCode == 206,
           "GET [0,1023]: expected 206, got \(getResp1?.statusCode ?? -1)")
    if let body = getData1 {
        expect(body.count == 1024, "GET [0,1023]: expected 1024 bytes, got \(body.count)")
        // Verify sequential byte pattern.
        let correct = body.enumerated().allSatisfy { idx, byte in byte == UInt8(idx & 0xFF) }
        expect(correct, "GET [0,1023]: byte content mismatch")
    } else {
        fail("GET [0,1023]: no body returned")
    }
    let crHeader1 = getResp1?.allHeaderFields["Content-Range"] as? String
    expect(crHeader1 == "bytes 0-1023/\(contentLength)",
           "GET [0,1023]: Content-Range expected 'bytes 0-1023/\(contentLength)', got \(crHeader1 ?? "nil")")
    NSLog("[StreamE2ESelfTest] Test 7 (GET 0-1023) %@", (getResp1?.statusCode == 206) ? "PASS" : "FAIL")

    // MARK: - 8. Test: GET bytes=1024-2047 → 206, different byte range

    nonisolated(unsafe) var getResp2: HTTPURLResponse?
    nonisolated(unsafe) var getData2: Data?
    let getSem2 = DispatchSemaphore(value: 0)
    var getReq2 = URLRequest(url: baseURL)
    getReq2.httpMethod = "GET"
    getReq2.setValue("bytes=1024-2047", forHTTPHeaderField: "Range")
    URLSession.shared.dataTask(with: getReq2) { data, resp, _ in
        getResp2 = resp as? HTTPURLResponse
        getData2 = data
        getSem2.signal()
    }.resume()
    getSem2.wait()

    expect(getResp2?.statusCode == 206,
           "GET [1024,2047]: expected 206, got \(getResp2?.statusCode ?? -1)")
    if let body = getData2 {
        expect(body.count == 1024, "GET [1024,2047]: expected 1024 bytes, got \(body.count)")
        // Bytes at offset 1024..2047 follow the sequential pattern starting at 0x00 again (1024 & 0xFF == 0).
        let correct = body.enumerated().allSatisfy { idx, byte in
            byte == UInt8((1024 + idx) & 0xFF)
        }
        expect(correct, "GET [1024,2047]: byte content mismatch")
    } else {
        fail("GET [1024,2047]: no body returned")
    }
    NSLog("[StreamE2ESelfTest] Test 8 (GET 1024-2047) %@", (getResp2?.statusCode == 206) ? "PASS" : "FAIL")

    // MARK: - 9. Test: GET with no Range header → full response (200 or 206)

    nonisolated(unsafe) var getResp3: HTTPURLResponse?
    nonisolated(unsafe) var getData3: Data?
    let getSem3 = DispatchSemaphore(value: 0)
    var getReq3 = URLRequest(url: baseURL)
    getReq3.httpMethod = "GET"
    // No Range header — PlaybackSession treats this as rangeStart=0, rangeEnd=fileSize-1.
    URLSession.shared.dataTask(with: getReq3) { data, resp, _ in
        getResp3 = resp as? HTTPURLResponse
        getData3 = data
        getSem3.signal()
    }.resume()
    getSem3.wait()

    let noRangeStatus = getResp3?.statusCode ?? -1
    expect(noRangeStatus == 200 || noRangeStatus == 206,
           "GET (no Range): expected 200 or 206, got \(noRangeStatus)")
    if let body = getData3 {
        expect(body.count == Int(contentLength),
               "GET (no Range): expected \(contentLength) bytes, got \(body.count)")
    } else {
        fail("GET (no Range): no body returned")
    }
    NSLog("[StreamE2ESelfTest] Test 9 (GET no Range) %@",
          (noRangeStatus == 200 || noRangeStatus == 206) ? "PASS" : "FAIL")

    // MARK: - 10. Verify returned bytes match the known pattern (spot-check)

    if let body = getData3, body.count == Int(contentLength) {
        // Spot-check 4 positions across the file.
        let checkOffsets = [0, 256, 1024, fileSize - 1]
        for offset in checkOffsets {
            let expected = UInt8(offset & 0xFF)
            let actual = body[offset]
            expect(actual == expected,
                   "Byte content at offset \(offset): expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))")
        }
        NSLog("[StreamE2ESelfTest] Test 10 (byte verification) PASS")
    }

    return failures
}

/// Entry point called from main.swift when --stream-e2e-self-test is passed.
func runStreamE2ESelfTestAndExit() {
    NSLog("[StreamE2ESelfTest] Starting end-to-end stream self-test…")
    let failures = runStreamE2ESelfTests()
    if failures.isEmpty {
        NSLog("[StreamE2ESelfTest] All tests PASSED.")
        exit(0)
    } else {
        NSLog("[StreamE2ESelfTest] FAILED — %d failure(s):", failures.count)
        for f in failures {
            NSLog("[StreamE2ESelfTest]   FAIL: %@", f)
        }
        exit(1)
    }
}

#endif // DEBUG
