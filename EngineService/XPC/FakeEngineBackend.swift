import Foundation
import EngineInterface

// MARK: - FakeEngineBackend

/// In-memory fake engine backend used by EngineXPCServer before libtorrent exists.
///
/// All mutable state is protected by a single serial DispatchQueue.
/// The timer fires on that queue, so no extra synchronisation is needed.
///
/// Thread safety contract: all public methods are called on XPC's internal dispatch
/// queue; the backend serialises access internally via `queue`.
final class FakeEngineBackend: EngineXPCBackend {

    // MARK: Private state

    private let queue = DispatchQueue(label: "com.butterbar.engine.fake", qos: .default)

    // torrentID → snapshot
    private var torrents: [String: TorrentSummaryDTO] = [:]

    // torrentID → [files]
    private var files: [String: [TorrentFileDTO]] = [:]

    // streamID → descriptor
    private var streams: [String: StreamDescriptorDTO] = [:]

    private weak var clientProxy: (EngineEvents & NSObjectProtocol)?
    private var updateTimer: DispatchSourceTimer?

    // MARK: - Torrent lifecycle

    /// Creates a synthetic torrent from a magnet URI.
    /// Derives a display name from the `dn=` parameter if present; falls back to the hash.
    func addMagnet(_ magnet: String) throws -> TorrentSummaryDTO {
        let torrentID = UUID().uuidString
        let name = extractName(from: magnet) ?? "Unknown-\(torrentID.prefix(8))"

        let dto = TorrentSummaryDTO(
            torrentID: torrentID as NSString,
            name: name as NSString,
            totalBytes: 1_073_741_824, // 1 GB
            progressQ16: 0,
            state: "downloading",
            peerCount: 7,
            downRateBytesPerSec: 2_097_152,  // 2 MB/s
            upRateBytesPerSec: 524_288,       // 512 KB/s
            errorMessage: nil
        )

        queue.sync {
            torrents[torrentID] = dto
            files[torrentID] = makeFakeFiles(for: name, torrentID: torrentID)
            startTimerIfNeeded()
        }

        return dto
    }

    /// Creates a synthetic torrent from a .torrent bookmark (name is synthesised).
    func addTorrentFile(_ bookmarkData: NSData) throws -> TorrentSummaryDTO {
        let torrentID = UUID().uuidString
        let name = "TorrentFile-\(torrentID.prefix(8))"

        let dto = TorrentSummaryDTO(
            torrentID: torrentID as NSString,
            name: name as NSString,
            totalBytes: 536_870_912, // 512 MB
            progressQ16: 0,
            state: "downloading",
            peerCount: 4,
            downRateBytesPerSec: 1_048_576,
            upRateBytesPerSec: 262_144,
            errorMessage: nil
        )

        queue.sync {
            torrents[torrentID] = dto
            files[torrentID] = makeFakeFiles(for: name, torrentID: torrentID)
            startTimerIfNeeded()
        }

        return dto
    }

    func listTorrents() -> [TorrentSummaryDTO] {
        queue.sync { Array(torrents.values) }
    }

    func removeTorrent(_ torrentID: String, deleteData: Bool) {
        queue.sync {
            torrents.removeValue(forKey: torrentID)
            files.removeValue(forKey: torrentID)
            // Close any streams for this torrent.
            streams = streams.filter { $0.value.loopbackURL.range(of: torrentID).location == NSNotFound }
            if torrents.isEmpty { stopTimer() }
        }
    }

    func listFiles(for torrentID: String) throws -> [TorrentFileDTO] {
        let result: [TorrentFileDTO]? = queue.sync { files[torrentID] }
        guard let fileDTOs = result else {
            throw NSError(
                domain: EngineErrorDomain,
                code: EngineErrorCode.torrentNotFound.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "torrent \(torrentID) not found"]
            )
        }
        return fileDTOs
    }

    func setWantedFiles(torrentID: String, fileIndexes: [Int]) throws {
        // No-op: fake backend downloads everything.
    }

    /// Opens a fake stream for any known torrent + file combination.
    func openStream(torrentID: String, fileIndex: Int) throws -> StreamDescriptorDTO {
        let result: StreamDescriptorDTO? = queue.sync {
            guard let torrent = torrents[torrentID] else { return nil }
            let streamID = UUID().uuidString
            let descriptor = StreamDescriptorDTO(
                streamID: streamID as NSString,
                loopbackURL: "http://127.0.0.1:52100/stream/\(streamID)" as NSString,
                contentType: "video/mp4",
                contentLength: torrent.totalBytes,
                resumeByteOffset: 0  // Fake backend has no history storage; real backend populates from CacheManager.fetchHistory.
            )
            streams[streamID] = descriptor
            return descriptor
        }
        guard let descriptor = result else {
            throw NSError(
                domain: EngineErrorDomain,
                code: EngineErrorCode.torrentNotFound.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "torrent \(torrentID) not found"]
            )
        }
        return descriptor
    }

    func closeStream(_ streamID: String) {
        queue.sync { _ = streams.removeValue(forKey: streamID) }
    }

    /// Stores the client proxy weakly and starts the progress-update timer.
    func subscribe(client: EngineEvents & NSObjectProtocol) {
        queue.sync {
            clientProxy = client
            startTimerIfNeeded()
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

    private func makeFakeFiles(for name: String, torrentID: String) -> [TorrentFileDTO] {
        [
            TorrentFileDTO(
                fileIndex: 0,
                path: "\(name)/\(name).mp4" as NSString,
                sizeBytes: 1_000_000_000,
                mimeTypeHint: "video/mp4",
                isPlayableByAVFoundation: true
            ),
            TorrentFileDTO(
                fileIndex: 1,
                path: "\(name)/extras.mkv" as NSString,
                sizeBytes: 73_741_824,
                mimeTypeHint: "video/x-matroska",
                isPlayableByAVFoundation: true
            ),
        ]
    }

    // MARK: - Progress-update timer

    /// Starts a repeating 2-second timer that increments `progressQ16` by 1000 (~1.5%)
    /// for each active torrent, and emits `torrentUpdated` to the subscribed client.
    ///
    /// Must be called on `queue`.
    private func startTimerIfNeeded() {
        guard updateTimer == nil, !torrents.isEmpty else { return }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        updateTimer = timer
    }

    /// Must be called on `queue`.
    private func stopTimer() {
        updateTimer?.cancel()
        updateTimer = nil
    }

    /// Called every 2 seconds. Mutates progress and notifies the subscriber.
    /// Must be called on `queue`.
    private func tick() {
        guard let proxy = clientProxy else {
            // Client gone; stop emitting.
            stopTimer()
            return
        }

        var updatedTorrents: [TorrentSummaryDTO] = []

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
            updatedTorrents.append(updated)
        }

        for snapshot in updatedTorrents {
            proxy.torrentUpdated(snapshot)
        }
    }
}
