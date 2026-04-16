// Probe for T-CACHE-EVICTION: empirically verify libtorrent's file_priority and
// storage behaviour against a real sparse file on APFS/HFS+.
//
// Activated when EngineService is launched with:
//   EngineService --cache-eviction-probe <magnet-or-torrent-path>
//   EngineService --cache-eviction-probe <magnet-or-torrent-path> --file-index N
//   EngineService --cache-eviction-probe          ← prints usage and exits 1
//
// After running, paste the NSLog output into docs/libtorrent-eviction-notes.md.
//
// Gaps noted at time of writing:
//   - TorrentBridge exposes setFilePriority (file granularity) but NOT
//     setPiecePriority (piece granularity). Probe B uses file priority as the
//     closest available lever.
//   - Downloaded content is LEFT on disk after the probe so iterative reruns
//     don't require re-downloading. The save path is NSTemporaryDirectory().

#if DEBUG

import Foundation

// MARK: - Filesystem helpers

/// Returns (apparentSize, onDiskBytes) for the file at `path` using stat(2).
/// `onDiskBytes` reflects allocated blocks only — sparse regions cost nothing.
private func statFile(_ path: String) -> (apparentSize: Int64, onDiskBytes: Int64)? {
    var st = stat()
    guard stat(path, &st) == 0 else { return nil }
    let apparent = Int64(st.st_size)
    // st_blocks is in 512-byte units regardless of filesystem block size.
    let onDisk = Int64(st.st_blocks) * 512
    return (apparent, onDisk)
}

/// Attempts to punch a sparse hole in the file at `fd` over [offset, offset+length).
/// Uses fcntl(F_PUNCHHOLE) on Apple platforms (APFS supports it; HFS+ does not).
/// Returns true if the syscall succeeded.
private func punchHole(fd: Int32, offset: Int64, length: Int64) -> Bool {
#if canImport(Darwin)
    var args = fpunchhole_t()
    args.fp_flags = 0
    args.reserved = 0
    args.fp_offset = off_t(offset)
    args.fp_length = off_t(length)
    return fcntl(fd, F_PUNCHHOLE, &args) == 0
#else
    return false
#endif
}

// MARK: - Argument parsing

private struct ProbeArgs {
    enum Source {
        case magnet(String)
        case torrentFile(String)   // absolute, verified to exist
    }
    let source: Source
    let fileIndex: Int?            // nil = probe picks largest file
}

private func parseProbeArgs(from args: [String]) -> ProbeArgs? {
    // args here are the elements *after* --cache-eviction-probe.
    guard !args.isEmpty else { return nil }

    let first = args[0]
    let source: ProbeArgs.Source
    if first.hasPrefix("magnet:") {
        source = .magnet(first)
    } else {
        // Treat as file path. Resolve to absolute.
        let url = URL(fileURLWithPath: first).standardized
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("[CacheEvictionProbe] ERROR: .torrent file not found: %@", url.path)
            return nil
        }
        source = .torrentFile(url.path)
    }

    var fileIndex: Int? = nil
    if let fiIdx = args.firstIndex(of: "--file-index"), fiIdx + 1 < args.count,
       let n = Int(args[fiIdx + 1]) {
        fileIndex = n
    }

    return ProbeArgs(source: source, fileIndex: fileIndex)
}

private func printProbeUsage() {
    let usage = """
[CacheEvictionProbe] USAGE:
  EngineService --cache-eviction-probe <magnet-or-torrent-path>
  EngineService --cache-eviction-probe <magnet-or-torrent-path> --file-index N

  <magnet-or-torrent-path>  A magnet: URI or an absolute path to a .torrent file.
  --file-index N            Probe the file at index N (default: largest file in torrent).

  Suggested well-seeded magnet (Internet Archive — Big Buck Bunny, ~160 MB MP4):
    magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969

  Downloaded content is left in NSTemporaryDirectory() after the probe so
  re-runs skip re-downloading. Paste NSLog output into docs/libtorrent-eviction-notes.md.
"""
    NSLog("%@", usage)
}

// MARK: - Probe entry point

