# Player state foundation — design (Phase 3)

> **Scope:** the foundation ticket for Epic #3 (#18). Defines `PlayerState`,
> the deterministic state machine that drives it, the engine-event projection
> rules that translate `StreamHealthDTO` and XPC errors into player events,
> and the seam through which the resume prompt (#19) consumes Phase 1's
> `WatchStatus`.
>
> **Status:** Opus design pass, 2026-04-16. Doc-only PR; no implementation
> in this revision. Phase 3 dependent tickets (#19, #22, #23, #24, #26) land
> against the foundation in subsequent feature PRs.

## Why a design doc

Phase 3's foundation sits between four frozen surfaces:

1. **Engine event stream** (`02-stream-health.md`, `03-xpc-contract.md`,
   `EngineEvents` protocol) — the only source of truth for what the engine
   is doing for this stream.
2. **AVKit / AVPlayer** — the only source of truth for what the decoder
   and the actual player are doing (rate, status, buffer).
3. **`WatchStatus`** from Phase 1 (#34) — the only honest signal for
   whether the user has prior progress on this file.
4. **Brand voice and chrome** (`06-brand.md`) — the surface that every
   `PlayerState` value is rendered through.

`PlayerState` has to be coherent across all four without bloating any of
them. This doc records the choices so dependent tickets (#19, #22, #23,
#24, #26 in Phase 3, and #20, #21 in the deferred Phase 3 tail) can
implement against a stable target.

## Decisions

### D1 — Cross-phase split: Option A (defer #20 + #21 to a Phase 3 tail)

Per `docs/v1-roadmap.md § Phase 3`, the cross-phase decision was Option A
vs Option B. Choosing **Option A**: land #18, #19, #22, #23, #24, #26 in
Phase 3 proper; defer #20 (end-of-episode detection) and #21
(next-episode auto-play with grace period) to a Phase 3 tail that runs
after Phase 4's #11 (metadata schema) lands.

Reasons:

- **#21 is fundamentally a metadata feature.** "Up next: <episode title>"
  with a real grace period requires real season → episode → next-episode
  relationships. Stubbing those introduces a fake user-facing string that
  has to be migrated when #11 lands.
- **A stub leaks into the foundation type.** Option B forces `PlayerState`
  (or an adjacent context object) to carry an `EpisodeRef` of some shape
  before the real schema exists. When #11 lands the change ripples through
  every site that touched the stub. Option A confines the cost to the
  tail.
- **`PlayerState` itself is episode-agnostic.** End-of-episode detection
  is a separate detector that observes `PlayerState` (specifically, the
  `.playing → .closed` edge near content end) and consults metadata. It
  does not require new states or transitions in the foundation.
- **Phase 3 still satisfies the epic's foundation guarantee.** Per the
  roadmap, "Phase 3 done = … every player surface routes through
  `PlayerState` rather than ad-hoc booleans." That holds without #20/#21
  in the same phase.

**Rejected alternative:** Option B. Higher refactor cost, concentrated
in the wrong place (the foundation type rather than the tail tickets).

### D2 — `PlayerState` is six cases; "opening" folds into `.buffering`

The brief specifies six cases: `.open | .playing | .paused | .buffering |
.error | .closed`. We honour that exactly:

- `.closed` — initial and terminal. No descriptor, no `AVPlayer`, nothing
  to render except the empty-player chrome.
- `.open` — descriptor in hand, `AVPlayer` attached, AVPlayer rate is
  `0`. This is the resume-prompt window (#19). Distinct from `.paused`:
  `.paused` implies the user explicitly paused; `.open` implies the user
  has not yet started this stream.
- `.playing` — `AVPlayer.rate > 0` and the engine tier is not
  `.starving`. Normal playback.
- `.paused` — `AVPlayer.rate == 0` because the user paused. Engine may
  still be downloading.
- `.buffering(reason:)` — covers three distinct gates that all render as
  "we are waiting on bytes":
  - `.openingStream` — awaiting `engine.openStream` reply. Replaces what
    a separate `.opening` state would otherwise be.
  - `.engineStarving` — `StreamHealthDTO.tier == .starving`.
  - `.playerRebuffering` — `AVPlayerItem.isPlaybackBufferEmpty == true`.
- `.error(PlayerError)` — recoverable from the model's perspective via
  retry; terminal from this stream's perspective.

**Rejected alternative:** add a 7th `.opening` state. Rejected because
from the user's perspective "we are loading the stream" and "we have
stalled mid-play" are the same chrome — both render the calm progress
indicator with the same copy register. The internal `BufferingReason`
distinguishes them for telemetry, copy variation (#26), and tests.

### D3 — `PlayerState` carries no IDs; the VM owns identity

`PlayerState` is the state of *one* stream's playback in *one*
`PlayerViewModel` instance. It carries no `streamID`, no `torrentID`, no
`fileIndex` — the owning view model already knows.

This mirrors `WatchStatus` (Phase 1), which similarly carries no
`(torrentID, fileIndex)` — the calling context owns identity. Keeping
the enum identity-free makes it cheap to compare with `Equatable` and
keeps the test surface small.

### D4 — `PlayerStateMachine` is a pure function, no clocks

Lives in `App/Features/Player/PlayerStateMachine.swift` as
`enum PlayerStateMachine` with one method:

```swift
public static func apply(_ event: PlayerEvent,
                         to state: PlayerState,
                         now: Date) -> PlayerState
```

Constraints, mirroring `WatchStateMachine` (Phase 1) and the planner
discipline (addendum A3):

- No real clocks (`now` is injected).
- No I/O, no `DispatchQueue`, no `Combine`.
- No randomness.
- Internal mutable state is **not** permitted — the machine is a pure
  function over `(event, state, now)`. Any state worth keeping
  (timestamps, retry counts, last-known tier) lives on the `PlayerState`
  cases as associated values or on the calling `PlayerViewModel`.

The state machine is tested deterministically by replaying event
sequences. The `PlayerViewModel` is tested separately with a fake
`EngineClient` and a fake `AVPlayer` driver.

### D5 — Engine-event projection happens at the VM, not in the machine

The state machine sees only `PlayerEvent`. It never imports
`EngineInterface` and never inspects a `StreamHealthDTO` directly.
`PlayerViewModel` does the projection:

| Engine / AVPlayer signal                                                       | `PlayerEvent`                                  |
| ------------------------------------------------------------------------------ | ---------------------------------------------- |
| User clicks play on a file in the library                                      | `.userRequestedOpen`                           |
| `engine.openStream` reply with non-nil `StreamDescriptorDTO`                   | `.engineReturnedDescriptor(descriptor)`        |
| `engine.openStream` reply with non-nil `NSError`                               | `.engineReturnedOpenError(EngineErrorCode)`    |
| `EngineEvents.streamHealthChanged(dto)` filtered to this stream                | `.engineHealthChanged(dto.tier)`               |
| `EngineClient.eventsDidChangeNotification`, current connection invalid        | `.engineDisconnected`                          |
| `EngineClient.eventsDidChangeNotification`, current connection valid          | `.engineReconnected`                           |
| `AVPlayer.timeControlStatus` → `.playing`                                      | `.avPlayerBeganPlaying`                        |
| `AVPlayerItem.isPlaybackBufferEmpty` rises edge                                | `.avPlayerStalled`                             |
| `AVPlayerItem.isPlaybackLikelyToKeepUp` rises edge after a stall               | `.avPlayerResumed`                             |
| `AVPlayerItem.status` → `.failed`                                              | `.avPlayerFailed`                              |
| User taps the play button in the overlay                                       | `.userTappedPlay`                              |
| User taps the pause button in the overlay                                      | `.userTappedPause`                             |
| User taps close / dismisses the player window                                  | `.userTappedClose`                             |
| User taps "Retry" in an error state (#26)                                      | `.userTappedRetry`                             |

The full `PlayerEvent` enum:

```swift
public enum PlayerEvent: Equatable, Sendable {
    case userRequestedOpen
    case engineReturnedDescriptor(StreamDescriptorDTO)
    case engineReturnedOpenError(EngineErrorCode)
    case userTappedPlay
    case userTappedPause
    case userTappedClose
    case userTappedRetry
    case avPlayerBeganPlaying
    case avPlayerStalled
    case avPlayerResumed
    case avPlayerFailed
    case engineHealthChanged(StreamHealthDTO.Tier)
    case engineDisconnected
    case engineReconnected
}
```

Note `.engineHealthChanged` carries the tier as a typed Swift enum, not
the wire `NSString`. The DTO → domain conversion already happens at the
mapping layer (`Packages/XPCMapping`); the state machine consumes the
domain type. This matches the pattern set by PR #146 ("type
StreamHealthDTO tier at domain boundary").

### D6 — No auto-resume on XPC reconnect

`.error(.xpcDisconnected)` does **not** auto-recover on
`.engineReconnected`. The user must explicitly tap retry.

Reason: a stream can be invalidated while the connection is down. The
engine may have evicted pieces, restarted, or closed the stream from
its side (cache eviction, disk pressure, supervised restart). An
auto-resume that re-attaches `AVPlayer` to a now-dead loopback URL would
silently fail in a way the user can't reason about.

`PlayerViewModel` still re-subscribes to event streams on reconnect (so
that subsequent retries land on a live event channel). The state itself
stays in `.error(.xpcDisconnected)` until the user acts.

### D7 — Resume prompt seam (#19)

The resume prompt fires when the state machine first enters `.open`
for a freshly-opened stream, **and** the following two predicates both
hold:

1. `WatchStatus.from(history:totalBytes:) ∈ {.inProgress(_, _),
   .reWatching(_, _, _)}` (from Phase 1 — `LibraryDomain`).
2. `streamDescriptor.resumeByteOffset > 0` (from
   `EngineInterface.StreamDescriptorDTO`).

Both must hold for an honest prompt. The two predicates are intentionally
redundant:

- `WatchStatus` is the **user-meaningful** signal — "you were 23 minutes
  in" is what the prompt copy reflects.
- `resumeByteOffset` is the **operationally meaningful** signal — what
  `AVPlayer` actually seeks to (per `PlayerViewModel.scheduleResumeSeek`,
  approximated as `byteOffset / contentLength × duration`).

If they disagree (history shows in-progress but offset is `0`, or offset
is `> 0` but no history row exists), the prompt is suppressed and the
stream starts from the beginning silently. The disagreement is logged —
these states are invariant violations the engine guarantees do not
happen (see Phase 1's design doc § Derivation matrix). The model treats
them as defensive fallbacks rather than user-facing options.

The prompt UI itself (modal vs. overlay strip vs. transient toast) and
the copy ("Continue from 23m" vs. "Resume" vs. ...) are out of scope
for this foundation — they belong to #19's PR. This doc only specifies
**when** the prompt is offered and **what data** it consumes.

#### Resume prompt → `PlayerEvent` mapping

After the prompt resolves:

| User choice                          | `PlayerViewModel` action                                       | Resulting `PlayerEvent`     |
| ------------------------------------ | -------------------------------------------------------------- | --------------------------- |
| "Continue from where you stopped"    | Schedule resume seek per existing `PlayerViewModel` path; play | `.userTappedPlay`           |
| "Start from the beginning"           | Seek to `.zero` (override the prepared resume seek); play      | `.userTappedPlay`           |
| Dismiss without choosing             | Stay in `.open`; no event                                      | (none)                      |

The state machine sees only `.userTappedPlay` (or nothing). Resume
choice routing lives in the VM, not in the machine.

## Type sketch

```swift
// App/Features/Player/PlayerState.swift

public enum PlayerState: Equatable, Sendable {
    case closed
    case open
    case playing
    case paused
    case buffering(reason: BufferingReason)
    case error(PlayerError)
}

public enum BufferingReason: Equatable, Sendable {
    case openingStream
    case engineStarving
    case playerRebuffering
}

public enum PlayerError: Equatable, Sendable {
    case streamOpenFailed(EngineErrorCode)
    case xpcDisconnected
    case playbackFailed
    case streamLost                        // see § Open questions O1
}

// App/Features/Player/PlayerStateMachine.swift

public enum PlayerStateMachine {
    public static func apply(_ event: PlayerEvent,
                             to state: PlayerState,
                             now: Date) -> PlayerState
}
```

The machine and the enum live in the existing `App/Features/Player/`
target. They do **not** require a new SPM package. `EngineErrorCode` is
re-exported from `EngineInterface`.

## Transition matrix (`PlayerStateMachine.apply`)

Rows are current `PlayerState`; columns are `PlayerEvent` families. Cells
give the resulting state. `inv` = invariant violation: state machine
logs and returns input state unchanged (defensive — these inputs should
never arise from the projection in D5).

`buf(r)` = `.buffering(reason: r)`; `err(e)` = `.error(e)`.

| from \ event              | `userRequestedOpen`         | `engineReturnedDescriptor` | `engineReturnedOpenError(c)`    | `userTappedPlay`        | `userTappedPause`         | `userTappedClose`         | `userTappedRetry`        |
| ------------------------- | --------------------------- | -------------------------- | ------------------------------- | ----------------------- | ------------------------- | ------------------------- | ------------------------ |
| `.closed`                 | `buf(.openingStream)`       | inv                        | inv                             | inv                     | inv                       | `.closed` (idem)          | inv                      |
| `.open`                   | inv                         | `.open` (idem)             | inv                             | `.playing`              | `.paused`                 | `.closed`                 | inv                      |
| `.playing`                | inv                         | inv                        | inv                             | `.playing` (idem)       | `.paused`                 | `.closed`                 | inv                      |
| `.paused`                 | inv                         | inv                        | inv                             | `.playing`              | `.paused` (idem)          | `.closed`                 | inv                      |
| `buf(.openingStream)`     | `buf(.openingStream)` (idem)| `.open`                    | `err(.streamOpenFailed(c))`     | inv                     | inv                       | `.closed`                 | inv                      |
| `buf(.engineStarving)`    | inv                         | inv                        | inv                             | `buf(.engineStarving)` (idem; AVPlayer kept playing intent) | `.paused` | `.closed`                 | inv                      |
| `buf(.playerRebuffering)` | inv                         | inv                        | inv                             | `buf(.playerRebuffering)` (idem) | `.paused`         | `.closed`                 | inv                      |
| `err(_)`                  | inv                         | inv                        | inv                             | inv                     | inv                       | `.closed`                 | `buf(.openingStream)`    |

| from \ event              | `avPlayerBeganPlaying` | `avPlayerStalled`           | `avPlayerResumed`           | `avPlayerFailed`        | `engineHealthChanged(t)`                                                       | `engineDisconnected`        | `engineReconnected`             |
| ------------------------- | ---------------------- | --------------------------- | --------------------------- | ----------------------- | ------------------------------------------------------------------------------ | --------------------------- | ------------------------------- |
| `.closed`                 | inv                    | inv                         | inv                         | inv                     | `.closed` (no-op; not subscribed)                                              | `.closed` (no-op)           | `.closed` (no-op)               |
| `.open`                   | `.playing`             | `buf(.playerRebuffering)`   | `.open` (idem; not stalled) | `err(.playbackFailed)`  | `t == .starving` → `buf(.engineStarving)`; else `.open`                        | `err(.xpcDisconnected)`     | `.open` (no auto-resume per D6) |
| `.playing`                | `.playing` (idem)      | `buf(.playerRebuffering)`   | `.playing` (idem)           | `err(.playbackFailed)`  | `t == .starving` → `buf(.engineStarving)`; else `.playing`                     | `err(.xpcDisconnected)`     | `.playing` (no auto-resume)     |
| `.paused`                 | `.paused` (idem; AVPlayer rate spurious) | `.paused` (idem)| `.paused` (idem)            | `err(.playbackFailed)`  | `.paused` (engine starvation suppressed while paused — health visible in HUD only) | `err(.xpcDisconnected)` | `.paused`                       |
| `buf(.openingStream)`     | inv                    | inv                         | inv                         | inv                     | `buf(.openingStream)` (no-op; pre-open)                                        | `err(.xpcDisconnected)`     | `buf(.openingStream)`           |
| `buf(.engineStarving)`    | `.playing` (race: AVPlayer began before health update — accept) | `buf(.playerRebuffering)` (player wins; reason swap) | `buf(.engineStarving)` | `err(.playbackFailed)` | `t == .starving` → `buf(.engineStarving)` (idem); else → `.playing` | `err(.xpcDisconnected)` | `buf(.engineStarving)` |
| `buf(.playerRebuffering)` | `.playing`             | `buf(.playerRebuffering)` (idem) | `.playing` (if no engine starvation in flight) | `err(.playbackFailed)` | `t == .starving` → `buf(.engineStarving)` (reason swap); else `buf(.playerRebuffering)` | `err(.xpcDisconnected)` | `buf(.playerRebuffering)` |
| `err(_)`                  | inv                    | inv                         | inv                         | inv                     | `err(_)` (no-op; UI shows error chrome regardless)                             | `err(_)` (idem)             | `err(_)` (no auto-resume per D6) |

Threshold/precedence notes:

- **Engine starving wins over player rebuffering** when both are active
  (engine is the deeper signal — if there are no bytes, the player's
  underrun is a symptom). When only the player is starved (engine
  reports `.healthy`/`.marginal`, but AVPlayer hit a brief underrun),
  surface as `.playerRebuffering`.
- **Buffering does not pre-empt user pause.** A `.paused` state stays
  paused even if engine reports starving — the user's intent is
  authoritative. The HUD still renders the tier indicator per
  `06-brand.md § Tier colours`.
- **Idempotent transitions are explicit.** Repeated same-state events
  (e.g. `.userTappedPlay` while already `.playing`) are no-ops and must
  not log invariant violations.

## Engine-event projection rules (mirror of D5)

Lives in `PlayerViewModel`. Drives the state machine; not part of it.

| Source                                                                 | Projected event                                  | Notes                                                                                  |
| ---------------------------------------------------------------------- | ------------------------------------------------ | -------------------------------------------------------------------------------------- |
| `engine.openStream(_:fileIndex:)` reply, descriptor non-nil            | `.engineReturnedDescriptor(d)`                   | Always exactly one event per call.                                                     |
| `engine.openStream` reply, error non-nil                               | `.engineReturnedOpenError(code)`                 | `code` derived from `NSError.code` mapped to `EngineErrorCode`; unknown → `.unknown`.  |
| `EngineEvents.streamHealthChanged(dto)`                                | `.engineHealthChanged(dto.tier)` if `dto.streamID == self.streamID`; else dropped | Tier conversion uses the typed enum from PR #146.                  |
| `EngineEvents.fileAvailabilityChanged(_:)`                             | (dropped)                                        | Not consumed by `PlayerState`. Belongs to library/HUD overlays.                        |
| `EngineEvents.diskPressureChanged(_:)`                                 | (dropped)                                        | Disk-pressure UI is engine-level, not stream-level.                                    |
| `EngineEvents.torrentUpdated(_:)`                                      | (dropped)                                        | Out of scope for `PlayerState`.                                                        |
| `EngineClient.eventsDidChangeNotification`, `events == nil`            | `.engineDisconnected`                            | Edge-triggered: only on the `valid → nil` transition.                                  |
| `EngineClient.eventsDidChangeNotification`, `events != nil`, prior nil | `.engineReconnected`                             | Edge-triggered: only on the `nil → valid` transition.                                  |
| `AVPlayer.timeControlStatus` → `.playing`                              | `.avPlayerBeganPlaying`                          | KVO observer.                                                                          |
| `AVPlayer.timeControlStatus` → `.waitingToPlayAtSpecifiedRate`         | `.avPlayerStalled`                               | When AVPlayer is waiting on buffer, not when paused.                                   |
| `AVPlayer.timeControlStatus` → `.paused` after user tap                | (no event from KVO; user tap drives `.userTappedPause` instead) | KVO observer must distinguish user pause from forced pause; default to no-op for KVO `.paused` and let the tap path drive the event. |
| `AVPlayerItem.isPlaybackBufferEmpty` rises edge                        | `.avPlayerStalled`                               | Same handler as the timeControlStatus path; debounced by the state machine's idempotence. |
| `AVPlayerItem.isPlaybackLikelyToKeepUp` rises edge after stall         | `.avPlayerResumed`                               |                                                                                        |
| `AVPlayerItem.status` → `.failed`                                      | `.avPlayerFailed`                                |                                                                                        |

## Test shape

The foundation ticket (#18) lands these test groups. Other Phase 3
tickets reuse the harnesses.

### State-machine tests (`PlayerStateMachineTests`)

- One case per cell in the transition matrix above (8 rows × 14 columns
  ≈ 112 cells; many are `inv` no-ops, but each must be asserted).
- Idempotence: applying the same event twice from a stable state is a
  no-op where the matrix says so.
- Tier-resolve edge: `.buffering(.engineStarving)` + `.engineHealthChanged(.healthy)`
  → `.playing`; `.engineHealthChanged(.marginal)` → `.playing`;
  `.engineHealthChanged(.starving)` → idem.
- Reason-swap edge: `.buffering(.playerRebuffering)` + `.engineHealthChanged(.starving)`
  → `.buffering(.engineStarving)` (engine wins).
- Race edge: `.buffering(.engineStarving)` + `.avPlayerBeganPlaying`
  → `.playing` (accept the AVPlayer signal as ground truth — see
  precedence note above).
- Invariant-violation rows: every `inv` cell returns the input state
  unchanged and emits a log; never crashes.
- Determinism: a recorded event log replays to the same final state
  regardless of `now` value variations within sane bounds.

### Resume-prompt seam tests (`ResumePromptDecisionTests`)

A small pure helper:

```swift
struct ResumePromptDecision {
    static func shouldOffer(watchStatus: WatchStatus,
                            descriptor: StreamDescriptorDTO) -> Bool
}
```

- `(watched(_), 0)` → `false`.
- `(unwatched, 0)` → `false`.
- `(inProgress(_, _), > 0)` → `true`.
- `(reWatching(_, _, _), > 0)` → `true`.
- `(inProgress(_, _), 0)` → `false` (invariant violation; logged).
- `(unwatched, > 0)` → `false` (invariant violation; logged).
- `(watched(_), > 0)` → `false` (this is a re-watch about to start; the
  user just opened a watched file, AVPlayer should start from the
  beginning, no prompt).

### View-model integration tests (`PlayerViewModelStateProjectionTests`)

Out of scope for this design doc as a deliverable, but the doc
specifies the test shape for #18's PR:

- Fake `EngineClient` returns a `StreamDescriptorDTO` with
  `resumeByteOffset = 0`. Open stream. Verify `PlayerState`
  trajectory `.closed → .buffering(.openingStream) → .open → .playing`
  after `avPlayerBeganPlaying`.
- Fake `EngineClient.openStream` errors. Verify trajectory
  `.closed → .buffering(.openingStream) → .error(.streamOpenFailed(_))`.
- Fake engine emits `.streamHealthChanged(starving)` mid-play. Verify
  `.playing → .buffering(.engineStarving)`.
- Fake engine emits `.streamHealthChanged(healthy)` after the above.
  Verify `.buffering(.engineStarving) → .playing`.
- `EngineClient` simulates a disconnect (events publisher → nil).
  Verify `.playing → .error(.xpcDisconnected)`. Reconnect simulated;
  verify state stays `.error(.xpcDisconnected)` per D6.
- User taps retry from error. Verify `.error → .buffering(.openingStream)`
  and that `engineClient.openStream` is invoked again.

## Out of scope for the foundation

- Player overlay UI / chrome / picker design (those are #22, #23, #24).
- Resume prompt copy, layout, dismissal animation (that is #19).
- Failure-state copy and retry-button placement (those are #26).
- Episode-aware logic (`.endOfEpisode` detection, "Up next" overlay,
  grace-period countdown). Deferred to the Phase 3 tail (#20, #21)
  per D1.
- Snapshot tests for any UI surface — none in this PR.
- Keyboard shortcut bindings — basic shortcuts (space, arrow, F) are a
  separate Phase 3 ticket per the spec 07 § Outstanding work bullet
  not currently on the roadmap (filing a fresh issue if it surfaces
  during implementation).

## Risks and mitigations

| Risk                                                                          | Mitigation                                                                                                              |
| ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Engine and AVPlayer disagree on "stalled" (engine healthy, player rebuffering)| Reason-swap rule in the matrix surfaces both; UI distinguishes via `BufferingReason` for #26's copy.                    |
| Auto-resume on reconnect re-attaches to a dead loopback URL                   | D6 — no auto-resume; user-driven retry only.                                                                            |
| Resume prompt flickers (state machine briefly re-enters `.open`)              | Prompt is fired once per `PlayerViewModel` lifetime, gated on a `hasOfferedResume: Bool` flag in the VM, not in the machine. |
| Missed `.engineDisconnected` event leaves the user staring at a frozen player | KVO on `EngineClient.events` is edge-triggered; debounced state-machine tests prevent regression.                       |
| Race between `.engineHealthChanged(.healthy)` and `.avPlayerStalled`          | Matrix resolves: starving precedence applies only when health is currently starving, otherwise stall reason wins.       |
| `EngineErrorCode` enum drift between projection and state machine             | `EngineErrorCode` is the single source; `PlayerError.streamOpenFailed(EngineErrorCode)` references it directly.         |

## Open questions

These are recorded here rather than written into the contract in this
pass, per the brief.

### O1 — Engine-initiated stream close

The current XPC contract (spec 03) has no `EngineEvents.streamClosed(_:)`
event. The engine can stop serving a stream (cache eviction, supervised
restart, file deletion, libtorrent error) but does not announce it. The
app would notice only by:

- Health-event silence over a timeout (no formal SLA exists).
- AVPlayer's loopback connection dropping → `.avPlayerFailed`.

The latter is what `PlayerError.streamLost` is reserved for in D2's
type sketch. It is currently unreachable in v1 because no projection
edge fires it.

**Recommendation for Phase 3 implementation:**

- Phase 3 implementation PRs may detect "no health event in N seconds
  while in `.playing`" and project `.engineDisconnected` as a heuristic
  fallback. Conservative.
- A clean answer is `EngineEvents.streamClosed(streamID, reason)` with
  reason `.evicted | .engineRestart | .underlyingError(NSError)`.
  Adding it requires:
  - DTO addition (or `NSString` + `NSError` parameters per A1's request
    versioning rule — events follow the same DTO discipline).
  - `EngineXPCProtocol.swift` and `EngineEventsProtocol.swift` updates.
  - `XPCInterfaceFactory` allowed-classes update.
  - Bidirectional mapping in `XPCMapping`.
  - A new addendum item (would be A27).

If #18's implementation hits a real case where this matters,
**stop and escalate to Opus** for an addendum + contract bump in a
separate PR. Do not bundle it into the foundation feature PR.

### O2 — Spec 03 drift (out of scope to fix here)

`StreamDescriptorDTO.resumeByteOffset` exists in the
`EngineInterface` source (`schemaVersion = 2`) but is not reflected in
spec 03's DTO definition prose. This is doc-hygiene drift, not a Phase 3
concern. Filing as a separate doc-only follow-up so spec 03 catches up
with the code.

### O3 — Engine-side stream-close acknowledgement

When `PlayerStateMachine` reaches `.closed` via `userTappedClose`, the
VM issues `engine.closeStream(streamID)`. The reply is fire-and-forget
in v1. If the engine returns an error (e.g. unknown stream because of a
race), the model does not surface it — the user has already moved on.
This is deliberate and matches the existing `PlayerViewModel.close()`
contract.

## Cross-references

- Phase 1 foundation: [`docs/design/watch-state-foundation.md`](watch-state-foundation.md)
  — `WatchStatus`, `WatchStateMachine`, `PlaybackHistoryDTO`,
  `listPlaybackHistory` / `playbackHistoryChanged`. Consumed by #19's
  resume prompt seam.
- Phase 2 foundation: subtitle model and `SubtitleTrack` (Epic #4 #27).
  Consumed by #22's track picker. The foundation does not constrain
  `PlayerState`; subtitle picker UI is a sibling overlay that observes
  but does not drive the state machine.
- Engine surface: `02-stream-health.md` (tier semantics),
  `03-xpc-contract.md` (DTOs and events).
- Brand: `06-brand.md § Window chrome`, `§ Tier colours`, `§ Voice` —
  every `PlayerState` value has a brand-compliant rendering specified
  in the dependent tickets (#22, #23, #24, #26).
- Roadmap: `docs/v1-roadmap.md § Phase 3` — Option A recorded in the
  cross-phase dependency note.
