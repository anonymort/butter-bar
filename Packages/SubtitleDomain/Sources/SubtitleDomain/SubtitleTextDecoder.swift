import Foundation

/// Decodes subtitle file bytes to a `String`. Tries UTF-8 first (with
/// and without BOM), then Windows-1252, then ISO-8859-1. Binary data
/// (failing the text-likelihood heuristic) surfaces as `.decoding`.
///
/// Rationale per design doc § D2: SRT files in the wild arrive in a
/// handful of encodings; this fallback chain matches what VLC and mpv do.
/// Windows-1252 is tried before ISO-8859-1 because legacy Windows tooling
/// often tags files as Latin-1 when they actually contain CP-1252
/// smart-quote bytes.
public enum SubtitleTextDecoder {

    public static func decode(_ data: Data) -> Result<String, SubtitleLoadError> {
        // UTF-8 BOM: strip and decode.
        if hasUTF8BOM(data) {
            let stripped = data.dropFirst(3)
            if let s = String(data: stripped, encoding: .utf8) {
                return .success(s)
            }
        }
        // Plain UTF-8.
        if let s = String(data: data, encoding: .utf8) {
            return .success(s)
        }
        // UTF-8 failed. Reject obvious binary before trying 8-bit encodings,
        // because `.isoLatin1` decodes *any* byte sequence and would happily
        // turn a JPEG into a nonsense string.
        guard isLikelyText(data) else {
            return .failure(.decoding(reason: "File does not look like a text document."))
        }
        if let s = String(data: data, encoding: .windowsCP1252) {
            return .success(s)
        }
        if let s = String(data: data, encoding: .isoLatin1) {
            return .success(s)
        }
        return .failure(.decoding(reason: "File is not valid UTF-8, Windows-1252, or ISO-8859-1 text."))
    }

    /// Heuristic: data is "likely text" if NUL bytes and non-whitespace
    /// control bytes are each below 5% of the total. Conservative; allows
    /// all reasonable SRT files through while rejecting obvious binary.
    internal static func isLikelyText(_ data: Data) -> Bool {
        guard !data.isEmpty else { return true }
        var nulCount = 0
        var controlCount = 0
        for byte in data {
            if byte == 0 {
                nulCount += 1
            } else if byte < 0x09 || (byte > 0x0D && byte < 0x20) {
                controlCount += 1
            }
        }
        return nulCount * 20 < data.count && controlCount * 20 < data.count
    }

    internal static func hasUTF8BOM(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        return data[data.startIndex] == 0xEF
            && data[data.index(after: data.startIndex)] == 0xBB
            && data[data.index(data.startIndex, offsetBy: 2)] == 0xBF
    }
}
