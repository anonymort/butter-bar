// Probe for T-CACHE-EVICTION: empirically verify libtorrent's file_priority and
// storage behaviour against a real sparse file on APFS/HFS+.
//
// Activated when EngineService is launched with the argument:
//   --cache-eviction-probe
//
// This probe MUST be run by the user on a real machine. It cannot be automated —
// it measures actual filesystem behaviour. After running, paste the NSLog output
// into docs/libtorrent-eviction-notes.md.
//
// Gaps noted at time of writing:
//   - TorrentBridge exposes setFilePriority (file granularity) but NOT
//     setPiecePriority (piece granularity). Probe B uses file priority as the
//     closest available lever. If per-piece eviction is needed, TorrentBridge
//     will need a new setPiecePriority method.
//   - createTestTorrent builds a torrent from a source directory with a default
//     piece size chosen by libtorrent (typically 16 KiB for small files, up to
//     1 MiB for large files). The probe creates a 4 MB file to target a
//     256 KiB piece size, giving ~16 pieces. Actual piece size is logged.

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

// MARK: - Probe entry point

/// Runs the four eviction probes against a synthetic torrent.
/// Returns a list of labelled observation strings for the user to record.
/// Failures are embedded inline with "ERROR:" prefix so they stand out.
func runCacheEvictionProbe() -> [String] {
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

    // MARK: - Setup: create a 4 MB synthetic file → torrent

    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("CacheEvictionProbe-\(UUID().uuidString)", isDirectory: true)
    let sourceDir = tmpDir.appendingPathComponent("source", isDirectory: true)
    let downloadDir = tmpDir.appendingPathComponent("download", isDirectory: true)
    let torrentPath = tmpDir.appendingPathComponent("probe.torrent").path

    defer { try? FileManager.default.removeItem(at: tmpDir) }

    do {
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        // 4 MB → libtorrent typically picks 256 KiB pieces → ~16 pieces.
        // Fill with non-zero pattern so libtorrent doesn't optimise it away.
        let fileSize = 4 * 1024 * 1024
        var data = Data(count: fileSize)
        data.withUnsafeMutableBytes { ptr in
            for i in 0 ..< fileSize { ptr[i] = UInt8(i & 0xFF) }
        }
        let srcFile = sourceDir.appendingPathComponent("probe.bin")
        try data.write(to: srcFile)
        note("Setup: wrote \(fileSize) byte source file at \(srcFile.path)")
    } catch {
        probeError("Setup failed: \(error)")
        return log
    }

    // MARK: - Create .torrent

    do {
        _ = try TorrentBridge.createTestTorrent(sourceDir.path, outputPath: torrentPath)
        note("Setup: created .torrent at \(torrentPath)")
    } catch {
        probeError("createTestTorrent failed: \(error)")
        return log
    }

    // MARK: - Add torrent, seed from source dir, download into downloadDir

    let bridge = TorrentBridge()

    // Subscribe alerts (needed for internal libtorrent polling to function).
    bridge.subscribeAlerts { alert in
        let type = alert["type"] as? String ?? "?"
        let msg  = alert["message"] as? String ?? ""
        NSLog("[CacheEvictionProbe:alert] type=%@ msg=%@", type, msg)
    }

    let torrentID: String
    do {
        torrentID = try bridge.addTorrentFile(atPath: torrentPath)
        note("Setup: added torrent id=\(torrentID)")
    } catch {
        probeError("addTorrentFile failed: \(error)")
        bridge.shutdown()
        return log
    }

    // Log piece size for the user's reference.
    let pieceLen = bridge.pieceLength(torrentID)
    note("Setup: piece length = \(pieceLen) bytes")
    if pieceLen == 0 {
        note("  (metadata not yet ready — waiting 3s)")
        Thread.sleep(forTimeInterval: 3)
        let pl2 = bridge.pieceLength(torrentID)
        note("  piece length after wait = \(pl2) bytes")
    }

    // Give libtorrent time to find the file and mark pieces available.
    // Since createTestTorrent adds the source as a seed, pieces should appear quickly.
    note("Setup: waiting up to 10s for pieces to become available...")
    var haveCount = 0
    for attempt in 1...20 {
        Thread.sleep(forTimeInterval: 0.5)
        if let pieces = try? bridge.havePieces(torrentID) {
            haveCount = pieces.count
            if haveCount > 0 {
                note("  attempt \(attempt): \(haveCount) piece(s) available — proceeding")
                break
            }
        }
    }
    if haveCount == 0 {
        note("  WARNING: no pieces available after 10s; probes will reflect an empty file")
    }

    // Locate the downloaded file path.
    // listFiles returns paths relative to the save path; the bridge uses the system
    // temp dir as the save root. We need the absolute path for stat(2).
    var downloadedFilePath: String? = nil
    do {
        let files = try bridge.listFiles(torrentID)
        note("Setup: listFiles returned \(files.count) file(s)")
        for f in files {
            let relPath = f["path"] as? String ?? "?"
            let size    = (f["size"] as? NSNumber)?.int64Value ?? -1
            note("  file: path=\(relPath) size=\(size)")
        }
        // The file is always at the torrent's save path (tmpDir) + relative path.
        if let first = files.first, let relPath = first["path"] as? String {
            // libtorrent writes into the session's save_path, which createTestTorrent
            // sets to sourceDir. For probing, re-derive from sourceDir.
            let candidate = sourceDir.appendingPathComponent(relPath).path
            if FileManager.default.fileExists(atPath: candidate) {
                downloadedFilePath = candidate
                note("  resolved on-disk path: \(candidate)")
            } else {
                // Fallback: try under tmpDir root.
                let candidate2 = tmpDir.appendingPathComponent(relPath).path
                if FileManager.default.fileExists(atPath: candidate2) {
                    downloadedFilePath = candidate2
                    note("  resolved on-disk path (fallback): \(candidate2)")
                } else {
                    note("  WARNING: could not resolve on-disk path for '\(relPath)'")
                    note("  candidate1=\(candidate)")
                    note("  candidate2=\(candidate2)")
                }
            }
        }
    } catch {
        probeError("listFiles failed: \(error)")
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
        try bridge.setFilePriority(torrentID, fileIndex: 0, priority: 0)
        note("Probe B: setFilePriority(0, fileIndex:0, priority:0) succeeded")
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
            // Get file size first.
            var preStat = stat()
            stat(fp, &preStat)
            let fileSize = Int64(preStat.st_size)
            note("Probe C: file size before punch = \(fileSize) bytes")

            // Punch from byte 0 to half the file (first 8 pieces if 16 total).
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

            // Stat after punch.
            if let s = statFile(fp) {
                note("Probe C: after F_PUNCHHOLE — file size=\(s.apparentSize), on-disk=\(s.onDiskBytes)")
                if s.onDiskBytes < preStat.st_blocks * 512 {
                    note("Probe C: RESULT: disk blocks decreased — APFS sparse region created.")
                } else {
                    note("Probe C: RESULT: disk blocks unchanged — punch had no effect.")
                }
            }

            // Now check: does libtorrent still think these bytes are present?
            do {
                let pieces = try bridge.havePieces(torrentID)
                note("Probe C: havePieces count=\(pieces.count) after punch (libtorrent's view unchanged?)")
            } catch {
                probeError("Probe C: havePieces failed: \(error)")
            }

            // Try to read from the punched region via TorrentBridge — should this fail?
            do {
                let data = try bridge.readBytes(torrentID, fileIndex: 0, offset: 0, length: 4096)
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

    // Also try ftruncate to see if it causes libtorrent to notice.
    note("")
    note("Probe C (truncate variant): attempt ftruncate to see libtorrent's reaction")
    if let fp = downloadedFilePath {
        var preStat = stat()
        stat(fp, &preStat)
        let originalSize = Int64(preStat.st_size)

        // Truncate to half. NOTE: this is destructive — it modifies the seeding file.
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

            // Restore size with ftruncate + zero-fill would corrupt the file;
            // libtorrent may re-expand and re-fetch. We check havePieces.
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
        try bridge.setFilePriority(torrentID, fileIndex: 0, priority: 1)
        note("Probe D: setFilePriority(0, fileIndex:0, priority:1) succeeded")
    } catch {
        probeError("Probe D: setFilePriority failed: \(error)")
    }

    // Wait up to 15 seconds for libtorrent to notice and re-fetch.
    note("Probe D: waiting up to 15s for re-fetch...")
    var piecesAfter: [NSNumber] = []
    for attempt in 1...30 {
        Thread.sleep(forTimeInterval: 0.5)
        if let pieces = try? bridge.havePieces(torrentID) {
            piecesAfter = pieces
            note("  attempt \(attempt): havePieces count=\(pieces.count)")
            // Stop early if piece count is back to where it was before truncation.
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

    bridge.removeTorrent(torrentID, deleteData: false)
    Thread.sleep(forTimeInterval: 0.1)
    bridge.shutdown()

    note("")
    note("=== T-CACHE-EVICTION probe complete ===")
    note("Copy all lines above into docs/libtorrent-eviction-notes.md")
    note("")
    note("Key questions to answer from the output:")
    note("  1. Did setFilePriority(0) change on-disk bytes? (Probe A vs B)")
    note("  2. Did F_PUNCHHOLE succeed on this filesystem? (Probe C)")
    note("  3. After punch, did libtorrent's havePieces still show the punched pieces? (Probe C)")
    note("  4. After ftruncate, did libtorrent automatically re-expand the file? (Probe C truncate)")
    note("  5. After restoring priority=1, did libtorrent re-fetch the missing pieces? (Probe D)")
    note("  6. What is the piece size for a 4 MB file? (Setup output)")

    return log
}

/// Entry point called from main.swift when --cache-eviction-probe is passed.
func runCacheEvictionProbeAndExit() {
    let lines = runCacheEvictionProbe()
    // Lines were already NSLogged as they were generated.
    // Exit 0 — this is a probe, not a pass/fail test.
    _ = lines
    exit(0)
}

#endif // DEBUG
