import AppKit
import SwiftUI

// MARK: - ButterBarCommands

/// Native macOS menu commands for ButterBar.
///
/// Wired into `ButterBarApp` via `.commands { ButterBarCommands() }`.
///
/// Playback items are always visible but disabled when no player is open.
/// Subtitle toggle mirrors the Cmd+Shift+C shortcut standard on macOS media apps.
struct ButterBarCommands: Commands {

    // Notifies app-level handlers that the user wants to open a magnet link
    // or torrent file. Views that own the relevant sheet subscribe to these.
    static let openMagnetLinkNotification = Notification.Name("ButterBar.openMagnetLink")
    static let openTorrentFileNotification = Notification.Name("ButterBar.openTorrentFile")

    // Notifies the focused player that a menu command was triggered.
    static let playPauseNotification      = Notification.Name("ButterBar.playPause")
    static let seekBackwardNotification   = Notification.Name("ButterBar.seekBackward")
    static let seekForwardNotification    = Notification.Name("ButterBar.seekForward")
    static let toggleFullscreenNotification = Notification.Name("ButterBar.toggleFullscreen")
    static let toggleSubtitlesNotification  = Notification.Name("ButterBar.toggleSubtitles")

    var body: some Commands {
        fileMenuCommands
        playbackMenuCommands
        viewMenuCommands
    }

    // MARK: - File menu additions

    @CommandsBuilder
    private var fileMenuCommands: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Magnet Link…") {
                NotificationCenter.default.post(name: Self.openMagnetLinkNotification, object: nil)
            }
            .keyboardShortcut("u", modifiers: .command)

            Button("Open Torrent File…") {
                openTorrentFile()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
    }

    // MARK: - Playback menu (new top-level)

    @CommandsBuilder
    private var playbackMenuCommands: some Commands {
        CommandMenu("Playback") {
            // Space is handled directly by PlayerView via .onKeyPress while
            // the player has keyboard focus. The menu item is present for
            // discoverability; Cmd+P provides a menu-safe equivalent.
            Button("Play/Pause") {
                NotificationCenter.default.post(name: Self.playPauseNotification, object: nil)
            }
            .keyboardShortcut("p", modifiers: .command)

            Divider()

            Button("Seek Backward 10 Seconds") {
                NotificationCenter.default.post(name: Self.seekBackwardNotification, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)

            Button("Seek Forward 10 Seconds") {
                NotificationCenter.default.post(name: Self.seekForwardNotification, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)

            Divider()

            Button("Toggle Full Screen") {
                NotificationCenter.default.post(name: Self.toggleFullscreenNotification, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }

    // MARK: - View menu additions

    @CommandsBuilder
    private var viewMenuCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Toggle Subtitles") {
                NotificationCenter.default.post(name: Self.toggleSubtitlesNotification, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }

    // MARK: - Helpers

    private func openTorrentFile() {
        let panel = NSOpenPanel()
        panel.title = "Open Torrent File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "torrent") ?? .data]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            NotificationCenter.default.post(
                name: Self.openTorrentFileNotification,
                object: url
            )
        }
    }
}
