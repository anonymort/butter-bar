// End-to-end stream self-test using a real magnet link or .torrent file.
//
// Activated when EngineService is launched with:
//   EngineService --stream-e2e-self-test <magnet-or-torrent-path>
//   EngineService --stream-e2e-self-test <magnet-or-torrent-path> --file-index N
//   EngineService --stream-e2e-self-test          ← prints usage and exits 1
//
// Exercises the full HTTP serving path end-to-end:
//   TorrentBridge → metadata → StreamRegistry.createStream → GatewayListener → URLSession
//
// The self-test does NOT require AVPlayer; it validates protocol-level assertions:
//   HEAD → 200, correct Content-Length
//   GET Range → 206, correct Content-Range, real bytes
//   GET unknown stream → 404
//   Byte values from HTTP match bytes from TorrentBridge.readBytes (gateway byte-accuracy)
//
// AVPlayer integration is a separate manual step — see docs/test-content.md.
//
// Suggested well-seeded magnet (Internet Archive — Big Buck Bunny, ~276 MB MP4):
//   magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969
//
// Downloaded content is left on disk for iterative reruns (no re-download required).
// Save path: NSTemporaryDirectory() → ~/Library/Containers/com.butterbar.app.EngineService/Data/tmp/

#if DEBUG

import Foundation
import Network

// MARK: - Argument parsing

private struct SelfTestArgs {
    enum Source {
        case magnet(String)
        case torrentFile(String)   // absolute, verified to exist
    }
    let source: Source
    let fileIndex: Int?            // nil = largest file by size
}

private func parseSelfTestArgs(from args: [String]) -> SelfTestArgs? {
    guard !args.isEmpty else { return nil }

    let first = args[0]
    let source: SelfTestArgs.Source
    if first.hasPrefix("magnet:") {
        source = .magnet(first)
    } else {
        let url = URL(fileURLWithPath: first).standardized
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("[StreamE2ESelfTest] ERROR: .torrent file not found: %@", url.path)
            return nil
        }
        source = .torrentFile(url.path)
    }

    var fileIndex: Int? = nil
    if let fiIdx = args.firstIndex(of: "--file-index"), fiIdx + 1 < args.count,
       let n = Int(args[fiIdx + 1]) {
        fileIndex = n
    }

    return SelfTestArgs(source: source, fileIndex: fileIndex)
}

private func printSelfTestUsage() {
    let usage = """
[StreamE2ESelfTest] USAGE:
  EngineService --stream-e2e-self-test <magnet-or-torrent-path>
  EngineService --stream-e2e-self-test <magnet-or-torrent-path> --file-index N

  <magnet-or-torrent-path>  A magnet: URI or an absolute path to a .torrent file.
  --file-index N            Test the file at index N (default: largest file in torrent).

  Suggested well-seeded magnet (Internet Archive — Big Buck Bunny, ~276 MB MP4):
    magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969

  See docs/test-content.md for additional test content options.
  Downloaded content is left in NSTemporaryDirectory() for iterative reruns.
"""
    NSLog("%@", usage)
}

// MARK: - MIME type helpers

private func mimeType(forPath path: String) -> String {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "mp4", "m4v": return "video/mp4"
    case "mkv":        return "video/x-matroska"
    case "webm":       return "video/webm"
    case "mov":        return "video/quicktime"
    case "avi":        return "video/x-msvideo"
    case "mp3":        return "audio/mpeg"
    case "aac":        return "audio/aac"
    case "flac":       return "audio/flac"
    default:           return "application/octet-stream"
    }
}

// MARK: - HTTP round-trip helpers

private struct RoundTripResult {
    let statusCode: Int
    let headers: [AnyHashable: Any]
    let body: Data?
}

private func httpRoundTrip(request: URLRequest, timeoutSeconds: TimeInterval = 30) -> RoundTripResult? {
    nonisolated(unsafe) var result: RoundTripResult? = nil
    let sem = DispatchSemaphore(value: 0)
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = timeoutSeconds
    config.timeoutIntervalForResource = timeoutSeconds
    let session = URLSession(configuration: config)
    session.dataTask(with: request) { data, resp, _ in
        if let http = resp as? HTTPURLResponse {
            result = RoundTripResult(statusCode: http.statusCode,
                                     headers: http.allHeaderFields,
                                     body: data)
        }
        sem.signal()
    }.resume()
    sem.wait()
    return result
}

// MARK: - Core self-test

