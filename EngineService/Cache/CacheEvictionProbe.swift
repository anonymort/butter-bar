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

    // -------------------------------------------------------------------------
    // Install alert collectors (used by C0, C1, C2 below)
    // Safe to replace the setup-time alert callback here: TorrentBridge serialises
    // both subscribeAlerts installation and alert drain on the same internal queue,
    // so we cannot miss or double-fire an alert during handover.
    // -------------------------------------------------------------------------
    let alertLock = NSLock()
    var hashFailedPieces: Set<Int> = []
    var pieceFinishedPieces: Set<Int> = []
    bridge.subscribeAlerts { alert in
        let type = alert["type"] as? String ?? "?"
        let msg  = alert["message"] as? String ?? ""
        NSLog("[CacheEvictionProbe:alert] type=%@ msg=%@", type, msg)

        if let idx = (alert["pieceIndex"] as? NSNumber)?.intValue {
            alertLock.lock()
            if type == "hash_failed_alert" {
                hashFailedPieces.insert(idx)
            } else if type == "piece_finished_alert" {
                pieceFinishedPieces.insert(idx)
            }
            alertLock.unlock()
        }
    }

    // -------------------------------------------------------------------------
    // Probe C0: baseline — corrupt a piece on disk + force_recheck, expect hash_failed_alert
    // Goal: confirm the bridge's alert pipeline delivers hash_failed_alert AT ALL for a
    // known-bad piece. If this fails, the pipeline is broken and all subsequent C1
    // observations are ambiguous.
    // -------------------------------------------------------------------------

    note("")
    note("--- Probe C0: baseline hash_failed via direct disk corruption + force_recheck ---")
    note("  Goal: confirm alert pipeline delivers hash_failed_alert when a piece is known-bad.")

    var c0Succeeded = false
    var c0CorruptedPiece: Int? = nil

    probeC0: do {
        var fileStart: Int64 = 0
        var fileEnd: Int64 = 0
        do {
            try bridge.fileByteRange(torrentID, fileIndex: Int32(targetFileIndex),
                                     start: &fileStart, end: &fileEnd)
        } catch {
            probeError("Probe C0: fileByteRange failed: \(error)")
            break probeC0
        }

        let havePiecesC0 = (try? bridge.havePieces(torrentID)) ?? []
        let haveSetC0 = Set(havePiecesC0.map { $0.intValue })
        let firstFullC0 = Int((fileStart + pieceLen - 1) / pieceLen)
        let lastFullC0  = Int(fileEnd / pieceLen)

        // Pick a piece near the END of the file so C1 (which picks from the start)
        // doesn't collide.
        var c0Target: Int? = nil
        for p in stride(from: lastFullC0 - 1, through: firstFullC0, by: -1) {
            if haveSetC0.contains(p) { c0Target = p; break }
        }
        guard let cp = c0Target else {
            note("Probe C0: SKIPPED — no downloaded piece fully inside target file.")
            break probeC0
        }
        note("Probe C0: target piece = \(cp)")

        alertLock.lock()
        hashFailedPieces.removeAll()
        pieceFinishedPieces.removeAll()
        alertLock.unlock()

        guard let fp = downloadedFilePath else {
            note("Probe C0: SKIPPED — no downloaded file path.")
            break probeC0
        }
        let pieceOffsetInFile = Int64(cp) * pieceLen - fileStart
        // Corrupt 32 bytes at the piece's midpoint to guarantee SHA1 mismatch.
        let corruptOffset = pieceOffsetInFile + pieceLen / 2
        let fd = open(fp, O_RDWR)
        if fd < 0 {
            probeError("Probe C0: open failed: \(String(cString: strerror(errno)))")
            break probeC0
        }
        var garbage = [UInt8](repeating: 0xFF, count: 32)
        if lseek(fd, off_t(corruptOffset), SEEK_SET) < 0 {
            close(fd)
            probeError("Probe C0: lseek failed: \(String(cString: strerror(errno)))")
            break probeC0
        }
        let written = write(fd, &garbage, 32)
        fsync(fd)
        close(fd)
        if written != 32 {
            probeError("Probe C0: short write: \(written) bytes")
            break probeC0
        }
        note("Probe C0: wrote 32 bytes of 0xFF at file-offset \(corruptOffset) (inside piece \(cp))")

        do {
            try bridge.forceRecheck(torrentID)
            note("Probe C0: forceRecheck() called; polling for hash_failed_alert up to 60s...")
        } catch {
            probeError("Probe C0: forceRecheck failed: \(error)")
            break probeC0
        }

        let c0Deadline = Date().addingTimeInterval(60)
        var c0Got = false
        while Date() < c0Deadline {
            alertLock.lock()
            c0Got = hashFailedPieces.contains(cp)
            alertLock.unlock()
            if c0Got { break }
            Thread.sleep(forTimeInterval: 0.5)
        }

        if c0Got {
            note("Probe C0: RESULT: hash_failed_alert received for piece \(cp). Alert pipeline VERIFIED.")
            c0Succeeded = true
            c0CorruptedPiece = cp
        } else {
            alertLock.lock()
            let snapshot = hashFailedPieces
            alertLock.unlock()
            note("Probe C0: RESULT: NEGATIVE — no hash_failed_alert for piece \(cp) in 60s.")
            note("  Other hash_failed pieces seen in this window: \(snapshot.count == 0 ? "none" : String(describing: snapshot))")
            note("  If this is negative, something is wrong with the alert pipeline (mask, drain, or bridge).")
        }

        // Wait for checking state to clear so subsequent probes start clean.
        note("Probe C0: waiting for torrent to leave checking state (up to 30s)...")
        let c0CheckDeadline = Date().addingTimeInterval(30)
        while Date() < c0CheckDeadline {
            if let snap = try? bridge.statusSnapshot(torrentID) {
                let state = snap["state"] as? String ?? "unknown"
                if state != "checkingFiles" && state != "checkingResumeData" {
                    note("Probe C0: post-check state = \(state)")
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    // -------------------------------------------------------------------------
    // Probe A: file state and have-bitmap observation (post-C0 steady state)
    // -------------------------------------------------------------------------

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

    // -------------------------------------------------------------------------
    // Probe C1: addPiece(zeros, overwrite_existing) + F_PUNCHHOLE — runs with
    //           DEFAULT priority=1. If this produces hash_failed_alert, priority=0
    //           in Probe B is the blocker observed in run #2.
    // -------------------------------------------------------------------------

    note("")
    note("--- Probe C1: addPiece(zeros, overwrite_existing) + F_PUNCHHOLE (priority=1) ---")
    note("  Goal: confirm zeros trigger hash_failed_alert, piece leaves havePieces, punch reclaims blocks.")
    note("  Runs BEFORE Probe B so target file is at default priority=1 — isolates add_piece from priority interaction.")

    var c1ClearedPiece: Int? = nil

    // All C1 logic in a labeled do-block so we can break out early on skip conditions.
    probeC1: do {
        var fileStart: Int64 = 0
        var fileEnd: Int64 = 0
        do {
            try bridge.fileByteRange(torrentID, fileIndex: Int32(targetFileIndex),
                                     start: &fileStart, end: &fileEnd)
        } catch {
            probeError("Probe C1: fileByteRange failed: \(error)")
            break probeC1
        }

        let havePiecesBefore: [NSNumber]
        do {
            havePiecesBefore = try bridge.havePieces(torrentID)
        } catch {
            probeError("Probe C1: havePieces failed: \(error)")
            break probeC1
        }
        let haveSet = Set(havePiecesBefore.map { $0.intValue })

        // firstFullPiece = ceil(fileStart / pieceLen), lastFullPieceExcl = floor(fileEnd / pieceLen)
        let firstFull = Int((fileStart + pieceLen - 1) / pieceLen)
        let lastFull  = Int(fileEnd / pieceLen)   // exclusive upper bound

        note("Probe C1: file byte range [\(fileStart), \(fileEnd)), pieceLen=\(pieceLen)")
        note("Probe C1: full-piece range within file: [\(firstFull), \(lastFull))")

        // Pick first downloaded piece in the full-piece range. Skip the piece
        // that Probe C0 corrupted (if any) so the two probes don't interfere.
        var targetPiece: Int? = nil
        for p in firstFull..<lastFull {
            if haveSet.contains(p) && p != c0CorruptedPiece {
                targetPiece = p
                break
            }
        }

        guard let tp = targetPiece else {
            note("Probe C1: SKIPPED — no suitable downloaded piece fully inside target file (firstFull=\(firstFull), lastFull=\(lastFull), haveSet size=\(haveSet.count), C0-corrupted=\(String(describing: c0CorruptedPiece)))")
            note("Probe C1: RESULT: SKIPPED")
            break probeC1
        }

        note("Probe C1: target piece = \(tp)")
        note("Probe C1: pre-check havePieces includes piece \(tp): \(haveSet.contains(tp))")

        // Clear alert sets so we observe only this probe's events.
        alertLock.lock()
        hashFailedPieces.removeAll()
        pieceFinishedPieces.removeAll()
        alertLock.unlock()

        // Pre-stat the file.
        var preOnDisk: Int64 = 0
        if let fp = downloadedFilePath, let s = statFile(fp) {
            preOnDisk = s.onDiskBytes
            note("Probe C1: file on-disk bytes before = \(s.onDiskBytes)")
        }

        // Build zeros buffer sized to the actual piece length (last piece may differ,
        // but we only pick full pieces so pieceLen is correct here).
        let zeros = Data(count: Int(pieceLen))

        // Call addPiece with overwrite_existing.
        do {
            try bridge.addPiece(torrentID, piece: Int32(tp), data: zeros, overwriteExisting: true)
            note("Probe C1: addPiece(piece:\(tp), zeros, overwrite_existing) sent (priority=1)")
        } catch {
            probeError("Probe C1: addPiece failed: \(error)")
            // Continue — we still want to punch and observe.
        }

        // Poll for hash_failed_alert for up to 30s (extended from 15s to tolerate
        // disk-flush lag on APFS per alert_types.hpp:929-931).
        note("Probe C1: polling for hash_failed_alert (pieceIndex=\(tp)) for up to 30s...")
        let c1Deadline = Date().addingTimeInterval(30)
        var lastC1Log = Date()
        var gotHashFailed = false
        var gotPieceFinished = false
        while Date() < c1Deadline {
            alertLock.lock()
            gotHashFailed    = hashFailedPieces.contains(tp)
            gotPieceFinished = pieceFinishedPieces.contains(tp)
            alertLock.unlock()

            if gotHashFailed || gotPieceFinished { break }

            if Date().timeIntervalSince(lastC1Log) >= 3 {
                alertLock.lock()
                let hfCount = hashFailedPieces.count
                let pfCount = pieceFinishedPieces.count
                alertLock.unlock()
                note("  Probe C1: still waiting... hashFailed.count=\(hfCount) pieceDone.count=\(pfCount)")
                lastC1Log = Date()
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        if gotHashFailed {
            note("Probe C1: hash_failed_alert received for piece \(tp) — as expected.")
        } else if gotPieceFinished {
            note("Probe C1: UNEXPECTED — piece_finished_alert received (zeros matched hash!). Piece NOT evicted.")
        } else {
            note("Probe C1: NEGATIVE RESULT — neither hash_failed_alert nor piece_finished_alert arrived within 15s.")
            note("  Possible causes: alert mask, libtorrent version behaviour, or torrent not in downloading/finished state.")
        }

        // Check havePieces after hash failure.
        let havePiecesAfterAdd = (try? bridge.havePieces(torrentID)) ?? []
        let haveSetAfter = Set(havePiecesAfterAdd.map { $0.intValue })
        let pieceCleared = !haveSetAfter.contains(tp)
        note("Probe C1: after addPiece — havePieces contains piece \(tp): \(!pieceCleared)")

        if gotHashFailed && pieceCleared {
            note("Probe C1: piece \(tp) confirmed removed from have-bitmap after hash failure.")
            c1ClearedPiece = tp
        } else if gotHashFailed && !pieceCleared {
            note("Probe C1: WARNING — hash_failed_alert arrived but piece \(tp) still in have-bitmap. libtorrent may not have updated yet.")
            // Give it another 2s.
            Thread.sleep(forTimeInterval: 2)
            let havePiecesRetry = (try? bridge.havePieces(torrentID)) ?? []
            if !Set(havePiecesRetry.map { $0.intValue }).contains(tp) {
                note("Probe C1: piece \(tp) confirmed cleared after additional 2s wait.")
                c1ClearedPiece = tp
            } else {
                note("Probe C1: piece \(tp) still in have-bitmap after extra wait.")
            }
        }

        // Punch a BLOCK-ALIGNED sub-range of the piece. For multi-file torrents where
        // the file does not start on a piece boundary (e.g. a 140-byte sidecar precedes
        // the MP4), piece-aligned in torrent space is NOT 4 KiB-aligned in file space
        // — F_PUNCHHOLE rejects unaligned offsets with EINVAL. Compute an aligned
        // sub-range: skip up to (blockSize-1) leading bytes, trim up to (blockSize-1)
        // trailing bytes. We forfeit up to ~8 KiB of reclaim per piece for correctness.
        if let fp = downloadedFilePath {
            let pieceOffsetInFile = Int64(tp) * pieceLen - fileStart
            let pieceEndInFile = pieceOffsetInFile + pieceLen
            let blockSize: Int64 = 4096
            let alignedStart = ((pieceOffsetInFile + blockSize - 1) / blockSize) * blockSize
            let alignedEnd = (pieceEndInFile / blockSize) * blockSize
            let alignedLen = alignedEnd - alignedStart

            if alignedLen <= 0 {
                note("Probe C1: SKIPPING punch — aligned sub-range is empty (piece geometry pathological)")
            } else {
                let leadingSkip = alignedStart - pieceOffsetInFile
                let trailingSkip = pieceEndInFile - alignedEnd
                note("Probe C1: punching block-aligned sub-range [\(alignedStart), \(alignedEnd)) len=\(alignedLen) " +
                     "(piece file-range [\(pieceOffsetInFile), \(pieceEndInFile)); leading skip=\(leadingSkip), trailing skip=\(trailingSkip))")
                let fd = open(fp, O_RDWR)
                if fd < 0 {
                    let errStr = String(cString: strerror(errno))
                    probeError("Probe C1: open for punch failed: \(errStr) (errno=\(errno))")
                } else {
                    let punchOK = punchHole(fd: fd, offset: alignedStart, length: alignedLen)
                    if punchOK {
                        note("Probe C1: F_PUNCHHOLE succeeded.")
                    } else {
                        let errStr = String(cString: strerror(errno))
                        note("Probe C1: F_PUNCHHOLE failed: \(errStr) (errno=\(errno))")
                        note("  On HFS+: ENOTSUP is expected. On APFS with block-aligned args: success expected.")
                    }
                    close(fd)

                    if let s = statFile(fp) {
                        let delta = preOnDisk - s.onDiskBytes
                        note("Probe C1: after punch — on-disk bytes = \(s.onDiskBytes) (delta = \(delta))")
                        let slack: Int64 = 65536  // APFS block-rounding allowance
                        if delta >= alignedLen - slack {
                            note("Probe C1: RESULT: on-disk bytes decreased by ~alignedLen — APFS sparse region created.")
                        } else if delta > 0 {
                            note("Probe C1: RESULT: on-disk bytes decreased by \(delta), less than alignedLen (\(alignedLen)). Partial effect.")
                        } else {
                            note("Probe C1: RESULT: on-disk bytes unchanged — punch had no effect (HFS+ or already sparse).")
                        }
                    }
                }
            }
        }
    } // end probeC1

    // -------------------------------------------------------------------------
    // Probe B: set file priority to 0, observe file state
    //   Runs AFTER Probe C1 now, so we can confirm the "priority=0 blocks addPiece"
    //   hypothesis by contrast with C1's result.
    // -------------------------------------------------------------------------

    note("")
    note("--- Probe B: set file priority to 0 (ignore), observe file state ---")
    note("  Note: TorrentBridge exposes setFilePriority (file granularity) only.")
    note("  Per-piece priority (lt::torrent_handle::piece_priority) is NOT bridged.")
    do {
        try bridge.setFilePriority(torrentID, fileIndex: Int32(targetFileIndex), priority: 0)
        note("Probe B: setFilePriority(\(torrentID), fileIndex:\(targetFileIndex), priority:0) succeeded")
    } catch {
        probeError("Probe B: setFilePriority failed: \(error)")
    }

    if let fp = downloadedFilePath, let s = statFile(fp) {
        note("Probe B (immediate): file size=\(s.apparentSize), on-disk=\(s.onDiskBytes)")
    } else {
        note("Probe B (immediate): SKIPPED — no file path")
    }

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

    // -------------------------------------------------------------------------
    // Probe C2: force_recheck
    // -------------------------------------------------------------------------

    note("")
    note("--- Probe C2: force_recheck() — validate fallback re-verification mechanism ---")
    note("  Goal: confirm force_recheck completes and produces a coherent havePieces bitmap.")

    let havePiecesBeforeRecheck = (try? bridge.havePieces(torrentID))?.count ?? 0
    note("Probe C2: havePieces count before force_recheck = \(havePiecesBeforeRecheck)")

    do {
        try bridge.forceRecheck(torrentID)
        note("Probe C2: forceRecheck() called — libtorrent will disconnect peers and re-hash all pieces.")
    } catch {
        probeError("Probe C2: forceRecheck failed: \(error)")
    }

    // Poll for state to transition through checkingFiles/checkingResumeData, up to 90s.
    note("Probe C2: polling for checking state to clear (up to 90s)...")
    let c2Deadline = Date().addingTimeInterval(90)
    var lastC2Log = Date()
    var lastState = ""
    var checkingStarted = false
    var checkingCleared = false

    while Date() < c2Deadline {
        if let snap = try? bridge.statusSnapshot(torrentID) {
            let state = snap["state"] as? String ?? "unknown"
            if state != lastState {
                note("  Probe C2: state transition → \(state)")
                lastState = state
            }
            if state == "checkingFiles" || state == "checkingResumeData" {
                checkingStarted = true
            }
            if checkingStarted && state != "checkingFiles" && state != "checkingResumeData" {
                checkingCleared = true
                break
            }
        }
        if Date().timeIntervalSince(lastC2Log) >= 5 {
            note("  Probe C2: still checking... state=\(lastState)")
            lastC2Log = Date()
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    if checkingCleared {
        note("Probe C2: checking completed. Final state = \(lastState)")
    } else if checkingStarted {
        note("Probe C2: checking started but did NOT clear within 90s.")
    } else {
        note("Probe C2: checking state was never observed — force_recheck may have completed too quickly or state polling missed it.")
    }

    let havePiecesAfterRecheck = (try? bridge.havePieces(torrentID))?.count ?? 0
    let recheckDelta = havePiecesAfterRecheck - havePiecesBeforeRecheck
    note("Probe C2: havePieces count after recheck = \(havePiecesAfterRecheck) (delta = \(recheckDelta >= 0 ? "+\(recheckDelta)" : "\(recheckDelta)"))")
    if let cp = c1ClearedPiece {
        let stillMissing = !((try? bridge.havePieces(torrentID))?.map({ $0.intValue }).contains(cp) ?? false)
        note("Probe C2: piece \(cp) cleared in C1 — still missing after recheck: \(stillMissing)")
        note("  Expected: true (punched zeros won't match the piece hash).")
    }
    note("Probe C2: RESULT: recheck completed=\(checkingCleared), bitmap delta=\(recheckDelta)")

    // -------------------------------------------------------------------------
    // Probe C3: priority restore → re-fetch of cleared piece
    // -------------------------------------------------------------------------

    note("")
    note("--- Probe C3: priority restore → re-fetch of C1-cleared piece ---")
    note("  Goal: confirm libtorrent re-downloads the piece cleared in C1 after priority=1 is restored.")

    if let c3TargetPiece = c1ClearedPiece {
        do {
            try bridge.setFilePriority(torrentID, fileIndex: Int32(targetFileIndex), priority: 1)
            note("Probe C3: setFilePriority(\(targetFileIndex), priority:1) called.")
        } catch {
            probeError("Probe C3: setFilePriority failed: \(error)")
        }

        note("Probe C3: polling for piece \(c3TargetPiece) to reappear in havePieces (up to 30s)...")
        let c3Deadline = Date().addingTimeInterval(30)
        var lastC3Log = Date()
        var c3Refetched = false

        while Date() < c3Deadline {
            if let pieces = try? bridge.havePieces(torrentID) {
                if pieces.map({ $0.intValue }).contains(c3TargetPiece) {
                    c3Refetched = true
                    break
                }
            }
            if Date().timeIntervalSince(lastC3Log) >= 2 {
                let count = (try? bridge.havePieces(torrentID))?.count ?? 0
                note("  Probe C3: still waiting... havePieces count=\(count)")
                lastC3Log = Date()
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        if c3Refetched {
            note("Probe C3: RESULT: cleared piece \(c3TargetPiece) re-fetched successfully after priority restore.")
        } else {
            note("Probe C3: RESULT: cleared piece \(c3TargetPiece) NOT re-fetched within 30s.")
            note("  Possible causes: no peers, file priority 0 still set, or libtorrent de-prioritised the piece.")
        }
    } else {
        note("Probe C3: SKIPPED — C1 did not clear any pieces.")
    }

    // MARK: - Probe D: file-level priority restore, re-fetch of entire file

    note("")
    note("--- Probe D: file-level priority restore, wait for full re-fetch ---")
    note("  Tests the whole-file priority-restore pathway (distinct from C3's single-piece test).")
    note("  If C2 (force_recheck) significantly changed havePieces, Probe D behaviour may differ.")
    // Priority may already be 1 from C3; set it again to be explicit.

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
    note("  1. Did disk-corrupt + force_recheck produce hash_failed_alert? (Probe C0 — confirms alert pipeline works)")
    note("  2. With DEFAULT priority=1, did addPiece(zeros, overwrite_existing) produce a hash_failed_alert? (Probe C1)")
    note("  3. After C1's hash failure, did the targeted piece leave havePieces()? (Probe C1)")
    note("  4. Did the BLOCK-ALIGNED F_PUNCHHOLE reduce on-disk bytes by ~alignedLen? (Probe C1)")
    note("  5. Did setFilePriority(0) alone change on-disk bytes? (Probe A vs B — expected no.)")
    note("  6. Did force_recheck() complete and produce a coherent havePieces() bitmap? (Probe C2)")
    note("  7. After C1 + priority restore, did libtorrent re-download the cleared piece? (Probe C3)")
    note("  8. Does file-level setFilePriority(1) trigger full re-fetch of the file? (Probe D)")
    note("  9. What is the piece length for this torrent? (Setup output)")

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
