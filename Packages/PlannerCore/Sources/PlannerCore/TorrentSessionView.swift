// TorrentSessionView.swift — Read-only view the planner uses to observe torrent state.
// In production, wraps TorrentBridge. In tests, driven by FakeTorrentSession.
//
// NOTE: The spec (04-piece-planner.md) defines havePieces() -> BitSet.
// BitSet is a custom type that will be introduced in T-PLANNER-TYPES. Until that task
// merges, IndexSet is used here as a stand-in — it has identical semantics for
// this use case (ordered set of non-negative integers). T-PLANNER-TYPES will
// resolve the type mismatch; this file should be replaced by T-PLANNER-TYPES output.

import Foundation

public struct ByteRange: Hashable, Sendable {
    public let start: Int64 // inclusive
    public let end: Int64   // inclusive

    public init(start: Int64, end: Int64) {
        self.start = start
        self.end = end
    }
}

public protocol TorrentSessionView {
    var pieceLength: Int64 { get }
    var fileByteRange: ByteRange { get }
    func havePieces() -> IndexSet   // BitSet in final form (T-PLANNER-TYPES)
    func downloadRateBytesPerSec() -> Int64
    func peerCount() -> Int
}
