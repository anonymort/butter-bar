import Foundation
import EngineInterface
import EngineStore
import GRDB
import PlannerCore

// MARK: - EngineXPCBackend protocol

/// Internal protocol implemented by both RealEngineBackend and FakeEngineBackend.
/// EngineXPCServer delegates every call through this abstraction.
protocol EngineXPCBackend: AnyObject {
    func addMagnet(_ magnet: String) throws -> TorrentSummaryDTO
    func addTorrentFile(_ bookmarkData: NSData) throws -> TorrentSummaryDTO
    func listTorrents() -> [TorrentSummaryDTO]
    func removeTorrent(_ torrentID: String, deleteData: Bool)
    func listFiles(for torrentID: String) throws -> [TorrentFileDTO]
    func setWantedFiles(torrentID: String, fileIndexes: [Int]) throws
    func openStream(torrentID: String, fileIndex: Int) throws -> StreamDescriptorDTO
    func closeStream(_ streamID: String)
    func subscribe(client: EngineEvents & NSObjectProtocol)
}

// MARK: - RealEngineBackend

/// Production backend that wires EngineXPCServer to the real
/// TorrentBridge + StreamRegistry + GatewayListener + CacheManager stack.
///
/// Lifetime: process startup → shutdown.  One instance is created in main.swift
/// and shared across all per-connection EngineXPCServer instances.
///
/// Thread safety: XPC dispatches each method on its own queue. All mutable state
/// here is serialised onto `queue`.  TorrentBridge serialises internally.
/// StreamRegistry requires single-queue access — all createStream/closeStream
/// calls go through `queue`.
final class RealEngineBackend: EngineXPCBackend {

    // MARK: - Private state

    private let queue = DispatchQueue(label: "com.butterbar.engine.backend", qos: .default)

    private let bridge: TorrentBridge
    private let gatewayListener: GatewayListener
    private let registry: StreamRegistry
    private let cacheManager: CacheManager?   // nil if DB failed at startup
    private let alertDispatcher: AlertDispatcher

    /// Populated by addMagnet / addTorrentFile; drives listTorrents.
    private var knownTorrentIDs: Set<String> = []

    /// Weak reference to the current event proxy; stored on first subscribe().
    private weak var eventProxy: (EngineEvents & NSObjectProtocol)?

    // MARK: - Init

    /// Starts the full engine stack. Exits the process if a critical component fails.
    init() {
        // 1. TorrentBridge
        let bridge = TorrentBridge()
        self.bridge = bridge

        // 2. CacheManager — non-fatal if DB fails.
        let cacheManager = RealEngineBackend.openCacheManager()
        self.cacheManager = cacheManager

        // 3. GatewayListener — fatal if binding fails.
        let listener: GatewayListener
        do {
            listener = try GatewayListener()
        } catch {
            NSLog("[RealEngineBackend] FATAL: GatewayListener init failed: %@", "\(error)")
            exit(1)
        }
        self.gatewayListener = listener

        // 4. StreamRegistry (must be captured before the request handler closure below).
        let registry = StreamRegistry(cacheManager: cacheManager)
        self.registry = registry

        // 5. Start listener and wait for port (up to 5 s).
        let semaphore = DispatchSemaphore(value: 0)
        listener.onReady = { port in
            NSLog("[RealEngineBackend] gateway bound on port %d", port)
            semaphore.signal()
        }
        listener.requestHandler = { [weak registry] request in
            registry?.handleRequest(request) ?? HTTPRangeResponse.notFound()
        }
        listener.start()

        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            NSLog("[RealEngineBackend] FATAL: GatewayListener did not become ready within 5 s")
            exit(1)
        }

        // 6. AlertDispatcher (subscribed lazily in subscribe()).
        self.alertDispatcher = AlertDispatcher(bridge: bridge)

