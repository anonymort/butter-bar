public struct PieceDeadline: Equatable, Sendable, Codable {
    public let piece: Int
    public let deadlineMs: Int
    public let priority: Priority

    public enum Priority: String, Equatable, Sendable, Codable {
        case critical      // playhead window
        case readahead     // rolling lookahead
        case background    // not in active read window
    }

    public init(piece: Int, deadlineMs: Int, priority: Priority) {
        self.piece = piece
        self.deadlineMs = deadlineMs
        self.priority = priority
    }
}
