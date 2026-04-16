# 07 — Product Surface

> **Revision 1** — initial product surface spec. Sits on top of the engine specs (01–05). Where this spec describes "Playback," that maps to the planner/gateway/cache subsystems in 04 and 05. Where it describes "Provider abstraction," that sits above the TorrentBridge in 01. See addendum A17 for the layering model.

## Purpose

Defines the user-facing product surface for Butter Bar — a macOS-native media client in the general product category of tools such as Popcorn Time, Seren, and Umbrella.

The engine specs (01–05) describe how Butter Bar plays bytes. This spec describes what the user sees and does: catalogue browsing, title discovery, account sync, subtitle handling, watch state, and provider configuration. The brand spec (06) governs how all of that looks and reads.

Items here are written as feature areas, each with required features, optional features, and outstanding work. The outstanding-work checklists are the source material for GitHub issues — see `08-issue-workflow.md` for the conversion pattern.

## Scope summary

**Must-have feature areas (P0):**
1. Discovery and metadata
2. Playback (engine in specs 04–05; UX in this spec)
3. Subtitles
4. Watch state and local library

**Required for credible v1 (P1):**
5. Account sync
6. Provider abstraction and source resolution
7. Settings, recovery, and diagnostics
8. Native macOS experience

**Deferred (P2+):**
- Casting / AirPlay / external playback
- Downloads / offline handling
- Trailers and extras
- Advanced sorting and filtering
- Multi-provider quality ranking
- Rich recommendations

## 1. Discovery and Metadata

### Goal
Browse and search films and television content cleanly and quickly. The catalogue layer is what the user sees on app launch; it must feel fast and considered, not like a directory listing.

### Required features
- Home screen with curated rows: trending, popular, recently released, top rated, continue watching.
- Global search.
- Title detail pages.
- Show season and episode navigation.
- Artwork, synopsis, runtime, year, genres, cast, rating.
- Related / recommended titles.
- Separate handling for movies vs shows.

### Outstanding work
- [ ] Define metadata schema for movie, show, season, episode (`epic:data-model`).
- [ ] Decide source(s) of metadata and image assets — open question, see end of this spec.
- [ ] Design browse hierarchy and navigation patterns.
- [ ] Implement search index and result ranking.
- [ ] Build title detail page UI.
- [ ] Build season/episode selector UI.
- [ ] Implement continue-watching row fed by local state (depends on Module 4).

### Notes
This is the minimum surface users expect before playback even begins. It is also the surface that determines whether Butter Bar feels like a real app or a torrent-search frontend.

## 2. Playback (UX layer)

### Goal
Reliable native playback with minimal friction. The playback *engine* (planner, gateway, cache) is specified in 04–05; this section is the *UX* layer on top.

### Required features
- Built-in video player using AVKit (per spec 01).
- Play / pause / scrub / seek.
- Fullscreen support.
- Resume from previous position.
- Auto-play next episode.
- Subtitle loading and switching.
- Audio track selection.
- Playback error handling.

### Optional but valuable (defer to v1.5+)
- External player handoff.
- Picture-in-picture.
- AirPlay support.
- Keyboard shortcuts (some — basic shortcuts in v1, full coverage in v1.5).
- Playback speed controls.

### Outstanding work
- [ ] Define player state model (open / playing / paused / buffering / error / closed).
- [ ] Implement resume prompt logic.
- [ ] Implement end-of-episode detection.
- [ ] Implement next-episode auto-play flow with grace period.
- [ ] Add subtitle track picker.
- [ ] Add audio track picker.
- [ ] Design player overlay controls per `06-brand.md` § Window chrome.
- [ ] Add basic keyboard shortcut support (space, arrow keys, F for fullscreen).
- [ ] Build playback failure states and retry paths.

### Engine integration
Every action in this section flows through the XPC contract in spec 03. The UI never touches the gateway URL directly except as a source for `AVPlayer`. State events arrive via `EngineEvents` subscriptions.

## 3. Subtitles

### Goal
First-class subtitle support, not an afterthought.

### Required features
- Detect available subtitle tracks embedded in the asset (handled by AVKit).
- Load local subtitle files via drag-and-drop onto the player window.
- Enable / disable subtitles during playback.
- Subtitle language selection.
- Remember user preference per language.

### Optional but valuable (defer to v1.5+)
- Subtitle search via OpenSubtitles or similar (sidecar fetching — explicitly deferred per `01-architecture.md` § What v1 explicitly excludes).
- Subtitle offset adjustment.
- Subtitle styling controls.
- Forced subtitle handling.

### Outstanding work
- [ ] Define subtitle model and supported formats (SRT, embedded WebVTT, embedded MOV text).
- [ ] Implement subtitle file ingestion via drag-and-drop.
- [ ] Build subtitle selection UI.
- [ ] Persist preferred subtitle language.
- [ ] Add fallback behaviour when subtitles fail to load.
- [ ] Defer: subtitle timing offset controls (v1.5+).

### Notes
Embedded subtitles are AVKit's responsibility and require minimal work. Sidecar `.srt` ingestion is in v1 only via drag-and-drop; programmatic fetching from subtitle services is v1.5+.

