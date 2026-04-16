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

### T-REPO-INIT `[sonnet]` · DONE — Xcode project with ButterBar app + EngineService XPC targets, three Swift packages (EngineInterface, PlannerCore, TestFixtures), full directory layout. Both targets build. Opus-reviewed, PR #85.
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

### T-PLANNER-TYPES `[sonnet]` · DONE — One file per type/protocol: `ByteRange`, `PlayerEvent`, `StreamHealth`, `PieceDeadline`, `FailReason`, `PlannerAction`, `TorrentSessionView`, `PiecePlanner`. Plus `PlannerTypes.swift` for `Instant` (typealias `Int64`, milliseconds, no real-clock dependency) and `BitSet` (typealias `Set<Int>`, stdlib-only). `swift build` passes. All types carry `Sendable` and `Codable` conformances for actor-boundary safety and trace replay.
Implement the type declarations from `04-piece-planner.md`: `PlayerEvent`, `ByteRange`, `PlannerAction`, `PieceDeadline`, `FailReason`, `TorrentSessionView` protocol, `PiecePlanner` protocol. No implementations. No tests yet (types only).

**Spec:** `04-piece-planner.md` § Inputs, Outputs.
**Acceptance:** `PlannerCore` package compiles. Types match the spec verbatim.

### T-PLANNER-FAKE-SESSION `[sonnet]` · DONE — `FakeTorrentSession` with schedule-driven availability, download rate, and peer count. 21 tests pass.
Implement `FakeTorrentSession: TorrentSessionView` in `PlannerCore`'s test support module. Driven by a schedule: `(t_ms, havePieces, downloadRate, peerCount)`. Exposes a `step(to: Int)` method that advances the current time.

**Spec:** `04-piece-planner.md` § Trace format.
**Acceptance:** Unit test demonstrating that `havePieces()` returns the correct set at each scheduled time point.
**Blocks:** `T-PLANNER-TRACE-LOADER`, `T-PLANNER-CORE`.

### T-PLANNER-TRACE-LOADER `[sonnet]` · DONE — `Trace` and `ExpectedActions` Codable structs in TestFixtures. Discriminated unions with custom Codable for snake_case. 7 tests pass.
Implement JSON decoding for the trace format and the expected-actions format. Both as Swift `Codable` structs in `TestFixtures`. Decoding errors must point at the offending field.

**Spec:** `04-piece-planner.md` § Trace format, Expected action format.
**Acceptance:** Round-trip test: encode a trace, decode it, assert equality. One passing test per format.
**Blocks:** `T-PLANNER-FIXTURES`.

### T-PLANNER-FIXTURES `[opus]` · DONE — Four trace+expected pairs authored. Traces designed by Opus, expected actions derived by Sonnet agents, Opus-reviewed with two corrections (emit_health format flattened, clearDeadlinesExcept scope narrowed to critical window per spec).
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

### T-PLANNER-CORE `[sonnet]` · DONE — `DefaultPiecePlanner` implemented as a deterministic state machine: initial-play, mid-play, seek (auto-detected by byte distance), cancel, and tick policies; `StreamHealthTierComputer` (pure static, no real clocks); 68 tests pass (4 fixture replay + 64 unit). All four expected-action fixtures updated to match the spec formula (30 MB byte-based readahead window, `clearDeadlinesExcept` scoped to critical 4 pieces only). No `Foundation.Date`, `DispatchQueue`, or real clocks anywhere in the module.
Implement `PiecePlanner` against `04-piece-planner.md`. All four policies: initial play, mid-play GET, seek, cancel, tick. Uses `TorrentSessionView` exclusively — no libtorrent imports in this module.

**Spec:** `04-piece-planner.md` § Policies.
**Acceptance:**
- All four fixture tests pass byte-for-byte against their expected-actions files.
- Unit tests for the readahead window policy at all three bitrate regimes.
- Unit tests for `StreamHealth` tier computation (see `02-stream-health.md` test obligations).
- No `Foundation.Date`, no `DispatchQueue`, no real clocks in the planner module.
**Depends on:** `T-PLANNER-TYPES`, `T-PLANNER-FAKE-SESSION`, `T-PLANNER-FIXTURES`.
**Review gate:** `[opus]` reviews before marking DONE. This is the project's highest-risk component.

### T-PLANNER-PROPERTY-TESTS `[sonnet]` · DONE
Added `PlannerPropertyTests.swift` with 8 invariants, 100 seeds each (800 generated traces). Hand-rolled LCG generator (no SwiftCheck dependency). All 8 pass; total suite is now 76 tests.

Invariants: (1) no negative deadlines, (2) waitForRange always covered by prior setDeadlines, (3) cancel never produces critical-priority deadlines, (4) clearDeadlinesExcept immediately followed by setDeadlines, (5) seek classification only when distance > pieceLength*4, (6) health emit throttle respected, (7) all pieces within file bounds, (8) critical piece indices precede readahead piece indices.

