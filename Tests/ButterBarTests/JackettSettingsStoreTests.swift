import XCTest
@testable import ButterBar

final class JackettSettingsStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "JackettSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - testLoadBaseURL_returnsDefaultWhenUnset

    func testLoadBaseURL_returnsDefaultWhenUnset() {
        let store = JackettSettingsStore(defaults: defaults, keychain: FakeKeychain())
        XCTAssertEqual(store.loadBaseURL(), URL(string: "http://localhost:9117")!)
    }

    // MARK: - testSaveAndLoadBaseURL_roundTrips

    func testSaveAndLoadBaseURL_roundTrips() {
        let store = JackettSettingsStore(defaults: defaults, keychain: FakeKeychain())
        let remote = URL(string: "https://jackett.mydomain.tld:9117")!
        store.saveBaseURL(remote)
        XCTAssertEqual(store.loadBaseURL(), remote)
    }

    // MARK: - testSaveAPIKey_emptyDeletes

    func testSaveAPIKey_emptyDeletes() throws {
        let keychain = FakeKeychain()
        let store = JackettSettingsStore(defaults: defaults, keychain: keychain)

        try store.saveAPIKey("abc123")
        XCTAssertEqual(store.loadAPIKey(), "abc123")

        try store.saveAPIKey("")
        XCTAssertEqual(store.loadAPIKey(), "")
        XCTAssertTrue(keychain.deleted)
    }

    // MARK: - testLoadConfig_reflectsPersistedState

    func testLoadConfig_reflectsPersistedState() throws {
        let keychain = FakeKeychain()
        let store = JackettSettingsStore(defaults: defaults, keychain: keychain)
        store.saveBaseURL(URL(string: "http://example:9117")!)
        try store.saveAPIKey("k")

        let config = store.loadConfig()
        XCTAssertEqual(config.baseURL, URL(string: "http://example:9117")!)
        XCTAssertEqual(config.apiKey, "k")
        XCTAssertTrue(config.isEnabled)
    }

    // MARK: - testLoadConfig_emptyKeyIsDisabled

    func testLoadConfig_emptyKeyIsDisabled() {
        let store = JackettSettingsStore(defaults: defaults, keychain: FakeKeychain())
        let config = store.loadConfig()
        XCTAssertFalse(config.isEnabled)
    }
}

// MARK: - FakeKeychain

private final class FakeKeychain: KeychainAccess, @unchecked Sendable {
    private var stored: String?
    private(set) var deleted: Bool = false

    func read() throws -> String? { stored }

    func write(_ value: String) throws {
        stored = value
        deleted = false
    }

    func delete() throws {
        stored = nil
        deleted = true
    }
}
