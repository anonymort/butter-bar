// DefaultPiecePlanner.swift — Deterministic piece scheduling state machine.
//
// RULES (enforced by protocol and internal discipline):
//   - Never read a real clock (all time comes from the `at` parameter).
//   - Never use Foundation.Date, DispatchQueue, randomness, threads, disk, or network.
//   - All torrent state comes from the injected TorrentSessionView.
//
// See spec 04 (PiecePlanner) and spec 02 (StreamHealth).

public final class DefaultPiecePlanner: PiecePlanner {

    // MARK: - State

    /// Byte offset of the end of the most recently accepted GET range.
    /// Updated on every GET (not on cancel, not on actual data delivery).
    /// Nil until the first GET arrives.
    private var lastServedByteEnd: Int64?

    /// Tracks which pieces are in the current active deadline set, keyed by piece index.
    private var currentDeadlinePieces: Set<Int> = []

    /// The pieces currently classified as critical (for cancel policy).
    private var criticalPieces: Set<Int> = []

    /// Outstanding requests: requestID → ByteRange.
    private var outstandingRequests: [String: ByteRange] = [:]

    /// Last emitted StreamHealth (for throttle / change detection).
    private var lastEmittedHealth: StreamHealth?

    /// Timestamp of the last emitHealth emission.
    private var lastEmittedAt: Instant?

    // MARK: - Init

    public init() {}

    // MARK: - PiecePlanner protocol

    public func handle(event: PlayerEvent,
                       at time: Instant,
                       session: TorrentSessionView) -> [PlannerAction] {
        switch event {
        case .head:
            return handleHead()
        case .get(let requestID, let range):
            return handleGet(requestID: requestID, range: range, at: time, session: session)
        case .cancel(let requestID):
            return handleCancel(requestID: requestID, session: session)
        }
    }

    public func tick(at time: Instant,
                     session: TorrentSessionView) -> [PlannerAction] {
        var actions: [PlannerAction] = []

        // Recompute health and potentially emit.
        let health = computeHealth(at: time, session: session)
        if let healthAction = maybeEmitHealth(health, at: time) {
            actions.append(healthAction)
        }

        // Top up readahead if the window has slipped.
        if let lastByte = lastServedByteEnd {
            let topUp = computeReadaheadTopUp(from: lastByte, session: session)
            if !topUp.isEmpty {
                actions.append(.setDeadlines(topUp))
            }
        }

        return actions
    }

    public func currentHealth(at time: Instant,
                              session: TorrentSessionView) -> StreamHealth {
        computeHealth(at: time, session: session)
    }

    // MARK: - Event handlers

    private func handleHead() -> [PlannerAction] {
        // HEAD: no scheduling actions. Just note we've seen a HEAD.
        return []
    }

    private func handleGet(requestID: String,
                           range: ByteRange,
                           at time: Instant,
                           session: TorrentSessionView) -> [PlannerAction] {
        var actions: [PlannerAction] = []

        let isFirstGet = lastServedByteEnd == nil

        if isFirstGet {
            // Initial play policy.
            actions += initialPlay(requestID: requestID, range: range, at: time, session: session)
        } else if let lastByte = lastServedByteEnd {
            let distance = abs(range.start - (lastByte + 1))
            let seekThreshold = session.pieceLength * 4

            if distance <= session.pieceLength * 2 {
                // Mid-play: sequential.
                actions += midPlay(requestID: requestID, range: range, at: time, session: session)
            } else if distance > seekThreshold {
                // Seek: far jump.
                actions += seek(requestID: requestID, range: range, at: time, session: session)
            } else {
                // Between sequential and seek threshold: treat as mid-play.
                actions += midPlay(requestID: requestID, range: range, at: time, session: session)
            }
        }

        // Track the request and update last served byte.
        outstandingRequests[requestID] = range
        lastServedByteEnd = range.end

        return actions
    }

