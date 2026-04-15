# 01 — Architecture (v1, frozen)

> **Revision 2** — pure-function language replaced (addendum A11); table list corrected to match spec 05 with in-memory note (addendum A12). Baseline revision was rev 1.

## Top-level shape

```
┌─────────────────────────┐
│      SwiftUI App        │
│  (AVPlayerView, Library,│
│   Search, Player UI)    │
└────────────┬────────────┘
             │ NSXPCConnection
             │ (commands + event subscription)
┌────────────▼────────────┐
│      EngineService      │
│                         │
│  ┌───────────────────┐  │
│  │ TorrentBridge     │  │  ObjC++ over libtorrent
│  │ (libtorrent)      │  │
│  └─────────┬─────────┘  │
│            │            │
│  ┌─────────▼─────────┐  │
│  │ PiecePlanner      │  │  pure Swift, testable in isolation
│  └─────────┬─────────┘  │
│            │            │
│  ┌─────────▼─────────┐  │
│  │ PlaybackGateway   │  │  Network.framework, 127.0.0.1 only
│  └─────────┬─────────┘  │
│            │            │
│  ┌─────────▼─────────┐  │
│  │ CacheManager      │  │  piece-granular LRU + pinned set
│  └─────────┬─────────┘  │
│            │            │
│  ┌─────────▼─────────┐  │
│  │ Store (GRDB)      │  │  single writer
│  └───────────────────┘  │
└─────────────────────────┘
              ▲
              │ 127.0.0.1:ephemeral
              │ HTTP Range
┌─────────────┴───────────┐
│      AVPlayer           │  talks directly to engine's gateway
│      (in app process)   │
└─────────────────────────┘
```

## Component responsibilities

### App process

- SwiftUI views and view models.
- `AVPlayerView` wrapped via `NSViewRepresentable`.
- Holds an `NSXPCConnection` to `EngineService`.
- Subscribes to engine events for live UI updates.
- **Does not:** touch SQLite, touch libtorrent, parse torrent files, serve HTTP, manage disk state.

### EngineService process

#### TorrentBridge (ObjC++)

Narrow wrapper over libtorrent. Expose only what the project needs. Target surface area: ~15 methods.

Required methods (minimum):

- `addMagnet(_ magnet: String) -> TorrentHandle`
- `addTorrentFile(_ path: String) -> TorrentHandle`
- `removeTorrent(_ handle: TorrentHandle, deleteData: Bool)`
- `listFiles(_ handle: TorrentHandle) -> [FileEntry]`
- `setFilePriority(_ handle: TorrentHandle, fileIndex: Int, priority: Int)`
- `havePieces(_ handle: TorrentHandle) -> BitSet`
- `setPieceDeadline(_ handle: TorrentHandle, piece: Int, deadlineMs: Int)`
- `clearPieceDeadlines(_ handle: TorrentHandle, exceptPieces: [Int])`
- `statusSnapshot(_ handle: TorrentHandle) -> TorrentStatus`
- `pieceLength(_ handle: TorrentHandle) -> Int64`
- `fileByteRange(_ handle: TorrentHandle, fileIndex: Int) -> (start: Int64, end: Int64)`
- `readBytes(_ handle: TorrentHandle, fileIndex: Int, range: ByteRange) -> Data?`
- `subscribeAlerts(_ callback: (TorrentAlert) -> Void)`

Do **not** expose: peer lists at packet granularity, DHT internals, tracker scrape details, session settings beyond what's needed. These can be added later; they contaminate the API surface now.

#### PiecePlanner (pure Swift)

See `04-piece-planner.md` for full spec. Responsibilities:

- Translate player byte requests into deadline calls.
- Own readahead window policy (time-based, not byte-based).
- Own seek policy (drop old deadlines, set new ones).
- Own cancellation policy (when player drops a request).
- Emit `StreamHealth` updates.

Deterministic state machine driven by `(events, availability schedule, injected time)`. Internal mutable state is permitted but no real clocks, threading, randomness, or I/O. No libtorrent dependency at compile time. See `00-addendum.md` A3.

#### PlaybackGateway

- `Network.framework` `NWListener` bound to `127.0.0.1` on an ephemeral port.
- One gateway per EngineService process, multiple stream sessions inside it.
- Handles HEAD, GET, Range, 206, 416, client disconnect.
- For each incoming request, asks `PiecePlanner.onRangeRequest(...)` and then waits for bytes or times out per the planner's wait policy.
- Serves bytes via `TorrentBridge.readBytes(...)` from the sparse file.
- **Does not:** own piece state, decide priorities, manage deadlines. It is a dumb adapter.

Surface:

```swift
protocol RangeResponder {
    func respond(to request: HTTPRangeRequest) async throws -> HTTPRangeResponse
}
```

#### CacheManager

See `05-cache-policy.md`. Piece-granular LRU with pinned set.

#### Store (GRDB)

- Stock GRDB, system SQLite, no FTS5.
- Persisted tables (per `05-cache-policy.md` § Schema): `playback_history`, `pinned_files`, `settings`. That is the entire persisted v1 schema.
- **In-memory only, not persisted:** active torrent state and resume data (libtorrent owns this on disk via its own resume mechanism), file lists (derived from torrent metadata on demand), stream sessions (ephemeral by definition).
- Single writer: only `EngineService` writes. App has zero direct access.
- All reads exposed as typed DTOs over XPC.

## Cross-cutting rules

1. **No domain types cross the XPC boundary.** DTOs only. See `03-xpc-contract.md`.
2. **The planner never calls libtorrent directly in tests.** It calls a `TorrentSession` protocol; tests supply a fake.
3. **The gateway never computes piece indices.** It asks the planner.
4. **The app never polls.** It subscribes to events and renders what arrives.
5. **The engine never trusts the app.** Every XPC request is validated (`torrentID` exists, `fileIndex` in range, `streamID` still live).

## What v1 explicitly excludes

- Transcoding.
- Sidecar `.srt` subtitle ingestion.
- FTS5 / full-text library search.
- Library sync across devices.
- Remote engine (non-loopback gateway).
- Season pack heuristics beyond showing the file list.
- DLNA, AirPlay output beyond what AVPlayer natively provides.
