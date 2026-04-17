import Foundation
import SubtitleDomain
import UniformTypeIdentifiers

// MARK: - SubtitleIngestor

/// Pure-function SRT ingestion pipeline. Takes an `NSItemProvider` (from a
/// drag-and-drop) and returns a `SubtitleTrack` or a `SubtitleLoadError`.
///
/// Pipeline (design doc § Ingestion pipeline):
/// 1. Resolve file URL from the provider (reject non-.srt extension).
/// 2. Read data from the URL (.fileUnavailable on failure).
/// 3. Decode text via `SubtitleTextDecoder` (.decoding on failure).
/// 4. Parse SRT via `SRTParser` (.decoding on failure).
/// 5. Sniff BCP-47 language from the filename token before ".srt".
/// 6. Build and return a `.sidecar` `SubtitleTrack`.
enum SubtitleIngestor {

    static func ingest(from itemProvider: NSItemProvider) async -> Result<SubtitleTrack, SubtitleLoadError> {
        // Step 1 — resolve file URL
        let urlResult = await resolveURL(from: itemProvider)
        guard case .success(let url) = urlResult else {
            if case .failure(let error) = urlResult { return .failure(error) }
            return .failure(.fileUnavailable(reason: "Could not resolve URL"))
        }

        // Reject non-.srt extensions
        guard url.pathExtension.lowercased() == "srt" else {
            return .failure(.unsupportedFormat(reason: "Extension '\(url.pathExtension)' is not supported. Only .srt is supported in v1."))
        }

        // Step 2 — read data
        guard let data = try? Data(contentsOf: url) else {
            return .failure(.fileUnavailable(reason: "Could not read file at \(url.lastPathComponent)"))
        }

        // Step 3 — decode text
        let decodeResult = SubtitleTextDecoder.decode(data)
        guard case .success(let text) = decodeResult else {
            if case .failure(let error) = decodeResult { return .failure(error) }
            return .failure(.decoding(reason: "Decoding failed for \(url.lastPathComponent)"))
        }

        // Step 4 — parse SRT
        let parseResult = SRTParser.parse(text)
        guard case .success(let cues) = parseResult else {
            if case .failure(let error) = parseResult { return .failure(error) }
            return .failure(.decoding(reason: "Parsing failed for \(url.lastPathComponent)"))
        }

        // Step 5 — sniff language from filename
        let language = sniffLanguage(from: url.lastPathComponent)

        // Step 6 — build track
        let track = SubtitleTrack(
            id: "sidecar-\(UUID().uuidString)",
            source: .sidecar(url: url, format: .srt, cues: cues),
            language: language,
            label: url.deletingPathExtension().lastPathComponent
        )
        return .success(track)
    }

    // MARK: - Private helpers

    /// Resolves a file URL from the item provider using a checked continuation.
    private static func resolveURL(from provider: NSItemProvider) async -> Result<URL, SubtitleLoadError> {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let url {
                    continuation.resume(returning: .success(url))
                } else {
                    let reason = error?.localizedDescription ?? "Unknown error"
                    continuation.resume(returning: .failure(.fileUnavailable(reason: reason)))
                }
            }
        }
    }

    /// Regex: `^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$`
    /// Matches the dot-delimited token immediately before `.srt`.
    ///
    /// Examples:
    ///   `Movie.en.srt`      → `"en"`
    ///   `Movie.pt-BR.srt`   → `"pt-BR"`
    ///   `Movie.srt`         → `nil`
    ///   `Movie.English.srt` → `nil` (4+ letters in primary = fails 2–3 rule)
    ///   `Movie.zh-Hans.srt` → `"zh-Hans"`
    static func sniffLanguage(from filename: String) -> String? {
        // Remove .srt extension, then get the last dot-separated component.
        let withoutExtension: String
        if filename.lowercased().hasSuffix(".srt") {
            withoutExtension = String(filename.dropLast(4))
        } else {
            return nil
        }
        let components = withoutExtension.split(separator: ".", omittingEmptySubsequences: true)
        guard let lastComponent = components.last else { return nil }
        let token = String(lastComponent)
        let pattern = #"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)) != nil else {
            return nil
        }
        return token
    }
}