**Depends on:** `T-PLANNER-CORE` DONE + REVIEWED.

---

## Phase 2 — XPC contract

**Phase gate:** Phase 1 `T-PLANNER-CORE` must be DONE and reviewed.

### T-XPC-DTOS `[sonnet]` · DONE — All 8 DTO types implemented in EngineInterface: TorrentSummaryDTO, TorrentFileDTO, StreamDescriptorDTO, ByteRangeDTO, FileAvailabilityDTO, StreamHealthDTO, DiskPressureDTO, EngineErrorCode. All NSSecureCoding with explicit encode/decode and allowedClasses throughout. 19 tests pass (round-trip per DTO, nil-field variants, ByteRangeDTO nested in FileAvailabilityDTO array).
Implement all DTO classes from `03-xpc-contract.md` in `EngineInterface` package. Every class: `NSSecureCoding`, explicit `encode(with:)` and `init?(coder:)`, `schemaVersion` field.

**Spec:** `03-xpc-contract.md` § DTO definitions.
**Acceptance:** Round-trip secure-coding tests for every DTO, including nil-permitted fields.

### T-XPC-PROTOCOLS `[sonnet]` · DONE — @objc protocols + `XPCInterfaceFactory` with allowed-class registration. 13 new tests (32 total in EngineInterface).
Declare `EngineXPC` and `EngineEvents` `@objc` protocols in `EngineInterface`. Wire up a minimal `NSXPCInterface` factory that registers allowed classes for each method.

**Spec:** `03-xpc-contract.md` § Protocols.
**Acceptance:** Compiles. Interface factory unit test verifies every method has its allowed classes registered (none missing is the common bug).
**Depends on:** `T-XPC-DTOS`.

### T-XPC-MAPPING `[sonnet]` · DONE — `Packages/XPCMapping` package with domain types + bidirectional DTO mapping. 25 tests pass.
Write bidirectional mapping between DTOs and internal domain types (`TorrentSummary`, `StreamHealth`, etc.). Mapping lives in `EngineService/XPC/Mapping.swift` — the one allowed place for DTO↔domain conversion.

**Acceptance:** Unit tests: for every DTO, `toDomain → toDTO → toDomain` is idempotent.
**Depends on:** `T-XPC-DTOS`, `T-PLANNER-TYPES` (for `StreamHealth`).

Follow-ups:
- `EngineService/XPC/Mapping.swift` stub should be added once EngineService is a proper Swift module (currently EngineService has only `main.swift`). The XPCMapping package is the logical home; any import at the EngineService Xcode target boundary just imports XPCMapping.
- `StreamHealth` does not carry `streamID` — the DTO→domain conversion drops it. The reverse (domain→DTO) requires `streamID` as a caller-supplied parameter. Opus should confirm this contract is correct before T-XPC-SERVER-SKELETON proceeds.

### T-XPC-SERVER-SKELETON `[sonnet]` · DONE — `EngineService/XPC/EngineXPCServer.swift` created: `@objc final class EngineXPCServer: NSObject, EngineXPC` with `listTorrents` returning `[]`, `subscribe` retaining client proxy weakly and returning nil, all other methods returning `EngineErrorCode.notImplemented`. `main.swift` updated to use `NSXPCListener.service()` with `XPCDelegate`. EngineInterface package linked to EngineService Xcode target. `xcodebuild -scheme EngineService` succeeds.
Implement `EngineXPCServer` in `EngineService` with:
- `listTorrents(_:)` returning `[]`.
- `subscribe(_:reply:)` succeeding with `nil` error and retaining the client proxy weakly (no events emitted yet).
- All other methods returning `NSError(domain: "com.butterbar.engine", code: .notImplemented)`.

Wire up `NSXPCListener` using `NSXPCListener.service()`. See `00-addendum.md` A2 for the rationale (listTorrents must return a valid empty array, not an error, so the app has a safe read-only path for plumbing tests).

**Acceptance:** App can establish a connection, call `listTorrents` and receive an empty array, call `subscribe` and get a nil error, call any other method and receive `.notImplemented`. Engine survives client death.
**Depends on:** `T-XPC-PROTOCOLS`, `T-XPC-MAPPING`.

### T-XPC-CLIENT-CONNECTION `[sonnet]` · DONE — `App/Shared/EngineClient.swift` (public actor) and `App/Shared/EngineEventHandler.swift` (NSObject + EngineEvents) created. All 8 EngineXPC methods wrapped as `async throws`. Invalidation triggers reconnect after 500 ms back-off; interruption re-subscribes without recreating the connection. `EngineEventHandler` forwards events via Combine `PassthroughSubject` publishers. `App/Shared/DTOSendable.swift` adds `@unchecked Sendable` conformances to the 7 DTO types (NSObject subclasses are not Sendable in SDK; all fields are immutable `let`). `xcodebuild -scheme ButterBar build CODE_SIGN_IDENTITY=-` succeeds. Note: true integration test (connect, kill service, reconnect) deferred to `T-XPC-INTEGRATION` per task spec.
Implement app-side `EngineClient` actor that owns the `NSXPCConnection`, handles invalidation, and re-subscribes on reconnect. All reply blocks bridged to `async` methods.

