# Subtitle foundation — design (Phase 2)

> **Scope:** the foundation ticket for Epic #4 (#27). Defines `SubtitleTrack`,
> the sidecar-parsing pipeline, the resolution rule that picks a default
> track, the fallback behaviour, and the test shape every Phase 2 ticket
> consumes.
>
> **Status:** Opus design pass, 2026-04-16. Approved before implementation.

## Why a design doc

Phase 2's foundation ticket sits between three surfaces:

1. **AVKit's media-selection model** (`AVPlayerItem`, `.legible` selection group).
2. **The brand-compliant player HUD** (`06-brand.md`, `App/Features/Player`).
3. **Ad-hoc sidecar SRTs the user drags onto the window** — no existing
   plumbing for these in the app.

There are no frozen numbered specs to honour for this phase (spec 07 § 3
gives the user-facing goals and defers the mechanism). The risk in Phase 2
is not contradicting a spec — it is silently picking an AVFoundation
composition path that locks us into brittle code. This doc records the
decisions up front so #28, #29, #30, #32 can implement against a stable
target.

## Decisions

### D1 — Sidecar rendering is app-side, not AVFoundation composition

`AVMutableComposition` + `AVAssetResourceLoaderDelegate` can inject a
sidecar text track into the asset so AVKit renders it natively. It is also
fragile: timing-mode quirks on WebVTT, encoding-specific failures on SRT,
and an opaque failure surface when the composition can't be mutated after
`replaceCurrentItem(with:)`.

**Decision:** we do **not** wire sidecars into the asset. Instead:

- Parse SRT → `[SubtitleCue]` once, at ingestion.
- A SwiftUI `SubtitleOverlay` view above the player renders the currently
  active cue, bound to an `AVPlayer` periodic time observer.
- Embedded tracks remain AVKit's responsibility, toggled via
  `setSelectedMediaOption(_:in:)` on the legible group.

Trade-off: the overlay won't pick up AirPlay / PiP subtitle surfaces (v1.5+
problem — spec 07 § 3 already defers the "optional but valuable" list).
Gain: the SRT path has no asset composition, no resource-loader delegate,
no runtime coupling to the container format.

**Rejected alternative**: build a `AVAssetResourceLoaderDelegate` that
fakes a WebVTT manifest wrapping the SRT. Shipping-blocker risk; worth
neither the LOC nor the edge-case surface for v1.

### D2 — Scope is SRT sidecar plus AVKit-surfaced embedded, nothing else

Supported in v1:

- **Sidecar:** `.srt` only, UTF-8 / ISO-8859-1 / Windows-1252 text encoding.
- **Embedded:** every track AVKit exposes via the `.legible` selection
  group — in practice WebVTT, MOV text (tx3g), and closed captions. We do
  not distinguish these in the UI; the model presents them uniformly.

Everything else surfaces via the fallback banner (D9):

- Sidecar `.vtt`, `.ass`, `.ssa`, `.sub/.idx`, PGS → `.unsupportedFormat`.
- Image-based subtitles inside the asset that AVKit can't render → that's
  AVKit's problem, not ours.

**Rejected alternative**: support sidecar WebVTT in v1 because SRT-to-WebVTT
is a small delta. Rejected on YAGNI: the user base wanting WebVTT sidecars
is vanishingly small versus SRT. If pressure emerges, WebVTT is a second
parser on the same contract — additive, not a rewrite.

### D3 — `SubtitleTrack` is one type with two source cases

```swift
public struct SubtitleTrack: Equatable, Identifiable, Sendable {
    public let id: String             // stable within a playback session
    public let source: SubtitleSource
    public let language: String?      // BCP-47 (e.g. "en", "pt-BR"), nil if unknown
    public let label: String          // human-readable, UI-ready
    public let cues: [SubtitleCue]?   // non-nil for .sidecar, nil for .embedded
}

public enum SubtitleSource: Equatable, Sendable {
    case embedded(identifier: String)                 // opaque handle
    case sidecar(url: URL, format: SubtitleFormat)
}
```

