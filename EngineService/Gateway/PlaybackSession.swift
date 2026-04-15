import Foundation
import PlannerCore

/// Coordinates a single playback stream: translates HTTP requests into planner
/// events, executes planner actions against the bridge, and serves bytes.
///
/// One PlaybackSession per active stream. The session owns the planner and the
/// ByteReader for its (torrentID, fileIndex) pair. Tick-based planner maintenance
/// runs on an internal serial queue — all other entry points are called from the
/// gateway queue and are therefore serialised by the GatewayListener.
// @unchecked Sendable: all mutation is serialised — tickQueue for the timer path,
// gateway queue for handleRequest. The two paths never overlap because the timer
// only touches the planner and bridge, which are themselves thread-safe.
final class PlaybackSession: @unchecked Sendable {

    let streamID: String
    let contentType: String
    let contentLength: Int64

    private let planner: any PiecePlanner
    private let torrentSession: TorrentSessionView
    private let bridge: TorrentBridge
    private let torrentID: String
    private let byteReader: ByteReader

    /// Called when the planner emits a StreamHealth update. Invoked on tickQueue
    /// or on the gateway queue depending on the code path that produced the action.
    var onHealthUpdate: ((StreamHealth) -> Void)?

    private var tickTimer: DispatchSourceTimer?
    private let tickQueue = DispatchQueue(label: "com.butterbar.engine.session.tick")

    /// - Throws: `ByteReader.ReadError.metadataNotReady` if torrent metadata is
    ///   not yet available (piece length or file byte range unavailable).
    init(streamID: String,
         contentType: String,
         contentLength: Int64,
         planner: any PiecePlanner,
         torrentSession: TorrentSessionView,
         bridge: TorrentBridge,
         torrentID: String,
         fileIndex: Int) throws {
        self.streamID = streamID
        self.contentType = contentType
        self.contentLength = contentLength
        self.planner = planner
        self.torrentSession = torrentSession
        self.bridge = bridge
        self.torrentID = torrentID
        self.byteReader = try ByteReader(bridge: bridge, torrentID: torrentID, fileIndex: fileIndex)
    }

