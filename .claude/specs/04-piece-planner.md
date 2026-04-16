# 04 — PiecePlanner

> **Revision 5** — § Mid-play GET clarified: the range `(pieceLength*2, pieceLength*4]` is treated as mid-play, not seek (addendum A21). **Revision 4** — § Seek and § Mid-play GET clarified: "most recently served byte" means `range.end` of most recent GET event processed, not delivered bytes (addendum A20). Rev 3 had expected-actions example rewritten to derive correctly from deadline-spacing rules (addendum A13); § Tick gains explicit `emitHealth` emission rules (addendum A15). Rev 2 introduced "deterministic state machine" language (addendum A3); `.seek` removed from public `PlayerEvent` and derived internally from GET patterns (addendum A4); explicit zero/unknown-rate fallback for deadline spacing added (addendum A5). Baseline revision was rev 1.

The planner is the project's highest-risk component. Build it first, build it deterministic, build it from traces.

## Core principle

`PiecePlanner` is a **deterministic state machine**, not a pure function. Given the same initial state and the same sequence of inputs at the same timestamps, it produces the same sequence of outputs every run. Internal mutable state is permitted and expected: recent served byte ranges, outstanding request IDs, last-emitted `StreamHealth`, last emission time, last activity time, current readahead target.

What it must not do:

- Read a real clock (time is always a method parameter).
- Use randomness.
- Touch threads, queues, disk, or network.
- Import libtorrent at compile time (all torrent state arrives via the injected `TorrentSessionView`).

This is what makes replay testing work: tests supply time, supply events, supply the availability schedule, and assert the exact action stream.

```swift
public protocol PiecePlanner {
    func handle(event: PlayerEvent,
                at time: Instant,
                session: TorrentSessionView) -> [PlannerAction]

    func tick(at time: Instant,
              session: TorrentSessionView) -> [PlannerAction]

    func currentHealth(at time: Instant,
                       session: TorrentSessionView) -> StreamHealth
}
```

`TorrentSessionView` is a read-only protocol. In production it wraps `TorrentBridge`. In tests it's a fake driven by the availability schedule.

```swift
public protocol TorrentSessionView {
    var pieceLength: Int64 { get }
    var fileByteRange: ByteRange { get }          // within the sparse file for the selected file
    func havePieces() -> BitSet
    func downloadRateBytesPerSec() -> Int64
    func peerCount() -> Int
}
```

## Inputs

```swift
public enum PlayerEvent {
    case head                                        // HEAD request from AVPlayer
    case get(requestID: String, range: ByteRange)    // GET with Range
    case cancel(requestID: String)                   // client closed before response complete
}

public struct ByteRange: Hashable, Sendable {
    public let start: Int64   // inclusive
    public let end: Int64     // inclusive
}
```

Seek is **not** a public event. The planner detects a seek internally by comparing each incoming GET's `range.start` against its record of most-recently-served bytes, and branches to its seek policy accordingly. The gateway emits only the three events above.

## Outputs

```swift
public enum PlannerAction: Equatable {
    case setDeadlines([PieceDeadline])
    case clearDeadlinesExcept(pieces: [Int])
    case waitForRange(requestID: String, maxWaitMs: Int)
    case failRange(requestID: String, reason: FailReason)
    case emitHealth(StreamHealth)
}

public struct PieceDeadline: Equatable {
    public let piece: Int
    public let deadlineMs: Int
    public let priority: Priority

    public enum Priority: String, Equatable {
        case critical      // playhead window
        case readahead     // rolling lookahead
        case background    // not in active read window
    }
}

public enum FailReason: String, Equatable {
    case rangeOutOfBounds
    case waitTimedOut
    case streamClosed
}
```

## Policies (v1)

### Readahead window

