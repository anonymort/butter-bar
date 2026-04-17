import Foundation

/// Centralised access to the TMDB v4 access token used by `TMDBProvider`.
///
/// Resolution order:
///   1. `TMDB_ACCESS_TOKEN` environment variable (preferred).
///   2. `TMDBSecrets.local.swift` (gitignored) defines a
///      `TMDBSecretsLocal.token` static; this file references it via a
///      function pointer that the local file installs at process start.
///   3. Empty string. With no token, live calls fail with `.authentication`.
///
/// The local override pattern: copy
/// `TMDBSecrets.local.swift.example` → `TMDBSecrets.local.swift`, fill in
/// the token, and the gitignore rule keeps it out of the repo.
public enum TMDBSecrets {

    /// Hook the local file installs at process start. `nil` means no
    /// local override.
    nonisolated(unsafe) public static var localTokenProvider: (@Sendable () -> String)?

    public static var tmdbAccessToken: String {
        if let env = ProcessInfo.processInfo.environment["TMDB_ACCESS_TOKEN"], !env.isEmpty {
            return env
        }
        return localTokenProvider?() ?? ""
    }
}
