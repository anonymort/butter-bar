/// Injected time value for the planner — milliseconds since an arbitrary epoch.
/// The planner must never read a real clock; all time is supplied by callers.
/// Using Int64 (not ContinuousClock.Instant) keeps the type free of real-time
/// coupling, which is required for deterministic trace replay.
public typealias Instant = Int64

/// Piece availability set. Set<Int> satisfies the planner's need to check
/// membership and iterate over available pieces without requiring a Foundation
/// import in this pure-logic module. The alias keeps call sites readable and
/// leaves room to swap the backing type later without touching the protocol.
public typealias BitSet = Set<Int>
