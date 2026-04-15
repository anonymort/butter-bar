/// The single operational metric shared between the planner and the UI.
/// The UI renders tiers but must not recompute them. See spec 02.
public struct StreamHealth: Sendable, Hashable, Codable {
    public let secondsBufferedAhead: Double
    public let downloadRateBytesPerSec: Int64
    public let requiredBitrateBytesPerSec: Int64?   // nil until inferred or probed
    public let peerCount: Int
    public let outstandingCriticalPieces: Int
    public let recentStallCount: Int
    public let tier: Tier

    public enum Tier: String, Sendable, Codable {
        case healthy
        case marginal
        case starving
    }

    public init(
        secondsBufferedAhead: Double,
        downloadRateBytesPerSec: Int64,
        requiredBitrateBytesPerSec: Int64?,
        peerCount: Int,
        outstandingCriticalPieces: Int,
        recentStallCount: Int,
        tier: Tier
    ) {
        self.secondsBufferedAhead = secondsBufferedAhead
        self.downloadRateBytesPerSec = downloadRateBytesPerSec
        self.requiredBitrateBytesPerSec = requiredBitrateBytesPerSec
        self.peerCount = peerCount
        self.outstandingCriticalPieces = outstandingCriticalPieces
        self.recentStallCount = recentStallCount
        self.tier = tier
    }
}
