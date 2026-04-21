import SwiftUI

@main
struct ButterBarApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            ButterBarCommands()
        }

        // Settings window — opens via ⌘, or the application menu automatically.
        Settings {
            SettingsView()
        }
    }
}
