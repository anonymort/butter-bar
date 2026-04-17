import Foundation

/// Pure, deterministic parser that extracts `(title, year, season, episode,
/// release group, quality hints)` from common release filenames. Lives in
/// MetadataDomain because the matching seam ranges over its output;
/// orchestration glue (which feeds the result into a network search) lives
/// where it's first needed.
///
/// No I/O, no randomness, no clock — every input maps to exactly one output.
public enum TitleNameParser {

    public static func parse(_ name: String) -> ParsedTitle {
        // 1. Strip extension.
        var working = stripExtension(name)

        // 2. Strip wrapping brackets/parens commonly used by anime release
        // groups before they pin the actual title (e.g. "[SubsPlease]").
        let leadingGroup = extractLeadingBracketGroup(&working)

        // 3. Quality hints. Tokenise on whitespace / brackets only — keep
        // hyphens and dots inside tokens so `WEB-DL`, `H.264`, `H.265`,
        // `Blu-ray`, `H-264` survive intact. Then break each composite
        // token on dots only when it isn't itself a known quality hint
        // (so `Web-DL` stays whole but `1080p.BluRay.x264` decomposes).
        let qualityHints = extractQualityHints(rawName: working)

        // 4. Release group: the trailing `-GROUP` suffix on the original
        // filename (after extension strip), if any.
        let trailingGroup = extractTrailingGroup(working)

        // 5. Find season/episode marker. Range over the original (with
        // dot/underscore separators replaced by spaces) so we can use the
        // marker's index to cleanly split the title.
        let titleAxis = working
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")

        let seasonEpisode = findSeasonEpisode(in: titleAxis)

        // 6. Year: a 4-digit year between 1900–2099 surrounded by
        // word boundaries. If multiple, prefer one that is wrapped by `()`
        // in the original; otherwise the last one before the season/episode
        // marker; otherwise the first one.
        let year = findYear(in: titleAxis, beforeIndex: seasonEpisode?.startIndex)

        // 7. Title: everything before the earliest of (year, season/episode).
        let cutoff = earliestCutoff(year: year?.range,
                                    seasonEpisode: seasonEpisode?.startIndex,
                                    in: titleAxis)
        let rawTitle: String = {
            if let cutoff {
                return String(titleAxis[..<cutoff])
            } else {
                // No year, no S/E; strip trailing `-GROUP` if present.
                if let group = trailingGroup,
                   let dashRange = titleAxis.range(of: "-\(group)", options: .backwards) {
                    return String(titleAxis[..<dashRange.lowerBound])
                }
                return titleAxis
            }
        }()

        let title = cleanTitle(rawTitle)

        return ParsedTitle(
            title: title,
            year: year?.value,
            season: seasonEpisode?.season,
            episode: seasonEpisode?.episode,
            releaseGroup: trailingGroup ?? leadingGroup,
            qualityHints: qualityHints
        )
    }

    // MARK: - Stages

    private static func stripExtension(_ name: String) -> String {
        let knownExts: Set<String> = ["mkv", "mp4", "avi", "m4v", "mov", "wmv", "flv", "webm", "ts", "m2ts"]
        if let dot = name.lastIndex(of: "."),
           dot > name.startIndex {
            let ext = String(name[name.index(after: dot)...]).lowercased()
            if knownExts.contains(ext) {
                return String(name[..<dot])
            }
        }
        return name
    }

    private static func extractLeadingBracketGroup(_ working: inout String) -> String? {
        let trimmed = working.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") else { return nil }
        guard let close = trimmed.firstIndex(of: "]") else { return nil }
        let group = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        // Drop the bracketed prefix from `working`.
        let after = trimmed.index(after: close)
        working = String(trimmed[after...]).trimmingCharacters(in: .whitespaces)
        return group.isEmpty ? nil : group
    }

