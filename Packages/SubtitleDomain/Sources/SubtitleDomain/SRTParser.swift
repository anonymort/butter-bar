import CoreMedia
import Foundation

/// Parses an SRT string into `[SubtitleCue]`. Pure function — no I/O, no
/// clocks, no globals. See `docs/design/subtitle-foundation.md` § Type
/// sketch for the contract.
///
/// Recoverable syntax slips (missing index, blank trailing lines, stray
/// whitespace) are absorbed. Unrecoverable shape (no valid cues at all,
/// or a malformed timecode within a cue block) surfaces as `.decoding`.
public enum SRTParser {

    public static func parse(_ text: String) -> Result<[SubtitleCue], SubtitleLoadError> {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Split on one-or-more blank lines. Using a regex-free approach:
        // iterate the blocks by collapsing runs of blank lines.
        let blocks = splitBlocks(normalized)

        if blocks.isEmpty {
            return .success([])
        }

        var cues: [SubtitleCue] = []
        for (ordinal, block) in blocks.enumerated() {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }

            guard let headerIdx = indexOfTimecodeLine(in: lines) else {
                return .failure(.decoding(reason: "Block \(ordinal + 1) has no timecode line (no '-->' marker)."))
            }

            guard let (start, end) = parseTimecodeLine(lines[headerIdx]) else {
                return .failure(.decoding(reason: "Block \(ordinal + 1) has an invalid timecode: \(lines[headerIdx])"))
            }

            // Index line is optional. If the timecode is on line 1 (not 0),
            // line 0 is treated as the index if it's a pure integer.
            let index: Int
            if headerIdx >= 1,
               let parsed = Int(lines[0].trimmingCharacters(in: .whitespaces)) {
                index = parsed
            } else {
                index = ordinal + 1
            }

            let textLines = headerIdx + 1 < lines.count
                ? Array(lines[(headerIdx + 1)...])
                : []
            let rawText = textLines.joined(separator: "\n")
            let cleanText = Self.cleanupText(rawText)

            cues.append(SubtitleCue(
                index: index,
                startTime: start,
                endTime: end,
                text: cleanText
            ))
        }

        return .success(cues)
    }

    // MARK: - Internals (visible for tests)

    internal static func splitBlocks(_ normalized: String) -> [String] {
        var blocks: [String] = []
        var current: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !current.isEmpty {
                    blocks.append(current.joined(separator: "\n"))
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            blocks.append(current.joined(separator: "\n"))
        }
        return blocks
    }

    internal static func indexOfTimecodeLine(in lines: [String]) -> Int? {
        for (i, line) in lines.enumerated() where line.contains("-->") {
            return i
        }
        return nil
    }

    /// Parses a single timecode line like "HH:MM:SS,mmm --> HH:MM:SS,mmm".
    /// Accepts `.` as an alternative millisecond separator (seen in some
    /// wild-caught SRT files). Returns `nil` on any malformation.
    internal static func parseTimecodeLine(_ line: String) -> (CMTime, CMTime)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        let leftRaw = parts[0].trimmingCharacters(in: .whitespaces)
        // Some files append cue-position hints after the end timecode
        // (e.g. "X1:... Y1:..."). Strip anything after the first whitespace.
        let rightRaw = parts[1]
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .first ?? ""
        guard let start = parseTimecode(leftRaw),
              let end = parseTimecode(rightRaw) else {
            return nil
        }
        return (start, end)
    }

    internal static func parseTimecode(_ s: String) -> CMTime? {
        // Normalize `,` to `.` for the milliseconds separator.
        let normalized = s.replacingOccurrences(of: ",", with: ".")
        let colonParts = normalized.components(separatedBy: ":")
        guard colonParts.count == 3 else { return nil }
        guard let h = Int(colonParts[0]),
              let m = Int(colonParts[1]) else { return nil }
        let secParts = colonParts[2].components(separatedBy: ".")
        guard secParts.count == 2 else { return nil }
        guard let sec = Int(secParts[0]),
              let ms = Int(secParts[1]),
              h >= 0, m >= 0, m < 60,
              sec >= 0, sec < 60,
              ms >= 0, ms < 1000 else { return nil }
        let totalMs = Int64(h) * 3_600_000
                    + Int64(m) * 60_000
                    + Int64(sec) * 1_000
                    + Int64(ms)
        return CMTime(value: totalMs, timescale: 1_000)
    }

    /// Light tag stripping (`<i>`, `<b>`, `<u>`, case-insensitive) and
    /// entity decoding. Not a full HTML parser — SRT in the wild uses only
    /// a small vocabulary of presentational tags.
    internal static func cleanupText(_ s: String) -> String {
        let tagPatterns: [String] = [
            "<i>", "</i>", "<I>", "</I>",
            "<b>", "</b>", "<B>", "</B>",
            "<u>", "</u>", "<U>", "</U>"
        ]
        var result = s
        for tag in tagPatterns {
            result = result.replacingOccurrences(of: tag, with: "")
        }
        // Entity decoding. Order matters: `&amp;` last so a literal
        // `&amp;lt;` doesn't double-decode to `<`.
        result = result
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
