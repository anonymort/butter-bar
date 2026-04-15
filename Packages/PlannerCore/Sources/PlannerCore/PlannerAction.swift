public enum PlannerAction: Equatable, Sendable, Codable {
    case setDeadlines([PieceDeadline])
    case clearDeadlinesExcept(pieces: [Int])
    case waitForRange(requestID: String, maxWaitMs: Int)
    case failRange(requestID: String, reason: FailReason)
    case emitHealth(StreamHealth)
}
