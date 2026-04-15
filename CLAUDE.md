# ButterBar — Project Instructions

A buttery-smooth native macOS media player for **macOS Tahoe (26) and later**. Streams from torrent sources (lawful/public-domain use cases). Premium craft-app feel, AVKit playback, no transcoding, no compromises on UI polish, fully native to the Liquid Glass design language.

This file is the orchestration root. Read it first, then follow the pointers below.

## Orchestration model

This project uses a two-tier model:

- **Opus (design, review, architecture decisions).** Reads this file, the specs in `.claude/specs/`, and the current task list. Owns architectural decisions, spec revisions, interface contracts, and code review of merged work. Does not write implementation code directly unless a Sonnet agent is blocked on a genuinely hard design call.
- **Sonnet (implementation, grunt work, tests).** Picks one task at a time from `.claude/tasks/TASKS.md`, implements against the frozen specs, writes tests, and marks tasks complete. Does not modify specs. If a spec appears wrong or ambiguous, Sonnet stops and escalates to Opus via a `BLOCKED:` note on the task.

The boundary is strict: **specs are frozen until Opus revises them**. Sonnet implements what's written, even if it has opinions.

## Reading order

1. This file (`CLAUDE.md`) — orientation.
2. `.claude/specs/00-addendum.md` — revision decisions that override or clarify the numbered specs. Read before any numbered spec.
3. `.claude/specs/01-architecture.md` — the settled v1 engine architecture. Non-negotiable.
4. `.claude/specs/02-stream-health.md` — canonical `StreamHealth` definition. Engine and UI both consume this.
5. `.claude/specs/03-xpc-contract.md` — XPC interface and DTO layer.
6. `.claude/specs/04-piece-planner.md` — planner responsibilities, trace schema, action schema.
7. `.claude/specs/05-cache-policy.md` — piece-granular eviction and resume offsets.
8. `.claude/specs/06-brand.md` — visual identity, voice, palette, logo specifications. Required for any UI task.
9. `.claude/specs/09-platform-tahoe.md` — macOS Tahoe deployment target, SDK, Liquid Glass adoption stance, hardware support. Required for anything touching deployment configuration, Info.plist, or icon assets.
10. `.claude/specs/07-product-surface.md` — user-facing feature areas: catalogue, sync, providers, watch state. Required for any product-surface work.
11. `.claude/specs/08-issue-workflow.md` — GitHub issue/branch/PR conventions. Required for any issue creation or PR.
12. `.claude/tasks/TASKS.md` — engine build queue with blockers.
13. `.claude/agents/` — role-specific instructions for sub-agent invocations.

**Precedence rule:** where the addendum conflicts with a numbered spec, the addendum wins. Numbered specs carry revision blocks pointing at the addendum items that affect them.

**Two-tracker model (per addendum A17):** engine work is tracked in `TASKS.md`. Product surface work is tracked as GitHub issues per spec 08. The two trackers connect at well-defined seams; both are authoritative within their scope.

**Platform target (per addendum A18):** macOS 26 (Tahoe) minimum, Xcode 26 / SDK 26, Liquid Glass adopted natively. Spec 09 has the full picture.

## Frozen v1 decisions

These are decided. Do not reopen without an explicit revision from Opus.

- **Platform target:** macOS Tahoe (26.0) minimum, Xcode 26 / SDK 26 build, Apple silicon priority. See `09-platform-tahoe.md`.
- **UI:** SwiftUI app, `AVPlayerView` (AVKit) wrapped for SwiftUI, Liquid Glass adopted on toolbar/sidebar/HUD per `06-brand.md`.
- **IPC:** `NSXPCConnection` between app and engine. DTO layer separate from domain types.
- **Engine process:** Separate long-lived process (`EngineService`) owning libtorrent, SQLite, and the playback gateway.
- **Torrent core:** libtorrent-rasterbar behind one narrow ObjC++ bridge (`TorrentBridge`). No separate C++ policy layer in v1.
- **Playback gateway:** Loopback HTTP server on `127.0.0.1` using `Network.framework` / `NWListener`. Lives **inside** the engine process, not the app. Supports HEAD, GET, Range, 206.
- **Storage:** Stock GRDB over system SQLite. **No FTS5** in v1. Library search is in-memory `localizedStandardContains` filtering over summaries.
- **Piece scheduling:** Deadline-driven via `set_piece_deadline()`. Not `sequential_download`.
- **PiecePlanner:** First-class component. Deterministic state machine driven by `(events, availability schedule, injected time)`; internal mutable state is permitted but no real clocks, threading, randomness, or I/O. Developed trace-first, test-first. See `00-addendum.md` A3.
- **Codec policy:** Native playback only. AVFoundation-compatible containers/codecs. No transcoding pipeline in v1.
- **Multi-file torrents:** Supported. Expose file list, let user pick.
- **Subtitles:** Embedded/associated legible tracks only. Sidecar `.srt` ingestion is explicitly v1.5+ work.
- **Single-writer ownership:** Engine owns SQLite. App has no direct read or write access to the database file. All projections served via XPC.
- **Cache eviction:** Piece-granular, not file-granular. Persisted `resumeByteOffset` per file.
- **App icon:** Liquid Glass `.icon` bundle authored in Apple's Icon Composer from the supplied prep package (`icons/ButterBar-LiquidGlass-prep/`); placed at `App/AppIcon.icon` (sibling of `Assets.xcassets`, not nested in it). Legacy `.icns` retained inactive. See `06-brand.md` § Asset specifications.

