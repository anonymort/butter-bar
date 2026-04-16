<p align="center">
  <img src="icons/butter-bar-logo-1024.png" width="128" height="128" alt="ButterBar logo">
</p>

<h1 align="center">Butter Bar</h1>

<p align="center">A buttery-smooth native macOS media client for <strong>macOS Tahoe (26) and later</strong>.</p>

Butter Bar is a desktop-native streaming application in the general product category of clients like Popcorn Time, Seren, and Umbrella. It pairs a deterministic, well-tested playback engine (libtorrent-backed streaming, AVKit playback, native loopback HTTP gateway) with a polished SwiftUI product surface (catalogue browsing, metadata, account sync, subtitles, watch state) — all built natively against the Liquid Glass design language Apple introduced in macOS Tahoe.

## Status

**Phase 5 runtime-verified; Phase 6 code complete + test-verified.** Phases 0–5 done. Phase 5 `T-STREAM-E2E` runs end-to-end against the Internet Archive "Big Buck Bunny" torrent (276 MB MP4) with HTTP bytes matching `TorrentBridge.readBytes` byte-for-byte. All supporting unit tests pass: 158 SPM tests (PlannerCore, EngineInterface, XPCMapping, EngineStore), 10 snapshot tests for LibraryView and StreamHealthHUD in both colour schemes, plus HTTP/CacheManager/ResumeTracker self-tests. Phase 6 code (cache glue, resume tracking, library view, player, health HUD) compiles cleanly and is unit-test covered. Known open items: `T-CACHE-EVICTION` probe rewritten to accept real magnets and awaits a user-run observation session before eviction can be implemented; `T-BRAND-ASSETS` requires hands-on Icon Composer work; the XPC server still delegates to `FakeEngineBackend` rather than the real `StreamRegistry`, so the full app-to-stream path through NSXPCConnection has not yet been exercised end-to-end.

## Documentation

Start with [`CLAUDE.md`](./CLAUDE.md). It is the orchestration root and points at everything else in the right reading order.

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
