import Foundation

public struct CastMember: Equatable, Sendable, Hashable, Codable, Identifiable {
    public let id: Int
    public let name: String
    public let character: String
    public let profilePath: String?

    public init(id: Int,
                name: String,
                character: String,
                profilePath: String?) {
        self.id = id
        self.name = name
        self.character = character
        self.profilePath = profilePath
    }
}
