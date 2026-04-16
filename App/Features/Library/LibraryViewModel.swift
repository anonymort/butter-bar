import Foundation
import EngineInterface

// MARK: - LibraryViewModel

/// Bridges the actor-isolated `EngineClient` to the SwiftUI main actor.
/// All published properties are updated on the main actor.
@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var torrents: [TorrentSummaryDTO] = []
    @Published var loadError: String?

    /// Exposed so `LibraryView` can pass the client to `PlayerView` for stream lifecycle.
    let engineClient: EngineClient
    private(set) var isRefreshing: Bool = false

    /// Set `true` in preview/snapshot factory methods to prevent `.task` from
    /// firing a real `EngineClient` call and overwriting pre-populated state.
    /// For Canvas / snapshot-test use only — do not set in production code paths.
    var skipRefresh: Bool = false

    init(client: EngineClient) {
        self.engineClient = client
    }

    func start() async {
        guard !skipRefresh else { return }
        await engineClient.connect()
        await refresh()
    }

    func refresh() async {
        guard !skipRefresh else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            torrents = try await engineClient.listTorrents()
            loadError = nil
        } catch {
            loadError = "Could not load library: \(error.localizedDescription)"
        }
    }

    func listFiles(torrentID: String) async throws -> [TorrentFileDTO] {
        try await engineClient.listFiles(torrentID as NSString)
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
}