- Expressed in **seconds of media**, not bytes.
- Default target: 30 seconds ahead of the current playhead byte.
- When `downloadRateBytesPerSec >= 1.5 * observedOrInferredBitrate`, target stays at 30 s.
- When `downloadRateBytesPerSec < observedOrInferredBitrate`, widen target to 60 s to build cushion.
- When bitrate is unknown, fall back to a byte-based heuristic: 30 MB readahead window (~30 s at 8 Mbps H.264).

### Deadline spacing

Critical pieces (the playhead window) use a fixed schedule regardless of observed rate: first 4 pieces at 0, 100, 200, 300 ms.

Readahead pieces use spacing derived from observed download rate:

- **When `observedRate >= 100 KB/s`** (rate is measurable): spacing = `pieceLength / observedRate`, with a floor of 200 ms per piece.
- **When `observedRate < 100 KB/s`** (functionally zero or not yet measured, e.g. very first play before any peers connect):
  - First 4 readahead pieces: 250 ms spacing.
  - Next 4 readahead pieces: 500 ms spacing.
  - Remaining pieces in the window: 1000 ms spacing.
- The planner re-evaluates spacing on every `tick` once `observedRate` has been ≥ 100 KB/s for 2 consecutive ticks. Recomputation only affects deadlines not yet set; existing deadlines are not retroactively shortened.

### Initial play

On first `get` after `head`:

1. Compute covering pieces for `[range.start, range.end + readaheadBytes]`.
2. Emit `setDeadlines` with:
   - First 4 pieces: `critical`, deadlines 0/100/200/300 ms.
   - Remaining pieces up to the readahead window: `readahead`, deadlines computed per the spacing rules above.
3. Emit `waitForRange` with `maxWaitMs = 1500` (first play is allowed more slack than mid-playback).

### Mid-play GET

On a `get` whose range starts within `pieceLength * 4` of the most recent GET's `range.end` (i.e. sequential or in the gap between sequential and seek thresholds):

1. Confirm covering pieces are still on the deadline list.
2. Extend the readahead window if it has slipped.
3. Emit `waitForRange` with `maxWaitMs = 800`.

**Gap clarification:** GETs in the range `(pieceLength*2, pieceLength*4]` are classified as mid-play, not seek. This is the conservative choice — it avoids unnecessary deadline clearing for distances that are close but not clearly a seek (per addendum A21).

### Seek (internally detected)

When a `get` arrives whose range starts **more than** `pieceLength * 4` away from the most recent GET's `range.end` (i.e. beyond the mid-play and gap windows), the planner classifies it as a seek and:

1. Emits `clearDeadlinesExcept` covering the new window only. Do not keep old deadlines around — they compete for peer slots.
2. Emits `setDeadlines` for the new window with critical priority on the first 4 pieces (spacing per the deadline-spacing rules above).
3. Emits `waitForRange` with `maxWaitMs = 1200`.

**First-GET special case:** if no bytes have been served yet (initial play, not a seek), the "most recent served byte" is undefined and the Initial play policy applies instead. A GET with non-zero `range.start` on initial play is *not* classified as a seek; it's just an initial play starting at a non-zero offset, which is common for back-moov MP4 and for containers where AVPlayer probes trailing metadata first.

### Cancel

On `cancel(requestID)`:

1. If the cancelled request's pieces are not part of the active playhead window, demote them to `background` via a new `setDeadlines` call.
2. If they are part of the active window (overlapping GET patterns are common), no-op.

### Tick

Called externally at ~2 Hz:

1. Recompute `StreamHealth` from current session state.
2. Decide whether to emit it (see emission rules below).
3. If readahead has fallen below target, emit `setDeadlines` to top it up.
4. If more than 5 seconds have passed since last player activity with no stream close, emit nothing structural but keep deadlines alive.

**Emission rules for `emitHealth(StreamHealth)`:** a `tick` (or `handle(event:)`) call emits a `.emitHealth(StreamHealth)` action when **any** of these is true:

