import Foundation
import Security

// MARK: - JackettConfig

/// Snapshot of the user's Jackett provider configuration. Produced by
/// `JackettSettingsStore` at provider-registry build time.
///
/// `apiKey` is empty when the user hasn't entered one — callers should treat
/// an empty key as "provider disabled" and skip registration.
struct JackettConfig: Equatable {
    var baseURL: URL
    var apiKey: String

    static let defaultBaseURL: URL = URL(string: "http://localhost:9117")!
    static let empty = JackettConfig(baseURL: Self.defaultBaseURL, apiKey: "")

    var isEnabled: Bool { !apiKey.isEmpty }
}

// MARK: - JackettSettingsStore

/// Read/write access to the user's Jackett base URL (UserDefaults) and API
/// key (Keychain). Kept separate from any UI type so provider-registry code
/// can read without importing SwiftUI.
///
/// Not `@MainActor`: both `UserDefaults` and the `SecItem*` Keychain APIs are
/// thread-safe, and the provider registry needs to read the config during
/// property-initialiser expressions that aren't guaranteed to run on the main
/// actor.
final class JackettSettingsStore {

    static let baseURLDefaultsKey = "providers.jackett.baseURL"
    static let keychainService = "ButterBar.Jackett"
    static let keychainAccount = "apiKey"

    private let defaults: UserDefaults
    private let keychain: any KeychainAccess

    init(defaults: UserDefaults = .standard, keychain: (any KeychainAccess)? = nil) {
        self.defaults = defaults
        self.keychain = keychain ?? SystemKeychain(
            service: Self.keychainService,
            account: Self.keychainAccount
        )
    }

    /// Returns the stored base URL or the documented default
    /// (`http://localhost:9117`) when none has been set.
    func loadBaseURL() -> URL {
        if let raw = defaults.string(forKey: Self.baseURLDefaultsKey),
           let url = URL(string: raw) {
            return url
        }
        return JackettConfig.defaultBaseURL
    }

    func saveBaseURL(_ url: URL) {
        defaults.set(url.absoluteString, forKey: Self.baseURLDefaultsKey)
    }

    /// Returns the stored API key, or the empty string when none is set or
    /// the Keychain lookup fails.
    func loadAPIKey() -> String {
        (try? keychain.read()) ?? ""
    }

    /// Persists the API key to the Keychain. Passing the empty string removes
    /// the item rather than storing a zero-length secret.
    func saveAPIKey(_ key: String) throws {
        if key.isEmpty {
            try keychain.delete()
        } else {
            try keychain.write(key)
        }
    }

    /// Composite load used by `DefaultProviderRegistry` at registry build
    /// time. Reads URL + API key in a single call.
    func loadConfig() -> JackettConfig {
        JackettConfig(baseURL: loadBaseURL(), apiKey: loadAPIKey())
    }
}

// MARK: - KeychainAccess

/// Narrow Keychain abstraction so tests can inject a fake without touching
/// the real `SecItem*` APIs.
protocol KeychainAccess: Sendable {
    func read() throws -> String?
    func write(_ value: String) throws
    func delete() throws
}

/// Real `SecItem`-backed keychain store. Uses `kSecClassGenericPassword` with
/// the service/account pair supplied at init.
struct SystemKeychain: KeychainAccess {
    let service: String
    let account: String

    func read() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let s = String(data: data, encoding: .utf8) else {
                return nil
            }
            return s
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status)
        }
    }

    func write(_ value: String) throws {
        let data = Data(value.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = baseQuery
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
        default:
            throw KeychainError.osStatus(updateStatus)
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.osStatus(status)
        }
    }
}

enum KeychainError: Error, Equatable {
    case osStatus(OSStatus)
}
