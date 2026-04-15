# 09 — Platform (macOS Tahoe)

> **Revision 1** — initial platform spec for the Tahoe targeting decision. See addendum A18. Captures deployment target, SDK requirement, supported hardware, framework versions, and the Liquid Glass adoption stance.

## Summary

ButterBar v1 targets **macOS Tahoe 26.0 and later**. Built with **Xcode 26 (or later) and the macOS 26 SDK**. Apple silicon and supported Intel Macs. Liquid Glass design language adopted natively, not opted out of.

## Deployment target

- **Minimum macOS version:** **macOS 26.0 (Tahoe)**.
- **No support for macOS 15 (Sequoia) or earlier.**

This is a hard floor for v1. Reasons:

1. The Liquid Glass design language requires macOS 26+ to render correctly. Building against an older target would produce a non-Tahoe-native app that immediately reads as out-of-place on the only OS we target.
2. The `.icon` format requires the macOS 26 runtime. Older runtimes use `.icns` and would render the supplied legacy fallback only.
3. The SwiftUI APIs we rely on for the player HUD and sidebar treatment (`.glassEffect`, modernised `NavigationStack` behaviours, `NavigationSplitView` glass sidebar) are macOS 26+.
4. Maintaining backward compatibility with Sequoia adds cross-version test surface for an audience that, by definition, uses an older OS — not the audience we want for v1.

If a v1.5+ business need arises to support macOS 15, it would be a deliberate decision tracked through an addendum item, not a default fallback. The Xcode project should not be configured to allow it implicitly.

## SDK requirement

- **Build with macOS 26 SDK or later.** (Xcode 26+.)
- All targets in the project (`ButterBar` app, `EngineService` XPC service, all Swift packages) use the same SDK.

This aligns with Apple's stated requirement that App Store Connect submissions from April 2026 onwards be built against the iOS 26 / macOS 26 SDK family. We are past that date; building against an older SDK is not a viable shipping option.

## Hardware support

ButterBar inherits Tahoe's hardware support:

- **All Apple silicon Macs** (M1 family and later).
- **Specific Intel Macs only:** Mac Pro (2019), MacBook Pro 16-inch (2019), MacBook Pro 13-inch (2020, four Thunderbolt 3 ports), iMac (2020).

This is the last macOS release supporting Intel hardware. Future versions of macOS will be Apple silicon only. ButterBar's engineering decisions should not assume Intel — performance budgets, threading expectations, and performance benchmarks should be set on Apple silicon and verified to work on the supported Intel models, not the other way around.

There is no runtime branch for "Intel vs. Apple silicon" in v1 code. If one becomes necessary for a libtorrent or codec issue, it lives behind a feature flag, not in the architecture.

## Frameworks and APIs

### SwiftUI

- Full SwiftUI app structure. No AppKit fallback for the main app; AppKit interop only via `NSViewRepresentable` for `AVKit` (per `01-architecture.md`).
- Liquid Glass treatments adopted automatically by recompiling against the macOS 26 SDK — toolbars, sidebars, sheets, popovers, menu bar all get glass without explicit code.
- Manual glass surfaces (HUD only — see `06-brand.md`) use `.glassEffect(.regular.interactive())`.

### AVKit / AVFoundation

- `AVPlayer` and `AVPlayerView` per `01-architecture.md`. Tahoe doesn't change the playback APIs in any breaking way for v1.
- `AVAssetResourceLoaderDelegate` remains the v2 alternative to the loopback HTTP gateway, unchanged.

### Network framework

- `NWListener` for the loopback HTTP gateway per `01-architecture.md`. Unchanged in Tahoe.

### NSXPCConnection

- Per `03-xpc-contract.md`. Unchanged in Tahoe. The XPC bundle layout in Xcode 26 is the same as Xcode 16; no migration work needed.

### Foundation Models (Apple Intelligence)

- **Not used in v1.** Tahoe ships the Foundation Models framework as a system-level Apple Intelligence layer, but ButterBar has no v1 feature that requires on-device LLM inference. Out of scope for v1; revisit for recommendations or summarisation in v1.5+.

### Phone / Continuity

- **Not used in v1.** Tahoe brings iPhone calling and Continuity features to the Mac; irrelevant to a media player.

## Liquid Glass adoption stance

**Adopted.** Not opted out.

ButterBar v1 ships with Liquid Glass enabled. We do **not** set `UIDesignRequiresCompatibility = YES` in `Info.plist` (the temporary opt-out flag Apple provides for apps that need more migration time).

The brand spec (06) governs *where* glass is used (floating navigation only, never content). The platform spec (this file) governs *whether* glass is used (yes, in v1, by default).

If a build-blocking issue arises during development that forces a temporary opt-out, the flag may be set on a development branch only, and the relevant addendum item (A19+) must record the reason and the tracking issue for re-enabling glass.

## Icon format

Per `06-brand.md` § Tahoe icon workflow, the primary icon format is `.icon` (Tahoe-native, authored in Apple's Icon Composer tool from the supplied Liquid Glass prep package). The `AppIcon.icon` bundle lives at `App/AppIcon.icon` — at the **same level as `Assets.xcassets`**, not inside it. This matches Apple's documented Xcode integration path.

The legacy `.icns` and `.iconset/` are bundled in `icons/` as inactive insurance, in case a future addendum lowers the deployment target below 26.

## Code-signing and notarisation

- **Hardened runtime:** required.
- **App Sandbox:** enabled. The XPC service inherits the same sandbox model. Specific entitlements: network client (for libtorrent), user-selected file access (for opening `.torrent` files), Keychain access (for OAuth tokens — module 5).
- **Notarisation:** required for distribution outside the Mac App Store. Even Mac App Store builds benefit from Apple's notarisation pipeline.
- **Developer ID:** Matt Kneale's Developer ID Application certificate. Stored as a GitHub Actions secret for release builds.

## CI considerations

- macOS 26 runners required (`macos-26` GitHub Actions image once stable; `macos-latest` aliases there once Apple promotes it).
- Xcode 26 selected explicitly via `xcversion select 26.x` or the GitHub Actions `xcode-version` input.
- The current CI workflow (`.github/workflows/ci.yml`) is a placeholder; it expands as engine packages come online per `TASKS.md` Phase 0–2.

## What this spec does not cover

- Application code style — see `.claude/agents/sonnet-implementer.md`.
- Brand visual identity — see `06-brand.md`.
- Release process / versioning — defer to a future `10-release.md` written before v1 tag is cut.

## Test obligations

- Build-time check that the macOS deployment target is `26.0` or later. Failing this check blocks merge.
- Build-time check that `UIDesignRequiresCompatibility` is not set in `Info.plist`.
- Manual smoke test on at least one Apple silicon Mac and one supported Intel Mac before each release.
- Visual check that the toolbar, sidebar, sheets, and HUD all render with Liquid Glass treatment in the running app.
