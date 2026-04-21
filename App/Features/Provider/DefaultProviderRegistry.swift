import ProviderDomain

/// Returns the default set of providers registered for use by the pipeline.
/// The YTS provider handles movies; EZTV handles TV shows.
/// Both have `.none` auth model — no API key required.
enum DefaultProviderRegistry {
    static func makeProviders() -> [any MediaProvider] {
        [YTSProvider(), EZTVProvider()]
    }
}
