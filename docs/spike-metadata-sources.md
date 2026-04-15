# Spike: Metadata Source Evaluation — TMDB / TVDB / Trakt

**Date:** 2026-04-15
**Branch:** `spike/metadata-source-evaluation`
**Status:** Complete

---

## 1. Executive Summary

Use **TMDB as the primary metadata and image source** — it covers both movies and TV comprehensively, has a strong image CDN, provides trending/popular/discover endpoints that map directly to ButterBar's home-screen rows, and has a well-maintained Swift package. Layer **Trakt on top for watch-state sync** (Module 5): Trakt's watch history, ratings, and list APIs are exactly what that module needs, and since Trakt already sources its own metadata from TMDB, the two are designed to be used together. TVDB is not recommended for v1 — its licensing model introduces friction for end users and its movie coverage is historically weaker.

---

## 2. Comparison Matrix

| Dimension | TMDB | TVDB | Trakt |
|---|---|---|---|
| **Primary focus** | Movies + TV (equal) | TV (movies added later) | Social tracking layer (metadata from TMDB) |
| **API version** | v3 (stable) + v4 (auth/lists) | v4 | v2 |
| **Pricing — free tier** | Free for non-commercial with attribution | Free if company revenue < $50k/yr | Free (no tiers) |
| **Pricing — commercial** | ~$149/month (contact sales; revenue threshold unclear) | $1k–$10k/yr by revenue band; >$1M custom | No paid tier documented |
| **Rate limit** | ~40 req/s per IP (soft, no daily cap) | Not publicly documented | 1,000 GET req / 5 min; 1 write req/s |
| **Images served directly?** | Yes — own CDN at `image.tmdb.org` | Yes — own image host | No — returns TMDB/TVDB/Fanart.tv IDs only |
| **Poster sizes** | w92, w154, w185, w342, w500, w780, original | Available but fewer documented sizes | N/A |
| **Backdrop sizes** | w300, w780, w1280, original (up to 4K) | Available | N/A |
| **Episode stills** | Yes (up to 1080p+) | Yes | N/A |
| **Logo / SVG artwork** | Yes (company/network logos in SVG + PNG) | No | N/A |
| **Trending endpoint** | Yes — daily/weekly movies + TV | No | Yes — real-time watchers |
| **Popular / top-rated** | Yes | No | Yes — popular lists |
| **Discover / filter** | Yes — 30+ filter options | No | Limited |
| **Season + episode detail** | Yes — full hierarchy | Yes | Yes (pulls from TMDB) |
| **Watch history sync** | No | No | Yes — core feature |
| **Ratings sync** | No | No | Yes |
| **OAuth required for lists** | Optional (user personalisation only) | No | Yes (for user data) |
| **Swift package** | `adamayoung/TMDb` — Swift 6, macOS 13+, actively maintained | None official; community libraries only | None official |
| **Attribution required** | Yes — "not endorsed" notice in About/Credits | Yes — direct link to thetvdb.com | No explicit requirement found |

---

## 3. Recommendation

### Primary metadata: TMDB

TMDB wins on every axis that matters for ButterBar:

- **Data breadth.** Movies and TV are equally deep. Season, episode, and episode-still data are first-class.
- **Discovery endpoints.** `/trending/{media_type}/{time_window}`, `/movie/popular`, `/movie/top_rated`, `/discover/movie`, `/discover/tv` map directly to ButterBar's planned home-screen rows (trending, popular, top rated, curated).
- **Image CDN.** `image.tmdb.org` serves posters up to original (2000×3000), backdrops up to 4K (3840×2160), episode stills up to 1080p+, and SVG/PNG logos. Every image type ButterBar needs is covered.
- **Rate limits.** ~40 req/s per client IP is generous for a desktop app where one user's session generates maybe a few hundred calls. No documented daily cap.
- **Swift package.** `adamayoung/TMDb` (Swift 6, macOS 13+, SPM) covers all required endpoints including trending, search, TV seasons/episodes, images, and recommendations. It has 260+ commits, CI, and Swift 6 concurrency support — usable as a starting point or reference.

