import Foundation
import MetadataDomain

/// App-side `Identifiable` conformance for `MediaItem`. Lives here rather
/// than in `MetadataDomain` because `Identifiable` is a SwiftUI/runtime
/// conformance the domain package shouldn't carry.
extension MediaItem: Identifiable {}

/// Sidebar destinations exposed by the Discovery surface (#13).
///
/// `Library` is the existing surface, preserved as a sibling. `Home` is the
/// default landing surface; `Movies` and `Shows` are the typed grids.
/// Watchlist is intentionally absent — that's p1 (Account Sync, Epic #6).
enum DiscoveryDestination: String, CaseIterable, Identifiable, Hashable {
    case home
    case library
    case movies
    case shows

    var id: String { rawValue }

    /// Sidebar label per `06-brand.md § Voice` — direct, sentence-cased.
    var title: String {
        switch self {
        case .home:    return "Home"
        case .library: return "Library"
        case .movies:  return "Movies"
        case .shows:   return "Shows"
        }
    }

    /// SF Symbol for the sidebar row. Symbols only — no novelty glyphs.
    var systemImage: String {
        switch self {
        case .home:    return "house"
        case .library: return "tray.full"
        case .movies:  return "film"
        case .shows:   return "tv"
        }
    }
}
