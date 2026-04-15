# TASKS

Engine build queue for ButterBar v1. Tasks are picked top-down within an unblocked phase. Do not skip phases.

> **Two-tracker model (per addendum A17).** This file tracks **engine work only** — the playback substrate described in specs 01–05. **Product surface work** (catalogue, sync, providers, watch state, settings, macOS polish — described in spec 07) is tracked as **GitHub issues** per spec 08, not here. The two trackers connect at well-defined seams; both are authoritative within their scope. If you find yourself wanting to add a third tracker, stop.

> **Platform target (per addendum A18).** All engine work targets **macOS Tahoe (26.0) minimum**, built with **Xcode 26 / SDK 26**. See `09-platform-tahoe.md` for the full picture. Do not introduce code paths or build settings that lower this floor.

**Legend:** `TODO` · `IN PROGRESS` · `BLOCKED: <reason>` · `DONE` · `REVIEW` (awaiting Opus gate)

**Agent routing:**
- `[opus]` — design, spec revision, review. Opus only.
- `[sonnet]` — implementation, tests, scaffolding. Sonnet.
- `[either]` — trivial or self-contained; whoever picks it up.

---

## Phase 0 — Foundation (no blockers)

### T-REPO-INIT `[sonnet]` · TODO
Create the target Xcode project structure described in `CLAUDE.md` → Project layout. Two targets: `ButterBar` (app) and `EngineService` (XPC service). Swift packages: `EngineInterface`, `PlannerCore`, `TestFixtures`. Empty test targets for each. Top-level `icons/` directory containing the supplied logo source material — both the flat asset package (SVG, PNGs, `.iconset`, `.icns`) AND the `ButterBar-LiquidGlass-prep/` subfolder (layered PNGs, revised SVG, size exports, README). `App/Brand/` folder for `BrandColors.swift` and related token files (empty placeholders are fine). No logic yet.

**Note on `AppIcon.icon`:** do NOT create the `.icon` bundle in this task. It's a separate task (`T-BRAND-ASSETS`) that requires running Apple's Icon Composer GUI and tuning Liquid Glass properties per-layer. T-REPO-INIT only places the source material; T-BRAND-ASSETS produces the `.icon` bundle.

**Platform configuration (per `09-platform-tahoe.md`):**
- Both targets: `MACOSX_DEPLOYMENT_TARGET = 26.0`.
- Both targets: build settings use the macOS 26 SDK (Xcode 26+).
- `Info.plist` for the app target: do NOT include `UIDesignRequiresCompatibility` (Liquid Glass is adopted, not opted out).
- Hardened runtime enabled. App Sandbox enabled.

**Acceptance:** Project builds empty. `xcodebuild -scheme ButterBar build` succeeds. `xcodebuild -scheme EngineService build` succeeds. Test targets run zero tests successfully. `icons/` contains both the flat assets and the `ButterBar-LiquidGlass-prep/` subfolder. `App/Brand/` directory exists. Deployment target verified at 26.0 in the Xcode build settings inspector.

**Blocks:** everything downstream.

### T-SPEC-LINT `[opus]` · DONE — Opus pre-flight review verified A11–A19 applied correctly across all specs; no contradictions found. Two editorial findings (duplicate A17/A18 text in addendum, stale T-SPEC-LINT scope) fixed in PR #81. Both agent role files confirmed to reference 00-addendum.md.
Read all specs (addendum + 01–09) end-to-end once the repo exists. Verify that the revision blocks in each numbered spec match the addendum items they reference, and that no contradictions remain between the addendum and the numbered specs. If new contradictions are found, append a new addendum item (A20+) rather than editing existing ones.

