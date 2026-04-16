import Foundation

/// Single source for the "is this file complete?" rule. Both engine
/// (`CacheManager` write path) and app (`WatchStatus` derivation) consume
/// this helper to avoid drift.
///
/// The rule is `progress >= 0.95 * total` per spec 05 § Update rules. Stored
/// as integer arithmetic to avoid double-precision drift at large file sizes.
public enum WatchThreshold {
    /// `true` when `progress` is at or beyond 95% of `total`.
    /// `total <= 0` returns `false` — undefined files are never "complete."
    public static func isComplete(progress: Int64, total: Int64) -> Bool {
        guard total > 0 else { return false }
        // Integer rearrangement of `progress >= 0.95 * total`:
        //   progress * 100 >= total * 95
        // Avoids floating-point drift on multi-GB files.
        return progress.multipliedReportingOverflow(by: 100).0 >=
               total.multipliedReportingOverflow(by: 95).0
    }
}
