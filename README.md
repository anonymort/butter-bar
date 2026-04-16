<p align="center">
  <img src="icons/butter-bar-logo-1024.png" width="128" height="128" alt="ButterBar logo">
</p>

<h1 align="center">Butter Bar</h1>

<p align="center">A buttery-smooth native macOS media client for <strong>macOS Tahoe (26) and later</strong>.</p>

Butter Bar is a desktop-native streaming application in the general product category of clients like Popcorn Time, Seren, and Umbrella. It pairs a deterministic, well-tested playback engine (libtorrent-backed streaming, AVKit playback, native loopback HTTP gateway) with a polished SwiftUI product surface (catalogue browsing, metadata, account sync, subtitles, watch state) — all built natively against the Liquid Glass design language Apple introduced in macOS Tahoe.

## Status

**Phases 0–6 complete, app↔engine XPC runtime-verified.** Phase 5 `T-STREAM-E2E` runs end-to-end against the Internet Archive "Big Buck Bunny" torrent (276 MB MP4) with HTTP bytes matching `TorrentBridge.readBytes` byte-for-byte. All supporting unit tests pass: 158 SPM tests (PlannerCore, EngineInterface, XPCMapping, EngineStore), 10 snapshot baselines for LibraryView and StreamHealthHUD in both colour schemes, plus HTTP/CacheManager/ResumeTracker self-tests. Phase 6 cache/resume/library/player/HUD code compiles cleanly and is unit-test covered. `EngineXPCServer` now delegates to `RealEngineBackend` (TorrentBridge + StreamRegistry + GatewayListener + CacheManager), the `.xpc` bundle is embedded in `ButterBar.app`, and the full app→XPC→engine path is runtime-verified — the library loads cleanly when launching the app (GitHub #95 resolved). Known open items: `T-CACHE-EVICTION` probe awaits a user-run observation session against a real magnet; `T-BRAND-ASSETS` requires Icon Composer (GitHub #112); the AVPlayer end-to-end acceptance (recorded video of actual playback through the UI) is the remaining v1 milestone.

**Latest hardening (2026-04-16):** `docs/architecture.md` now captures the shipped v1 architecture and rejected implementation paths. HUD snapshot tests use SwiftUI's renderer with explicit colour-scheme pinning, so all six StreamHealthHUD baselines are active again. `TorrentAlert` no longer uses `-1` as a missing `pieceIndex` sentinel and now has a typed `hashFailed` case. The CI/libtorrent setup uses Homebrew `opt` symlinks instead of versioned Cellar paths.

**Phase 6 wrap-up (2026-04-16):** T-UI-LIBRARY and T-UI-PLAYER both Opus-reviewed APPROVE-WITH-FOLLOW-UPS and marked DONE in TASKS.md. Brand-token compliance verified across feature code, glass strictly limited to floating navigation chrome (the HUD), `.preferredColorScheme(.dark)` enforced on the player, motion is value-tied `.easeInOut` throughout. Nine non-blocking follow-ups filed as GitHub issues: #110 (HUD reconnect re-subscribe), #111 (library error banner double-prefix), #112 (T-BRAND-ASSETS user-action: Icon Composer authoring), #113 (HUD initial visibility timer), #114 (drop unreachable `#available(macOS 26)` guards), #115 (HUD glass tinting), #116 (`BrandColors.videoLetterbox`), #117 (typed `StreamHealthTier` enum at XPC boundary), #118 (`ButterBar` scheme has no test action — snapshot tests cannot run via xcodebuild as-is).

## Documentation

Start with [`CLAUDE.md`](./CLAUDE.md). It is the orchestration root and points at everything else in the right reading order. For a contributor-facing overview of the implemented v1 system, read [`docs/architecture.md`](./docs/architecture.md).

The full specification set lives in [`.claude/specs/`](./.claude/specs/):

- **00-addendum** — revision decisions; overrides numbered specs on conflict.
- **01-architecture** — engine top-level shape and component responsibilities.
- **02-stream-health** — canonical `StreamHealth` type.
- **03-xpc-contract** — XPC interface and DTO layer.
- **04-piece-planner** — planner contract, trace schema, fixture set.
- **05-cache-policy** — piece-granular eviction and resume offsets.
- **06-brand** — visual identity, voice, palette, logo (Tahoe-aware).
- **07-product-surface** — user-facing feature areas: catalogue, sync, providers, watch state.
- **08-issue-workflow** — GitHub issue/branch/PR conventions.
- **09-platform-tahoe** — macOS 26 deployment target, SDK, Liquid Glass adoption stance.

## Two-tracker model

Engine work is tracked in [`.claude/tasks/TASKS.md`](./.claude/tasks/TASKS.md). Product-surface work is tracked as [GitHub issues](https://github.com/anonymort/butter-bar/issues). The reasoning is in [spec 08](./.claude/specs/08-issue-workflow.md) and addendum A17.

## Contributing

Read [`CONTRIBUTING.md`](./CONTRIBUTING.md). Branch conventions, PR rules, and the code-review model are defined in spec 08.

## Setup

To set up the GitHub project (labels, milestones, epic issues), run:

```bash
./scripts/setup-repo.sh
```

This requires the [GitHub CLI](https://cli.github.com/) (`gh`) authenticated against the `anonymort/butter-bar` repository.

## Licence

TBD before v1 release.