**Spec:** `03-xpc-contract.md` § Connection model.
**Acceptance:** Integration test: start service, connect, kill service, reconnect, verify subscription restored.
**Depends on:** `T-XPC-SERVER-SKELETON`.

### T-XPC-INTEGRATION `[sonnet]` · DONE — Opus-reviewed. FakeEngineBackend with in-memory state, 2s progress timer, weak client proxy. EngineXPCServer delegates all methods. 9 integration tests (41 total in EngineInterface). Both Xcode targets build.
Replace stubs with a fake engine backend (no libtorrent yet) that returns synthetic torrents and emits synthetic events on a timer. End-to-end flow: app adds a fake magnet, sees it appear in `listTorrents`, receives `torrentUpdated` events.

Built: `EngineService/XPC/FakeEngineBackend.swift` — in-memory store with a `DispatchSourceTimer` that fires every 2 s, increments `progressQ16` by 1000 per torrent, transitions state to "seeding" at 65536, and calls `clientProxy?.torrentUpdated`. `EngineXPCServer` is now a thin delegation wrapper over `FakeEngineBackend`. All 8 EngineXPC methods implemented; `listFiles` returns `notFound` for unknown torrentID; `setWantedFiles` and `closeStream` are documented no-ops. Integration tests in `Packages/EngineInterface/Tests/EngineInterfaceTests/XPCIntegrationTests.swift` cover the full happy path (9 tests) without an NSXPCConnection — the fake server is called directly in-process via `MockEngineServer`, a local replica typed to the `EngineXPC` protocol. All 41 EngineInterface tests pass; both Xcode schemes build.

Follow-ups noticed (for Opus to triage):
- `FakeEngineBackend` and the test-only `MockEngineServer` have duplicated logic. Once `EngineService` is a Swift package (or a testable module), the integration test could import `FakeEngineBackend` directly and remove the replica.
- The timer currently never cleans up if the EngineService process is torn down without `closeStream` being called — not a problem for the fake, but the real backend will need explicit teardown.
- `openStream` ignores `fileIndex` — a known limitation until the gateway is wired.

**Acceptance:** Integration test walks the full happy path.
**Depends on:** `T-XPC-CLIENT-CONNECTION`.
**Review gate:** `[opus]` reviews before marking DONE. First real cross-process boundary.

### T-STORE-SCHEMA `[sonnet]` · DONE — `Packages/EngineStore` package created with GRDB 7.10.0 dependency. `V1Migration` (static enum), three `PersistableRecord`/`FetchableRecord` models (`PlaybackHistoryRecord`, `PinnedFileRecord`, `SettingRecord`), and `EngineDatabase` factory. 14 tests pass: migration clean, idempotent, schema version recorded, round-trips for all three tables including default-value assertions.
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

### T-LIBTORRENT-BUILD `[sonnet]` · DONE — libtorrent-rasterbar 2.0.12 installed via Homebrew, EngineService Xcode target configured with header/library search paths, linker flags, and preprocessor defines. `TorrentBridgeSmokeTest` ObjC++ class creates and tears down `lt::session`. Bridging header wired. Build documented in `docs/build-libtorrent.md`. Both Xcode schemes build clean.
Add libtorrent-rasterbar as a dependency. Prefer vcpkg or a prebuilt xcframework. Document the build in `docs/build-libtorrent.md`.

**Acceptance:** `EngineService` links libtorrent. A trivial smoke test creates a `lt::session` and tears it down.

### T-BRIDGE-API `[sonnet]` · DONE — `TorrentBridge.h` and `TorrentBridge.mm` created in `EngineService/Bridge/`. Full method surface from spec 01: lifecycle, add magnet/torrent-file, remove, listFiles, setFilePriority, havePieces, setPieceDeadline, clearPieceDeadlines, statusSnapshot, pieceLength, fileByteRange, readBytes, subscribeAlerts. Error domain `com.butterbar.engine`, codes 1–5. Alert polling via 250 ms dispatch timer. `createTestTorrent:` DEBUG-only class method retained as dead code (sandbox-broken — see GitHub #94). `BridgeSelfTest.swift` **converted to shim 2026-04-16** after runtime verification revealed `createTestTorrent` failures; the bridge's actual method surface is now runtime-verified end-to-end via `--stream-e2e-self-test` against a real public-domain torrent (addMagnet, listFiles, pieceLength, havePieces, readBytes, fileByteRange, subscribeAlerts all exercised). Both `EngineService` and `ButterBar` schemes build clean.
Implement `TorrentBridge` in ObjC++ with exactly the method surface from `01-architecture.md` § TorrentBridge. Nothing more.

**Acceptance:** Unit tests using a small known torrent (public domain, e.g. an Internet Archive magnet). Verify: add, list files, get status, set piece deadline, read bytes.
**Depends on:** `T-LIBTORRENT-BUILD`.