    private func handleCancel(requestID: String,
                               session: TorrentSessionView) -> [PlannerAction] {
        guard let range = outstandingRequests.removeValue(forKey: requestID) else {
            return []
        }

        let cancelledPieces = piecesForRange(range, pieceLength: session.pieceLength)

        // If ANY cancelled piece overlaps the critical window, no-op (spec 04 § Cancel).
        let overlapsActive = !cancelledPieces.isDisjoint(with: criticalPieces)
        if overlapsActive {
            return []
        }

        // Demote non-critical cancelled pieces to background.
        let piecesToDemote = cancelledPieces.filter { currentDeadlinePieces.contains($0) }
        if piecesToDemote.isEmpty {
            return []
        }

        let demotedDeadlines = piecesToDemote.sorted().map { piece in
            PieceDeadline(piece: piece, deadlineMs: 0, priority: .background)
        }
        return [.setDeadlines(demotedDeadlines)]
    }

    // MARK: - Play policies

    private func initialPlay(requestID: String,
                             range: ByteRange,
                             at time: Instant,
                             session: TorrentSessionView) -> [PlannerAction] {
        var actions: [PlannerAction] = []
        let deadlines = computeFullWindow(from: range, session: session)
        let pieces = deadlines.map(\.piece)
        currentDeadlinePieces = Set(pieces)
        criticalPieces = Set(deadlines.filter { $0.priority == .critical }.map(\.piece))

        actions.append(.setDeadlines(deadlines))
        actions.append(.waitForRange(requestID: requestID, maxWaitMs: 1500))

        let health = computeHealth(at: time, session: session)
        if let healthAction = maybeEmitHealth(health, at: time) {
            actions.append(healthAction)
        }

        return actions
    }

    private func midPlay(requestID: String,
                         range: ByteRange,
                         at time: Instant,
                         session: TorrentSessionView) -> [PlannerAction] {
        var actions: [PlannerAction] = []

        // Extend readahead window if it has slipped.
        let topUp = computeReadaheadTopUp(from: range.end, session: session)
        if !topUp.isEmpty {
            let newPieces = topUp.map(\.piece)
            currentDeadlinePieces.formUnion(newPieces)
            actions.append(.setDeadlines(topUp))
        }

        actions.append(.waitForRange(requestID: requestID, maxWaitMs: 800))

        let health = computeHealth(at: time, session: session)
        if let healthAction = maybeEmitHealth(health, at: time) {
            actions.append(healthAction)
        }

        return actions
    }

    private func seek(requestID: String,
                      range: ByteRange,
                      at time: Instant,
                      session: TorrentSessionView) -> [PlannerAction] {
        var actions: [PlannerAction] = []

        let deadlines = computeFullWindow(from: range, session: session)
        let newPieces = deadlines.map(\.piece)
        let newPieceSet = Set(newPieces)
        let newCritical = deadlines.filter { $0.priority == .critical }.map(\.piece).sorted()

        // Clear all existing deadlines except the new critical window.
        // The readahead is immediately set below, so it doesn't need to be retained.
        actions.append(.clearDeadlinesExcept(pieces: newCritical))
        currentDeadlinePieces = newPieceSet
        criticalPieces = Set(newCritical)

        actions.append(.setDeadlines(deadlines))
        actions.append(.waitForRange(requestID: requestID, maxWaitMs: 1200))

        let health = computeHealth(at: time, session: session)
        if let healthAction = maybeEmitHealth(health, at: time) {
            actions.append(healthAction)
        }

        return actions
    }

    // MARK: - Window computation

    /// Computes the full set of piece deadlines for a request window.
    private func computeFullWindow(from range: ByteRange,
                                   session: TorrentSessionView) -> [PieceDeadline] {
        let pieceLength = session.pieceLength
        let firstPiece = Int(range.start / pieceLength)
        let readaheadEndByte = range.end + StreamHealthThresholds.readaheadBytes
        let maxPieceIndex = Int(session.fileByteRange.end / pieceLength)
        let lastPiece = min(Int(readaheadEndByte / pieceLength), maxPieceIndex)

        var deadlines: [PieceDeadline] = []

        // Critical window: first 4 pieces at fixed 0/100/200/300 ms.
        let criticalOffsets = [0, 100, 200, 300]
        for (i, offset) in criticalOffsets.enumerated() {
            let piece = firstPiece + i
            guard piece <= lastPiece else { break }
            deadlines.append(PieceDeadline(piece: piece, deadlineMs: offset, priority: .critical))
        }

        // Readahead pieces.
        let rate = session.downloadRateBytesPerSec()
        let readaheadDeadlines = computeReadaheadDeadlines(
            from: firstPiece + 4,
            to: lastPiece,
            rate: rate,
            pieceLength: pieceLength
        )
        deadlines += readaheadDeadlines

        return deadlines
    }

