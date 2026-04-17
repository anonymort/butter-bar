import SubtitleDomain
import SwiftUI

// MARK: - SubtitleSelectionMenu

/// HUD menu button for subtitle track selection.
///
/// Groups embedded tracks first, then sidecar tracks. A checkmark marks the
/// active selection. "Off" deactivates subtitles.
///
/// Placed inside the player HUD vstack alongside `StreamHealthHUD`.
struct SubtitleSelectionMenu: View {

    @ObservedObject var controller: SubtitleController

    var body: some View {
        Menu {
            // "Off" option
            Button {
                controller.selectTrack(nil)
            } label: {
                Label(
                    "Off",
                    systemImage: controller.selection == nil ? "checkmark" : ""
                )
            }

            let embedded = embeddedTracks
            let sidecars = sidecarTracks

            if !embedded.isEmpty {
                Divider()
                Section("Embedded") {
                    ForEach(embedded) { track in
                        trackButton(track)
                    }
                }
            }

            if !sidecars.isEmpty {
                Divider()
                Section("Subtitles") {
                    ForEach(sidecars) { track in
                        trackButton(track)
                    }
                }
            }
        } label: {
            Label("Subtitles", systemImage: "captions.bubble")
                .brandCaption()
                .foregroundStyle(BrandColors.cocoaFaint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: - Private

    private var embeddedTracks: [SubtitleTrack] {
        controller.tracks.filter {
            if case .embedded = $0.source { return true }
            return false
        }
    }

    private var sidecarTracks: [SubtitleTrack] {
        controller.tracks.filter {
            if case .sidecar = $0.source { return true }
            return false
        }
    }

    @ViewBuilder
    private func trackButton(_ track: SubtitleTrack) -> some View {
        Button {
            controller.selectTrack(track)
        } label: {
            HStack {
                Text(rowLabel(for: track))
                if let lang = track.language {
                    Text("(\(lang))")
                        .brandCaption()
                        .foregroundStyle(BrandColors.cocoaSoft)
                }
            }
        }
        .overlay(alignment: .leading) {
            if controller.selection?.id == track.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(BrandColors.butter)
            }
        }
    }

    private func rowLabel(for track: SubtitleTrack) -> String {
        track.label
    }
}