**Acceptance:** Either no new contradictions, or new addendum items appended at the bottom of `00-addendum.md`. Additionally: verify both `.claude/agents/opus-designer.md` and `.claude/agents/sonnet-implementer.md` reference `00-addendum.md` in their reading order — this defends against the most subtle drift mode (agents skipping the precedence layer because their role file doesn't mention it).

---

## Phase 1 — PlannerCore (planner-first development)

**Phase gate:** Phase 0 must be DONE. No Phase 1 task starts until `T-REPO-INIT` and `T-SPEC-LINT` are both DONE.

### T-PLANNER-TYPES `[sonnet]` · TODO
Implement the type declarations from `04-piece-planner.md`: `PlayerEvent`, `ByteRange`, `PlannerAction`, `PieceDeadline`, `FailReason`, `TorrentSessionView` protocol, `PiecePlanner` protocol. No implementations. No tests yet (types only).

**Spec:** `04-piece-planner.md` § Inputs, Outputs.
**Acceptance:** `PlannerCore` package compiles. Types match the spec verbatim.

### T-PLANNER-FAKE-SESSION `[sonnet]` · TODO
Implement `FakeTorrentSession: TorrentSessionView` in `PlannerCore`'s test support module. Driven by a schedule: `(t_ms, havePieces, downloadRate, peerCount)`. Exposes a `step(to: Int)` method that advances the current time.

**Spec:** `04-piece-planner.md` § Trace format.
**Acceptance:** Unit test demonstrating that `havePieces()` returns the correct set at each scheduled time point.
**Blocks:** `T-PLANNER-TRACE-LOADER`, `T-PLANNER-CORE`.

### T-PLANNER-TRACE-LOADER `[sonnet]` · TODO
Implement JSON decoding for the trace format and the expected-actions format. Both as Swift `Codable` structs in `TestFixtures`. Decoding errors must point at the offending field.

**Spec:** `04-piece-planner.md` § Trace format, Expected action format.
**Acceptance:** Round-trip test: encode a trace, decode it, assert equality. One passing test per format.
**Blocks:** `T-PLANNER-FIXTURES`.

### T-PLANNER-FIXTURES `[opus]` · TODO
Hand-author the four v1 fixtures and their expected-actions files:
1. `front-moov-mp4-001`
2. `back-moov-mp4-001`
3. `mkv-cues-001`
4. `immediate-seek-001`

These are the source of truth for planner correctness. Opus writes them because they encode policy decisions.

**Spec:** `04-piece-planner.md` § Minimum fixture set, Policies.
**Acceptance:** Four pairs of JSON files in `Packages/TestFixtures/traces/` and `Packages/TestFixtures/expected/`. Each pair loads cleanly via the trace loader.
**Depends on:** `T-PLANNER-TRACE-LOADER` DONE.
**Blocks:** `T-PLANNER-CORE`.

### T-PLANNER-CORE `[sonnet]` · TODO
Implement `PiecePlanner` against `04-piece-planner.md`. All four policies: initial play, mid-play GET, seek, cancel, tick. Uses `TorrentSessionView` exclusively — no libtorrent imports in this module.

**Spec:** `04-piece-planner.md` § Policies.
**Acceptance:**
- All four fixture tests pass byte-for-byte against their expected-actions files.
- Unit tests for the readahead window policy at all three bitrate regimes.
- Unit tests for `StreamHealth` tier computation (see `02-stream-health.md` test obligations).
- No `Foundation.Date`, no `DispatchQueue`, no real clocks in the planner module.
**Depends on:** `T-PLANNER-TYPES`, `T-PLANNER-FAKE-SESSION`, `T-PLANNER-FIXTURES`.
**Review gate:** `[opus]` reviews before marking DONE. This is the project's highest-risk component.

### T-PLANNER-PROPERTY-TESTS `[sonnet]` · TODO
Add property-based tests using `SwiftCheck` or hand-rolled generators: random trace inputs within reasonable bounds, assert invariants (no deadline ever in the past, no `waitForRange` without a preceding `setDeadlines` covering the range, cancellation never leaves orphaned critical deadlines).

**Acceptance:** At least 6 invariants, each with ≥100 generated cases. All pass.
**Depends on:** `T-PLANNER-CORE` DONE + REVIEWED.

---

## Phase 2 — XPC contract

**Phase gate:** Phase 1 `T-PLANNER-CORE` must be DONE and reviewed.

### T-XPC-DTOS `[sonnet]` · TODO
Implement all DTO classes from `03-xpc-contract.md` in `EngineInterface` package. Every class: `NSSecureCoding`, explicit `encode(with:)` and `init?(coder:)`, `schemaVersion` field.

**Spec:** `03-xpc-contract.md` § DTO definitions.
**Acceptance:** Round-trip secure-coding tests for every DTO, including nil-permitted fields.

### T-XPC-PROTOCOLS `[sonnet]` · TODO
Declare `EngineXPC` and `EngineEvents` `@objc` protocols in `EngineInterface`. Wire up a minimal `NSXPCInterface` factory that registers allowed classes for each method.

**Spec:** `03-xpc-contract.md` § Protocols.
**Acceptance:** Compiles. Interface factory unit test verifies every method has its allowed classes registered (none missing is the common bug).
**Depends on:** `T-XPC-DTOS`.

### T-XPC-MAPPING `[sonnet]` · TODO
Write bidirectional mapping between DTOs and internal domain types (`TorrentSummary`, `StreamHealth`, etc.). Mapping lives in `EngineService/XPC/Mapping.swift` — the one allowed place for DTO↔domain conversion.

**Acceptance:** Unit tests: for every DTO, `toDomain → toDTO → toDomain` is idempotent.
**Depends on:** `T-XPC-DTOS`, `T-PLANNER-TYPES` (for `StreamHealth`).

### T-XPC-SERVER-SKELETON `[sonnet]` · TODO
Implement `EngineXPCServer` in `EngineService` with:
- `listTorrents(_:)` returning `[]`.
- `subscribe(_:reply:)` succeeding with `nil` error and retaining the client proxy weakly (no events emitted yet).
- All other methods returning `NSError(domain: "com.butterbar.engine", code: .notImplemented)`.

Wire up `NSXPCListener` using `NSXPCListener.service()`. See `00-addendum.md` A2 for the rationale (listTorrents must return a valid empty array, not an error, so the app has a safe read-only path for plumbing tests).

**Acceptance:** App can establish a connection, call `listTorrents` and receive an empty array, call `subscribe` and get a nil error, call any other method and receive `.notImplemented`. Engine survives client death.
**Depends on:** `T-XPC-PROTOCOLS`, `T-XPC-MAPPING`.

### T-XPC-CLIENT-CONNECTION `[sonnet]` · TODO
Implement app-side `EngineClient` actor that owns the `NSXPCConnection`, handles invalidation, and re-subscribes on reconnect. All reply blocks bridged to `async` methods.

**Spec:** `03-xpc-contract.md` § Connection model.
**Acceptance:** Integration test: start service, connect, kill service, reconnect, verify subscription restored.
**Depends on:** `T-XPC-SERVER-SKELETON`.

### T-XPC-INTEGRATION `[sonnet]` · TODO
Replace stubs with a fake engine backend (no libtorrent yet) that returns synthetic torrents and emits synthetic events on a timer. End-to-end flow: app adds a fake magnet, sees it appear in `listTorrents`, receives `torrentUpdated` events.

**Acceptance:** Integration test walks the full happy path.
**Depends on:** `T-XPC-CLIENT-CONNECTION`.
**Review gate:** `[opus]` reviews before marking DONE. First real cross-process boundary.

### T-STORE-SCHEMA `[sonnet]` · TODO
Create the GRDB migration for the v1 database schema: `playback_history`, `pinned_files`, and `settings` tables per `05-cache-policy.md` § Schema. Implement Swift models for each row type. No business logic — just schema, migration, models, and round-trip tests.

**Spec:** `05-cache-policy.md` § Schema, `00-addendum.md` A7.
**Acceptance:**
- Migration runs cleanly on a fresh database.
- Migration is idempotent (running it twice is a no-op).
- Round-trip insert/fetch tests for each table.
- Schema version recorded in GRDB's migration table.
**Blocks:** `T-CACHE-SCHEMA`, `T-CACHE-EVICTION`, `T-CACHE-RESUME`.

---

## Phase 3 — TorrentBridge

**Phase gate:** Phase 2 `T-XPC-INTEGRATION` must be DONE and reviewed.

### T-LIBTORRENT-BUILD `[sonnet]` · TODO
Add libtorrent-rasterbar as a dependency. Prefer vcpkg or a prebuilt xcframework. Document the build in `docs/build-libtorrent.md`.

**Acceptance:** `EngineService` links libtorrent. A trivial smoke test creates a `lt::session` and tears it down.

### T-BRIDGE-API `[sonnet]` · TODO
Implement `TorrentBridge` in ObjC++ with exactly the method surface from `01-architecture.md` § TorrentBridge. Nothing more.

**Acceptance:** Unit tests using a small known torrent (public domain, e.g. an Internet Archive magnet). Verify: add, list files, get status, set piece deadline, read bytes.
**Depends on:** `T-LIBTORRENT-BUILD`.

### T-BRIDGE-REAL-SESSION `[sonnet]` · TODO
Implement `RealTorrentSession: TorrentSessionView` — a thin adapter that exposes `TorrentBridge` state to the planner. This is the first place planner code meets real libtorrent.

**Acceptance:** Planner unit tests can be re-run using `RealTorrentSession` against a recorded libtorrent state dump.
**Depends on:** `T-BRIDGE-API`, `T-PLANNER-CORE`.

### T-BRIDGE-ALERTS `[sonnet]` · TODO
Wire libtorrent's alert stream into the engine's event system. Alert → typed Swift enum → DTO → XPC.

**Acceptance:** `torrentUpdated`, `fileAvailabilityChanged` events flow from real libtorrent to the app in a manual end-to-end test.
**Depends on:** `T-BRIDGE-API`, `T-XPC-INTEGRATION`.

---

## Phase 4 — PlaybackGateway

**Phase gate:** Phase 3 `T-BRIDGE-REAL-SESSION` must be DONE.

### T-GATEWAY-LISTENER `[sonnet]` · TODO
Implement `NWListener` on `127.0.0.1` with an ephemeral port. Accept one connection, log the request, close. Proves the Network.framework setup works before any HTTP parsing.

**Acceptance:** Manual curl against the port returns an empty response and closes cleanly.

### T-GATEWAY-HTTP `[sonnet]` · TODO
Implement HTTP/1.1 request parsing for HEAD and GET with `Range:` header. Response builder for 200, 206, 416. Zero framework dependencies beyond Foundation + Network.

**Acceptance:** Unit tests with hand-crafted byte streams: valid HEAD, valid GET with range, malformed range, range beyond length. All handled.
**Depends on:** `T-GATEWAY-LISTENER`.

### T-GATEWAY-PLANNER-WIRING `[sonnet]` · TODO
Connect the gateway to `PiecePlanner`. Every incoming request becomes a `PlayerEvent`. Planner actions drive `TorrentBridge` calls (via a mapper, not directly from the gateway). Gateway waits for bytes per the planner's `waitForRange` action.

**Acceptance:** Integration test: fake `TorrentSession` + real gateway + real planner + hand-crafted HTTP client. Plays through a 10 MB synthetic file.
**Depends on:** `T-GATEWAY-HTTP`, `T-BRIDGE-REAL-SESSION`.

### T-GATEWAY-BYTE-READER `[sonnet]` · TODO
Implement sparse-file reader that pulls bytes from the libtorrent-managed file via `TorrentBridge.readBytes(...)`. Handles partial reads (asked for N bytes, got M).

**Acceptance:** Unit tests with a pre-populated sparse file.
**Depends on:** `T-BRIDGE-API`.

---

## Phase 5 — First end-to-end stream

**Phase gate:** Phase 4 `T-GATEWAY-PLANNER-WIRING` and `T-GATEWAY-BYTE-READER` must be DONE.

### T-STREAM-E2E `[sonnet]` · TODO
Open a known-good public-domain torrent, select a file, open a stream via XPC, point `AVPlayer` at the returned loopback URL, verify playback starts within 10 seconds and runs for 60 seconds without a stall.

**Acceptance:** Manual test with a named public-domain torrent (Internet Archive, documented in `docs/test-content.md`). Recorded video of successful playback committed to the repo.
**Depends on:** all Phase 4 tasks.
**Review gate:** `[opus]` reviews before marking DONE. First real proof the architecture works.

---

## Phase 6 — CacheManager, UI, polish

**Phase gate:** `T-STREAM-E2E` DONE and reviewed.

### T-CACHE-SCHEMA `[sonnet]` · TODO
Wire `CacheManager` to the GRDB models created in `T-STORE-SCHEMA`. This task is now a thin glue layer — read/write helpers for `playback_history` and `pinned_files` from the cache layer's point of view, plus an in-memory view of the pinned set refreshed on startup.

**Depends on:** `T-STORE-SCHEMA`.
**Acceptance:** Unit tests that exercise the read/write helpers and verify the in-memory pinned set is rebuilt correctly after a simulated engine restart.

### T-CACHE-EVICTION `[sonnet]` · TODO · SPIKE
Spike and then implement `CacheManager` with the eviction ordering from `05-cache-policy.md`. Unit tests with synthetic sparse-file state.

**This task is an implementation spike.** The eviction mechanism described in `05-cache-policy.md` ("truncate regions where possible, or mark them for future overwrite") is hand-wavy because libtorrent's file-hole semantics and per-piece eviction behaviour need to be verified empirically against the real library. Before implementing:

1. Write a small probe program that exercises libtorrent's `file_priority` and storage APIs against a real sparse file on HFS+/APFS.
2. Verify what actually happens when a piece's priority is set to 0 — does the file region get truncated, sparsified, or just marked inert in libtorrent's view?
3. Verify that setting a previously-evicted piece back to high priority causes libtorrent to re-fetch it.
4. Document the observed behaviour in `docs/libtorrent-eviction-notes.md`.
5. Only then implement `CacheManager` against the observed reality, and only then update `05-cache-policy.md` with the confirmed mechanism.

**Depends on:** `T-CACHE-SCHEMA`, `T-BRIDGE-API` (need real libtorrent to probe).
**Acceptance:** Probe notes committed, CacheManager implemented against observed behaviour, unit tests green, spec 05 updated with concrete mechanism (remove the "where possible / mark for future overwrite" hedge).

### T-CACHE-RESUME `[sonnet]` · TODO
Wire resume offset tracking: update every 15 seconds during playback, on stream close, and on clean shutdown. Restore on next open.
**Depends on:** `T-CACHE-SCHEMA`.

### T-BRAND-ASSETS `[sonnet]` · TODO
Author the `AppIcon.icon` bundle by importing the supplied Liquid Glass prep package into Apple's Icon Composer.

**This task requires Icon Composer (Xcode 26 → Open Developer Tool → Icon Composer).** It is hands-on GUI work, not scriptable. Allow ~1–2 hours for tuning.

The source material is **already supplied** in `icons/ButterBar-LiquidGlass-prep/` (placed there by `T-REPO-INIT`). Read its `README` first — it documents the layer mapping/order. Workflow per `06-brand.md` § Tahoe icon workflow:

1. Open Icon Composer.
2. Drag the layered PNGs from `icons/ButterBar-LiquidGlass-prep/` into the Icon Composer sidebar in their numeric order (`0_…`, `1_…`, etc.). Icon Composer auto-creates the layer group.
3. If the prep package uses a flat background colour rather than a background-layer PNG, set the document fill colour in Icon Composer's document settings. This saves one of the four foreground-layer slots.
4. Tune Liquid Glass per layer: specular highlights, blur, translucency, shadows. Icon Composer's Liquid Glass toggle is on by default; toggle off only for layers that should remain matte (e.g. the carved play symbol, which reads as a recess and should NOT catch a highlight).
5. Configure the four appearance variants:
   - **Default** — straight from the layered import.
   - **Dark** — adjust per-layer opacity/colour for legibility against `cocoa` dark surfaces.
   - **Tinted (Mono)** — ensure at least one layer is close to white so the accent tint reads correctly.
   - **Clear** — let Icon Composer derive; verify it remains identifiable.
6. Preview at 16, 32, 64, 128, 256, 512, 1024 px. The carved play symbol may disappear at 16 px — that's expected; the pat-on-bar silhouette must still read.
7. Save as `App/AppIcon.icon` — at the **same level as `App/Assets.xcassets`**, NOT inside the asset catalogue. Apple's documented Xcode integration treats `.icon` as a first-class project asset, not a member of `xcassets`.
8. In Xcode, drag `App/AppIcon.icon` into the project navigator. In the app target's General settings, set **App Icon Set Name** to `AppIcon`.

**Spec:** `06-brand.md` § Logo, § Asset specifications, § Tahoe icon workflow. `09-platform-tahoe.md` § Icon format.
**Acceptance:**
- `App/AppIcon.icon/` exists in the repo (it's a folder bundle but appears as a single Icon Composer file in Finder).
- Xcode project's app target references `AppIcon` as its App Icon Set Name.
- App builds and the icon appears correctly in Finder, Dock, and About window with full Liquid Glass treatment (visible specular response when window scrolls past, dynamic lighting in the Dock).
- All four appearance variants render correctly when the user toggles System Settings → Appearance → Icon & widget style (Default / Dark / Tinted / Clear).
- **Squircle compliance check** — the icon does NOT show a grey squircle jail border in Finder or Dock. If it does, content has bled outside the safe area and Icon Composer needs re-tuning.
- **16-pixel legibility check** — the icon is identifiable as the ButterBar mark at 16 × 16 in Finder list view on a Retina display. The carved play symbol may be invisible at this size; the pat-on-bar silhouette must read.
- The `icons/ButterBar.icns` and `icons/ButterBar.iconset/` legacy fallbacks remain in `icons/` and are NOT added to the Xcode project for v1.

### T-UI-LIBRARY `[sonnet]` · TODO
SwiftUI library view: list of torrents, in-memory filter with `localizedStandardContains`, open-file sheet for multi-file torrents.

**Spec:** `06-brand.md` § Window chrome and layout, § Typography, § Voice. Use `cream`-toned surface, `cocoa` primary text, `cocoaSoft` for metadata. Empty-state copy per the brand voice ("Add a magnet link to begin." not "Welcome!").
**Acceptance:** Library view renders with brand-compliant colours and typography. Empty state matches the brand voice. Snapshot test for light and dark modes.

### T-UI-PLAYER `[sonnet]` · TODO
SwiftUI player view with `AVPlayerView` (via `NSViewRepresentable`), `StreamHealth` HUD, peer count, readahead indicator.

**Spec:** `06-brand.md` § Window chrome and layout (player window is dark by default), § Motion (slow easeInOut, no springs).
**Depends on:** `T-UI-LIBRARY`, `T-STREAM-E2E`.
**Acceptance:** Player window opens dark regardless of system appearance. HUD floats over video with `cocoa` 60% opacity background. Buffer-ahead indicator animates continuously, not in steps.

### T-UI-HEALTH-HUD `[sonnet]` · TODO
Render `StreamHealth.tier` with the brand tier colours. No tier recomputation in the UI layer.

**Spec:** `02-stream-health.md` § UI rendering contract, `06-brand.md` § Tier colours, § Motion.
**Depends on:** `T-UI-PLAYER`.
**Acceptance:**
- Each tier uses exactly the brand token: `tierHealthy` / `tierMarginal` / `tierStarving`.
- 400 ms cross-fade between tier colours on transition (per brand motion spec).
- Every tier is paired with a text label — colour is never the sole signal.
- Snapshot tests for all three tiers in both light and dark modes.

---

## Phase 7 — Hardening

### T-SECURITY-XPC-CODESIGN `[sonnet]` · TODO
Once the service bundle is signed, add `setCodeSigningRequirement(_:)` to the connection and verify rejected peers.

### T-PERF-SEEK-BENCH `[sonnet]` · TODO
Benchmark: measure seek-to-first-frame time across the four trace fixtures. Record results. Regressions block merges.

### T-DOC-ARCHITECTURE `[opus]` · TODO
Write `docs/architecture.md` describing the shipped v1 for future contributors. Includes the diagrams from `01-architecture.md` plus notes on what was tried and rejected.

---

## Escalation protocol

Any task marked `BLOCKED:` halts work on that task. The blocking reason goes in the task description. Opus triages blocked tasks at the next review gate or on explicit request.

Sonnet must not:
- Modify specs to unblock itself.
- Pick up a task from a later phase to "make progress" while blocked.
- Silently reinterpret an ambiguous spec — raise it.