    /// Computes readahead deadlines for pieces [from...to] using the rate-based or zero-rate spacing.
    private func computeReadaheadDeadlines(from startPiece: Int,
                                           to lastPiece: Int,
                                           rate: Int64,
                                           pieceLength: Int64) -> [PieceDeadline] {
        guard startPiece <= lastPiece else { return [] }

        var deadlines: [PieceDeadline] = []
        let useRateBased = rate >= StreamHealthThresholds.minRateForSpacingBytesPerSec

        if useRateBased {
            let spacingMs = max(
                Int((Double(pieceLength) * 1000.0 / Double(rate)).rounded()),
                StreamHealthThresholds.minDeadlineSpacingMs
            )
            for (i, piece) in (startPiece...lastPiece).enumerated() {
                let deadline = spacingMs * (i + 1)
                deadlines.append(PieceDeadline(piece: piece, deadlineMs: deadline, priority: .readahead))
            }
        } else {
            // Zero-rate fallback tiers:
            // First 4 readahead pieces: 250 ms spacing.
            // Next 4: 500 ms spacing.
            // Rest: 1000 ms spacing.
            var accumulatedMs = 0
            for (i, piece) in (startPiece...lastPiece).enumerated() {
                let spacing: Int
                if i < 4 {
                    spacing = 250
                } else if i < 8 {
                    spacing = 500
                } else {
                    spacing = 1000
                }
                accumulatedMs += spacing
                deadlines.append(PieceDeadline(piece: piece, deadlineMs: accumulatedMs, priority: .readahead))
            }
        }

        return deadlines
    }

    /// Computes new readahead pieces needed to top up the window from a given last-served byte.
    private func computeReadaheadTopUp(from lastByte: Int64,
                                       session: TorrentSessionView) -> [PieceDeadline] {
        let pieceLength = session.pieceLength
        let readaheadEndByte = lastByte + StreamHealthThresholds.readaheadBytes
        let maxPieceIndex = Int(session.fileByteRange.end / pieceLength)
        let targetLastPiece = min(Int(readaheadEndByte / pieceLength), maxPieceIndex)

        // Find the highest piece currently scheduled.
        let currentMax = currentDeadlinePieces.max() ?? -1
        guard targetLastPiece > currentMax else { return [] }

        let rate = session.downloadRateBytesPerSec()
        let useRateBased = rate >= StreamHealthThresholds.minRateForSpacingBytesPerSec

        var deadlines: [PieceDeadline] = []

        if useRateBased {
            // Determine the spacing and the offset for the first NEW piece.
            let spacingMs = max(
                Int((Double(pieceLength) * 1000.0 / Double(rate)).rounded()),
                StreamHealthThresholds.minDeadlineSpacingMs
            )
            // The new pieces are (currentMax+1)...targetLastPiece.
            // Their deadlines continue from where the existing sequence left off.
            // We need to know the position of currentMax+1 within the readahead sequence.
            // The first readahead piece is at index 0 (critical end + 1).
            // We track the "first readahead piece" using criticalPieces.
            let firstReadaheadPiece = (criticalPieces.min() ?? 0) + 4
            let startIndex = currentMax + 1 - firstReadaheadPiece
            for (offset, piece) in ((currentMax + 1)...targetLastPiece).enumerated() {
                let idx = startIndex + offset
                let deadline = spacingMs * (idx + 1)
                deadlines.append(PieceDeadline(piece: piece, deadlineMs: deadline, priority: .readahead))
            }
        } else {
            // Zero-rate fallback: extend within the same tier system.
            let firstReadaheadPiece = (criticalPieces.min() ?? 0) + 4
            var accumulatedMs: Int
            let startIdx = currentMax + 1 - firstReadaheadPiece

            // Compute accumulated ms up to the start index.
            accumulatedMs = 0
            for i in 0..<startIdx {
                let spacing: Int = i < 4 ? 250 : (i < 8 ? 500 : 1000)
                accumulatedMs += spacing
            }

            for (offset, piece) in ((currentMax + 1)...targetLastPiece).enumerated() {
                let i = startIdx + offset
                let spacing: Int = i < 4 ? 250 : (i < 8 ? 500 : 1000)
                accumulatedMs += spacing
                deadlines.append(PieceDeadline(piece: piece, deadlineMs: accumulatedMs, priority: .readahead))
            }
        }

        currentDeadlinePieces.formUnion(deadlines.map(\.piece))
        return deadlines
    }

