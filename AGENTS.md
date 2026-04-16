# ButterBar — Codex Agent Instructions

This file adapts `CLAUDE.md` for Codex. `CLAUDE.md` remains the source of truth; if this file and `CLAUDE.md` differ, follow `CLAUDE.md` and update this file.

ButterBar is a buttery-smooth native macOS media player for **macOS Tahoe (26) and later**. It streams from torrent sources for lawful/public-domain use cases, uses AVKit playback with no transcoding, and should feel like a calm, premium native app aligned with Liquid Glass.

## Operating Model

Codex should work as an implementation agent unless the user explicitly asks for architecture, design review, spec revision, or code review.

- Implement one scoped task at a time from `.claude/tasks/TASKS.md` when doing engine work.
- Treat specs in `.claude/specs/` as frozen implementation contracts.
- Do not modify specs unless the user explicitly asks for a design/spec revision.
- If a spec appears wrong, incomplete, or ambiguous, stop that task and mark it `BLOCKED: <reason>` in `.claude/tasks/TASKS.md` instead of silently changing the contract.
- Write tests alongside implementation for any non-trivial component.

## Reading Order

Read only as much as needed for the current task, but preserve this precedence:

1. `CLAUDE.md` — source-of-truth orientation.
2. `.claude/specs/00-addendum.md` — revision decisions that override or clarify numbered specs.
3. `.claude/specs/01-architecture.md` — settled v1 engine architecture.
4. `.claude/specs/02-stream-health.md` — canonical `StreamHealth` definition.
5. `.claude/specs/03-xpc-contract.md` — XPC interface and DTO layer.
6. `.claude/specs/04-piece-planner.md` — planner responsibilities, trace schema, action schema.
7. `.claude/specs/05-cache-policy.md` — piece-granular eviction and resume offsets.
8. `.claude/specs/06-brand.md` — visual identity, voice, palette, logo specifications. Required for UI work.
9. `.claude/specs/09-platform-tahoe.md` — macOS Tahoe deployment target, SDK, Liquid Glass stance, hardware support. Required for deployment configuration, Info.plist, and icon assets.
10. `.claude/specs/07-product-surface.md` — catalogue, sync, providers, watch state. Required for product-surface work.
11. `.claude/specs/08-issue-workflow.md` — GitHub issue, branch, and PR conventions. Required for issue creation or PR work.
12. `.claude/tasks/TASKS.md` — engine build queue with blockers.
13. `.claude/agents/` — role-specific instructions when invoking or emulating a specialized agent.

Precedence rule: where `.claude/specs/00-addendum.md` conflicts with a numbered spec, the addendum wins. Numbered specs may include revision blocks pointing at the addendum items that affect them.

## Tracking Model

ButterBar uses two authoritative trackers:

- Engine work lives in `.claude/tasks/TASKS.md`.
- Product-surface work lives in GitHub issues under the conventions in `.claude/specs/08-issue-workflow.md`.

Keep these scopes separate. Connect them only at the seams defined by the specs.

## Frozen V1 Decisions

Do not reopen these decisions unless the user explicitly asks for a spec/design revision:

- Platform target: macOS Tahoe 26.0 minimum, Xcode 26 / SDK 26, Apple silicon priority.
- UI: SwiftUI app with `AVPlayerView` wrapped for SwiftUI; Liquid Glass on toolbar/sidebar/HUD per brand spec.
- IPC: `NSXPCConnection` between app and engine, with DTOs separate from domain types.
- Engine process: separate long-lived `EngineService` process owning libtorrent, SQLite, and playback gateway.
- Torrent core: libtorrent-rasterbar behind one narrow ObjC++ `TorrentBridge`; no separate C++ policy layer in v1.
- Playback gateway: loopback HTTP server on `127.0.0.1` using `Network.framework` / `NWListener`, inside the engine process. It supports HEAD, GET, Range, and 206.
- Storage: stock GRDB over system SQLite. No FTS5 in v1. Library search uses in-memory `localizedStandardContains` filtering over summaries.
- Piece scheduling: deadline-driven via `set_piece_deadline()`, not `sequential_download`.
- PiecePlanner: first-class deterministic state machine driven by `(events, availability schedule, injected time)`. No real clocks, threading, randomness, or I/O inside planner logic. Build trace-first and test-first.
- Codec policy: native playback only with AVFoundation-compatible containers/codecs. No transcoding pipeline in v1.
- Multi-file torrents: supported with exposed file list and user file selection.
- Subtitles: embedded/associated legible tracks only. Sidecar `.srt` ingestion is v1.5+.
- Single-writer ownership: engine owns SQLite. App has no direct database access. All projections are served via XPC.
- Cache eviction: piece-granular, not file-granular. Persist `resumeByteOffset` per file.
- App icon: Liquid Glass `.icon` bundle authored in Apple's Icon Composer from `icons/ButterBar-LiquidGlass-prep/`, placed at `App/AppIcon.icon` beside `Assets.xcassets`. Legacy `.icns` remains inactive.

