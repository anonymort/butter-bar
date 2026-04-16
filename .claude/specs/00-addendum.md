# 00 — Addendum (revision 1)

This addendum records decisions made during the pre-implementation review pass. It exists to resolve contradictions and under-specifications in specs 01–05 without rewriting them. Where an addendum item conflicts with a numbered spec, the **addendum wins** and the affected spec has been updated to reference this file.

## A1 — XPC request versioning

**Problem:** `03-xpc-contract.md` (rev 1) claimed the engine would reject requests with a newer `schemaVersion` than it understands, but several request methods take raw `NSString`/`NSNumber` parameters with no DTO and therefore no version field.

**Decision (v1):** Only **response and event DTOs** are versioned in v1. Request-side versioning is deferred to v2 and will require a contract bump if request signatures change.

**Implications:**
- `schemaVersion` on response/event DTOs remains meaningful: the client may reject replies whose `schemaVersion` it does not understand.
- Adding fields to an existing response DTO requires a new DTO type with an incremented `schemaVersion`, not a field addition to the v1 DTO.
- Adding a new request method is backward-compatible (clients that don't know it simply don't call it).
- **Changing** the signature of an existing request method is a breaking change and must be accompanied by a contract bump.

Spec 03 has been updated to state this explicitly in its Versioning section.

## A2 — T-XPC-SERVER-SKELETON behaviour

**Problem:** The task description said "all methods return stubbed `notImplemented`" but the acceptance said `listTorrents` returns an empty array. Contradiction.

**Decision:** The acceptance wins. Specifically:
- `listTorrents(_:)` returns `[]`.
- `subscribe(_:reply:)` succeeds with `nil` error and simply retains the client proxy weakly; no events are actually emitted in the skeleton.
- All other methods return `NSError(domain: "com.butterbar.engine", code: .notImplemented)`.

Rationale: this gives the app a safe read-only path to connect against for XPC plumbing tests without forcing the client to interpret `notImplemented` as the expected answer for a normal list query.

`TASKS.md` T-XPC-SERVER-SKELETON has been updated.

## A3 — PiecePlanner is a deterministic state machine, not a pure function

**Problem:** `04-piece-planner.md` rev 1 called the planner a "pure function of input events and availability schedule," but the planner plainly needs internal state: recent served byte ranges, outstanding request IDs, last-emitted `StreamHealth`, last emission time for throttling, last activity time, current readahead window target.

**Decision:** The planner is a **deterministic state machine**, not a pure function. The distinction matters:
- **Deterministic:** given the same initial state + the same sequence of inputs at the same timestamps, the planner produces the same sequence of outputs every run. This is what the replay tests verify.
- **Stateful:** the planner instance owns mutable internal state between calls. That state is allowed and expected.
- **Non-requirements:** no real clocks, no threading, no `DispatchQueue`, no randomness, no I/O.

Testability is preserved by injecting time (`Instant` is a method parameter, never read from the system clock) and by injecting the `TorrentSessionView`.

Spec 04's opening paragraph has been updated.

## A4 — Seek event ownership

**Problem:** `PlayerEvent` in spec 04 included `.seek(toByteOffset:)`, but the same spec said seek was "planner-internal, derived from non-contiguous GETs." Meanwhile `T-GATEWAY-PLANNER-WIRING` said the gateway converts every incoming request to a `PlayerEvent`, which leaves no obvious source for a `.seek` event.

**Decision:** `.seek` is **removed from the public `PlayerEvent` enum**. The gateway emits only `.head`, `.get`, and `.cancel`. The planner detects seeks internally by comparing incoming GET ranges to its own record of most-recently-served bytes, and branches to its seek policy without needing an external signal.

This simplifies the gateway (it no longer needs to track anything) and eliminates a fake abstraction.

Spec 04 § Inputs and § Policies have been updated.

## A5 — Zero/unknown download rate fallback for deadline spacing

**Problem:** Spec 04 rev 1 said readahead deadlines are spaced by `pieceLength / observedRate` with a floor of 200 ms per piece. On first play, `observedRate` is plausibly zero, which divides by zero.

**Decision:** Explicit fallback. When `observedRate < 100 KB/s` (functionally zero or unmeasured):
- First 4 readahead pieces: 250 ms spacing.
- Next 4 readahead pieces: 500 ms spacing.
- Remaining pieces in the window: 1000 ms spacing.
- Re-evaluate spacing on every `tick` once rate becomes measurable (≥ 100 KB/s sustained for 2 consecutive ticks).

Critical-priority pieces (the playhead window) always use the existing 0/100/200/300 ms schedule regardless of observed rate.

Spec 04 § Policies has been updated.

## A6 — Byte→time mapping for resume offsets (v1 weakening)

**Problem:** `05-cache-policy.md` rev 1 required `resumeByteOffset` to be computed via "the gateway's byte→time map." No such subsystem is specified or scheduled, and building one is non-trivial (VBR content, late moov, Matroska cues, partial metadata).

