/// Declares how a provider authenticates itself when contacting source APIs.
///
/// `oauth` is defined here for protocol completeness but is not implemented
/// in v1. Providers that require OAuth must declare it so the UI can gate
/// them behind a "not yet supported" message rather than silently failing.
public enum ProviderAuthModel: Sendable, Codable, Equatable {
    /// Public API — no credentials required.
    case none
    /// Static API key injected at provider initialisation time.
    case apiKey(key: String)
    /// OAuth 2 flow — v1.5+ only. `clientID` is embedded; token exchange is not implemented.
    case oauth(clientID: String)
}