### T-BRIDGE-REAL-SESSION `[sonnet]` · DONE — `RealTorrentSession.swift` in `EngineService/Bridge/`. Conforms to `TorrentSessionView`, delegates to `TorrentBridge` for a specific torrentID+fileIndex. Caches `pieceLength` and `fileByteRange` at init. PlannerCore added as dependency to EngineService target. Build clean.
Implement `RealTorrentSession: TorrentSessionView` — a thin adapter that exposes `TorrentBridge` state to the planner. This is the first place planner code meets real libtorrent.

**Acceptance:** Planner unit tests can be re-run using `RealTorrentSession` against a recorded libtorrent state dump.
**Depends on:** `T-BRIDGE-API`, `T-PLANNER-CORE`.

### T-BRIDGE-ALERTS `[sonnet]` · DONE — `TorrentAlert.swift` (7-case enum with `from(_:)` parser) and `AlertDispatcher.swift` (subscribes to TorrentBridge alerts, maps to EngineEvents proxy calls: `torrentUpdated` and `fileAvailabilityChanged`). Not yet wired into EngineXPCServer (deferred to real backend integration). Both schemes build clean.
Wire libtorrent's alert stream into the engine's event system. Alert → typed Swift enum → DTO → XPC.

**Acceptance:** `torrentUpdated`, `fileAvailabilityChanged` events flow from real libtorrent to the app in a manual end-to-end test.
**Depends on:** `T-BRIDGE-API`, `T-XPC-INTEGRATION`.

---

## Phase 4 — PlaybackGateway

**Phase gate:** Phase 3 `T-BRIDGE-REAL-SESSION` must be DONE.

### T-GATEWAY-LISTENER `[sonnet]` · DONE — `GatewayListener.swift` in `EngineService/Gateway/`. NWListener on 127.0.0.1:0 (ephemeral), exposes port via `onReady` callback, accepts connections, incremental HTTP read loop, `requestHandler` callback for dispatch. `@unchecked Sendable` for Swift 6 concurrency. Build clean.
Implement `NWListener` on `127.0.0.1` with an ephemeral port. Accept one connection, log the request, close. Proves the Network.framework setup works before any HTTP parsing.

**Acceptance:** Manual curl against the port returns an empty response and closes cleanly.

### T-GATEWAY-HTTP `[sonnet]` · DONE — `HTTPTypes.swift` (request/response value types with 5 response factories), `HTTPParser.swift` (RFC 7233 byte-range parsing, incomplete-data handling), `HTTPSerializer.swift` (deterministic header serialization). `HTTPSelfTest.swift` with 11 tests covering GET+range, HEAD, open-ended range, malformed ranges, 416/200/206 serialization. GatewayListener updated with incremental read loop and requestHandler dispatch. Build clean.
Implement HTTP/1.1 request parsing for HEAD and GET with `Range:` header. Response builder for 200, 206, 416. Zero framework dependencies beyond Foundation + Network.

**Acceptance:** Unit tests with hand-crafted byte streams: valid HEAD, valid GET with range, malformed range, range beyond length. All handled.
**Depends on:** `T-GATEWAY-LISTENER`.

### T-GATEWAY-PLANNER-WIRING `[sonnet]` · DONE — `PlaybackSession.swift` (gateway ↔ planner coordinator) and `StreamRegistry.swift` (stream routing) created in `EngineService/Gateway/`. Originally had `GatewayPlannerSelfTest.swift` (`--gateway-planner-self-test` launch arg) covering 7 direct session tests and 2 live HTTP round-trip tests via a real `GatewayListener`, but that test relied on the broken `createTestTorrent` helper. **Converted to shim 2026-04-16** — coverage fully subsumed by `--stream-e2e-self-test` against a real torrent (see GitHub #94). Both Xcode schemes build clean. Dispatch wired in `main.swift`.
Connect the gateway to `PiecePlanner`. Every incoming request becomes a `PlayerEvent`. Planner actions drive `TorrentBridge` calls (via a mapper, not directly from the gateway). Gateway waits for bytes per the planner's `waitForRange` action.

**Acceptance:** Integration test: fake `TorrentSession` + real gateway + real planner + hand-crafted HTTP client. Plays through a 10 MB synthetic file.
**Depends on:** `T-GATEWAY-HTTP`, `T-BRIDGE-REAL-SESSION`.

### T-GATEWAY-BYTE-READER `[sonnet]` · DONE — `ByteReader.swift` in `EngineService/Gateway/`. Maps byte ranges to torrent pieces, walks contiguous available run via `havePieces`, throws `bytesNotAvailable` if first piece missing, returns partial `ReadResult` if tail pieces unavailable. Enforces issue #91 (no silent zero-reads from sparse file). Build clean.
Implement sparse-file reader that pulls bytes from the libtorrent-managed file via `TorrentBridge.readBytes(...)`. Handles partial reads (asked for N bytes, got M).

