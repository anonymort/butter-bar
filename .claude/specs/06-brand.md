# 06 — Brand (ButterBar)

> **Revision 3** — Asset specifications and Icon Composer workflow rewritten around the supplied **Liquid Glass prep package** (`icons/ButterBar-LiquidGlass-prep/`). Layered source material clarified (background + up to 4 foreground groups). `AppIcon.icon` placement corrected — at the same level as `Assets.xcassets`, not inside it. See addendum A19. Rev 2 introduced Tahoe targeting and the Liquid Glass design language. Rev 1 was the initial brand spec for the rebrand from PopcornMac.

## Brand position

ButterBar is a premium native macOS media client built for **macOS Tahoe (26) and later**. The brand cues are *craft, smoothness, warmth* — closer to apps like Things, Soulver, or Mela than to traditional torrent clients. Functional, confident, no novelty themes, no skeuomorphism, no torrent-scene aesthetic.

The name has two meanings the design supports:
- **Butter** — buttery-smooth playback, the core promise; reflected literally in the logo's butter-pat motif.
- **Bar** — the seek/progress bar, the canonical control; reflected in the shelf the butter pat rests on.

The logo also carves a play symbol into the butter pat, tying the metaphor to the product function. Avoid ever leaning on just one of the three ideas; the full mark holds them simultaneously.

## Voice

- **Direct.** Short sentences. No exclamation marks except in genuine error states.
- **Calm.** Even when buffering is poor or peers are scarce, the UI never panics. "Slower than usual" beats "Connection problems!"
- **Concrete.** "12 seconds buffered" not "Loading…". Numbers when we have them.
- **British English** in all UI strings, error messages, and documentation.
- **No marketing voice in the product.** Save the warmth for onboarding and About; the operational UI stays factual.

| Context | Good | Avoid |
|---|---|---|
| Stream healthy | "12 s ready · 4.2 MB/s" | "Streaming smoothly!" |
| Stream marginal | "Buffer low — 6 s ready" | "⚠️ Connection issues" |
| Stream starving | "Stalled — waiting for peers" | "Error: insufficient bandwidth" |
| First open | "Add a magnet link to begin." | "Welcome to ButterBar! 🎬" |

## Colour palette

Defined as semantic tokens, not raw hex literals. UI code references tokens; the token→hex mapping lives in one Swift file (`BrandColors.swift`). Tahoe's Liquid Glass material picks up tints from underlying content — keep the brand palette warm enough that glass surfaces don't read as cold or generic Apple-default.

### Core palette

| Token | Light hex | Dark hex | Use |
|---|---|---|---|
| `butter` | `#F5C84B` | `#E5B83B` | Primary brand colour. Sparingly: logo, healthy tier accent, primary buttons, glass tint. |
| `butterDeep` | `#C9971F` | `#B8861A` | Hover/pressed state of `butter`. The carved play symbol in the logo. |
| `cream` | `#FAF6EC` | `#2A2620` | Surface background. Inverts in dark mode to a warm dark, not pure black. |
| `creamRaised` | `#FFFDF5` | `#332E26` | Cards, sheets, raised surfaces (under glass). |
| `cocoa` | `#2A1F12` | `#F1ECE0` | Primary text. Warm dark, not pure black. Inverts to warm off-white in dark mode. |
| `cocoaSoft` | `#5A4A35` | `#C2B8A5` | Secondary text, captions, metadata. |
| `cocoaFaint` | `#9C8E78` | `#7A6F5C` | Tertiary text, disabled states, dividers. |

### Tier colours (StreamHealth)

The `StreamHealth.tier` enum maps to one colour token each. **The mapping is fixed** — UI may not introduce new tier colours or substitute different tokens. See `02-stream-health.md` § UI rendering contract.

| Tier | Token | Light hex | Dark hex | Notes |
|---|---|---|---|---|
| `healthy` | `tierHealthy` | `#7BA05B` | `#8FB36F` | Muted olive-green. Not the system green — too aggressive against `butter`. |
| `marginal` | `tierMarginal` | `#E5B83B` | `#F5C84B` | Same family as `butter` but distinguishable. Marginal is "watch this," not "panic." |
| `starving` | `tierStarving` | `#C25A3D` | `#D46B4E` | Warm terracotta, not red. Red would feel like an error; starving is a recoverable state. |

**Why no system colours:** macOS system green/yellow/red read as iOS/Apple defaults and break the warm palette. ButterBar uses its own tier colours. The trade-off: users with red-green colour deficiency lose some signal — mitigate by always pairing tier colour with the tier label text.

### Surface tokens

