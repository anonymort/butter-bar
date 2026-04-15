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

## Summary of file changes in this revision

(extends earlier summaries)

- `00-addendum.md` — A16–A19 appended in earlier revision; A20–A22 appended from Phase 1 review.
- `06-brand.md` — rev 3: § Asset specifications and § Tahoe icon workflow rewritten around the Liquid Glass prep package. Layer model corrected (background + up to 4 foreground groups). `.icon` placement corrected to `App/AppIcon.icon` (sibling of Assets.xcassets, not nested). Step-by-step Icon Composer workflow added. (A19.) Rev 2 introduced Tahoe targeting (A18); rev 1 was the initial brand spec.
- `07-product-surface.md` — authoritative product surface spec for catalogue, sync, providers, etc. (A17.)
- `08-issue-workflow.md` — GitHub issue/branch/PR conventions. (A17.)
- `09-platform-tahoe.md` — authoritative platform spec: macOS 26 deployment target, SDK 26, Apple silicon priority, Liquid Glass adoption stance. § Icon format updated for corrected `.icon` placement. (A18, A19.)
- All files mentioning project name — `PopcornMac` → `ButterBar`, `popcornmac` → `butterbar`.
- `02-stream-health.md` — revision bumped; UI rendering contract now points at `06-brand.md` for tier colours.
- `CLAUDE.md` — tagline mentions Tahoe; reading order includes specs 09; project layout updated to show `App/AppIcon.icon` at sibling level and top-level `icons/` (with `ButterBar-LiquidGlass-prep/` subfolder). (A18, A19.)
- `.claude/README.md` — directory listing updated.
- `TASKS.md` — `T-REPO-INIT` and `T-BRAND-ASSETS` rewritten for the Liquid Glass prep workflow. T-REPO-INIT places source material; T-BRAND-ASSETS runs Icon Composer. (A18, A19.)
- Both agent role files — brand, product surface, issue workflow, platform specs added to reading order. (A17, A18.)
- `.github/workflows/ci.yml` — runner upgraded to `macos-26`. (A18.)
- Top-level repo files: `README.md`, `CONTRIBUTING.md`, `CODEOWNERS`, `.github/ISSUE_TEMPLATE/*`, `.github/PULL_REQUEST_TEMPLATE.md`, `scripts/seed-issues.sh`, `scripts/setup-repo.sh`.
- `docs/logo-generation-prompt.md` — removed (A18). Logo asset package supplied.
- `icons/` — **expected top-level directory** for the supplied source material (flat package + Liquid Glass prep package). Not bundled in this zip — drop in locally per `docs/claude-code-setup.md`.
