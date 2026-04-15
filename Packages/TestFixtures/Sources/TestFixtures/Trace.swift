// Trace.swift — JSON-decodable trace format for PiecePlanner replay tests.
// Format spec: 04-piece-planner.md § Trace format.

import Foundation

// MARK: - Top-level

/// The full input trace for a single planner replay test.
public struct Trace: Codable, Equatable, Sendable {
    /// Identifier that pairs this trace with its expected-actions file.
    public var assetID: String
    /// Human-readable description of what the trace exercises.
    public var description: String
    /// Total byte length of the file being streamed.
    public var contentLength: Int64
    /// Torrent piece size in bytes.
    public var pieceLength: Int64
    /// Byte range of the selected file within the sparse file.
    public var fileByteRange: ByteRangeEntry
    /// Ordered sequence of HTTP-gateway events.
    public var events: [TraceEvent]
    /// Scheduled availability of pieces over time.
    public var availabilitySchedule: [AvailabilityEntry]
    /// Scheduled download rate over time.
    public var downloadRateSchedule: [DownloadRateEntry]
    /// Scheduled peer count over time.
    public var peerCountSchedule: [PeerCountEntry]

    public init(
        assetID: String,
        description: String,
        contentLength: Int64,
        pieceLength: Int64,
        fileByteRange: ByteRangeEntry,
        events: [TraceEvent],
        availabilitySchedule: [AvailabilityEntry],
        downloadRateSchedule: [DownloadRateEntry],
        peerCountSchedule: [PeerCountEntry]
    ) {
        self.assetID = assetID
        self.description = description
        self.contentLength = contentLength
        self.pieceLength = pieceLength
        self.fileByteRange = fileByteRange
        self.events = events
        self.availabilitySchedule = availabilitySchedule
        self.downloadRateSchedule = downloadRateSchedule
        self.peerCountSchedule = peerCountSchedule
    }

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case description
        case contentLength = "content_length"
        case pieceLength = "piece_length"
        case fileByteRange = "file_byte_range"
        case events
        case availabilitySchedule = "availability_schedule"
        case downloadRateSchedule = "download_rate_schedule"
        case peerCountSchedule = "peer_count_schedule"
    }
}

// MARK: - ByteRangeEntry

/// An inclusive byte range [start, end].
public struct ByteRangeEntry: Codable, Equatable, Sendable {
    public var start: Int64
    public var end: Int64

    public init(start: Int64, end: Int64) {
        self.start = start
        self.end = end
    }
}

// MARK: - TraceEvent

/// A single event from the HTTP gateway, with a timestamp.
public struct TraceEvent: Equatable, Sendable {
    public var tMs: Int
    public var kind: TraceEventKind

    public init(tMs: Int, kind: TraceEventKind) {
        self.tMs = tMs
        self.kind = kind
    }
}

/// The discriminated event types the gateway can emit.
public enum TraceEventKind: Equatable, Sendable {
    /// AVPlayer issued a HEAD request.
    case head
    /// AVPlayer issued a GET with a Range header.
    case get(requestID: String, rangeStart: Int64, rangeEnd: Int64)
    /// Client closed the connection before the response completed.
    case cancel(requestID: String)
}

// Custom Codable for TraceEvent — the `kind` field is a discriminator.
extension TraceEvent: Codable {
    enum CodingKeys: String, CodingKey {
        case tMs = "t_ms"
        case kind
        case requestID = "request_id"
        case rangeStart = "range_start"
        case rangeEnd = "range_end"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tMs = try container.decode(Int.self, forKey: .tMs)
        let kindString = try container.decode(String.self, forKey: .kind)
        switch kindString {
        case "head":
            kind = .head
        case "get":
            let requestID = try container.decode(String.self, forKey: .requestID)
            let rangeStart = try container.decode(Int64.self, forKey: .rangeStart)
            let rangeEnd = try container.decode(Int64.self, forKey: .rangeEnd)
            kind = .get(requestID: requestID, rangeStart: rangeStart, rangeEnd: rangeEnd)
        case "cancel":
            let requestID = try container.decode(String.self, forKey: .requestID)
            kind = .cancel(requestID: requestID)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown trace event kind '\(kindString)'. Expected one of: head, get, cancel."
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tMs, forKey: .tMs)
        switch kind {
        case .head:
            try container.encode("head", forKey: .kind)
        case .get(let requestID, let rangeStart, let rangeEnd):
            try container.encode("get", forKey: .kind)
            try container.encode(requestID, forKey: .requestID)
            try container.encode(rangeStart, forKey: .rangeStart)
            try container.encode(rangeEnd, forKey: .rangeEnd)
        case .cancel(let requestID):
            try container.encode("cancel", forKey: .kind)
            try container.encode(requestID, forKey: .requestID)
        }
    }
}

// MARK: - Schedule entry types

/// One snapshot in the piece-availability schedule.
public struct AvailabilityEntry: Codable, Equatable, Sendable {
    public var tMs: Int
    /// Piece indices available at this point in time.
    public var havePieces: [Int]

    public init(tMs: Int, havePieces: [Int]) {
        self.tMs = tMs
        self.havePieces = havePieces
    }

    enum CodingKeys: String, CodingKey {
        case tMs = "t_ms"
        case havePieces = "have_pieces"
    }
}

/// One snapshot in the download-rate schedule.
public struct DownloadRateEntry: Codable, Equatable, Sendable {
    public var tMs: Int
    public var bytesPerSec: Int64

    public init(tMs: Int, bytesPerSec: Int64) {
        self.tMs = tMs
        self.bytesPerSec = bytesPerSec
    }

    enum CodingKeys: String, CodingKey {
        case tMs = "t_ms"
        case bytesPerSec = "bytes_per_sec"
    }
}

/// One snapshot in the peer-count schedule.
public struct PeerCountEntry: Codable, Equatable, Sendable {
    public var tMs: Int
    public var count: Int

    public init(tMs: Int, count: Int) {
        self.tMs = tMs
        self.count = count
    }

    enum CodingKeys: String, CodingKey {
        case tMs = "t_ms"
        case count
    }
}