| Token | Use |
|---|---|
| `surfaceBase` | Window background. Maps to `cream`. |
| `surfaceRaised` | Cards, sheets, content panels under glass chrome. Maps to `creamRaised`. |
| `surfaceOverlay` | Modal scrims, popovers without glass treatment. Maps to `cocoa` at 40% opacity. |

## Typography

System fonts only. No custom font files in v1.

- **Display / large headers:** SF Pro Display, weight 600, tracking -0.02em.
- **Body / UI text:** SF Pro Text, weight 400 for body, 500 for emphasis.
- **Numerals (rates, durations, byte counts):** SF Pro Text with `.monospaced(.body)` modifier in SwiftUI, so `12 s ready · 4.2 MB/s` doesn't jitter as values change.
- **Captions / metadata:** SF Pro Text 12pt, weight 400, `cocoaSoft` colour.

Line heights default to SwiftUI's automatic. Don't fight the system layout.

## Motion

ButterBar's motion language is **slow, soft, and continuous**. The product promise is buttery; UI motion should feel butter-like, not bouncy. Tahoe's Liquid Glass already adds significant ambient motion (lensing, specular response) — your own animations should sit underneath that, not compete with it.

- **Default transition curve:** `easeInOut`, duration 250 ms. SwiftUI: `.animation(.easeInOut(duration: 0.25), value: ...)`.
- **Tier transitions in HUD:** 400 ms cross-fade between tier colours, never an abrupt swap.
- **Buffer-ahead indicator:** updates continuously rather than stepping. If `secondsBufferedAhead` jumps from 8 to 32, animate the fill across 800 ms.
- **No spring physics.** Springs feel iOS-y and undermine the calm. `easeInOut` everywhere.
- **No icon spinners as primary state.** A spinner says "we don't know what's happening." The buffer-ahead indicator is the primary live element.

## Liquid Glass

Tahoe ships with the Liquid Glass design language. Per Apple's guidance: glass is for the **navigation layer that floats above content**, never for content itself. ButterBar follows this strictly.

### Where glass is used

- **Toolbar and window chrome.** Automatic when the app is built against the macOS 26 SDK.
- **Sidebar.** Automatic.
- **Player HUD.** The floating overlay on top of the video uses `.glassEffect(.regular.interactive())` so it picks up tint from the video underneath.
- **Sheets and popovers.** Automatic for system sheets/popovers.

### Where glass is forbidden

- **Library row backgrounds.** Content. Solid `surfaceBase`.
- **Title detail page panels.** Content. Solid `surfaceRaised`.
- **Settings page rows.** Content. Solid `surfaceRaised`.
- **Anything in the body of a view that isn't floating navigation.**

The wrong pattern (`.glassEffect()` on a `List` row) produces visual mush and fails Apple's HIG guidance.

### Compatibility flag

If a future engineering need arises to ship a build against macOS 26 SDK but render the legacy (pre-Tahoe) design temporarily, add `UIDesignRequiresCompatibility = YES` to `Info.plist`. This is an Apple-provided opt-out scheduled to remain available until macOS 27 (per Apple developer documentation as of late 2025). **Do not ship v1 with this flag set.** It exists only as a debugging escape hatch.

## Logo

The mark is supplied as a complete asset package — see § Asset specifications below. The concept and rationale are recorded here for future maintenance.

### Concept

A **butter pat** rests on a **horizontal bar/shelf**. A **play symbol** is carved into the butter pat. The three ideas — butter, bar, play — sit in a single mark without any one dominating.

Colour rationale per supplied package:
- Butter pat in `butter` (`#F5C84B`).
- Carved play symbol in `butterDeep` (`#C9971F`) — implied recess/shadow rather than an additive shape.
- Bar/shelf in `butterDeep` so it grounds the composition without competing with the pat.

### Design notes (from supplied package)

- The mark is kept well inside the safe area for Tahoe's squircle masking.
- Contrast and silhouette were kept simple so the icon remains legible at 16 px (the smallest macOS list-view icon size).
- The carved play symbol drops out at extremely small sizes; the silhouette of the pat-on-bar carries the identity at thumbnail scale.

### Asset specifications

The supplied `icons/` folder at the repo root contains two complementary deliverables:

#### Flat asset package (legacy / preview)

Files at the top level of `icons/`:

