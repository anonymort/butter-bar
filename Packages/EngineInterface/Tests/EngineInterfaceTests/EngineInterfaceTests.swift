import XCTest
@testable import EngineInterface

// MARK: - Helpers

private func roundTrip<T: NSObject & NSSecureCoding>(_ object: T) throws -> T {
    let data = try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true)
    guard let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: T.self, from: data) else {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unarchive returned nil"])
    }
    return decoded
}

// MARK: - TorrentSummaryDTO

final class TorrentSummaryDTOTests: XCTestCase {

    func testRoundTrip_allFields() throws {
        let dto = TorrentSummaryDTO(
            torrentID: "abc-123",
            name: "Big Buck Bunny",
            totalBytes: 768_000_000,
            progressQ16: 32768,
            state: "downloading",
            peerCount: 12,
            downRateBytesPerSec: 1_500_000,
            upRateBytesPerSec: 200_000,
            errorMessage: nil
        )
        let decoded = try roundTrip(dto)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.torrentID, "abc-123")
        XCTAssertEqual(decoded.name, "Big Buck Bunny")
        XCTAssertEqual(decoded.totalBytes, 768_000_000)
        XCTAssertEqual(decoded.progressQ16, 32768)
        XCTAssertEqual(decoded.state, "downloading")
        XCTAssertEqual(decoded.peerCount, 12)
        XCTAssertEqual(decoded.downRateBytesPerSec, 1_500_000)
        XCTAssertEqual(decoded.upRateBytesPerSec, 200_000)
        XCTAssertNil(decoded.errorMessage)
    }

    func testRoundTrip_errorMessage_nil() throws {
        let dto = TorrentSummaryDTO(
            torrentID: "t1",
            name: "Test",
            totalBytes: 0,
            progressQ16: 0,
            state: "queued",
            peerCount: 0,
            downRateBytesPerSec: 0,
            upRateBytesPerSec: 0,
            errorMessage: nil
        )
        let decoded = try roundTrip(dto)
        XCTAssertNil(decoded.errorMessage)
    }

    func testRoundTrip_errorMessage_nonNil() throws {
        let dto = TorrentSummaryDTO(
            torrentID: "t2",
            name: "Broken",
            totalBytes: 100,
            progressQ16: 0,
            state: "error",
            peerCount: 0,
            downRateBytesPerSec: 0,
            upRateBytesPerSec: 0,
            errorMessage: "tracker unreachable"
        )
        let decoded = try roundTrip(dto)
        XCTAssertEqual(decoded.errorMessage, "tracker unreachable")
    }
}

// MARK: - TorrentFileDTO

final class TorrentFileDTOTests: XCTestCase {

    func testRoundTrip_allFields() throws {
        let dto = TorrentFileDTO(
            fileIndex: 2,
            path: "video/feature.mp4",
            sizeBytes: 2_147_483_648,
            mimeTypeHint: "video/mp4",
            isPlayableByAVFoundation: true
        )
        let decoded = try roundTrip(dto)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.fileIndex, 2)
        XCTAssertEqual(decoded.path, "video/feature.mp4")
        XCTAssertEqual(decoded.sizeBytes, 2_147_483_648)
        XCTAssertEqual(decoded.mimeTypeHint, "video/mp4")
        XCTAssertTrue(decoded.isPlayableByAVFoundation)
    }

    func testRoundTrip_mimeTypeHint_nil() throws {
        let dto = TorrentFileDTO(
            fileIndex: 0,
            path: "unknown.bin",
            sizeBytes: 512,
            mimeTypeHint: nil,
            isPlayableByAVFoundation: false
        )
        let decoded = try roundTrip(dto)
        XCTAssertNil(decoded.mimeTypeHint)
        XCTAssertFalse(decoded.isPlayableByAVFoundation)
    }

    func testRoundTrip_mimeTypeHint_nonNil() throws {
        let dto = TorrentFileDTO(
            fileIndex: 1,
            path: "audio.m4a",
            sizeBytes: 8_000_000,
            mimeTypeHint: "audio/mp4",
            isPlayableByAVFoundation: true
        )
        let decoded = try roundTrip(dto)
        XCTAssertEqual(decoded.mimeTypeHint, "audio/mp4")
    }
}

