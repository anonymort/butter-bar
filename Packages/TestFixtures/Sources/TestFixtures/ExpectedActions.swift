// ExpectedActions.swift — JSON-decodable expected-actions format for planner replay assertions.
// Format spec: 04-piece-planner.md § Expected action format.

import Foundation

// MARK: - Top-level

/// The expected output of the planner for a given trace.
public struct ExpectedActions: Codable, Equatable, Sendable {
    /// Must match the `asset_id` of the paired trace file.
    public var traceID: String
    /// Ordered sequence of actions the planner must produce.
    public var actions: [ExpectedAction]

    public init(traceID: String, actions: [ExpectedAction]) {
        self.traceID = traceID
        self.actions = actions
    }

    enum CodingKeys: String, CodingKey {
        case traceID = "trace_id"
        case actions
    }
}

// MARK: - ExpectedAction

/// A single expected planner output, with a timestamp.
public struct ExpectedAction: Equatable, Sendable {
    public var tMs: Int
    public var kind: ExpectedActionKind

    public init(tMs: Int, kind: ExpectedActionKind) {
        self.tMs = tMs
        self.kind = kind
    }
}

/// The discriminated set of actions the planner can emit.
public enum ExpectedActionKind: Equatable, Sendable {
    /// Set deadlines on a list of pieces.
    case setDeadlines(pieces: [ExpectedPieceDeadline])
    /// Clear all deadlines except the listed piece indices.
    case clearDeadlinesExcept(pieces: [Int])
    /// Tell the gateway to wait for a byte range to become available.
    case waitForRange(requestID: String, maxWaitMs: Int)
    /// Tell the gateway to fail a range request.
    case failRange(requestID: String, reason: FailReason)
    /// Emit a stream health snapshot.
    case emitHealth(health: ExpectedStreamHealth)
}

// MARK: - ExpectedPieceDeadline

/// A piece index with an associated deadline and scheduling priority.
public struct ExpectedPieceDeadline: Codable, Equatable, Sendable {
    public var piece: Int
    public var deadlineMs: Int
    public var priority: PiecePriority

    public init(piece: Int, deadlineMs: Int, priority: PiecePriority) {
        self.piece = piece
        self.deadlineMs = deadlineMs
        self.priority = priority
    }

    enum CodingKeys: String, CodingKey {
        case piece
        case deadlineMs = "deadline_ms"
        case priority
    }
}

/// Scheduling priority for a piece deadline.
public enum PiecePriority: String, Codable, Equatable, Sendable {
    /// Pieces the playhead is currently reading.
    case critical
    /// Pieces buffered ahead of the playhead.
    case readahead
    /// Pieces outside the active read window.
    case background
}

// MARK: - FailReason

/// Why the gateway must fail a range request.
public enum FailReason: String, Codable, Equatable, Sendable {
    case rangeOutOfBounds = "range_out_of_bounds"
    case waitTimedOut = "wait_timed_out"
    case streamClosed = "stream_closed"
}

// MARK: - ExpectedStreamHealth

/// The expected `StreamHealth` snapshot inside an `emitHealth` action.
/// Mirrors `StreamHealth` from spec 02; kept separate so TestFixtures has no
/// dependency on PlannerCore.
public struct ExpectedStreamHealth: Codable, Equatable, Sendable {
    public var secondsBufferedAhead: Double
    public var downloadRateBytesPerSec: Int64
    /// Nil until the planner has observed ≥ 60 s of continuous playback.
    public var requiredBitrateBytesPerSec: Int64?
    public var peerCount: Int
    public var outstandingCriticalPieces: Int
    public var recentStallCount: Int
    public var tier: HealthTier

    public init(
        secondsBufferedAhead: Double,
        downloadRateBytesPerSec: Int64,
        requiredBitrateBytesPerSec: Int64?,
        peerCount: Int,
        outstandingCriticalPieces: Int,
        recentStallCount: Int,
        tier: HealthTier
    ) {
        self.secondsBufferedAhead = secondsBufferedAhead
        self.downloadRateBytesPerSec = downloadRateBytesPerSec
        self.requiredBitrateBytesPerSec = requiredBitrateBytesPerSec
        self.peerCount = peerCount
        self.outstandingCriticalPieces = outstandingCriticalPieces
        self.recentStallCount = recentStallCount
        self.tier = tier
    }

    enum CodingKeys: String, CodingKey {
        case secondsBufferedAhead = "seconds_buffered_ahead"
        case downloadRateBytesPerSec = "download_rate_bytes_per_sec"
        case requiredBitrateBytesPerSec = "required_bitrate_bytes_per_sec"
        case peerCount = "peer_count"
        case outstandingCriticalPieces = "outstanding_critical_pieces"
        case recentStallCount = "recent_stall_count"
        case tier
    }
}

