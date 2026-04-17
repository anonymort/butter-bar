# Codex Prompt — Finish ButterBar v1 p0

> **Purpose:** Hand this prompt to Codex (or any coding agent) to close the
> remaining 4 p0 issues and 3 follow-ups that constitute a credible v1.
>
> **Generated:** 2026-04-17 from a verified clean main at `f427cc3`.

---

## Context

ButterBar is a native macOS (Tahoe 26+) media player built in SwiftUI with an
XPC-separated engine process. It streams from torrent sources, uses AVKit for
playback, and has a warm "craft app" brand identity.

The codebase is substantially complete. Four p0 GitHub issues remain open, plus
three small follow-ups. Once these land, both remaining p0 epics (#2 Discovery,
#3 Playback UX) can close and the app hits the "credible v1" bar defined in
`docs/v1-roadmap.md`.

**Repo:** `github.com/anonymort/butter-bar` — branch: `main`

## Read these files first (in order)

1. `CLAUDE.md` — project conventions, frozen decisions, layout
2. `.claude/specs/06-brand.md` — visual identity, colour tokens, voice, typography, motion, test obligations
3. `.claude/specs/07-product-surface.md` — what "credible v1" means
4. `docs/v1-roadmap.md` — phase structure, status blocks, dependency graph
5. `App/Brand/BrandColors.swift` — all colour tokens (use ONLY these, never raw colours)
6. `App/Brand/BrandTypography.swift` — typography modifiers

## The 7 work items (do them in this order)

## Completion status — 2026-04-17

- [x] Issue #25 — Keyboard shortcuts: wired in `PlayerView` and covered by `KeyboardShortcutTests`.
- [x] Issue #14 — Search: TMDB-backed search view/model integrated into `ContentView`, with debounce/cancellation tests.
- [x] Issue #16 — Season/episode selector: selector view/model wired from title detail, with lazy season loading and watch-state tests.
- [x] Issue #22 — Subtitle track picker: new picker sheet wired from player chrome, while retaining the legacy menu surface for existing snapshots.
- [x] Follow-up #21 — NextEpisodeCoordinator host-wire: `PlayerViewModel` resolves and opens the next episode through injected/library resolvers.
- [x] Follow-up #15 — Metadata cast/credits: `Movie` and `Show` now carry real decoded TMDB cast data.
- [x] Follow-up #29 — SubtitleController selection-nil fix: embedded activation failure clears selection and surfaces `systemTrackFailed`.

Verification performed from `/tmp/ButterBar-codex-v1-build` to avoid iCloud-backed
workspace placeholder stalls:

- [x] `swift test --package-path Packages/MetadataDomain`
- [x] `xcodebuild build -scheme ButterBar -destination 'generic/platform=macOS' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -quiet`
- [x] `xcodebuild test -scheme ButterBar -destination 'platform=macOS,arch=arm64' ARCHS=arm64 ONLY_ACTIVE_ARCH=YES -quiet`

Note: the unconstrained generic macOS build attempted an x86_64 EngineService
link, but the installed Homebrew `libtorrent-rasterbar`, `libssl`, and
`libcrypto` dylibs are arm64-only in this environment. The arm64 build/test path
matches the available local dependency architecture and passed.

### 1. Issue #25 — Keyboard shortcuts (smallest, no dependencies)

**Branch:** `feature/keyboard-shortcuts-25`
**PR closes:** `#25`

Add basic keyboard shortcuts to `PlayerView`:
- **Space** → toggle play/pause
- **Left arrow** → seek back 10s
- **Right arrow** → seek forward 10s
- **F** → toggle fullscreen
- **Escape** → exit fullscreen (if fullscreen) or close player

**Implementation notes:**
- Use `.onKeyPress` (macOS 14+) or `.keyboardShortcut` on the PlayerView body.
  Since the target is macOS 26, `.onKeyPress` is available.
- Route through existing `viewModel.play()`, `viewModel.pause()`,
  `viewModel.seek(toSeconds:)`, and `toggleFullscreen()` methods already on
  `PlayerView`.
- Only respond when `PlayerState` is `.playing`, `.paused`, or `.buffering(_)`.
  Ignore keypresses in `.closed`, `.open`, `.error(_)`.

**Tests:**
- `KeyboardShortcutTests` — unit tests that simulate key events and assert the
  correct VM method was called. Can be lightweight; this is simple wiring.
- No snapshots needed (no new UI surface).

**AC from spec 07:** "Space bar play/pause. Arrow-key scrub. F for fullscreen."

---

### 2. Issue #14 — Search (TMDB-backed discovery search)

**Branch:** `feature/search-14`
**PR closes:** `#14`

Build the discovery search surface. Full acceptance criteria are on the issue body
(pasted below for convenience). Key points:

**Architecture:**
- New files: `App/Features/Discovery/SearchView.swift`, `SearchViewModel.swift`
- `SearchViewModel` owns a `MetadataProvider` ref (injected), debounce logic
  (250ms), and pagination state.
- The debounce must cancel in-flight `searchMulti` calls on each new keystroke.
  Use `Task` cancellation — no Combine needed.
- Results are `[MediaItem]` from `MetadataProvider.searchMulti(query:)` (already
  exists on the protocol and `TMDBProvider`).

**UI integration:**
- Add a `.searchable(text:)` modifier to `ContentView`'s NavigationSplitView,
  OR add a `DiscoveryDestination.search` case to the sidebar. Propose whichever
  feels more native to macOS — `.searchable` is probably better for Tahoe.
- Result rows: poster thumbnail (w154), title, year, type badge (Movie/Show),
  truncated overview.
- Tap → navigate to `TitleDetailView` (already exists via #15). Wire through the
  existing `NavigationSplitView` detail or sheet pattern already in `ContentView`.
- Empty query → no results shown (no trending fallback).
- No-results: calm one-liner per brand voice ("Nothing matched 'xyz'").
- Error: "We can't reach the catalogue right now" — no raw error codes.
- Loading: calm shimmer (use the existing shimmer pattern from `TitleDetailLoadingView`).

**Tests (required):**
- `SearchViewModelTests`: debounce (inject `Clock`), cancellation, pagination,
  empty-query, error propagation. Use `FakeMetadataProvider`.
- Snapshot tests: empty, no-results, populated, error, loading. Light + dark.
  Follow `AudioPickerSnapshotTests` pattern (ImageRenderer, `assertSnapshot`).

**Brand rules:**
- All colours via `BrandColors.*`. No `Color.black`, no system tints.
- Typography via `BrandTypography` modifiers (`.brandBody()`, `.brandCaption()`, etc.).

---

### 3. Issue #16 — Season/episode selector

**Branch:** `feature/season-episode-selector-16`
**PR closes:** `#16`

Full acceptance criteria are on the issue body. Key points:

**Architecture:**
- New files: `App/Features/Discovery/SeasonEpisodeSelectorView.swift`,
  `SeasonEpisodeSelectorViewModel.swift`
- Entry point: `TitleDetailView.onBrowseSeasons` callback (already a `(Show) -> Void`
  closure on `TitleDetailView`, currently defaulting to no-op). Wire this to push
  the selector.
- Season picker: segmented control or picker across the top. Default to most
  recent season with episodes.
- Episode list: vertical list. Each row = episode number (monospaced numerals),
  title, still image (w300), overview, runtime.
- Watch-state badges from `EngineClient.listPlaybackHistory()` + `playbackHistoryChanged`
  subscription. Match episodes to local files via `TitleNameParser` + `MatchRanker`
  (both exist in `MetadataDomain`).
- Lazy season-detail fetch: `MetadataProvider.seasonDetail(showID:, season:)` on
  first season selection per session.
- Per-row "Find a torrent" → placeholder modal (Module 6 not in scope).

**Tests (required):**
- `SeasonEpisodeSelectorViewModelTests`: season selection, lazy fetch, watch-state
  badge derivation, subscription update.
- Snapshots: multiple seasons, mixed watch states, specials, loading, error.
  Light + dark.

---

### 4. Issue #22 — Subtitle track picker in player chrome

**Branch:** `feature/subtitle-picker-22`
**PR closes:** `#22`

Full acceptance criteria are on the issue body. Key points:

**What already exists (DO NOT rebuild):**
- `SubtitleController` (`App/Features/Subtitles/SubtitleController.swift`) — owns
  `tracks: [SubtitleTrack]`, `selection: SubtitleTrack?`, `selectTrack(_:)`.
- `SubtitleSelectionMenu` (`App/Features/Subtitles/SubtitleSelectionMenu.swift`) —
  a basic `Menu`-based picker already wired into `PlayerView`. This is from the
  Phase 2 rebuild and does the job for basic selection.
- `SubtitlePreferenceStore` — persists preferred language in UserDefaults.

**What this ticket adds:**
- Upgrade the `SubtitleSelectionMenu` into a proper picker overlay matching the
  `AudioPickerView` pattern (sheet/popover, not a `Menu`). Use the same visual
  structure: header with close button, track list with checkmarks, grouped by
  source (Embedded / Sidecar), "Off" entry at top.
- Each row: language label (BCP-47 → human name via `Locale(identifier:).localizedString(forLanguageCode:)`),
  source indicator (Embedded / Sidecar), checkmark for active selection.
- Wire into `PlayerOverlay.onOpenSubtitlePicker` (the hook already exists but
  defaults to `{}`). Mirror the `showingAudioPicker` pattern in `PlayerView`.
- Disable when `PlayerState` is `.closed` or `.error(_)`.
- Selecting a track calls `controller.selectTrack(_:)` which handles AVKit
  application and preference persistence.
- Empty state: "No subtitles available" — calm one-liner.

**Tests:**
- `SubtitlePickerViewModelTests` (or extend existing `SubtitleControllerTests`):
  list composition, selection, preference persistence.
- Snapshots: empty, single-track, multi-track, dark + light. Follow the exact
  `AudioPickerSnapshotTests` pattern.

---

### 5. Follow-up: NextEpisodeCoordinator host-wire

**Branch:** `feature/next-episode-wire`
**PR refs:** `Refs #21`

`NextEpisodeCoordinator` (from PR #175) is unit-tested but not wired into
`PlayerView`. It needs an `Episode → (torrentID, fileIndex)` resolver.

**Implementation:**
- Add a resolver closure to `PlayerViewModel`: something like
  `var resolveNextEpisode: (Episode) async -> (torrentID: String, fileIndex: Int32)?`
- When `NextEpisodeCoordinator` fires its "play next" signal, the VM calls the
  resolver, then opens a new stream via `EngineClient.openStream(...)`.
- For v1, the resolver can use `TitleNameParser` + `MatchRanker` from
  `MetadataDomain` to find a matching library file. If no match, show a calm
  "Next episode not in library" message and don't auto-play.
- Wire the `UpNextOverlay` dismiss into `PlayerView` (it exists but may not
  be connected to the coordinator's actual stream-open path).

**Tests:**
- Extend `NextEpisodeCoordinatorTests` with a wiring test using a fake resolver.

---

### 6. Follow-up: MetadataProvider cast/credits

**Branch:** `feature/metadata-cast-credits`
**PR refs:** `Refs #15`

`TitleDetailView` has a `CastChipRow` wired via injected fixtures. Make it real.

**Implementation:**
- TMDB movie detail and show detail responses include `credits.cast`. The
  `TMDBProvider` already fetches detail — extend the response model to decode
  `credits.cast` into a `[CastMember]` struct (name, character, profilePath).
- Add `cast: [CastMember]` to `Movie` and `Show` in `MetadataDomain`.
- `TitleDetailViewModel` passes the real cast to the view.
- `FakeMetadataProvider` already returns fixture data — update fixtures to
  include cast members.

**Tests:**
- Unit test: `TMDBProvider` decodes cast from a fixture JSON response.
- Verify `TitleDetailViewModel` exposes cast.

---

### 7. Follow-up: SubtitleController selection-nil fix

**Branch:** `fix/subtitle-selection-nil`
**PR refs:** `Refs #29`

In `SubtitleController.activateTrack`, if AVKit activation fails (the
`select(_:in:)` call doesn't take effect), the controller currently leaves the
prior `selection` intact. Per the design doc § Fallback matrix row 4, it should
set `selection = nil` so the UI reflects the failure.

**Implementation:**
- In `SubtitleController`, after calling `playerItem?.select(option, in: group)`,
  verify the selection took effect. If not, set `selection = nil` and fire
  `activeError = .systemTrackFailed`.
- The verification: re-read `playerItem?.currentMediaSelection.selectedMediaOption(in: group)`
  and compare.

**Tests:**
- Add a test in `SubtitleControllerTests` that stubs a failing selection and
  asserts `selection` becomes `nil` and `activeError` is set.

---

## Global rules for every PR

### Git workflow
- One branch per item, off `main`. Pull `main` before branching.
- PR title: `feat(module): description (#N)` or `fix(module): description`
- PR body: `Closes #N` (or `Refs #N` for follow-ups).
- Commit messages: `<type>: <description>` — first line ≤72 chars.

### Brand compliance (enforced — PRs get bounced for violations)
- **Colours:** `BrandColors.*` only. Never `Color.black`, `Color.white`,
  `.red`, `.green`, `.yellow`, or any system colour.
- **Typography:** `BrandTypography` modifiers only (`.brandBody()`,
  `.brandBodyEmphasis()`, `.brandCaption()`, `.brandTitle()`). No raw `.font()`.
- **Motion:** `.easeInOut` value-tied animations. No springs. Duration ≤0.3s
  for micro-interactions.
- **Voice:** calm, direct, sentence-cased. No exclamation marks, no sad-face
  icons, no "Oops!" copy. Error states are quiet explanations with a Retry
  affordance.
- **Glass:** liquid glass material on toolbar/sidebar/floating chrome only.
  Never on content surfaces, sheets, or list rows.

### Testing (enforced)
- Every new SwiftUI surface gets light + dark snapshot tests following the
  `AudioPickerSnapshotTests` pattern:
  ```swift
  ImageRenderer → cgImage → NSImage → assertSnapshot(of:, as: .image, named:)
  ```
- Unit tests for all view model logic. Use `FakeMetadataProvider`,
  `EngineClient` stubs, injected closures. No live network calls.
- Tests must compile and pass in isolation. No test interdependencies.

### Code patterns to follow
- View models are `@MainActor final class: ObservableObject` with `@Published`
  properties.
- Views take `@ObservedObject var viewModel` (not `@StateObject` — owner
  creates the state object).
- Pure domain types live in `Packages/` (MetadataDomain, SubtitleDomain,
  PlayerDomain, LibraryDomain). App code imports these.
- `EngineClient` is the XPC boundary. Always async. Subscribe to published
  streams for live updates.

### Xcode project
- Add new `.swift` files to the `ButterBar` target in `project.pbxproj`.
- Add new test files to the `ButterBarTests` target.
- Snapshot baselines go under `Tests/ButterBarTests/__Snapshots__/<TestClass>/`.

### What NOT to do
- Don't modify specs (`.claude/specs/*`).
- Don't modify `CLAUDE.md`.
- Don't add dependencies. No SPM packages. No Combine where `async/await` works.
- Don't refactor code you're not changing.
- Don't add features beyond the acceptance criteria.
- Don't use `any` types. Maintain full type safety.
- Don't add comments that restate the code. Only comment non-obvious "why".

## Verification before claiming done

After all 7 items are merged:

```bash
# All p0 issues closed
gh issue list --state open --label "priority:p0"
# Expected: only epics #2 and #3 (close them manually after verification)

# Tests pass
xcodebuild test -scheme ButterBar -destination 'platform=macOS'

# No stale branches
git branch  # should show only main

# Clean working tree
git status  # should be clean
```

## Epic closure criteria

After all PRs merge:
- **Epic #3 (Playback UX):** close if #18, #19, #20, #21, #22, #23, #24, #25, #26
  are all CLOSED. Run: `gh issue close 3 -c "All p0 playback issues closed."`
- **Epic #2 (Discovery):** close if #11, #13, #14, #15, #16, #17 are all CLOSED.
  Run: `gh issue close 2 -c "All p0 discovery issues closed."`

At that point, all four p0 epics (#2, #3, #4, #5) are closed and the app is a
credible v1.