// MARK: - StreamDescriptorDTO

final class StreamDescriptorDTOTests: XCTestCase {

    func testRoundTrip_allFields() throws {
        let dto = StreamDescriptorDTO(
            streamID: "stream-xyz",
            loopbackURL: "http://127.0.0.1:49152/stream/stream-xyz",
            contentType: "video/mp4",
            contentLength: 1_073_741_824
        )
        let decoded = try roundTrip(dto)

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.streamID, "stream-xyz")
        XCTAssertEqual(decoded.loopbackURL, "http://127.0.0.1:49152/stream/stream-xyz")
        XCTAssertEqual(decoded.contentType, "video/mp4")
        XCTAssertEqual(decoded.contentLength, 1_073_741_824)
        XCTAssertEqual(decoded.resumeByteOffset, 0)
    }
}

// MARK: - ByteRangeDTO

final class ByteRangeDTOTests: XCTestCase {

    func testRoundTrip() throws {
        let dto = ByteRangeDTO(startByte: 1024, endByte: 2047)
        let decoded = try roundTrip(dto)

        XCTAssertEqual(decoded.startByte, 1024)
        XCTAssertEqual(decoded.endByte, 2047)
    }

    func testRoundTrip_zeroRange() throws {
        let dto = ByteRangeDTO(startByte: 0, endByte: 0)
        let decoded = try roundTrip(dto)
        XCTAssertEqual(decoded.startByte, 0)
        XCTAssertEqual(decoded.endByte, 0)
    }

    func testRoundTrip_largeValues() throws {
        let dto = ByteRangeDTO(startByte: 0, endByte: Int64.max)
        let decoded = try roundTrip(dto)
        XCTAssertEqual(decoded.startByte, 0)
        XCTAssertEqual(decoded.endByte, Int64.max)
    }
}

// MARK: - FileAvailabilityDTO

final class FileAvailabilityDTOTests: XCTestCase {

    func testRoundTrip_emptyRanges() throws {
        let dto = FileAvailabilityDTO(
            torrentID: "t-empty",
            fileIndex: 0,
            availableRanges: []
        )
        let decoded = try roundTrip(dto)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.torrentID, "t-empty")
        XCTAssertEqual(decoded.fileIndex, 0)
        XCTAssertTrue(decoded.availableRanges.isEmpty)
    }

    func testRoundTrip_multipleRanges() throws {
        let ranges = [
            ByteRangeDTO(startByte: 0, endByte: 511),
            ByteRangeDTO(startByte: 1024, endByte: 2047),
            ByteRangeDTO(startByte: 4096, endByte: 8191),
        ]
        let dto = FileAvailabilityDTO(
            torrentID: "t-multi",
            fileIndex: 3,
            availableRanges: ranges
        )
        let decoded = try roundTrip(dto)

        XCTAssertEqual(decoded.availableRanges.count, 3)
        XCTAssertEqual(decoded.availableRanges[0].startByte, 0)
        XCTAssertEqual(decoded.availableRanges[0].endByte, 511)
        XCTAssertEqual(decoded.availableRanges[1].startByte, 1024)
        XCTAssertEqual(decoded.availableRanges[1].endByte, 2047)
        XCTAssertEqual(decoded.availableRanges[2].startByte, 4096)
        XCTAssertEqual(decoded.availableRanges[2].endByte, 8191)
    }

    func testRoundTrip_singleRange() throws {
        let dto = FileAvailabilityDTO(
            torrentID: "t-single",
            fileIndex: 1,
            availableRanges: [ByteRangeDTO(startByte: 0, endByte: 999_999)]
        )
        let decoded = try roundTrip(dto)

        XCTAssertEqual(decoded.availableRanges.count, 1)
        XCTAssertEqual(decoded.availableRanges[0].startByte, 0)
        XCTAssertEqual(decoded.availableRanges[0].endByte, 999_999)
    }
}

// MARK: - StreamHealthDTO