**Decision for v1:** Weaken the cache spec. `resumeByteOffset` is persisted as **the last byte offset successfully served to the player**, not a time-accurate seek point. On resume, the UI offers "continue from where you stopped" which issues a fresh stream open; AVPlayer handles seeking to a reasonable keyframe near that byte offset, which is good enough for v1.

A true byte→time map is deferred to v1.5 or later. The spec should not pretend it exists.

Spec 05 § Resume offset persistence has been updated. The `total_watched_seconds` column is retained for future use but is populated from `CMTime.seconds` observations rather than from a byte→time conversion.

## A7 — Settings table schema

**Problem:** `05-cache-policy.md` rev 1 said explicitly kept files are stored in the `settings` table as `(torrentID, fileIndex)` tuples, but no schema or task created that table.

**Decision:** Add a minimal `settings` table and associated GRDB migration. Schema:

```sql
CREATE TABLE settings (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,           -- JSON-encoded
    updated_at INTEGER NOT NULL    -- unix ms
);

CREATE TABLE pinned_files (
    torrent_id TEXT NOT NULL,
    file_index INTEGER NOT NULL,
    pinned_at INTEGER NOT NULL,    -- unix ms
    PRIMARY KEY (torrent_id, file_index)
);
```

Rationale for splitting: the generic `settings` key-value table is useful for engine-wide state (budget thresholds, observed bitrate caches, etc.), while pinned files have relational structure that deserves its own table.

A new task `T-STORE-SCHEMA` has been added to Phase 2 and is a prerequisite for `T-CACHE-SCHEMA`.

## A8 — `FileAvailabilityDTO.availableRanges` cleanup

**Problem:** Spec 03 rev 1 defined `availableRanges: [NSArray]` as nested numeric pairs. This is awkward to decode with `allowedClasses` and annoying to debug.

**Decision:** Introduce a proper `ByteRangeDTO` object and change the field to `[ByteRangeDTO]`.

```swift
@objc(ByteRangeDTO)
public final class ByteRangeDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }
    public let startByte: Int64
    public let endByte: Int64   // inclusive
}
```

Spec 03 § DTO definitions has been updated.

## A9 — StreamHealth throttle state ownership

**Problem:** Spec 02 rev 1 required throttled emission (2 Hz cap, immediate on tier transition), which implies the planner owns throttle state. This was left implicit.

**Decision:** Throttle state (last emission time, last emitted tier) lives **inside the planner**. This is consistent with A3 (planner is a deterministic state machine). Spec 02 has been updated to name the owner explicitly.

## A10 — Required bitrate inference scope

**Problem:** Spec 02 rev 1 defined two paths for learning `requiredBitrateBytesPerSec` (container metadata and observed sustained rate), but no task implements the container-metadata path. In practice v1 will run with `requiredBitrateBytesPerSec == nil` for the first 60 seconds of every stream.

**Decision:** Accept that. The observed-sustained-rate path is the v1 implementation. Container-metadata probing is a v1.5 enhancement tracked as a follow-up. Spec 02 has been updated to mark the container-metadata path as "v1.5+."

## A11 — Spec 01 stale "pure function" wording

**Problem:** `01-architecture.md` line 92 still described `PiecePlanner` as a "Pure function of `(trace events, availability schedule) → (planner actions)`," contradicting `CLAUDE.md`, A3, and spec 04.

**Decision:** Replace the line in spec 01 § PiecePlanner (pure Swift) with the deterministic-state-machine wording, with an explicit pointer to A3.

Spec 01 has been updated.

## A12 — Spec 01 vs spec 05 table list drift

**Problem:** `01-architecture.md` § Store (GRDB) listed five tables (`torrents`, `files`, `stream_sessions`, `playback_history`, `settings`) but spec 05 § Schema only defines three (`playback_history`, `pinned_files`, `settings`). Three tables are referenced but undefined; one defined table is missing from spec 01.

**Decision:** Spec 01 lists exactly the three tables defined in spec 05 (`playback_history`, `pinned_files`, `settings`), with a one-line note that active torrent state, file lists, and stream sessions are held in memory by libtorrent and the engine respectively, not persisted.

Rationale for the in-memory choice: libtorrent already owns active torrent state (resume data is its responsibility); file lists are derived from torrent metadata on demand; stream sessions are by definition ephemeral. Persisting them would create a second source of truth and a class of consistency bugs we don't need.

Spec 01 has been updated.

## A13 — Spec 04 expected-actions example contradicts deadline-spacing rules

**Problem:** `04-piece-planner.md` § Expected action format showed pieces 0/1/2 at 0/250/500 ms with mixed critical/readahead priorities, but § Deadline spacing requires the first 4 pieces to be `critical` at 0/100/200/300 ms regardless of observed rate.

**Decision:** Rewrite the expected-actions example so it derives correctly from the deadline-spacing rules. Add a meta-rule: any in-spec example must be a valid planner output, and T-PLANNER-FIXTURES must verify each example mechanically rather than trusting the prose.

Spec 04 has been updated. The example now shows pieces 0–3 as `critical` with the fixed schedule, then readahead pieces using the zero-rate fallback (250/500/1000 ms tiers per A5).

## A14 — Agent role files must read the addendum

