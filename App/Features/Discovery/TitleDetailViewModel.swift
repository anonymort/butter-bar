import Foundation
import SwiftUI
import MetadataDomain

// MARK: - Cast member (local app type)
//
// `MetadataDomain` (#11) does not expose cast in v1; the foundation seals
// `Movie`/`Show`/`MetadataProvider` at the surface needed to ship Phase 4.
// Cast surfacing is a follow-up to extend the foundation. The detail page
// holds a local value type so the chip-row UI is wired and snapshot-tested
// today; once `MetadataProvider` exposes credits, the view model populates
// this list from the same fetch and no UI change is needed.

struct CastMember: Equatable, Sendable, Hashable, Identifiable {
    let id: Int
    let name: String
    let character: String
    let profilePath: String?
}

// MARK: - Library match seam
//
// "In your library" is the join between a discovery-side `MediaItem` and a
// local library file. The actual matching uses #11's `TitleNameParser` +
// `MatchRanker` over the engine's torrent file list and lives in #17's
// orchestration layer. The detail page consumes the result via this
// injected closure so tests can assert behaviour without an `EngineClient`.

struct LibraryMatch: Equatable, Sendable, Hashable {
    let torrentID: String
    let fileIndex: Int
    /// Display label for the link affordance. Engine-derived.
    let displayName: String
}

typealias LibraryMatcher = @Sendable (MediaItem) async -> LibraryMatch?

// MARK: - Detail content

/// Successful detail payload — fully resolved metadata for a single
/// `MediaItem`, ready for the view to render.
struct TitleDetail: Equatable, Sendable {
    let item: MediaItem
    let cast: [CastMember]
    let recommendations: [MediaItem]
    let libraryMatch: LibraryMatch?

    /// Convenience for view rendering — derived from `item`.
    var displayTitle: String {
        switch item {
        case .movie(let m): return m.title
        case .show(let s): return s.name
        }
    }

    var year: Int? {
        switch item {
        case .movie(let m): return m.releaseYear
        case .show(let s): return s.firstAirYear
        }
    }

    var runtimeMinutes: Int? {
        switch item {
        case .movie(let m): return m.runtimeMinutes
        case .show: return nil   // shows surface runtime per-episode (#16)
        }
    }

    var voteAverage: Double? {
        switch item {
        case .movie(let m): return m.voteAverage
        case .show(let s): return s.voteAverage
        }
    }

    var overview: String {
        switch item {
        case .movie(let m): return m.overview
        case .show(let s): return s.overview
        }
    }

    var genres: [Genre] {
        switch item {
        case .movie(let m): return m.genres
        case .show(let s): return s.genres
        }
    }

    var backdropPath: String? {
        switch item {
        case .movie(let m): return m.backdropPath
        case .show(let s): return s.backdropPath
        }
    }

    var posterPath: String? {
        switch item {
        case .movie(let m): return m.posterPath
        case .show(let s): return s.posterPath
        }
    }

    var isMovie: Bool {
        if case .movie = item { return true }
        return false
    }
}

/// Top-level view state. `loaded(_, isRevalidating:)` distinguishes a fresh
/// cache hit from a stale one being refreshed in the background — UI may
/// show a subtle indicator without blocking the content.
enum TitleDetailState: Equatable, Sendable {
    case loading
    case loaded(TitleDetail, isRevalidating: Bool)
    case error
}

// MARK: - View model

@MainActor
final class TitleDetailViewModel: ObservableObject {

    @Published private(set) var state: TitleDetailState = .loading

    private let id: MediaID
    private let kind: Kind
    private let provider: MetadataProvider
    private let libraryMatcher: LibraryMatcher
    private let castProvider: @Sendable (MediaID) async -> [CastMember]
    private let recommendationsCount: Int

    /// Movie or show is determined by the navigation destination — callers
    /// know which kind of item they tapped, so we pass it explicitly rather
    /// than try to infer from the `MediaID`.
    enum Kind: Sendable, Equatable {
        case movie
        case show
    }

