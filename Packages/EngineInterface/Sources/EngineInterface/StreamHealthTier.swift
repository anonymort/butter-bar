import Foundation

/// Typed tier projection for `StreamHealthDTO`.
///
/// The XPC wire format remains `NSString` (`StreamHealthDTO.tier`) to preserve
/// NSSecureCoding compatibility; this enum is a domain-layer convenience.
public enum StreamHealthTier: String, Codable, Sendable, CaseIterable {
    case healthy
    case marginal
    case starving
}