**Problem:** Both `opus-designer.md` and `sonnet-implementer.md` reading orders skipped `00-addendum.md`. The addendum is the precedence layer per CLAUDE.md, but agents following their own role file's reading order would never see it. This breaks the entire override mechanism.

**Decision:**
- `opus-designer.md` reading order has the addendum inserted as item 2 (after CLAUDE.md, before spec 01).
- `sonnet-implementer.md` reading order has the addendum as a mandatory item — Sonnet must always read the addendum even if the task only references one numbered spec.
- T-SPEC-LINT acceptance criteria gain a sub-bullet that verifies both agent role files reference the addendum, to defend against regression.

Both agent files have been updated.

## A15 — Tick → health emission timing

**Problem:** `04-piece-planner.md` § Tick said "Recompute StreamHealth" but didn't say *when* to emit it as a `PlannerAction`. Spec 02 § Emission rules defined the throttle (2 Hz cap, immediate on tier transition) but didn't tie it to the `tick`/`handle` output stream. This left fixture authoring under-specified — T-PLANNER-FIXTURES couldn't deterministically place `emitHealth` actions in expected outputs.

**Decision:** Spec 04 § Tick is updated with explicit emission rules:

A `tick(at: time, ...)` call emits a `.emitHealth(StreamHealth)` action when **any** of these is true:
1. Computed tier differs from the last emitted tier (immediate, regardless of throttle).
2. ≥ 500 ms have elapsed since last emission **and** any field of `StreamHealth` differs from the last emitted value.
3. No prior emission has occurred (first tick after stream open).

Otherwise `tick` emits no `emitHealth` action. The same rules apply to `handle(event:)` calls: an event that changes tier or that crosses the 500 ms throttle window with a field change emits `emitHealth`.

The planner's internal throttle state (last emission time, last emitted `StreamHealth`) advances only when an `emitHealth` action is actually produced, never on a "would-have-emitted-but-throttled" decision.

Spec 04 § Tick has been updated.

## A16 — Brand spec added (ButterBar rebrand)

**Context:** The project has been rebranded from PopcornMac to ButterBar. The brand position has shifted from "popcorn-time-aesthetic torrent client" to "premium native macOS media player." This affects every file that mentions the project name and adds a new spec covering visual identity, voice, and asset specifications.

**Decision:**
- New file `.claude/specs/06-brand.md` is the authoritative source for visual identity, voice, colour palette, typography, motion language, logo specifications, and UI tone.
- All references to `PopcornMac` / `popcornmac` across the pack have been updated to `ButterBar` / `butterbar`. This includes the Xcode target name, the engine error domain (`com.butterbar.engine`), and all prose.
- Spec 02 § UI rendering contract gains a pointer to `06-brand.md` § Tier colours; the tier-colour mapping is fixed in the brand spec, not redefined in the StreamHealth spec.
- Phase 6 UI tasks (T-UI-LIBRARY, T-UI-PLAYER, T-UI-HEALTH-HUD) gain explicit `06-brand.md` references. The HUD task acceptance now requires brand-compliant tier colours and the cocoa 60% opacity HUD background.
- A new `T-BRAND-ASSETS` task is added to Phase 6 covering logo creation and `AppIcon.appiconset` population. This is `[either]`-tagged — it can be done by Sonnet given the brand spec, or by Opus if a design judgement call is needed.

**Reading order impact:** the brand spec is item 7 in the reading order (between spec 05 and TASKS.md). It is required reading for any UI task in Phase 6 but optional for Phase 0–5 implementation work.

Spec 02 has been updated. CLAUDE.md and `.claude/README.md` have been updated. TASKS.md has been updated. Both agent role files have been updated to mention the brand spec.

## A17 — Engine and product surface layering

**Context:** The pack now contains two layers of specs:

- **Engine layer** (specs 01–05): the playback substrate — torrent core, piece planner, XPC, gateway, cache. These describe how Butter Bar plays bytes.
- **Product surface layer** (spec 07): the user-facing surface — discovery, metadata, account sync, subtitles, watch state, provider abstraction. These describe what the user sees and does.

Plus two cross-cutting specs:

- **Brand** (spec 06): visual identity and voice. Applies to product surface, irrelevant to engine.
- **Issue workflow** (spec 08): how the product surface is tracked as GitHub issues. Engine work continues to use `TASKS.md`.

**Decision:** the layers are non-overlapping and connect at three explicit seams:

1. **Provider abstraction (spec 07 § Module 6) sits on top of TorrentBridge (spec 01).** A torrent provider is one implementation of `MediaProvider`; it calls into the engine's `addMagnet` / `openStream` XPC methods (spec 03). Non-torrent providers are v1.5+; the interface must be designed so they can be added without breaking changes.

2. **Playback UX (spec 07 § Module 2) sits on top of the planner/gateway/cache (specs 04–05).** The UX layer never touches the gateway URL except as a source for `AVPlayer`. State events arrive via `EngineEvents` subscriptions per spec 03.

