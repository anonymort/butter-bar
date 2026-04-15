/// A closed byte range. Both `start` and `end` are inclusive.
public struct ByteRange: Hashable, Sendable, Codable {
    public let start: Int64   // inclusive
    public let end: Int64     // inclusive

    public init(start: Int64, end: Int64) {
        self.start = start
        self.end = end
    }
}