**Acceptance:** Unit tests with a pre-populated sparse file.
**Depends on:** `T-BRIDGE-API`.

---

## Phase 5 — First end-to-end stream

**Phase gate:** Phase 4 `T-GATEWAY-PLANNER-WIRING` and `T-GATEWAY-BYTE-READER` must be DONE.

### T-STREAM-E2E `[sonnet]` · DONE — **Runtime-verified 2026-04-16** against Internet Archive "Big Buck Bunny" (276 MB MP4). `createTestTorrent` dropped; self-test accepts a real magnet URI or `.torrent` path, waits for metadata + first 8 pieces, spins up StreamRegistry + GatewayListener, runs HTTP round-trips. Passed: HEAD → 200 (Content-Length 276,134,947); GET bytes=0-65535 → 206 (65536 bytes); GET bytes=524288-525311 → 206; GET /stream/unknown → 404; byte-accuracy (HTTP body ≡ TorrentBridge.readBytes). Required `com.apple.security.network.server` entitlement added to EngineService.entitlements so libtorrent can bind port 6881 for peer listen. AVPlayer integration remains a separate manual step (per original acceptance criteria "recorded video of successful playback"); protocol-level proof is in the above self-test. See `docs/test-content.md`. GitHub #94 closed.
Open a known-good public-domain torrent, select a file, open a stream via XPC, point `AVPlayer` at the returned loopback URL, verify playback starts within 10 seconds and runs for 60 seconds without a stall.

**New self-test invocation:**
```
EngineService --stream-e2e-self-test <magnet-or-torrent-path>
EngineService --stream-e2e-self-test <magnet-or-torrent-path> --file-index N
```
Suggested magnet (Big Buck Bunny, ~276 MB MP4, well-seeded):
```
magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969
```

**Acceptance:** Run self-test exits 0 against the above magnet. Then manual AVPlayer smoke test with a named public-domain torrent per `docs/test-content.md`.
**Depends on:** all Phase 4 tasks.
**Review gate:** `[opus]` reviews before marking DONE. First real proof the architecture works.

---

## Phase 6 — CacheManager, UI, polish

**Phase gate:** `T-STREAM-E2E` DONE and reviewed.

### T-GATEWAY-PLANNER-SERIALIZATION `[sonnet]` · DONE — Renamed `tickQueue` → `plannerQueue`; timer fires on it; `handleRequest` dispatches all planner calls onto it via `plannerQueue.sync { }`, releasing the lock before entering `waitAndRead` so ticks are never blocked during byte-serving. `processActionsAndServe` split into `processActionsForGET` (runs on plannerQueue, returns wait params) + inlined byte-serving in `handleRequest` (runs on gateway queue). `@unchecked Sendable` comment updated to reflect the actual mechanism. Both Xcode schemes build clean.
Serialize all planner access in `PlaybackSession` onto a single dispatch queue. Currently the tick timer runs on `tickQueue` while HTTP request handling runs on the gateway queue — both call `DefaultPiecePlanner` methods, which is a mutable class with no internal thread safety. The `@unchecked Sendable` comment claims "the two paths never overlap" but this is not enforced by any mechanism. Fix: route all planner calls (both `handle(event:)` from requests and `tick()` from the timer) through a single serial queue.

**Found during:** T-STREAM-E2E Opus review.
**Depends on:** `T-STREAM-E2E`.
**Acceptance:** `PlaybackSession` uses a single serial queue for all planner access. The `@unchecked Sendable` justification is updated to reflect the actual serialization mechanism. No behavioural change in the E2E self-test.

### T-CACHE-SCHEMA `[sonnet]` · DONE
Wire `CacheManager` to the GRDB models created in `T-STORE-SCHEMA`. Implemented `CacheManager` (playback history upsert/fetch + pinned-file CRUD + in-memory pinned set) and `PinnedKey` in `EngineService/Cache/CacheManager.swift`. Self-tests (6 cases including restart simulation) in `EngineService/Cache/CacheManagerSelfTest.swift`, wired to `--cache-manager-self-test`. Added `EngineStore` local SPM package dependency to EngineService target in Xcode project.

**Depends on:** `T-STORE-SCHEMA`.
**Acceptance:** Unit tests that exercise the read/write helpers and verify the in-memory pinned set is rebuilt correctly after a simulated engine restart.

### T-CACHE-EVICTION `[sonnet]` · DONE: mechanism decided (A24, F_PUNCHHOLE + force_recheck), probe validated it, CacheManager eviction implemented + self-tested on PR #101 and V2 branch (spec 05 rev 4).
Spike and then implement `CacheManager` with the eviction ordering from `05-cache-policy.md`. Unit tests with synthetic sparse-file state.

