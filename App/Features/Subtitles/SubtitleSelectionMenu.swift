import Combine
import PlayerDomain
import SubtitleDomain
import SwiftUI

struct SubtitlePickerTrackRow: Identifiable, Equatable {
    let id: String
    let track: SubtitleTrack
    let languageLabel: String
    let sourceLabel: String
    let isCurrent: Bool
}

@MainActor
final class SubtitlePickerViewModel: ObservableObject {
    @Published private(set) var embeddedRows: [SubtitlePickerTrackRow] = []
    @Published private(set) var sidecarRows: [SubtitlePickerTrackRow] = []
    @Published private(set) var isOffSelected: Bool = true

    let isDisabled: Bool

    private let controller: SubtitleController
    private var cancellables = Set<AnyCancellable>()

    init(controller: SubtitleController, state: PlayerState) {
        self.controller = controller
        self.isDisabled = Self.disabled(in: state)
        refresh()
        controller.$tracks
            .combineLatest(controller.$selection)
            .sink { [weak self] _, _ in self?.refresh() }
            .store(in: &cancellables)
    }

    var isEmpty: Bool {
        embeddedRows.isEmpty && sidecarRows.isEmpty
    }

    func selectOff() {
        guard !isDisabled else { return }
        controller.selectTrack(nil)
        refresh()
    }

    func select(_ row: SubtitlePickerTrackRow) {
        guard !isDisabled else { return }
        controller.selectTrack(row.track)
        refresh()
    }

    private func refresh() {
        let selectionID = controller.selection?.id
        isOffSelected = selectionID == nil
        embeddedRows = rows(for: controller.tracks.filter {
            if case .embedded = $0.source { return true }
            return false
        }, sourceLabel: "Embedded", selectionID: selectionID)
        sidecarRows = rows(for: controller.tracks.filter {
            if case .sidecar = $0.source { return true }
            return false
        }, sourceLabel: "Sidecar", selectionID: selectionID)
    }

    private func rows(for tracks: [SubtitleTrack],
                      sourceLabel: String,
                      selectionID: String?) -> [SubtitlePickerTrackRow] {
        tracks.map { track in
            SubtitlePickerTrackRow(
                id: track.id,
                track: track,
                languageLabel: Self.languageLabel(for: track),
                sourceLabel: sourceLabel,
                isCurrent: track.id == selectionID
            )
        }
    }

    private static func disabled(in state: PlayerState) -> Bool {
        switch state {
        case .closed, .error:
            return true
        case .open, .playing, .paused, .buffering:
            return false
        }
    }

    private static func languageLabel(for track: SubtitleTrack) -> String {
        guard let language = track.language,
              let code = language.split(separator: "-").first else {
            return track.label
        }
        let languageCode = String(code)
        let locale = Locale.current
        if let name = locale.localizedString(forLanguageCode: languageCode), !name.isEmpty {
            return name.capitalized(with: locale)
        }
        return track.label
    }
}

struct SubtitlePickerView: View {
    @ObservedObject var viewModel: SubtitlePickerViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(BrandColors.cocoaFaint.opacity(0.3))

            if viewModel.isDisabled {
                disabledState("Subtitle selection is unavailable.")
            } else if viewModel.isEmpty {
                disabledState("No subtitles available.")
            } else {
                trackList
            }
        }
        .frame(minWidth: 300, idealWidth: 340)
        .background(BrandColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack {
            Text("Subtitles")
                .brandBodyEmphasis()
                .foregroundStyle(BrandColors.cocoa)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(BrandTypography.caption)
                    .foregroundStyle(BrandColors.cocoaSoft)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close subtitle picker")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var trackList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SubtitlePickerOffRow(isCurrent: viewModel.isOffSelected) {
                    viewModel.selectOff()
                    onDismiss()
                }

                if !viewModel.embeddedRows.isEmpty {
                    groupTitle("Embedded")
                    ForEach(viewModel.embeddedRows) { row in
                        SubtitlePickerTrackButton(row: row) {
                            viewModel.select(row)
                            onDismiss()
                        }
                    }
                }

                if !viewModel.sidecarRows.isEmpty {
                    groupTitle("Sidecar")
                    ForEach(viewModel.sidecarRows) { row in
                        SubtitlePickerTrackButton(row: row) {
                            viewModel.select(row)
                            onDismiss()
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 360)
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title)
            .brandCaption()
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func disabledState(_ message: String) -> some View {
        Text(message)
            .brandBodyRegular()
            .foregroundStyle(BrandColors.cocoaSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
    }
}

private struct SubtitlePickerOffRow: View {
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                checkmark(isCurrent)
                Text("Off")
                    .brandBodyRegular()
                    .foregroundStyle(BrandColors.cocoa)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

private struct SubtitlePickerTrackButton: View {
    let row: SubtitlePickerTrackRow
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                checkmark(row.isCurrent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.languageLabel)
                        .brandBodyRegular()
                        .foregroundStyle(BrandColors.cocoa)
                        .lineLimit(1)
                    Text(row.sourceLabel)
                        .brandCaption()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(row.isCurrent ? .isSelected : [])
    }
}

private func checkmark(_ visible: Bool) -> some View {
    Image(systemName: "checkmark")
        .font(BrandTypography.caption)
        .foregroundStyle(visible ? BrandColors.butterDeep : BrandColors.cocoa.opacity(0))
        .frame(width: 14)
}


// Compatibility surface kept for the existing snapshot suite while production
// chrome uses `SubtitlePickerView` via the PlayerView sheet.
struct SubtitleSelectionMenu: View {
    @ObservedObject var controller: SubtitleController

    var body: some View {
        Menu {
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
                Text(track.label)
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
}