    /// Start the 500 ms tick timer. Call once after init before routing any requests.
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: tickQueue)
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.handleTick() }
        timer.resume()
        tickTimer = timer
    }

    /// Cancel the tick timer and release resources. Safe to call multiple times.
    func stop() {
        tickTimer?.cancel()
        tickTimer = nil
    }

    /// Synchronously handle an HTTP request for this stream and return the response.
    /// Called on the gateway dispatch queue.
    func handleRequest(_ request: HTTPRangeRequest) -> HTTPRangeResponse {
        let now = currentTimeMs()

        switch request.method {
        case .head:
            let actions = planner.handle(event: .head, at: now, session: torrentSession)
            processActions(actions)
            return HTTPRangeResponse.headResponse(contentType: contentType, contentLength: contentLength)

        case .get:
            let requestID = UUID().uuidString
            let rangeStart = request.rangeStart ?? 0
            let rangeEnd   = request.rangeEnd   ?? (contentLength - 1)

            guard rangeStart >= 0, rangeStart < contentLength else {
                return HTTPRangeResponse.rangeNotSatisfiable(totalLength: contentLength)
            }
            let clampedEnd = min(rangeEnd, contentLength - 1)

            let byteRange = ByteRange(start: rangeStart, end: clampedEnd)
            let event     = PlayerEvent.get(requestID: requestID, range: byteRange)
            let actions   = planner.handle(event: event, at: now, session: torrentSession)

            return processActionsAndServe(actions,
                                          requestID: requestID,
                                          rangeStart: rangeStart,
                                          rangeEnd: clampedEnd)
        }
    }

    // MARK: - Action processing

    /// Process actions that accompany a GET, block for bytes, and return the response.
    private func processActionsAndServe(_ actions: [PlannerAction],
                                        requestID: String,
                                        rangeStart: Int64,
                                        rangeEnd: Int64) -> HTTPRangeResponse {
        var maxWaitMs: Int = 0
        var failedReason: FailReason?

        for action in actions {
            switch action {
            case .setDeadlines(let deadlines):
                executeSetDeadlines(deadlines)
            case .clearDeadlinesExcept(let pieces):
                executeClearDeadlines(except: pieces)
            case .waitForRange(let rid, let wait) where rid == requestID:
                maxWaitMs = wait
            case .failRange(let rid, let reason) where rid == requestID:
                failedReason = reason
            case .emitHealth(let health):
                onHealthUpdate?(health)
            default:
                break
            }
        }

        if let reason = failedReason {
            return responseForFailReason(reason)
        }

        let length = rangeEnd - rangeStart + 1
        switch waitAndRead(offset: rangeStart, length: length, maxWaitMs: maxWaitMs) {
        case .success(let result):
            let actualEnd = rangeStart + result.bytesRead - 1
            return HTTPRangeResponse.partialContent(
                contentType: contentType,
                rangeStart: rangeStart,
                rangeEnd: actualEnd,
                totalLength: contentLength,
                body: result.data
            )
        case .failure:
            return HTTPRangeResponse.rangeNotSatisfiable(totalLength: contentLength)
        }
    }

    /// Process non-serving actions (used for HEAD and tick).
    private func processActions(_ actions: [PlannerAction]) {
        for action in actions {
            switch action {
            case .setDeadlines(let deadlines):
                executeSetDeadlines(deadlines)
            case .clearDeadlinesExcept(let pieces):
                executeClearDeadlines(except: pieces)
            case .emitHealth(let health):
                onHealthUpdate?(health)
            case .waitForRange, .failRange:
                // Should not appear outside a GET context; ignore defensively.
                break
            }
        }
    }

    // MARK: - Byte serving

    /// Poll ByteReader until bytes are available or the deadline is reached.
    /// Blocks the calling thread — acceptable for v1's one-connection-at-a-time model.
    private func waitAndRead(offset: Int64,
                             length: Int64,
                             maxWaitMs: Int) -> Result<ByteReader.ReadResult, Error> {
        let pollIntervalUs: UInt32 = 50_000   // 50 ms
        let deadline = DispatchWallTime.now() + .milliseconds(maxWaitMs)

        while DispatchWallTime.now() < deadline {
            switch attemptRead(offset: offset, length: length) {
            case .success(let r): return .success(r)
            case .failure(ByteReader.ReadError.bytesNotAvailable):
                usleep(pollIntervalUs)
            case .failure(let e):
                return .failure(e)
            }
        }

        // Final attempt after timeout expires.
        return attemptRead(offset: offset, length: length)
    }

    private func attemptRead(offset: Int64, length: Int64) -> Result<ByteReader.ReadResult, Error> {
        do {
            return .success(try byteReader.read(offset: offset, length: length))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Bridge calls

    private func executeSetDeadlines(_ deadlines: [PieceDeadline]) {
        for d in deadlines {
            try? bridge.setPieceDeadline(torrentID,
                                         piece: Int32(d.piece),
                                         deadlineMs: Int32(d.deadlineMs))
        }
    }

    private func executeClearDeadlines(except pieces: [Int]) {
        let nsPieces = pieces.map { NSNumber(value: $0) }
        try? bridge.clearPieceDeadlines(torrentID, exceptPieces: nsPieces)
    }

    // MARK: - Tick

    private func handleTick() {
        let now     = currentTimeMs()
        let actions = planner.tick(at: now, session: torrentSession)
        processActions(actions)
    }

    // MARK: - Helpers

    private func responseForFailReason(_ reason: FailReason) -> HTTPRangeResponse {
        switch reason {
        case .rangeOutOfBounds:
            return HTTPRangeResponse.rangeNotSatisfiable(totalLength: contentLength)
        case .waitTimedOut, .streamClosed:
            // 404 is a reasonable proxy for "this stream is gone" — the client will
            // retry or surface an error, which is preferable to stalling indefinitely.
            return HTTPRangeResponse.notFound()
        }
    }

    private func currentTimeMs() -> Instant {
        Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }
}
