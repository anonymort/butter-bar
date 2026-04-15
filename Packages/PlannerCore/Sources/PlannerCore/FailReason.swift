public enum FailReason: String, Equatable, Sendable, Codable {
    case rangeOutOfBounds
    case waitTimedOut
    case streamClosed
}