    /// Default cast-row size per AC. Overridable for snapshot tests.
    static let defaultCastCount = 8

    init(id: MediaID,
         kind: Kind,
         provider: MetadataProvider,
         libraryMatcher: @escaping LibraryMatcher = { _ in nil },
         castProvider: @escaping @Sendable (MediaID) async -> [CastMember] = { _ in [] },
         recommendationsCount: Int = 12) {
        self.id = id
        self.kind = kind
        self.provider = provider
        self.libraryMatcher = libraryMatcher
        self.castProvider = castProvider
        self.recommendationsCount = recommendationsCount
    }

    /// Idempotent entry point. Safe to call from `.task { ... }`.
    func load() async {
        // If we are already showing data, treat a re-entry as a soft refresh
        // (revalidation flag flips on, then off when fetch returns).
        switch state {
        case .loaded(let detail, _):
            state = .loaded(detail, isRevalidating: true)
        case .loading, .error:
            state = .loading
        }

        do {
            let item: MediaItem
            switch kind {
            case .movie:
                let m = try await provider.movieDetail(id: id)
                item = .movie(m)
            case .show:
                let s = try await provider.showDetail(id: id)
                item = .show(s)
            }

            // Recommendations and cast fetch in parallel; either failing is
            // non-fatal — the page still renders without them.
            async let recsTask: [MediaItem] = (try? provider.recommendations(for: id)) ?? []
            async let castTask: [CastMember] = castProvider(id)
            async let matchTask: LibraryMatch? = libraryMatcher(item)

            let recs = await recsTask
            let cast = await castTask
            let match = await matchTask

            let detail = TitleDetail(
                item: item,
                cast: Array(cast.prefix(Self.defaultCastCount)),
                recommendations: Array(recs.prefix(recommendationsCount)),
                libraryMatch: match
            )
            state = .loaded(detail, isRevalidating: false)
        } catch {
            state = .error
        }
    }

    /// Retry from the error state. Resets to `.loading` and re-runs `load`.
    func retry() async {
        state = .loading
        await load()
    }

    // MARK: - Image URL helpers (forwarded to the provider)

    func backdropURL(_ path: String) -> URL {
        provider.imageURL(path: path, size: TMDBImageSizes.size(for: .backdrop))
    }

    func posterURL(_ path: String) -> URL {
        provider.imageURL(path: path, size: TMDBImageSizes.size(for: .posterDetail))
    }

    func castProfileURL(_ path: String) -> URL {
        provider.imageURL(path: path, size: TMDBImageSizes.size(for: .headshot))
    }

    func recommendationPosterURL(_ path: String) -> URL {
        provider.imageURL(path: path, size: TMDBImageSizes.size(for: .posterCard))
    }

    // MARK: - Snapshot / Canvas factories
    //
    // Skip live fetch by seeding `state` directly. Tests then render the
    // view at a pinned colour scheme. The provider passed in is only used
    // for image-URL synthesis.

    static func previewLoadedMovie(provider: MetadataProvider,
                                   recommendations: [MediaItem],
                                   cast: [CastMember] = [],
                                   libraryMatch: LibraryMatch? = nil) -> TitleDetailViewModel {
        let vm = TitleDetailViewModel(
            id: MediaID(provider: .tmdb, id: 27205),
            kind: .movie,
            provider: provider
        )
        vm.state = .loaded(
            TitleDetail(
                item: .movie(SamplePreviewData.movie),
                cast: cast,
                recommendations: recommendations,
                libraryMatch: libraryMatch
            ),
            isRevalidating: false
        )
        return vm
    }

    static func previewLoadedShow(provider: MetadataProvider,
                                  recommendations: [MediaItem],
                                  cast: [CastMember] = [],
                                  libraryMatch: LibraryMatch? = nil) -> TitleDetailViewModel {
        let vm = TitleDetailViewModel(
            id: MediaID(provider: .tmdb, id: 1399),
            kind: .show,
            provider: provider
        )
        vm.state = .loaded(
            TitleDetail(
                item: .show(SamplePreviewData.show),
                cast: cast,
                recommendations: recommendations,
                libraryMatch: libraryMatch
            ),
            isRevalidating: false
        )
        return vm
    }

