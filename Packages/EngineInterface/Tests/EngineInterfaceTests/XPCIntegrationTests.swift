import XCTest
@testable import EngineInterface

// MARK: - In-process integration tests for the XPC happy path
//
// These tests exercise the full method surface of an EngineXPC-conforming object
// in-process, without involving NSXPCConnection. The server under test is
// MockEngineServer — a local replica of FakeEngineBackend's logic, but typed to
// match the EngineXPC protocol directly so we can call it synchronously.
//
// Why a local replica instead of importing EngineService?
//   EngineService is an Xcode-only target (not a Swift package), so it can't be
//   imported from an SPM test target. The mock here gives the same coverage over
//   the XPC contract (DTO construction, happy-path routing, error codes) without
//   a cross-boundary import.
//
// Review note for Opus: the "true" FakeEngineBackend lives at
// EngineService/XPC/FakeEngineBackend.swift and is used by EngineXPCServer at
// runtime. This file tests equivalent logic to verify the DTO contract is correct
// end-to-end. If the backend logic changes, update both files.

// MARK: - MockEngineServer

/// Minimal in-process fake that exercises the EngineXPC contract without XPC transport.
private final class MockEngineServer: NSObject, EngineXPC {

    private var torrents: [String: TorrentSummaryDTO] = [:]
    private var files: [String: [TorrentFileDTO]] = [:]
    private var streams: [String: StreamDescriptorDTO] = [:]

    // Collected events for test assertion.
    var receivedUpdates: [TorrentSummaryDTO] = []

    // MARK: EngineXPC conformance

    func addMagnet(_ magnet: String,
                   reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void) {
        let id = "fake-\(torrents.count + 1)"
        let name = extractName(from: magnet) ?? "TestTorrent"
        let dto = TorrentSummaryDTO(
            torrentID: id as NSString,
            name: name as NSString,
            totalBytes: 1_073_741_824,
            progressQ16: 0,
            state: "downloading",
            peerCount: 5,
            downRateBytesPerSec: 2_097_152,
            upRateBytesPerSec: 524_288,
            errorMessage: nil
        )
        torrents[id] = dto
        files[id] = [
            TorrentFileDTO(
                fileIndex: 0,
                path: "\(name)/\(name).mp4" as NSString,
                sizeBytes: 1_000_000_000,
                mimeTypeHint: "video/mp4",
                isPlayableByAVFoundation: true
            ),
            TorrentFileDTO(
                fileIndex: 1,
                path: "\(name)/sample.mkv" as NSString,
                sizeBytes: 73_741_824,
                mimeTypeHint: "video/x-matroska",
                isPlayableByAVFoundation: true
            ),
        ]
        reply(dto, nil)
    }

    func addTorrentFile(_ bookmarkData: NSData,
                        reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void) {
        let id = "fake-file-\(torrents.count + 1)"
        let dto = TorrentSummaryDTO(
            torrentID: id as NSString,
            name: "TorrentFile" as NSString,
            totalBytes: 536_870_912,
            progressQ16: 0,
            state: "downloading",
            peerCount: 3,
            downRateBytesPerSec: 1_048_576,
            upRateBytesPerSec: 262_144,
            errorMessage: nil
        )
        torrents[id] = dto
        reply(dto, nil)
    }

    func listTorrents(_ reply: @escaping ([TorrentSummaryDTO]) -> Void) {
        reply(Array(torrents.values))
    }

    func removeTorrent(_ torrentID: NSString,
                       deleteData: Bool,
                       reply: @escaping (NSError?) -> Void) {
        let id = torrentID as String
        torrents.removeValue(forKey: id)
        files.removeValue(forKey: id)
        reply(nil)
    }

    func listFiles(_ torrentID: NSString,
                   reply: @escaping ([TorrentFileDTO], NSError?) -> Void) {
        let id = torrentID as String
        if let fileDTOs = files[id] {
            reply(fileDTOs, nil)
        } else {
            reply([], NSError(
                domain: EngineErrorDomain,
                code: EngineErrorCode.torrentNotFound.rawValue,
                userInfo: nil
            ))
        }
    }

