import Foundation
import Combine
import EngineInterface
import LibraryDomain

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

    /// Exposed so `LibraryView` can pass the client to `PlayerView` for stream lifecycle.
    let engineClient: EngineClient
    private(set) var isRefreshing: Bool = false

    /// Set `true` in preview/snapshot factory methods to prevent `.task` from
    /// firing a real `EngineClient` call and overwriting pre-populated state.
    /// For Canvas / snapshot-test use only — do not set in production code paths.
    var skipRefresh: Bool = false

    private var cancellables: Set<AnyCancellable> = []

    init(client: EngineClient) {
        self.engineClient = client
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
            loadError = nil
        } catch {
            loadError = "Could not load library: \(error.localizedDescription)"
        }
    }

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

    // MARK: - Helpers

    /// Stable composite key for `(torrentID, fileIndex)`.
    static func key(for torrentID: String, fileIndex: Int) -> String {
        "\(torrentID)#\(fileIndex)"
    }

    /// Subscribe to engine `playbackHistoryChanged` events. Updates the
    /// `playbackHistory` map on the main actor; SwiftUI re-renders affected rows.
    private func subscribeToPlaybackHistoryChanges() async {
        guard let events = await engineClient.events else { return }
        events.playbackHistoryChangedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dto in
                guard let self else { return }
                let key = Self.key(for: dto.torrentID as String, fileIndex: Int(dto.fileIndex))
                self.playbackHistory[key] = dto
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
}