**Trade-off:** Commercial licensing is murky. The free tier is clearly for non-commercial use; a paid app on the Mac App Store almost certainly triggers the commercial requirement (~$149/month as of late 2025, contact `sales@themoviedb.org` to confirm). This should be resolved before shipping. Given that comparable apps (Infuse, etc.) operate with TMDB data, a negotiated license is plausible.

### Watch-state sync: Trakt

Trakt is the right choice for Module 5:

- Explicit watch history, ratings, and list sync APIs.
- Works with `ASWebAuthenticationSession` on macOS — standard OAuth 2 with a browser redirect, which is the approved pattern for native macOS apps.
- Trakt's own metadata is sourced from TMDB and cross-referenced with TMDB IDs, so IDs from the primary fetch can be passed directly to Trakt sync calls with no translation layer.
- Free, no rate-limit concerns for a single-user desktop client (1,000 GET req / 5 min is more than sufficient).

**Trakt is not a metadata source.** It does not serve images. Use it only for the sync/social layer.

### TVDB: not recommended for v1

- Movie coverage is an afterthought (TV-first, movies added later).
- The user-supported key model requires each end user to hold a $12/year TVDB subscription and enter a PIN — a significant onboarding friction for a premium macOS app.
- The licensed key model removes that friction but costs $1k–$10k/year based on revenue, comparable to or worse than TMDB's commercial tier.
- No trending/popular/discover endpoints.
- No official Swift library.

TVDB is only worth revisiting if ButterBar needs niche TV data (e.g., absolute episode ordering, alternate episode airing orders for anime) that TMDB doesn't carry — and even then, it would be a supplement, not a primary source.

---

## 4. API Key Strategy

### The problem

ButterBar is a distributed desktop binary. Any key embedded in the binary is extractable. Both TMDB and Trakt have keys that, if abused at scale, could get the app's registration revoked or rate-capped.

### Options and trade-offs

| Strategy | Pros | Cons |
|---|---|---|
| **Embed key in binary (obfuscated)** | Zero onboarding friction | Key is extractable; if revoked, requires app update; violates spirit of ToS |
| **User provides own key** | No key risk to developer; ToS-clean | High friction (requires TMDB account); unacceptable for a premium consumer app |
| **Proxy server (relay)** | Key never leaves server; can rate-limit/monitor per user | Requires running infrastructure; adds latency; operational cost |
| **Embed + rotate via remote config** | Low friction; can rotate without app update | Still extractable; needs a server for config delivery |

### Recommendation

For v1 (pre-App Store, closed beta): **embed the key**, obfuscated, with a warning in SECURITY.md. This is what Seren, Kodi addons, and virtually every comparable open-source player does.

