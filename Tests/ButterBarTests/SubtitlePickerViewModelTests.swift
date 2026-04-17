import CoreMedia
import SubtitleDomain
import XCTest
import PlayerDomain
@testable import ButterBar

@MainActor
final class SubtitlePickerViewModelTests: XCTestCase {
    func testRowsGroupedBySourceWithHumanLanguageLabels() {
        let controller = SubtitleController(preferenceStore: store())
        let embedded = track(id: "embedded-en", source: .embedded(identifier: "en"), language: "en", label: "English")
        let sidecar = track(id: "sidecar-fr", source: sidecarSource(), language: "fr", label: "French")
        controller._setTracksForTesting([embedded, sidecar], selection: sidecar)

        let vm = SubtitlePickerViewModel(controller: controller, state: .playing)

        XCTAssertEqual(vm.embeddedRows.map(\.sourceLabel), ["Embedded"])
        XCTAssertEqual(vm.sidecarRows.map(\.sourceLabel), ["Sidecar"])
        XCTAssertEqual(vm.embeddedRows.first?.languageLabel, "English")
        XCTAssertEqual(vm.sidecarRows.first?.languageLabel, "French")
        XCTAssertFalse(vm.isOffSelected)
        XCTAssertTrue(vm.sidecarRows.first?.isCurrent == true)
    }

    func testSelectOffPersistsOff() {
        let defaults = UserDefaults(suiteName: "SubtitlePicker-\(UUID().uuidString)")!
        let controller = SubtitleController(preferenceStore: SubtitlePreferenceStore(defaults: defaults))
        let sidecar = track(id: "sidecar-es", source: sidecarSource(), language: "es", label: "Spanish")
        controller._setTracksForTesting([sidecar], selection: sidecar)
        let vm = SubtitlePickerViewModel(controller: controller, state: .playing)

        vm.selectOff()

        XCTAssertNil(controller.selection)
        XCTAssertEqual(defaults.string(forKey: SubtitlePreferenceStore.key), "off")
    }

    func testDisabledInTerminalStates() {
        let controller = SubtitleController(preferenceStore: store())
        XCTAssertTrue(SubtitlePickerViewModel(controller: controller, state: .closed).isDisabled)
        XCTAssertTrue(SubtitlePickerViewModel(controller: controller, state: .error(.playbackFailed)).isDisabled)
        XCTAssertFalse(SubtitlePickerViewModel(controller: controller, state: .paused).isDisabled)
    }

    private func store() -> SubtitlePreferenceStore {
        SubtitlePreferenceStore(defaults: UserDefaults(suiteName: "SubtitlePicker-\(UUID().uuidString)")!)
    }

    private func track(id: String, source: SubtitleSource, language: String?, label: String) -> SubtitleTrack {
        SubtitleTrack(id: id, source: source, language: language, label: label)
    }

    private func sidecarSource() -> SubtitleSource {
        .sidecar(url: URL(fileURLWithPath: "/tmp/test.srt"), format: .srt,
                 cues: [SubtitleCue(index: 1, startTime: .zero,
                                    endTime: CMTime(seconds: 10, preferredTimescale: 600),
                                    text: "Test")])
    }
}
