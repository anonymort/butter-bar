import PlayerDomain
import SwiftUI

// MARK: - AudioPickerView
//
// Sheet/popover invoked from `PlayerOverlay`'s audio entry point (issue #23).
// Lists the available audio tracks; tap applies the change immediately and
// dismisses. Single-track assets render a calm disabled state — the entry
// point is never hidden (per AC: discoverability matters).
//
// Surface: solid `surfaceRaised` per `06-brand.md § Liquid Glass — Where glass
// is forbidden` (sheet contents are content, not floating navigation chrome).
// Brand tokens throughout — no system colours.

struct AudioPickerView: View {

    @ObservedObject var viewModel: AudioPickerViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
                .background(BrandColors.cocoaFaint.opacity(0.3))

            if viewModel.isDisabled {
                disabledState(message: "Audio selection is unavailable.")
            } else if viewModel.tracks.isEmpty {
                disabledState(message: "Only one audio track available.")
            } else {
                trackList
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
        .background(BrandColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Audio")
                .brandBodyEmphasis()
                .foregroundStyle(BrandColors.cocoa)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BrandColors.cocoaSoft)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close audio picker")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Track list

    private var trackList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(viewModel.tracks) { track in
                    AudioTrackRow(track: track) {
                        viewModel.select(track)
                        onDismiss()
                    }
                    if track.id != viewModel.tracks.last?.id {
                        Divider()
                            .background(BrandColors.cocoaFaint.opacity(0.2))
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .frame(maxHeight: 320)
    }

    // MARK: - Disabled state

    private func disabledState(message: String) -> some View {
        Text(message)
            .brandBodyRegular()
            .foregroundStyle(BrandColors.cocoaSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
    }
}

// MARK: - Row

private struct AudioTrackRow: View {

    let track: AudioTrack
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Reserve the check column even on non-current rows so labels
                // align in a single optical column.
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(track.isCurrent
                                     ? BrandColors.butterDeep
                                     : Color.clear)
                    .frame(width: 14)

                Text(track.displayName)
                    .brandBodyRegular()
                    .foregroundStyle(BrandColors.cocoa)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                if let hint = track.channelHint {
                    Text(hint)
                        .brandCaptionMonospacedNumeric()
                        .foregroundStyle(BrandColors.cocoaSoft)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(track.isCurrent ? .isSelected : [])
    }

    private var accessibilityLabel: String {
        if let hint = track.channelHint {
            return "\(track.displayName), \(hint)"
        }
        return track.displayName
    }
}

// MARK: - Previews

#Preview("Multi-track — light") {
    AudioPickerView(
        viewModel: previewViewModel(tracks: [
            AudioTrack(id: "en", displayName: "English",
                       channelHint: "5.1", isCurrent: true),
            AudioTrack(id: "fr", displayName: "French",
                       channelHint: "Stereo", isCurrent: false),
            AudioTrack(id: "ja", displayName: "Japanese",
                       channelHint: nil, isCurrent: false),
        ]),
        onDismiss: {}
    )
    .padding(40)
    .background(BrandColors.videoLetterbox)
    .preferredColorScheme(.light)
}

#Preview("Single-track — dark") {
    AudioPickerView(
        viewModel: previewViewModel(tracks: []),
        onDismiss: {}
    )
    .padding(40)
    .background(BrandColors.videoLetterbox)
    .preferredColorScheme(.dark)
}

@MainActor
private func previewViewModel(tracks: [AudioTrack]) -> AudioPickerViewModel {
    let provider = PreviewProvider(tracks: tracks)
    return AudioPickerViewModel(provider: provider, state: .playing)
}

@MainActor
private final class PreviewProvider: AudioMediaSelectionProviding {
    var options: [AudioMediaOption]
    var currentSelectionID: String?

    init(tracks: [AudioTrack]) {
        // Inject >1 entries so the view model surfaces them (single-track
        // collapses to empty per AC; the empty preview tests that path
        // explicitly).
        self.options = tracks.map {
            AudioMediaOption(id: $0.id, displayName: $0.displayName,
                             channelHint: $0.channelHint)
        }
        self.currentSelectionID = tracks.first(where: \.isCurrent)?.id
    }

    func select(optionID: String) {
        currentSelectionID = optionID
    }
}