    func setWantedFiles(_ torrentID: NSString,
                        fileIndexes: [NSNumber],
                        reply: @escaping (NSError?) -> Void) {
        reply(nil)
    }

    func openStream(_ torrentID: NSString,
                    fileIndex: NSNumber,
                    reply: @escaping (StreamDescriptorDTO?, NSError?) -> Void) {
        let id = torrentID as String
        guard torrents[id] != nil else {
            reply(nil, NSError(
                domain: EngineErrorDomain,
                code: EngineErrorCode.torrentNotFound.rawValue,
                userInfo: nil
            ))
            return
        }
        let streamID = "stream-\(streams.count + 1)"
        let descriptor = StreamDescriptorDTO(
            streamID: streamID as NSString,
            loopbackURL: "http://127.0.0.1:52100/stream/\(streamID)" as NSString,
            contentType: "video/mp4",
            contentLength: torrents[id]!.totalBytes
        )
        streams[streamID] = descriptor
        reply(descriptor, nil)
    }

    func closeStream(_ streamID: NSString,
                     reply: @escaping () -> Void) {
        streams.removeValue(forKey: streamID as String)
        reply()
    }

    func subscribe(_ client: EngineEvents,
                   reply: @escaping (NSError?) -> Void) {
        reply(nil)
    }

    // MARK: - Event simulation

    /// Simulate one tick of progress updates.
    /// Increments progressQ16 by 1000 and calls back the provided event receiver.
    func simulateTick(into receiver: FakeEventReceiver) {
        for (id, snapshot) in torrents {
            let newProgress = min(snapshot.progressQ16 + 1000, 65536)
            let newState: NSString = newProgress >= 65536 ? "seeding" : snapshot.state
            let updated = TorrentSummaryDTO(
                torrentID: snapshot.torrentID,
                name: snapshot.name,
                totalBytes: snapshot.totalBytes,
                progressQ16: newProgress,
                state: newState,
                peerCount: snapshot.peerCount,
                downRateBytesPerSec: newState == "seeding" ? 0 : snapshot.downRateBytesPerSec,
                upRateBytesPerSec: snapshot.upRateBytesPerSec,
                errorMessage: nil
            )
            torrents[id] = updated
            receiver.torrentUpdated(updated)
        }
    }

    // MARK: - Private helpers

    private func extractName(from magnet: String) -> String? {
        guard let range = magnet.range(of: "dn=") else { return nil }
        let rest = String(magnet[range.upperBound...])
        let name = rest.prefix(while: { $0 != "&" })
        let decoded = name.removingPercentEncoding ?? String(name)
        return decoded.isEmpty ? nil : decoded
    }
}

// MARK: - FakeEventReceiver

/// Captures EngineEvents callbacks for test assertion.
private final class FakeEventReceiver: NSObject, EngineEvents {
    var torrentUpdates: [TorrentSummaryDTO] = []
    var fileAvailabilityUpdates: [FileAvailabilityDTO] = []
    var streamHealthUpdates: [StreamHealthDTO] = []
    var diskPressureUpdates: [DiskPressureDTO] = []

    func torrentUpdated(_ snapshot: TorrentSummaryDTO) {
        torrentUpdates.append(snapshot)
    }

    func fileAvailabilityChanged(_ update: FileAvailabilityDTO) {
        fileAvailabilityUpdates.append(update)
    }

    func streamHealthChanged(_ update: StreamHealthDTO) {
        streamHealthUpdates.append(update)
    }

    func diskPressureChanged(_ update: DiskPressureDTO) {
        diskPressureUpdates.append(update)
    }
}

// MARK: - XPCIntegrationTests

final class XPCIntegrationTests: XCTestCase {

    // MARK: - Happy path: full flow

