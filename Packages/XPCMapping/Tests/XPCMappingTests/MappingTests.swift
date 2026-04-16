import XCTest
import EngineInterface
import PlannerCore
@testable import XPCMapping

final class MappingTests: XCTestCase {

    // MARK: - TorrentSummary

    func test_torrentSummary_roundTrip_allFields() {
        let domain = TorrentSummary(
            torrentID: "abc-123",
            name: "Big Buck Bunny",
            totalBytes: 1_073_741_824,
            progress: 0.75,
            state: .downloading,
            peerCount: 12,
            downRateBytesPerSec: 2_000_000,
            upRateBytesPerSec: 500_000,
            errorMessage: nil
        )
        let reconstructed = TorrentSummary(from: TorrentSummaryDTO(from: domain))
        XCTAssertEqual(reconstructed.torrentID, domain.torrentID)
        XCTAssertEqual(reconstructed.name, domain.name)
        XCTAssertEqual(reconstructed.totalBytes, domain.totalBytes)
        // Q16 encoding loses sub-1/65536 precision — allow a small tolerance.
        XCTAssertEqual(reconstructed.progress, domain.progress, accuracy: 1.0 / 65536.0)
        XCTAssertEqual(reconstructed.state, domain.state)
        XCTAssertEqual(reconstructed.peerCount, domain.peerCount)
        XCTAssertEqual(reconstructed.downRateBytesPerSec, domain.downRateBytesPerSec)
        XCTAssertEqual(reconstructed.upRateBytesPerSec, domain.upRateBytesPerSec)
        XCTAssertNil(reconstructed.errorMessage)
    }

    func test_torrentSummary_roundTrip_withErrorMessage() {
        let domain = TorrentSummary(
            torrentID: "err-001",
            name: "Broken",
            totalBytes: 0,
            progress: 0.0,
            state: .error,
            peerCount: 0,
            downRateBytesPerSec: 0,
            upRateBytesPerSec: 0,
            errorMessage: "tracker unreachable"
        )
        let reconstructed = TorrentSummary(from: TorrentSummaryDTO(from: domain))
        XCTAssertEqual(reconstructed.errorMessage, domain.errorMessage)
        XCTAssertEqual(reconstructed.state, .error)
    }

    func test_torrentSummary_progressQ16_edgeCases() {
        let zero = TorrentSummary(
            torrentID: "t", name: "t", totalBytes: 0,
            progress: 0.0, state: .queued,
            peerCount: 0, downRateBytesPerSec: 0, upRateBytesPerSec: 0,
            errorMessage: nil
        )
        XCTAssertEqual(TorrentSummaryDTO(from: zero).progressQ16, 0)
        XCTAssertEqual(TorrentSummary(from: TorrentSummaryDTO(from: zero)).progress, 0.0, accuracy: 1e-9)

        let full = TorrentSummary(
            torrentID: "t", name: "t", totalBytes: 1000,
            progress: 1.0, state: .seeding,
            peerCount: 0, downRateBytesPerSec: 0, upRateBytesPerSec: 0,
            errorMessage: nil
        )
        XCTAssertEqual(TorrentSummaryDTO(from: full).progressQ16, 65536)
        XCTAssertEqual(TorrentSummary(from: TorrentSummaryDTO(from: full)).progress, 1.0, accuracy: 1e-9)
    }

    func test_torrentSummary_allStates() {
        for state in TorrentState.allCases {
            let domain = TorrentSummary(
                torrentID: "t", name: "t", totalBytes: 0,
                progress: 0.0, state: state,
                peerCount: 0, downRateBytesPerSec: 0, upRateBytesPerSec: 0,
                errorMessage: nil
            )
            let reconstructed = TorrentSummary(from: TorrentSummaryDTO(from: domain))
            XCTAssertEqual(reconstructed.state, state, "State round-trip failed for \(state)")
        }
    }

    // MARK: - TorrentFile

    func test_torrentFile_roundTrip_allFields() {
        let domain = TorrentFile(
            fileIndex: 3,
            path: "movie/big-buck-bunny.mp4",
            sizeBytes: 734_003_200,
            mimeTypeHint: "video/mp4",
            isPlayableByAVFoundation: true
        )
        let reconstructed = TorrentFile(from: TorrentFileDTO(from: domain))
        XCTAssertEqual(reconstructed.fileIndex, domain.fileIndex)
        XCTAssertEqual(reconstructed.path, domain.path)
        XCTAssertEqual(reconstructed.sizeBytes, domain.sizeBytes)
        XCTAssertEqual(reconstructed.mimeTypeHint, domain.mimeTypeHint)
        XCTAssertEqual(reconstructed.isPlayableByAVFoundation, domain.isPlayableByAVFoundation)
    }

