// CacheManagerEviction.swift — eviction logic extension for CacheManager.
//
// Threading contract: same as CacheManager — synchronous, single queue, not
// thread-safe internally. Callers must serialise.
//
// Mechanism per spec 05 rev 4 + addendum A24:
//   1. setFilePriority(0) — stop peers requesting evicted pieces.
//   2. F_PUNCHHOLE over block-aligned sub-ranges of each piece within the file.
//   3. forceRecheck on the torrent — libtorrent re-hashes, removes punched pieces
//      from the have-bitmap.
//   4. Poll statusState until checking clears.

import Foundation

// MARK: - Eviction error

private enum EvictionError: Error {
    case forceRecheckFailed(String, underlying: Error)
    case recheckTimeout(String)
}

// MARK: - F_PUNCHHOLE helper

/// Punches a sparse hole in the file descriptor over [offset, offset+length).
/// Uses fcntl(F_PUNCHHOLE) on Apple platforms; APFS supports it, HFS+ does not.
/// Returns true if the syscall succeeded.
private func punchHoleRange(fd: Int32, offset: Int64, length: Int64) -> Bool {
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

// MARK: - CacheManager eviction extension

extension CacheManager {

    // MARK: - Budget constants

    /// Default high-water mark: 50 GB. Eviction starts when usedBytes >= this.
    public static let defaultHighWaterBytes: Int64 = 50 * 1024 * 1024 * 1024

    /// Default low-water mark: 40 GB. Eviction runs until usedBytes <= this.
    public static let defaultLowWaterBytes: Int64 = 40 * 1024 * 1024 * 1024

    // MARK: - Budget accounting

    /// Returns the sum of on-disk allocated bytes for the given file paths using
    /// stat(2).st_blocks * 512. Missing files contribute 0.
    /// Directories are not recursed — pass file paths directly.
    public func usedBytes(paths: [String]) -> Int64 {
        var total: Int64 = 0
        for path in paths {
            var st = stat()
            if stat(path, &st) == 0 {
                // st_blocks is in 512-byte units on all Darwin filesystems.
                total += Int64(st.st_blocks) * 512
            } else {
                NSLog("[CacheManager] usedBytes: stat failed for path %@ (errno=%d)", path, errno)
            }
        }
        return total
    }

    /// Classifies disk pressure per spec 05:
    /// - ok:       usedBytes < 0.80 * highWater
    /// - warn:     0.80 * highWater <= usedBytes < highWater
    /// - critical: usedBytes >= highWater
    public func pressure(usedBytes: Int64, highWater: Int64) -> DiskPressure {
        let warnThreshold = Int64(Double(highWater) * 0.80)
        if usedBytes >= highWater {
            return .critical
        } else if usedBytes >= warnThreshold {
            return .warn
        } else {
            return .ok
        }
    }

    // MARK: - Single-file eviction

    /// Evicts a single file by punching the block-aligned sub-range of each
    /// fully-interior piece, then force-rechecking the torrent and waiting
    /// for the checking state to clear.
    ///
    /// Step 1: setFilePriority(0) so peers don't re-request the evicted pieces.
    ///   Errors here are logged but do not throw — priority is best-effort.
    /// Step 2: Open the file and F_PUNCHHOLE each qualifying piece.
    ///   Per-piece punch failures are logged but do not throw.
    /// Step 3: forceRecheck(torrentID). Throws on failure.
    /// Step 4: Poll statusState every 500 ms until checking clears. Throws on timeout.
    ///
    /// Returns the number of bytes reclaimed (on-disk bytes before minus after).
    public func evictFile(
        candidate: EvictionCandidate,
        bridge: CacheManagerBridge,
        rechecktimeoutSeconds: Double = 120
    ) throws -> Int64 {
        let torrentId = candidate.torrentId
        let fileIndex = candidate.fileIndex
        let path = candidate.onDiskPath
        let pieceLength = candidate.pieceLength
        let fileStart = candidate.fileStartInTorrent
        let fileEnd = candidate.fileEndInTorrent

        // Step 1: disable peer requests for this file.
        do {
            try bridge.setFilePriority(torrentID: torrentId, fileIndex: fileIndex, priority: 0)
        } catch {
            NSLog("[CacheManager] evictFile: setFilePriority failed for %@/%d (ignored): %@",
                  torrentId, fileIndex, String(describing: error))
        }

        // Measure bytes before punching.
        let bytesBefore: Int64 = {
            var st = stat()
            guard stat(path, &st) == 0 else { return 0 }
            return Int64(st.st_blocks) * 512
        }()

        // Step 2: punch each fully-interior piece.
        //
        // "Full-inside" piece range per spec 05 and the probe's firstFull convention:
        //   firstFullPiece = ceil(fileStart / pieceLength)
        //   lastFullPieceExcl = floor(fileEnd / pieceLength)
        //
        // Piece p overlaps the file if p*L < fileEnd && (p+1)*L > fileStart.
        // "Fully inside" means the piece's entire byte range is within the file.
        // Using full-inside pieces avoids punching bytes belonging to neighbouring
        // files in multi-file torrents.
        let firstFull = Int((fileStart + pieceLength - 1) / pieceLength)
        let lastFullExcl = Int(fileEnd / pieceLength)

        guard firstFull < lastFullExcl else {
            // File is smaller than one piece — nothing to punch.
            NSLog("[CacheManager] evictFile: file %@ has no full interior pieces (firstFull=%d lastFullExcl=%d), skipping punch",
                  path, firstFull, lastFullExcl)
            // Still recheck so the bitmap reflects reality.
            return try recheckAndWait(torrentId: torrentId, bridge: bridge,
                                      bytesBefore: bytesBefore, path: path,
                                      timeoutSeconds: rechecktimeoutSeconds)
        }

        let fd = open(path, O_RDWR)
        if fd < 0 {
            let errStr = String(cString: strerror(errno))
            NSLog("[CacheManager] evictFile: open('%@') failed: %@ (errno=%d) — skipping punch",
                  path, errStr, errno)
        } else {
            defer { close(fd) }
            let blockSize: Int64 = 4096

            for p in firstFull..<lastFullExcl {
                // Piece p's byte range relative to the file.
                let pieceOffsetInFile = Int64(p) * pieceLength - fileStart
                let pieceEndInFile = pieceOffsetInFile + pieceLength

                // Block-align: skip leading partial block, trim trailing partial block.
                let alignedStart = ((pieceOffsetInFile + blockSize - 1) / blockSize) * blockSize
                let alignedEnd   = (pieceEndInFile / blockSize) * blockSize
                let alignedLen   = alignedEnd - alignedStart

                guard alignedLen > 0 else {
                    // Extremely short piece — can't punch a block-aligned range.
                    continue
                }

                let ok = punchHoleRange(fd: fd, offset: alignedStart, length: alignedLen)
                if !ok {
                    let errStr = String(cString: strerror(errno))
                    NSLog("[CacheManager] evictFile: F_PUNCHHOLE failed for piece %d " +
                          "offset=%lld length=%lld: %@ (errno=%d)",
                          p, alignedStart, alignedLen, errStr, errno)
                    // Non-fatal — partial reclamation is still useful.
                }
            }
        }

        // Steps 3 + 4: forceRecheck and wait.
        return try recheckAndWait(torrentId: torrentId, bridge: bridge,
                                  bytesBefore: bytesBefore, path: path,
                                  timeoutSeconds: rechecktimeoutSeconds)
    }

    // MARK: - Top-level eviction pass

    /// Evicts files from `candidates` until usedBytes drops to or below
    /// `lowWaterBytes`, or all candidates are exhausted.
    ///
    /// If usedBytes < highWaterBytes at call time, returns immediately with no
    /// candidates evicted (pressure is ok or warn, not critical).
    ///
    /// Caller responsibilities (this method does NOT re-check):
    ///   - Filter out pinned files before passing candidates.
    ///   - Filter out files with active streams.
    ///   - Sort by tierRank ascending, then by appropriate secondary key.
    ///
    /// forceRecheck is issued once per distinct torrentId after all its files
    /// have been punched in the pass (batched per spec 05 § Cost and batching).
    public func runEvictionPass(
        candidates: [EvictionCandidate],
        bridge: CacheManagerBridge,
        highWaterBytes: Int64 = CacheManager.defaultHighWaterBytes,
        lowWaterBytes: Int64 = CacheManager.defaultLowWaterBytes
    ) throws -> EvictionPassResult {
        let startTime = Date()

        let allPaths = candidates.map(\.onDiskPath)
        let initialUsed = usedBytes(paths: allPaths)
        let pressureBefore = pressure(usedBytes: initialUsed, highWater: highWaterBytes)

        guard initialUsed >= highWaterBytes else {
            // Not at high-water; nothing to do.
            return EvictionPassResult(
                candidatesEvicted: 0,
                torrentsRechecked: 0,
                bytesReclaimed: 0,
                usedBytesAfter: initialUsed,
                pressureBefore: pressureBefore,
                pressureAfter: pressureBefore,
                durationSeconds: -startTime.timeIntervalSinceNow,
                errors: []
            )
        }

        var evictedCandidates: [EvictionCandidate] = []
        var evictionErrors: [String] = []
        var currentUsed = initialUsed

        // Select candidates to evict until we expect to reach lowWater.
        // We punch first, then batch-recheck per torrent.
        for candidate in candidates {
            guard currentUsed > lowWaterBytes else { break }
            evictedCandidates.append(candidate)

            // Step 1: set priority to 0.
            do {
                try bridge.setFilePriority(
                    torrentID: candidate.torrentId,
                    fileIndex: candidate.fileIndex,
                    priority: 0
                )
            } catch {
                let msg = "setFilePriority failed for \(candidate.torrentId)/\(candidate.fileIndex): \(error)"
                NSLog("[CacheManager] runEvictionPass: %@", msg)
                // Non-fatal — continue to punch.
            }

            // Step 2: punch each fully-interior piece.
            let path = candidate.onDiskPath
            let pieceLength = candidate.pieceLength
            let fileStart = candidate.fileStartInTorrent
            let fileEnd = candidate.fileEndInTorrent

            let firstFull = Int((fileStart + pieceLength - 1) / pieceLength)
            let lastFullExcl = Int(fileEnd / pieceLength)

            if firstFull >= lastFullExcl {
                NSLog("[CacheManager] runEvictionPass: no full interior pieces for %@, skipping punch", path)
            } else {
                let fd = open(path, O_RDWR)
                if fd < 0 {
                    let errStr = String(cString: strerror(errno))
                    let msg = "open('\(path)') failed: \(errStr) (errno=\(errno))"
                    NSLog("[CacheManager] runEvictionPass: %@", msg)
                    evictionErrors.append(msg)
                } else {
                    let blockSize: Int64 = 4096
                    for p in firstFull..<lastFullExcl {
                        let pieceOffsetInFile = Int64(p) * pieceLength - fileStart
                        let pieceEndInFile = pieceOffsetInFile + pieceLength
                        let alignedStart = ((pieceOffsetInFile + blockSize - 1) / blockSize) * blockSize
                        let alignedEnd   = (pieceEndInFile / blockSize) * blockSize
                        let alignedLen   = alignedEnd - alignedStart

                        guard alignedLen > 0 else { continue }

                        if !punchHoleRange(fd: fd, offset: alignedStart, length: alignedLen) {
                            let errStr = String(cString: strerror(errno))
                            let msg = "F_PUNCHHOLE piece \(p) in '\(path)': \(errStr) (errno=\(errno))"
                            NSLog("[CacheManager] runEvictionPass: %@", msg)
                            evictionErrors.append(msg)
                        }
                    }
                    close(fd)
                }
            }

            // Optimistically subtract this file's current on-disk allocation from
            // the running total so we stop selecting candidates as soon as we
            // expect to reach lowWater. The true reclaimed bytes are measured
            // after all rechecks complete. Using st_blocks * 512 is consistent
            // with usedBytes(paths:).
            var st = stat()
            if stat(path, &st) == 0 {
                let onDisk = Int64(st.st_blocks) * 512
                currentUsed = max(0, currentUsed - onDisk)
            }
        }

        // Step 3: forceRecheck once per distinct torrentId.
        let torrentIds = Set(evictedCandidates.map(\.torrentId))
        var recheckErrors: [String] = []

        for torrentId in torrentIds {
            do {
                try bridge.forceRecheck(torrentID: torrentId)
            } catch {
                let msg = "forceRecheck failed for torrent \(torrentId): \(error)"
                NSLog("[CacheManager] runEvictionPass: %@", msg)
                recheckErrors.append(msg)
                // Fatal per spec — propagate after we've attempted all torrents.
                // Collect first, throw below.
                continue
            }

            // Step 4: wait for checking state to clear (120 s timeout).
            do {
                try waitForRecheckToComplete(torrentId: torrentId, bridge: bridge, timeoutSeconds: 120)
            } catch {
                let msg = "recheck wait failed for torrent \(torrentId): \(error)"
                NSLog("[CacheManager] runEvictionPass: %@", msg)
                recheckErrors.append(msg)
            }
        }

        // Throw if any recheck failed — these are fatal per spec.
        if !recheckErrors.isEmpty {
            throw NSError(
                domain: "com.butterbar.engine.cache",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: recheckErrors.joined(separator: "; ")]
            )
        }

        // Measure actual bytes after recheck across all candidate paths.
        let usedAfter = usedBytes(paths: allPaths)
        let bytesReclaimed = max(0, initialUsed - usedAfter)
        let pressureAfter = pressure(usedBytes: usedAfter, highWater: highWaterBytes)

        return EvictionPassResult(
            candidatesEvicted: evictedCandidates.count,
            torrentsRechecked: torrentIds.count,
            bytesReclaimed: bytesReclaimed,
            usedBytesAfter: usedAfter,
            pressureBefore: pressureBefore,
            pressureAfter: pressureAfter,
            durationSeconds: -startTime.timeIntervalSinceNow,
            errors: evictionErrors
        )
    }

    // MARK: - Private helpers

    /// Issues forceRecheck and waits for the torrent to leave checking states.
    /// Returns the bytes reclaimed (bytesBefore - bytesAfter).
    private func recheckAndWait(
        torrentId: String,
        bridge: CacheManagerBridge,
        bytesBefore: Int64,
        path: String,
        timeoutSeconds: Double
    ) throws -> Int64 {
        do {
            try bridge.forceRecheck(torrentID: torrentId)
        } catch {
            throw EvictionError.forceRecheckFailed(torrentId, underlying: error)
        }

        try waitForRecheckToComplete(torrentId: torrentId, bridge: bridge, timeoutSeconds: timeoutSeconds)

        let bytesAfter: Int64 = {
            var st = stat()
            guard stat(path, &st) == 0 else { return bytesBefore }
            return Int64(st.st_blocks) * 512
        }()

        return max(0, bytesBefore - bytesAfter)
    }

    /// Polls statusState every 500 ms until the torrent leaves checkingFiles /
    /// checkingResumeData states. Throws `EvictionError.recheckTimeout` if the
    /// timeout is exceeded.
    ///
    /// Per the probe: the recheck may complete in < 500 ms on small torrents, so
    /// we accept a non-checking state on the very first poll as valid.
    private func waitForRecheckToComplete(
        torrentId: String,
        bridge: CacheManagerBridge,
        timeoutSeconds: Double
    ) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            let state: String
            do {
                state = try bridge.statusState(torrentID: torrentId)
            } catch {
                NSLog("[CacheManager] waitForRecheckToComplete: statusState error for %@: %@",
                      torrentId, String(describing: error))
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }

            let isChecking = state == "checkingFiles" || state == "checkingResumeData"

            if !isChecking {
                // Not currently checking. Two valid exits:
                //   a) We saw checking and it cleared (normal path).
                //   b) We never saw checking — recheck completed in < 500 ms.
                // Both are acceptable per spec.
                return
            }

            Thread.sleep(forTimeInterval: 0.5)
        }

        throw EvictionError.recheckTimeout(torrentId)
    }
}
