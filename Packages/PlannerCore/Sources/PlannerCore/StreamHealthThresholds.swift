// StreamHealthThresholds.swift — Tuneable constants for StreamHealth tier computation.
// All thresholds in one place; do not scatter them. See spec 02.

public enum StreamHealthThresholds {
    // Buffer thresholds (seconds)
    public static let starvingBufferSeconds: Double = 10.0
    public static let marginalBufferLow: Double = 10.0
    public static let marginalBufferHigh: Double = 30.0
    public static let healthyBufferSeconds: Double = 30.0

    // Rate multiplier thresholds
    public static let healthyRateMultiplier: Double = 1.5
    public static let marginalRateMultiplier: Double = 1.5

    // Emission throttle
    public static let emitThrottleMs: Int64 = 500

    // Readahead
    public static let readaheadBytes: Int64 = 30_000_000
    public static let readaheadSecondsNormal: Double = 30.0
    public static let readaheadSecondsExtended: Double = 60.0

    // Minimum rate to use rate-based deadline spacing (100 KB/s)
    public static let minRateForSpacingBytesPerSec: Int64 = 100_000
    public static let minDeadlineSpacingMs: Int = 200
}