1. **Tier transition.** Computed tier differs from the last emitted tier. Emit immediately, regardless of throttle.
2. **Throttled field change.** ≥ 500 ms have elapsed (in injected time) since the last `emitHealth` action **and** any field of the computed `StreamHealth` differs from the last emitted value.
3. **First emission.** No prior emission has occurred for this stream session.

Otherwise no `emitHealth` action is produced.

The planner's internal throttle state — `lastEmittedAt: Instant?` and `lastEmittedHealth: StreamHealth?` — advances **only** when an `emitHealth` action is actually produced. A "would-have-emitted-but-throttled" decision must not advance the throttle clock; otherwise the next emission could be silently delayed by up to a full throttle window.

These rules are what make fixture authoring deterministic: given the trace, the schedule, and the injected time at each step, the position of `emitHealth` actions in the output stream is fully determined.

## Trace format (input)

Located in `Packages/TestFixtures/traces/*.json`.

```json
{
  "asset_id": "front-moov-mp4-001",
  "description": "AVPlayer opens MP4 with moov at front, plays 10s, seeks to 40%",
  "content_length": 1834521190,
  "piece_length": 2097152,
  "file_byte_range": { "start": 0, "end": 1834521189 },
  "events": [
    { "t_ms": 0,    "kind": "head" },
    { "t_ms": 12,   "kind": "get", "request_id": "r1", "range_start": 0,         "range_end": 1048575 },
    { "t_ms": 80,   "kind": "get", "request_id": "r2", "range_start": 1048576,   "range_end": 4194303 },
    { "t_ms": 1400, "kind": "cancel", "request_id": "r2" },
    { "t_ms": 1450, "kind": "get", "request_id": "r3", "range_start": 734003200, "range_end": 738197503 }
  ],
  "availability_schedule": [
    { "t_ms": 0,    "have_pieces": [] },
    { "t_ms": 200,  "have_pieces": [0, 1] },
    { "t_ms": 600,  "have_pieces": [2, 3, 4] },
    { "t_ms": 1600, "have_pieces": [350, 351, 352] }
  ],
  "download_rate_schedule": [
    { "t_ms": 0,    "bytes_per_sec": 0 },
    { "t_ms": 500,  "bytes_per_sec": 2500000 },
    { "t_ms": 2000, "bytes_per_sec": 4000000 }
  ],
  "peer_count_schedule": [
    { "t_ms": 0, "count": 0 },
    { "t_ms": 300, "count": 12 }
  ]
}
```

## Expected action format (output, for assertions)

Below is an illustrative example showing the structure of an expected-actions file. Note: the deadline values and piece selections are derived mechanically from the policies in this spec — see "Worked derivation" after the example. T-PLANNER-FIXTURES (which authors the real fixtures) must verify each expected file matches what the policies actually produce, not what looks intuitively right.

```json
{
  "trace_id": "front-moov-mp4-001",
  "actions": [
    {
      "t_ms": 12,
      "kind": "set_deadlines",
      "pieces": [
        { "piece": 0, "deadline_ms": 0,    "priority": "critical" },
        { "piece": 1, "deadline_ms": 100,  "priority": "critical" },
        { "piece": 2, "deadline_ms": 200,  "priority": "critical" },
        { "piece": 3, "deadline_ms": 300,  "priority": "critical" },
        { "piece": 4, "deadline_ms": 250,  "priority": "readahead" },
        { "piece": 5, "deadline_ms": 500,  "priority": "readahead" },
        { "piece": 6, "deadline_ms": 750,  "priority": "readahead" },
        { "piece": 7, "deadline_ms": 1000, "priority": "readahead" }
      ]
    },
    {
      "t_ms": 12,
      "kind": "wait_for_range",
      "request_id": "r1",
      "max_wait_ms": 1500
    },
    {
      "t_ms": 1450,
      "kind": "clear_deadlines_except",
      "pieces": [350, 351, 352, 353]
    },
    {
      "t_ms": 1450,
      "kind": "set_deadlines",
      "pieces": [
        { "piece": 350, "deadline_ms": 0,   "priority": "critical" },
        { "piece": 351, "deadline_ms": 100, "priority": "critical" },
        { "piece": 352, "deadline_ms": 200, "priority": "critical" },
        { "piece": 353, "deadline_ms": 300, "priority": "critical" }
      ]
    },
    {
      "t_ms": 1450,
      "kind": "wait_for_range",
      "request_id": "r3",
      "max_wait_ms": 1200
    }
  ]
}
```

