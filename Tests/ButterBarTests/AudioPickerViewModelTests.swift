import XCTest
import PlayerDomain
@testable import ButterBar

// MARK: - AudioPickerViewModelTests
//
// Pure unit tests for `AudioPickerViewModel`. AVPlayerItem can't be cleanly
// constructed without a real asset, so the view model depends on a small
// protocol seam (`AudioMediaSelectionProviding`) that production wires to
// `AVPlayerItem` and tests substitute with a fake.
//
// AC coverage (issue #23):
// - List composition from the underlying selection group.
// - `select(_:)` applies the change to the underlying group.
// - Single-track assets surface as an empty `tracks` list (the picker view
//   then renders the disabled "Only one audio track available" copy).
// - `isDisabled` reflects PlayerState — true for `.closed`/`.error(_)`,
//   false otherwise.

@MainActor
final class AudioPickerViewModelTests: XCTestCase {

    // MARK: - List composition

    func testTracks_multiTrack_listsAllOptionsWithCurrentMarked() {
        let provider = FakeAudioProvider(
            options: [
                FakeAudioOption(id: "en", displayName: "English",
                                channelHint: "5.1"),
                FakeAudioOption(id: "fr", displayName: "French",
                                channelHint: "Stereo"),
                FakeAudioOption(id: "ja", displayName: "Japanese",
                                channelHint: nil),
            ],
            selectedID: "en"
        )
        let vm = AudioPickerViewModel(provider: provider, state: .playing)

        XCTAssertEqual(vm.tracks.count, 3)
        XCTAssertEqual(vm.tracks[0].id, "en")
        XCTAssertEqual(vm.tracks[0].displayName, "English")
        XCTAssertEqual(vm.tracks[0].channelHint, "5.1")
        XCTAssertTrue(vm.tracks[0].isCurrent)

        XCTAssertEqual(vm.tracks[1].id, "fr")
        XCTAssertEqual(vm.tracks[1].channelHint, "Stereo")
        XCTAssertFalse(vm.tracks[1].isCurrent)

        XCTAssertNil(vm.tracks[2].channelHint)
        XCTAssertFalse(vm.tracks[2].isCurrent)
    }

    func testTracks_noProvider_isEmpty() {
        // No AVPlayerItem yet (e.g. .closed before player constructed).
        let vm = AudioPickerViewModel(provider: nil, state: .closed)
        XCTAssertTrue(vm.tracks.isEmpty)
    }

    // MARK: - Single-track behaviour

    func testTracks_singleTrack_isEmpty_perAC() {
        // Per AC: "Single-track assets: empty list / disabled state — no 'Off'
        // entry." The view model surfaces an empty list; the view renders the
        // calm copy.
        let provider = FakeAudioProvider(
            options: [FakeAudioOption(id: "en", displayName: "English",
                                      channelHint: "Stereo")],
            selectedID: "en"
        )
        let vm = AudioPickerViewModel(provider: provider, state: .playing)
        XCTAssertTrue(vm.tracks.isEmpty,
                      "Single-track assets should surface as empty tracks; " +
                      "the view renders the disabled state.")
    }

    // MARK: - Selection

    func testSelect_appliesChangeToUnderlyingGroup() {
        let provider = FakeAudioProvider(
            options: [
                FakeAudioOption(id: "en", displayName: "English",
                                channelHint: "5.1"),
                FakeAudioOption(id: "fr", displayName: "French",
                                channelHint: "Stereo"),
            ],
            selectedID: "en"
        )
        let vm = AudioPickerViewModel(provider: provider, state: .playing)

        let target = vm.tracks.first(where: { $0.id == "fr" })!
        vm.select(target)

        XCTAssertEqual(provider.selectedID, "fr")
    }

    func testSelect_refreshesIsCurrentFlag() {
        let provider = FakeAudioProvider(
            options: [
                FakeAudioOption(id: "en", displayName: "English",
                                channelHint: nil),
                FakeAudioOption(id: "fr", displayName: "French",
                                channelHint: nil),
            ],
            selectedID: "en"
        )
        let vm = AudioPickerViewModel(provider: provider, state: .playing)

        let fr = vm.tracks.first(where: { $0.id == "fr" })!
        vm.select(fr)

        // After selection the published list should reflect the new current.
        XCTAssertTrue(vm.tracks.first(where: { $0.id == "fr" })!.isCurrent)
        XCTAssertFalse(vm.tracks.first(where: { $0.id == "en" })!.isCurrent)
    }

    // MARK: - State integration

    func testIsDisabled_trueWhenClosed() {
        let provider = FakeAudioProvider(
            options: [
                FakeAudioOption(id: "en", displayName: "English",
                                channelHint: nil),
                FakeAudioOption(id: "fr", displayName: "French",
                                channelHint: nil),
            ],
            selectedID: "en"
        )
        let vm = AudioPickerViewModel(provider: provider, state: .closed)
        XCTAssertTrue(vm.isDisabled)
    }

    func testIsDisabled_trueWhenError() {
        let provider = FakeAudioProvider(
            options: [
                FakeAudioOption(id: "en", displayName: "English",
                                channelHint: nil),
                FakeAudioOption(id: "fr", displayName: "French",
                                channelHint: nil),
            ],
            selectedID: "en"
        )
        let vm = AudioPickerViewModel(provider: provider,
                                      state: .error(.playbackFailed))
        XCTAssertTrue(vm.isDisabled)
    }

    func testIsDisabled_falseInActiveStates() {
        let provider = FakeAudioProvider(
            options: [
                FakeAudioOption(id: "en", displayName: "English",
                                channelHint: nil),
                FakeAudioOption(id: "fr", displayName: "French",
                                channelHint: nil),
            ],
            selectedID: "en"
        )
        for state: PlayerState in [
            .open,
            .playing,
            .paused,
            .buffering(reason: .openingStream),
            .buffering(reason: .engineStarving),
            .buffering(reason: .playerRebuffering),
        ] {
            let vm = AudioPickerViewModel(provider: provider, state: state)
            XCTAssertFalse(vm.isDisabled,
                           "Picker should be enabled in \(state)")
        }
    }
}

// MARK: - Test fakes

/// Minimal in-memory implementation of `AudioMediaSelectionProviding` for tests.
/// Mirrors what `AVPlayerItem.AudioSelectionProvider` does in production.
@MainActor
private final class FakeAudioProvider: AudioMediaSelectionProviding {
    var options: [AudioMediaOption]
    var selectedID: String?

    init(options: [FakeAudioOption], selectedID: String?) {
        self.options = options.map { AudioMediaOption(
            id: $0.id, displayName: $0.displayName, channelHint: $0.channelHint
        )}
        self.selectedID = selectedID
    }

    var currentSelectionID: String? { selectedID }

    func select(optionID: String) {
        guard options.contains(where: { $0.id == optionID }) else { return }
        selectedID = optionID
    }
}

private struct FakeAudioOption {
    let id: String
    let displayName: String
    let channelHint: String?
}
