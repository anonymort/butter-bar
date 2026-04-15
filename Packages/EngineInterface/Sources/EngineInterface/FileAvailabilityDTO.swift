import Foundation

@objc(FileAvailabilityDTO)
public final class FileAvailabilityDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32
    public let torrentID: NSString
    public let fileIndex: Int32
    /// Fully downloaded byte ranges, coalesced, inclusive on both ends.
    public let availableRanges: [ByteRangeDTO]

    public init(
        torrentID: NSString,
        fileIndex: Int32,
        availableRanges: [ByteRangeDTO]
    ) {
        self.schemaVersion = 1
        self.torrentID = torrentID
        self.fileIndex = fileIndex
        self.availableRanges = availableRanges
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(torrentID, forKey: "torrentID")
        coder.encode(fileIndex, forKey: "fileIndex")
        coder.encode(availableRanges as NSArray, forKey: "availableRanges")
    }

    public required init?(coder: NSCoder) {
        schemaVersion = coder.decodeInt32(forKey: "schemaVersion")
        guard let torrentID = coder.decodeObject(of: NSString.self, forKey: "torrentID") else { return nil }
        fileIndex = coder.decodeInt32(forKey: "fileIndex")
        let rangesArray = coder.decodeObject(
            of: [NSArray.self, ByteRangeDTO.self],
            forKey: "availableRanges"
        ) as? [ByteRangeDTO] ?? []
        availableRanges = rangesArray
        self.torrentID = torrentID
    }
}
