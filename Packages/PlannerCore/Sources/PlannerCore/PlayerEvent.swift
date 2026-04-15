/// Events the gateway delivers to the planner. Seek is not a public event;
/// the planner detects it internally by comparing GET ranges to the last served byte.
public enum PlayerEvent: Sendable, Codable {
    case head                                        // HEAD request from AVPlayer
    case get(requestID: String, range: ByteRange)    // GET with Range
    case cancel(requestID: String)                   // client closed before response complete
}
