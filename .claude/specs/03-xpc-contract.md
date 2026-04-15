# 03 — XPC Contract

> **Revision 3** — v1.1 watched-seconds reporting method anchored in exclusion list (review finding F6). Rev 2 introduced request-versioning clarification to responses/events only (addendum A1) and `ByteRangeDTO` (addendum A8). Baseline revision was rev 1.

The XPC boundary is the most expensive mistake to make. This spec is narrow on purpose. Every method added here becomes a compatibility promise.

## Connection model

- `NSXPCConnection` between app (client) and `EngineService` (server).
- Server side exports `EngineXPC`. Client side exports `EngineEvents` as a remote object for event callbacks.
- App holds one connection for the lifetime of the app. On invalidation, reconnect and re-`subscribe`.
- Engine holds client proxy **weakly** and re-validates on every event emission. The engine must survive client death without leaking or blocking.
- Harden with a code-signing requirement on the connection (`NSXPCConnection.setCodeSigningRequirement(_:)`) once the service bundle is signed.

## DTO layer

All types crossing XPC are `NSObject` + `NSSecureCoding`, separate from internal Swift domain types. Mapping happens on both sides at the XPC boundary and nowhere else.

Rules:

- Every **response or event** DTO is versioned. Request methods in v1 use raw `NSString`/`NSNumber` parameters directly and are not versioned — see Versioning section below.
- Every DTO class declares `supportsSecureCoding = true`.
- Every DTO class overrides `encode(with:)` and `init?(coder:)` explicitly. No `Codable` bridging across XPC.
- Every field is an `@objc`-safe type: `NSString`, `NSNumber`, `NSArray`, `NSDictionary`, `NSData`, primitives, other DTOs.
- Every top-level **response/event** DTO carries a `schemaVersion: Int32` field. Clients may reject replies whose `schemaVersion` they don't understand.
- Decode with explicit `allowedClasses` — never `decodeObject(forKey:)` without a class list.

## Protocols (v1, frozen)

```swift
@objc public protocol EngineXPC {
    // Torrent lifecycle
    func addMagnet(_ magnet: String,
                   reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void)

    func addTorrentFile(_ bookmarkData: NSData,
                        reply: @escaping (TorrentSummaryDTO?, NSError?) -> Void)

    func listTorrents(_ reply: @escaping ([TorrentSummaryDTO]) -> Void)

    func removeTorrent(_ torrentID: NSString,
                       deleteData: Bool,
                       reply: @escaping (NSError?) -> Void)

    // File selection
    func listFiles(_ torrentID: NSString,
                   reply: @escaping ([TorrentFileDTO], NSError?) -> Void)

    func setWantedFiles(_ torrentID: NSString,
                        fileIndexes: [NSNumber],
                        reply: @escaping (NSError?) -> Void)

    // Stream lifecycle
    func openStream(_ torrentID: NSString,
                    fileIndex: NSNumber,
                    reply: @escaping (StreamDescriptorDTO?, NSError?) -> Void)

    func closeStream(_ streamID: NSString,
                     reply: @escaping () -> Void)

    // Event subscription
    func subscribe(_ client: EngineEvents,
                   reply: @escaping (NSError?) -> Void)
}

@objc public protocol EngineEvents {
    func torrentUpdated(_ snapshot: TorrentSummaryDTO)
    func fileAvailabilityChanged(_ update: FileAvailabilityDTO)
    func streamHealthChanged(_ update: StreamHealthDTO)
    func diskPressureChanged(_ update: DiskPressureDTO)
}
```

## DTO definitions (v1)

### TorrentSummaryDTO

```swift
@objc(TorrentSummaryDTO)
public final class TorrentSummaryDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32          // = 1
    public let torrentID: NSString
    public let name: NSString
    public let totalBytes: Int64
    public let progressQ16: Int32            // fixed-point [0, 65536]
    public let state: NSString               // "queued"|"checking"|"downloading"|"seeding"|"error"
    public let peerCount: Int32
    public let downRateBytesPerSec: Int64
    public let upRateBytesPerSec: Int64
    public let errorMessage: NSString?
}
```

### TorrentFileDTO

