import Foundation

@objc(TorrentSummaryDTO)
public final class TorrentSummaryDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32
    public let torrentID: NSString
    public let name: NSString
    public let totalBytes: Int64
    /// Fixed-point progress in [0, 65536].
    public let progressQ16: Int32
    /// One of: "queued" | "checking" | "downloading" | "seeding" | "error"
    public let state: NSString
    public let peerCount: Int32
    public let downRateBytesPerSec: Int64
    public let upRateBytesPerSec: Int64
    public let errorMessage: NSString?

    public init(
        torrentID: NSString,
        name: NSString,
        totalBytes: Int64,
        progressQ16: Int32,
        state: NSString,
        peerCount: Int32,
        downRateBytesPerSec: Int64,
        upRateBytesPerSec: Int64,
        errorMessage: NSString?
    ) {
        self.schemaVersion = 1
        self.torrentID = torrentID
        self.name = name
        self.totalBytes = totalBytes
        self.progressQ16 = progressQ16
        self.state = state
        self.peerCount = peerCount
        self.downRateBytesPerSec = downRateBytesPerSec
        self.upRateBytesPerSec = upRateBytesPerSec
        self.errorMessage = errorMessage
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(torrentID, forKey: "torrentID")
        coder.encode(name, forKey: "name")
        coder.encode(totalBytes, forKey: "totalBytes")
        coder.encode(progressQ16, forKey: "progressQ16")
        coder.encode(state, forKey: "state")
        coder.encode(peerCount, forKey: "peerCount")
        coder.encode(downRateBytesPerSec, forKey: "downRateBytesPerSec")
        coder.encode(upRateBytesPerSec, forKey: "upRateBytesPerSec")
        coder.encode(errorMessage, forKey: "errorMessage")
    }

    public required init?(coder: NSCoder) {
        schemaVersion = coder.decodeInt32(forKey: "schemaVersion")
        guard let torrentID = coder.decodeObject(of: NSString.self, forKey: "torrentID") else { return nil }
        guard let name = coder.decodeObject(of: NSString.self, forKey: "name") else { return nil }
        totalBytes = coder.decodeInt64(forKey: "totalBytes")
        progressQ16 = coder.decodeInt32(forKey: "progressQ16")
        guard let state = coder.decodeObject(of: NSString.self, forKey: "state") else { return nil }
        peerCount = coder.decodeInt32(forKey: "peerCount")
        downRateBytesPerSec = coder.decodeInt64(forKey: "downRateBytesPerSec")
        upRateBytesPerSec = coder.decodeInt64(forKey: "upRateBytesPerSec")
        errorMessage = coder.decodeObject(of: NSString.self, forKey: "errorMessage")
        self.torrentID = torrentID
        self.name = name
        self.state = state
    }
}
