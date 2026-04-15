// Self-test for gateway ↔ planner wiring.
// Activated when the EngineService process is launched with the argument
//   --gateway-planner-self-test
// Exits 0 on pass, 1 on failure.
//
// The test creates a synthetic 10 MB file, seeds it via TorrentBridge, waits for
// piece availability, then drives PlaybackSession directly AND via GatewayListener
// to verify the full stack: HTTP parse → planner event → bridge calls → byte read.

#if DEBUG

import Foundation
import Network

// MARK: - Self-test entry point

/// Runs all gateway-planner wiring self-tests and returns a list of failure messages.
func runGatewayPlannerSelfTests() -> [String] {
    var failures: [String] = []

    func fail(_ message: String, line: Int = #line) {
        failures.append("\(message) (line \(line))")
    }
    func expect(_ condition: Bool, _ message: String, line: Int = #line) {
        if !condition { fail(message, line: line) }
    }

    // MARK: - 1. Set up a 10 MB synthetic file

    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("GatewayPlannerSelfTest-\(UUID().uuidString)", isDirectory: true)
    let sourceDir = tmpDir.appendingPathComponent("source", isDirectory: true)
    let torrentPath = tmpDir.appendingPathComponent("test.torrent").path
    // 10 MB — enough for multiple pieces.
    let fileSize = 10 * 1024 * 1024
    let fileByte: UInt8 = 0xCD

    do {
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = sourceDir.appendingPathComponent("media.bin")
        let data = Data(repeating: fileByte, count: fileSize)
        try data.write(to: fileURL)
    } catch {
        failures.append("Setup failed: \(error)")
        return failures
    }

    defer {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - 2. Create .torrent

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

    // MARK: - 3. Wait for all pieces to become available (up to 10 s)
    // Since the torrent was created from local files and added to a session that
    // can read them, libtorrent should mark pieces as available quickly.

    var havePiecesArray: [NSNumber] = []
    let pieceWaitStart = Date()
    let pieceWaitLimit: TimeInterval = 10.0
    let pieceLength = bridge.pieceLength(torrentID)

    guard pieceLength > 0 else {
        fail("pieceLength is 0 — metadata not ready")
        return failures
    }

    let expectedPieceCount = Int((Int64(fileSize) + pieceLength - 1) / pieceLength)

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

    NSLog("[GatewayPlannerSelfTest] all %d pieces available", expectedPieceCount)

    // MARK: - 4. Direct PlaybackSession tests (no real HTTP, calls handleRequest directly)

    let registry = StreamRegistry()
    let streamID = "test-stream-\(UUID().uuidString)"
    let contentLength = Int64(fileSize)

    do {
        try registry.createStream(
            streamID: streamID,
            contentType: "video/mp4",
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

    // ---- Test 4a: HEAD request ---
    let headRequest = HTTPRangeRequest(
        method: .head,
        path: "/stream/\(streamID)",
        rangeStart: nil,
        rangeEnd: nil,
        headers: [:]
    )
    let headResponse = registry.handleRequest(headRequest)
    guard let headResponse else {
        fail("4a: handleRequest returned nil for HEAD")
        return failures
    }
    expect(headResponse.statusCode == 200, "4a: HEAD should return 200, got \(headResponse.statusCode)")
    expect(headResponse.body == nil, "4a: HEAD response should have no body")
    expect(headResponse.headers["Content-Length"] == "\(contentLength)",
           "4a: HEAD Content-Length should be \(contentLength), got \(headResponse.headers["Content-Length"] ?? "nil")")

    // ---- Test 4b: GET first 64 KB ---
    let chunkSize: Int64 = 65_536
    let getRequest1 = HTTPRangeRequest(
        method: .get,
        path: "/stream/\(streamID)",
        rangeStart: 0,
        rangeEnd: chunkSize - 1,
        headers: ["range": "bytes=0-\(chunkSize - 1)"]
    )
    let getResponse1 = registry.handleRequest(getRequest1)
    guard let getResponse1 else {
        fail("4b: handleRequest returned nil for GET 0-\(chunkSize - 1)")
        return failures
    }
    expect(getResponse1.statusCode == 206, "4b: GET should return 206, got \(getResponse1.statusCode)")
    if let body1 = getResponse1.body {
        expect(body1.count == Int(chunkSize), "4b: body length should be \(chunkSize), got \(body1.count)")
        // All bytes should be 0xCD.
        let allMatch = body1.allSatisfy { $0 == fileByte }
        expect(allMatch, "4b: body bytes should all be 0xCD")
    } else {
        fail("4b: GET response has no body")
    }

    // ---- Test 4c: GET mid-file chunk (to exercise mid-play policy) ---
    let midOffset: Int64 = 512 * 1024  // 512 KB in
    let getRequest2 = HTTPRangeRequest(
        method: .get,
        path: "/stream/\(streamID)",
        rangeStart: midOffset,
        rangeEnd: midOffset + chunkSize - 1,
        headers: ["range": "bytes=\(midOffset)-\(midOffset + chunkSize - 1)"]
    )
    let getResponse2 = registry.handleRequest(getRequest2)
    guard let getResponse2 else {
        fail("4c: handleRequest returned nil for mid-file GET")
        return failures
    }
    expect(getResponse2.statusCode == 206, "4c: mid GET should return 206, got \(getResponse2.statusCode)")
    if let body2 = getResponse2.body {
        let allMatch = body2.allSatisfy { $0 == fileByte }
        expect(allMatch, "4c: mid-file body bytes should all be 0xCD")
    } else {
        fail("4c: mid GET response has no body")
    }

    // ---- Test 4d: GET a seek (far jump) ---
    let seekOffset: Int64 = Int64(fileSize) - 2 * chunkSize
    let getRequest3 = HTTPRangeRequest(
        method: .get,
        path: "/stream/\(streamID)",
        rangeStart: seekOffset,
        rangeEnd: seekOffset + chunkSize - 1,
        headers: ["range": "bytes=\(seekOffset)-\(seekOffset + chunkSize - 1)"]
    )
    let getResponse3 = registry.handleRequest(getRequest3)
    guard let getResponse3 else {
        fail("4d: handleRequest returned nil for seek GET")
        return failures
    }
    expect(getResponse3.statusCode == 206, "4d: seek GET should return 206, got \(getResponse3.statusCode)")
    if let body3 = getResponse3.body {
        let allMatch = body3.allSatisfy { $0 == fileByte }
        expect(allMatch, "4d: seek body bytes should all be 0xCD")
    } else {
        fail("4d: seek GET response has no body")
    }

    // ---- Test 4e: StreamRegistry path extraction — wrong path returns nil ---
    let badPathRequest = HTTPRangeRequest(
        method: .head,
        path: "/bad-path",
        rangeStart: nil,
        rangeEnd: nil,
        headers: [:]
    )
    let badResponse = registry.handleRequest(badPathRequest)
    expect(badResponse == nil, "4e: bad path should return nil from StreamRegistry")

    // ---- Test 4f: Unknown stream ID returns nil ---
    let unknownStreamRequest = HTTPRangeRequest(
        method: .head,
        path: "/stream/no-such-stream",
        rangeStart: nil,
        rangeEnd: nil,
        headers: [:]
    )
    let unknownResponse = registry.handleRequest(unknownStreamRequest)
    expect(unknownResponse == nil, "4f: unknown stream should return nil from StreamRegistry")

    // ---- Test 4g: Out-of-range GET returns 416 ---
    let oorRequest = HTTPRangeRequest(
        method: .get,
        path: "/stream/\(streamID)",
        rangeStart: contentLength + 1000,
        rangeEnd: contentLength + 2000,
        headers: ["range": "bytes=\(contentLength + 1000)-\(contentLength + 2000)"]
    )
    let oorResponse = registry.handleRequest(oorRequest)
    guard let oorResponse else {
        fail("4g: handleRequest returned nil for out-of-range request")
        return failures
    }
    expect(oorResponse.statusCode == 416, "4g: OOR GET should return 416, got \(oorResponse.statusCode)")

    NSLog("[GatewayPlannerSelfTest] direct session tests passed")

    // MARK: - 5. Live HTTP round-trip via GatewayListener
    //
    // Start a real GatewayListener. Wire its requestHandler to a second StreamRegistry
    // with the same torrent. Send real HTTP requests using URLSession.

    var listenerPort: UInt16 = 0
    let listenerReady = DispatchSemaphore(value: 0)
    let gatewayListener: GatewayListener
    do {
        gatewayListener = try GatewayListener()
    } catch {
        fail("GatewayListener init threw: \(error)")
        return failures
    }

    let liveRegistry = StreamRegistry()
    let liveStreamID = "live-stream-\(UUID().uuidString)"
    do {
        try liveRegistry.createStream(
            streamID: liveStreamID,
            contentType: "video/mp4",
            contentLength: contentLength,
            bridge: bridge,
            torrentID: torrentID,
            fileIndex: 0
        )
    } catch {
        fail("liveRegistry.createStream threw: \(error)")
        return failures
    }
    defer { liveRegistry.closeStream(liveStreamID) }

    gatewayListener.requestHandler = { request in
        liveRegistry.handleRequest(request) ?? HTTPRangeResponse.notFound()
    }
    gatewayListener.onReady = { port in
        listenerPort = port
        listenerReady.signal()
    }
    gatewayListener.start()
    defer { gatewayListener.stop() }

    let portWait = listenerReady.wait(timeout: .now() + .seconds(5))
    guard portWait == .success else {
        fail("5: GatewayListener did not become ready within 5 seconds")
        return failures
    }

    NSLog("[GatewayPlannerSelfTest] GatewayListener ready on port %d", listenerPort)

    // ---- Test 5a: HTTP HEAD via URLSession ---
    // nonisolated(unsafe) is safe here: the semaphore serialises access —
    // the main thread only reads after .wait() returns.
    let headURL = URL(string: "http://127.0.0.1:\(listenerPort)/stream/\(liveStreamID)")!
    nonisolated(unsafe) var headHTTPResponse: HTTPURLResponse?
    let headSem = DispatchSemaphore(value: 0)
    var headReq = URLRequest(url: headURL)
    headReq.httpMethod = "HEAD"
    let headTask = URLSession.shared.dataTask(with: headReq) { _, response, _ in
        headHTTPResponse = response as? HTTPURLResponse
        headSem.signal()
    }
    headTask.resume()
    headSem.wait()
    expect(headHTTPResponse?.statusCode == 200,
           "5a: HTTP HEAD should return 200, got \(headHTTPResponse?.statusCode ?? -1)")
    let clHeader = headHTTPResponse?.allHeaderFields["Content-Length"] as? String
    expect(clHeader == "\(contentLength)",
           "5a: HTTP HEAD Content-Length should be \(contentLength), got \(clHeader ?? "nil")")

    // ---- Test 5b: HTTP GET first 4096 bytes ---
    nonisolated(unsafe) var getHTTPResponse: HTTPURLResponse?
    nonisolated(unsafe) var getRawResponse: Data?
    let getSem = DispatchSemaphore(value: 0)
    var getReq = URLRequest(url: headURL)
    getReq.httpMethod = "GET"
    getReq.setValue("bytes=0-4095", forHTTPHeaderField: "Range")
    let getTask = URLSession.shared.dataTask(with: getReq) { data, response, _ in
        getHTTPResponse = response as? HTTPURLResponse
        getRawResponse = data
        getSem.signal()
    }
    getTask.resume()
    getSem.wait()
    expect(getHTTPResponse?.statusCode == 206,
           "5b: HTTP GET should return 206, got \(getHTTPResponse?.statusCode ?? -1)")
    if let body = getRawResponse {
        expect(body.count == 4096, "5b: GET body should be 4096 bytes, got \(body.count)")
        let allMatch = body.allSatisfy { $0 == fileByte }
        expect(allMatch, "5b: GET body bytes should all be 0xCD")
    } else {
        fail("5b: GET response has no body")
    }

    NSLog("[GatewayPlannerSelfTest] live HTTP tests passed")

    return failures
}

/// Entry point called from main.swift when --gateway-planner-self-test is passed.
func runGatewayPlannerSelfTestAndExit() {
    let failures = runGatewayPlannerSelfTests()
    if failures.isEmpty {
        NSLog("[GatewayPlannerSelfTest] All tests passed.")
        exit(0)
    } else {
        NSLog("[GatewayPlannerSelfTest] FAILED — %d failure(s):", failures.count)
        for f in failures {
            NSLog("[GatewayPlannerSelfTest]   FAIL: %@", f)
        }
        exit(1)
    }
}

#endif // DEBUG
