import SwiftUI

// MARK: - Top-level Settings scene entry point

/// Root view for the Settings window (macOS Settings scene).
/// Sidebar sections match Module 7 IA from `07-product-surface.md`.
/// Glass is forbidden on content rows — only on sidebar/toolbar (automatic, per `06-brand.md`).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            AccountSettingsPane()
                .tabItem { Label("Account", systemImage: "person.circle") }
                .tag(SettingsTab.account)

            ProvidersSettingsPane()
                .tabItem { Label("Providers", systemImage: "server.rack") }
                .tag(SettingsTab.providers)

            PlaybackSettingsPane()
                .tabItem { Label("Playback", systemImage: "play.rectangle") }
                .tag(SettingsTab.playback)

            // StorageSettingsPane is defined in StorageSettingsPane.swift (issue #62).
            StorageSettingsPane()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
                .tag(SettingsTab.storage)

            AdvancedSettingsPane()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
                .tag(SettingsTab.advanced)
        }
        // Standard macOS Settings window size — wide enough for comfortable forms.
        .frame(minWidth: 520, minHeight: 360)
    }
}

// MARK: - Tab identity

private enum SettingsTab {
    case general, account, providers, playback, storage, advanced
}

// MARK: - Stub panes (non-Storage sections)

private struct GeneralSettingsPane: View {
    var body: some View {
        SettingsPlaceholder(
            icon: "gearshape",
            title: "General",
            subtitle: "General preferences will appear here."
        )
    }
}

private struct AccountSettingsPane: View {
    var body: some View {
        SettingsPlaceholder(
            icon: "person.circle",
            title: "Account",
            subtitle: "Sign in to Trakt to sync your watch history and lists."
        )
    }
}

private struct ProvidersSettingsPane: View {
    var body: some View {
        SettingsPlaceholder(
            icon: "server.rack",
            title: "Providers",
            subtitle: "Configure and prioritise torrent providers here."
        )
    }
}

private struct PlaybackSettingsPane: View {
    var body: some View {
        SettingsPlaceholder(
            icon: "play.rectangle",
            title: "Playback",
            subtitle: "Autoplay, subtitle preferences, and audio settings will appear here."
        )
    }
}

private struct AdvancedSettingsPane: View {
    var body: some View {
        SettingsPlaceholder(
            icon: "wrench.and.screwdriver",
            title: "Advanced",
            subtitle: "Diagnostic logging and debug options will appear here."
        )
    }
}

// MARK: - Shared placeholder

/// Consistent placeholder for Settings panes that are not yet implemented.
/// Matches `06-brand.md` voice: direct, no exclamation marks.
private struct SettingsPlaceholder: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(BrandColors.cocoaFaint)
            Text(title)
                .brandBodyEmphasis()
                .foregroundStyle(BrandColors.cocoa)
            Text(subtitle)
                .brandCaption()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandColors.surfaceBase)
    }
}