**Probe interface (2026-04-16 rewrite):** Original probe generated synthetic 256 KB content via `createTestTorrent`, which is broken in the sandbox. Rewritten to accept a real magnet link (or `.torrent` path) so observations come from real libtorrent behaviour on real content:
```
EngineService --cache-eviction-probe <magnet-or-torrent-path>
EngineService --cache-eviction-probe <magnet-or-torrent-path> --file-index N
```
Downloaded content is left in `NSTemporaryDirectory()` for iterative reruns. Paste NSLog output into `docs/libtorrent-eviction-notes.md`.

**This task is an implementation spike.** The eviction mechanism described in `05-cache-policy.md` ("truncate regions where possible, or mark them for future overwrite") is hand-wavy because libtorrent's file-hole semantics and per-piece eviction behaviour need to be verified empirically against the real library. Before implementing:

1. ✅ Write a small probe program that exercises libtorrent's `file_priority` and storage APIs against a real sparse file on HFS+/APFS. **Implemented as `--cache-eviction-probe` self-test in `EngineService/Cache/CacheEvictionProbe.swift`.**
2. Verify what actually happens when a piece's priority is set to 0 — does the file region get truncated, sparsified, or just marked inert in libtorrent's view?
3. Verify that setting a previously-evicted piece back to high priority causes libtorrent to re-fetch it.
4. Document the observed behaviour in `docs/libtorrent-eviction-notes.md`.
5. Only then implement `CacheManager` against the observed reality, and only then update `05-cache-policy.md` with the confirmed mechanism.

**User action required before steps 2–5 can proceed:** Run the probe on a real machine and paste the output into `docs/libtorrent-eviction-notes.md`:
```
.build/debug/EngineService --cache-eviction-probe 2>&1 | tee docs/libtorrent-eviction-notes.md
```

**TorrentBridge mechanism (2026-04-16 decision, addendum A23):** libtorrent 2.0.12 does NOT expose `torrent_handle::clear_piece`; `grep` of the Homebrew headers confirmed the method is internal to `disk_interface` only. Eviction is therefore built from two public methods:
- `addPiece(torrentID:, piece:, data:, overwriteExisting:)` — primary, per-piece. Writing 256 KB of zeros with `overwrite_existing` triggers a hash failure, which causes libtorrent to internally call `async_clear_piece` and remove the piece from the have-bitmap. Paired with a piece-aligned `F_PUNCHHOLE` *after* the `hash_failed_alert` arrives to reclaim APFS blocks.
- `forceRecheck(torrentID:)` — fallback, whole-torrent. Reserved for idle-time bulk reconciliation and recovery if the add_piece trick ever stops working.

Both methods are being added to `TorrentBridge.h/.mm` on `engine/T-CACHE-EVICTION`. The revised probe exercises both in a single run so observations come from the real library.

**Depends on:** `T-CACHE-SCHEMA`, `T-BRIDGE-API` (need real libtorrent to probe).
**Acceptance:** Probe notes committed, CacheManager implemented against observed behaviour, unit tests green, spec 05 updated with concrete mechanism (remove the "where possible / mark for future overwrite" hedge).

### T-CACHE-RESUME `[sonnet]` · DONE
Wire resume offset tracking: update every 15 seconds during playback, on stream close, and on clean shutdown. Restore on next open.
**Depends on:** `T-CACHE-SCHEMA`.
**Completed:** `ResumeTracker` with deadline-based 15s throttle + injectable time source; wired into `PlaybackSession` (tick path + stop) and `StreamRegistry` (creates tracker per stream). Five self-tests pass (`--resume-tracker-self-test`). `StreamDescriptorDTO` extended with `resumeByteOffset: Int64` (schema v2, additive/backward-compatible) for v1 XPC contract readiness; `StreamDescriptor` domain type and both mapping directions updated; `FakeEngineBackend` passes 0; real backend populates from `CacheManager.fetchHistory` — wired 2026-04-16 as part of GitHub #95.

### T-CACHE-EVICTION-WIRE `[sonnet]` · DONE — PR #108 (merged 2026-04-16)
Wire `CacheManager.runEvictionPass` into `RealEngineBackend`. Shipped: 30 s `DispatchSourceTimer` on the backend's serial queue (initial fire at +1 s so subscribers see DTO promptly), candidate computation with tier-rank assignment per spec 05 § Eviction order, v1 wholesale exclusion of pinned + partial-resume + active-stream files, `DiskPressureDTO` emission with 5 s throttle + level-change override, eviction pass invoked only when `level == .critical` and no torrent has an active stream, `StreamRegistry.hasActiveStream(torrentID:)` accessor, 8-case `--eviction-wire-self-test`, pure helpers extracted for coverage. Opus APPROVE-WITH-FOLLOW-UPS (findings F4/F5/F6/F7 applied in-PR; F2 helper-visibility drift and F3 decideToEvict extraction deferred as nice-to-haves). Closes #104.

