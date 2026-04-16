// PieceByteMapping.swift is compiled directly into this test target.
// It lives at EngineService/Bridge/PieceByteMapping.swift and is referenced via
// the ButterBarTests Sources build phase in project.pbxproj.

import XCTest
import EngineInterface

// MARK: - Helpers

private func ranges(
    pieces: [Int],
    pieceLength: Int64,
    fileStart: Int64,
    fileEnd: Int64
) -> [(start: Int64, end: Int64)] {
    PieceByteMapping.availableRanges(
        havePieces: pieces,
        pieceLength: pieceLength,
        fileStart: fileStart,
        fileEnd: fileEnd
    ).map { ($0.startByte, $0.endByte) }
}

final class PieceByteMappingTests: XCTestCase {

    // MARK: - Empty bitmap

    func testEmpty_noPieces_returnsEmpty() {
        let result = ranges(pieces: [], pieceLength: 256_000, fileStart: 0, fileEnd: 1_000_000)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Single piece

    func testSinglePiece_firstPiece_fileStartsAtZero() {
        // File covers [0, 512000), piece length 256000.
        // Piece 0 → torrent abs [0, 256000), file-relative [0, 255999] inclusive.
        let result = ranges(pieces: [0], pieceLength: 256_000, fileStart: 0, fileEnd: 512_000)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, 0)
        XCTAssertEqual(result[0].end, 255_999)
    }

    func testSinglePiece_middleOfFile() {
        // File covers torrent abs [100_000, 900_000). Piece length 256_000.
        // File spans pieces 0..2 (piece 0: [0,256000), piece 1: [256000,512000), piece 2: [512000,768000)).
        // havePieces = [1] → intersect with file → clamp → file-relative.
        // piece 1 abs [256000, 512000), clamped to file [100000, 900000) → [256000, 512000).
        // file-relative: start = 256000-100000 = 156000, end = 512000-100000-1 = 411999.
        let result = ranges(pieces: [1], pieceLength: 256_000, fileStart: 100_000, fileEnd: 900_000)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, 156_000)
        XCTAssertEqual(result[0].end, 411_999)
    }

    // MARK: - Contiguous run

    func testContiguousRun_coalescesIntoSingleRange() {
        // File [0, 768000), piece length 256000. Pieces 0,1,2 all present.
        // Should coalesce to single range [0, 767999].
        let result = ranges(pieces: [0, 1, 2], pieceLength: 256_000, fileStart: 0, fileEnd: 768_000)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, 0)
        XCTAssertEqual(result[0].end, 767_999)
    }

    func testContiguousRun_unsortedInput_coalescesCorrectly() {
        let result = ranges(pieces: [2, 0, 1], pieceLength: 256_000, fileStart: 0, fileEnd: 768_000)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, 0)
        XCTAssertEqual(result[0].end, 767_999)
    }

    // MARK: - Scattered pieces (gap in middle)

    func testScatteredPieces_producesMultipleRanges() {
        // File [0, 1_024_000), piece length 256_000. Pieces 0 and 3 (gap at 1 and 2).
        // Piece 0 → [0, 255999], piece 3 → [768000, 1023999].
        let result = ranges(pieces: [0, 3], pieceLength: 256_000, fileStart: 0, fileEnd: 1_024_000)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].start, 0)
        XCTAssertEqual(result[0].end, 255_999)
        XCTAssertEqual(result[1].start, 768_000)
        XCTAssertEqual(result[1].end, 1_023_999)
    }

    func testScatteredPieces_firstAndLast_twoRanges() {
        // File [0, 768000), pieces 0 and 2, gap at 1.
        let result = ranges(pieces: [0, 2], pieceLength: 256_000, fileStart: 0, fileEnd: 768_000)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].start, 0)
        XCTAssertEqual(result[0].end, 255_999)
        XCTAssertEqual(result[1].start, 512_000)
        XCTAssertEqual(result[1].end, 767_999)
    }

    // MARK: - All pieces

    func testAllPieces_singleRange_coveringWholeFile() {
        let result = ranges(pieces: [0, 1, 2, 3], pieceLength: 256_000, fileStart: 0, fileEnd: 1_024_000)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, 0)
        XCTAssertEqual(result[0].end, 1_023_999)
    }

    // MARK: - Last piece file-end truncation

    func testLastPiece_truncatedToFileEnd() {
        // File [0, 300_000): doesn't end on a piece boundary (piece length 256_000).
        // Piece 0 covers [0, 256000), piece 1 covers [256000, 512000) but file only goes to 300000.
        // Last piece (1) should be clamped: file-relative [256000, 299999].
        let result = ranges(pieces: [0, 1], pieceLength: 256_000, fileStart: 0, fileEnd: 300_000)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, 0)
        XCTAssertEqual(result[0].end, 299_999)
    }

    func testLastPiece_onlyLastPiecePresent_truncated() {
        // File [0, 300_000), only piece 1 downloaded.
        // Piece 1 abs [256000, 512000) clamped to [256000, 300000), file-relative [256000, 299999].
        let result = ranges(pieces: [1], pieceLength: 256_000, fileStart: 0, fileEnd: 300_000)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, 256_000)
        XCTAssertEqual(result[0].end, 299_999)
    }

    // MARK: - File does not start at zero (multi-file torrent offset)

    func testFileNotAtTorrentStart_singlePiece() {
        // File starts at torrent offset 512_000, length 256_000 → fileEnd = 768_000.
        // Piece length 256_000. Piece 2 covers torrent abs [512000, 768000).
        // Clamped to file → same. File-relative: [0, 255999].
        let result = ranges(pieces: [2], pieceLength: 256_000, fileStart: 512_000, fileEnd: 768_000)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, 0)
        XCTAssertEqual(result[0].end, 255_999)
    }

    func testFileNotAtTorrentStart_pieceOutsideFile_excluded() {
        // Only piece 0 downloaded, but file starts at 512_000. Piece 0 doesn't overlap.
        let result = ranges(pieces: [0], pieceLength: 256_000, fileStart: 512_000, fileEnd: 768_000)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Edge: zero piece length guard

    func testZeroPieceLength_returnsEmpty() {
        let result = ranges(pieces: [0, 1, 2], pieceLength: 0, fileStart: 0, fileEnd: 1_000_000)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Edge: empty file range guard

    func testEmptyFileRange_returnsEmpty() {
        // fileStart == fileEnd → zero-length file.
        let result = ranges(pieces: [0], pieceLength: 256_000, fileStart: 100, fileEnd: 100)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Duplicate pieces in input

    func testDuplicatePieces_treatedCorrectly() {
        // Duplicates should not produce duplicate ranges after sort+coalesce.
        let result = ranges(pieces: [0, 0, 1, 1], pieceLength: 256_000, fileStart: 0, fileEnd: 512_000)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, 0)
        XCTAssertEqual(result[0].end, 511_999)
    }
}
