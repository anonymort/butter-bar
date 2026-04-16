import Foundation
import EngineInterface

// MARK: - LibraryViewModel

/// Bridges the actor-isolated `EngineClient` to the SwiftUI main actor.
/// All published properties are updated on the main actor.
@MainActor
final class LibraryViewModel: ObservableObject {

    @Published var torrents: [TorrentSummaryDTO] = []
    @Published var loadError: String?

    private let client: EngineClient

    init(client: EngineClient) {
        self.client = client
    }

    func refresh() async {
        do {
            torrents = try await client.listTorrents()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func listFiles(torrentID: NSString) async throws -> [TorrentFileDTO] {
        try await client.listFiles(torrentID)
    }

    /// Connects the underlying `EngineClient`. Safe to call from any async context.
    func connectEngine() async {
        await client.connect()
    }
}

// MARK: - Preview factories

extension LibraryViewModel {

    /// A view model pre-populated with sample data for Xcode Previews.
    static var previewWithData: LibraryViewModel {
        let vm = LibraryViewModel(client: EngineClient())
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
    static var previewEmpty: LibraryViewModel {
        LibraryViewModel(client: EngineClient())
    }
}
