# v1 Roadmap — Product-Surface Execution Plan

**Status:** 2026-04-16 — engine tracker (`.claude/tasks/TASKS.md`) is DONE through Phase 7 hardening. All remaining v1 work is **product-surface** per `.claude/specs/07-product-surface.md` and is tracked as GitHub issues per `.claude/specs/08-issue-workflow.md`.

This document is the **canonical execution plan** for the p0 v1 product-surface work. It answers: what's next, what's blocked, and in what order. Start here before picking up any p0 issue.

## Why this doc exists

Every p0 feature ticket in the v1 milestone was created with `## Acceptance criteria\n\n(populate before picking this up)` — a deliberate signal that each one needs an Opus design pass before implementation. The engine tracker has phases and gates; the product-surface tracker does not, because issues are flat by nature. This roadmap imposes the phase/gate structure on the issue set without restructuring every issue body.

**If this doc and an issue body disagree**, the doc wins. When an issue is picked up, its acceptance criteria will be populated per the design decisions made here.

## What "v1" means

Per `spec 07 § Definition of a credible v1`, a user must be able to open the app, browse/search titles, open a detail page, select and play content, load subtitles, pause and resume, see continue-watching, optionally sync to an external account, and recover from common failures.

That flow decomposes into four p0 epics (Discovery, Playback UX, Subtitles, Watch State) plus four p1 epics (Account Sync, Provider Abstraction, Settings, Native macOS polish). This doc plans the **p0 work only**. P1 work gets its own roadmap entry once p0 is done — and some p1 decisions (see § Open questions) are prerequisites for p1 execution, not for p0.

## Engine readiness

All engine dependencies for p0 work are in place:
- `T-XPC-INTEGRATION` DONE — XPC boundary is real, event flow verified.
- `T-STORE-SCHEMA` DONE — `playback_history`, `pinned_files`, `settings` tables exist via GRDB.
- `T-STREAM-E2E` DONE — end-to-end playback works against a real torrent.
- `T-CACHE-EVICTION-WIRE` DONE — disk pressure + eviction shipped.
- Phase 6 UI foundations (`T-UI-LIBRARY`, `T-UI-PLAYER`, `T-UI-HEALTH-HUD`) DONE — brand-compliant library and player shells are built and reviewed.