The UI (`SubtitleSelectionMenu`, #29) and the resolver
(`LanguagePreferenceResolver`, this ticket) range over `[SubtitleTrack]`
without caring which case they're looking at. The app layer maps
`.embedded(identifier:)` back to a concrete `AVMediaSelectionOption` via
`AVMediaSelectionGroup.options` lookup at selection time.

**Why not two separate types** (`EmbeddedSubtitleTrack`, `SidecarSubtitleTrack`)?
Every consumer would immediately switch on which one it has. A single
union type makes the "pick one" semantics explicit.

### D4 — #72 folds into #28; close as duplicate

The epic explicitly asked Opus to decide. Product analysis:

- "Drop on the player window" (#28) — the player is currently playing a
  specific title. Binding the sidecar to that title is unambiguous.
- "Drop anywhere in the app" (#72) — where? The library grid holds a
  multi-title selection. The sidebar has no media context. Drop-on-row
  requires picking the right file inside a multi-file torrent, which the
  library grid doesn't surface. No coherent target.

**Decision:** close #72 as a duplicate of #28. If product later wants a
"batch import of sidecars into a titled folder" affordance, that is a new
feature, not this one.

### D5 — Sidecars are session-scoped in v1

Persisting `(torrentID, fileIndex) → sidecarURL` requires engine-side state
(a new table, a new XPC surface, a new event, a consent question about
absolute-path portability when the user's drive changes). None of that is
in Phase 2's scope. User drops an SRT, it's active for the rest of that
window session; on next open, they drop it again.

Known v1 limitation — surfaced in the first-run nudge copy (tracked in
Phase 3's HUD design for #24, not here). If users complain, the v1.5
remedy is a tiny `sidecar_subtitles` table keyed on the stable file hash,
not the torrent ID.

### D6 — Preferred language lives in `UserDefaults`, not the engine `settings` table

`.claude/specs/05-cache-policy.md` (via A7) defines a `settings` table on
the engine side, and the v1-roadmap Phase 2 bullet currently says #30
"writes to `settings` table". That wording is a hint from the issue body,
not a frozen contract.

**Decision:** the preference lives in the app's `UserDefaults` under the
key `"subtitles.preferredLanguage"`. Values are a BCP-47 string
(`"en"`, `"pt-BR"`), the sentinel `"off"`, or absent (no preference set
yet).

Rationale:

- No engine read path needs the value — subtitle resolution happens
  entirely app-side after stream open.
- No cross-process lifetime concern — the preference is a pure UI state.
- Adding an engine XPC round-trip for this single scalar would bloat
  spec 03 for zero functional gain.
- If Epic #6 (sync, p1) later wants to sync this preference across
  devices, the sync adapter reads `UserDefaults` at startup and writes
  back — a common pattern, not a blocker.

**Roadmap revision (this PR):** `docs/v1-roadmap.md` Phase 2 bullet rewords
#30 to "persist preferred language in `UserDefaults`".

**Rejected alternative**: `settings` table. Extra XPC surface, extra
migration, same functional outcome.

### D7 — `Packages/SubtitleDomain` owns the deterministic logic

Mirrors Phase 1's `Packages/LibraryDomain` split. Pure Swift, testable
without AVKit, no UIKit/AppKit imports:

- `SubtitleTrack`, `SubtitleSource`, `SubtitleFormat`, `SubtitleCue`,
  `SubtitleLoadError`.
- `SRTParser` (pure function, `String → Result<[SubtitleCue], SubtitleLoadError>`).
- `SubtitleTextDecoder` (pure function, `Data → Result<String, SubtitleLoadError>`).
- `LanguagePreferenceResolver` (pure function,
  `([SubtitleTrack], String?) → SubtitleTrack?`).

The SwiftUI and AVKit-adjacent pieces stay in the app target under
`App/Features/Subtitles/`:

- `SubtitleController` — observable, owns `tracks`, `selection`, error channel.
- `SubtitleIngestor` — NSItemProvider → `SubtitleTrack.sidecar`.
- `SubtitleOverlay` — SwiftUI cue-renderer synced to `AVPlayer`.
- `SubtitleSelectionMenu` — SwiftUI HUD menu (#29).
- `SubtitleErrorBanner` — HUD banner (#32).
- `SubtitlePreferenceStore` — thin `UserDefaults` wrapper (#30).

The package is a dependency of the app target. Neither the engine service
nor any other package depends on it.

### D8 — Selection resolution is a pure function at stream open

`LanguagePreferenceResolver.pick(from: tracks, preferred: pref)`:

1. If `pref == nil` → return `nil`. No preference means the user hasn't
   chosen; don't auto-enable.
2. If `pref == "off"` → return `nil`. User has explicitly chosen off;
   respect it.
3. Partition `tracks` into embedded-first order (already the natural order
   from `tracks`).
4. For each track, compare `track.language` to `pref` via BCP-47 prefix
   matching (case-insensitive primary-tag match: `"en"` matches `"en-US"`,
   `"pt"` matches `"pt-BR"`).
5. Return the first match. Embedded hits come before sidecar hits only
   because embedded tracks are listed first — there is no explicit tier
   preference, just order preservation.
6. No match → `nil`.

Manual selection via #29 overrides the resolver for the session and
writes `pref` back to the store (#30) — including `.off`, which persists
as `"off"`.

### D9 — Fallback is a HUD banner, one at a time

Trigger paths and resulting behaviour — consumed by #32:

| Trigger                                              | Was the failing track active? | Behaviour                                                      |
| ---------------------------------------------------- | ----------------------------- | -------------------------------------------------------------- |
| SRT parse / decoder failure on drop (#28)            | no (not yet selected)         | Banner. Active selection unchanged. Track not added.           |
| SRT file unreadable on drop (#28)                    | no                            | Banner. Active selection unchanged. Track not added.           |
| Unsupported format on drop (`.vtt`, `.ass`, …)       | no                            | Banner. Active selection unchanged. Track not added.           |
| AVKit embedded activation fails on selection (#29)   | was about to be               | Banner. Revert to `.off`. Previous selection is **not** restored. |
| Embedded activation fails during resolver auto-pick  | no                            | Log. No banner. Resolver picks `nil`.                          |
| Sidecar parsing later fails (corrupt mid-playback)   | yes                           | Banner. Revert to `.off`.                                      |

Banner properties:

- Single line, calm voice per `06-brand.md` § Voice ("No exclamation marks
  except in genuine error states" — these are recoverable).
- 6 s auto-dismiss; dismissable.
- One at a time; new error replaces old.
- Rendered in the existing player HUD glass surface.

Copy examples (final wording locked during #32 review):

- `.decoding` → "Couldn't read <filename>. The file may be damaged."
- `.fileUnavailable` → "Couldn't open <filename>."
- `.unsupportedFormat` → "That subtitle format isn't supported."
- `.systemTrackFailed` → "Couldn't enable that subtitle track."

### D10 — No spec rev, no addendum item

Phase 1 bumped spec 05 to rev 5 and added addendum A26 because it changed
engine schema and XPC surface. Phase 2 changes neither. The design doc is
the canonical record; the only ancillary change is the `v1-roadmap.md`
revision block for D6.

If future Opus passes want to surface these decisions at addendum level,
the right path is to introduce a new numbered spec "10 — subtitles" that
pulls from this doc. Not warranted for v1.

## Type sketch

```swift
// Packages/SubtitleDomain — pure Swift, no AppKit/UIKit/AVKit imports
import Foundation
import CoreMedia

public struct SubtitleCue: Equatable, Sendable {
    public let index: Int              // 1-based per SRT; used only for diagnostics
    public let startTime: CMTime
    public let endTime: CMTime
    public let text: String            // plain text; light tag stripping (<i>, <b>) applied by parser
}

public enum SubtitleFormat: String, Equatable, Sendable, CaseIterable {
    case srt
    case webVTT
    case movText
    case closedCaption
}

public enum SubtitleSource: Equatable, Sendable {
    case embedded(identifier: String)
    case sidecar(url: URL, format: SubtitleFormat)
}

public struct SubtitleTrack: Equatable, Identifiable, Sendable {
    public let id: String
    public let source: SubtitleSource
    public let language: String?       // BCP-47
    public let label: String
    public let cues: [SubtitleCue]?    // nil for .embedded, non-nil for .sidecar
}

public enum SubtitleLoadError: Error, Equatable, Sendable {
    case fileUnavailable(reason: String)
    case decoding(reason: String)
    case unsupportedFormat(reason: String)
    case systemTrackFailed(reason: String)
}

public enum SubtitleTextDecoder {
    /// Try UTF-8 first, then ISO-8859-1, then Windows-1252.
    /// Binary data (failing all three) surfaces as `.decoding`.
    public static func decode(_ data: Data) -> Result<String, SubtitleLoadError>
}

public enum SRTParser {
    /// Parses an SRT string into cues. Recoverable syntax slips (missing
    /// index, blank trailing lines) are absorbed. Unrecoverable shape
    /// (no valid cues at all) surfaces as `.decoding`.
    public static func parse(_ text: String) -> Result<[SubtitleCue], SubtitleLoadError>
}

public enum LanguagePreferenceResolver {
    public static func pick(from tracks: [SubtitleTrack],
                            preferred: String?) -> SubtitleTrack?
}
```

## Resolution matrix

| `preferred`    | match in tracks?      | result                                             |
| -------------- | --------------------- | -------------------------------------------------- |
| `nil`          | —                     | `nil` (user hasn't chosen; don't auto-enable)      |
| `"off"`        | —                     | `nil` (user explicitly off; respect it)            |
| `"en"`         | track with `"en"`     | that track                                         |
| `"en"`         | track with `"en-US"`  | that track (primary-tag prefix match)              |
| `"pt-BR"`      | track with `"pt"`     | that track (reverse prefix also matches)           |
| `"pt-BR"`      | track with `"pt-PT"`  | that track (shared primary tag)                    |
| `"en"`         | no match              | `nil`                                              |
| any            | embedded and sidecar both match | first in natural order (embedded listed first) |

BCP-47 comparison is case-insensitive on the primary tag. Region/subtag
differences do not prevent a match in v1; this is deliberately permissive
because user-supplied sidecars rarely carry precise region tags.

## Ingestion pipeline

Consumed by #28. One function per stage; each stage is a pure function
except `SubtitleIngestor` which performs the disk read.

```
NSItemProvider
   └─▶ resolveFileURL (reject non-.srt extension)
         └─▶ readData (may fail → .fileUnavailable)
               └─▶ SubtitleTextDecoder.decode (may fail → .decoding)
                     └─▶ SRTParser.parse (may fail → .decoding)
                           └─▶ sniffLanguage(from: filename) → language?
                                 └─▶ SubtitleTrack.sidecar(...)
```

Filename language sniffing: match the rightmost dot-separated token
immediately before `.srt` against `^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$`.
Match → that's the language tag. No match → `language = nil`.

Examples:
- `Movie.en.srt` → `"en"`.
- `Movie.pt-BR.srt` → `"pt-BR"`.
- `Movie.srt` → `nil`.
- `Movie.English.srt` → `"English"` (passes the regex; resolver will fail
  to match against BCP-47 preferences but that's correct — it's what the
  file says).

## Test shape

Foundation ticket (#27) lands the following test groups. Other Phase 2
tickets reuse the harnesses.

### `Packages/SubtitleDomain/Tests`

- `SRTParserTests`:
  - Single cue, multi-cue, CRLF line endings, UTF-8 BOM, HTML entities
    (`<i>`, `<b>`, `&amp;`), missing index (recoverable),
    bad timecode (`.decoding`), empty input (empty array), overlapping
    cues preserved in order, gaps preserved, trailing whitespace tolerated.
- `SubtitleTextDecoderTests`:
  - UTF-8, UTF-8 with BOM, ISO-8859-1, Windows-1252, binary (rejected).
- `LanguagePreferenceResolverTests`:
  - One case per row of the resolution matrix above.
- `SubtitleCueTests`:
  - CMTime ordering, Equatable, Sendable.

### App-side tests (land with the dependent tickets, not this PR)

- `SubtitleIngestorTests` (#28) — file validation, encoding fallback,
  filename language sniffing.
- `SubtitleControllerTests` (#29) — selection transitions, AVKit failure
  handling per D9.
- `SubtitlePreferenceStoreTests` (#30) — UserDefaults round-trips.
- `SubtitleErrorBannerSnapshotTests` (#32) — light/dark per error variant.
- `SubtitleSelectionMenuSnapshotTests` (#29) — light/dark per track
  combination.

## Engine and XPC impact

**None.** No new DTO, no new method, no new event, no schema migration.
Phase 2 is pure app-side. This is intentional (D1, D5, D6).

## Out of scope for the foundation

- Sidecar ingestion wiring (#28).
- Selection UI (#29).
- Preference persistence (#30).
- Fallback banner UI and copy locking (#32).
- Any AVKit runtime coupling (the package ships the `.embedded(identifier:)`
  handle; the app layer maps to `AVMediaSelectionOption` when wiring
  lands in #29).
- Sidecar persistence across sessions (explicit v1 limitation per D5).
- WebVTT / ASS / SSA / image-based sidecar parsing (deferred per D2).
- Subtitle offset, styling, forced subtitles (spec 07 § 3 "Optional but
  valuable" — v1.5+).

## Risks and mitigations

| Risk                                                            | Mitigation                                                                                                     |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| SwiftUI overlay cue-timing drifts versus `AVPlayer`             | Bind to `periodicTimeObserver` at 30 Hz minimum; cue lookup is O(log n) via binary search on sorted start times |
| SRT files in unknown encoding survive the fallback chain        | Document the UTF-8 → ISO-8859-1 → Windows-1252 chain; garbled text is a user-visible cue, not a silent corruption |
| User expects drag-on-library-grid behaviour                     | First-run nudge in Phase 3 HUD design (#24) explicitly says "drop subtitles on the video"; no other target exists |
| Embedded AVKit track fails silently during resolver auto-pick   | Auto-pick failures log but don't banner (D9); banners are reserved for user-initiated selections               |
| Persisted preference becomes stale if a user switches language  | Any manual selection writes the preference — the stored value always matches the last explicit choice          |
| `UserDefaults` is unsynced across devices                       | Deliberate — sync is Epic #6 (p1). The p1 adapter reads `UserDefaults` at startup                              |
| Sidecar overlay invisible on AirPlay / PiP                      | Acknowledged v1.5+ limitation per D1; spec 07 § 3 "Optional but valuable" already lists external-surface work as deferred |
