import ProviderDomain

/// Returns the default set of providers registered for use by the pipeline.
/// The YTS provider handles movies; EZTV handles TV shows. Both have `.none`
/// auth model — no API key required.
///
/// Jackett is registered only when the user has supplied a non-empty API
/// key in Settings > Providers (base URL + key read via
/// `JackettSettingsStore`). Call sites that don't touch the main actor pass
/// in a pre-loaded `JackettConfig`; the main-actor entry point reads it
/// from Keychain/UserDefaults automatically.
enum DefaultProviderRegistry {
    /// Convenience entry point. Reads Jackett config from
    /// `JackettSettingsStore` and composes the provider list. Runs wherever
    /// the app bootstrap initialises the pipeline — both `UserDefaults` and
    /// Keychain APIs used underneath are thread-safe.
    static func makeProviders() -> [any MediaProvider] {
        makeProviders(jackettConfig: JackettSettingsStore().loadConfig())
    }

    /// Pure function used by tests and by the `@MainActor` entry point.
    /// Takes an already-resolved Jackett config so it can run off the main
    /// actor.
    static func makeProviders(jackettConfig: JackettConfig) -> [any MediaProvider] {
        var providers: [any MediaProvider] = [YTSProvider(), EZTVProvider()]
        if jackettConfig.isEnabled {
            providers.append(JackettProvider(
                baseURL: jackettConfig.baseURL,
                apiKey: jackettConfig.apiKey
            ))
        }
        return providers
    }
}
