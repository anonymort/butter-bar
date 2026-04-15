import Foundation

/// Reads bytes from a libtorrent-managed sparse file, enforcing piece availability.
///
/// Maps byte ranges to torrent pieces and only reads bytes from contiguous fully-downloaded
/// pieces. If a requested range spans unavailable pieces, a partial read is returned up to
/// the first unavailable piece boundary. This prevents APFS from silently returning zeros
/// for holes in the sparse file (issue #91).
final class ByteReader {

    enum ReadError: Error {
        /// The torrent ID is not known to the bridge.
        case torrentNotFound
        /// Torrent metadata (piece length, file map) is not yet available.
        case metadataNotReady
        /// No piece covering the start of the requested range is downloaded.
        case bytesNotAvailable
        /// The bridge returned an I/O error.
        case readFailed(underlying: Error)
    }

    struct ReadResult {
        let data: Data
        /// Actual byte count returned (may be less than `requestedLength`).
        let bytesRead: Int64
        /// What the caller asked for.
        let requestedLength: Int64

        var isPartial: Bool { bytesRead < requestedLength }
    }

    private let bridge: TorrentBridge
    private let torrentID: String
    private let fileIndex: Int32
    private let pieceLength: Int64
    /// Byte offset of this file's first byte in the torrent's global piece address space.
    private let fileStart: Int64
    /// Exclusive end byte offset (one past the last byte of the file).
    private let fileEnd: Int64

    /// - Throws: `ReadError.metadataNotReady` if pieceLength is zero or fileByteRange fails.
    init(bridge: TorrentBridge, torrentID: String, fileIndex: Int) throws {
        self.bridge = bridge
        self.torrentID = torrentID
        self.fileIndex = Int32(fileIndex)

        let pl = bridge.pieceLength(torrentID)
        guard pl > 0 else { throw ReadError.metadataNotReady }
        self.pieceLength = pl

        var start: Int64 = 0
        var end: Int64 = 0
        do {
            try bridge.fileByteRange(torrentID, fileIndex: Int32(fileIndex), start: &start, end: &end)
        } catch {
            throw ReadError.metadataNotReady
        }
        self.fileStart = start
        self.fileEnd = end
    }

    /// Read bytes at `[offset, offset+length)` within the file (file-relative offsets).
    ///
    /// Returns up to `length` bytes. If pieces at the tail of the range aren't downloaded
    /// the result will be partial (`isPartial == true`). If even the first byte isn't in a
    /// downloaded piece, throws `bytesNotAvailable`.
    func read(offset: Int64, length: Int64) throws -> ReadResult {
        guard length > 0 else {
            return ReadResult(data: Data(), bytesRead: 0, requestedLength: length)
        }

        // Convert file-relative offset to torrent-absolute address space.
        let absStart = fileStart + offset
        let absEnd = min(fileStart + offset + length, fileEnd)
        let clampedLength = absEnd - absStart
        guard clampedLength > 0 else {
            return ReadResult(data: Data(), bytesRead: 0, requestedLength: length)
        }

        let firstPiece = Int(absStart / pieceLength)
        let lastPiece = Int((absEnd - 1) / pieceLength)

        // Fetch the availability bitmap.
        let havePiecesArray: [NSNumber]
        do {
            havePiecesArray = try bridge.havePieces(torrentID)
        } catch let e as ReadError {
            throw e
        } catch {
            throw ReadError.torrentNotFound
        }

        let haveSet = Set(havePiecesArray.map { $0.intValue })

        // Walk forward from firstPiece, finding how far the contiguous run of
        // downloaded pieces extends. Stop at the first gap.
        var availableAbsEnd = absStart
        for piece in firstPiece...lastPiece {
            guard haveSet.contains(piece) else { break }
            // This piece is fully downloaded — advance the readable boundary to
            // the end of this piece (clamped to the file/request boundary).
            let pieceAbsEnd = Int64(piece + 1) * pieceLength
            availableAbsEnd = min(pieceAbsEnd, absEnd)
        }

        guard availableAbsEnd > absStart else {
            throw ReadError.bytesNotAvailable
        }

        let readLength = availableAbsEnd - absStart

        // Issue the read via the bridge (file-relative offset, not torrent-absolute).
        let data: Data
        do {
            data = try bridge.readBytes(
                torrentID,
                fileIndex: fileIndex,
                offset: offset,
                length: readLength
            )
        } catch {
            throw ReadError.readFailed(underlying: error)
        }

        // The bridge may return fewer bytes than requested (e.g. short read near EOF).
        return ReadResult(
            data: data,
            bytesRead: Int64(data.count),
            requestedLength: length
        )
    }
}