## Reversed/rejected ideas (do not reintroduce without escalation)

- ~~SwiftNIO for v1 gateway~~ → Network.framework. Revisit only if HTTP surface grows past trivial.
- ~~Separate `TorrentCore` C++ policy layer~~ → collapsed into `TorrentBridge`.
- ~~FTS5 with custom SQLite build~~ → in-memory filtering. Library scope doesn't justify the custom build friction.
- ~~Rejecting multi-file torrents~~ → supported via file selection.
- ~~AVAssetResourceLoaderDelegate as primary playback path~~ → loopback HTTP first. Resource loader is a v2 option.

## Agent invocation protocol

When Opus delegates a task to a Sonnet sub-agent, the invocation must:

1. Reference the specific task ID from `TASKS.md`.
2. Point the agent at the relevant spec files (usually 1–3).
3. State the acceptance criteria as they appear in the task.
4. Forbid spec modification.
5. Require the agent to write tests alongside implementation for any non-trivial component.

When Sonnet completes a task it must:

1. Mark the task `DONE` in `TASKS.md` with a one-line summary of what was built.
2. List any follow-up items it noticed but did not do (these become new tasks for Opus to triage).
3. Flag any point where it felt the spec was unclear — even if it made a decision and moved on.

When Sonnet is blocked it must:

1. Mark the task `BLOCKED: <reason>` in `TASKS.md`.
2. Stop work on that task.
3. Not attempt to "fix" the spec itself.

## Review gates

Opus reviews at these points:

- Before any task in a new phase starts (Phase gate).
- After `T-PLANNER-CORE` completes — the planner is the project's highest-risk component.
- After `T-XPC-INTEGRATION` completes — first real cross-process boundary.
- After `T-STREAM-E2E` completes — first end-to-end playback of a known-good test torrent.

## Project layout (target)

```
ButterBar/
├── App/                          # SwiftUI app target
│   ├── AppIcon.icon/             # Tahoe Icon Composer bundle (sibling of Assets.xcassets)
│   ├── Assets.xcassets/          # Does NOT contain AppIcon for v1
│   ├── Brand/                    # BrandColors.swift, BrandTypography.swift, motion tokens
│   ├── Features/Library/
│   ├── Features/Search/
│   ├── Features/Torrents/
│   ├── Features/Player/
│   └── Shared/
├── EngineService/                # XPC service target
│   ├── Bridge/                   # ObjC++ TorrentBridge
│   ├── Planner/                  # PiecePlanner (pure Swift)
│   ├── Gateway/                  # Network.framework HTTP range server
│   ├── Cache/                    # CacheManager, eviction policy
│   ├── Store/                    # GRDB models + migrations
│   └── XPC/                      # EngineXPC impl
├── Packages/
│   ├── EngineInterface/          # Shared XPC protocols + DTOs
│   ├── PlannerCore/              # PiecePlanner + trace replay harness
│   └── TestFixtures/             # JSON traces, availability schedules
├── icons/                        # Supplied source material
│   ├── butter-bar-logo.svg       # Flat master + raster exports
│   ├── ButterBar.iconset/        # Legacy (inactive at v1 target)
│   ├── ButterBar.icns            # Legacy (inactive at v1 target)
│   └── ButterBar-LiquidGlass-prep/  # Layered PNGs for Icon Composer
└── Tests/
    ├── PlannerReplayTests/       # Deterministic trace-based tests
    ├── GatewayRangeTests/        # HTTP Range semantics
    └── XPCContractTests/         # DTO round-trip, secure coding
```

## One-line mission

Build ButterBar such that the planner is proven correct on recorded traces **before** any UI code exists, such that every cross-process message is a typed DTO, such that the first working end-to-end playback is boring and predictable, and such that the shipped product feels like a calm, premium native macOS Tahoe app — not a torrent client that happens to play video.
