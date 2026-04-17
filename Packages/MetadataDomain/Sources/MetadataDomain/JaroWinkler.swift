import Foundation

/// Jaro-Winkler string similarity. Pure, deterministic, no I/O.
/// Used by `MatchRanker` to score parsed-title vs candidate-title pairs.
/// Returns a value in `[0, 1]`; 1 = exact match.
enum JaroWinkler {

    static func similarity(_ a: String, _ b: String) -> Double {
        let s1 = Array(a)
        let s2 = Array(b)
        if s1.isEmpty && s2.isEmpty { return 1.0 }
        if s1.isEmpty || s2.isEmpty { return 0.0 }

        let jaro = jaroSimilarity(s1, s2)
        if jaro < 0.7 { return jaro }

        // Common-prefix bonus, capped at 4 chars.
        var prefix = 0
        for i in 0..<min(4, min(s1.count, s2.count)) {
            if s1[i] == s2[i] { prefix += 1 } else { break }
        }
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }

    private static func jaroSimilarity(_ s1: [Character], _ s2: [Character]) -> Double {
        let len1 = s1.count
        let len2 = s2.count
        let matchDistance = max(len1, len2) / 2 - 1
        var s1Matches = [Bool](repeating: false, count: len1)
        var s2Matches = [Bool](repeating: false, count: len2)

        var matches = 0
        for i in 0..<len1 {
            let start = max(0, i - matchDistance)
            let end = min(i + matchDistance + 1, len2)
            if start >= end { continue }
            for j in start..<end where !s2Matches[j] && s1[i] == s2[j] {
                s1Matches[i] = true
                s2Matches[j] = true
                matches += 1
                break
            }
        }
        if matches == 0 { return 0.0 }

        var transpositions = 0
        var k = 0
        for i in 0..<len1 where s1Matches[i] {
            while !s2Matches[k] { k += 1 }
            if s1[i] != s2[k] { transpositions += 1 }
            k += 1
        }
        let m = Double(matches)
        return (m / Double(len1) +
                m / Double(len2) +
                (m - Double(transpositions) / 2.0) / m) / 3.0
    }
}