```swift
@objc(TorrentFileDTO)
public final class TorrentFileDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32          // = 1
    public let fileIndex: Int32
    public let path: NSString                // relative within torrent
    public let sizeBytes: Int64
    public let mimeTypeHint: NSString?       // best-effort, may be nil
    public let isPlayableByAVFoundation: Bool  // engine-side heuristic
}
```

### StreamDescriptorDTO

```swift
@objc(StreamDescriptorDTO)
public final class StreamDescriptorDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32          // = 1
    public let streamID: NSString
    public let loopbackURL: NSString         // "http://127.0.0.1:PORT/stream/{streamID}"
    public let contentType: NSString         // e.g. "video/mp4"
    public let contentLength: Int64
}
```

### ByteRangeDTO

```swift
@objc(ByteRangeDTO)
public final class ByteRangeDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let startByte: Int64   // inclusive
    public let endByte: Int64     // inclusive
}
```

Used inside other DTOs wherever a byte range needs to cross the boundary. Not top-level, so no `schemaVersion` field — it rides the version of the parent DTO.

### FileAvailabilityDTO

```swift
@objc(FileAvailabilityDTO)
public final class FileAvailabilityDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32          // = 1
    public let torrentID: NSString
    public let fileIndex: Int32
    // Byte ranges fully downloaded, coalesced.
    public let availableRanges: [ByteRangeDTO]
}
```

### StreamHealthDTO

```swift
@objc(StreamHealthDTO)
public final class StreamHealthDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32          // = 1
    public let streamID: NSString
    public let secondsBufferedAhead: Double
    public let downloadRateBytesPerSec: Int64
    public let requiredBitrateBytesPerSec: NSNumber?   // nil until known
    public let peerCount: Int32
    public let outstandingCriticalPieces: Int32
    public let recentStallCount: Int32
    public let tier: NSString                // "healthy"|"marginal"|"starving"
}
```

### DiskPressureDTO

```swift
@objc(DiskPressureDTO)
public final class DiskPressureDTO: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let schemaVersion: Int32          // = 1
    public let totalBudgetBytes: Int64
    public let usedBytes: Int64
    public let pinnedBytes: Int64
    public let evictableBytes: Int64
    public let level: NSString               // "ok"|"warn"|"critical"
}
```

## Error handling

- All reply blocks that can fail take an optional `NSError`.
- Error domain: `"com.butterbar.engine"`.
- Error codes enumerated in `EngineErrorCode.swift` and kept in sync with the DTO layer.

## What is explicitly not in the v1 XPC contract

- Per-piece progress streaming (too chatty; use `FileAvailabilityDTO` instead).
- Peer list inspection.
- Tracker control.
- Engine settings (bandwidth limits, port config) — add in v1.1 if needed.
- App→engine watched-seconds reporting (planned for v1.1; the `total_watched_seconds` column in `playback_history` exists but stays at 0 in v1 — see `05-cache-policy.md` § Update rules).
- Any synchronous blocking query deeper than a snapshot read.

## Versioning

- v1 contract is frozen. Additions go to v2.
- **Only response and event DTOs are versioned in v1.** Request methods take raw typed parameters (`NSString`, `NSNumber`, etc.) directly; their compatibility is tied to the method signature rather than a DTO field.
- v2 response/event DTOs must either extend v1 DTOs by subclassing with a new `schemaVersion`, or introduce new DTO types entirely. Never mutate v1 DTO fields.
- **Adding a new request method** in v2 is backward-compatible (v1 clients simply don't call it).
- **Changing the signature of an existing request method** is a breaking change and requires a contract bump. In v1 this is forbidden.
- Request-side DTOs with `schemaVersion` fields may be introduced in v2 if request compatibility becomes a practical concern.
- **Multi-schema runtime support is a future expectation, not a v1 commitment.** v1 supports exactly schema v1 at runtime. Cross-version compatibility logic (e.g. engine accepting both v1 and v2 DTOs simultaneously) is deferred until there is a second schema to support.

## Test obligations

- `NSSecureCoding` round-trip test for every DTO with every field exercised (including nils where permitted).
- Contract test that encodes each DTO, writes to disk, and decodes with `allowedClasses` — this catches `init?(coder:)` mistakes that silently drop fields.
- Connection lifecycle test: client dies, engine survives, client reconnects, re-subscribes, receives events.
