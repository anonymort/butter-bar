import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
import PlayerDomain
@testable import ButterBar

// MARK: - AudioPickerSnapshotTests
//
// Per `06-brand.md § Test obligations`. Light + dark variants for both the
// multi-track and single-track (disabled) states. Baselines committed under
// __Snapshots__/AudioPickerSnapshotTests/.
//
// CI-advisory per existing ci.yml policy.

@MainActor
final class AudioPickerSnapshotTests: XCTestCase {

    private let snapshotSize = CGSize(width: 360, height: 360)

    // MARK: - Helpers

    private func picker(tracks: [AudioTrack],
                        state: PlayerState = .playing) -> some View {
        let provider = SnapshotProvider(tracks: tracks)
        let vm = AudioPickerViewModel(provider: provider, state: state)
        return ZStack {
            BrandColors.videoLetterbox
            AudioPickerView(viewModel: vm, onDismiss: {})
                .padding(20)
        }
    }

    private func snapshot<V: View>(_ view: V,
                                   named: String,
                                   colorScheme: ColorScheme) {
        let renderer = ImageRenderer(
            content: view
                .environment(\.colorScheme, colorScheme)
                .frame(width: snapshotSize.width, height: snapshotSize.height)
        )
        renderer.proposedSize = ProposedViewSize(snapshotSize)
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            XCTFail("Could not render snapshot")
            return
        }
        assertSnapshot(
            of: NSImage(cgImage: cgImage, size: snapshotSize),
            as: .image,
            named: named
        )
    }

    // MARK: - Multi-track

    private var multiTrack: [AudioTrack] {
        [
            AudioTrack(id: "en", displayName: "English",
                       channelHint: "5.1", isCurrent: true),
            AudioTrack(id: "fr", displayName: "French",
                       channelHint: "Stereo", isCurrent: false),
            AudioTrack(id: "ja", displayName: "Japanese",
                       channelHint: nil, isCurrent: false),
        ]
    }

    func testMultiTrack_dark() {
        snapshot(picker(tracks: multiTrack),
                 named: "dark-multiTrack",
                 colorScheme: .dark)
    }

    func testMultiTrack_light() {
        snapshot(picker(tracks: multiTrack),
                 named: "light-multiTrack",
                 colorScheme: .light)
    }

    // MARK: - Single-track (calm disabled copy)

    func testSingleTrack_dark() {
        snapshot(picker(tracks: [
            AudioTrack(id: "en", displayName: "English",
                       channelHint: "Stereo", isCurrent: true)
        ]),
                 named: "dark-singleTrack",
                 colorScheme: .dark)
    }

    func testSingleTrack_light() {
        snapshot(picker(tracks: [
            AudioTrack(id: "en", displayName: "English",
                       channelHint: "Stereo", isCurrent: true)
        ]),
                 named: "light-singleTrack",
                 colorScheme: .light)
    }
}

// MARK: - Snapshot fixtures

/// Tiny provider that surfaces a fixed list and ignores selection. Selection
/// behaviour is covered by `AudioPickerViewModelTests`; this fixture exists
/// purely to drive `AudioPickerViewModel`'s composition for visual capture.
@MainActor
private final class SnapshotProvider: AudioMediaSelectionProviding {
    var options: [AudioMediaOption]
    var currentSelectionID: String?

    init(tracks: [AudioTrack]) {
        self.options = tracks.map {
            AudioMediaOption(id: $0.id,
                             displayName: $0.displayName,
                             channelHint: $0.channelHint)
        }
        self.currentSelectionID = tracks.first(where: \.isCurrent)?.id
    }

    func select(optionID: String) {
        currentSelectionID = optionID
    }
}