    func test_torrentFile_roundTrip_nilMimeType() {
        let domain = TorrentFile(
            fileIndex: 0,
            path: "README.txt",
            sizeBytes: 1024,
            mimeTypeHint: nil,
            isPlayableByAVFoundation: false
        )
        let reconstructed = TorrentFile(from: TorrentFileDTO(from: domain))
        XCTAssertNil(reconstructed.mimeTypeHint)
        XCTAssertFalse(reconstructed.isPlayableByAVFoundation)
    }

    func test_torrentFile_roundTrip_zeroIndex() {
        let domain = TorrentFile(
            fileIndex: 0,
            path: "single.mkv",
            sizeBytes: 0,
            mimeTypeHint: nil,
            isPlayableByAVFoundation: false
        )
        let reconstructed = TorrentFile(from: TorrentFileDTO(from: domain))
        XCTAssertEqual(reconstructed.fileIndex, 0)
    }

    // MARK: - StreamDescriptor

    func test_streamDescriptor_roundTrip_allFields() {
        let domain = StreamDescriptor(
            streamID: "stream-uuid-001",
            loopbackURL: "http://127.0.0.1:49152/stream/stream-uuid-001",
            contentType: "video/mp4",
            contentLength: 734_003_200
        )
        let reconstructed = StreamDescriptor(from: StreamDescriptorDTO(from: domain))
        XCTAssertEqual(reconstructed.streamID, domain.streamID)
        XCTAssertEqual(reconstructed.loopbackURL, domain.loopbackURL)
        XCTAssertEqual(reconstructed.contentType, domain.contentType)
        XCTAssertEqual(reconstructed.contentLength, domain.contentLength)
    }

    func test_streamDescriptor_roundTrip_emptyStrings() {
        let domain = StreamDescriptor(
            streamID: "",
            loopbackURL: "",
            contentType: "",
            contentLength: 0
        )
        let reconstructed = StreamDescriptor(from: StreamDescriptorDTO(from: domain))
        XCTAssertEqual(reconstructed.streamID, "")
        XCTAssertEqual(reconstructed.contentLength, 0)
    }

    // MARK: - ByteRangeValue

    func test_byteRangeValue_roundTrip() {
        let domain = ByteRangeValue(start: 1024, end: 2047)
        let reconstructed = ByteRangeValue(from: ByteRangeDTO(from: domain))
        XCTAssertEqual(reconstructed.start, domain.start)
        XCTAssertEqual(reconstructed.end, domain.end)
    }

    func test_byteRangeValue_roundTrip_zeroBounds() {
        let domain = ByteRangeValue(start: 0, end: 0)
        let reconstructed = ByteRangeValue(from: ByteRangeDTO(from: domain))
        XCTAssertEqual(reconstructed.start, 0)
        XCTAssertEqual(reconstructed.end, 0)
    }

    func test_byteRangeValue_plannerCoreBridge() {
        let byteRange = ByteRange(start: 512, end: 1023)
        let value = ByteRangeValue(from: byteRange)
        let back = value.asByteRange()
        XCTAssertEqual(back.start, byteRange.start)
        XCTAssertEqual(back.end, byteRange.end)
    }

    // MARK: - FileAvailability

    func test_fileAvailability_roundTrip_withRanges() {
        let domain = FileAvailability(
            torrentID: "torrent-xyz",
            fileIndex: 2,
            availableRanges: [
                ByteRangeValue(start: 0, end: 16383),
                ByteRangeValue(start: 32768, end: 49151)
            ]
        )
        let reconstructed = FileAvailability(from: FileAvailabilityDTO(from: domain))
        XCTAssertEqual(reconstructed.torrentID, domain.torrentID)
        XCTAssertEqual(reconstructed.fileIndex, domain.fileIndex)
        XCTAssertEqual(reconstructed.availableRanges.count, 2)
        XCTAssertEqual(reconstructed.availableRanges[0].start, 0)
        XCTAssertEqual(reconstructed.availableRanges[0].end, 16383)
        XCTAssertEqual(reconstructed.availableRanges[1].start, 32768)
        XCTAssertEqual(reconstructed.availableRanges[1].end, 49151)
    }

    func test_fileAvailability_roundTrip_emptyRanges() {
        let domain = FileAvailability(torrentID: "t", fileIndex: 0, availableRanges: [])
        let reconstructed = FileAvailability(from: FileAvailabilityDTO(from: domain))
        XCTAssertTrue(reconstructed.availableRanges.isEmpty)
    }

    func test_fileAvailability_roundTrip_zeroFileIndex() {
        let domain = FileAvailability(torrentID: "t", fileIndex: 0, availableRanges: [])
        let reconstructed = FileAvailability(from: FileAvailabilityDTO(from: domain))
        XCTAssertEqual(reconstructed.fileIndex, 0)
    }

