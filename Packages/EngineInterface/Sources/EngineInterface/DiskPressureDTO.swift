import Foundation

@objc(DiskPressureDTO)
public final class DiskPressureDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32
    public let totalBudgetBytes: Int64
    public let usedBytes: Int64
    public let pinnedBytes: Int64
    public let evictableBytes: Int64
    /// One of: "ok" | "warn" | "critical"
    public let level: NSString

    public init(
        totalBudgetBytes: Int64,
        usedBytes: Int64,
        pinnedBytes: Int64,
        evictableBytes: Int64,
        level: NSString
    ) {
        self.schemaVersion = 1
        self.totalBudgetBytes = totalBudgetBytes
        self.usedBytes = usedBytes
        self.pinnedBytes = pinnedBytes
        self.evictableBytes = evictableBytes
        self.level = level
    }

    public func encode(with coder: NSCoder) {
        coder.encode(schemaVersion, forKey: "schemaVersion")
        coder.encode(totalBudgetBytes, forKey: "totalBudgetBytes")
        coder.encode(usedBytes, forKey: "usedBytes")
        coder.encode(pinnedBytes, forKey: "pinnedBytes")
        coder.encode(evictableBytes, forKey: "evictableBytes")
        coder.encode(level, forKey: "level")
    }

    public required init?(coder: NSCoder) {
        schemaVersion = coder.decodeInt32(forKey: "schemaVersion")
        totalBudgetBytes = coder.decodeInt64(forKey: "totalBudgetBytes")
        usedBytes = coder.decodeInt64(forKey: "usedBytes")
        pinnedBytes = coder.decodeInt64(forKey: "pinnedBytes")
        evictableBytes = coder.decodeInt64(forKey: "evictableBytes")
        guard let level = coder.decodeObject(of: NSString.self, forKey: "level") else { return nil }
        self.level = level
    }
}