    private static func extractTrailingGroup(_ working: String) -> String? {
        // Pattern: `-GROUP` at the end where GROUP is alphanumeric / no spaces / no dots.
        // Use regex against the original (which still has dots between tokens).
        let pattern = #"-([A-Za-z0-9_]+)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(working.startIndex..., in: working)
        guard let m = regex.firstMatch(in: working, range: nsRange),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: working) else {
            return nil
        }
        let candidate = String(working[r])
        // Reject if it's clearly a quality hint, episode token, or all digits.
        if isQualityToken(candidate) { return nil }
        if isAllDigits(candidate) { return nil }
        if candidate.range(of: #"^[Ss]\d+([Ee]\d+)?$"#, options: .regularExpression) != nil { return nil }
        return candidate
    }

    private static func extractQualityHints(rawName: String) -> Set<ParsedTitle.QualityHint> {
        // First pass: split on whitespace and brackets only.
        let primary = rawName.split(whereSeparator: { c in
            c == " " || c == "_" || c == "[" || c == "]" || c == "(" || c == ")"
        }).map(String.init)

        var hints: Set<ParsedTitle.QualityHint> = []
        for primaryToken in primary {
            // If the whole composite token matches, take it.
            if let hint = qualityHint(for: primaryToken) {
                hints.insert(hint)
                continue
            }
            // Otherwise break on dots and dashes and try each subtoken.
            let subtokens = primaryToken.split(whereSeparator: { $0 == "." || $0 == "-" }).map(String.init)
            for sub in subtokens {
                if let hint = qualityHint(for: sub) {
                    hints.insert(hint)
                }
            }
            // Special: detect "H.264" / "H.265" / "WEB.DL" patterns that
            // were dot-joined. Look for adjacent `H` + `264`/`265` and
            // `WEB` + `DL` runs.
            for i in 0..<max(0, subtokens.count - 1) {
                let pair = subtokens[i] + subtokens[i + 1]
                let pairDotted = subtokens[i] + "." + subtokens[i + 1]
                let pairDashed = subtokens[i] + "-" + subtokens[i + 1]
                for candidate in [pair, pairDotted, pairDashed] {
                    if let hint = qualityHint(for: candidate) {
                        hints.insert(hint)
                    }
                }
            }
        }
        return hints
    }

    private static func qualityHint(for token: String) -> ParsedTitle.QualityHint? {
        let lower = token.lowercased()
        switch lower {
        case "480p": return .p480
        case "576p": return .p576
        case "720p": return .p720
        case "1080p": return .p1080
        case "2160p", "4k": return .p2160
        case "uhd": return .uhd
        case "bluray", "blu-ray": return .bluRay
        case "webrip": return .webRip
        case "web-dl", "webdl": return .webDL
        case "hdrip": return .hdRip
        case "dvdrip": return .dvdRip
        case "hdtv": return .hdtv
        case "remux": return .remux
        case "x264": return .x264
        case "x265": return .x265
        case "h264", "h.264": return .h264
        case "h265", "h.265": return .h265
        case "hevc": return .hevc
        case "xvid": return .xvid
        case "av1": return .av1
        case "hdr": return .hdr
        case "hdr10": return .hdr10
        case "dv": return .dolbyVision
        case "dts": return .dts
        case "ddp", "ddp5", "ddp5.1", "ddp2.0": return .ddp
        case "ac3": return .ac3
        case "atmos": return .atmos
        case "truehd": return .truehd
        default: return nil
        }
    }

    private static func isQualityToken(_ s: String) -> Bool {
        return qualityHint(for: s) != nil
    }

    private static func isAllDigits(_ s: String) -> Bool {
        return !s.isEmpty && s.allSatisfy(\.isNumber)
    }

    private struct SeasonEpisode {
        let season: Int
        let episode: Int?
        let startIndex: String.Index
    }

