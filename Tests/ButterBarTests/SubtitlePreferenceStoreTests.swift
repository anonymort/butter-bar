import Foundation
import XCTest
@testable import ButterBar

// MARK: - SubtitlePreferenceStoreTests

/// Uses an isolated `UserDefaults` suite per test to avoid cross-test
/// contamination.
@MainActor
final class SubtitlePreferenceStoreTests: XCTestCase {

    private func makeStore() -> (SubtitlePreferenceStore, UserDefaults) {
        let suiteName = "SubtitlePreferenceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (SubtitlePreferenceStore(defaults: defaults), defaults)
    }

    // MARK: - Round-trips

    func testRoundTrip_BCP47() {
        let (store, _) = makeStore()
        store.save("en")
        XCTAssertEqual(store.load(), "en")
    }

    func testRoundTrip_regionTag() {
        let (store, _) = makeStore()
        store.save("pt-BR")
        XCTAssertEqual(store.load(), "pt-BR")
    }

    func testRoundTrip_off() {
        let (store, _) = makeStore()
        store.save("off")
        XCTAssertEqual(store.load(), "off")
    }

    // MARK: - Nil removes key

    func testSaveNil_removesKey() {
        let (store, defaults) = makeStore()
        store.save("en")
        store.save(nil)
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.string(forKey: SubtitlePreferenceStore.key))
    }

    // MARK: - Clear

    func testClear_removesKey() {
        let (store, defaults) = makeStore()
        store.save("de")
        store.clear()
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.string(forKey: SubtitlePreferenceStore.key))
    }

    // MARK: - Initial state

    func testInitialLoad_returnsNil() {
        let (store, _) = makeStore()
        XCTAssertNil(store.load())
    }
}