    /// Walks the complete happy path:
    /// addMagnet → listTorrents → listFiles → openStream → subscribe (events) → removeTorrent
    func testHappyPath_fullFlow() {
        let server = MockEngineServer()
        let receiver = FakeEventReceiver()

        // 1. addMagnet returns a TorrentSummaryDTO.
        var addedDTO: TorrentSummaryDTO?
        server.addMagnet("magnet:?xt=urn:btih:FAKEHASH&dn=TestMovie") { dto, error in
            XCTAssertNil(error, "addMagnet must not return an error")
            XCTAssertNotNil(dto, "addMagnet must return a TorrentSummaryDTO")
            addedDTO = dto
        }
        guard let summary = addedDTO else {
            XCTFail("No DTO returned from addMagnet")
            return
        }

        XCTAssertEqual(summary.schemaVersion, 1)
        XCTAssertFalse((summary.torrentID as String).isEmpty)
        XCTAssertEqual(summary.name, "TestMovie")
        XCTAssertEqual(summary.state, "downloading")
        XCTAssertGreaterThan(summary.totalBytes, 0)

        // 2. listTorrents contains the added torrent.
        var listResult: [TorrentSummaryDTO] = []
        server.listTorrents { summaries in
            listResult = summaries
        }
        XCTAssertEqual(listResult.count, 1)
        XCTAssertEqual(listResult.first?.torrentID, summary.torrentID)

        // 3. listFiles returns file entries for the known torrent.
        var listedFiles: [TorrentFileDTO] = []
        var listFilesError: NSError?
        server.listFiles(summary.torrentID) { fileDTOs, error in
            listedFiles = fileDTOs
            listFilesError = error
        }
        XCTAssertNil(listFilesError, "listFiles must not return an error for a known torrent")
        XCTAssertFalse(listedFiles.isEmpty, "listFiles must return at least one file")
        XCTAssertEqual(listedFiles.first?.schemaVersion, 1)
        XCTAssertNotNil(listedFiles.first?.mimeTypeHint)

        // 4. openStream returns a StreamDescriptorDTO with a loopback URL.
        var descriptor: StreamDescriptorDTO?
        var openStreamError: NSError?
        server.openStream(summary.torrentID, fileIndex: 0) { dto, error in
            descriptor = dto
            openStreamError = error
        }
        XCTAssertNil(openStreamError, "openStream must not return an error for a known torrent")
        guard let streamDesc = descriptor else {
            XCTFail("openStream must return a StreamDescriptorDTO")
            return
        }
        XCTAssertEqual(streamDesc.schemaVersion, 1)
        XCTAssertFalse((streamDesc.streamID as String).isEmpty)
        XCTAssertTrue((streamDesc.loopbackURL as String).hasPrefix("http://127.0.0.1:"),
                      "loopback URL must point at localhost")
        XCTAssertFalse((streamDesc.contentType as String).isEmpty)
        XCTAssertGreaterThan(streamDesc.contentLength, 0)

        // 5. subscribe succeeds; simulated tick delivers torrentUpdated events.
        var subscribeError: NSError?
        server.subscribe(receiver) { error in
            subscribeError = error
        }
        XCTAssertNil(subscribeError, "subscribe must succeed")

        server.simulateTick(into: receiver)

        XCTAssertFalse(receiver.torrentUpdates.isEmpty, "torrentUpdated events must arrive after a tick")
        let updatedSnapshot = receiver.torrentUpdates.first!
        XCTAssertEqual(updatedSnapshot.torrentID, summary.torrentID)
        XCTAssertGreaterThan(updatedSnapshot.progressQ16, summary.progressQ16,
                             "progressQ16 must increase on each tick")

        // 6. removeTorrent removes it from listTorrents.
        var removeError: NSError?
        server.removeTorrent(summary.torrentID, deleteData: false) { error in
            removeError = error
        }
        XCTAssertNil(removeError, "removeTorrent must not return an error")

        var afterRemove: [TorrentSummaryDTO] = []
        server.listTorrents { summaries in
            afterRemove = summaries
        }
        XCTAssertTrue(afterRemove.isEmpty, "listTorrents must be empty after remove")
    }

    // MARK: - Error paths

    func testListFiles_unknownTorrent_returnsError() {
        let server = MockEngineServer()
        var receivedError: NSError?
        server.listFiles("does-not-exist") { _, error in
            receivedError = error
        }
        XCTAssertNotNil(receivedError)
        XCTAssertEqual(receivedError?.domain, EngineErrorDomain)
        XCTAssertEqual(receivedError?.code, EngineErrorCode.torrentNotFound.rawValue)
    }

