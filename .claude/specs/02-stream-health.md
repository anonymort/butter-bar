# 02 — StreamHealth (canonical)

> **Revision 3** — UI rendering contract now points at `06-brand.md` § Tier colours for the tier→colour mapping (addendum A16). Rev 2 named throttle state ownership explicitly (addendum A9) and marked container-metadata bitrate inference as v1.5+ (addendum A10). Baseline revision was rev 1.

`StreamHealth` is the single operational metric shared between the planner and the UI. The UI may decorate it (colours, labels, animations) but must not reinterpret the tiers or recompute them from the raw fields.

## Type

```swift
public struct StreamHealth: Sendable, Hashable, Codable {
    public let secondsBufferedAhead: Double
    public let downloadRateBytesPerSec: Int64
    public let requiredBitrateBytesPerSec: Int64?   // nil until inferred or probed
    public let peerCount: Int
    public let outstandingCriticalPieces: Int
    public let recentStallCount: Int
    public let tier: Tier

    public enum Tier: String, Sendable, Codable {
        case healthy
        case marginal
        case starving
    }
}
```

## Tier semantics (v1 thresholds)

Thresholds are tuneable constants in one file (`StreamHealthThresholds.swift`). Do not scatter them.

- **healthy** — all of the following:
  - `secondsBufferedAhead >= 30`, and
  - either `requiredBitrateBytesPerSec == nil` or `downloadRateBytesPerSec >= 1.5 * requiredBitrateBytesPerSec`, and
  - `outstandingCriticalPieces == 0`.

- **marginal** — not starving, and any of:
  - `10 <= secondsBufferedAhead < 30`, or
  - `requiredBitrateBytesPerSec != nil && downloadRateBytesPerSec < 1.5 * requiredBitrateBytesPerSec && downloadRateBytesPerSec >= requiredBitrateBytesPerSec`.

- **starving** — any of:
  - `secondsBufferedAhead < 10`, or
  - `requiredBitrateBytesPerSec != nil && downloadRateBytesPerSec < requiredBitrateBytesPerSec`, or
  - `outstandingCriticalPieces > 0` for the current read window.

Precedence: starving wins over marginal wins over healthy. Evaluate in that order.

## Required bitrate inference

`requiredBitrateBytesPerSec` starts `nil` and becomes non-nil once one of these happens:

1. *(v1.5+)* The asset's container declares an overall bitrate the gateway can read cheaply (MP4 `mvhd` / Matroska `Duration` + file size). **Not implemented in v1.** The code path exists but is never reached.
2. *(v1)* The planner has observed ≥ 60 seconds of continuous successful playback and can compute `bytes_served / seconds_elapsed`.

If neither is available, leave it `nil` and let the tier logic fall through to the buffer-based rules. In practice v1 streams run with `requiredBitrateBytesPerSec == nil` for their first 60 seconds, which is acceptable because the buffer-based thresholds still work.

## Emission rules

- **Owner:** the `PiecePlanner` instance owns throttle state (last emission time, last emitted tier). This is consistent with the planner being a deterministic state machine — see `00-addendum.md` A3 and A9.
- Planner emits `StreamHealth` on every state change that affects any field, throttled to at most 2 Hz.
- On tier transition, emit immediately regardless of throttle.
- Engine forwards to app via `EngineEvents.streamHealthChanged(_:)`.

## UI rendering contract

UI may:

- Render tier colours per the fixed mapping in `06-brand.md` § Tier colours. The mapping is `healthy → tierHealthy`, `marginal → tierMarginal`, `starving → tierStarving`. UI may not introduce new tier colours or substitute different tokens.
- Show `secondsBufferedAhead` as "X s ready" or similar, using the monospaced numeral style from `06-brand.md` § Typography.
- Show `peerCount` and `downloadRateBytesPerSec` as secondary stats in `cocoaSoft`.
- Animate transitions per `06-brand.md` § Motion (400 ms cross-fade between tier colours).

UI may **not**:

- Compute its own tier.
- Show a different health state from `tier`.
- Hide the tier when starving (the user has to know).
- Use system green/yellow/red — these break the warm palette. Use the brand tier colours.
- Communicate tier through colour alone — every tier indicator must be paired with a text label so the signal is not lost for users with colour vision deficiency.

## Test obligations

- Unit tests for tier computation covering every boundary condition in both directions.
- Snapshot test for the throttle (2 Hz cap, immediate emit on tier change).
- Codable round-trip test for `StreamHealth` itself (useful for persistence, debugging, and for the DTO mapping layer). Note: `StreamHealth` does not cross XPC directly — `StreamHealthDTO` does — but the round-trip test catches field-list drift early.