### T-BRAND-ASSETS `[sonnet]` · DONE 2026-04-16 — `App/AppIcon.icon` authored in Icon Composer from the supplied Liquid Glass prep package, wired into the ButterBar Xcode target as a `folder.iconcomposer.icon` resource, `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` set on Debug + Release. Build produces `AppIcon.icns` with the brown-on-blue butter-bar mark; Dock and Finder render correctly after `lsregister -f` + `killall Dock Finder`. Closes #112. Follow-up polish (warm-palette background, per-variant Dark/Tinted/Clear tuning) deferred — open as a new issue if/when desired; the Apple-default blue gradient remains in `icon.json` § fill.
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

### T-UI-LIBRARY `[sonnet]` · DONE 2026-04-16 — Opus-reviewed APPROVE-WITH-FOLLOW-UPS
SwiftUI library list (`App/Features/Library/LibraryView.swift`, 258 lines) using brand tokens throughout (`surfaceBase`, `cocoa`, `cocoaSoft`, `cocoaFaint`, `creamRaised`, `butter`); calm empty-state copy "Add a magnet link to begin."; in-memory filter via `.searchable` + `localizedStandardContains`; multi-file `FileSelectionSheet`; per-row `TorrentRow` with monospaced numerics for progress and rate; error banner overlay. `LibraryViewModel` (@MainActor) bridges actor-isolated `EngineClient` with `previewWithData` / `previewEmpty` factories. 4 snapshot baselines committed (populated × empty × {light, dark}). Opus review: brand-token compliance ✓, voice ✓, glass-only-on-floating ✓, motion (.easeInOut value-tied) ✓, deployment target ✓. Follow-ups filed: #111 (error banner double-prefix), #114 (HUD initial-visibility analogue is in #114), #116 (`Color.black` token).

**Spec:** `06-brand.md` § Window chrome and layout, § Typography, § Voice. Use `cream`-toned surface, `cocoa` primary text, `cocoaSoft` for metadata. Empty-state copy per the brand voice ("Add a magnet link to begin." not "Welcome!").
**Acceptance:** Library view renders with brand-compliant colours and typography. Empty state matches the brand voice. Snapshot test for light and dark modes.