3. **Watch state (spec 07 § Module 4) sits on top of `playback_history` (spec 05).** The byte-accurate resume offset in spec 05 is presented to the user as time-accurate via AVPlayer's time observer; the engine never converts. The v1.1 watched-seconds reporting method (anchored in spec 03 exclusion list per F6) is what closes this gap properly.

**Trackers:**
- Engine work tracked in `.claude/tasks/TASKS.md`. Phased, dependency-ordered, Opus/Sonnet routed.
- Product surface work tracked as GitHub issues per spec 08. Eight epics (one per module), milestoned to v1 / v1.1 / v1.5+.

**Sequencing:** the engine build plan completes Phases 0–5 before most product-surface issues become actionable. Phase 6 of the engine plan (UI tasks) is the first place the two trackers interleave. Product-surface P0 issues should not be picked up until the engine is at least at Phase 5 (T-STREAM-E2E green).

**Reading order impact:** specs 07 and 08 are added as items 9 and 10 in the reading order. They are required reading for product-surface work and for any agent invocation that creates GitHub issues. They are optional for pure engine work in Phases 0–5.

Spec 07 has been added. Spec 08 has been added. CLAUDE.md, `.claude/README.md`, `TASKS.md`, and both agent role files have been updated.

## A18 — macOS Tahoe targeting and supplied icon package

**Context:** The deployment target has been formalised at **macOS Tahoe (26)**. This affects the brand spec (logo format, glass treatment), introduces a new platform spec, and supersedes the earlier Big Sur+ squircle masking note that lived in spec 06 rev 1. Separately, the logo asset package has been supplied as a complete deliverable, removing the need for the Gemini logo-generation prompt that previously lived in `docs/`.

**Decision:**

1. **New spec `09-platform-tahoe.md`** — authoritative platform spec. Covers:
   - macOS 26.0 minimum deployment target (no support for Sequoia or earlier in v1).
   - macOS 26 SDK build requirement (Xcode 26+).
   - Apple silicon priority; supported Intel models inherited from Tahoe's hardware list.
   - Liquid Glass adoption stance (adopted, not opted out — `UIDesignRequiresCompatibility` left unset).
   - Hardened runtime, App Sandbox, notarisation requirements.
   - CI implications (macOS 26 runners, Xcode 26).

