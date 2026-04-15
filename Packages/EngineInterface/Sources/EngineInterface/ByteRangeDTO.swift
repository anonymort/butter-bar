import Foundation

/// A byte range [startByte, endByte], both inclusive.
/// No schemaVersion — this DTO rides the version of its parent (per A8).
@objc(ByteRangeDTO)
public final class ByteRangeDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let startByte: Int64
    public let endByte: Int64

    public init(startByte: Int64, endByte: Int64) {
        self.startByte = startByte
        self.endByte = endByte
    }

    public func encode(with coder: NSCoder) {
        coder.encode(startByte, forKey: "startByte")
        coder.encode(endByte, forKey: "endByte")
    }

    public required init?(coder: NSCoder) {
        startByte = coder.decodeInt64(forKey: "startByte")
        endByte = coder.decodeInt64(forKey: "endByte")
    }
}