    // MARK: - StreamHealth

    private func computeHealth(at time: Instant,
                                session: TorrentSessionView) -> StreamHealth {
        let rate = session.downloadRateBytesPerSec()
        let peers = session.peerCount()
        let required: Int64? = nil  // v1: always nil for first 60s

        // secondsBufferedAhead: can't compute without bitrate; use 0.0.
        let buffered: Double = 0.0

        // Outstanding critical pieces not yet downloaded.
        let have = session.havePieces()
        let outstandingCritical = criticalPieces.filter { !have.contains($0) }.count

        let tier = StreamHealthTierComputer.computeTier(
            secondsBufferedAhead: buffered,
            downloadRate: rate,
            requiredBitrate: required,
            outstandingCriticalPieces: outstandingCritical
        )

        return StreamHealth(
            secondsBufferedAhead: buffered,
            downloadRateBytesPerSec: rate,
            requiredBitrateBytesPerSec: required,
            peerCount: peers,
            outstandingCriticalPieces: outstandingCritical,
            recentStallCount: 0,
            tier: tier
        )
    }

    /// Applies emission rules and returns an emitHealth action if one should be produced.
    /// Throttle state advances ONLY when an action is produced.
    private func maybeEmitHealth(_ health: StreamHealth, at time: Instant) -> PlannerAction? {
        let shouldEmit: Bool

        if let previous = lastEmittedHealth {
            if health.tier != previous.tier {
                // Tier transition — emit immediately regardless of throttle.
                shouldEmit = true
            } else if let lastAt = lastEmittedAt,
                      (time - lastAt) >= StreamHealthThresholds.emitThrottleMs,
                      health != previous {
                // Throttled field change.
                shouldEmit = true
            } else {
                shouldEmit = false
            }
        } else {
            // First emission.
            shouldEmit = true
        }

        if shouldEmit {
            lastEmittedHealth = health
            lastEmittedAt = time
            return .emitHealth(health)
        }
        return nil
    }

    // MARK: - Helpers

    private func piecesForRange(_ range: ByteRange, pieceLength: Int64) -> Set<Int> {
        let first = Int(range.start / pieceLength)
        let last = Int(range.end / pieceLength)
        return Set(first...last)
    }
}

// MARK: - StreamHealthTierComputer

/// Computes StreamHealth.Tier from the raw fields. Pure function, no state.
/// Precedence: starving > marginal > healthy. See spec 02.
public enum StreamHealthTierComputer {
    public static func computeTier(secondsBufferedAhead: Double,
                                   downloadRate: Int64,
                                   requiredBitrate: Int64?,
                                   outstandingCriticalPieces: Int) -> StreamHealth.Tier {
        // Starving wins.
        if isStarving(buffered: secondsBufferedAhead,
                      rate: downloadRate,
                      required: requiredBitrate,
                      outstanding: outstandingCriticalPieces) {
            return .starving
        }

        // Marginal next.
        if isMarginal(buffered: secondsBufferedAhead,
                      rate: downloadRate,
                      required: requiredBitrate) {
            return .marginal
        }

        return .healthy
    }

    // starving when:
    //   buffer < 10s, OR
    //   required != nil AND rate < required, OR
    //   outstandingCritical > 0
    private static func isStarving(buffered: Double,
                                    rate: Int64,
                                    required: Int64?,
                                    outstanding: Int) -> Bool {
        if buffered < StreamHealthThresholds.starvingBufferSeconds { return true }
        if let req = required, rate < req { return true }
        if outstanding > 0 { return true }
        return false
    }

    // marginal when not starving AND:
    //   10 <= buffer < 30, OR
    //   required != nil AND rate < 1.5*required AND rate >= required
    private static func isMarginal(buffered: Double,
                                    rate: Int64,
                                    required: Int64?) -> Bool {
        if buffered >= StreamHealthThresholds.marginalBufferLow &&
           buffered < StreamHealthThresholds.marginalBufferHigh {
            return true
        }
        if let req = required {
            let threshold = Double(req) * StreamHealthThresholds.marginalRateMultiplier
            if Double(rate) < threshold && rate >= req { return true }
        }
        return false
    }
}
