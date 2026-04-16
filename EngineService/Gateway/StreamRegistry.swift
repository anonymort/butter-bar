import Foundation
import PlannerCore

/// Registry of active playback streams.
///
/// Creates, stores, and routes HTTP requests to `PlaybackSession` instances.
/// Path contract: `/stream/<streamID>` — the stream ID is the last path component.
///
/// All methods must be called from a single queue (the gateway queue). The registry
/// itself does no internal locking; serialisation is guaranteed by the caller.
final class StreamRegistry {

    /// Optional CacheManager for resume-offset persistence. When nil, no
    /// history is recorded and no resume position is offered.
    private let cacheManager: CacheManager?

    private var sessions: [String: PlaybackSession] = [:]
    /// Maps streamID → torrentID. Parallel to `sessions`; kept in sync by createStream/closeStream.
    private var streamTorrentIDs: [String: String] = [:]

    init(cacheManager: CacheManager? = nil) {
        self.cacheManager = cacheManager
    }

    // MARK: - Stream lifecycle

    /// Create a new stream, start its tick timer, and register it.
    ///
    /// - Parameters:
    ///   - streamID: Stable identifier used to route requests. Must be unique.
    ///   - contentType: MIME type reported in HTTP responses (e.g. `"video/mp4"`).
    ///   - contentLength: Total file length in bytes.
    ///   - bridge: Live TorrentBridge for the engine process.
    ///   - torrentID: Identifier returned by `TorrentBridge.addMagnet` / `addTorrentFileAtPath`.
    ///   - fileIndex: Zero-based index of the selected file within the torrent.
    ///   - onHealthUpdate: Called whenever the planner emits a `StreamHealth` update.
    /// - Returns: The newly created `PlaybackSession`.
    /// - Throws: `ByteReader.ReadError.metadataNotReady` if torrent metadata is
    ///   unavailable at the time of registration.
    @discardableResult
    func createStream(streamID: String,
                      contentType: String,
                      contentLength: Int64,
                      bridge: TorrentBridge,
                      torrentID: String,
                      fileIndex: Int,
                      onHealthUpdate: ((StreamHealth) -> Void)? = nil) throws -> PlaybackSession {
        let realSession = try RealTorrentSession(bridge: bridge, torrentID: torrentID, fileIndex: fileIndex)
        let planner     = DefaultPiecePlanner()

        // Build a ResumeTracker if we have a CacheManager.
        let tracker: ResumeTracker? = cacheManager.map {
            ResumeTracker(cacheManager: $0,
                          torrentId: torrentID,
                          fileIndex: fileIndex,
                          fileSize: contentLength)
        }

        // Log any existing resume offset for this file (app reads it at open time via XPC).
        if let cm = cacheManager {
            do {
                if let record = try cm.fetchHistory(torrentId: torrentID, fileIndex: fileIndex),
                   record.resumeByteOffset > 0 {
                    NSLog("[StreamRegistry] resume offset for stream %@: %lld", streamID, record.resumeByteOffset)
                }
            } catch {
                NSLog("[StreamRegistry] fetchHistory error: %@", "\(error)")
            }
        }

        let session = try PlaybackSession(
            streamID: streamID,
            contentType: contentType,
            contentLength: contentLength,
            planner: planner,
            torrentSession: realSession,
            bridge: bridge,
            torrentID: torrentID,
            fileIndex: fileIndex,
            resumeTracker: tracker
        )
        session.onHealthUpdate = onHealthUpdate
        session.start()
        sessions[streamID] = session
        streamTorrentIDs[streamID] = torrentID
        NSLog("[StreamRegistry] created stream %@", streamID)
        return session
    }

    /// Stop and remove the stream identified by `streamID`. No-op if unknown.
    func closeStream(_ streamID: String) {
        if let session = sessions.removeValue(forKey: streamID) {
            session.stop()
            NSLog("[StreamRegistry] closed stream %@", streamID)
        }
        streamTorrentIDs.removeValue(forKey: streamID)
    }

    /// Remove all streams, stopping each one.
    func closeAll() {
        for (id, session) in sessions {
            session.stop()
            NSLog("[StreamRegistry] closed stream %@ (closeAll)", id)
        }
        sessions.removeAll()
        streamTorrentIDs.removeAll()
    }

    // MARK: - Active stream query

    /// Returns true if any session is currently registered for the given torrentID.
    /// Used by the eviction tick to skip torrents with active streams.
    func hasActiveStream(torrentID: String) -> Bool {
        streamTorrentIDs.values.contains(torrentID)
    }

    // MARK: - Request routing

    /// Route an HTTP request to the matching session based on the path.
    ///
    /// Returns `nil` if the path does not match `/stream/<streamID>` or no
    /// session is registered for the extracted stream ID. The caller should
    /// return a 404 response in that case.
    func handleRequest(_ request: HTTPRangeRequest) -> HTTPRangeResponse? {
        guard let streamID = extractStreamID(from: request.path),
              let session  = sessions[streamID] else {
            NSLog("[StreamRegistry] no session for path %@", request.path)
            return nil
        }
        return session.handleRequest(request)
    }

    // MARK: - Private

    /// Extract the stream ID from a path of the form `/stream/<streamID>`.
    /// Returns `nil` for any other path shape.
    private func extractStreamID(from path: String) -> String? {
        // Split on "/" — e.g. "/stream/ABC-123" → ["", "stream", "ABC-123"]
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2,
              components[0] == "stream" else {
            return nil
        }
        return String(components[1])
    }
}