## Rejected Ideas

Do not reintroduce these without explicit escalation:

- SwiftNIO for the v1 gateway. Use Network.framework unless the HTTP surface grows past trivial.
- Separate `TorrentCore` C++ policy layer. V1 collapses this into `TorrentBridge`.
- FTS5 with custom SQLite build. V1 uses in-memory filtering.
- Rejecting multi-file torrents. V1 supports file selection.
- `AVAssetResourceLoaderDelegate` as the primary playback path. V1 uses loopback HTTP first; resource loader is a v2 option.

## Task Workflow

When implementing a task from `.claude/tasks/TASKS.md`:

1. Identify the exact task ID.
2. Read the relevant specs, normally `00-addendum.md` plus one to three task-specific numbered specs.
3. Preserve acceptance criteria as written.
4. Do not modify specs.
5. Implement the smallest coherent change that satisfies the task.
6. Add focused tests for non-trivial behavior.
7. Mark the task `DONE` in `.claude/tasks/TASKS.md` with a one-line summary when complete.
8. List follow-up items noticed but not done.
9. Flag any unclear spec point even if a practical implementation decision was made.

If blocked:

1. Mark the task `BLOCKED: <reason>` in `.claude/tasks/TASKS.md`.
2. Stop work on that task.
3. Do not patch the spec to unblock yourself unless explicitly instructed.

## Review Gates

Expect architecture/design review at these points:

- Before any task in a new phase starts.
- After `T-PLANNER-CORE` completes.
- After `T-XPC-INTEGRATION` completes.
- After `T-STREAM-E2E` completes.

For these review-gated tasks, move to review status rather than treating the work as fully complete if the surrounding workflow requires it.

## GitHub And PR Workflow

Follow `.claude/specs/08-issue-workflow.md` for issues, branches, and PRs.

Claude Code hooks in `.claude/settings.json` run after `gh pr create` and `gh pr merge` through `scripts/pr-lifecycle-hook.sh`. Treat hook output as mandatory.

On PR create:

- Ensure the PR body references an issue with `Closes #N` or `Refs #N`.
- For `engine/T-*` branches, update `.claude/tasks/TASKS.md` status as required.

On PR merge for engine branches:

- Parse the task ID from the branch name, for example `engine/T-PLANNER-CORE` -> `T-PLANNER-CORE`.
- Mark review-gated tasks as `REVIEW`: `T-PLANNER-CORE`, `T-XPC-INTEGRATION`, `T-STREAM-E2E`.
- Mark other engine tasks as `DONE`.

Non-engine branches rely on GitHub's `Closes #N` auto-close behavior. The hook validates the reference.

## Target Layout

The intended project structure is:

```text
ButterBar/
├── App/                          # SwiftUI app target
│   ├── AppIcon.icon/             # Tahoe Icon Composer bundle
│   ├── Assets.xcassets/          # Does not contain AppIcon for v1
│   ├── Brand/
│   ├── Features/Library/
│   ├── Features/Search/
│   ├── Features/Torrents/
│   ├── Features/Player/
│   └── Shared/
├── EngineService/                # XPC service target
│   ├── Bridge/                   # ObjC++ TorrentBridge
│   ├── Planner/                  # PiecePlanner pure Swift
│   ├── Gateway/                  # Network.framework HTTP range server
│   ├── Cache/
│   ├── Store/                    # GRDB models and migrations
│   └── XPC/
├── Packages/
│   ├── EngineInterface/          # Shared XPC protocols and DTOs
│   ├── PlannerCore/              # PiecePlanner and trace replay harness
│   └── TestFixtures/             # JSON traces, availability schedules
├── icons/
│   ├── butter-bar-logo.svg
│   ├── ButterBar.iconset/        # Legacy inactive v1 asset
│   ├── ButterBar.icns            # Legacy inactive v1 asset
│   └── ButterBar-LiquidGlass-prep/
└── Tests/
    ├── PlannerReplayTests/
    ├── GatewayRangeTests/
    └── XPCContractTests/
```

## Mission

Build ButterBar so the planner is proven correct on recorded traces before UI code exists; every cross-process message is a typed DTO; the first working end-to-end playback is boring and predictable; and the shipped product feels like a calm, premium native macOS Tahoe app rather than a torrent client that happens to play video.
