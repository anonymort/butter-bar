import SwiftUI

// MARK: - Providers pane (issue #179)

/// Settings > Providers.
///
/// Currently surfaces only Jackett configuration (base URL + API key +
/// test-connection). YTS and EZTV require no user-facing config and are
/// therefore not listed here.
struct ProvidersSettingsPane: View {

    @StateObject private var viewModel: ProvidersSettingsViewModel

    init(viewModel: ProvidersSettingsViewModel = ProvidersSettingsViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Base URL") {
                    TextField(
                        "http://localhost:9117",
                        text: $viewModel.baseURLText
                    )
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .autocorrectionDisabled(true)
                    .frame(maxWidth: 260)
                }

                LabeledContent("API key") {
                    SecureField("Paste your Jackett API key", text: $viewModel.apiKeyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }

                LabeledContent("") {
                    HStack(spacing: 8) {
                        Button("Save") { viewModel.save() }
                            .disabled(!viewModel.canSave)

                        Button("Test connection") {
                            Task { await viewModel.testConnection() }
                        }
                        .disabled(!viewModel.canTest)

                        if let status = viewModel.status {
                            Text(status.message)
                                .brandCaption()
                                .foregroundStyle(status.isError ? Color.red : BrandColors.cocoaSoft)
                        }
                    }
                }
            } header: {
                Text("Jackett")
            } footer: {
                // Voice: direct, explanatory. No exclamation marks (06-brand.md).
                Text("Jackett is a self-hosted torrent proxy that aggregates indexers via Torznab. Leave the API key empty to disable Jackett entirely.")
                    .brandCaption()
                    .foregroundStyle(BrandColors.cocoaSoft)
            }
        }
        .formStyle(.grouped)
        .background(BrandColors.surfaceBase)
        .onAppear { viewModel.reload() }
    }
}