## 4. Watch State and Local Library

### Goal
Track what the user has watched and where they left off. Engine-side this is partly handled by `playback_history` in spec 05; this section adds the user-facing surface.

### Required features
- Watched / unwatched status.
- Resume position tracking (engine: byte-accurate per spec 05; UX: presented as time-accurate via AVPlayer's time observer).
- Continue-watching list.
- Favourites / saved titles.
- Episode progress.
- Local playback history view.

### Optional but valuable
- Collections / custom lists (defer to v1.5+).
- Manual mark-as-watched controls (v1).
- Remove from continue-watching (v1).
- Hide watched items in some views (v1).

### Outstanding work
- [ ] Extend `playback_history` schema for v1.1 watched-seconds reporting (anchored in spec 03 exclusion list).
- [ ] Build watched-state transitions (in-progress → watched → re-watching).
- [ ] Implement continue-watching row generation from local state.
- [ ] Add favourites/save feature with new `favourites` table.
- [ ] Add manual mark-watched/unwatched actions.
- [ ] Define conflict rules between local and synced state (depends on Module 5).
- [ ] Add clear-history and reset-state tools (depends on Module 7).

## 5. Account Sync

### Goal
Sync watch state, lists, and preferences across devices and sessions. v1 target service: Trakt. Open question whether to add Simkl in v1 or defer.

### Required features
- External account login (OAuth flow).
- Sync watched history.
- Sync playback progress (subject to Trakt/Simkl rate limits).
- Sync watchlist / saved list.
- Sync ratings or equivalent user actions.
- Re-sync on login or token refresh.

### Optional but valuable
- Background sync (v1).
- Conflict resolution UI (v1.5+).
- Multi-account support (v2).
- Manual "sync now" button (v1).

### Outstanding work
- [ ] Define account abstraction layer (`AccountProvider` protocol).
- [ ] Implement OAuth flow with `ASWebAuthenticationSession`.
- [ ] Store tokens securely in Keychain.
- [ ] Implement initial library/state sync.
- [ ] Implement incremental sync.
- [ ] Build sync status UI (per `06-brand.md` voice — calm, factual).
- [ ] Build re-auth flow for expired credentials.
- [ ] Design conflict-resolution strategy (last-write-wins for v1; UI for v1.5+).
- [ ] Add manual force-sync command.

### Notes
Without sync, the app feels disposable. Trakt is the dominant choice in this product category and has good API documentation and rate limits.

## 6. Provider Abstraction and Source Resolution

### Goal
Separate the user-facing media experience from the underlying source/provider integrations. This is the architectural heart of the product surface and where engine and product layers meet.

### Required features
- Provider abstraction layer (`MediaProvider` protocol).
- Provider account management (per-provider auth).
- Search across configured providers.
- Source list retrieval per title/episode.
- Source ranking / prioritisation.
- Source health/error states.
- Provider enable / disable controls.

### Optional but valuable
- Multiple provider aggregation (v1).
- Deduplication of equivalent sources (v1).
- Quality ranking (v1 — basic; v1.5 — sophisticated).
- Latency / reliability scoring (v1.5+).
- Provider diagnostics page (v1).

### Outstanding work
- [ ] Define `MediaProvider` interface contract.
- [ ] Define source result schema (`SourceCandidate`).
- [ ] Build provider configuration UI.
- [ ] Implement provider auth model (per-provider; some need API keys, some OAuth, some no auth).
- [ ] Implement source search pipeline (parallel queries, timeout-bounded).
- [ ] Implement source ranking strategy (initial: quality > seeders > size; refinable).
- [ ] Handle empty-source and degraded-source states gracefully.
- [ ] Add retry logic and timeout rules.
- [ ] Add provider diagnostics logging.
- [ ] Add provider priority ordering UI (drag-to-reorder).

### Engine integration
A torrent provider implementation calls into the engine's `addMagnet` / `openStream` XPC methods (spec 03). Non-torrent providers (HTTP streams) are a v1.5+ extension; v1 targets torrent-only providers. The `MediaProvider` interface must be designed so non-torrent providers can be added without breaking changes.

### Notes
This is the real architectural heart of the product. It will consume disproportionate engineering time relative to its visible UI footprint. Spec it carefully before building concrete providers.

## 7. Settings, Recovery, and Diagnostics

### Goal
User control and recovery from failure. For this class of app, auth failures, sync failures, cache corruption, and stale state are routine — the support surface is not optional.

### Required features
- Settings page.
- Account management (Trakt/sync accounts).
- Provider management.
- Subtitle preferences.
- Playback preferences.
- Cache clearing.
- Re-authentication flows.
- Diagnostic logging.

### Optional but valuable
- Export logs (v1).
- Advanced debug mode (v1.5+).
- Health checks (v1).
- Reset app state ("repair" command) (v1).
- Beta/experimental flags (v1.5+).

### Outstanding work
- [ ] Design settings information architecture (sidebar with sections).
- [ ] Implement account management view.
- [ ] Implement provider management view.
- [ ] Implement cache/database reset actions (with confirmation — uses `06-brand.md` voice).
- [ ] Implement secure log capture (no tokens, no magnet links in logs).
- [ ] Add user-visible error reporting.
- [ ] Add debug mode / diagnostics screen.
- [ ] Add "repair app state" recovery flow.

### Notes
Operational support is not secondary. A user who hits a sync error and can't resolve it within the app will uninstall.

## 8. Native macOS Experience

### Goal
Feel properly designed for macOS rather than cross-platform. This is a differentiator for a macOS-only product and should be visible from the first launch, not bolted on at the end.

### Required features
- Native windowing and toolbar behaviour.
- Keyboard shortcuts.
- Spotlight-like quick search feel.
- Proper fullscreen behaviour.
- System appearance support (light/dark, per `06-brand.md` palette).
- Menu bar integration where appropriate.

### Optional but valuable
- Picture-in-picture (v1.5+).
- Handoff / deep links (v2).
- Notification support (v1.5+).
- Touch Bar fallback (skip — declining hardware).
- Drag-and-drop subtitle loading (v1 — already in Module 3).

### Outstanding work
- [ ] Define macOS UI principles for the app (per `06-brand.md`).
- [ ] Implement native menu commands (File, Edit, View, Playback, Library, Account, Window, Help).
- [ ] Add keyboard navigation across browse screens.
- [ ] Add dark/light appearance support per brand palette.
- [ ] Improve focus behaviour for keyboard use.
- [ ] Add drag-and-drop support for subtitle files (Module 3 dependency).
- [ ] Decide whether a menu bar companion mode is useful (open question).

## Non-goals for v1

These features are useful but should not block v1:

- Social features.
- Chat or co-watching.
- Recommendation ML.
- User profiles / multi-user households.
- Downloads and full offline library sync.
- Casting to every external device type.
- Advanced analytics dashboards.
- Plugin marketplace.
- Custom skins/themes (the brand spec is the only visual identity).

## Priority order

### P0 (must work for v1)
- Discovery (Module 1).
- Playback UX (Module 2) on top of the engine in specs 04–05.
- Subtitles (Module 3).
- Local progress state (Module 4).

### P1 (must work for credible v1)
- Account sync (Module 5).
- Provider abstraction (Module 6).
- Settings and diagnostics (Module 7).
- macOS-native polish (Module 8).

### P2 (post-v1)
- External player support.
- AirPlay / casting.
- Richer filtering.
- Advanced quality ranking.
- Recommendations.

## Main risks

1. **Source-resolution complexity** (Module 6). Likely much harder than its UI suggests. Spec the interface before building any concrete provider.
2. **State inconsistency.** Watch state, resume position, and synced account state can drift. Conflict rules need explicit definition.
3. **Authentication fragility.** External account and provider auth needs robust token handling and re-auth flows.
4. **Cache invalidation.** Browse data, metadata, and provider results can become stale. TTL strategy needed per data type.
5. **Playback edge cases.** Subtitle timing, next-episode transitions, and failure recovery need careful handling. Already partially addressed by the planner work in spec 04.

## Definition of a credible v1

A v1 is credible if a user can:

1. Open the app.
2. Browse or search titles.
3. Open a title page.
4. Select a film or episode.
5. Play it reliably (engine work in specs 04–05).
6. Load subtitles.
7. Stop and later resume (via spec 05 cache + Module 4).
8. See progress reflected in continue-watching (Module 4).
9. Optionally sync that state to an external account (Module 5).
10. Recover easily from common failures (Module 7).

If those flows are robust, the product envelope is essentially covered.

## Open questions

These are blocking decisions for issue creation. Raise as discussion threads on GitHub before opening implementation issues.

- [x] ~~Which metadata source should be primary? Candidates: TMDB (free, requires key), TVDB (paid for some tiers), Trakt (decent metadata, primarily a sync service).~~ **Resolved 2026-04-16:** TMDB primary for metadata + artwork; Trakt reserved for Module 5 (Account Sync). Decision recorded in [`docs/spike-metadata-sources.md`](../../docs/spike-metadata-sources.md) and [`docs/design/discovery-metadata-foundation.md § D1`](../../docs/design/discovery-metadata-foundation.md).
- [ ] Should external-player handoff be in v1 or deferred to v1.5+? (Recommendation: defer.)
- [ ] Should sync (Module 5) be optional in v1 or required for onboarding? (Recommendation: optional, with clear "skip" path.)
- [ ] How much provider logic is built in vs plugin-based? (Recommendation: built-in for v1; plugin architecture is v2.)
- [ ] Is AirPlay a v1 expectation for a macOS-only audience? (Recommendation: no, defer.)
- [ ] How much offline/download behaviour is in scope? (Recommendation: none in v1; "keep" pinning per spec 05 is the closest equivalent.)
- [ ] What diagnostic tooling is exposed to users vs internal only? (Recommendation: log export visible; raw debug mode hidden behind a defaults-write flag.)

## Test obligations

Per-module test obligations belong with each module's GitHub issues. The high-level acceptance test for v1 is the "Definition of a credible v1" walkthrough above — performed manually as a release gate before any v1 tag is cut.
