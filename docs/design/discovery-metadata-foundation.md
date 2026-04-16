# Discovery and metadata foundation — design (Phase 4)

> **Scope:** the foundation ticket for Epic #2 (#11). Defines the canonical
> `MediaItem` schema (Movie / Show / Season / Episode), the new
> `Packages/MetadataDomain` package, the `MetadataProvider` protocol and
> its `TMDBProvider` implementation, the on-disk metadata cache with TTL
> policy, the pure name-parsing and ranking helpers used by every
> downstream "match a torrent file to a TMDB title" flow, and the test
> shape every Phase 4 ticket consumes.
>
> **Status:** Opus design pass, 2026-04-16. Doc-only PR; no
> implementation in this revision. Phase 4 dependent tickets (#13, #14,
> #15, #16, #17) and the Phase 3 tail (#20, #21) land against the
> foundation in subsequent feature PRs.

## Why a design doc

Phase 4's foundation sits between five surfaces:

1. **TMDB API** — the metadata source and image CDN. Spike at
   [`docs/spike-metadata-sources.md`](../spike-metadata-sources.md)
   resolved the source decision on 2026-04-15: TMDB primary, Trakt
   reserved for sync (Module 5, p1).
2. **Phase 1's `LibraryDomain`** — `WatchStatus`, `listPlaybackHistory`.
   #17 (continue-watching) joins these to metadata.
3. **The library file list** — torrent file names like
   `Show.Name.S01E02.1080p.x264-GROUP.mkv`. Matching these to TMDB
   titles is the load-bearing seam between local state and metadata.
4. **Brand voice and chrome** (`06-brand.md`) — Discovery is the
   first surface a user sees; the calm register has to render against
   real data without leaking provider artefacts (raw URLs, error codes,
   placeholder strings).
5. **App Sandbox** — the metadata cache lives in
   `~/Library/Application Support/ButterBar/metadata/` per the
   sandbox container, not in user-visible Documents.

`MediaItem` and the cache layer have to be coherent across all five
without bloating any of them. This doc records the choices so #13, #14,
#15, #16, #17 can implement against a stable target, and so the Phase 3
tail (#20, #21) has the episode-aware schema it has been waiting on.

## Decisions

### D1 — Metadata source: TMDB primary, Trakt deferred to Module 5

Per the spike (2026-04-15):

- **TMDB** for metadata, search, browse rows, artwork. Free tier
  (personal use). API access token embedded in the binary per the
  spike's § 4 decision.
- **Trakt** is **not** a Phase 4 concern. Trakt is the sync source for
  Module 5 (Account Sync, p1). Watch state in Phase 4 reads from Phase
  1's local `playback_history`, not from Trakt.
- TVDB rejected per spike § 3.

**Implication for `#11`:** the `needs-design` label on the issue is
removed. The spike doc + this design doc together resolve the open
question that has been on `.claude/specs/07-product-surface.md § Open
questions` since the spec was written. Spec 07's open-question line is
left as-is in this PR (small doc-hygiene drift; tracked as a separate
follow-up rather than widening this PR's surface).

### D2 — `MediaItem` is a discriminated union over `Movie | Show`

The top-level domain type is:

```swift
public enum MediaItem: Equatable, Sendable, Hashable, Codable {
    case movie(Movie)
    case show(Show)
}
```

Reasons:

- **Single value-typed entry point** for every consumer (browse rows,
  detail page, search results, continue-watching). A consumer can
  pattern-match on the discriminator instead of carrying parallel arrays
  or generic constraints.
- **`Codable` round-trips cleanly** via Swift's automatic synthesis on
  enums with associated values (Swift 5.5+; we're on Swift 6).
- **`Hashable` and `Equatable`** are free, which makes it valid as a
  SwiftUI `id` and as a cache key.

`Show` carries `[Season]`, each `Season` carries `[Episode]`. Episodes
are first-class (carry their own `MediaID`, runtime, still URL,
overview), so #20's end-of-episode detection can identify the exact
episode without re-traversing the show.

### D3 — `MediaID` wraps `(provider, id)` for v1.5 expansion

```swift
public struct MediaID: Equatable, Sendable, Hashable, Codable {
    public let provider: Provider
    public let id: Int64

    public enum Provider: String, Sendable, Codable {
        case tmdb
    }
}
```

Only `.tmdb` is defined in v1. `Provider` exists as an enum (not a raw
string) so that adding `.imdb`, `.tvdb`, or `.fanart` in v1.5 is
type-safe and doesn't require migrating cached data — the provider
field becomes a discriminator that silently invalidates v1 cache
entries that don't carry it (they all do; `.tmdb` is implicit).

Trakt IDs are not represented in `MediaID` because Trakt is not a
metadata source for v1 — when Module 5 lands, it will join via
`MediaID(provider: .tmdb, id:)` per the spike's § 5 cross-reference
strategy.

### D4 — Metadata cache is on-disk JSON, not SQLite

The cache stores TMDB JSON responses keyed by canonical request URL,
with TTL stamps and ETag/Last-Modified support. Files live under
`~/Library/Application Support/ButterBar/metadata/`:

```
metadata/
├── responses/
│   ├── trending-movie-week-{date}.json
│   ├── tv-{tmdbID}.json
│   └── tv-{tmdbID}-season-{n}.json
├── images/                          # See D5
└── cache_meta.json                  # TTL stamps, ETags
```

Reasons:

- **The data is read-mostly and shape-stable.** TMDB responses are
  immutable per request URL until TTL expires. SQL would only earn
  itself if we needed cross-row queries (e.g. "all shows with cast
  member X"); we don't, in v1.
- **No second migration story.** GRDB is already used by the engine for
  `playback_history` etc.; a second GRDB store on the app side
  introduces a parallel migration discipline. Files don't.
- **Easier to invalidate.** Bumping the TMDB schema (rare) is `rm -rf
  ~/Library/Application Support/ButterBar/metadata/responses/`. App
  re-fetches on next access.
- **Easier to debug.** `cat metadata/responses/tv-1668.json` is more
  approachable than a SQLite browser.

**Rejected alternative:** GRDB with `movies`, `shows`, `seasons`,
`episodes` tables. Marked as a v1.5+ option if a future feature needs
cross-entity queries that file scan can't satisfy.

### D5 — Image cache uses `URLCache` with a 500 MB disk budget

Images are fetched from `image.tmdb.org`. We use `URLSession` with a
custom `URLCache` configured against a 500 MB disk store under
`~/Library/Application Support/ButterBar/metadata/images/`. No third-
party image library (`Kingfisher`, `Nuke`) is introduced in v1.

- **Eviction:** LRU; `URLCache` handles it.
- **Sizes:** for posters, fetch `w342` for grid rows, `w500` for detail
  pages; for backdrops `w1280`; for episode stills `w300`. Sizes are
  constants in one file (`TMDBImageSizes.swift`) and not scattered.
- **Retina:** request `2x` size where the layout's logical size warrants
  it (e.g. `w780` for a `w342` slot when on a 2x display). Not
  pixel-perfect, but pragmatic.
- **Failure mode:** image fetch failure shows a brand-tokenized
  placeholder (a soft butter-coloured rounded rect) — never a broken
  image icon, never the URL.

**Rejected alternatives:** `Kingfisher` / `Nuke`. Both are excellent;
neither is needed for v1's surface area. `URLCache` is built-in,
zero-dependency, and good enough.

### D6 — `MetadataProvider` protocol + one v1 impl (`TMDBProvider`)

```swift
public protocol MetadataProvider: Sendable {
    func trending(media: TrendingMedia, window: TrendingWindow) async throws -> [MediaItem]
    func popular(media: TrendingMedia) async throws -> [MediaItem]
    func topRated(media: TrendingMedia) async throws -> [MediaItem]

    func searchMulti(query: String) async throws -> [MediaItem]

    func movieDetail(id: MediaID) async throws -> Movie
    func showDetail(id: MediaID) async throws -> Show
    func seasonDetail(showID: MediaID, season: Int) async throws -> Season

    func recommendations(for id: MediaID) async throws -> [MediaItem]

    func imageURL(path: String, size: TMDBImageSize) -> URL
}
```

Two concrete types in v1:

- **`TMDBProvider`** — production impl. Lives in a new
  `App/Discovery/TMDBProvider.swift` (or a sibling module), depends on
  `MetadataDomain`. Embeds the API access token from a non-checked-in
  source (e.g. `Secrets.swift` generated at build time from a local
  `.env` file, mirroring the engine's pattern).
- **`FakeMetadataProvider`** — test impl. Lives in
  `Packages/MetadataDomain/Tests/Support/`. Returns canned JSON from
  fixtures so every consumer can be tested without a live TMDB call.

A third impl (`StubMetadataProvider` returning fixed data for SwiftUI
previews) is a follow-up — not in scope for #11.

**Rejected alternative:** adopt `adamayoung/TMDb` SPM dependency
directly across the app. Strong package, but coupling the app's domain
types to a third-party model is the kind of decision that costs us
later. The protocol layer keeps `TMDb` (if we adopt it) confined to a
single file at the boundary. **Adopting `TMDb` vs hand-rolling
`URLSession` is recorded as Open Question O1.**

### D7 — TTL table

| Resource                                     | TTL     | Refresh trigger                        |
| -------------------------------------------- | ------- | -------------------------------------- |
| `/trending/{movie,tv}/week`                  | 6 h     | First miss after expiry; stale-while-revalidate on cache hit. |
| `/trending/{movie,tv}/day`                   | 1 h     | Same.                                  |
| `/movie/popular`, `/tv/popular`              | 24 h    | Same.                                  |
| `/movie/top_rated`, `/tv/top_rated`          | 7 d     | Top-rated lists are slow-moving.       |
| `/movie/{id}`, `/tv/{id}` detail             | 7 d     | Plus ETag-driven revalidation.         |
| `/tv/{id}/season/{n}` detail                 | 30 d    | Episode lists are stable post-airing.  |
| `/search/multi?q=…`                          | 0 (no cache) | Search is interactive; freshness wins. |
| `/movie/{id}/recommendations`                | 7 d     |                                        |
| Configuration (`/configuration`)             | 30 d    | Image base URL changes once per year. |
| Image responses (CDN)                        | indefinite | Filenames are content-addressed.    |

All TTLs are constants in one file (`MetadataCacheTTL.swift`) and
tunable. **Stale-while-revalidate** for browse rows: serve the stale
copy immediately, kick off a background fetch, swap in the fresh
result when ready. This keeps the home screen instant even on cold
starts where the network is slow.

### D8 — Pure parsing and ranking (`TitleNameParser`, `MatchRanker`)

The matching seam from "torrent file name" to "TMDB MediaItem" splits
into three layers:

1. **Pure** `TitleNameParser.parse(_ name: String) -> ParsedTitle`.
   Extracts `(title, year?, season?, episode?)` from common release
   formats. Lives in `MetadataDomain`. No I/O, deterministic, fully
   tested over a fixture set of real-world release names.
2. **Network** `MetadataProvider.searchMulti(_:)` → `[MediaItem]`. Lives
   in `TMDBProvider`. The orchestration code (in #17, #15, etc.) feeds
   parser output into search.
3. **Pure** `MatchRanker.rank(parsed: ParsedTitle, candidates:
   [MediaItem]) -> [RankedMatch]`. Scores candidates against parsed
   inputs (title similarity via Jaro-Winkler, year ±1 tolerance,
   episode-shape match for shows). Lives in `MetadataDomain`. Pure,
   deterministic, fully tested.

Layers (1) and (3) ship with #11 because they're foundation-level and
every downstream "match a file" caller needs them. Orchestration glue
(`LibraryMetadataResolver` or similar) lives where it's first needed
(#17 for continue-watching).

```swift
public struct ParsedTitle: Equatable, Sendable {
    public let title: String
    public let year: Int?
    public let season: Int?
    public let episode: Int?
    public let releaseGroup: String?
    public let qualityHints: Set<QualityHint>   // 1080p, x264, BluRay, etc.

    public enum QualityHint: String, Equatable, Sendable, Hashable { … }
}

public enum TitleNameParser {
    public static func parse(_ name: String) -> ParsedTitle
}

public struct RankedMatch: Equatable, Sendable {
    public let item: MediaItem
    public let confidence: Double   // [0, 1]; 1 = perfect match
    public let reasons: [String]    // human-readable, for debug + telemetry
}

public enum MatchRanker {
    public static func rank(parsed: ParsedTitle,
                            candidates: [MediaItem]) -> [RankedMatch]
}
```

**Rejected alternative:** put parsing/ranking in `LibraryDomain`. It's
metadata-side glue; `LibraryDomain` is watch-state-side. Cohesion wins.

### D9 — Continue-watching projection (#17 seam)

#17 needs to render `ContinueWatchingItem`s = `(MediaItem, WatchStatus,
lastPlayedAt)` for in-progress files. The data path:

1. Call `engineClient.listPlaybackHistory()` → `[PlaybackHistoryDTO]`
   (Phase 1).
2. Filter to `WatchStatus ∈ {.inProgress, .reWatching}`.
3. For each, look up the torrent file's name (already in
   `TorrentFileDTO`, served by the existing `engineClient.listFiles`).
4. `TitleNameParser.parse(fileName)` → `ParsedTitle`.
5. `MetadataProvider.searchMulti(parsed.title)` → candidates.
6. `MatchRanker.rank(parsed, candidates)` → top match (gated by a
   minimum confidence threshold; default `0.6`).
7. If matched: render `(MediaItem, WatchStatus, lastPlayedAt)`. If not:
   render with the raw file name as fallback (calm copy: "Untitled
   torrent file"; never drop the row).

The match results are themselves cached (key: file name) with a 30-day
TTL — re-parsing on every continue-watching render would be wasteful.

#17's PR contains the orchestration. #11 contains the building blocks.

### D10 — Search UI (#14) is TMDB-backed, not local

Spec 07 § 1 mentions "Global search." Per `.claude/specs/01-architecture.md`
and `CLAUDE.md`, library-side search uses in-memory
`localizedStandardContains` filtering — but that's library scope (files
the user has). The Discovery search surface (#14) is **discovery-side**
search — finding titles on TMDB to add to the library.

- **Endpoint:** `GET /search/multi?query=…`. Returns mixed
  movies/shows.
- **Debouncing:** 250 ms after the user stops typing. Cancel in-flight
  requests.
- **No local index** in the SQLite sense. The "index" is TMDB itself.
- **Result ranking:** TMDB's own popularity-weighted ordering; we don't
  re-rank. If the user wants better matches, they type more characters.

Library-side search (filtering downloaded files) is a Module 4 / library
concern — out of scope for #14, and may merit its own ticket later.

### D11 — Browse hierarchy (#13)

Sidebar:

- **Library** (existing).
- **Home** (new, default landing surface).
- **Movies** (new — TMDB-backed grid filtered to movies).
- **Shows** (new).
- ~~Watchlist~~ — p1 (Account Sync), not Phase 4.

Home rows (top to bottom):

1. **Continue Watching** (#17) — only rendered if there are matched
   in-progress files.
2. **Trending — Movies** (TMDB `/trending/movie/week`).
3. **Trending — Shows** (TMDB `/trending/tv/week`).
4. **Popular Movies** (TMDB `/movie/popular`).
5. **Popular Shows** (TMDB `/tv/popular`).
6. **Top Rated Movies** (TMDB `/movie/top_rated`).
7. **Top Rated Shows** (TMDB `/tv/top_rated`).

Each row is a horizontally-scrolling carousel of poster cards. Tap a
card → title detail page (#15). Empty/error state per `06-brand.md §
Voice` — a quiet "We can't reach the catalogue right now" rather than
a red banner.

The exact row set is tuned in #13's PR; this list is the starting
point.

### D12 — Phase 3 tail unblocked once #11 lands

#20 (end-of-episode detection) and #21 (next-episode auto-play) were
deferred during Phase 3's design pass (`docs/design/player-state-foundation.md
§ D1`, Option A) on the grounds that they need real episode metadata.
With #11 merged, both unblock and can be picked up.

**Sequencing recommendation:**

- #11 lands first (foundation).
- Phase 4 dependent tickets (#13, #14, #15, #16, #17) and Phase 3 tail
  (#20, #21) can then proceed in parallel — they share #11 as a
  dependency but have no inter-dependencies among themselves except
  #16 needs #15.

## Type sketch

```swift
// Packages/MetadataDomain/Sources/MetadataDomain/

public struct Movie: Equatable, Sendable, Hashable, Codable {
    public let id: MediaID
    public let title: String
    public let originalTitle: String
    public let releaseYear: Int?
    public let runtimeMinutes: Int?
    public let overview: String
    public let genres: [Genre]
    public let posterPath: String?         // TMDB path; combine with imageURL
    public let backdropPath: String?
    public let voteAverage: Double?
    public let popularity: Double?
}

public struct Show: Equatable, Sendable, Hashable, Codable {
    public let id: MediaID
    public let name: String
    public let originalName: String
    public let firstAirYear: Int?
    public let lastAirYear: Int?
    public let status: ShowStatus           // .returning | .ended | .canceled | .inProduction
    public let overview: String
    public let genres: [Genre]
    public let posterPath: String?
    public let backdropPath: String?
    public let voteAverage: Double?
    public let popularity: Double?
    public let seasons: [Season]            // hydrated lazily by detail fetch
}

public struct Season: Equatable, Sendable, Hashable, Codable {
    public let showID: MediaID
    public let seasonNumber: Int
    public let name: String
    public let overview: String
    public let posterPath: String?
    public let airDate: Date?
    public let episodes: [Episode]
}

public struct Episode: Equatable, Sendable, Hashable, Codable {
    public let id: MediaID                  // distinct TMDB ID per episode
    public let showID: MediaID
    public let seasonNumber: Int
    public let episodeNumber: Int
    public let name: String
    public let overview: String
    public let stillPath: String?
    public let runtimeMinutes: Int?
    public let airDate: Date?
}

public struct Genre: Equatable, Sendable, Hashable, Codable {
    public let id: Int
    public let name: String
}

public enum ShowStatus: String, Equatable, Sendable, Codable {
    case returning, ended, canceled, inProduction
}

public enum TrendingMedia: String, Sendable {
    case movie, tv, all
}

public enum TrendingWindow: String, Sendable {
    case day, week
}
```

`Packages/MetadataDomain` declared as a new local SPM package, mirroring
`LibraryDomain` (Phase 1) and `SubtitleDomain` (Phase 2). It depends on
nothing engine-side — metadata is fully orthogonal to the XPC layer.

## Cache layout

```
~/Library/Application Support/ButterBar/metadata/
├── responses/
│   ├── trending-movie-week-2026-W16.json
│   ├── popular-movie-2026-04-16.json
│   ├── movie-1668.json
│   ├── tv-1668.json
│   ├── tv-1668-season-1.json
│   ├── tv-1668-season-2.json
│   ├── recommendations-movie-1668.json
│   ├── search-multi-{hash}.json          # only if we ever decide to cache search; D7 says we don't
│   └── configuration.json
├── images/                                # URLCache-managed
└── cache_meta.json                        # { url → { etag, fetched_at, expires_at } }
```

Cache writes are atomic (write to `.tmp`, rename to final) so a crash
mid-write never produces a half-file. Read failures (corrupt JSON,
truncated file) treat the entry as cache-miss and re-fetch.

## Test shape

The foundation ticket (#11) lands these test groups. Other Phase 4
tickets reuse the harnesses.

### Domain-type tests (`Packages/MetadataDomain`)

- `MediaItemCodableTests`: round-trip `Movie`, `Show`, `Season`,
  `Episode`, `MediaItem` enum cases. JSON snapshot tests guard schema
  shape.
- `MediaIDTests`: equality, hashing, codable round-trip.

### Parsing tests (`TitleNameParserTests`)

Fixture file `Packages/MetadataDomain/Tests/Fixtures/release-names.txt`
with ≥ 50 representative torrent file names (movies, shows, anime,
foreign, ambiguous). Each entry has a sidecar `.expected.json` with the
expected `ParsedTitle`. Parser is required to match.

### Ranking tests (`MatchRankerTests`)

Synthetic candidate lists per parsed input; assert that the expected
top match has confidence ≥ threshold and that the right reasons appear
in the result. Includes the "wrong year" demotion case, the
"different show with same title" case, and the "Roman numeral sequels"
case (`Rocky II` ≠ `Rocky 2`).

### Cache tests (`MetadataCacheTests`)

- TTL expiry (with injected clock).
- Stale-while-revalidate path.
- Atomic write + corrupted-read fallback.
- ETag round-trip.
- Eviction is unbounded for response cache (small JSON; capped only by
  disk budget — TBD whether to add an LRU; flag as Open Question O3).

### Provider contract tests (`MetadataProviderContractTests`)

A protocol-level test suite that any `MetadataProvider` impl must
satisfy. Run against `FakeMetadataProvider` in CI. The TMDB integration
tests (against the real API) are gated behind a build flag and do
**not** run in CI (no embedded keys in CI).

### Image cache tests (`ImageCacheTests`)

- `URLCache` configuration is correct (disk path, 500 MB budget).
- Failure-mode placeholder is rendered when a fetch errors.
- Size suffix selection is correct for given logical sizes.

### Library matching seam tests (deferred)

The integration test "given a torrent file, find its TMDB match" lands
with #17 (where the orchestration lives). #11 covers only the building
blocks.

## Out of scope for the foundation

- Browse hierarchy UI (sidebar, home grid, carousels) — that is **#13**.
- Search UI — that is **#14**.
- Title detail page UI — that is **#15**.
- Season/episode selector UI — that is **#16**.
- Continue-watching row UI and orchestration — that is **#17**.
- End-of-episode detection — that is **#20** (Phase 3 tail).
- Next-episode auto-play — that is **#21** (Phase 3 tail).
- Trakt integration / sync — that is Module 5 / Epic #6 (p1).
- Local library search (filter downloaded files) — Module 4 concern,
  separate ticket if it surfaces.
- TMDB API client choice (`adamayoung/TMDb` vs hand-rolled URLSession)
  — Open Question O1; resolved in #11's implementation PR.
- A `StubMetadataProvider` for SwiftUI previews — follow-up.
- Per-user TMDB account integration (favourites on TMDB itself) — out
  of v1 scope; possibly v1.5+.

## Risks and mitigations

| Risk                                                                              | Mitigation                                                                                                                          |
| --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| TMDB rate-limit hit on heavy browsing                                             | TTLs (D7) keep cold starts cheap; in-flight request coalescing per URL; respect TMDB's `Retry-After` header.                        |
| TMDB API access token revoked                                                     | Embedded token rotation requires app update — accept for personal-use posture per spike § 4. If the app is ever distributed, revisit relay pattern. |
| Cache directory grows unbounded                                                   | Image budget capped at 500 MB via `URLCache`. Response cache JSON is small (< 100 KB per entry); track total size, alert at 100 MB. |
| Match ranker false positives (wrong title, wrong year)                            | Confidence threshold; user-facing "Wrong title? Search…" affordance on match displays (UI ticket); ranker reasons exposed for debug. |
| Episode metadata drift (TMDB updates an episode after we cached it)               | 30-day TTL per D7; ETag revalidation; manual "refresh metadata" path lives in Settings (Epic #8, p1).                              |
| New TMDB account types impose API changes                                         | Provider protocol confines breakage to a single impl file.                                                                          |
| Personal-use API key gets pulled                                                  | Same as revocation above — accepted risk for v1 personal use.                                                                       |
| Sandbox blocks writing to `~/Library/Application Support/`                        | This is the standard sandboxed app-support path; entitlements as configured already permit it.                                      |
| Search UI feels laggy (network round-trip per keystroke)                          | Debounce 250 ms; cancel in-flight requests on new keystroke; show a calm spinner not a jarring loading state.                       |

## Open questions

These are recorded here rather than resolved in this pass. Each is
expected to land in a specific implementation PR.

### O1 — TMDB client: `adamayoung/TMDb` SPM dependency vs hand-rolled `URLSession`

Per the spike § 5, `adamayoung/TMDb` is a credible Swift 6 / macOS 13+
SPM package covering all required endpoints. Trade-offs:

- **Adopt** — saves writing ~500 lines of REST boilerplate and image-URL
  building. Couples our build to a third-party package's release
  cadence; we'd still wrap it behind `MetadataProvider` so the surface
  is one file.
- **Hand-roll** — total control; one fewer dependency; thin glue layer
  inside `TMDBProvider`. ~3 days of work to cover the endpoint set in
  the spike § 5.

**Recommendation for #11's implementation PR:** start hand-rolled. If
the second TMDB endpoint we add takes more than a day, switch to
`TMDb`. The protocol layer means the swap is a one-file change.

### O2 — Cache eviction policy for response JSON

Response JSON entries are small (< 100 KB typical) so a 100 MB cap
holds ~1000 entries — well above what a v1 user will ever have. But:

- Should we add an explicit LRU on the response cache, or trust the
  total disk usage to stay sub-100 MB indefinitely?
- What happens on cold-cache rebuild after the user clears the cache
  (Settings, Epic #8) — is the re-fetch storm a problem?

**Recommendation for #11's implementation PR:** measure first. Ship
with no LRU; track total size; re-evaluate if it ever crosses 50 MB on
a real install.

### O3 — Spec 07 § Open questions doc-hygiene drift

Spec 07's "Open questions" list still asks "Which metadata source
should be primary?" — answered by the spike on 2026-04-15 and recorded
here in D1. The spec line is stale. Not fixed in this PR to keep the
surface small; tracked as a separate doc-hygiene follow-up that can
strike the resolved bullet and link to the spike.

## Cross-references

- Phase 1 foundation: [`docs/design/watch-state-foundation.md`](watch-state-foundation.md)
  — `WatchStatus`, `listPlaybackHistory`. Consumed by #17's continue-watching projection (D9).
- Phase 2 foundation: [`docs/design/subtitle-foundation.md`](subtitle-foundation.md)
  — `SubtitleTrack`. No direct dependency from Phase 4, but #15 and
  #16 will surface subtitle availability indicators where applicable.
- Phase 3 foundation: [`docs/design/player-state-foundation.md`](player-state-foundation.md)
  — `PlayerState`. The Phase 3 tail (#20, #21) consumes #11's episode
  schema (D2, D12).
- Spike: [`docs/spike-metadata-sources.md`](../spike-metadata-sources.md)
  — TMDB / TVDB / Trakt evaluation; the source of D1.
- Spec 07 § 1 (Discovery and metadata) — the product-surface spec this
  foundation services.
- Spec 07 § 6 (Provider Abstraction) — clarifies that `MediaProvider`
  (torrent provider) is distinct from `MetadataProvider` (TMDB
  provider). The two protocols co-exist; one sources playable content,
  the other sources information about content.
- Roadmap: `docs/v1-roadmap.md § Phase 4` — this design pass closes
  the long-standing `needs-design` flag on #11 (D1).
