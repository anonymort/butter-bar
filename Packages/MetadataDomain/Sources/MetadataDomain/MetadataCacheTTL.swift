import Foundation

/// Single-source TTL constants for the metadata cache.
/// Tunable, but intentionally co-located so refresh intervals don't drift
/// across the codebase. See design § D7.
public enum MetadataCacheTTL {
    public static let trendingWeek: TimeInterval = 6 * 60 * 60          // 6 h
    public static let trendingDay: TimeInterval = 1 * 60 * 60           // 1 h
    public static let popular: TimeInterval = 24 * 60 * 60              // 24 h
    public static let topRated: TimeInterval = 7 * 24 * 60 * 60         // 7 d
    public static let movieDetail: TimeInterval = 7 * 24 * 60 * 60      // 7 d
    public static let showDetail: TimeInterval = 7 * 24 * 60 * 60       // 7 d
    public static let seasonDetail: TimeInterval = 30 * 24 * 60 * 60    // 30 d
    public static let recommendations: TimeInterval = 7 * 24 * 60 * 60  // 7 d
    public static let configuration: TimeInterval = 30 * 24 * 60 * 60   // 30 d

    /// Search is interactive; freshness wins. Returning `0` signals the
    /// cache should treat search responses as never-cached.
    public static let searchMulti: TimeInterval = 0

    /// Match-result cache: parsed-name → ranked-match. Lives in the same
    /// cache layer; consulted by #17.
    public static let matchResult: TimeInterval = 30 * 24 * 60 * 60     // 30 d
}
