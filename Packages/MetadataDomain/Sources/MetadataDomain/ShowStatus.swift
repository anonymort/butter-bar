import Foundation

public enum ShowStatus: String, Equatable, Sendable, Codable, Hashable {
    case returning
    case ended
    case canceled
    case inProduction
}