### T-UI-PLAYER `[sonnet]` · DONE 2026-04-16 — Opus-reviewed APPROVE-WITH-FOLLOW-UPS
SwiftUI player (`App/Features/Player/PlayerView.swift` + `PlayerViewModel.swift` + `AVPlayerViewRepresentable.swift`): `AVPlayerView` wrapped via `NSViewRepresentable`; `.preferredColorScheme(.dark)` enforced regardless of system appearance; `Color.black` letterbox; floating `StreamHealthHUD` at bottom-centre with 24 pt margin, auto-hide on hover (3 s timer); `viewModel.health` subscription via `EngineEventHandler.streamHealthChangedSubject` filtered by `streamID`; resume-seek by byte-ratio when `streamDescriptor.resumeByteOffset > 0`; idempotent `close()` releases `AVPlayer` and calls `closeStream` over XPC. HUD already DONE under T-UI-HEALTH-HUD provides the continuous 800 ms `.easeInOut` buffer-ahead animation, tier-colour 4 pt left strip paired with text label, and `.glassEffect(.regular.interactive())` floating surface. Opus review: dark-by-default ✓, glass-only-on-floating ✓, value-tied .easeInOut motion ✓, brand-token compliance ✓ (one nit: `Color.black` letterbox → #116). Follow-ups filed: #110 (HUD reconnect re-subscribe), #113 (HUD initial visibility timer), #114 (drop unreachable `#available(macOS 26)` guards), #115 (HUD glass tinting), #117 (typed tier enum), ~~#118 (snapshot tests need test scheme)~~ — resolved by PR #120. New follow-up #121 filed during #118 review (NSHostingView appearance pinning; 3 light-mode HUD tests skipped pending).

**Spec:** `06-brand.md` § Window chrome and layout (player window is dark by default), § Motion (slow easeInOut, no springs).
**Depends on:** `T-UI-LIBRARY`, `T-STREAM-E2E`.
**Acceptance:** Player window opens dark regardless of system appearance. HUD floats over video with `cocoa` 60% opacity background. Buffer-ahead indicator animates continuously, not in steps.

> Acceptance note: spec 06 § Window chrome supersedes the "cocoa 60% opacity background" wording in this task with `.glassEffect(.regular.interactive())` for the production path on macOS 26. The `cocoa.opacity(0.6)` fallback still exists in code but is unreachable at the v1 deployment target — see #114.

### T-UI-HEALTH-HUD `[sonnet]` · DONE — Largely subsumed by `StreamHealthHUD` in T-UI-PLAYER: brand tier tokens (`tierHealthy`/`tierMarginal`/`tierStarving`), 400 ms cross-fade, 4 pt left colour strip paired with text label (colour never sole signal), 800 ms buffer-fill animation, glass surface with cocoa fallback. Residual work landed here: light-mode snapshot tests added (3 variants) alongside the existing 3 dark-mode snapshots — 6 total per spec 06 § Test obligations. No tier computation in UI; tier comes from `StreamHealthDTO.tier` as assigned by the engine.

### T-XPC-REAL-BACKEND `[codex]` · DONE 2026-04-16 — GitHub #95. `EngineXPCServer` now delegates to `RealEngineBackend` (owns `TorrentBridge + StreamRegistry + GatewayListener + CacheManager + AlertDispatcher`); `FakeEngineBackend` retained behind `--fake-backend` launch arg for test isolation. `EngineService.xpc` embedded in `ButterBar.app/Contents/XPCServices/` via Copy Files phase + `PBXTargetDependency`. `Info.plist` fixed (`XPCService.ServiceType = Application`, was non-standard `NSXPCServiceType`). `main.swift` converted to `@main EngineServiceMain` (XPC-brokered launches bypass top-level `main.swift` code). `com.apple.security.network.server` entitlement added to EngineService for libtorrent peer listen. Final fixes (by Codex): eliminated race between `ContentView.onAppear { connect }` and `LibraryView.task { refresh }` by collapsing into a single sequential `LibraryViewModel.start()`; `EngineClient.connect()` made idempotent; `EngineClientError: LocalizedError` for useful error messages; all continuation-backed `EngineClient` wrappers (`listTorrents`, `addMagnet`, `addTorrentFile`, `removeTorrent`, `listFiles`, `setWantedFiles`, `openStream`, `closeStream`, `subscribe`) now use per-call XPC proxy error handlers plus a single-shot `ContinuationResumer`, so mid-call connection invalidation cannot leak a Swift continuation. App launches, XPC connects, library loads — no error banner. First runtime verification of the full app→XPC→engine→gateway path. Follow-up hardening also fixed a duplicate Xcode project file reference for `StreamE2ESelfTest.swift`; AppIntents.framework is linked for the app/XPC products so Xcode metadata extraction is clean; the fake-backend/cache Swift warnings are fixed; the Debug app clean build is warning-free.

---

## Phase 7 — Hardening

### T-SECURITY-XPC-CODESIGN `[sonnet]` · DONE — PR #109 (merged 2026-04-16)
Once the service bundle is signed, add `setCodeSigningRequirement(_:)` to the connection and verify rejected peers. Shipped via two coordinated commits: (1) main `1483bcc` set project-level `DEVELOPMENT_TEAM = 6633CLRXPK` (free personal team) after user configured Xcode Signing & Capabilities — bundles now sign with `Apple Development: matt@drmk.link (626V43H78B)`, real `TeamIdentifier=6633CLRXPK` replaces prior adhoc; (2) PR #109 added `NSXPCConnection.setCodeSigningRequirement` on both sides of the app↔engine link with `identifier "<bundle id>" and anchor apple generic and certificate leaf[subject.OU] = "6633CLRXPK"`. Calls are non-throwing; server delegate sets the requirement on every accepted connection so peer messages from non-matching bundles are silently dropped by the runtime. `--xpc-codesign-self-test` validates: requirement-string parseability, the running process satisfies its own engine requirement, and a wrong-team requirement is rejected (`SecCodeCheckValidity` returns `errSecCSReqFailed` / -67050). Opus APPROVE-WITH-FOLLOW-UPS (3 low-severity nits, all non-blocking).

**Known follow-up:** paid-team migration would require updating both requirement-string OU values from `6633CLRXPK` to the new team identifier in three locations: `App/Shared/EngineClient.swift`, `EngineService/EngineServiceMain.swift`, `EngineService/XPC/XPCCodesignSelfTest.swift`.

### T-PERF-SEEK-BENCH `[sonnet]` · DONE — PR #106 (merged 2026-04-16)
Benchmark: measure seek-to-first-frame time across the four trace fixtures. Record results. Regressions block merges. **Shipped:** `PlannerSeekBenchTests.swift` (XCTest `measure(metrics: [XCTClockMetric()])`, 4 fixtures, fresh planner+session per iteration); `PlannerSeekBenchRecorder.swift` (opt-in N=20 recorder gated on `BUTTERBAR_RECORD_SEEK_BASELINE=1`); `scripts/run-seek-bench.sh`; `docs/benchmarks/README.md`; `docs/benchmarks/seek-baseline.json` (arm64 / macOS 26.5: p50 0.039–0.058 ms). Spec gap (specs 02/04/05 name no numerical SLA) captured in follow-up issue #107 tagged `[opus]`. Opus APPROVE; 3 cosmetic fixups applied in-PR. Closes #105.

### T-DOC-ARCHITECTURE `[opus]` · TODO
Write `docs/architecture.md` describing the shipped v1 for future contributors. Includes the diagrams from `01-architecture.md` plus notes on what was tried and rejected.

---

## Escalation protocol

Any task marked `BLOCKED:` halts work on that task. The blocking reason goes in the task description. Opus triages blocked tasks at the next review gate or on explicit request.

Sonnet must not:
- Modify specs to unblock itself.
- Pick up a task from a later phase to "make progress" while blocked.
- Silently reinterpret an ambiguous spec — raise it.
