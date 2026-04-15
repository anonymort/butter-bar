# Issue conversion mapping

This document maps every outstanding-work checkbox in `.claude/specs/07-product-surface.md` to a planned GitHub Feature issue. It is the **source of truth** for `scripts/seed-issues.sh` and the **review artefact** for bulk issue creation.

Read this through before running `seed-issues.sh`. If anything looks wrong — missing items, wrong priority, wrong module — fix it here first, then re-run the script (it's idempotent and uses titles to detect duplicates).

## Format

Each row: spec section · checkbox text · proposed issue title · priority · module · milestone · dependencies.

Issue titles follow the pattern `<Module>: <verb-led description>` so they sort and scan well in the GitHub issue list.

## Module 1 — Discovery and metadata

| # | Checkbox | Issue title | Pri | Module | Milestone | Depends |
|---|---|---|---|---|---|---|
| 1.1 | Define metadata schema for movie, show, season, episode | `Discovery: define metadata schema (movie/show/season/episode)` | p0 | discovery | v1 | needs-design (which metadata source?) |
| 1.2 | Decide source of metadata and image assets | `Discovery: spike — evaluate metadata sources (TMDB / TVDB / Trakt)` | p0 | discovery | v1 | — (this is a spike, opens as `type:spike`) |
| 1.3 | Design browse hierarchy and navigation patterns | `Discovery: design browse hierarchy and navigation` | p0 | discovery | v1 | 1.1 |
| 1.4 | Implement search index and result ranking | `Discovery: implement search index and result ranking` | p0 | discovery | v1 | 1.1 |
| 1.5 | Build title detail page UI | `Discovery: build title detail page UI` | p0 | discovery | v1 | 1.1, 1.3 |
| 1.6 | Build season/episode selector UI | `Discovery: build season/episode selector UI` | p0 | discovery | v1 | 1.5 |
| 1.7 | Implement continue-watching row fed by local state | `Discovery: continue-watching row from local state` | p0 | discovery | v1 | 4.3 |

## Module 2 — Playback UX

| # | Checkbox | Issue title | Pri | Module | Milestone | Depends |
|---|---|---|---|---|---|---|
| 2.1 | Define player state model | `Playback: define player state model` | p0 | playback | v1 | engine T-XPC-INTEGRATION |
| 2.2 | Implement resume prompt logic | `Playback: implement resume prompt logic` | p0 | playback | v1 | 2.1, 4.2 |
| 2.3 | Implement end-of-episode detection | `Playback: implement end-of-episode detection` | p0 | playback | v1 | 2.1 |
| 2.4 | Implement next-episode auto-play flow | `Playback: implement next-episode auto-play flow` | p0 | playback | v1 | 2.3, 1.6 |
| 2.5 | Add subtitle track picker | `Playback: subtitle track picker UI` | p0 | playback | v1 | 3.3 |
| 2.6 | Add audio track picker | `Playback: audio track picker UI` | p0 | playback | v1 | 2.1 |
| 2.7 | Design player overlay controls | `Playback: design player overlay controls per brand` | p0 | playback | v1 | brand spec |
| 2.8 | Add keyboard shortcut support | `Playback: basic keyboard shortcuts (space/arrows/F)` | p1 | playback | v1 | 2.7 |
| 2.9 | Build playback failure states and retry paths | `Playback: failure states and retry paths` | p0 | playback | v1 | 2.1 |

## Module 3 — Subtitles

| # | Checkbox | Issue title | Pri | Module | Milestone | Depends |
|---|---|---|---|---|---|---|
| 3.1 | Define subtitle model and supported formats | `Subtitles: define model and supported formats (SRT/WebVTT/MOV text)` | p0 | subtitles | v1 | — |
| 3.2 | Implement subtitle file ingestion | `Subtitles: drag-and-drop SRT ingestion onto player` | p0 | subtitles | v1 | 3.1 |
| 3.3 | Build subtitle selection UI | `Subtitles: selection UI` | p0 | subtitles | v1 | 3.1 |
| 3.4 | Persist preferred subtitle language | `Subtitles: persist preferred language` | p0 | subtitles | v1 | 3.3, settings storage |
| 3.5 | Add subtitle timing offset controls | `Subtitles: timing offset controls` | p2 | subtitles | v1.5 | 3.3 |
| 3.6 | Add fallback behaviour when subtitles fail to load | `Subtitles: fallback when load fails` | p0 | subtitles | v1 | 3.2 |

## Module 4 — Watch state and local library

| # | Checkbox | Issue title | Pri | Module | Milestone | Depends |
|---|---|---|---|---|---|---|
| 4.1 | Extend playback_history schema for watched-seconds | `Library: extend playback_history for watched-seconds (v1.1 path)` | p2 | library | v1.1 | engine T-STORE-SCHEMA |
| 4.2 | Build watched-state transitions | `Library: watched-state transitions (in-progress → watched → re-watching)` | p0 | library | v1 | engine T-STORE-SCHEMA |
| 4.3 | Implement continue-watching row generation | `Library: continue-watching row generation` | p0 | library | v1 | 4.2 |
| 4.4 | Add favourites/save feature | `Library: favourites with new schema table` | p0 | library | v1 | engine T-STORE-SCHEMA |
| 4.5 | Add manual mark-watched/unwatched actions | `Library: manual mark watched/unwatched` | p0 | library | v1 | 4.2 |
| 4.6 | Define conflict rules between local and synced state | `Library: define local/sync conflict rules` | p1 | library | v1 | 5.x (sync) |
| 4.7 | Add clear-history and reset-state tools | `Library: clear history and reset state tools` | p1 | library | v1 | 7.4 |

## Module 5 — Account sync

| # | Checkbox | Issue title | Pri | Module | Milestone | Depends |
|---|---|---|---|---|---|---|
| 5.1 | Define account abstraction layer | `Sync: define AccountProvider protocol` | p1 | sync | v1 | — |
| 5.2 | Implement OAuth flow | `Sync: OAuth via ASWebAuthenticationSession (Trakt)` | p1 | sync | v1 | 5.1 |
| 5.3 | Store tokens securely | `Sync: Keychain token storage` | p1 | sync | v1 | 5.2 |
| 5.4 | Implement initial library/state sync | `Sync: initial library/state sync` | p1 | sync | v1 | 5.3 |
| 5.5 | Implement incremental sync | `Sync: incremental sync` | p1 | sync | v1 | 5.4 |
| 5.6 | Build sync status UI | `Sync: status UI per brand voice` | p1 | sync | v1 | 5.4, brand spec |
| 5.7 | Build re-auth flow for expired credentials | `Sync: re-auth flow for expired tokens` | p1 | sync | v1 | 5.3 |
| 5.8 | Design conflict-resolution strategy | `Sync: conflict resolution (last-write-wins for v1)` | p1 | sync | v1 | 5.5, 4.6 |
| 5.9 | Add manual force-sync command | `Sync: manual "sync now" command` | p1 | sync | v1 | 5.5 |

## Module 6 — Provider abstraction

| # | Checkbox | Issue title | Pri | Module | Milestone | Depends |
|---|---|---|---|---|---|---|
| 6.1 | Define provider interface contract | `Provider: define MediaProvider protocol` | p1 | provider | v1 | needs-design |
| 6.2 | Design source result schema | `Provider: SourceCandidate schema` | p1 | provider | v1 | 6.1 |
| 6.3 | Build provider configuration UI | `Provider: configuration UI` | p1 | provider | v1 | 6.1 |
| 6.4 | Implement provider auth model | `Provider: auth model (API key / OAuth / none)` | p1 | provider | v1 | 6.1, 5.3 (Keychain) |
| 6.5 | Implement source search pipeline | `Provider: parallel source search pipeline with timeouts` | p1 | provider | v1 | 6.1, 6.2 |
| 6.6 | Implement source ranking strategy | `Provider: source ranking (quality > seeders > size)` | p1 | provider | v1 | 6.5 |
| 6.7 | Handle empty-source and degraded-source states | `Provider: empty/degraded source states` | p1 | provider | v1 | 6.5 |
| 6.8 | Add retry logic and timeout rules | `Provider: retry and timeout policy` | p1 | provider | v1 | 6.5 |
| 6.9 | Add provider diagnostics logging | `Provider: diagnostics logging` | p1 | provider | v1 | 7.5 |
| 6.10 | Add provider priority ordering UI | `Provider: drag-to-reorder priority UI` | p1 | provider | v1 | 6.3 |

## Module 7 — Settings and diagnostics

| # | Checkbox | Issue title | Pri | Module | Milestone | Depends |
|---|---|---|---|---|---|---|
| 7.1 | Design settings information architecture | `Settings: information architecture (sidebar sections)` | p1 | settings | v1 | brand spec |
| 7.2 | Implement account management view | `Settings: account management view` | p1 | settings | v1 | 7.1, 5.x |
| 7.3 | Implement provider management view | `Settings: provider management view` | p1 | settings | v1 | 7.1, 6.3 |
| 7.4 | Implement cache/database reset actions | `Settings: cache and database reset actions` | p1 | settings | v1 | 7.1, engine cache |
| 7.5 | Implement secure log capture | `Settings: secure log capture (no tokens, no magnets)` | p1 | settings | v1 | — |
| 7.6 | Add user-visible error reporting | `Settings: user-visible error reporting` | p1 | settings | v1 | 7.5 |
| 7.7 | Add debug mode / diagnostics screen | `Settings: debug mode / diagnostics screen` | p1 | settings | v1 | 7.5 |
| 7.8 | Add "repair app state" recovery flow | `Settings: repair app state recovery flow` | p1 | settings | v1 | 7.4 |

## Module 8 — Native macOS experience

| # | Checkbox | Issue title | Pri | Module | Milestone | Depends |
|---|---|---|---|---|---|---|
| 8.1 | Define macOS UI principles | `macOS: UI principles document (per brand)` | p1 | macos | v1 | brand spec |
| 8.2 | Implement native menu commands | `macOS: native menu commands (File/Edit/View/Playback/Library/Account/Window/Help)` | p1 | macos | v1 | 8.1 |
| 8.3 | Add keyboard navigation across browse screens | `macOS: keyboard navigation across browse` | p1 | macos | v1 | 1.x |
| 8.4 | Add dark/light appearance support | `macOS: dark/light appearance per brand palette` | p1 | macos | v1 | brand spec |
| 8.5 | Improve focus behaviour for keyboard use | `macOS: focus behaviour for keyboard use` | p1 | macos | v1 | 8.3 |
| 8.6 | Add drag-and-drop support for subtitle files | `macOS: drag-and-drop subtitle files` | p0 | macos | v1 | 3.2 (same work, dual-tagged) |
| 8.7 | Decide whether menu bar companion mode is useful | `macOS: spike — menu bar companion mode worth it?` | p3 | macos | v1.5 | — (spike) |

## Open-question issues

These come from the "Open questions" section in spec 07 § Open questions. Each is either a `type:spike` or a `type:task` requiring a documented decision.

| # | Question | Issue title | Type | Pri |
|---|---|---|---|---|
| OQ.1 | Which metadata source first? | `Decision: primary metadata source (TMDB/TVDB/Trakt)` | spike | p0 |
| OQ.2 | External player handoff in v1? | `Decision: external player handoff in v1?` | task | p1 |
| OQ.3 | Sync optional or required onboarding? | `Decision: account sync optional or required?` | task | p1 |
| OQ.4 | Built-in vs plugin providers? | `Decision: built-in vs plugin provider model for v1` | task | p1 |
| OQ.5 | AirPlay in v1? | `Decision: AirPlay in v1?` | task | p1 |
| OQ.6 | Offline/download scope? | `Decision: offline/download scope for v1` | task | p1 |
| OQ.7 | Diagnostic tooling exposure? | `Decision: which diagnostics are user-visible?` | task | p1 |

## Counts

- 8 epics
- 56 features (across modules 1–8)
- 1 spike (1.2)
- 7 open-question issues
- **Total: 72 issues**

## Process

1. Review this file. Adjust titles, priorities, dependencies, milestones as needed.
2. Run `./scripts/setup-repo.sh` first to create labels, milestones, and the 8 epics.
3. Run `./scripts/seed-issues.sh` to create the 56+8 child issues.
4. Manually link each child to its parent epic (or use the script's auto-comment feature).
5. The spike issues (1.2, 8.7, OQ.1) should be picked up first because they unblock downstream design work.