    private static func findSeasonEpisode(in axis: String) -> SeasonEpisode? {
        // Pattern A: SxxEyy or SxxExx-Ezz; first wins.
        let patternA = #"(?i)\bS(\d{1,2})E(\d{1,3})\b"#
        if let m = firstMatch(patternA, in: axis),
           m.numberOfRanges >= 3,
           let sR = Range(m.range(at: 1), in: axis),
           let eR = Range(m.range(at: 2), in: axis),
           let s = Int(axis[sR]),
           let e = Int(axis[eR]),
           let whole = Range(m.range, in: axis) {
            return SeasonEpisode(season: s, episode: e, startIndex: whole.lowerBound)
        }
        // Pattern B: Season-only marker, e.g. "Season 1" / "S01" without episode.
        let patternB = #"(?i)\bS(\d{2})\b"#
        if let m = firstMatch(patternB, in: axis),
           m.numberOfRanges >= 2,
           let sR = Range(m.range(at: 1), in: axis),
           let s = Int(axis[sR]),
           let whole = Range(m.range, in: axis) {
            return SeasonEpisode(season: s, episode: nil, startIndex: whole.lowerBound)
        }
        let patternC = #"(?i)\bSeason\s+(\d{1,2})\b"#
        if let m = firstMatch(patternC, in: axis),
           m.numberOfRanges >= 2,
           let sR = Range(m.range(at: 1), in: axis),
           let s = Int(axis[sR]),
           let whole = Range(m.range, in: axis) {
            return SeasonEpisode(season: s, episode: nil, startIndex: whole.lowerBound)
        }
        // Pattern D: episode-only marker for anime: " - 12" trailing the title.
        // Only treat as season=1 episode=N when there is no season marker
        // and the number is between 1 and 999 with bracketed/dashed framing.
        let patternD = #"(?<=\s-\s)(\d{1,4})(?=\s|$|\s*\[|\s*\()"#
        if let m = firstMatch(patternD, in: axis),
           m.numberOfRanges >= 2,
           let nR = Range(m.range(at: 1), in: axis),
           let n = Int(axis[nR]),
           n >= 1, n <= 9999,
           let whole = Range(m.range, in: axis) {
            // Use the position before the " - " for the title cut.
            // Walk backward 3 chars (" - ") from `whole.lowerBound`.
            let dashStart: String.Index = {
                let want = axis.index(whole.lowerBound, offsetBy: -3, limitedBy: axis.startIndex)
                return want ?? whole.lowerBound
            }()
            return SeasonEpisode(season: 1, episode: n, startIndex: dashStart)
        }
        return nil
    }

    private struct YearMatch {
        let value: Int
        let range: Range<String.Index>
    }

    private static func findYear(in axis: String, beforeIndex limit: String.Index?) -> YearMatch? {
        // Year between 1900 and 2099 surrounded by word boundaries.
        let pattern = #"(?<![\dA-Za-z])(19\d{2}|20\d{2})(?![\dA-Za-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(axis.startIndex..., in: axis)
        let matches = regex.matches(in: axis, range: nsRange)
        guard !matches.isEmpty else { return nil }

        var best: YearMatch?
        for m in matches {
            guard let r = Range(m.range(at: 1), in: axis),
                  let value = Int(axis[r]) else { continue }
            if let limit, r.lowerBound >= limit {
                continue
            }
            best = YearMatch(value: value, range: r)
        }
        if let best { return best }
        // Fallback: take the first match even if past the limit (unusual, but safer than dropping).
        guard let first = matches.first,
              let r = Range(first.range(at: 1), in: axis),
              let value = Int(axis[r]) else {
            return nil
        }
        return YearMatch(value: value, range: r)
    }

    private static func earliestCutoff(year: Range<String.Index>?,
                                       seasonEpisode: String.Index?,
                                       in axis: String) -> String.Index? {
        let candidates: [String.Index] = [year?.lowerBound, seasonEpisode].compactMap { $0 }
        return candidates.min()
    }

    private static func cleanTitle(_ raw: String) -> String {
        // Drop bracketed annotations entirely (e.g. "(2019)" leftover).
        var s = raw
        s = s.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        // Collapse repeated separators.
        s = s.replacingOccurrences(of: #"[\.\-_]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(_ pattern: String, in s: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(s.startIndex..., in: s)
        return regex.firstMatch(in: s, range: nsRange)
    }
}