| File | Purpose |
|---|---|
| `butter-bar-logo.svg` | Master vector source, 1024 × 1024 canvas — the original flat composition. |
| `butter-bar-logo-1024.png` | Master raster export at 1024 × 1024. Useful as a flattened preview / marketing image. |
| `butter-bar-logo@1x.png` | Convenience raster for documentation, GitHub social preview. |
| `butter-bar-logo@2x.png` | Convenience Retina raster. |
| `butter-bar-logo@3x.png` | Convenience extra-Retina raster. |
| `ButterBar.iconset/` | Legacy macOS icon PNG set. Used to generate the `.icns` fallback below. |
| `ButterBar.icns` | Legacy `.icns` container. Inactive at the v1 deployment target — retained for back-deploy or App Store Connect tooling that still inspects raster sizes. |

#### Liquid Glass prep package (primary path)

Files in `icons/ButterBar-LiquidGlass-prep/`:

| File / folder | Purpose |
|---|---|
| Layered transparent PNGs | One PNG per icon layer, 1024 × 1024 each, transparent background, no drop shadows or highlights baked in (Icon Composer applies these). Filenames are prefixed `0_`, `1_`, `2_`… per Apple's recommended ordering convention so they sort correctly in Icon Composer. |
| Revised SVG master | Updated vector source with explicit layer separation, suitable for re-import into a vector tool if layer adjustments become necessary. |
| Flattened preview PNG | A single composite PNG showing what the layers look like assembled. For visual reference only. |
| Size exports (16, 32, 64, 128, 256, 512, 1024) | Flattened raster previews at each macOS icon size. For legibility testing without going through Icon Composer. |
| `README` | Layer mapping/order notes explaining which layer is which (background, butter pat, carved play symbol, bar/shelf, any specular hints) and the recommended import order. |

This is the package to use when authoring `AppIcon.icon` in Icon Composer. The flat assets above are not suitable for the layered Liquid Glass workflow — they would render as a single image with system-applied specular only, missing the layer-specific tuning that gives Liquid Glass its depth.

### Tahoe icon workflow (Icon Composer)

macOS Tahoe (26) introduced a new icon format — **`.icon`** — authored in Apple's **Icon Composer** tool (shipped with Xcode 26). The format supports a **background plus up to four foreground layer groups**; each group can have its own material properties (specular, blur, translucency, shadow), and the system uses these to generate the final dynamic Liquid Glass appearance.

The `.icon` bundle supports four appearance modes that Tahoe selects between based on user preference:

1. **Default** — the standard icon as designed.
2. **Dark** — explicit dark-mode variant.
3. **Tinted (Mono)** — monochrome version that picks up the user's accent colour. For "Mono" to look right, at least one layer should be close to white.
4. **Clear** — translucent version used when the user has selected the clear icon style in System Settings → Appearance.

For ButterBar v1, **Default and Dark are mandatory**; Tinted and Clear should be supplied unless Icon Composer can derive them cleanly from the layered source.

#### Step-by-step workflow

1. **Open Icon Composer** — Xcode 26 → Open Developer Tool → Icon Composer. (Requires macOS Sequoia 15.3+ to launch the tool itself; the resulting `.icon` file targets macOS 26.)
2. **Drag the layered PNGs** from `icons/ButterBar-LiquidGlass-prep/` into the Icon Composer sidebar in their numeric order (`0_…`, `1_…`, `2_…`, `3_…`). The tool will create a layer group automatically.
3. **Set the background colour** in Icon Composer's document settings if it isn't a layer in the prep package — using a flat colour fill in document settings rather than a layer saves one of the four available foreground slots.
4. **Tune Liquid Glass properties per layer:** specular highlights, blur, translucency, shadows. Toggle Liquid Glass on by default; toggle off only for layers that should remain matte (e.g. the carved play symbol, which reads as a recess and should not catch a highlight).
5. **Configure appearance variants** for Default / Dark / Tinted / Clear. Adjust per-layer opacity or colour where needed; for Tinted mode, ensure at least one element is close to white.
6. **Preview** at multiple sizes and on different backgrounds within Icon Composer. Confirm the 16-pixel rendering remains identifiable as the ButterBar mark.
7. **Save as `AppIcon.icon`** in the `App/` directory — at the **same level as `Assets.xcassets`**, not inside it. (This is the Apple-documented Xcode integration path; the `.icon` file is its own first-class asset, not a member of the asset catalogue.)
8. **Commit `App/AppIcon.icon`** to the repo. Icon Composer files are folder bundles; they version-control fine but appear as a single item in Finder.

#### Xcode integration

Once `App/AppIcon.icon` exists:

1. Drag it into the Xcode project navigator (alongside `Assets.xcassets`, not nested in it).
2. In the app target's General settings, set **App Icon Set Name** to `AppIcon` (or whatever the `.icon` filename is, without the `.icon` extension).
3. Build. The icon should appear correctly in Finder and Dock with full Liquid Glass treatment.