/// Runs the stream E2E self-test against a real torrent.
/// Returns a list of failure strings. Empty = all passed.
private func runSelfTest(testArgs: SelfTestArgs) -> [String] {
    var failures: [String] = []

    func fail(_ msg: String) {
        NSLog("[StreamE2ESelfTest] FAIL: %@", msg)
        failures.append(msg)
    }
    func assert_(_ cond: Bool, _ msg: String) {
        if !cond { fail(msg) }
    }
    func log(_ msg: String) {
        NSLog("[StreamE2ESelfTest] %@", msg)
    }

    log("=== T-STREAM-E2E self-test starting ===")

    // MARK: 1. Create bridge and add torrent

    let bridge = TorrentBridge()
    bridge.subscribeAlerts { alert in
        let type = alert["type"] as? String ?? "?"
        let msg  = alert["message"] as? String ?? ""
        NSLog("[StreamE2ESelfTest:alert] type=%@ msg=%@", type, msg)
    }

    let torrentID: String
    switch testArgs.source {
    case .magnet(let uri):
        log("Adding magnet: \(uri)")
        do { torrentID = try bridge.addMagnet(uri) }
        catch {
            fail("addMagnet failed: \(error)")
            bridge.shutdown()
            return failures
        }
    case .torrentFile(let path):
        log("Adding .torrent file: \(path)")
        do { torrentID = try bridge.addTorrentFile(atPath: path) }
        catch {
            fail("addTorrentFile failed: \(error)")
            bridge.shutdown()
            return failures
        }
    }
    log("Torrent ID: \(torrentID)")

    // Teardown on all exit paths.
    defer {
        bridge.removeTorrent(torrentID, deleteData: false)
        Thread.sleep(forTimeInterval: 0.1)
        bridge.shutdown()
        log("Cleanup complete. Downloaded content left in NSTemporaryDirectory() for reruns.")
    }

    // MARK: 2. Wait for metadata (up to 60s)

    log("Waiting up to 60s for torrent metadata...")
    let metaDeadline = Date().addingTimeInterval(60)
    var pieceLen: Int64 = 0
    while Date() < metaDeadline {
        pieceLen = bridge.pieceLength(torrentID)
        if pieceLen > 0 { break }
        Thread.sleep(forTimeInterval: 0.5)
    }
    guard pieceLen > 0 else {
        fail("METADATA_TIMEOUT — no metadata within 60s. Is the magnet well-seeded?")
        exit(2)
    }
    log("Metadata ready — piece length: \(pieceLen) bytes")

    // MARK: 3. List files

    let files: [NSDictionary]
    do {
        files = try bridge.listFiles(torrentID).map { $0 as NSDictionary }
    } catch {
        fail("listFiles failed: \(error)")
        return failures
    }
    log("File count: \(files.count)")
    for f in files {
        let path = f["path"] as? String ?? "?"
        let size = (f["size"] as? NSNumber)?.int64Value ?? -1
        let idx  = (f["index"] as? NSNumber)?.intValue ?? -1
        log("  file[\(idx)]: path=\(path) size=\(size)")
    }

    // MARK: 4. Select target file

    let targetFileIndex: Int
    if let userIdx = testArgs.fileIndex {
        guard userIdx >= 0 && userIdx < files.count else {
            fail("--file-index \(userIdx) out of range (file count: \(files.count))")
            return failures
        }
        targetFileIndex = userIdx
        log("Using user-specified file index \(targetFileIndex)")
    } else {
        var largestIdx = 0
        var largestSize: Int64 = -1
        for f in files {
            let size = (f["size"] as? NSNumber)?.int64Value ?? 0
            let idx  = (f["index"] as? NSNumber)?.intValue ?? 0
            if size > largestSize { largestSize = size; largestIdx = idx }
        }
        targetFileIndex = largestIdx
        log("Auto-selected largest file at index \(targetFileIndex) (size: \(largestSize) bytes)")
    }

    guard let targetFile = files.first(where: { ($0["index"] as? NSNumber)?.intValue == targetFileIndex }) else {
        fail("Could not locate file dict for index \(targetFileIndex)")
        return failures
    }
    let targetPath = targetFile["path"] as? String ?? "unknown"
    let contentLength = (targetFile["size"] as? NSNumber)?.int64Value ?? 0
    let contentType = mimeType(forPath: targetPath)
    log("Target file: \(targetPath) (\(contentLength) bytes, \(contentType))")

    // MARK: 5. Compute first 8 piece indices for the target file

    var fileStart: Int64 = 0, fileEnd: Int64 = 0
    do {
        try bridge.fileByteRange(torrentID,
                                 fileIndex: Int32(targetFileIndex),
                                 start: &fileStart,
                                 end: &fileEnd)
    } catch {
        fail("fileByteRange failed: \(error)")
        return failures
    }
    log("File byte range: [\(fileStart), \(fileEnd))")

    let firstPiece = Int(fileStart / pieceLen)
    let targetPieceCount = min(8, Int((fileEnd - fileStart + pieceLen - 1) / pieceLen))
    let requiredPieces = Set((firstPiece ..< firstPiece + targetPieceCount))
    log("Need pieces \(firstPiece)–\(firstPiece + targetPieceCount - 1) (\(targetPieceCount) pieces)")

    // MARK: 6. Wait for the first 8 pieces to download (up to 180s)

    log("Waiting up to 180s for first \(targetPieceCount) pieces of target file...")
    let downloadDeadline = Date().addingTimeInterval(180)
    var haveCount = 0
    var lastProgressLog = Date()

    while Date() < downloadDeadline {
        if let pieces = try? bridge.havePieces(torrentID) {
            let pieceSet = Set(pieces.compactMap { $0.intValue })
            haveCount = requiredPieces.intersection(pieceSet).count
            if haveCount >= targetPieceCount {
                log("Have all \(targetPieceCount) required piece(s) — proceeding")
                break
            }
        }
        if Date().timeIntervalSince(lastProgressLog) >= 10 {
            log("  ... still waiting, have \(haveCount)/\(targetPieceCount) required piece(s)")
            lastProgressLog = Date()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    guard haveCount >= targetPieceCount else {
        fail("DOWNLOAD_TIMEOUT — only \(haveCount)/\(targetPieceCount) pieces within 180s. Insufficient peers?")
        exit(2)
    }

    // MARK: 7. Set up StreamRegistry and GatewayListener

    let registry = StreamRegistry()
    let streamID = "e2e-\(UUID().uuidString)"

    do {
        try registry.createStream(
            streamID: streamID,
            contentType: contentType,
            contentLength: contentLength,
            bridge: bridge,
            torrentID: torrentID,
            fileIndex: targetFileIndex
        )
    } catch {
        fail("createStream threw: \(error)")
        return failures
    }
    defer { registry.closeStream(streamID) }

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

    gatewayListener.requestHandler = { request in
        registry.handleRequest(request) ?? HTTPRangeResponse.notFound()
    }
    gatewayListener.onReady = { port in
        listenerPort = port
        listenerReady.signal()
    }
    gatewayListener.start()

    guard listenerReady.wait(timeout: .now() + .seconds(10)) == .success else {
        fail("GatewayListener did not become ready within 10s")
        return failures
    }
    log("GatewayListener ready on port \(listenerPort)")

    let baseURL = URL(string: "http://127.0.0.1:\(listenerPort)/stream/\(streamID)")!

    // MARK: 8. Test: HEAD → 200 with correct Content-Length

    log("--- Test: HEAD ---")
    var headReq = URLRequest(url: baseURL)
    headReq.httpMethod = "HEAD"
    if let r = httpRoundTrip(request: headReq) {
        assert_(r.statusCode == 200,
                "HEAD: expected 200, got \(r.statusCode)")
        let cl = r.headers["Content-Length"] as? String
        assert_(cl == "\(contentLength)",
                "HEAD: Content-Length expected \(contentLength), got \(cl ?? "nil")")
        log("HEAD → \(r.statusCode), Content-Length: \(cl ?? "nil") \(r.statusCode == 200 ? "PASS" : "FAIL")")
    } else {
        fail("HEAD: no HTTP response received")
    }

    // MARK: 9. Test: GET bytes=0-65535 → 206 with correct Content-Range

    log("--- Test: GET bytes=0-65535 ---")
    let rangeEnd: Int64 = min(65535, contentLength - 1)
    var getReq1 = URLRequest(url: baseURL)
    getReq1.httpMethod = "GET"
    getReq1.setValue("bytes=0-\(rangeEnd)", forHTTPHeaderField: "Range")
    if let r = httpRoundTrip(request: getReq1) {
        assert_(r.statusCode == 206,
                "GET bytes=0-\(rangeEnd): expected 206, got \(r.statusCode)")
        let cr = r.headers["Content-Range"] as? String
        let expectedCR = "bytes 0-\(rangeEnd)/\(contentLength)"
        assert_(cr == expectedCR,
                "GET bytes=0-\(rangeEnd): Content-Range expected '\(expectedCR)', got '\(cr ?? "nil")'")
        let bodyLen = r.body?.count ?? 0
        assert_(bodyLen == Int(rangeEnd) + 1,
                "GET bytes=0-\(rangeEnd): expected \(rangeEnd + 1) bytes, got \(bodyLen)")
        log("GET bytes=0-\(rangeEnd) → \(r.statusCode), body=\(bodyLen) bytes \(r.statusCode == 206 ? "PASS" : "FAIL")")
    } else {
        fail("GET bytes=0-\(rangeEnd): no HTTP response received")
    }

    // MARK: 10. Test: GET mid-range → 206

    // Pick a mid-point safely inside the guaranteed-available region (first 8 pieces of the file).
    // The available bytes are file offsets 0 ..< (targetPieceCount * pieceLen).
    // Use the second quarter of the available region to avoid overlap with the first range test.
    let availableBytes = Int64(targetPieceCount) * pieceLen
    let midStart: Int64 = min(availableBytes / 4, contentLength - 1024)
    let midEnd: Int64   = min(midStart + 1023, contentLength - 1)

    log("--- Test: GET bytes=\(midStart)-\(midEnd) (mid-range) ---")
    var getReq2 = URLRequest(url: baseURL)
    getReq2.httpMethod = "GET"
    getReq2.setValue("bytes=\(midStart)-\(midEnd)", forHTTPHeaderField: "Range")
    if let r = httpRoundTrip(request: getReq2) {
        assert_(r.statusCode == 206,
                "GET bytes=\(midStart)-\(midEnd): expected 206, got \(r.statusCode)")
        let cr = r.headers["Content-Range"] as? String
        let expectedCR = "bytes \(midStart)-\(midEnd)/\(contentLength)"
        assert_(cr == expectedCR,
                "GET bytes=\(midStart)-\(midEnd): Content-Range expected '\(expectedCR)', got '\(cr ?? "nil")'")
        let bodyLen = r.body?.count ?? 0
        let expectedLen = Int(midEnd - midStart + 1)
        assert_(bodyLen == expectedLen,
                "GET bytes=\(midStart)-\(midEnd): expected \(expectedLen) bytes, got \(bodyLen)")
        log("GET bytes=\(midStart)-\(midEnd) → \(r.statusCode), body=\(bodyLen) bytes \(r.statusCode == 206 ? "PASS" : "FAIL")")
    } else {
        fail("GET bytes=\(midStart)-\(midEnd): no HTTP response received")
    }

    // MARK: 11. Test: GET unknown stream → 404

    log("--- Test: GET /stream/unknown-id → 404 ---")
    var unknownReq = URLRequest(url: URL(string: "http://127.0.0.1:\(listenerPort)/stream/unknown-\(UUID().uuidString)")!)
    unknownReq.httpMethod = "GET"
    if let r = httpRoundTrip(request: unknownReq) {
        assert_(r.statusCode == 404,
                "GET /stream/unknown: expected 404, got \(r.statusCode)")
        log("GET /stream/unknown → \(r.statusCode) \(r.statusCode == 404 ? "PASS" : "FAIL")")
    } else {
        fail("GET /stream/unknown: no HTTP response received")
    }

    // MARK: 12. Byte verification: HTTP bytes must match TorrentBridge.readBytes

    log("--- Test: byte accuracy (HTTP vs TorrentBridge.readBytes) ---")
    // Re-fetch the first range via HTTP and compare to what the bridge returns.
    let verifyLen: Int64 = min(rangeEnd + 1, contentLength)
    var verifyReq = URLRequest(url: baseURL)
    verifyReq.httpMethod = "GET"
    verifyReq.setValue("bytes=0-\(verifyLen - 1)", forHTTPHeaderField: "Range")
    if let r = httpRoundTrip(request: verifyReq), let httpBody = r.body {
        do {
            let bridgeBytes = try bridge.readBytes(torrentID,
                                                   fileIndex: Int32(targetFileIndex),
                                                   offset: 0,
                                                   length: verifyLen)
            assert_(httpBody == bridgeBytes,
                    "Byte accuracy: HTTP body (\(httpBody.count) bytes) does not match TorrentBridge.readBytes (\(bridgeBytes.count) bytes)")
            if httpBody == bridgeBytes {
                log("Byte accuracy PASS — HTTP and bridge agree on \(httpBody.count) bytes")
            }
        } catch {
            fail("Byte accuracy: TorrentBridge.readBytes threw: \(error)")
        }
    } else {
        fail("Byte accuracy: HTTP re-fetch failed")
    }

    // MARK: Done

    if failures.isEmpty {
        log("=== ALL TESTS PASSED ===")
    } else {
        log("=== \(failures.count) FAILURE(S) — see FAIL lines above ===")
    }
    return failures
}

// MARK: - Entry point

/// Entry point called from main.swift when --stream-e2e-self-test is passed.
/// `trailingArgs` is everything after --stream-e2e-self-test in CommandLine.arguments.
func runStreamE2ESelfTestAndExit(trailingArgs: [String]) {
    guard let testArgs = parseSelfTestArgs(from: trailingArgs) else {
        printSelfTestUsage()
        exit(1)
    }
    let failures = runSelfTest(testArgs: testArgs)
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
