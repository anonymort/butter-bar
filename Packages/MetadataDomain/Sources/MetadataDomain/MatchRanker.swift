import Foundation

public struct RankedMatch: Equatable, Sendable {
    public let item: MediaItem
    /// Confidence in `[0, 1]`. 1 = perfect match.
    public let confidence: Double
    /// Human-readable reasons for debug + telemetry.
    public let reasons: [String]

    public init(item: MediaItem, confidence: Double, reasons: [String]) {
        self.item = item
        self.confidence = confidence
        self.reasons = reasons
    }
}

/// Pure ranker that scores a `[MediaItem]` candidate list against a
/// `ParsedTitle`. Title similarity uses Jaro-Winkler; year matches with a
/// `±1` tolerance (trailers and re-releases drift); shows are bonused when
/// the parsed input also has a season/episode marker.
///
/// The default minimum confidence threshold callers should require is
/// `MatchRanker.defaultThreshold` (`0.6`).
public enum MatchRanker {

    public static let defaultThreshold: Double = 0.6

    public static func rank(parsed: ParsedTitle,
                            candidates: [MediaItem]) -> [RankedMatch] {
        let parsedTitleNorm = normalise(parsed.title)
        return candidates.map { item in
            score(parsed: parsed,
                  parsedTitleNorm: parsedTitleNorm,
                  candidate: item)
        }.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Scoring

    private static func score(parsed: ParsedTitle,
                              parsedTitleNorm: String,
                              candidate: MediaItem) -> RankedMatch {
        let candidateTitle: String
        let candidateYear: Int?
        let candidateIsShow: Bool
        switch candidate {
        case .movie(let m):
            candidateTitle = m.title
            candidateYear = m.releaseYear
            candidateIsShow = false
        case .show(let s):
            candidateTitle = s.name
            candidateYear = s.firstAirYear
            candidateIsShow = true
        }

        var reasons: [String] = []

        // 1. Title similarity (Jaro-Winkler over normalised forms).
        let titleSim = JaroWinkler.similarity(parsedTitleNorm, normalise(candidateTitle))
        reasons.append(String(format: "title-sim=%.2f", titleSim))

        // 2. Year score: exact = 1.0, ±1 = 0.85, ±2 = 0.5, else 0.
        var yearScore: Double = 0.5  // neutral when we don't know
        if let py = parsed.year, let cy = candidateYear {
            let delta = abs(py - cy)
            switch delta {
            case 0:
                yearScore = 1.0
                reasons.append("year=exact(\(cy))")
            case 1:
                yearScore = 0.85
                reasons.append("year=±1(\(cy)≈\(py))")
            case 2:
                yearScore = 0.5
                reasons.append("year=±2(\(cy)≈\(py))")
            default:
                yearScore = 0.0
                reasons.append("year=miss(\(cy)≠\(py))")
            }
        } else if parsed.year != nil && candidateYear == nil {
            yearScore = 0.4   // candidate has no year info; mild demotion
            reasons.append("year=candidate-unknown")
        } else if parsed.year == nil {
            yearScore = 0.6   // no signal; don't penalise too hard
            reasons.append("year=parsed-unknown")
        }

        // 3. Episode-shape match: parsed has S/E and candidate is a Show, or
        // parsed has no S/E and candidate is a Movie.
        let parsedIsShowShape = parsed.season != nil || parsed.episode != nil
        var shapeScore: Double = 0.5
        if parsedIsShowShape && candidateIsShow {
            shapeScore = 1.0
            reasons.append("shape=show↔show")
        } else if !parsedIsShowShape && !candidateIsShow {
            shapeScore = 1.0
            reasons.append("shape=movie↔movie")
        } else if parsedIsShowShape && !candidateIsShow {
            shapeScore = 0.1
            reasons.append("shape=show-vs-movie")
        } else {
            // parsed is movie-shape, candidate is show — possible (anime
            // releases without S/E markers); mild demotion only.
            shapeScore = 0.4
            reasons.append("shape=movie-vs-show")
        }

        // Weighted combination. Title carries most of the signal; year and
        // shape are gates more than they are scores.
        let confidence = (titleSim * 0.65) + (yearScore * 0.20) + (shapeScore * 0.15)

        return RankedMatch(item: candidate,
                           confidence: confidence,
                           reasons: reasons)
    }

    // MARK: - Normalisation

    /// Lowercase, strip punctuation, collapse whitespace. Keeps Roman
    /// numerals as-is so that `Rocky II` ≠ `Rocky 2`.
    static func normalise(_ s: String) -> String {
        let lowered = s.lowercased()
        var stripped = ""
        stripped.reserveCapacity(lowered.count)
        for ch in lowered {
            if ch.isLetter || ch.isNumber || ch == " " {
                stripped.append(ch)
            } else {
                stripped.append(" ")
            }
        }
        // Collapse runs of whitespace.
        let collapsed = stripped
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
        return collapsed
    }
}