**Missing engine seams** that may surface during p0 execution (each gets a fresh engine issue when encountered):
- `favourites` table (Epic #5 — #36 needs it). **Filed as `T-STORE-FAVOURITES` in `TASKS.md` Phase 8 during the Phase 1 design pass (2026-04-16).**
- `playback_history.completed_at` column + `listPlaybackHistory` / `playbackHistoryChanged` XPC surface (Epic #5 — #34 foundation). **Bundled into the #34 foundation PR per `docs/design/watch-state-foundation.md`; spec 05 → rev 5, addendum A26.**
- Watched-seconds reporting path (spec 05 § exclusion list; anchored in spec 03 exclusion list per F6 — v1.1).
- Episode metadata association with `playback_history` (Epic #2 + #5 interaction).

## Four-phase execution

Phases are ordered smallest/cleanest first to build momentum and expose cross-epic dependencies early. Each phase completes before the next begins — this is a checkpoint boundary, not a suggestion.

Every phase follows the same protocol:
1. **Opus design pass** — populate acceptance criteria on every issue in the phase; write a short `docs/design/<epic-slug>-foundation.md` covering the foundation ticket's types and transitions.
2. **Foundation PR** — implement the foundation ticket first; merge before dependent tickets.
3. **Dependent tickets** — one PR per ticket, small and reviewable. Order follows the in-phase dependency graph below.
4. **Phase close** — all tickets in the phase are closed; epic tracker issue is closed.

### Phase 1 — Watch state and local library (Epic #5)

**Why first:** smallest surface, most engine-adjacent, strengthens the existing library/player shells without touching new external services. A credible Phase 1 is a proof that the phased approach works.

**Foundation:** **#34** — watched-state transitions (`in-progress → watched → re-watching`). Defines `WatchStatus` enum, the deterministic transition state machine, the new `Packages/LibraryDomain` package, the `completed_at` schema column (V2 migration; spec 05 rev 5; addendum A26), and the `listPlaybackHistory` + `playbackHistoryChanged` XPC additions. **Full design:** [`docs/design/watch-state-foundation.md`](design/watch-state-foundation.md).

**Dependent tickets (merge after foundation):**
- **#35** continue-watching row generation (depends on #34 state model + `listPlaybackHistory` / `playbackHistoryChanged` XPC surface).
- **#37** manual mark-watched / mark-unwatched actions (depends on #34 transitions + the new `setWatchedState` XPC method introduced alongside).
- **#36** favourites with new schema table (independent of #34; depends on engine task `T-STORE-FAVOURITES` in `TASKS.md` Phase 8).

**Deferred / reassigned:**
- **#72** (macOS: drag-and-drop subtitle files) is labelled `module:macos` but is functionally the same as **#28** (Subtitles: drag-and-drop SRT ingestion onto player). Consolidate in Phase 2 — likely close #72 as duplicate of #28 or split into "drop anywhere in app" vs "drop on player window" if product decides both are needed.

**Out of scope for Phase 1:**
- Remote (Trakt) sync of watch state — that's Epic #5-adjacent but lives in the p1 Account Sync epic.
- Clear-history / reset-state controls — deferred to Epic #7 (Settings) at p1.

**Phase 1 done =** #34, #35, #36, #37 closed; epic #5 closed; `WatchStatus` is used by the player view model; continue-watching row renders from real data.

### Phase 2 — Subtitles (Epic #4)

**Why second:** self-contained (mostly AVKit + ingestion), no cross-module dependencies, and unblocks Phase 3's subtitle picker (#22).

**Foundation:** **#27** — define `SubtitleTrack`, the sidecar SRT parser, and the language resolver. Lands the new `Packages/SubtitleDomain` package (pure Swift, AVKit-free) plus the ingestion / selection / fallback contracts used by #28, #29, #30, #32. **Full design:** [`docs/design/subtitle-foundation.md`](design/subtitle-foundation.md).

**Dependent tickets (merge after foundation):**
- **#28** drag-and-drop SRT ingestion onto the player window. **Consolidates #72** — closed as duplicate during the Phase 2 design pass (design doc D4).
- **#29** selection UI (depends on #27; surfaces in the player HUD; consumed verbatim by Phase 3 #22).
- **#30** persist preferred language in `UserDefaults` under `"subtitles.preferredLanguage"` (design doc D6 — revision of the previous "writes to `settings` table" wording; preference is pure UI state, no engine round-trip).
- **#32** fallback when load fails (depends on #28 + #29; HUD banner, one-at-a-time, per `06-brand.md` voice — see design doc § Fallback matrix).

**Out of scope for Phase 2:**
- OpenSubtitles search — explicitly deferred per `01-architecture.md § What v1 explicitly excludes`.
- Sidecar WebVTT / ASS / SSA / image-based subtitles — deferred per design doc D2.
- Cross-session sidecar persistence — explicit v1 limitation per design doc D5.
- Subtitle offset / styling controls — v1.5+ per spec 07.

**Status (2026-04-17):** design merged (PR #157); foundation #27 merged (PR #161 — `Packages/SubtitleDomain`, 46 tests); app integration (#28/#29/#30/#32) **PAUSED**. PR #171 was closed without merge after `main` diverged mid-flight — PRs #164 (PlayerState foundation), #166 (overlay controls), and #167 (resume prompt) reshaped `PlayerView` / `PlayerViewModel` around `PlayerDomain.PlayerState` and the `PlayerOverlay` / `PlayerScrubBar` chrome, making the branch's player-integration commits stale against the new shape. The subtitle implementation (SubtitleController, SubtitleIngestor, SubtitleOverlay, SubtitleSelectionMenu, SubtitlePreferenceStore, SubtitleErrorBanner + 25 unit tests + 22 snapshot baselines) is preserved on dangling commit `4308cdc`. See epic #4 for the pickup plan.

**Phase 2 done =** #27, #28, #29, #30, #32 closed; #72 closed as duplicate of #28; epic #4 closed; user can drag a `.srt` onto the player, pick a track, and have the preference persisted across launches.

### Phase 3 — Playback UX (Epic #3)

**Why third:** depends on Phase 1 foundation (#34 watched-state for resume prompt) and Phase 2 foundation (#27 subtitle model for the track picker). Waiting until these are done keeps Epic #3 from growing its own forks of those models.

**Foundation:** **#18** — define player state model (`.open | .playing | .paused | .buffering | .error | .closed`). The state machine drives every other Playback UX ticket; get this wrong and the whole epic churns.

**Dependent tickets (merge after foundation), grouped by sub-area:**

*Resume flow:*
- **#19** implement resume prompt logic (needs #18 + **#34** from Phase 1).

*Episode flow:*
- **#20** end-of-episode detection (needs #18 + episode metadata from Phase 4 **#11** — see cross-phase note below).
- **#21** next-episode auto-play with grace period (needs #20 + #18).

*Track selection:*
- **#22** subtitle track picker UI (needs #18 + **#29** from Phase 2).
- **#23** audio track picker UI (needs #18).

*Chrome and error paths:*
- **#24** design player overlay controls per `06-brand.md` (needs #18).
- **#26** failure states and retry paths (needs #18 + engine event contract from spec 03).

**Cross-phase dependency note:** #20 and #21 depend on episode metadata that only exists after Phase 4's foundation (#11). Two options were considered during Phase 3's Opus design pass:
- **Option A (chosen, 2026-04-16):** land #18, #19, #22, #23, #24, #26 in Phase 3; defer #20 + #21 to a Phase 3 tail that runs after Phase 4's #11 lands. Keeps Phase 3 shippable without movies-only being a regression. Rationale: #21 is fundamentally a metadata feature; stubbing leaks into the foundation type and forces a migration when #11 lands. Full reasoning in [`docs/design/player-state-foundation.md § D1`](design/player-state-foundation.md).
- ~~**Option B:** stub episode metadata in Phase 3 with a minimal inline type, then migrate to the real schema in Phase 4. Higher refactor cost but unblocks Phase 3 fully.~~ Rejected.

**Out of scope for Phase 3:**
- Keyboard shortcuts beyond space/arrow/F (rest is v1.5+).
- PiP, AirPlay, external player handoff — p2 per spec 07.
- Playback speed controls — v1.5+.

**Phase 3 done =** #18–#26 closed per option chosen above; epic #3 closed; every player surface routes through `PlayerState` rather than ad-hoc booleans.

### Phase 4 — Discovery and metadata (Epic #2)

**Why last:** largest surface (browse hierarchy, search, detail pages, season/episode selectors), touches an external network service (TMDB), and provides the inputs that Phase 3's tail (#20, #21) and Phase 1's #35 (continue-watching) consume fully.

**Foundation:** **#11** — define metadata schema for movie, show, season, episode. The long-standing "needs-design (which metadata source?)" note on the ticket is **resolved (2026-04-16)** by the spike at [`docs/spike-metadata-sources.md`](spike-metadata-sources.md) plus the Phase 4 design pass at [`docs/design/discovery-metadata-foundation.md`](design/discovery-metadata-foundation.md): **TMDB primary** for metadata, browse rows, search, and artwork; **Trakt is reserved for Module 5 (Account Sync, p1)** and is not a Phase 4 concern. Produces the Swift types, the new `Packages/MetadataDomain` package, the `MetadataProvider` protocol + `TMDBProvider` impl, the on-disk JSON cache with TTLs, and the pure name-parser + match-ranker that downstream "torrent file → TMDB title" flows consume.

**Dependent tickets (merge after foundation):**
- **#13** design browse hierarchy and navigation (sidebar + home screen rows; depends on #11). Row set per `discovery-metadata-foundation.md § D11`.
- **#14** implement search and result ranking — **TMDB-backed via `/search/multi` per `discovery-metadata-foundation.md § D10`**, debounced; not a local index. Depends on #11.
- **#15** build title detail page UI (depends on #11, #14 for entry, and `06-brand.md` for chrome).
- **#16** build season/episode selector UI (depends on #15 + #11 episode schema).
- **#17** continue-watching row from local state (depends on #11 for metadata projection + matching seam per `discovery-metadata-foundation.md § D9`, plus **#35** from Phase 1 for the underlying `playback_history` feed).

**Phase 3 tail (Option A confirmed 2026-04-16):**
- **#20** end-of-episode detection — needs episode schema from #11.
- **#21** next-episode auto-play — needs #20 + episode schema from #11.

**Out of scope for Phase 4:**
- Related / recommended titles beyond what Trakt's stock endpoints provide (richer recommendations are p2).
- Advanced sort/filter (p2).
- Trailers / extras (p2).

**Phase 4 done =** #11, #13, #14, #15, #16, #17 closed (+ #20, #21 if in tail); epic #2 closed; the "Definition of a credible v1" walkthrough in spec 07 § passes end-to-end manually.

## Dependency graph (at-a-glance)

```
Phase 1 (Watch state)                    Phase 2 (Subtitles)
    #34 ──┬── #35 ◄────────┐                 #27 ──┬── #28 (+ #72 consolidated)
          ├── #37          │                       ├── #29 ◄──────────┐
          └── #36 (new engine issue: favourites)   │    │              │
                                                  ├── #30 (needs #29) │
                                                  └── #32 (needs #28+#29)
                                                                      │
Phase 3 (Playback UX)                                                 │
    #18 ──┬── #19 (needs #34 from P1)                                 │
          ├── #22 (needs #29 from P2) ◄──────────────────────────────┘
          ├── #23
          ├── #24
          └── #26
                ↓
            [Option A tail after Phase 4]
                ↓
          ├── #20 (needs #11 from P4)
          └── #21 (needs #20)

Phase 4 (Discovery)
    #11 ──┬── #13
          ├── #14
          ├── #15 ── #16
          └── #17 (needs #35 from P1)
```

## Cross-cutting conventions

**Per issue workflow** — follow `.claude/specs/08-issue-workflow.md`:
- Branch: `feature/<issue-slug>-<N>` or `fix/…` or similar.
- PR body: `Closes #N`.
- Opus reviews at foundation tickets and at each phase boundary.

**What "foundation PR" includes:**
- Types / model definitions only (no UI wiring beyond the minimum needed to compile).
- Unit tests for transitions, serialisation, edge cases.
- Brand tokens, motion tokens, or voice copy touched only if the foundation requires them.
- No dependent-ticket functionality — that's what the dependent tickets are for.

**Snapshot tests:** every Phase 3 and Phase 4 ticket that introduces or changes a SwiftUI surface must add light-mode + dark-mode snapshots per `06-brand.md § Test obligations`. Follow the pattern already established by `LibrarySnapshotTests` and `PlayerHUDSnapshotTests`.

**Brand compliance** (per `06-brand.md`): every UI PR uses brand tokens exclusively (no raw `Color.black`, no system green/yellow/red); glass only on floating chrome; motion uses value-tied `.easeInOut`, not springs; empty/error copy follows the calm brand voice. Opus will bounce PRs that violate these in review.

## What's NOT in this roadmap

**p1 epics** — Account Sync (#6), Provider Abstraction (#7), Settings/Diagnostics (#8), Native macOS polish (#9). These come after p0 completes. A p1 roadmap should be written at that point; its shape depends on decisions #75–#79 (which are intentionally still open).

**Deferred items per spec 07:** External player handoff, AirPlay, PiP, advanced filter/sort, rich recommendations, trailers, downloads, custom themes. Do not reopen during p0 work.

**Engine work:** none expected, but the `favourites` table migration (#36) and possibly the watched-seconds reporting path (v1.1) will spawn fresh engine tickets in `TASKS.md` if needed.

## Open questions that could bite p0 work

These are not blockers for Phase 1, but they become relevant later:

- **#11 metadata source** — decision recorded: TMDB + Trakt. Authentication posture (embedded keys for personal use) per memory. Revisit if app scope expands beyond personal-use.
- **#78 offline/download scope** (p1) — does not block p0 but the `pinned_files` table already exists; watch for Phase 4 conflating "pin" with "download".
- **Sync conflict rules** (Epic #5) — p1 concern; flag during Phase 1 foundation design so #34 doesn't hard-code single-device assumptions.
- **Player overlay control set** (#24) — needs an Opus design call; `06-brand.md § Window chrome` has the direction but not the exhaustive list.

## How to use this doc

**Starting a phase:** open the foundation ticket, do the Opus design pass (populate acceptance criteria on every ticket in the phase, write the foundation design doc), then implement the foundation, then dependent tickets in order.

**Picking up a single ticket:** check the phase it belongs to; check blockers; if blocked, don't start — work the blocker first. Don't pick up a ticket whose foundation PR hasn't landed.

**Closing a phase:** verify every ticket in the phase is closed, close the epic, update memory (`project_session_resume.md`) with the new resume point.

**Updating this doc:** any change to phase ordering, dependencies, or scope is an Opus decision. Record the change with a date and a one-line rationale in a revision block at the top of this doc, preserving history. Do not rewrite silently.