For App Store / public release: **proxy relay** is the cleanest architecture. A lightweight serverless function (Cloudflare Worker or equivalent) signs requests server-side. The app authenticates to the relay (e.g., with an app-specific token tied to the user's ButterBar account), and the relay forwards to TMDB/Trakt with its own keys. This also enables:
- Per-user rate limiting
- Analytics on which endpoints are called
- Key rotation without app updates

This decision should be made before the product-surface work begins in earnest, since it affects whether a ButterBar account/backend is required.

**Trakt specifically:** Trakt's OAuth flow means the `client_id`/`client_secret` must be in the binary or relay. The `client_secret` is effectively the higher-risk item — if someone extracts it and registers a fake app, they could phish users. The relay pattern avoids this entirely.

---

## 5. Integration Notes

### TMDB

- **Base URL:** `https://api.themoviedb.org/3/`
- **Auth:** `Authorization: Bearer <access_token>` header (preferred over `?api_key=` query param). The access token is obtained from the TMDB dashboard — it is not user-specific for public endpoints.
- **Image base URL:** Retrieve dynamically from `GET /configuration` → `images.base_url` (currently `https://image.tmdb.org/t/p/`). Append size + file path. Cache this response; it rarely changes.
- **Key endpoints for ButterBar:**
  - `GET /trending/{movie|tv|all}/{day|week}` — home screen trending rows
  - `GET /movie/popular`, `GET /tv/popular` — popular rows
  - `GET /movie/top_rated`, `GET /tv/top_rated` — top-rated rows
  - `GET /discover/movie`, `GET /discover/tv` — filtered catalogue views
  - `GET /search/multi` — unified search
  - `GET /movie/{id}`, `GET /tv/{id}` — title detail pages
  - `GET /tv/{id}/season/{n}`, `GET /tv/{id}/season/{n}/episode/{n}` — episode navigation
  - `GET /movie/{id}/recommendations`, `GET /tv/{id}/recommendations` — related titles
  - `GET /movie/{id}/images`, `GET /tv/{id}/images` — full image listings (use `include_image_language=en,null` for untagged stills)
- **`append_to_response`:** Use to combine detail + credits + images in a single call (reduces round-trips on title detail page).
- **Swift package:** `adamayoung/TMDb` via SPM. Requires Swift 6 / macOS 13+. Covers all the endpoints above. Consider using it as a reference implementation and wrapping it behind a ButterBar-internal `MetadataService` protocol to avoid coupling the app layer directly to the package's types.
- **Attribution:** Display "This product uses the TMDB API but is not endorsed or certified by TMDB" in the app's About screen. Include TMDB logo (from approved assets) less prominently than ButterBar's own branding. Link to `https://www.themoviedb.org`.

### Trakt

- **Base URL:** `https://api.trakt.tv/`
- **Required headers:** `Content-Type: application/json`, `trakt-api-version: 2`, `trakt-api-key: <client_id>`
- **OAuth flow:**
  1. Open `https://trakt.tv/oauth/authorize?response_type=code&client_id=…&redirect_uri=…` via `ASWebAuthenticationSession`.
  2. Handle the callback URL in the session completion handler.
  3. Exchange code for access + refresh tokens via `POST /oauth/token`.
  4. Store tokens in Keychain (not UserDefaults). Refresh via `POST /oauth/token` with `grant_type=refresh_token` before expiry.
- **Key endpoints for Module 5 sync:**
  - `POST /sync/history` — mark watched
  - `GET /sync/history/{movies|shows}` — pull watch history
  - `GET /sync/ratings/{movies|shows}` — pull ratings
  - `POST /sync/ratings` — push ratings
  - `GET /users/{username}/lists` — user lists
  - `GET /movies/trending`, `GET /shows/trending` — optionally use Trakt's trending as a second opinion
- **ID cross-referencing:** Trakt objects include an `ids` block with `tmdb`, `tvdb`, `imdb`, `trakt` IDs. Use the `tmdb` ID to join back to TMDB artwork and supplementary metadata.
- **No official Swift library.** Build a thin networking layer using `URLSession` / `async`-`await`. It's a REST API with predictable JSON responses; a full SDK is overkill.

### TVDB (for reference only)

If TVDB is ever needed for supplemental data (alternate episode ordering, etc.):
- Auth: `POST /login` with `{"apikey": "...", "pin": "..."}` → JWT bearer token (24-hour expiry).
- The PIN requirement means you must either have a licensed key (no PIN needed from users) or require users to subscribe at thetvdb.com.
- Base URL: `https://api4.thetvdb.com/v4/`

---

## 6. Open Questions

| # | Question | Who decides | Priority |
|---|---|---|---|
| OQ-1 | Does ButterBar plan to charge users (App Store paid app, subscription, or IAP)? This determines whether TMDB's commercial license is required before launch. | Product / Opus | High |
| OQ-2 | Is a ButterBar backend/relay in scope for v1 or v2? The API key strategy recommendation diverges significantly depending on the answer. | Opus | High |
| OQ-3 | Should TMDB commercial licensing be negotiated proactively now, or deferred until the app is closer to launch? Given TMDB's ~$149/month disclosed price, early contact de-risks last-minute surprises. | Opus | Medium |
| OQ-4 | Is Trakt Module 5 scope for v1 or a later milestone? If v2+, the OAuth infrastructure design can be deferred. | Opus | Medium |
| OQ-5 | Should ButterBar surface Trakt-powered social features (friends' ratings, community trending) or restrict Trakt to private sync only? Affects product UX and data-sharing stance. | Product / Opus | Low |
| OQ-6 | Is Fanart.tv worth adding for supplemental logo/banner artwork (clearart, disc art, etc.)? It provides content TMDB doesn't carry. Free tier: 100 req/day; $3.50/month for higher volume. | Opus | Low |