    static func previewLoading(provider: MetadataProvider) -> TitleDetailViewModel {
        let vm = TitleDetailViewModel(
            id: MediaID(provider: .tmdb, id: 27205),
            kind: .movie,
            provider: provider
        )
        vm.state = .loading
        return vm
    }

    static func previewError(provider: MetadataProvider) -> TitleDetailViewModel {
        let vm = TitleDetailViewModel(
            id: MediaID(provider: .tmdb, id: 27205),
            kind: .movie,
            provider: provider
        )
        vm.state = .error
        return vm
    }
}

// Test-visible preview fixtures. Kept inside the app target so snapshot
// tests can reference them without a roundtrip through MetadataDomain's
// test target.
enum SamplePreviewData {
    static let movie = Movie(
        id: MediaID(provider: .tmdb, id: 27205),
        title: "Inception",
        originalTitle: "Inception",
        releaseYear: 2010,
        runtimeMinutes: 148,
        overview: "A thief who steals corporate secrets through use of "
            + "dream-sharing technology is given the inverse task of "
            + "planting an idea into the mind of a CEO.",
        genres: [
            Genre(id: 28, name: "Action"),
            Genre(id: 878, name: "Science Fiction"),
            Genre(id: 12, name: "Adventure")
        ],
        posterPath: "/inception.jpg",
        backdropPath: "/inception_back.jpg",
        voteAverage: 8.4,
        popularity: 100.0
    )

    static let show = Show(
        id: MediaID(provider: .tmdb, id: 1399),
        name: "Game of Thrones",
        originalName: "Game of Thrones",
        firstAirYear: 2011,
        lastAirYear: 2019,
        status: .ended,
        overview: "Seven noble families fight for control of the mythical "
            + "land of Westeros.",
        genres: [
            Genre(id: 18, name: "Drama"),
            Genre(id: 10765, name: "Sci-Fi & Fantasy")
        ],
        posterPath: "/got.jpg",
        backdropPath: "/got_back.jpg",
        voteAverage: 8.4,
        popularity: 200.0,
        seasons: []
    )

    static let cast: [CastMember] = [
        CastMember(id: 1, name: "Leonardo DiCaprio", character: "Cobb", profilePath: nil),
        CastMember(id: 2, name: "Joseph Gordon-Levitt", character: "Arthur", profilePath: nil),
        CastMember(id: 3, name: "Elliot Page", character: "Ariadne", profilePath: nil),
        CastMember(id: 4, name: "Tom Hardy", character: "Eames", profilePath: nil),
        CastMember(id: 5, name: "Ken Watanabe", character: "Saito", profilePath: nil),
        CastMember(id: 6, name: "Cillian Murphy", character: "Robert Fischer", profilePath: nil),
        CastMember(id: 7, name: "Marion Cotillard", character: "Mal", profilePath: nil),
        CastMember(id: 8, name: "Michael Caine", character: "Miles", profilePath: nil)
    ]

    static let recommendations: [MediaItem] = [
        .movie(Movie(
            id: MediaID(provider: .tmdb, id: 157336),
            title: "Interstellar",
            originalTitle: "Interstellar",
            releaseYear: 2014,
            runtimeMinutes: 169,
            overview: "",
            genres: [],
            posterPath: "/interstellar.jpg",
            backdropPath: nil,
            voteAverage: 8.4,
            popularity: 90
        )),
        .movie(Movie(
            id: MediaID(provider: .tmdb, id: 1124),
            title: "The Prestige",
            originalTitle: "The Prestige",
            releaseYear: 2006,
            runtimeMinutes: 130,
            overview: "",
            genres: [],
            posterPath: "/prestige.jpg",
            backdropPath: nil,
            voteAverage: 8.2,
            popularity: 70
        ))
    ]

    static let libraryMatch = LibraryMatch(
        torrentID: "abc123",
        fileIndex: 0,
        displayName: "Inception (2010) 1080p.mkv"
    )
}
