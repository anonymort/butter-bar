# Watch state foundation — design (Phase 1)

> **Scope:** the foundation ticket for Epic #5 (#34). Defines `WatchStatus`, the
> deterministic transitions that drive it, the engine schema and XPC surface
> that feed it, and the test shape every Phase 1 ticket consumes.
>
> **Status:** Opus design pass, 2026-04-16. Approved before implementation.

## Why a design doc

Phase 1's foundation ticket sits between three frozen surfaces:

1. **Engine schema** (`05-cache-policy.md` § Schema, `EngineStore`).
2. **XPC contract** (`03-xpc-contract.md`, `EngineInterface`).
3. **Brand-compliant library UI** (`06-brand.md`, `App/Features/Library`).

The watch state model has to be coherent across all three without bloating any
of them. This doc records the choices so dependent tickets (#35, #36, #37) can
implement against a stable target.

## Decisions

### D1 — `WatchStatus` carries a real `completedAt: Date`

The hinted enum shape on #34 included `.watched(completedAt:)`. To make that
honest we add a new column on `playback_history`:

- **Schema**: `completed_at INTEGER NULL` (unix ms), additive V2 migration
  named `v2_add_completed_at`. Existing rows get `NULL`; the engine fills it
  on the next completion.
- **Spec**: spec 05 → rev 5; addendum **A26** records the rule.
- **Rejected alternative**: derive timestamp from `last_played_at`. Wrong
  semantics — re-watch updates `last_played_at` and would silently overwrite
  the original completion time. Library copy "Watched 3 days ago" would
  drift after every re-open.

### D2 — Progress is byte-accurate, not time-accurate

`WatchStatus` carries `progressBytes: Int64` and `totalBytes: Int64`, never
seconds. This matches spec 05 rev 4 (A6): the v1 cache spec deliberately
weakened resume to "last byte served." Container-aware byte→time mapping is
v1.5+ work. The library progress bar uses `progressBytes / totalBytes`, per
spec 05 § "What this means for the UI".

The hint in #34 (`progressSeconds:`) was the issue body's original placeholder
text and is superseded here.

### D3 — `WatchStatus` is app-side; engine writes the source rows

The engine remains the sole writer of `playback_history` (single-writer
ownership per spec 01). It does not know about "re-watching" or "watched";
those are app-derived from a row plus `totalBytes`.

The app cannot derive watch status today: there is no XPC method to read
`playback_history` rows, only the per-stream `StreamDescriptorDTO.resumeByteOffset`.
We therefore extend the XPC contract:

- **DTO**: `PlaybackHistoryDTO` (`schemaVersion = 1`, NSSecureCoding).
- **Method**: `EngineXPC.listPlaybackHistory(reply: ([PlaybackHistoryDTO]) -> Void)`.
- **Event**: `EngineEvents.playbackHistoryChanged(_ dto: PlaybackHistoryDTO)`,
  emitted on every write (15 s tick, stream close, manual toggle).
- **Versioning**: response/event DTOs are versioned per A1; new methods are
  backward-compatible per the same rule.

### D4 — Re-watch is derived, not persisted as a third state

We keep `playback_history.completed: Bool`. "Re-watching" is the row state
`(completed = 1, resumeByteOffset > 0)`. This holds because:

- Spec 05 already resets `resume_byte_offset = 0` on the next stream open
  after completion.
- The engine never clears `completed` automatically; only manual mark-unwatched
  flips it back to 0.
- Therefore any positive offset on a row with `completed = 1` is, by
  construction, an in-flight re-watch.

A subsequent re-completion during a re-watch updates `completed_at = now()`
(most recent completion wins). This trades the "original first watched" date
for predictable copy in the library — the row always answers "when did you
last finish this?" rather than "when did you first finish this?". The
distinction is unrecoverable in v1 without a watch-event log, which is out
of scope.

### D5 — `WatchStateMachine` is a pure function, no clocks

Mirrors the planner discipline (addendum A3). All transitions live in
`WatchStateMachine.apply(_:to:now:)`, take their `now: Date` as an injected
parameter, and have no I/O, no `DispatchQueue`, no real clocks. The
state-machine tests are therefore deterministic.

The engine's persistence path is *not* this state machine — it writes raw
`(completed, completed_at, resume_byte_offset)` per the rules in §
"Engine write rules" below. The state machine is the app-side mirror used
for command handling (mark-watched, mark-unwatched, observed events).

## Type sketch

```swift
// Packages/LibraryDomain (new package, depends on EngineInterface)

public enum WatchStatus: Equatable, Sendable {
    case unwatched
    case inProgress(progressBytes: Int64, totalBytes: Int64)
    case watched(completedAt: Date)
    case reWatching(progressBytes: Int64,
                    totalBytes: Int64,
                    previouslyCompletedAt: Date)
}

public extension WatchStatus {
    /// Project a row from the engine into a status for the UI.
    /// `nil` row → `.unwatched` (file has no playback history).
    static func from(history: PlaybackHistoryDTO?,
                     totalBytes: Int64) -> WatchStatus
}

public enum WatchEvent: Equatable, Sendable {
    case streamOpened(totalBytes: Int64)
    case progress(bytes: Int64, totalBytes: Int64)
    case streamClosed(finalBytes: Int64, totalBytes: Int64)
    case manuallyMarkedWatched(at: Date)
    case manuallyMarkedUnwatched
}

public enum WatchStateMachine {
    public static func apply(_ event: WatchEvent,
                             to status: WatchStatus,
                             now: Date) -> WatchStatus
}
```

## Derivation matrix (DTO → `WatchStatus`)

`history` is a `PlaybackHistoryDTO?`; `total = totalBytes`.

| `completed` | `completed_at` | `resume_byte_offset` | result                                                      |
| ----------- | -------------- | -------------------- | ----------------------------------------------------------- |
| (row absent)| —              | —                    | `.unwatched`                                                |
| `false`     | `NULL`         | `0`                  | `.unwatched`                                                |
| `false`     | `NULL`         | `n > 0`              | `.inProgress(n, total)`                                     |
| `true`      | `T`            | `0`                  | `.watched(T)`                                               |
| `true`      | `T`            | `n > 0`              | `.reWatching(n, total, T)`                                  |
| `true`      | `NULL`         | any                  | **invariant violation** — log + treat as `.watched(now)`    |
| `false`     | `T ≠ NULL`     | any                  | **invariant violation** — log + treat as `.inProgress`/`.unwatched` per offset |

Engine writes guarantee the invariants; the violation rows exist only as
defensive UI fallbacks.

## Transition matrix (`WatchStateMachine.apply`)

Rows are current `WatchStatus`; columns are `WatchEvent`. Cells give the
resulting status.

`s.opened(T)` = `streamOpened(totalBytes: T)`
`prog(b,T)` = `progress(bytes: b, totalBytes: T)`
`s.closed(b,T)` = `streamClosed(finalBytes: b, totalBytes: T)`
`mark.W` = `manuallyMarkedWatched(at: now)`
`mark.U` = `manuallyMarkedUnwatched`
**threshold** = `b ≥ Int64(0.95 * Double(T))` (matches spec 05 § Update rules)

| from \ event | `s.opened(T)`               | `prog(b,T)`                                | `s.closed(b,T)`                                                         | `mark.W`             | `mark.U`     |
| ------------ | --------------------------- | ------------------------------------------ | ----------------------------------------------------------------------- | -------------------- | ------------ |
| `.unwatched` | `.inProgress(0,T)`          | `.inProgress(b,T)`                         | `.unwatched` (b=0) <br> `.watched(now)` (threshold) <br> `.inProgress(b,T)` (otherwise) | `.watched(now)`      | `.unwatched` |
| `.inProgress(p,T)` | `.inProgress(p,T)` (idempotent) | `.inProgress(max(p,b), T)`         | `.watched(now)` (threshold) <br> `.inProgress(max(p,b),T)` (otherwise)   | `.watched(now)`      | `.unwatched` |
| `.watched(W)` | `.reWatching(0,T,W)`        | invariant — must `.opened` first; log + treat as `.reWatching(b,T,W)` | `.watched(W)` (idempotent — closed without progress)                  | `.watched(W)` (no-op; keeps original W) | `.unwatched` |
| `.reWatching(p,T,W)` | `.reWatching(p,T,W)` (idempotent) | `.reWatching(max(p,b),T,W)`     | `.watched(now)` (threshold; **W replaced by `now`**) <br> `.reWatching(max(p,b),T,W)` (otherwise) | `.watched(now)` (W replaced) | `.unwatched` |

Notes:

- `manuallyMarkedWatched` on `.watched(W)` is a no-op: keeping the original
  date matches user intent ("I'm just confirming, not re-stamping").
- `manuallyMarkedWatched` on `.reWatching(_, _, W)` **does** replace W with
  now, because the user is asserting "treat this as freshly watched right
  now" rather than just confirming the prior watch.
- Crossing the threshold during a re-watch replaces W. This is the
  most-recent-completion-wins rule from D4.

## Engine write rules (mirror of the state machine)

Lives in `CacheManager` and is invoked from the existing 15 s tick / close
path plus a new manual-toggle XPC method.

| Trigger                                  | Resulting row state                                                                                       |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Stream open on never-played file         | Insert `(resume=0, last_played=now, completed=0, completed_at=NULL)` (existing behaviour)                 |
| 15 s tick during play                    | Update `resume_byte_offset = b, last_played_at = now`. If `b ≥ 0.95*size` AND `completed=0`: also set `completed=1, completed_at=now` |
| Tick during play after re-completion     | If `completed=1` AND `b ≥ 0.95*size` AND `b > stored resume`: update `completed_at=now` (most recent wins) |
| Stream close                             | Same rule as the 15 s tick, evaluated on the final byte                                                   |
| Stream open after completion             | Reset `resume_byte_offset = 0`; **do not** clear `completed` or `completed_at` (re-watch starts here)     |
| Manual mark-watched (XPC)                | Set `completed=1, completed_at=now, resume_byte_offset=0` (creates row if absent; `last_played_at=now`)   |
| Manual mark-unwatched (XPC)              | Set `completed=0, completed_at=NULL, resume_byte_offset=0` (preserves `last_played_at` for ordering)      |

After every write, emit `playbackHistoryChanged(dto)` to subscribed clients.

## Test shape

The foundation ticket lands these test groups. Other Phase 1 tickets reuse
the harnesses.

### Schema tests (Packages/EngineStore)

- `MigrationV2Tests`:
  - Fresh DB → both V1 and V2 apply cleanly; `completed_at` column exists.
  - Idempotent: running V2 twice is a no-op.
  - V1-only DB → V2 applies; existing rows have `completed_at = NULL`.
- `PlaybackHistoryRecordV2Tests`:
  - Round-trip insert/fetch with `completedAt = nil` and `completedAt = 1234`.

### DTO tests (Packages/EngineInterface)

- `PlaybackHistoryDTOTests`:
  - NSSecureCoding round-trip with all `completedAt` shapes.
  - `schemaVersion = 1` constant.

### Mapping tests (Packages/XPCMapping)

- `PlaybackHistoryMappingTests`:
  - Domain → DTO → domain idempotent for all rows in the derivation matrix.

### Domain tests (Packages/LibraryDomain — new)

- `WatchStatusDerivationTests`:
  - One case per row in the derivation matrix above (≥ 7 cases).
- `WatchStateMachineTests`:
  - One case per cell in the transition matrix (4 × 5 = 20 base cases).
  - Idempotence: applying the same event twice from a stable state is a
    no-op where the matrix says so.
  - Threshold edge: `b == ceil(0.95 * T)` crosses; `b == ceil(0.95*T) - 1`
    does not.
  - Invariant-violation rows produce the documented fallback, never crash.

### Engine write-path tests (EngineService)

- `CacheManagerWatchStateTests`:
  - 0→1 transition sets `completed_at` to the injected `now`.
  - Re-completion during re-watch updates `completed_at`.
  - Manual mark-watched on absent row creates correct shape.
  - Manual mark-unwatched preserves `last_played_at`.
  - `playbackHistoryChanged` event is emitted exactly once per write.

### XPC integration test (Packages/EngineInterface)

- `XPCPlaybackHistoryTests` (extends the in-process `MockEngineServer`):
  - `listPlaybackHistory` returns `[]` against an empty fake.
  - After a synthetic write, the next call returns the inserted row, and
    the subscribed event fires once.

## Out of scope for the foundation

- Library UI changes (continue-watching row, watched badge, heart toggle,
  context menu) — those are #35/#36/#37.
- The `favourites` table — independent engine task `T-STORE-FAVOURITES`,
  filed in `TASKS.md` as part of this design pass.
- Snapshot tests for any UI surface — none in this PR.
- Trakt/sync-side conflict rules — explicitly Phase 2+ per `docs/v1-roadmap.md`.

## Risks and mitigations

| Risk                                                                 | Mitigation                                                                                                |
| -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Engine and app drift on the threshold formula                        | Single helper `WatchThreshold.isComplete(progress:total:)` exported from `LibraryDomain`, used by both    |
| `playbackHistoryChanged` storm during heavy seek                     | Engine writes are already throttled to 15 s ticks + close; event piggy-backs on the same write           |
| `completed_at` lost on V2 migration of a populated production DB     | Migration is additive; rows preserve `completed`. Loss of historical `completed_at` is acceptable for v1 |
| Re-watch UI confusion ("why does this say 'Watched yesterday' when I'm at 50%?") | `.reWatching` carries `previouslyCompletedAt` so UI can pick the right copy ("Re-watching, last finished yesterday") |
| Future v2 wants per-watch event log (drop "most-recent wins" rule)   | Not blocked by this design — adding an `episodes_watched` table would supplement, not contradict, `completed_at` |