/// Stream health tier, mirroring `StreamHealth.Tier` from spec 02.
public enum HealthTier: String, Codable, Equatable, Sendable {
    case healthy
    case marginal
    case starving
}

// MARK: - Custom Codable for ExpectedAction

extension ExpectedAction: Codable {
    enum CodingKeys: String, CodingKey {
        case tMs = "t_ms"
        case kind
        // set_deadlines
        case pieces
        // clear_deadlines_except: reuses `pieces`
        // wait_for_range
        case requestID = "request_id"
        case maxWaitMs = "max_wait_ms"
        // fail_range: reuses `requestID`
        case reason
        // emit_health fields — decoded as a nested struct
        case secondsBufferedAhead = "seconds_buffered_ahead"
        case downloadRateBytesPerSec = "download_rate_bytes_per_sec"
        case requiredBitrateBytesPerSec = "required_bitrate_bytes_per_sec"
        case peerCount = "peer_count"
        case outstandingCriticalPieces = "outstanding_critical_pieces"
        case recentStallCount = "recent_stall_count"
        case tier
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tMs = try container.decode(Int.self, forKey: .tMs)
        let kindString = try container.decode(String.self, forKey: .kind)
        switch kindString {
        case "set_deadlines":
            let pieces = try container.decode([ExpectedPieceDeadline].self, forKey: .pieces)
            kind = .setDeadlines(pieces: pieces)

        case "clear_deadlines_except":
            let pieces = try container.decode([Int].self, forKey: .pieces)
            kind = .clearDeadlinesExcept(pieces: pieces)

        case "wait_for_range":
            let requestID = try container.decode(String.self, forKey: .requestID)
            let maxWaitMs = try container.decode(Int.self, forKey: .maxWaitMs)
            kind = .waitForRange(requestID: requestID, maxWaitMs: maxWaitMs)

        case "fail_range":
            let requestID = try container.decode(String.self, forKey: .requestID)
            let reason = try container.decode(FailReason.self, forKey: .reason)
            kind = .failRange(requestID: requestID, reason: reason)

        case "emit_health":
            let secondsBufferedAhead = try container.decode(Double.self, forKey: .secondsBufferedAhead)
            let downloadRateBytesPerSec = try container.decode(Int64.self, forKey: .downloadRateBytesPerSec)
            let requiredBitrateBytesPerSec = try container.decodeIfPresent(Int64.self, forKey: .requiredBitrateBytesPerSec)
            let peerCount = try container.decode(Int.self, forKey: .peerCount)
            let outstandingCriticalPieces = try container.decode(Int.self, forKey: .outstandingCriticalPieces)
            let recentStallCount = try container.decode(Int.self, forKey: .recentStallCount)
            let tier = try container.decode(HealthTier.self, forKey: .tier)
            kind = .emitHealth(health: ExpectedStreamHealth(
                secondsBufferedAhead: secondsBufferedAhead,
                downloadRateBytesPerSec: downloadRateBytesPerSec,
                requiredBitrateBytesPerSec: requiredBitrateBytesPerSec,
                peerCount: peerCount,
                outstandingCriticalPieces: outstandingCriticalPieces,
                recentStallCount: recentStallCount,
                tier: tier
            ))

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown expected action kind '\(kindString)'. Expected one of: set_deadlines, clear_deadlines_except, wait_for_range, fail_range, emit_health."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tMs, forKey: .tMs)
        switch kind {
        case .setDeadlines(let pieces):
            try container.encode("set_deadlines", forKey: .kind)
            try container.encode(pieces, forKey: .pieces)

        case .clearDeadlinesExcept(let pieces):
            try container.encode("clear_deadlines_except", forKey: .kind)
            try container.encode(pieces, forKey: .pieces)

        case .waitForRange(let requestID, let maxWaitMs):
            try container.encode("wait_for_range", forKey: .kind)
            try container.encode(requestID, forKey: .requestID)
            try container.encode(maxWaitMs, forKey: .maxWaitMs)

        case .failRange(let requestID, let reason):
            try container.encode("fail_range", forKey: .kind)
            try container.encode(requestID, forKey: .requestID)
            try container.encode(reason, forKey: .reason)

        case .emitHealth(let health):
            try container.encode("emit_health", forKey: .kind)
            try container.encode(health.secondsBufferedAhead, forKey: .secondsBufferedAhead)
            try container.encode(health.downloadRateBytesPerSec, forKey: .downloadRateBytesPerSec)
            try container.encodeIfPresent(health.requiredBitrateBytesPerSec, forKey: .requiredBitrateBytesPerSec)
            try container.encode(health.peerCount, forKey: .peerCount)
            try container.encode(health.outstandingCriticalPieces, forKey: .outstandingCriticalPieces)
            try container.encode(health.recentStallCount, forKey: .recentStallCount)
            try container.encode(health.tier, forKey: .tier)
        }
    }
}
