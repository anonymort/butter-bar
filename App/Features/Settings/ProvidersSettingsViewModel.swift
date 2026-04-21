import Foundation
import SwiftUI

// MARK: - ProvidersSettingsViewModel

/// View-model for the Jackett section of Settings > Providers.
///
/// Reads and writes through `JackettSettingsStore` so persistence (Keychain
/// for the API key, UserDefaults for the base URL) sits behind a single
/// testable seam. The `testConnection()` probe hits the Jackett
/// `/api/v2.0/server/config` endpoint; anything in the 2xx range counts as a
/// healthy instance.
@MainActor
final class ProvidersSettingsViewModel: ObservableObject {

    @Published var baseURLText: String = ""
    @Published var apiKeyText: String = ""
    @Published private(set) var status: Status?

    struct Status: Equatable {
        let message: String
        let isError: Bool
    }

    private let store: JackettSettingsStore
    private let session: URLSession

    init(
        store: JackettSettingsStore = JackettSettingsStore(),
        session: URLSession = .shared
    ) {
        self.store = store
        self.session = session
    }

    func reload() {
        baseURLText = store.loadBaseURL().absoluteString
        apiKeyText = store.loadAPIKey()
    }

    var canSave: Bool {
        URL(string: baseURLText) != nil
    }

    var canTest: Bool {
        canSave && !apiKeyText.isEmpty
    }

    func save() {
        guard let url = URL(string: baseURLText) else {
            status = Status(message: "That doesn’t look like a URL.", isError: true)
            return
        }
        store.saveBaseURL(url)
        do {
            try store.saveAPIKey(apiKeyText)
            status = Status(message: "Saved.", isError: false)
        } catch {
            status = Status(
                message: "Couldn’t save the API key to your Keychain.",
                isError: true
            )
        }
    }

    func testConnection() async {
        guard let base = URL(string: baseURLText) else {
            status = Status(message: "That doesn’t look like a URL.", isError: true)
            return
        }
        guard !apiKeyText.isEmpty else {
            status = Status(message: "Enter an API key first.", isError: true)
            return
        }

        let url = Self.configProbeURL(base: base, apiKey: apiKeyText)
        status = Status(message: "Testing…", isError: false)
        do {
            let (_, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                status = Status(message: "Connected.", isError: false)
            } else if let http = response as? HTTPURLResponse, http.statusCode == 401 || http.statusCode == 403 {
                status = Status(message: "Jackett rejected the API key.", isError: true)
            } else {
                status = Status(message: "Jackett responded with an unexpected status.", isError: true)
            }
        } catch {
            status = Status(message: "Couldn’t reach Jackett.", isError: true)
        }
    }

    /// Build the `server/config` probe URL — extracted as a static helper so
    /// tests can assert the exact shape.
    static func configProbeURL(base: URL, apiKey: String) -> URL {
        var components = URLComponents(
            url: base.appendingPathComponent("api/v2.0/server/config"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "apikey", value: apiKey)]
        return components.url!
    }
}
