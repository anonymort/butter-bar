import Foundation

@objc(StreamHealthDTO)
public final class StreamHealthDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32
    public let streamID: NSString
    public let secondsBufferedAhead: Double
    public let downloadRateBytesPerSec: Int64
    /// nil until bitrate is known (typically first ~60 s of playback).
    public let requiredBitrateBytesPerSec: NSNumber?
    public let peerCount: Int32
    public let outstandingCriticalPieces: Int32
    public let recentStallCount: Int32
    /// One of: "healthy" | "marginal" | "starving"
    public let tier: NSString

    public init(
        streamID: NSString,
        secondsBufferedAhead: Double,
        downloadRateBytesPerSec: Int64,
        requiredBitrateBytesPerSec: NSNumber?,
        peerCount: Int32,
        outstandingCriticalPieces: Int32,
        recentStallCount: Int32,
        tier: NSString
    ) {
        self.schemaVersion = 1
        self.streamID = streamID
        self.secondsBufferedAhead = secondsBufferedAhead
        self.downloadRateBytesPerSec = downloadRateBytesPerSec
        self.requiredBitrateBytesPerSec = requiredBitrateBytesPerSec
        self.peerCount = peerCount
        self.outstandingCriticalPieces = outstandingCriticalPieces
        self.recentStallCount = recentStallCount
        self.tier = tier
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(streamID, forKey: "streamID")
        coder.encode(secondsBufferedAhead, forKey: "secondsBufferedAhead")
        coder.encode(downloadRateBytesPerSec, forKey: "downloadRateBytesPerSec")
        coder.encode(requiredBitrateBytesPerSec, forKey: "requiredBitrateBytesPerSec")
        coder.encode(peerCount, forKey: "peerCount")
        coder.encode(outstandingCriticalPieces, forKey: "outstandingCriticalPieces")
        coder.encode(recentStallCount, forKey: "recentStallCount")
        coder.encode(tier, forKey: "tier")
    }

    public required init?(coder: NSCoder) {
        schemaVersion = coder.decodeInt32(forKey: "schemaVersion")
        guard let streamID = coder.decodeObject(of: NSString.self, forKey: "streamID") else { return nil }
        secondsBufferedAhead = coder.decodeDouble(forKey: "secondsBufferedAhead")
        downloadRateBytesPerSec = coder.decodeInt64(forKey: "downloadRateBytesPerSec")
        requiredBitrateBytesPerSec = coder.decodeObject(of: NSNumber.self, forKey: "requiredBitrateBytesPerSec")
        peerCount = coder.decodeInt32(forKey: "peerCount")
        outstandingCriticalPieces = coder.decodeInt32(forKey: "outstandingCriticalPieces")
        recentStallCount = coder.decodeInt32(forKey: "recentStallCount")
        guard let tier = coder.decodeObject(of: NSString.self, forKey: "tier") else { return nil }
        self.streamID = streamID
        self.tier = tier
    }
}