2. **Spec 06 (Brand) bumped to rev 2** with Tahoe-specific changes:
   - Logo concept rewritten to match the supplied package: butter pat resting on bar/shelf with a carved play symbol. Three ideas (butter, bar, play) in a single mark.
   - Asset specifications rewritten around the supplied `icons/` folder.
   - Icon workflow migrated from `AppIcon.appiconset/` (raster sizes) to `AppIcon.icon` (Apple's new Icon Composer format introduced in Tahoe).
   - Squircle compliance section added.
   - Liquid Glass section added — glass is for floating navigation chrome only.

3. **Spec 02 (StreamHealth)** unchanged in content; pointer to "06-brand.md § Tier colours" still resolves correctly.

4. **`docs/logo-generation-prompt.md` removed.** The Gemini prompt is no longer needed because the logo package has been supplied.

5. **`T-BRAND-ASSETS` task** rewritten to consume the supplied package and run it through Icon Composer.

6. **Reading order:** spec 09 added as item 9; specs 07/08 shift to 10/11.

**Note:** A18's spec 06 rev 2 had two imprecisions — `.icon` placement and layer model — that were corrected in A19. Read A19 immediately after A18 for the up-to-date workflow.

## A19 — Liquid Glass icon prep package and corrected Icon Composer workflow

**Context:** A second, more detailed icon asset deliverable has been supplied — the **Liquid Glass prep package** at `icons/ButterBar-LiquidGlass-prep/`. This package contains layered transparent PNGs ready for direct import into Apple's Icon Composer, plus a revised SVG master, a flattened preview, and size exports for legibility testing. It supersedes the flat `butter-bar-logo-1024.png` as the source for the `.icon` bundle.

Separately, while writing the workflow into spec 06 rev 2 (per A18), two things were imprecise:

1. The `.icon` placement was specified as `App/Assets.xcassets/AppIcon.icon`. **This is wrong.** Apple's documented Xcode integration places the `.icon` file at the **same level as `Assets.xcassets`**, not inside it. The `.icon` is its own first-class project asset, dragged into the project navigator and referenced via the target's "App Icon Set Name" setting.

2. The layer model was described as "four appearance variants" without distinguishing variants from the `.icon` format's actual structure: a **background plus up to four foreground layer groups**, each with independent material properties (specular, blur, translucency, shadow). The system uses these layers to generate the dynamic Liquid Glass appearance. Appearance variants (Default / Dark / Tinted / Clear) are a separate axis applied on top of the layered structure.

**Decision:**

1. **Spec 06 (Brand) bumped to rev 3.** § Asset specifications and § Tahoe icon workflow rewritten:
   - Two complementary asset deliverables documented: the flat package (legacy / preview) and the Liquid Glass prep package (primary path for Icon Composer).
   - Layer model corrected: background + up to 4 foreground groups, each with material properties.
   - `.icon` placement corrected: `App/AppIcon.icon` at the same level as `Assets.xcassets`, not inside it.
   - Step-by-step Icon Composer workflow added (8 steps from import to commit).
   - Xcode integration steps added (drag into project navigator; set App Icon Set Name).
   - Backwards-compat trick noted but not applied (deployment target is 26).
   - Squircle compliance section reworded to clarify Apple applies the platform mask at render time.

2. **Spec 09 (Platform) updated.** § Icon format corrected to reference the `App/AppIcon.icon` placement and the supplied prep package.

3. **CLAUDE.md project layout corrected.** `App/AppIcon.icon` shown as sibling of `Assets.xcassets`. Top-level `icons/` directory replaces the earlier `design/icons/` location and now shows both the flat package and the `ButterBar-LiquidGlass-prep/` subfolder.

4. **`T-REPO-INIT`** updated:
   - Top-level directory is `icons/`, not `design/icons/`.
   - Includes both the flat package and the `ButterBar-LiquidGlass-prep/` subfolder.
   - Explicit note that `T-REPO-INIT` does NOT create the `.icon` bundle — that's `T-BRAND-ASSETS`.

5. **`T-BRAND-ASSETS`** rewritten:
   - Workflow moves from "import a single PNG" to "import layered PNGs, tune Liquid Glass per layer, configure four appearance variants."
   - Hands-on GUI work in Icon Composer; ~1–2 hours of tuning expected.
   - Output saved to `App/AppIcon.icon` (NOT inside `Assets.xcassets`).
   - Acceptance now includes Liquid Glass material verification (visible specular response in Dock).

6. **`docs/claude-code-setup.md`** updated to reflect the new `icons/` layout and the Liquid Glass prep workflow.

**Cascading deletions:**
- `design/icons/` references — replaced with top-level `icons/` references throughout.
- "Import `butter-bar-logo-1024.png` as the master" instruction in T-BRAND-ASSETS — replaced with the layered import from `ButterBar-LiquidGlass-prep/`.

**Provenance:** the layer-model and `.icon`-placement corrections are based on Apple's developer documentation and WWDC 2025 session "Create icons with Icon Composer" (session 361), plus widely-circulated developer commentary confirming the same workflow. The "background + up to 4 foreground groups" layer count comes directly from Apple's documentation. The placement correction comes from Apple's documented Xcode integration path: `.icon` files are dragged into the project navigator alongside `Assets.xcassets`, not into it.

---

### A20 — Clarify "most recently served byte" tracking (spec 04)

**Context:** During Phase 1 implementation, the mkv-cues-001 fixture exposed an ambiguity in spec 04. The spec uses the phrase "most-recently-served bytes" when describing seek detection, but does not define whether this tracks the range.end of every GET event processed, or only bytes actually delivered to the player.

**Decision:** "Most recently served byte" means the `range.end` of the most recent GET event the planner processed, regardless of whether data was actually delivered before a cancel. This is the correct behavior because:
- After a seek sets deadlines for a new region, the next GET must clear those deadlines if it targets a different region.
- If the planner only tracked delivered bytes, a cancelled request would leave stale deadlines competing for peer slots.

**Affected spec:** `04-piece-planner.md` § Seek (internally detected). The sentence "whose range starts more than pieceLength * 4 away from the most recent served byte" should be read as "most recent GET's range.end".

### A21 — Document pieceLength gap between sequential and seek thresholds (spec 04)

**Context:** Spec 04 defines mid-play as "within pieceLength * 2" and seek as "more than pieceLength * 4". The gap (2x to 4x) is not addressed.

**Decision:** GETs in the gap are treated as mid-play (sequential). This is the conservative choice — it avoids unnecessary deadline clearing for distances that are close but not clearly a seek.

**Affected spec:** `04-piece-planner.md` § Mid-play GET, § Seek.

### A22 — Document secondsBufferedAhead when bitrate is unknown (specs 02, 04)

**Context:** In v1, `requiredBitrateBytesPerSec` is nil for the first 60 seconds of playback (spec 02 § Required bitrate inference). The specs do not define what `secondsBufferedAhead` should be when bitrate is nil.

**Decision:** `secondsBufferedAhead` is `0.0` when `requiredBitrateBytesPerSec` is nil. The tier computation falls through to `outstandingCriticalPieces` as the primary health signal during this period. This means every stream starts in the `starving` tier until all critical pieces are downloaded, which is the correct user-facing behavior (you ARE starving until the buffer forms).

**Known limitation:** The `.healthy` and `.marginal` tiers via the buffer path are unreachable in v1 until 60 seconds of continuous playback. This is acceptable for v1 — the critical-pieces path provides adequate tier transitions during the early buffer-building phase.

**Affected specs:** `02-stream-health.md` § Tier semantics, `04-piece-planner.md` § Tick.

## A23 — libtorrent 2.0.12 eviction API constraint and chosen mechanism

**Context:** Spec 05 rev 2 § Piece eviction mechanism described the primitive as "set priority to 0, truncate regions where possible, or mark them for future overwrite, update the in-memory view." This was hand-wavy because the actual libtorrent API surface had not been verified. Investigation on 2026-04-16 (`docs/libtorrent-eviction-notes.md`) confirmed:

- `torrent_handle::clear_piece` does NOT exist in libtorrent 2.0.12 (our pinned version). It is declared only on the internal `disk_interface` and is called by libtorrent when a piece fails its hash check.
- Setting `piece_priority(idx, 0)` does not reclaim disk or update the have-bitmap for pieces already downloaded.
- `ftruncate()` reduces the file on disk but libtorrent does not re-check, so the have-bitmap goes out of sync with reality.

**Decision (v1):** Eviction is implemented in two tiers.

1. **Hot path (per piece, surgical):** `add_piece(idx, 256 KB of zeros, overwrite_existing)` → wait for `hash_failed_alert` → `fcntl(F_PUNCHHOLE)` over the piece-aligned byte range. The intentional hash failure invokes libtorrent's internal `async_clear_piece` and removes the piece from the have-bitmap. The punch reclaims APFS blocks that the zero write re-allocated.
2. **Fallback (bulk, idle):** `force_recheck()` — only for idle-time reconciliation and recovery if the add_piece trick stops working.

**Risk:** the hot path trades on an implementation detail (add_piece writes its buffer to disk before hashing). If libtorrent ever short-circuits this, we fall back to `force_recheck`. The fallback is already in the bridge surface for this reason.

**Affected files:**
- `05-cache-policy.md` § Piece eviction mechanism (rewritten — see Rev 3 block).
- `TorrentBridge.h/.mm` — two new methods: `forceRecheck(torrentID:)` and `addPiece(torrentID:, piece:, data:, overwriteExisting:)`.
- `EngineService/Cache/CacheEvictionProbe.swift` — revised to test both mechanisms head-to-head.
- `TASKS.md` T-CACHE-EVICTION — status and probe plan updated.

## A24 — Eviction mechanism retraction + PUNCH + FORCE_RECHECK replacement

**Context:** Addendum A23 (rev 3 of spec 05) specified a per-piece hot path built on `add_piece(zeros, overwrite_existing)` → `hash_failed_alert` → `F_PUNCHHOLE`. Probe run #3 on 2026-04-16 (`docs/libtorrent-eviction-notes.md`) disproved this empirically. With libtorrent 2.0.12 (our pinned version):

- `add_piece(zeros, overwrite_existing)` produces NO alert — neither `hash_failed_alert` nor `piece_finished_alert` — at either file priority (1 or 0). Tested across two runs with multiple polling windows. The expected internal `async_clear_piece` path is therefore unreachable through `add_piece`.
- `hash_failed_alert` is only emitted for peer-download hash failures, not for disk-recheck mismatches (confirmed by Probe C0 in run #3: corrupting a piece on disk and calling `force_recheck` produces no alert, but the have-bitmap still updates).
- What DOES work: a block-aligned `F_PUNCHHOLE` paired with `force_recheck()`. The punch reclaims APFS blocks; the recheck detects the now-bad piece and removes it from the have-bitmap. On Apple silicon, recheck takes ~0.5 s per 275 MB of resident content.

**Decision (v1, replaces A23):** Eviction is implemented as a single tier: `F_PUNCHHOLE` + `force_recheck`.

1. Set the target file's priority to 0 (if not already) so peers do not auto-request the punched pieces.
2. For each piece: compute a block-aligned sub-range within the file-relative byte space of that piece, `fcntl(fd, F_PUNCHHOLE, …)` over that sub-range. Geometry: `alignedStart = ceil(pieceFileOffset / 4096) * 4096`, `alignedEnd = floor((pieceFileOffset + pieceLength) / 4096) * 4096`. Up to ~8 KiB is forfeited at each piece boundary for correctness on multi-file torrents where the file does not start on a piece boundary.
3. `forceRecheck(torrentID)` after punching every piece in the batch. Poll `statusSnapshot` until the torrent leaves `checkingResumeData`/`checkingFiles`.
4. The have-bitmap is now in sync with disk. When the user later wants the evicted file, CacheManager restores priority and the normal deadline/priority pipeline re-downloads.

**What about `addPiece`?** The bridge method is retained but not used by eviction. It is a legitimate `lt::torrent_handle::add_piece` wrapper that may be useful for other purposes (e.g., injecting test pieces, future API experiments). The header doc is updated to note that `add_piece` with `overwrite_existing` does NOT drive eviction in 2.0.12.

**What about batching?** `force_recheck` is O(on-disk bytes) and disconnects peers for its duration. CacheManager batches evictions: one `forceRecheck` per affected torrent per eviction run. Eviction never runs against a torrent with an active stream (would disrupt playback); if disk pressure crosses `highWater` while every torrent is streaming, CacheManager emits `DiskPressureDTO(state: critical)` and defers.

**Affected files:**
- `05-cache-policy.md` rev 4: § Piece eviction mechanism rewritten from scratch.
- `docs/libtorrent-eviction-notes.md`: probe run #3 analysis appended.
- `EngineService/Bridge/TorrentBridge.h`: `addPiece` header doc amended to note it's not part of the eviction path in 2.0.12.
- `EngineService/Cache/CacheEvictionProbe.swift`: Probe C0 (baseline disk-corrupt recheck, confirms bitmap-updates-without-alerts), Probe C1 (addPiece regression sentinel — expected negative), Probe B moved after C1, punch geometry fixed.
- `EngineService/Cache/CacheManager.swift`: eviction logic implemented per this spec.

## A25 — Planner-layer seek SLA and regression threshold (resolves #107)

**Context:** T-PERF-SEEK-BENCH (PR #106) shipped the planner seek bench: XCTest performance tests across the four trace fixtures plus a 20-iteration baseline recorder (`docs/benchmarks/seek-baseline.json`). The recorded baseline on arm64 / macOS 26.5 shows p50 0.039–0.058 ms and p90 0.040–0.060 ms per fixture — purely planner overhead, no network, no decode. Specs 02 / 04 / 05 name no numerical seek-to-first-frame SLA, and issue #107 collected the four design calls needed to close the bench loop.

**Decision (v1):** the planner bench is a **regression guard, not a user-facing SLA**. User-visible seek latency is dominated by libtorrent piece fetch and AVFoundation decode — neither is measured by this bench, and measuring them would require a real-network harness on top of `T-STREAM-E2E`. The v1 architectural seek SLA is the synchronous-deadline guarantee already in spec 04:

> On seek, the planner emits `setDeadlines(critical=[…], deadlineMs=0)` synchronously inside `handle(event:)`.

That property is verified by the correctness tests (fixture replay, byte-for-byte against expected-actions files). The bench's job is to catch *regressions* of that guarantee — an accidental O(N²) path, an allocation storm, a sync-to-async split — all of which would move the replay time by a large multiple.

**Numerical threshold:** **50% over the committed p90** per fixture, applied uniformly. Tight enough to catch the regression classes above (each would move replay ≥ 10×); generous enough to absorb sub-ms measurement noise and host-drift between local arm64 and CI macos-26 runners. Written into `docs/benchmarks/seek-baseline.json` as `regression_threshold_pct: 50.0`.

**CI gate:** **advisory only, do not gate merges**. Sub-ms measurements across heterogeneous silicon + scheduling produce flaky CI signal unrelated to code quality. The bench runs on PRs for visibility; Opus triages any headline regression manually. Revisit this stance if and when we have a dedicated bench runner with stable hardware.

**End-to-end seek SLA:** **deferred to v1.5+**. Requires a real-network harness (T-STREAM-E2E-style) with a controlled peer set and a known-good magnet, and a decoder-side measurement (`AVPlayerItem.timebase` rate change from 0 → 1). Not in scope for v1.

**Affected files:**
- `docs/benchmarks/seek-baseline.json` — `regression_threshold_pct` set to `50.0`; `notes` updated to reference A25.
- `Packages/PlannerCore/Tests/PlannerCoreTests/PlannerSeekBenchRecorder.swift` — recorder defaults bumped to match (so re-recording preserves the threshold).
- `docs/benchmarks/README.md` — § Deferred: regression gate threshold rewritten to "Regression threshold" and pointed at A25.
- `TASKS.md` — `T-PERF-SEEK-BENCH` follow-up note marks #107 resolved.

## A26 — `playback_history.completed_at` for watch state foundation (Epic #5 Phase 1)

**Context:** Epic #5 Phase 1 foundation (#34) defines the app-side `WatchStatus` enum, with `.watched(completedAt: Date)` and `.reWatching(_, _, previouslyCompletedAt: Date)` cases. Spec 05 rev 4 stores `completed: Bool` on `playback_history` but no completion timestamp. The library UI needs that timestamp to show honest "Watched X days ago" copy and to preserve the original completion date across re-watches. Approximating from `last_played_at` was rejected during the design pass: re-watching mutates `last_played_at`, which would silently overwrite the original completion time.

**Decision:** Add `completed_at INTEGER NULL` (unix milliseconds) to the `playback_history` table. Write rules:

- Engine sets `completed_at = now()` whenever `completed` transitions 0 → 1 (either by the spec 05 § Update rules byte criterion `resume_byte_offset >= 0.95 * file_size`, or by manual mark-watched via the new XPC method introduced in #34).
- Subsequent re-completions during a re-watch (the byte criterion re-firing while `completed` is already 1) **also** update `completed_at = now()`. Most-recent-completion-wins; the original completion date is unrecoverable in v1, by design.
- Manual mark-unwatched (XPC) sets `completed = 0`, `completed_at = NULL`, `resume_byte_offset = 0`. `last_played_at` is preserved so library ordering does not jump.
- The next stream open after completion still resets `resume_byte_offset = 0` per spec 05 unchanged; it does **not** clear `completed` or `completed_at`.

**Migration:** new GRDB migration `v2_add_completed_at` is additive and backward-compatible. Rows created under V1 carry `completed_at = NULL`; the engine fills the column at the next completion. Loss of historical completion timestamps for already-completed rows is acceptable for v1.

**XPC contract additions** (also part of #34):
- New DTO `PlaybackHistoryDTO` (`schemaVersion = 1`, NSSecureCoding) carrying every column of `playback_history` including the new `completedAt` (nullable).
- New method `EngineXPC.listPlaybackHistory(reply: ([PlaybackHistoryDTO]) -> Void)` — the app's first read path into the table. Returns `[]` when empty.
- New event `EngineEvents.playbackHistoryChanged(_ dto: PlaybackHistoryDTO)` — emitted exactly once per write (15 s tick, stream close, manual toggle). Coalescing is the engine's responsibility.

Both follow the response/event versioning rule from A1.

**Affected files:**
- `05-cache-policy.md` — rev 5: § Schema gains the new column; § Update rules gain the `completed_at` write semantics; § Resume offset persistence gains a manual-toggle reference.
- `Packages/EngineStore/Sources/EngineStore/V1Migration.swift` — companion `V2Migration` added; `EngineDatabase` registers both.
- `Packages/EngineStore/Sources/EngineStore/PlaybackHistoryRecord.swift` — `completedAt: Int64?` field added.
- `Packages/EngineInterface/Sources/EngineInterface/PlaybackHistoryDTO.swift` — new file.
- `Packages/EngineInterface/Sources/EngineInterface/EngineXPCProtocol.swift` — `listPlaybackHistory` added.
- `Packages/EngineInterface/Sources/EngineInterface/EngineEventsProtocol.swift` — `playbackHistoryChanged` added.
- `EngineService/Cache/CacheManager.swift` — write rules above implemented; event emitted after every write.
- `EngineService/XPC/EngineXPCServer.swift` (and `RealEngineBackend`) — `listPlaybackHistory` wired.
- `Packages/LibraryDomain/` — new local SPM package containing `WatchStatus`, `WatchEvent`, `WatchStateMachine`, and the derivation helpers.
- `docs/design/watch-state-foundation.md` — full design record (transition matrix, write rules, test shape).

## Summary of file changes in this revision

(extends earlier summaries)

- `00-addendum.md` — A16–A19 appended in earlier revision; A20–A22 appended from Phase 1 review; A23 appended from 2026-04-16 API surface investigation; A24 appended same-day after probe run #3 disproved A23's hot path; A25 appended 2026-04-16 to resolve #107 (planner seek SLA + 50% regression threshold, advisory-only, E2E SLA deferred to v1.5+); A26 appended 2026-04-16 to add `playback_history.completed_at` plus the `listPlaybackHistory` / `playbackHistoryChanged` XPC surface for Epic #5 Phase 1 foundation (#34).
- `06-brand.md` — rev 3: § Asset specifications and § Tahoe icon workflow rewritten around the Liquid Glass prep package. Layer model corrected (background + up to 4 foreground groups). `.icon` placement corrected to `App/AppIcon.icon` (sibling of Assets.xcassets, not nested). Step-by-step Icon Composer workflow added. (A19.) Rev 2 introduced Tahoe targeting (A18); rev 1 was the initial brand spec.
- `07-product-surface.md` — authoritative product surface spec for catalogue, sync, providers, etc. (A17.)
- `08-issue-workflow.md` — GitHub issue/branch/PR conventions. (A17.)
- `09-platform-tahoe.md` — authoritative platform spec: macOS 26 deployment target, SDK 26, Apple silicon priority, Liquid Glass adoption stance. § Icon format updated for corrected `.icon` placement. (A18, A19.)
- All files mentioning project name — `PopcornMac` → `ButterBar`, `popcornmac` → `butterbar`.
- `02-stream-health.md` — revision bumped; UI rendering contract now points at `06-brand.md` for tier colours.
- `05-cache-policy.md` — rev 3: § Piece eviction mechanism rewritten with concrete 2.0.12 API surface (add_piece/hash-fail primary + force_recheck fallback) (A23). Rev 4: mechanism retracted and replaced with `F_PUNCHHOLE` + `force_recheck` after probe disproof (A24).
- `CLAUDE.md` — tagline mentions Tahoe; reading order includes specs 09; project layout updated to show `App/AppIcon.icon` at sibling level and top-level `icons/` (with `ButterBar-LiquidGlass-prep/` subfolder). (A18, A19.)
- `.claude/README.md` — directory listing updated.
- `TASKS.md` — `T-REPO-INIT` and `T-BRAND-ASSETS` rewritten for the Liquid Glass prep workflow. T-REPO-INIT places source material; T-BRAND-ASSETS runs Icon Composer. (A18, A19.)
- Both agent role files — brand, product surface, issue workflow, platform specs added to reading order. (A17, A18.)
- `.github/workflows/ci.yml` — runner upgraded to `macos-26`. (A18.)
- Top-level repo files: `README.md`, `CONTRIBUTING.md`, `CODEOWNERS`, `.github/ISSUE_TEMPLATE/*`, `.github/PULL_REQUEST_TEMPLATE.md`, `scripts/seed-issues.sh`, `scripts/setup-repo.sh`.
- `docs/logo-generation-prompt.md` — removed (A18). Logo asset package supplied.
- `icons/` — **expected top-level directory** for the supplied source material (flat package + Liquid Glass prep package). Not bundled in this zip — drop in locally per `docs/claude-code-setup.md`.
