import Foundation
import Combine
import EngineInterface
import LibraryDomain
import MetadataDomain

// MARK: - LibraryViewModel

/// Bridges the actor-isolated `EngineClient` to the SwiftUI main actor.
/// All published properties are updated on the main actor.
@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var torrents: [TorrentSummaryDTO] = []
    @Published var loadError: String?

    /// Map of `"\(torrentID)#\(fileIndex)"` → `PlaybackHistoryDTO`.
    /// Source of truth for `WatchStatus` derivation in the UI. Populated on
    /// `start()` and kept in sync via `playbackHistoryChanged` events.
    @Published var playbackHistory: [String: PlaybackHistoryDTO] = [:]

    /// Map of `"\(torrentID)#\(fileIndex)"` → `FavouriteDTO`. Populated on
    /// `start()` from `listFavourites` and kept in sync via `favouritesChanged`.
    @Published var favourites: [String: FavouriteDTO] = [:]

    /// When true, only show favourited torrents in the library list. UI binding
    /// for the toolbar filter introduced by #36.
    @Published var favouritesOnly: Bool = false

    /// Exposed so `LibraryView` can pass the client to `PlayerView` for stream lifecycle.
    let engineClient: EngineClient
    private(set) var isRefreshing: Bool = false

    /// Metadata-enriched continue-watching items (#17). Populated by
    /// `LibraryMetadataResolver` whenever the underlying torrents/history
    /// change. When `metadataResolver` is `nil` (preview / older code paths),
    /// this stays empty and `displayContinueWatching` falls back to the raw
    /// projection.
    @Published private(set) var enrichedContinueWatching: [ContinueWatchingItem] = []

    /// Optional resolver. Production code injects it from
    /// `ButterBarApp`; preview / snapshot factories may leave it nil to
    /// keep the row metadata-free.
    let metadataResolver: LibraryMetadataResolver?

    /// Optional image URL builder for the row. Mirrors the lifecycle of
    /// `metadataResolver` — when both are set, posters render; when nil,
    /// the placeholder rect carries the slot.
    let posterURLBuilder: ((String) -> URL)?

    /// Set `true` in preview/snapshot factory methods to prevent `.task` from
    /// firing a real `EngineClient` call and overwriting pre-populated state.
    /// For Canvas / snapshot-test use only — do not set in production code paths.
    var skipRefresh: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    init(client: EngineClient,
         metadataResolver: LibraryMetadataResolver? = nil,
         posterURLBuilder: ((String) -> URL)? = nil) {
        self.engineClient = client
        self.metadataResolver = metadataResolver
        self.posterURLBuilder = posterURLBuilder
    }

    func start() async {
        guard !skipRefresh else { return }
        await engineClient.connect()
        await subscribeToPlaybackHistoryChanges()
        await refresh()
    }

    func refresh() async {
        guard !skipRefresh else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            torrents = try await engineClient.listTorrents()
            // Refresh the watch-state map alongside the torrent list. Both
            // live on the same engine; serial fetch is fine for v1.
            let history = try await engineClient.listPlaybackHistory()
            playbackHistory = Dictionary(
                uniqueKeysWithValues: history.map {
                    (Self.key(for: $0.torrentID as String, fileIndex: Int($0.fileIndex)), $0)
                }
            )
            // #36 — favourites map.
            let favs = try await engineClient.listFavourites()
            favourites = Dictionary(
                uniqueKeysWithValues: favs.map {
                    (Self.key(for: $0.torrentID as String, fileIndex: Int($0.fileIndex)), $0)
                }
            )
            loadError = nil
            await refreshContinueWatching()
        } catch {
            loadError = "Could not load library: \(error.localizedDescription)"
        }
    }

    // MARK: - Continue watching enrichment (#17)

    /// Re-run the metadata resolver against the current torrents + history.
    /// Cheap if everything is cache-hot. Safe to call repeatedly.
    func refreshContinueWatching() async {
        guard let resolver = metadataResolver else { return }
        let history = Array(playbackHistory.values)
        let snapshotTorrents = torrents
        let client = engineClient
        let items = await resolver.resolve(
            history: history,
            torrents: snapshotTorrents,
            fileNameLookup: { torrentID, fileIndex in
                // Best-effort lookup of the file name. Failures fall back
                // to the torrent name in `LibraryMetadataResolver`.
                guard let files = try? await client.listFiles(torrentID as NSString),
                      let file = files.first(where: { Int($0.fileIndex) == fileIndex }) else {
                    return nil
                }
                return file.path as String
            }
        )
        self.enrichedContinueWatching = items
    }

    /// Read-side projection used by `LibraryView`. Prefers the
    /// metadata-enriched output when the resolver is wired up (or when a
    /// preview/snapshot factory has populated `enrichedContinueWatching`
    /// directly), and falls back to the raw synchronous projection
    /// otherwise.
    var displayContinueWatching: [ContinueWatchingItem] {
        if metadataResolver != nil || previewForcesEnriched {
            return enrichedContinueWatching
        }
        return continueWatching
    }

    /// Snapshot/Preview escape hatch: lets the preview factory hand-craft
    /// the enriched array without instantiating a resolver. Production
    /// code never sets this.
    var previewForcesEnriched: Bool = false

    func listFiles(torrentID: String) async throws -> [TorrentFileDTO] {
        try await engineClient.listFiles(torrentID as NSString)
    }

    // MARK: - Watch state (A26 — Epic #5 Phase 1, #37)

    /// Derive the current `WatchStatus` for `(torrentID, fileIndex)`.
    /// Uses the published `playbackHistory` map and the supplied `totalBytes`.
    func watchStatus(torrentID: String,
                     fileIndex: Int,
                     totalBytes: Int64) -> WatchStatus {
        let key = Self.key(for: torrentID, fileIndex: fileIndex)
        return WatchStatus.from(history: playbackHistory[key], totalBytes: totalBytes)
    }

    /// Mark a file as watched. The engine writes the canonical row state and
    /// emits `playbackHistoryChanged` which updates `playbackHistory` live.
    func markWatched(torrentID: String, fileIndex: Int) async {
        do {
            try await engineClient.setWatchedState(
                torrentID: torrentID as NSString,
                fileIndex: NSNumber(value: fileIndex),
                watched: true
            )
        } catch {
            loadError = "Could not mark watched: \(error.localizedDescription)"
        }
    }

    /// Mark a file as unwatched. Same engine echo flow as `markWatched`.
    func markUnwatched(torrentID: String, fileIndex: Int) async {
        do {
            try await engineClient.setWatchedState(
                torrentID: torrentID as NSString,
                fileIndex: NSNumber(value: fileIndex),
                watched: false
            )
        } catch {
            loadError = "Could not mark unwatched: \(error.localizedDescription)"
        }
    }

    // MARK: - Favourites (#36)

    /// Whether `(torrentID, fileIndex)` is currently favourited. v1 surface is
    /// per-file 0; the projection over the favourites map.
    func isFavourite(torrentID: String, fileIndex: Int) -> Bool {
        favourites[Self.key(for: torrentID, fileIndex: fileIndex)] != nil
    }

    /// Toggle the favourite flag. The engine writes the canonical row state
    /// and emits `favouritesChanged`, which updates the local map.
    func toggleFavourite(torrentID: String, fileIndex: Int) async {
        let current = isFavourite(torrentID: torrentID, fileIndex: fileIndex)
        do {
            try await engineClient.setFavourite(
                torrentID: torrentID as NSString,
                fileIndex: NSNumber(value: fileIndex),
                isFavourite: !current
            )
        } catch {
            loadError = "Could not update favourite: \(error.localizedDescription)"
        }
    }

    /// Torrents filtered by `favouritesOnly` flag. Used by `LibraryView` to
    /// build its display list.
    var displayedTorrents: [TorrentSummaryDTO] {
        guard favouritesOnly else { return torrents }
        return torrents.filter { isFavourite(torrentID: $0.torrentID as String, fileIndex: 0) }
    }

    // MARK: - Continue watching (#35)

    /// Items to show in the library's "Continue watching" row, sorted most-
    /// recently-played first. Includes only files whose `WatchStatus` is
    /// `.inProgress` or `.reWatching`. v1 surface is per-torrent file 0
    /// (matches the rest of Phase 1's per-file limitations — see #37).
    var continueWatching: [ContinueWatchingItem] {
        let candidates: [ContinueWatchingItem] = torrents.compactMap { torrent in
            let id = torrent.torrentID as String
            guard let dto = playbackHistory[Self.key(for: id, fileIndex: 0)] else {
                return nil
            }
            let status = WatchStatus.from(history: dto, totalBytes: torrent.totalBytes)
            switch status {
            case .inProgress(let p, let t):
                return ContinueWatchingItem(
                    torrent: torrent,
                    fileIndex: 0,
                    progressBytes: p,
                    totalBytes: t,
                    lastPlayedAtMillis: dto.lastPlayedAt,
                    isReWatching: false
                )
            case .reWatching(let p, let t, _):
                return ContinueWatchingItem(
                    torrent: torrent,
                    fileIndex: 0,
                    progressBytes: p,
                    totalBytes: t,
                    lastPlayedAtMillis: dto.lastPlayedAt,
                    isReWatching: true
                )
            case .unwatched, .watched:
                return nil
            }
        }
        return candidates.sorted { $0.lastPlayedAtMillis > $1.lastPlayedAtMillis }
    }

    // MARK: - Helpers

    /// Stable composite key for `(torrentID, fileIndex)`.
    static func key(for torrentID: String, fileIndex: Int) -> String {
        "\(torrentID)#\(fileIndex)"
    }

    /// Subscribe to engine `playbackHistoryChanged` and `favouritesChanged`
    /// events. Updates published maps on the main actor; SwiftUI re-renders
    /// affected rows.
    private func subscribeToPlaybackHistoryChanges() async {
        guard let events = await engineClient.events else { return }
        events.playbackHistoryChangedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dto in
                guard let self else { return }
                let key = Self.key(for: dto.torrentID as String, fileIndex: Int(dto.fileIndex))
                self.playbackHistory[key] = dto
                // #17: re-derive the enriched row whenever watch state
                // changes. The resolver's match cache absorbs the cost.
                Task { [weak self] in
                    await self?.refreshContinueWatching()
                }
            }
            .store(in: &cancellables)
        events.favouritesChangedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }
                let key = Self.key(
                    for: change.favourite.torrentID as String,
                    fileIndex: Int(change.favourite.fileIndex)
                )
                if change.isRemoved {
                    self.favourites.removeValue(forKey: key)
                } else {
                    self.favourites[key] = change.favourite
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Preview factories

extension LibraryViewModel {

    /// A view model pre-populated with sample data for Xcode Previews and snapshot tests.
    /// `skipRefresh` is set so `.task { await viewModel.start() }` does not overwrite
    /// the pre-populated state during Canvas rendering or snapshot capture.
    static var previewWithData: LibraryViewModel {
        let vm = LibraryViewModel(client: EngineClient())
        vm.skipRefresh = true
        vm.torrents = [
            TorrentSummaryDTO(
                torrentID: "abc123",
                name: "Cosmos: A Personal Voyage (1980)",
                totalBytes: 8_589_934_592,
                progressQ16: 52_428,   // ~80%
                state: "downloading",
                peerCount: 14,
                downRateBytesPerSec: 4_300_000,
                upRateBytesPerSec: 512_000,
                errorMessage: nil
            ),
            TorrentSummaryDTO(
                torrentID: "def456",
                name: "Night of the Living Dead (1968)",
                totalBytes: 734_003_200,
                progressQ16: 65_536,   // 100%
                state: "seeding",
                peerCount: 3,
                downRateBytesPerSec: 0,
                upRateBytesPerSec: 120_000,
                errorMessage: nil
            ),
            TorrentSummaryDTO(
                torrentID: "ghi789",
                name: "The General (1926)",
                totalBytes: 1_073_741_824,
                progressQ16: 0,
                state: "queued",
                peerCount: 0,
                downRateBytesPerSec: 0,
                upRateBytesPerSec: 0,
                errorMessage: nil
            ),
        ]
        return vm
    }

    /// A view model with no torrents — shows the empty state.
    /// `skipRefresh` is set so snapshot tests see a stable empty state.
    static var previewEmpty: LibraryViewModel {
        let vm = LibraryViewModel(client: EngineClient())
        vm.skipRefresh = true
        return vm
    }

    /// Pre-populated with a continue-watching projection for #35 visual
    /// snapshots. Exercises `.inProgress` and `.reWatching` side-by-side,
    /// sorted by `lastPlayedAtMillis` desc.
    static var previewWithContinueWatching: LibraryViewModel {
        let vm = previewWithData
        // Cosmos: .reWatching at ~35%, older lastPlayedAt.
        vm.playbackHistory["abc123#0"] = PlaybackHistoryDTO(
            torrentID: "abc123",
            fileIndex: 0,
            resumeByteOffset: 3_006_477_107,
            lastPlayedAt: 1_700_000_000_000,
            totalWatchedSeconds: 0,
            completed: true,
            completedAt: NSNumber(value: 1_699_000_000_000)
        )
        // The General: .inProgress at ~22%, newer lastPlayedAt — appears first.
        vm.playbackHistory["ghi789#0"] = PlaybackHistoryDTO(
            torrentID: "ghi789",
            fileIndex: 0,
            resumeByteOffset: 236_223_201,  // ~22% of 1.07 GB
            lastPlayedAt: 1_700_000_500_000,
            totalWatchedSeconds: 0,
            completed: false,
            completedAt: nil
        )
        // Night of the Living Dead: .watched — excluded from projection.
        vm.playbackHistory["def456#0"] = PlaybackHistoryDTO(
            torrentID: "def456",
            fileIndex: 0,
            resumeByteOffset: 0,
            lastPlayedAt: 1_700_000_300_000,
            totalWatchedSeconds: 0,
            completed: true,
            completedAt: NSNumber(value: 1_700_000_300_000)
        )
        return vm
    }

    /// Pre-populated with metadata-enriched continue-watching items for #17
    /// visual snapshots. The resolver remains nil; we set the
    /// `enrichedContinueWatching` array directly so snapshots are
    /// deterministic without exercising the network seam.
    static var previewWithEnrichedContinueWatching: LibraryViewModel {
        let vm = previewWithContinueWatching
        // Force `displayContinueWatching` to use the enriched array by
        // assigning a dummy resolver-flag via `previewForcesEnriched`.
        vm.previewForcesEnriched = true
        let raw = vm.continueWatching
        vm.enrichedContinueWatching = raw.enumerated().map { index, item in
            // Mix matched + unmatched: index 0 (most recent) is matched as
            // a show with an episode designator, index 1 is unmatched.
            if index == 0 {
                let show = Show(
                    id: MediaID(provider: .tmdb, id: 1399),
                    name: "The General",
                    originalName: "The General",
                    firstAirYear: 2011,
                    lastAirYear: 2019,
                    status: .ended,  // typed via MetadataDomain.ShowStatus
                    overview: "",
                    genres: [],
                    posterPath: "/sample.jpg",
                    backdropPath: nil,
                    voteAverage: nil,
                    popularity: nil,
                    seasons: []
                )
                return ContinueWatchingItem(
                    torrent: item.torrent,
                    fileIndex: item.fileIndex,
                    progressBytes: item.progressBytes,
                    totalBytes: item.totalBytes,
                    lastPlayedAtMillis: item.lastPlayedAtMillis,
                    isReWatching: item.isReWatching,
                    media: .show(show),
                    posterPath: "/sample.jpg",
                    episodeDesignator: "S01E04"
                )
            }
            return item
        }
        return vm
    }

    /// Pre-populated with watch state for #37 visual snapshots:
    /// - Cosmos (abc123#0): `.reWatching` at ~35% (was previously completed).
    /// - Night of the Living Dead (def456#0): `.watched`.
    /// - The General (ghi789#0): `.unwatched` (no playback history row).
    static var previewWithWatchState: LibraryViewModel {
        let vm = previewWithData
        vm.playbackHistory["abc123#0"] = PlaybackHistoryDTO(
            torrentID: "abc123",
            fileIndex: 0,
            resumeByteOffset: 3_006_477_107,   // ~35% of 8.59 GB
            lastPlayedAt: 1_700_000_000_000,
            totalWatchedSeconds: 0,
            completed: true,
            completedAt: NSNumber(value: 1_699_000_000_000)
        )
        vm.playbackHistory["def456#0"] = PlaybackHistoryDTO(
            torrentID: "def456",
            fileIndex: 0,
            resumeByteOffset: 0,
            lastPlayedAt: 1_700_000_300_000,
            totalWatchedSeconds: 0,
            completed: true,
            completedAt: NSNumber(value: 1_700_000_300_000)
        )
        return vm
    }

    /// Pre-populated with two favourited rows for #36 visual snapshots.
    /// - Cosmos (abc123#0) and Night of the Living Dead (def456#0): favourited.
    /// - The General (ghi789#0): NOT favourited.
    static var previewWithFavourites: LibraryViewModel {
        let vm = previewWithData
        vm.favourites["abc123#0"] = FavouriteDTO(
            torrentID: "abc123",
            fileIndex: 0,
            favouritedAt: 1_700_000_400_000
        )
        vm.favourites["def456#0"] = FavouriteDTO(
            torrentID: "def456",
            fileIndex: 0,
            favouritedAt: 1_700_000_500_000
        )
        return vm
    }
}