#### Backwards-compatibility note

The Apple-documented backwards-compat trick — keeping an `AppIcon` set inside `Assets.xcassets` and naming the Icon Composer file `AppIcon` — would let the system fall back to flat icons on pre-Tahoe macOS. **For ButterBar v1 this is not needed** because the deployment target is macOS 26. The `ButterBar.icns` and `ButterBar.iconset/` files in `icons/` are retained as inactive insurance, in case a future addendum lowers the deployment target.

### Asset packaging in the repo

```
butter-bar/
├── App/
│   ├── AppIcon.icon/             ← built in Icon Composer; sibling of Assets.xcassets
│   └── Assets.xcassets/          ← does NOT contain AppIcon for v1
├── icons/                        ← supplied source material (version-controlled)
│   ├── butter-bar-logo.svg
│   ├── butter-bar-logo-1024.png
│   ├── butter-bar-logo@1x.png
│   ├── butter-bar-logo@2x.png
│   ├── butter-bar-logo@3x.png
│   ├── ButterBar.iconset/
│   ├── ButterBar.icns
│   └── ButterBar-LiquidGlass-prep/
│       ├── README                ← layer mapping/order
│       ├── 0_*.png               ← background layer (or use document fill colour)
│       ├── 1_*.png               ← layer 1 (e.g. bar/shelf)
│       ├── 2_*.png               ← layer 2 (e.g. butter pat)
│       ├── 3_*.png               ← layer 3 (e.g. carved play recess)
│       ├── butter-bar-logo.svg   ← revised SVG master with explicit layer separation
│       ├── flattened-preview.png ← composite preview
│       └── 16.png … 1024.png     ← size exports for legibility testing
```

The `App/AppIcon.icon` bundle is the only product that ends up in the shipped binary; the `icons/` folder is version-controlled source material, not bundled at build time.

### Squircle compliance

Tahoe enforces squircle compliance for app icons. Non-compliant icons are placed inside a grey squircle ("squircle jail"). The supplied prep package was designed with the mark centred and away from edges so the system mask doesn't crop content. **Do not redesign the mark to add edge bleed.** Apple documents that the system applies the final platform mask at render time — your job is to keep content within the safe area.

### What the logo must not do

- No film reels, no popcorn, no torrent magnet imagery.
- No gradients beyond the implied recess of the carved play symbol.
- No text wordmark inside the icon — the icon is the mark, the wordmark is separate.
- No drop shadows baked into the master SVG; Tahoe and Icon Composer handle icon shadowing and material treatment at render time.
- No animated icon. Tahoe supports motion in icons in some contexts; ButterBar's icon is intentionally still — it fits the calm tone.

### Wordmark

The wordmark "ButterBar" is rendered in **SF Pro Display, weight 600**, with no custom letter spacing. Set tight against the icon when paired (icon left, wordmark right, baseline-aligned). No custom-typeset wordmark in v1.

## Window chrome and layout

- **Window style:** macOS Tahoe standard titlebar with toolbar items rendering as Liquid Glass automatically.
- **Sidebar:** uses Tahoe's automatic Liquid Glass sidebar treatment. Selected row uses `butter` background tint at 12% opacity with `cocoa` text.
- **Player window:** dark by default regardless of system appearance. Video looks correct on dark; light-mode player chrome looks amateurish next to most film content.
- **HUD (StreamHealth + controls):** floating glass surface (`.glassEffect(.regular.interactive())`) over the video. Tier colour as a 4 px left border accent.

## App Store / metadata copy

Working drafts. Not final.

- **Tagline:** "Buttery streaming. Native to the Mac."
- **Subtitle (App Store):** "A calm, focused media player for macOS Tahoe."
- **First-run welcome:** "Paste a magnet link or open a torrent file to begin."

## What this spec does not cover

- iOS or iPad layout (no plans).
- Marketing site visuals.
- Onboarding animation sequences (deferred to v1.5+).
- Localisation beyond British English (deferred).
- Promotional materials beyond the app icon and basic wordmark.
- macOS Tahoe platform requirements, deployment targets, SDK requirements — see `09-platform-tahoe.md`.

## Test obligations

- Snapshot tests for tier colour rendering at all three tiers in both light and dark modes.
- Accessibility audit: every tier indicator paired with a text label.
- Icon legibility check: the supplied logo must remain identifiable as the ButterBar mark at 16 × 16 px on a Retina display.
- Liquid Glass placement check: no `.glassEffect()` on content; only on floating navigation chrome.
- Squircle compliance check: the rendered app icon in Finder/Dock must not show a grey squircle jail border.