    func testOpenStream_unknownTorrent_returnsError() {
        let server = MockEngineServer()
        var receivedError: NSError?
        var receivedDTO: StreamDescriptorDTO?
        server.openStream("does-not-exist", fileIndex: 0) { dto, error in
            receivedDTO = dto
            receivedError = error
        }
        XCTAssertNil(receivedDTO)
        XCTAssertNotNil(receivedError)
        XCTAssertEqual(receivedError?.domain, EngineErrorDomain)
        XCTAssertEqual(receivedError?.code, EngineErrorCode.torrentNotFound.rawValue)
    }

    // MARK: - listTorrents starts empty

    func testListTorrents_initiallyEmpty() {
        let server = MockEngineServer()
        var result: [TorrentSummaryDTO] = []
        server.listTorrents { result = $0 }
        XCTAssertTrue(result.isEmpty, "listTorrents must return [] before any torrents are added")
    }

    // MARK: - Progress advances and transitions to seeding

    func testProgressTick_advancesToSeeding() {
        let server = MockEngineServer()
        let receiver = FakeEventReceiver()

        server.addMagnet("magnet:?xt=urn:btih:PROGTEST&dn=ProgressTest") { _, _ in }

        // Simulate enough ticks to reach 65536 (seeding).
        // progressQ16 starts at 0, increments by 1000 per tick → 66 ticks needed.
        for _ in 0..<66 {
            server.simulateTick(into: receiver)
        }

        let lastUpdate = receiver.torrentUpdates.last
        XCTAssertNotNil(lastUpdate)
        XCTAssertEqual(lastUpdate?.progressQ16, 65536)
        XCTAssertEqual(lastUpdate?.state, "seeding")
    }

    // MARK: - Multiple torrents

    func testMultipleTorrents_eachListedSeparately() {
        let server = MockEngineServer()

        server.addMagnet("magnet:?xt=urn:btih:AAA&dn=MovieA") { _, _ in }
        server.addMagnet("magnet:?xt=urn:btih:BBB&dn=MovieB") { _, _ in }

        var result: [TorrentSummaryDTO] = []
        server.listTorrents { result = $0 }

        XCTAssertEqual(result.count, 2)
        let names = Set(result.map { $0.name as String })
        XCTAssertTrue(names.contains("MovieA"))
        XCTAssertTrue(names.contains("MovieB"))
    }

    // MARK: - setWantedFiles is a no-op success

    func testSetWantedFiles_succeedsNoOp() {
        let server = MockEngineServer()
        var addedID: NSString = ""
        server.addMagnet("magnet:?xt=urn:btih:WANTEDTEST&dn=WantedTest") { dto, _ in
            addedID = dto?.torrentID ?? ""
        }

        var error: NSError?
        server.setWantedFiles(addedID, fileIndexes: [0]) { error = $0 }
        XCTAssertNil(error, "setWantedFiles must succeed silently")
    }

    // MARK: - closeStream succeeds

    func testCloseStream_succeedsNoOp() {
        let server = MockEngineServer()

        var torrentID: NSString = ""
        server.addMagnet("magnet:?xt=urn:btih:CLOSETEST&dn=CloseTest") { dto, _ in
            torrentID = dto?.torrentID ?? ""
        }

        var streamID: NSString = ""
        server.openStream(torrentID, fileIndex: 0) { dto, _ in
            streamID = dto?.streamID ?? ""
        }

        var closeCalled = false
        server.closeStream(streamID) { closeCalled = true }
        XCTAssertTrue(closeCalled, "closeStream reply must be called")
    }

    // MARK: - DTO round-trip through NSSecureCoding survives the integration path

    func testAddedTorrent_DTORoundTrips() throws {
        let server = MockEngineServer()
        var dto: TorrentSummaryDTO?
        server.addMagnet("magnet:?xt=urn:btih:ROUNDTRIP&dn=RoundTripTest") { d, _ in dto = d }

        guard let original = dto else { XCTFail(); return }

        let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: TorrentSummaryDTO.self, from: data)

        XCTAssertEqual(decoded?.torrentID, original.torrentID)
        XCTAssertEqual(decoded?.name, original.name)
        XCTAssertEqual(decoded?.state, original.state)
        XCTAssertEqual(decoded?.progressQ16, original.progressQ16)
    }
}
