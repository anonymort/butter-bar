import XCTest
import PlayerDomain
@testable import ButterBar

final class KeyboardShortcutTests: XCTestCase {
    func testShortcutsEnabledOnlyInActivePlaybackStates() {
        for shortcut in [PlayerKeyboardShortcut.playPause, .seekBackward, .seekForward, .toggleFullscreen, .escape] {
            XCTAssertTrue(shortcut.isEnabled(in: .playing))
            XCTAssertTrue(shortcut.isEnabled(in: .paused))
            XCTAssertTrue(shortcut.isEnabled(in: .buffering(reason: .engineStarving)))
            XCTAssertFalse(shortcut.isEnabled(in: .open))
            XCTAssertFalse(shortcut.isEnabled(in: .closed))
            XCTAssertFalse(shortcut.isEnabled(in: .error(.playbackFailed)))
        }
    }
}