        NSLog("[RealEngineBackend] startup complete")
    }

    // MARK: - EngineXPCBackend

    func addMagnet(_ magnet: String) throws -> TorrentSummaryDTO {
        let torrentID = try bridge.addMagnet(magnet)
        let dto = try buildSummaryDTO(torrentID: torrentID)
        queue.sync { _ = knownTorrentIDs.insert(torrentID) }
        return dto
    }

    func addTorrentFile(_ bookmarkData: NSData) throws -> TorrentSummaryDTO {
        // Resolve the bookmark to a file path.
        var stale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmarkData as Data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw engineError(.bookmarkInvalid, "bookmark resolution failed: \(error.localizedDescription)")
        }

        guard url.startAccessingSecurityScopedResource() else {
            throw engineError(.bookmarkInvalid, "could not access security-scoped resource")
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let torrentID = try bridge.addTorrentFile(atPath: url.path)

        let dto = try buildSummaryDTO(torrentID: torrentID)
        queue.sync { _ = knownTorrentIDs.insert(torrentID) }
        return dto
    }

    func listTorrents() -> [TorrentSummaryDTO] {
        let ids = queue.sync { knownTorrentIDs }
        return ids.compactMap { try? buildSummaryDTO(torrentID: $0) }
    }

    func removeTorrent(_ torrentID: String, deleteData: Bool) {
        bridge.removeTorrent(torrentID, deleteData: deleteData)
        queue.sync { _ = knownTorrentIDs.remove(torrentID) }
    }

    func listFiles(for torrentID: String) throws -> [TorrentFileDTO] {
        let rawFiles = try bridge.listFiles(torrentID)
        return rawFiles.enumerated().map { (index, dict) in
            let path   = dict["path"] as? String ?? ""
            let size   = (dict["size"] as? NSNumber)?.int64Value ?? 0
            let mime   = mimeType(for: path)
            return TorrentFileDTO(
                fileIndex: Int32(index),
                path: path as NSString,
                sizeBytes: size,
                mimeTypeHint: mime as NSString,
                isPlayableByAVFoundation: isPlayable(mimeType: mime)
            )
        }
    }

    func setWantedFiles(torrentID: String, fileIndexes: [Int]) throws {
        let rawFiles = try bridge.listFiles(torrentID)
        let wantedSet = Set(fileIndexes)
        for index in 0..<rawFiles.count {
            let priority: Int32 = wantedSet.contains(index) ? 4 : 0
            // Log but don't fail — partially successful priority sets are better than none.
            do {
                try bridge.setFilePriority(torrentID, fileIndex: Int32(index), priority: priority)
            } catch {
                NSLog("[RealEngineBackend] setFilePriority(%d, %d) error: %@", index, priority, "\(error)")
            }
        }
    }

    func openStream(torrentID: String, fileIndex: Int) throws -> StreamDescriptorDTO {
        // Resume offset from history (best-effort).
        let resumeOffset: Int64 = {
            guard let cm = cacheManager,
                  let record = try? cm.fetchHistory(torrentId: torrentID, fileIndex: fileIndex)
            else { return 0 }
            return record.resumeByteOffset
        }()

        // File size from listFiles.
        let rawFiles = try bridge.listFiles(torrentID)
        guard fileIndex < rawFiles.count else {
            throw engineError(.fileIndexOutOfRange, "fileIndex \(fileIndex) out of range for \(torrentID)")
        }

        let fileDict = rawFiles[fileIndex]
        let contentLength = (fileDict["size"] as? NSNumber)?.int64Value ?? 0
        let path          = fileDict["path"] as? String ?? ""
        let contentType   = mimeType(for: path)

        let streamID = UUID().uuidString

        // createStream must run on queue (StreamRegistry requires single-queue access).
        var createError: Error?
        queue.sync {
            do {
                try registry.createStream(
                    streamID: streamID,
                    contentType: contentType,
                    contentLength: contentLength,
                    bridge: bridge,
                    torrentID: torrentID,
                    fileIndex: fileIndex,
                    onHealthUpdate: { [weak self] health in
                        self?.emitStreamHealth(streamID: streamID, health: health)
                    }
                )
            } catch {
                createError = error
            }
        }

        if let err = createError {
            throw err
        }

        guard let port = gatewayListener.port else {
            throw engineError(.streamOpenFailed, "gateway port not available")
        }

        let loopbackURL = "http://127.0.0.1:\(port)/stream/\(streamID)"
        return StreamDescriptorDTO(
            streamID: streamID as NSString,
            loopbackURL: loopbackURL as NSString,
            contentType: contentType as NSString,
            contentLength: contentLength,
            resumeByteOffset: resumeOffset
        )
    }

    func closeStream(_ streamID: String) {
        queue.sync { registry.closeStream(streamID) }
    }

    func subscribe(client: EngineEvents & NSObjectProtocol) {
        eventProxy = client
        alertDispatcher.setClient(client)
        alertDispatcher.startListening()
    }

    // MARK: - Private helpers

    private func buildSummaryDTO(torrentID: String) throws -> TorrentSummaryDTO {
        guard let snapshot = try? bridge.statusSnapshot(torrentID) else {
            // Metadata not yet available — return a minimal DTO.
            return TorrentSummaryDTO(
                torrentID: torrentID as NSString,
                name: torrentID as NSString,
                totalBytes: 0,
                progressQ16: 0,
                state: "queued",
                peerCount: 0,
                downRateBytesPerSec: 0,
                upRateBytesPerSec: 0,
                errorMessage: nil
            )
        }

        let progress = (snapshot["progress"] as? NSNumber)?.floatValue ?? 0
        return TorrentSummaryDTO(
            torrentID: torrentID as NSString,
            name: torrentID as NSString,      // real name comes from metadata alert
            totalBytes: (snapshot["totalBytes"] as? NSNumber)?.int64Value ?? 0,
            progressQ16: Int32(min(progress * 65536, 65536)),
            state: (snapshot["state"] as? NSString) ?? ("unknown" as NSString),
            peerCount: Int32((snapshot["peerCount"] as? NSNumber)?.intValue ?? 0),
            downRateBytesPerSec: (snapshot["downloadRate"] as? NSNumber)?.int64Value ?? 0,
            upRateBytesPerSec: (snapshot["uploadRate"] as? NSNumber)?.int64Value ?? 0,
            errorMessage: nil
        )
    }

    private func emitStreamHealth(streamID: String, health: StreamHealth) {
        guard let proxy = eventProxy else { return }
        let dto = StreamHealthDTO(
            streamID: streamID as NSString,
            secondsBufferedAhead: health.secondsBufferedAhead,
            downloadRateBytesPerSec: health.downloadRateBytesPerSec,
            requiredBitrateBytesPerSec: health.requiredBitrateBytesPerSec.map { NSNumber(value: $0) },
            peerCount: Int32(health.peerCount),
            outstandingCriticalPieces: Int32(health.outstandingCriticalPieces),
            recentStallCount: Int32(health.recentStallCount),
            tier: health.tier.rawValue as NSString
        )
        proxy.streamHealthChanged(dto)
    }

    private func engineError(_ code: EngineErrorCode, _ description: String) -> NSError {
        NSError(
            domain: EngineErrorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    // MARK: - CacheManager setup

    private static func openCacheManager() -> CacheManager? {
        do {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbDir = appSupport.appendingPathComponent("ButterBar", isDirectory: true)
            try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
            let dbPath = dbDir.appendingPathComponent("engine.sqlite").path
            let db = try EngineDatabase.open(at: dbPath)
            NSLog("[RealEngineBackend] CacheManager opened at %@", dbPath)
            return try CacheManager(db: db)
        } catch {
            NSLog("[RealEngineBackend] CacheManager unavailable (non-fatal): %@", "\(error)")
            return nil
        }
    }
}

// MARK: - MIME type helper

private func mimeType(for path: String) -> String {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "mp4", "m4v": return "video/mp4"
    case "mkv":        return "video/x-matroska"
    case "webm":       return "video/webm"
    case "mov":        return "video/quicktime"
    default:           return "application/octet-stream"
    }
}

private func isPlayable(mimeType: String) -> Bool {
    mimeType.hasPrefix("video/mp4") || mimeType.hasPrefix("video/quicktime")
}
