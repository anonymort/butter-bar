import Foundation
import EngineInterface

/// Pure functions for mapping torrent piece indices to file-relative byte ranges.
///
/// All inputs are value types or primitives — no bridge calls, no I/O, no clocks.
/// This makes the logic trivially testable with synthetic bitmaps.
enum PieceByteMapping {

    /// Maps a set of downloaded piece indices to coalesced file-relative byte ranges.
    ///
    /// - Parameters:
    ///   - havePieces: Piece indices that are fully downloaded (any order, may contain duplicates).
    ///   - pieceLength: Uniform piece size in bytes (from `TorrentBridge.pieceLength`).
    ///   - fileStart: Torrent-absolute byte offset of the first byte of the file.
    ///   - fileEnd: Torrent-absolute exclusive end offset (one past the last byte of the file).
    /// - Returns: Sorted, coalesced `ByteRangeDTO` entries in file-relative coordinates,
    ///   with both `startByte` and `endByte` inclusive.
    ///   Returns an empty array when `havePieces` is empty, `pieceLength` is zero,
    ///   or no downloaded piece intersects the file.
    static func availableRanges(
        havePieces: [Int],
        pieceLength: Int64,
        fileStart: Int64,
        fileEnd: Int64
    ) -> [ByteRangeDTO] {
        guard pieceLength > 0, fileEnd > fileStart, !havePieces.isEmpty else { return [] }

        let firstFilePiece = Int(fileStart / pieceLength)
        let lastFilePiece  = Int((fileEnd - 1) / pieceLength)

        // Filter to pieces that overlap this file and sort.
        let relevant = havePieces
            .filter { $0 >= firstFilePiece && $0 <= lastFilePiece }
            .sorted()

        guard !relevant.isEmpty else { return [] }

        // Convert each piece to its torrent-absolute byte interval, then clamp to
        // the file's byte range, then convert to file-relative coordinates.
        var ranges: [ByteRangeDTO] = []
        var runStart: Int64? = nil
        var runEnd:   Int64? = nil

        for piece in relevant {
            let pieceAbsStart = Int64(piece) * pieceLength
            let pieceAbsEnd   = pieceAbsStart + pieceLength  // exclusive

            // Clamp to file boundaries (torrent-absolute).
            let clampedAbsStart = max(pieceAbsStart, fileStart)
            let clampedAbsEnd   = min(pieceAbsEnd,   fileEnd)   // exclusive

            guard clampedAbsEnd > clampedAbsStart else { continue }

            // File-relative, inclusive on both ends.
            let relStart = clampedAbsStart - fileStart
            let relEnd   = clampedAbsEnd   - fileStart - 1

            if let rs = runStart, let re = runEnd {
                // Coalesce: adjacent means relStart == re + 1.
                if relStart <= re + 1 {
                    runEnd = max(re, relEnd)
                } else {
                    ranges.append(ByteRangeDTO(startByte: rs, endByte: re))
                    runStart = relStart
                    runEnd   = relEnd
                }
            } else {
                runStart = relStart
                runEnd   = relEnd
            }
        }

        if let rs = runStart, let re = runEnd {
            ranges.append(ByteRangeDTO(startByte: rs, endByte: re))
        }

        return ranges
    }
}