/// Runs the four eviction probes against a real torrent (magnet or .torrent file).
/// Returns a list of labelled observation strings for the user to record.
/// Failures are embedded inline with "ERROR:" prefix so they stand out.
private func runCacheEvictionProbe(probeArgs: ProbeArgs) -> [String] {
    var log: [String] = []

    func note(_ s: String) {
        NSLog("[CacheEvictionProbe] %@", s)
        log.append(s)
    }
    func probeError(_ s: String) {
        let msg = "ERROR: \(s)"
        NSLog("[CacheEvictionProbe] %@", msg)
        log.append(msg)
    }

    note("=== T-CACHE-EVICTION probe starting ===")
    note("Paste all lines below into docs/libtorrent-eviction-notes.md")

    // MARK: - Setup: create bridge and add torrent

    let bridge = TorrentBridge()

    bridge.subscribeAlerts { alert in
        let type = alert["type"] as? String ?? "?"
        let msg  = alert["message"] as? String ?? ""
        NSLog("[CacheEvictionProbe:alert] type=%@ msg=%@", type, msg)
    }

    // The save path is NSTemporaryDirectory() — the bridge hardcodes this.
    // Leaving content there after the probe allows iterative reruns.
    let savePath = NSTemporaryDirectory()
    note("Setup: save path = \(savePath)")

    let torrentID: String
    switch probeArgs.source {
    case .magnet(let uri):
        note("Setup: adding magnet \(uri)")
        do {
            torrentID = try bridge.addMagnet(uri)
        } catch {
            probeError("addMagnet failed: \(error)")
            bridge.shutdown()
            return log
        }

    case .torrentFile(let path):
        note("Setup: adding .torrent file at \(path)")
        do {
            torrentID = try bridge.addTorrentFile(atPath: path)
        } catch {
            probeError("addTorrentFile failed: \(error)")
            bridge.shutdown()
            return log
        }
    }
    note("Setup: torrent id = \(torrentID)")

    // MARK: - Wait for metadata (magnet links start without file info)

    note("Setup: waiting up to 60s for torrent metadata...")
    let metadataDeadline = Date().addingTimeInterval(60)
    var pieceLen: Int64 = 0
    while Date() < metadataDeadline {
        pieceLen = bridge.pieceLength(torrentID)
        if pieceLen > 0 { break }
        Thread.sleep(forTimeInterval: 0.5)
    }

    guard pieceLen > 0 else {
        probeError("METADATA_TIMEOUT — check magnet/peers/network. Is the magnet well-seeded?")
        bridge.removeTorrent(torrentID, deleteData: false)
        bridge.shutdown()
        exit(2)
    }
    note("Setup: metadata arrived — piece length = \(pieceLen) bytes")

    // MARK: - Report torrent properties

    let files: [NSDictionary]
    do {
        files = try bridge.listFiles(torrentID).map { $0 as NSDictionary }
    } catch {
        probeError("listFiles failed: \(error)")
        bridge.removeTorrent(torrentID, deleteData: false)
        bridge.shutdown()
        return log
    }

    note("Setup: file count = \(files.count)")
    for f in files {
        let relPath = f["path"] as? String ?? "?"
        let size    = (f["size"] as? NSNumber)?.int64Value ?? -1
        let idx     = (f["index"] as? NSNumber)?.intValue ?? -1
        note("  file[\(idx)]: path=\(relPath) size=\(size) bytes")
    }

    // Derive total size from files to compute piece count.
    let totalBytes = files.reduce(Int64(0)) { acc, f in
        acc + ((f["size"] as? NSNumber)?.int64Value ?? 0)
    }
    let pieceCount = pieceLen > 0 ? (totalBytes + pieceLen - 1) / pieceLen : 0
    note("Setup: totalBytes=\(totalBytes) pieceCount~=\(pieceCount)")

    // Pick the file to probe.
    let targetFileIndex: Int
    if let userIdx = probeArgs.fileIndex {
        guard userIdx >= 0 && userIdx < files.count else {
            probeError("--file-index \(userIdx) out of range (file count = \(files.count))")
            bridge.removeTorrent(torrentID, deleteData: false)
            bridge.shutdown()
            return log
        }
        targetFileIndex = userIdx
        note("Setup: using user-specified file index \(targetFileIndex)")
    } else {
        // Pick largest file.
        var largestIdx = 0
        var largestSize: Int64 = -1
        for f in files {
            let size = (f["size"] as? NSNumber)?.int64Value ?? 0
            let idx  = (f["index"] as? NSNumber)?.intValue ?? 0
            if size > largestSize {
                largestSize = size
                largestIdx = idx
            }
        }
        targetFileIndex = largestIdx
        note("Setup: auto-selected largest file at index \(targetFileIndex) (size=\(largestSize) bytes)")
    }

    if let targetFile = files.first(where: { ($0["index"] as? NSNumber)?.intValue == targetFileIndex }) {
        note("Setup: probing file: \(targetFile["path"] as? String ?? "?")")
    }

    // MARK: - Wait for pieces to download

    note("Setup: waiting up to 120s for at least 8 pieces of target file to download...")
    let downloadDeadline = Date().addingTimeInterval(120)
    var haveCount = 0
    var lastProgressLog = Date()

    while Date() < downloadDeadline {
        if let pieces = try? bridge.havePieces(torrentID) {
            haveCount = pieces.count
            if haveCount >= 8 {
                note("  downloaded \(haveCount) piece(s) — proceeding")
                break
            }
        }
        // Report progress every 10 seconds.
        if Date().timeIntervalSince(lastProgressLog) >= 10 {
            note("  ... still waiting, have \(haveCount) piece(s) so far")
            lastProgressLog = Date()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    if haveCount == 0 {
        probeError("DOWNLOAD_TIMEOUT — no pieces arrived within 120s. Insufficient peers? Try a different magnet.")
        bridge.removeTorrent(torrentID, deleteData: false)
        bridge.shutdown()
        exit(2)
    }
    if haveCount < 8 {
        note("  WARNING: only \(haveCount) piece(s) available after 120s; probes may be limited")
    }

    // MARK: - Resolve the on-disk path of the target file

    // libtorrent saves into savePath + relative path from listFiles.
    var downloadedFilePath: String? = nil
    if let targetFile = files.first(where: { ($0["index"] as? NSNumber)?.intValue == targetFileIndex }),
       let relPath = targetFile["path"] as? String {
        let candidate = (savePath as NSString).appendingPathComponent(relPath)
        if FileManager.default.fileExists(atPath: candidate) {
            downloadedFilePath = candidate
            note("Setup: on-disk path resolved: \(candidate)")
        } else {
            note("Setup: WARNING — could not find file on disk at \(candidate)")
            note("  (it may not exist yet if no pieces have been written)")
        }
    }

    // MARK: - Probe A: file size and on-disk blocks before eviction

    note("")
    note("--- Probe A: file state BEFORE priority change ---")
    if let fp = downloadedFilePath, let s = statFile(fp) {
        note("Probe A: file size=\(s.apparentSize) bytes, on-disk=\(s.onDiskBytes) bytes")
        note("Probe A: sparse ratio = \(s.onDiskBytes == 0 ? "n/a" : String(format: "%.1f%%", Double(s.onDiskBytes) / Double(s.apparentSize) * 100))")
    } else {
        note("Probe A: SKIPPED — could not resolve on-disk file path (see setup warnings above)")
    }
    do {
        let pieces = try bridge.havePieces(torrentID)
        note("Probe A: havePieces count=\(pieces.count), indices=\(pieces.prefix(8).map(\.intValue))\(pieces.count > 8 ? "..." : "")")
    } catch {
        probeError("Probe A: havePieces failed: \(error)")
    }

    // MARK: - Probe B: set file priority to 0, observe immediate file state

    note("")
    note("--- Probe B: set file priority to 0 (ignore), observe file state ---")
    note("  Note: TorrentBridge exposes setFilePriority (file granularity) only.")
    note("  Per-piece priority (lt::torrent_handle::piece_priority) is NOT bridged.")
    note("  This probe uses file-level priority as the coarsest available lever.")
    do {
        try bridge.setFilePriority(torrentID, fileIndex: Int32(targetFileIndex), priority: 0)
        note("Probe B: setFilePriority(\(torrentID), fileIndex:\(targetFileIndex), priority:0) succeeded")
    } catch {
        probeError("Probe B: setFilePriority failed: \(error)")
    }

    // Immediate stat — no sleep; we want the instant view before libtorrent does anything.
    if let fp = downloadedFilePath, let s = statFile(fp) {
        note("Probe B (immediate): file size=\(s.apparentSize), on-disk=\(s.onDiskBytes)")
    } else {
        note("Probe B (immediate): SKIPPED — no file path")
    }

    // Also check after a short wait to see if libtorrent reacts asynchronously.
    Thread.sleep(forTimeInterval: 2)
    if let fp = downloadedFilePath, let s = statFile(fp) {
        note("Probe B (after 2s): file size=\(s.apparentSize), on-disk=\(s.onDiskBytes)")
    }
    do {
        let pieces = try bridge.havePieces(torrentID)
        note("Probe B: havePieces count=\(pieces.count) (did priority=0 evict pieces?)")
    } catch {
        probeError("Probe B: havePieces failed: \(error)")
    }

    // MARK: - Probe C: explicit sparse-hole punch attempt via F_PUNCHHOLE

    note("")
    note("--- Probe C: attempt F_PUNCHHOLE on file region ---")
    note("  Hypothesis: libtorrent does not truncate/sparsify on priority=0;")
    note("  the app must call F_PUNCHHOLE itself to reclaim APFS disk space.")
    if let fp = downloadedFilePath {
        let fd = open(fp, O_RDWR)
        if fd < 0 {
            let errStr = String(cString: strerror(errno))
            probeError("Probe C: open(\(fp)) failed: \(errStr) (errno=\(errno))")
        } else {
            var preStat = stat()
            stat(fp, &preStat)
            let fileSize = Int64(preStat.st_size)
            note("Probe C: file size before punch = \(fileSize) bytes")

            // Punch from byte 0 to half the file.
            let punchLen = fileSize / 2
            let success = punchHole(fd: fd, offset: 0, length: punchLen)
            if success {
                note("Probe C: F_PUNCHHOLE succeeded for [0, \(punchLen))")
            } else {
                let errStr = String(cString: strerror(errno))
                note("Probe C: F_PUNCHHOLE failed: \(errStr) (errno=\(errno))")
                note("  On HFS+: ENOTSUP is expected (no sparse file support).")
                note("  On APFS: success is expected.")
            }
            close(fd)

            if let s = statFile(fp) {
                note("Probe C: after F_PUNCHHOLE — file size=\(s.apparentSize), on-disk=\(s.onDiskBytes)")
                if s.onDiskBytes < preStat.st_blocks * 512 {
                    note("Probe C: RESULT: disk blocks decreased — APFS sparse region created.")
                } else {
                    note("Probe C: RESULT: disk blocks unchanged — punch had no effect.")
                }
            }

            do {
                let pieces = try bridge.havePieces(torrentID)
                note("Probe C: havePieces count=\(pieces.count) after punch (libtorrent's view unchanged?)")
            } catch {
                probeError("Probe C: havePieces failed: \(error)")
            }

            // Try to read from the punched region via TorrentBridge.
            do {
                let data = try bridge.readBytes(torrentID, fileIndex: Int32(targetFileIndex), offset: 0, length: 4096)
                note("Probe C: readBytes from punched region returned \(data.count) bytes")
                note("  (non-nil means libtorrent served bytes; are they zeros from the hole?)")
                let allZero = data.allSatisfy { $0 == 0 }
                note("  data is all-zero: \(allZero)")
            } catch {
                note("Probe C: readBytes from punched region threw: \(error)")
                note("  (error is expected if libtorrent detects the missing data)")
            }
        }
    } else {
        note("Probe C: SKIPPED — no file path resolved")
    }

    // Truncate variant.
    note("")
    note("Probe C (truncate variant): attempt ftruncate to see libtorrent's reaction")
    if let fp = downloadedFilePath {
        var preStat = stat()
        stat(fp, &preStat)
        let originalSize = Int64(preStat.st_size)

        let fd2 = open(fp, O_RDWR)
        if fd2 >= 0 {
            if ftruncate(fd2, off_t(originalSize / 2)) == 0 {
                note("Probe C (truncate): ftruncate to \(originalSize / 2) succeeded")
            } else {
                let errStr = String(cString: strerror(errno))
                note("Probe C (truncate): ftruncate failed: \(errStr) (errno=\(errno))")
            }
            close(fd2)

            if let s = statFile(fp) {
                note("Probe C (truncate): file size=\(s.apparentSize), on-disk=\(s.onDiskBytes)")
            }

            Thread.sleep(forTimeInterval: 2)
            do {
                let pieces = try bridge.havePieces(torrentID)
                note("Probe C (truncate): havePieces after 2s = \(pieces.count) pieces")
            } catch {
                probeError("Probe C (truncate): havePieces failed: \(error)")
            }
        } else {
            let errStr = String(cString: strerror(errno))
            probeError("Probe C (truncate): open failed: \(errStr) (errno=\(errno))")
        }
    } else {
        note("Probe C (truncate): SKIPPED — no file path")
    }

    // MARK: - Probe D: restore priority to 1, verify libtorrent re-fetches

    note("")
    note("--- Probe D: restore file priority to 1, wait for re-fetch ---")
    do {
        try bridge.setFilePriority(torrentID, fileIndex: Int32(targetFileIndex), priority: 1)
        note("Probe D: setFilePriority(\(torrentID), fileIndex:\(targetFileIndex), priority:1) succeeded")
    } catch {
        probeError("Probe D: setFilePriority failed: \(error)")
    }

    note("Probe D: waiting up to 15s for re-fetch...")
    var piecesAfter: [NSNumber] = []
    for attempt in 1...30 {
        Thread.sleep(forTimeInterval: 0.5)
        if let pieces = try? bridge.havePieces(torrentID) {
            piecesAfter = pieces
            note("  attempt \(attempt): havePieces count=\(pieces.count)")
            if pieces.count >= haveCount {
                note("  piece count restored — stopping early")
                break
            }
        }
    }
    note("Probe D: final havePieces count=\(piecesAfter.count)")
    note("  indices=\(piecesAfter.prefix(8).map(\.intValue))\(piecesAfter.count > 8 ? "..." : "")")
    if let fp = downloadedFilePath, let s = statFile(fp) {
        note("Probe D: file size=\(s.apparentSize), on-disk=\(s.onDiskBytes)")
    }

    // MARK: - Teardown

    // Remove from libtorrent but leave downloaded content for re-runs.
    bridge.removeTorrent(torrentID, deleteData: false)
    Thread.sleep(forTimeInterval: 0.1)
    bridge.shutdown()

    note("")
    note("=== T-CACHE-EVICTION probe complete ===")
    note("Downloaded content left at: \(savePath)  (intentional — re-runs skip re-download)")
    note("Copy all lines above into docs/libtorrent-eviction-notes.md")
    note("")
    note("Key questions to answer from the output:")
    note("  1. Did setFilePriority(0) change on-disk bytes? (Probe A vs B)")
    note("  2. Did F_PUNCHHOLE succeed on this filesystem? (Probe C)")
    note("  3. After punch, did libtorrent's havePieces still show the punched pieces? (Probe C)")
    note("  4. After ftruncate, did libtorrent automatically re-expand the file? (Probe C truncate)")
    note("  5. After restoring priority=1, did libtorrent re-fetch the missing pieces? (Probe D)")
    note("  6. What is the piece length for this torrent? (Setup output)")

    return log
}

/// Entry point called from main.swift when --cache-eviction-probe is passed.
/// `trailingArgs` is everything after --cache-eviction-probe in CommandLine.arguments.
func runCacheEvictionProbeAndExit(trailingArgs: [String]) {
    guard let probeArgs = parseProbeArgs(from: trailingArgs) else {
        printProbeUsage()
        exit(1)
    }
    let lines = runCacheEvictionProbe(probeArgs: probeArgs)
    _ = lines
    exit(0)
}

#endif // DEBUG