### Worked derivation (so fixture authors can sanity-check)

For the GET at `t_ms=12` requesting bytes `[0, 1048575]` with `piece_length = 2097152`:

- Range covers piece 0 only (1 MB ≤ 2 MB piece).
- At `t_ms=12`, the download rate schedule shows 0 bytes/sec → zero-rate fallback applies (§ Deadline spacing).
- Critical window: first 4 pieces (0, 1, 2, 3) at fixed 0/100/200/300 ms regardless of rate.
- Readahead pieces use the zero-rate fallback tiers: first 4 readahead pieces (4, 5, 6, 7) at 250 ms spacing → 250/500/750/1000 ms.
- The example truncates at piece 7 for brevity; the real readahead window per § Readahead window is 30 MB (~14 pieces) when bitrate is unknown, so the actual fixture would extend further with the next 4 pieces at 500 ms spacing (1500/2000/2500/3000 ms) and then 1000 ms thereafter.
- `waitForRange` uses 1500 ms because this is the initial play (§ Initial play).

For the GET at `t_ms=1450` requesting bytes `[734003200, 738197503]`:

- This is far from the most-recently-served byte (still around 1 MB region) → seek policy applies.
- New covering pieces: bytes 734003200 / 2097152 = piece 350 onwards. The 4 MB request spans pieces 350–352, and the seek policy sets critical priority on the first 4 pieces (350–353).
- `clearDeadlinesExcept` lists the pieces to retain, which is exactly the new critical window (350–353); all earlier deadlines are dropped because they would compete for peer slots.
- `waitForRange` uses 1200 ms per § Seek.

### Meta-rule

Any expected-actions example or fixture file must derive mechanically from the policies in § Policies and § Deadline spacing. T-PLANNER-FIXTURES must include a verification step that runs the planner against each fixture's trace and confirms the expected file is what the planner actually produces — fixtures that disagree with the planner are wrong, not the planner. If a fixture *should* disagree with the planner, the policy is wrong and must be revised through an addendum item.

## Minimum fixture set (v1)

All four must exist and all four must pass before `T-PLANNER-CORE` is marked done.

1. **`front-moov-mp4-001`** — MP4 with `moov` at the front. Linear play for 10 seconds, then seek to ~40%. Baseline case.
2. **`back-moov-mp4-001`** — MP4 with `moov` at the end. AVPlayer issues a tail read before any sequential playback. Planner must survive non-linear early reads without dropping the eventual forward deadlines.
3. **`mkv-cues-001`** — MKV with cues element in the middle. AVPlayer probes cues early, then plays from start.
4. **`immediate-seek-001`** — User scrubs within 500 ms of opening playback, before initial buffer has formed. Planner must abandon initial deadlines cleanly.

## Test obligations

- Each fixture has a paired expected-actions file.
- `PlannerReplayTests` loads the trace, runs the planner deterministically, and asserts the action sequence matches.
- **Deterministic** means: given the same trace + schedule, the planner produces the same action list every run. No real clocks, no randomness, no wall time.
- Deviation from expected output fails the test loudly with a diff.
- When spec thresholds change (e.g. readahead target), the expected-actions files are regenerated **with Opus review**, not silently.

## What the planner does not do

- Own the HTTP connection.
- Own the sparse file reader.
- Make libtorrent API calls (a caller maps `PlannerAction` to `TorrentBridge` calls).
- Know about subtitles, audio tracks, or codecs.
- Persist anything.