final class StreamHealthDTOTests: XCTestCase {

    func testRoundTrip_allFields() throws {
        let dto = StreamHealthDTO(
            streamID: "sh-001",
            secondsBufferedAhead: 12.5,
            downloadRateBytesPerSec: 5_000_000,
            requiredBitrateBytesPerSec: NSNumber(value: 2_500_000),
            peerCount: 8,
            outstandingCriticalPieces: 3,
            recentStallCount: 0,
            tier: "healthy"
        )
        let decoded = try roundTrip(dto)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.streamID, "sh-001")
        XCTAssertEqual(decoded.secondsBufferedAhead, 12.5, accuracy: 0.001)
        XCTAssertEqual(decoded.downloadRateBytesPerSec, 5_000_000)
        XCTAssertEqual(decoded.requiredBitrateBytesPerSec?.int64Value, 2_500_000)
        XCTAssertEqual(decoded.peerCount, 8)
        XCTAssertEqual(decoded.outstandingCriticalPieces, 3)
        XCTAssertEqual(decoded.recentStallCount, 0)
        XCTAssertEqual(decoded.tier, "healthy")
    }

    func testRoundTrip_requiredBitrate_nil() throws {
        let dto = StreamHealthDTO(
            streamID: "sh-002",
            secondsBufferedAhead: 0.0,
            downloadRateBytesPerSec: 0,
            requiredBitrateBytesPerSec: nil,
            peerCount: 0,
            outstandingCriticalPieces: 10,
            recentStallCount: 2,
            tier: "starving"
        )
        let decoded = try roundTrip(dto)
        XCTAssertNil(decoded.requiredBitrateBytesPerSec)
        XCTAssertEqual(decoded.tier, "starving")
    }

    func testRoundTrip_requiredBitrate_nonNil() throws {
        let dto = StreamHealthDTO(
            streamID: "sh-003",
            secondsBufferedAhead: 5.0,
            downloadRateBytesPerSec: 3_000_000,
            requiredBitrateBytesPerSec: NSNumber(value: 1_800_000),
            peerCount: 4,
            outstandingCriticalPieces: 1,
            recentStallCount: 0,
            tier: "marginal"
        )
        let decoded = try roundTrip(dto)
        XCTAssertEqual(decoded.requiredBitrateBytesPerSec?.int64Value, 1_800_000)
        XCTAssertEqual(decoded.tier, "marginal")
    }
}

// MARK: - DiskPressureDTO

final class DiskPressureDTOTests: XCTestCase {

    func testRoundTrip_allFields() throws {
        let dto = DiskPressureDTO(
            totalBudgetBytes: 10_737_418_240,
            usedBytes: 6_442_450_944,
            pinnedBytes: 2_147_483_648,
            evictableBytes: 4_294_967_296,
            level: "warn"
        )
        let decoded = try roundTrip(dto)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.totalBudgetBytes, 10_737_418_240)
        XCTAssertEqual(decoded.usedBytes, 6_442_450_944)
        XCTAssertEqual(decoded.pinnedBytes, 2_147_483_648)
        XCTAssertEqual(decoded.evictableBytes, 4_294_967_296)
        XCTAssertEqual(decoded.level, "warn")
    }

    func testRoundTrip_okLevel() throws {
        let dto = DiskPressureDTO(
            totalBudgetBytes: 10_000_000_000,
            usedBytes: 1_000_000_000,
            pinnedBytes: 500_000_000,
            evictableBytes: 500_000_000,
            level: "ok"
        )
        let decoded = try roundTrip(dto)
        XCTAssertEqual(decoded.level, "ok")
    }

    func testRoundTrip_criticalLevel() throws {
        let dto = DiskPressureDTO(
            totalBudgetBytes: 5_000_000_000,
            usedBytes: 4_900_000_000,
            pinnedBytes: 4_900_000_000,
            evictableBytes: 0,
            level: "critical"
        )
        let decoded = try roundTrip(dto)
        XCTAssertEqual(decoded.level, "critical")
        XCTAssertEqual(decoded.evictableBytes, 0)
    }
}
