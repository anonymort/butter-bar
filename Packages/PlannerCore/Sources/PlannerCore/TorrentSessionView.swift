/// Read-only view of torrent state injected into the planner.
/// In production this wraps TorrentBridge. In tests it's a fake driven by
/// the availability schedule from the trace fixture.
public protocol TorrentSessionView {
    var pieceLength: Int64 { get }
    var fileByteRange: ByteRange { get }          // within the sparse file for the selected file
    func havePieces() -> BitSet
    func downloadRateBytesPerSec() -> Int64
    func peerCount() -> Int
}
