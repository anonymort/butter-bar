import Foundation

/// Typed errors surfaced by `MediaProvider` implementations.
///
/// Callers should treat `.rateLimited` as recoverable (back off and retry)
/// and `.authRequired` as fatal for the current session (trigger re-auth).
public enum MediaProviderError: Error, LocalizedError, Sendable {
    case networkError(underlying: Error)
    case rateLimited
    case notFound
    case authRequired

    public var errorDescription: String? {
        switch self {
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .rateLimited:
            return "Provider rate limit reached. Try again later."
        case .notFound:
            return "No results found for this title."
        case .authRequired:
            return "Provider authentication required."
        }
    }
}