    // MARK: - StreamHealth

    func test_streamHealth_roundTrip_allFields() {
        let domain = StreamHealth(
            secondsBufferedAhead: 12.5,
            downloadRateBytesPerSec: 1_500_000,
            requiredBitrateBytesPerSec: 800_000,
            peerCount: 8,
            outstandingCriticalPieces: 3,
            recentStallCount: 1,
            tier: .marginal
        )
        let dto = StreamHealthDTO(streamID: "stream-001", from: domain)
        // streamID survives on the DTO
        XCTAssertEqual(dto.streamID as String, "stream-001")
        // domain fields survive the round-trip
        let reconstructed = StreamHealth(from: dto)
        XCTAssertEqual(reconstructed.secondsBufferedAhead, domain.secondsBufferedAhead)
        XCTAssertEqual(reconstructed.downloadRateBytesPerSec, domain.downloadRateBytesPerSec)
        XCTAssertEqual(reconstructed.requiredBitrateBytesPerSec, domain.requiredBitrateBytesPerSec)
        XCTAssertEqual(reconstructed.peerCount, domain.peerCount)
        XCTAssertEqual(reconstructed.outstandingCriticalPieces, domain.outstandingCriticalPieces)
        XCTAssertEqual(reconstructed.recentStallCount, domain.recentStallCount)
        XCTAssertEqual(reconstructed.tier, domain.tier)
    }

    func test_streamHealth_roundTrip_nilBitrate() {
        let domain = StreamHealth(
            secondsBufferedAhead: 0.0,
            downloadRateBytesPerSec: 0,
            requiredBitrateBytesPerSec: nil,
            peerCount: 0,
            outstandingCriticalPieces: 0,
            recentStallCount: 0,
            tier: .healthy
        )
        let reconstructed = StreamHealth(from: StreamHealthDTO(streamID: "s", from: domain))
        XCTAssertNil(reconstructed.requiredBitrateBytesPerSec)
    }

    func test_streamHealth_allTiers() {
        for tier in [StreamHealth.Tier.healthy, .marginal, .starving] {
            let domain = StreamHealth(
                secondsBufferedAhead: 0,
                downloadRateBytesPerSec: 0,
                requiredBitrateBytesPerSec: nil,
                peerCount: 0,
                outstandingCriticalPieces: 0,
                recentStallCount: 0,
                tier: tier
            )
            let reconstructed = StreamHealth(from: StreamHealthDTO(streamID: "s", from: domain))
            XCTAssertEqual(reconstructed.tier, tier, "Tier round-trip failed for \(tier)")
        }
    }

    func test_streamHealth_unknownTierFallsBackToStarving() {
        let dto = StreamHealthDTO(
            streamID: "s",
            secondsBufferedAhead: 0,
            downloadRateBytesPerSec: 0,
            requiredBitrateBytesPerSec: nil,
            peerCount: 0,
            outstandingCriticalPieces: 0,
            recentStallCount: 0,
            tier: "unexpected"
        )
        let reconstructed = StreamHealth(from: dto)
        XCTAssertEqual(reconstructed.tier, .starving)
    }

    func test_streamHealth_roundTrip_zeroCounts() {
        let domain = StreamHealth(
            secondsBufferedAhead: 0.0,
            downloadRateBytesPerSec: 0,
            requiredBitrateBytesPerSec: nil,
            peerCount: 0,
            outstandingCriticalPieces: 0,
            recentStallCount: 0,
            tier: .starving
        )
        let reconstructed = StreamHealth(from: StreamHealthDTO(streamID: "s", from: domain))
        XCTAssertEqual(reconstructed.peerCount, 0)
        XCTAssertEqual(reconstructed.outstandingCriticalPieces, 0)
        XCTAssertEqual(reconstructed.recentStallCount, 0)
    }

    // MARK: - DiskPressure

    func test_diskPressure_roundTrip_allFields() {
        let domain = DiskPressure(
            totalBudgetBytes: 10_737_418_240,
            usedBytes: 4_294_967_296,
            pinnedBytes: 1_073_741_824,
            evictableBytes: 3_221_225_472,
            level: .warn
        )
        let reconstructed = DiskPressure(from: DiskPressureDTO(from: domain))
        XCTAssertEqual(reconstructed.totalBudgetBytes, domain.totalBudgetBytes)
        XCTAssertEqual(reconstructed.usedBytes, domain.usedBytes)
        XCTAssertEqual(reconstructed.pinnedBytes, domain.pinnedBytes)
        XCTAssertEqual(reconstructed.evictableBytes, domain.evictableBytes)
        XCTAssertEqual(reconstructed.level, domain.level)
    }

