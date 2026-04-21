import XCTest
import ProviderDomain
@testable import ButterBar

final class DefaultProviderRegistryTests: XCTestCase {

    // MARK: - testRegistry_withoutJackettKey_onlyRegistersBuiltIns

    func testRegistry_withoutJackettKey_onlyRegistersBuiltIns() {
        let providers = DefaultProviderRegistry.makeProviders(
            jackettConfig: JackettConfig(
                baseURL: JackettConfig.defaultBaseURL,
                apiKey: ""
            )
        )
        let names = providers.map(\.name)
        XCTAssertEqual(names, ["YTS", "EZTV"])
    }

    // MARK: - testRegistry_withJackettKey_appendsJackett

    func testRegistry_withJackettKey_appendsJackett() {
        let providers = DefaultProviderRegistry.makeProviders(
            jackettConfig: JackettConfig(
                baseURL: URL(string: "http://localhost:9117")!,
                apiKey: "my-secret"
            )
        )
        let names = providers.map(\.name)
        XCTAssertEqual(names, ["YTS", "EZTV", "Jackett"])

        // The Jackett provider declares .apiKey auth.
        guard let jackett = providers.last else { return XCTFail("Jackett missing") }
        guard case .apiKey(let key) = jackett.authModel else {
            return XCTFail("Expected .apiKey auth, got \(jackett.authModel)")
        }
        XCTAssertEqual(key, "my-secret")
    }

    // MARK: - testConfigProbeURL_includesApiKey

    @MainActor
    func testConfigProbeURL_includesApiKey() {
        let url = ProvidersSettingsViewModel.configProbeURL(
            base: URL(string: "http://localhost:9117")!,
            apiKey: "ABC"
        )
        XCTAssertEqual(url.absoluteString, "http://localhost:9117/api/v2.0/server/config?apikey=ABC")
    }
}
