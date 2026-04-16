import AVFoundation
import Combine
import EngineInterface
import Foundation

// MARK: - PlayerViewModel

/// Bridges `EngineClient` to the SwiftUI player view.
///
/// Owns `AVPlayer` lifetime and subscribes to `StreamHealthDTO` events
/// filtered by the active stream ID. All published properties are updated
/// on the main actor.
@MainActor
final class PlayerViewModel: ObservableObject {

    // MARK: Published

    @Published private(set) var health: StreamHealthDTO?
    @Published private(set) var error: String?

    // MARK: Internal

    /// Strong reference — released in `close()`.
    private(set) var player: AVPlayer?

    // MARK: Private

    private let streamDescriptor: StreamDescriptorDTO
    private let engineClient: EngineClient
    private var cancellables = Set<AnyCancellable>()
    private var isClosed = false

    // MARK: - Init

    init(streamDescriptor: StreamDescriptorDTO, engineClient: EngineClient) {
        self.streamDescriptor = streamDescriptor
        self.engineClient = engineClient

        guard let url = URL(string: streamDescriptor.loopbackURL as String) else {
            self.error = "Invalid stream URL: \(streamDescriptor.loopbackURL)"
            return
        }

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer

        // Resume seek if a prior byte offset was persisted.
        // AVPlayer seeks by time, not bytes — we derive approximate time
        // from the byte ratio once the asset duration is known.
        if streamDescriptor.resumeByteOffset > 0 {
            scheduleResumeSeek(player: avPlayer, item: item)
        }

        // Subscribe to health events.
        Task { await self.subscribeToHealth() }
    }

    // MARK: - Playback controls

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    /// Pauses, closes the stream with the engine, and releases the player.
    /// Safe to call multiple times — subsequent calls are no-ops.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        cancellables.removeAll()
        player?.pause()
        player = nil
        let streamID = streamDescriptor.streamID
        Task {
            try? await engineClient.closeStream(streamID)
        }
    }

    // MARK: - Private helpers

    private func subscribeToHealth() async {
        guard let events = await engineClient.events else { return }
        let targetID = streamDescriptor.streamID as String

        events.streamHealthChangedSubject
            .filter { ($0.streamID as String) == targetID }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] dto in
                self?.health = dto
            }
            .store(in: &cancellables)
    }

    /// Once the asset duration is available, seeks to the byte-ratio–derived time.
    /// This is a best-effort approximation; the planner and gateway handle actual
    /// piece scheduling from the correct offset.
    private func scheduleResumeSeek(player: AVPlayer, item: AVPlayerItem) {
        // Wait for the item to become ready so duration is valid.
        item.publisher(for: \.status)
            .filter { $0 == .readyToPlay }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak player, weak item] _ in
                guard let self,
                      let player,
                      let item,
                      item.duration.isNumeric,
                      item.duration.seconds > 0,
                      self.streamDescriptor.contentLength > 0
                else { return }

                let ratio = Double(self.streamDescriptor.resumeByteOffset)
                    / Double(self.streamDescriptor.contentLength)
                let seekSeconds = item.duration.seconds * ratio
                let seekTime = CMTime(seconds: seekSeconds, preferredTimescale: 600)
                player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 5, preferredTimescale: 600))
            }
            .store(in: &cancellables)
    }

}