    func test_diskPressure_roundTrip_zeroBytes() {
        let domain = DiskPressure(
            totalBudgetBytes: 0,
            usedBytes: 0,
            pinnedBytes: 0,
            evictableBytes: 0,
            level: .ok
        )
        let reconstructed = DiskPressure(from: DiskPressureDTO(from: domain))
        XCTAssertEqual(reconstructed.totalBudgetBytes, 0)
        XCTAssertEqual(reconstructed.level, .ok)
    }

    func test_diskPressure_allLevels() {
        for level in DiskPressureLevel.allCases {
            let domain = DiskPressure(
                totalBudgetBytes: 0, usedBytes: 0, pinnedBytes: 0,
                evictableBytes: 0, level: level
            )
            let reconstructed = DiskPressure(from: DiskPressureDTO(from: domain))
            XCTAssertEqual(reconstructed.level, level, "Level round-trip failed for \(level)")
        }
    }

    // MARK: - Idempotency (domain → DTO → domain → DTO, second DTO equals first)

    func test_torrentSummary_idempotent() {
        let domain = TorrentSummary(
            torrentID: "idem-1", name: "Test", totalBytes: 500,
            progress: 0.5, state: .checking,
            peerCount: 5, downRateBytesPerSec: 100, upRateBytesPerSec: 50,
            errorMessage: nil
        )
        let dto1 = TorrentSummaryDTO(from: domain)
        let domain2 = TorrentSummary(from: dto1)
        let dto2 = TorrentSummaryDTO(from: domain2)
        XCTAssertEqual(dto1.progressQ16, dto2.progressQ16)
        XCTAssertEqual(dto1.state as String, dto2.state as String)
        XCTAssertEqual(dto1.peerCount, dto2.peerCount)
    }

    func test_diskPressure_idempotent() {
        let domain = DiskPressure(
            totalBudgetBytes: 1000, usedBytes: 400, pinnedBytes: 100,
            evictableBytes: 300, level: .critical
        )
        let dto1 = DiskPressureDTO(from: domain)
        let domain2 = DiskPressure(from: dto1)
        let dto2 = DiskPressureDTO(from: domain2)
        XCTAssertEqual(dto1.level as String, dto2.level as String)
        XCTAssertEqual(dto1.usedBytes, dto2.usedBytes)
    }

    func test_fileAvailability_idempotent() {
        let domain = FileAvailability(
            torrentID: "idem-fa",
            fileIndex: 1,
            availableRanges: [ByteRangeValue(start: 0, end: 1023)]
        )
        let dto1 = FileAvailabilityDTO(from: domain)
        let domain2 = FileAvailability(from: dto1)
        let dto2 = FileAvailabilityDTO(from: domain2)
        XCTAssertEqual(dto1.fileIndex, dto2.fileIndex)
        XCTAssertEqual(dto1.availableRanges.count, dto2.availableRanges.count)
        XCTAssertEqual(dto1.availableRanges.first?.startByte, dto2.availableRanges.first?.startByte)
    }
}

// MARK: - PlaybackHistorySnapshot ↔ PlaybackHistoryDTO (A26)

final class PlaybackHistoryMappingTests: XCTestCase {

    func test_playbackHistory_roundTrip_completedAtSet() {
        let domain = PlaybackHistorySnapshot(
            torrentID: "ph-1",
            fileIndex: 2,
            resumeByteOffset: 9_500_000,
            lastPlayedAtMillis: 1_700_000_010_000,
            totalWatchedSeconds: 0,
            completed: true,
            completedAtMillis: 1_700_000_012_345
        )
        let reconstructed = PlaybackHistorySnapshot(from: PlaybackHistoryDTO(from: domain))
        XCTAssertEqual(reconstructed, domain)
    }

    func test_playbackHistory_roundTrip_completedAtNil() {
        let domain = PlaybackHistorySnapshot(
            torrentID: "ph-2",
            fileIndex: 0,
            resumeByteOffset: 1024,
            lastPlayedAtMillis: 1_700_000_011_000,
            totalWatchedSeconds: 0,
            completed: false,
            completedAtMillis: nil
        )
        let reconstructed = PlaybackHistorySnapshot(from: PlaybackHistoryDTO(from: domain))
        XCTAssertEqual(reconstructed, domain)
    }

    func test_playbackHistory_unwatched_roundTrip() {
        let domain = PlaybackHistorySnapshot(
            torrentID: "ph-3",
            fileIndex: 5,
            resumeByteOffset: 0,
            lastPlayedAtMillis: 1_700_000_012_000,
            totalWatchedSeconds: 0,
            completed: false,
            completedAtMillis: nil
        )
        let reconstructed = PlaybackHistorySnapshot(from: PlaybackHistoryDTO(from: domain))
        XCTAssertEqual(reconstructed, domain)
    }
}
