import Foundation
import Combine
import MetadataDomain

// MARK: - HomeRowKind

/// Identifies a Home row by what it fetches. The order in `HomeViewModel.rows`
/// mirrors `discovery-metadata-foundation.md § D11`.
enum HomeRowKind: String, CaseIterable, Identifiable, Hashable {
    case continueWatching   // #17 populates; we render an empty placeholder for now and hide it.
    case trendingMovies
    case trendingShows
    case popularMovies
    case popularShows
    case topRatedMovies
    case topRatedShows

    var id: String { rawValue }

    /// Calm, factual title per `06-brand.md § Voice`. Title-cased nouns.
    var title: String {
        switch self {
        case .continueWatching: return "Continue watching"
        case .trendingMovies:   return "Trending — movies"
        case .trendingShows:    return "Trending — shows"
        case .popularMovies:    return "Popular movies"
        case .popularShows:     return "Popular shows"
        case .topRatedMovies:   return "Top rated movies"
        case .topRatedShows:    return "Top rated shows"
        }
    }
}

// MARK: - HomeRowState

/// Per-row UI state. Each row loads independently so a single TMDB hiccup
/// doesn't blank the whole Home screen — failed rows render a quiet
/// "We can't reach the catalogue right now" line per `06-brand.md § Voice`.
enum HomeRowState: Equatable {
    case loading
    case loaded([MediaItem])
    case failed
    case empty

    var items: [MediaItem] {
        if case .loaded(let items) = self { return items }
        return []
    }

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }
}

// MARK: - HomeViewModel

/// Drives the Home screen's rows. Each row fetches independently against the
/// injected `MetadataProvider`; in-flight requests are coalesced per row so
/// repeated `.task` triggers (e.g. on view re-appearance) don't spam TMDB.
///
/// `continueWatching` is rendered as a placeholder (state stays `.empty` until
/// #17 wires real data) — per the issue AC, the row hides when empty.
@MainActor
final class HomeViewModel: ObservableObject {

    @Published private(set) var rowStates: [HomeRowKind: HomeRowState]

    private let provider: MetadataProvider

    /// Tracks rows currently fetching, used to coalesce repeated triggers.
    private var inFlight: Set<HomeRowKind> = []

    init(provider: MetadataProvider) {
        self.provider = provider
        // Continue Watching is always seeded as `.empty` for now — #17 will
        // populate it. Other rows start `.loading` so the UI can shimmer.
        var initial: [HomeRowKind: HomeRowState] = [:]
        for kind in HomeRowKind.allCases {
            initial[kind] = (kind == .continueWatching) ? .empty : .loading
        }
        self.rowStates = initial
    }

    /// Rows in display order, including the (possibly hidden) Continue
    /// Watching row. UI decides whether to render based on `state`.
    var rows: [(kind: HomeRowKind, state: HomeRowState)] {
        HomeRowKind.allCases.map { ($0, rowStates[$0] ?? .loading) }
    }

    /// Whether a row should be visible. Continue Watching hides when empty
    /// per the issue AC; all other rows render their state.
    func shouldRender(_ kind: HomeRowKind) -> Bool {
        switch kind {
        case .continueWatching:
            return rowStates[kind]?.isLoaded == true
                && rowStates[kind]!.items.isEmpty == false
        default:
            return true
        }
    }

    /// Kick off all data-bearing rows in parallel. Idempotent; in-flight
    /// rows are coalesced.
    func load() async {
        await withTaskGroup(of: Void.self) { group in
            for kind in HomeRowKind.allCases where kind != .continueWatching {
                group.addTask { [weak self] in await self?.loadRow(kind) }
            }
        }
    }

    /// Load a single row. Public for retry affordances; coalesces in-flight.
    func loadRow(_ kind: HomeRowKind) async {
        if inFlight.contains(kind) { return }
        inFlight.insert(kind)
        defer { inFlight.remove(kind) }

        // Don't blow away a loaded row to a shimmer when re-fetching.
        if rowStates[kind]?.isLoaded != true {
            rowStates[kind] = .loading
        }

        do {
            let items = try await fetch(kind)
            rowStates[kind] = items.isEmpty ? .empty : .loaded(items)
        } catch {
            rowStates[kind] = .failed
        }
    }

    /// Test/preview-only seam to set per-row state without going through the
    /// provider. Snapshot suites use this to render deterministic states
    /// (loaded / failed / loading) without firing live fetches.
    func _setRowState(_ kind: HomeRowKind, _ state: HomeRowState) {
        rowStates[kind] = state
    }

    private func fetch(_ kind: HomeRowKind) async throws -> [MediaItem] {
        switch kind {
        case .continueWatching:
            // #17 will replace this; for now nothing to fetch.
            return []
        case .trendingMovies:
            return try await provider.trending(media: .movie, window: .week)
        case .trendingShows:
            return try await provider.trending(media: .tv, window: .week)
        case .popularMovies:
            return try await provider.popular(media: .movie)
        case .popularShows:
            return try await provider.popular(media: .tv)
        case .topRatedMovies:
            return try await provider.topRated(media: .movie)
        case .topRatedShows:
            return try await provider.topRated(media: .tv)
        }
    }
}
