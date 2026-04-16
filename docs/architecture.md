# ButterBar Architecture

Last updated: 2026-04-16.

This document describes the shipped v1 architecture as it exists after Phase 7 hardening. The frozen source spec remains `.claude/specs/01-architecture.md`; this file is the contributor-facing map of the implementation.

## Top-Level Shape

```text
SwiftUI app
  LibraryView, PlayerView, AVPlayerView
        |
        | NSXPCConnection
        v
EngineService.xpc
  EngineXPCServer
  RealEngineBackend
        |
        +-- TorrentBridge          ObjC++ wrapper over libtorrent-rasterbar
        +-- AlertDispatcher        libtorrent alerts -> EngineEvents DTOs
        +-- StreamRegistry         stream IDs -> playback sessions
        +-- PlaybackGateway        127.0.0.1 HTTP range server
        +-- DefaultPiecePlanner    deterministic piece deadlines and health
        +-- CacheManager           GRDB-backed history, pinned files, eviction
        |
        v
AVPlayer in the app consumes the loopback HTTP URL returned by EngineService.
```

## Process Boundary

The app owns UI only. It never touches SQLite, libtorrent, torrent metadata parsing, or loopback HTTP serving directly. All engine access goes through `EngineClient`, which wraps `NSXPCConnection` calls in Swift concurrency continuations with per-call proxy error handlers.

The XPC service owns all mutable engine state. `EngineXPCServer` delegates to `RealEngineBackend`, which owns `TorrentBridge`, `StreamRegistry`, `GatewayListener`, `CacheManager`, and `AlertDispatcher`.

Both sides set XPC code-signing requirements for the current development team. If the team identifier changes, update the requirement strings in `App/Shared/EngineClient.swift`, `EngineService/EngineServiceMain.swift`, and `EngineService/XPC/XPCCodesignSelfTest.swift`.

## Streaming Path

```text
LibraryView.openStream
        |
EngineClient.openStream
        |
EngineXPCServer -> RealEngineBackend
        |
StreamRegistry creates PlaybackSession
        |
GatewayListener returns http://127.0.0.1:<port>/stream/<streamID>
        |
AVPlayer issues HEAD/GET Range requests
        |
PlaybackSession maps requests to PlayerEvent
        |
DefaultPiecePlanner emits deadlines and wait policy
        |
TorrentBridge sets libtorrent deadlines and reads sparse-file bytes
```

Planner access is serialized inside `PlaybackSession`; the planner remains a deterministic mutable state machine with injected time and a `TorrentSessionView` protocol. Tests use fakes and trace fixtures rather than libtorrent.

## Event Path

`TorrentBridge.subscribeAlerts` drains relevant libtorrent alerts into dictionaries. `TorrentAlert.from(_:)` is the typed parser boundary. `AlertDispatcher` converts typed alerts into `EngineEvents` calls such as `torrentUpdated` and `fileAvailabilityChanged`.

Piece indexes are optional when they come from alert dictionaries. Missing values are represented as `nil`, never `-1`, so future piece math cannot accidentally use a sentinel as a real piece index. `hash_failed_alert` is also typed, even though the eviction design no longer depends on hash-failed alerts.

## Persistence

The v1 persistent store is GRDB over system SQLite, owned by EngineService only. Persisted tables are:

- `playback_history`
- `pinned_files`
- `settings`

Active torrent state, file lists, and stream sessions are not app-owned persistent data. They are either libtorrent-managed, derived from torrent metadata, or process-ephemeral.

## CI And Dependencies

CI installs `libtorrent-rasterbar` with Homebrew before Xcode snapshot tests. The Xcode project uses Homebrew `opt` symlinks:

- `/opt/homebrew/opt/libtorrent-rasterbar/include`
- `/opt/homebrew/opt/libtorrent-rasterbar/lib`

Do not pin versioned Homebrew Cellar paths in project settings; Homebrew formula updates must not silently break CI.

## Tried And Rejected

- Synthetic `TorrentBridge.createTestTorrent` self-tests were dropped for runtime proof because sandboxed synthetic torrents were unreliable. Real-magnet self-tests now cover the bridge and gateway paths.
- The cache-eviction hot path based on `add_piece(zeros, overwrite_existing) -> hash_failed_alert -> F_PUNCHHOLE` was rejected after probe runs showed libtorrent 2.0.12 does not emit those alerts for that path. Eviction uses force-recheck/status transitions instead.
- Version-pinned Homebrew Cellar search paths were replaced by `opt` symlinks for CI and local upgrade resilience.
- Product-surface library features such as watched-seconds history, watched-state transitions, and favourites remain GitHub issue work requiring spec 07 design input, not mechanical engine hardening.
