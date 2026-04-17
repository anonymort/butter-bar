import Foundation

/// Per-entry sidecar metadata stored alongside a cached response. Persisted
/// to `cache_meta.json` (one map keyed by canonical URL) so a single read
/// hydrates the entire TTL/ETag table.
public struct MetadataCacheEntryMeta: Equatable, Sendable, Codable {
    public let etag: String?
    public let lastModified: String?
    /// Wall-clock instant the response was first written.
    public let fetchedAt: Date
    /// Wall-clock instant past which the entry is stale.
    public let expiresAt: Date

    public init(etag: String?,
                lastModified: String?,
                fetchedAt: Date,
                expiresAt: Date) {
        self.etag = etag
        self.lastModified = lastModified
        self.fetchedAt = fetchedAt
        self.expiresAt = expiresAt
    }
}

/// Lookup result for a cache hit.
public struct MetadataCacheHit: Equatable, Sendable {
    public enum Freshness: Sendable, Equatable { case fresh, stale }
    public let data: Data
    public let freshness: Freshness
    public let meta: MetadataCacheEntryMeta
}

/// Injectable wall-clock; tests substitute a fixed-time clock. Pure layer
/// over `Date()`; nothing else relies on `Date.init`.
public struct CacheClock: Sendable {
    public var now: @Sendable () -> Date
    public init(now: @escaping @Sendable () -> Date) { self.now = now }
    public static let system = CacheClock(now: { Date() })
}

/// On-disk JSON cache for TMDB responses. Atomic writes (via `.tmp` + rename),
/// corrupt-read fallback, ETag/Last-Modified round-trip. The cache itself
/// does not perform network I/O — callers consult it before a fetch and
/// write the response back after.
///
/// Stale-while-revalidate flow:
///   1. `lookup(url:)` → `.stale(...)` ⇒ caller renders the stale data
///      immediately, kicks off a background fetch, and `store(...)`s the
///      fresh result when ready.
///   2. `lookup(url:)` → `.fresh(...)` ⇒ caller renders directly; no fetch.
///   3. Miss ⇒ caller fetches, then `store(...)`s.
public final class MetadataCache: @unchecked Sendable {
    public let baseDirectory: URL
    private let responsesDirectory: URL
    private let metaURL: URL
    private let clock: CacheClock
    private let lock = NSLock()
    private var meta: [String: MetadataCacheEntryMeta]

    /// Standard sandbox path: `~/Library/Application Support/ButterBar/metadata/`.
    public static func defaultBaseDirectory() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
        return appSupport.appendingPathComponent("ButterBar/metadata", isDirectory: true)
    }

    public init(baseDirectory: URL,
                clock: CacheClock = .system) throws {
        self.baseDirectory = baseDirectory
        self.responsesDirectory = baseDirectory.appendingPathComponent("responses", isDirectory: true)
        self.metaURL = baseDirectory.appendingPathComponent("cache_meta.json")
        self.clock = clock

        let fm = FileManager.default
        try fm.createDirectory(at: responsesDirectory, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: metaURL),
           let parsed = try? JSONDecoder.iso8601.decode([String: MetadataCacheEntryMeta].self, from: data) {
            self.meta = parsed
        } else {
            self.meta = [:]
        }
    }

    // MARK: - Public API

    /// Inspect the cache without touching the network. A return of `nil`
    /// means "miss"; callers should fetch + store. A `.stale` return is
    /// usable but the caller should kick off a background refresh.
    public func lookup(url: URL) -> MetadataCacheHit? {
        lock.lock(); defer { lock.unlock() }
        let key = canonicalKey(for: url)
        guard let entryMeta = meta[key] else { return nil }
        let path = responseFile(for: key)
        guard let data = try? Data(contentsOf: path) else {
            // Corrupt or missing payload; treat as miss.
            meta.removeValue(forKey: key)
            try? FileManager.default.removeItem(at: path)
            persistMetaLocked()
            return nil
        }
        // Validate JSON structure on read so a half-written file doesn't
        // poison downstream decoding. The cache itself is JSON-shape-agnostic
        // beyond "must parse"; concrete decoding happens in callers.
        guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
            meta.removeValue(forKey: key)
            try? FileManager.default.removeItem(at: path)
            persistMetaLocked()
            return nil
        }
        let now = clock.now()
        let freshness: MetadataCacheHit.Freshness = (entryMeta.expiresAt > now) ? .fresh : .stale
        return MetadataCacheHit(data: data, freshness: freshness, meta: entryMeta)
    }

    /// Store (or overwrite) a cache entry. Atomic write via `.tmp` + rename.
    public func store(url: URL,
                      data: Data,
                      ttl: TimeInterval,
                      etag: String? = nil,
                      lastModified: String? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        let key = canonicalKey(for: url)
        let path = responseFile(for: key)
        let tmp = path.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        // Replace if exists; rename is atomic on the same volume.
        if FileManager.default.fileExists(atPath: path.path) {
            _ = try FileManager.default.replaceItemAt(path, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: path)
        }
        let now = clock.now()
        meta[key] = MetadataCacheEntryMeta(
            etag: etag,
            lastModified: lastModified,
            fetchedAt: now,
            expiresAt: now.addingTimeInterval(max(0, ttl))
        )
        persistMetaLocked()
    }

    /// Update sidecar TTL/ETag without rewriting the payload — for `304 Not
    /// Modified` responses where the body is unchanged.
    public func touch(url: URL,
                      ttl: TimeInterval,
                      etag: String? = nil,
                      lastModified: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        let key = canonicalKey(for: url)
        guard meta[key] != nil else { return }
        let now = clock.now()
        meta[key] = MetadataCacheEntryMeta(
            etag: etag ?? meta[key]?.etag,
            lastModified: lastModified ?? meta[key]?.lastModified,
            fetchedAt: now,
            expiresAt: now.addingTimeInterval(max(0, ttl))
        )
        persistMetaLocked()
    }

    public func remove(url: URL) {
        lock.lock(); defer { lock.unlock() }
        let key = canonicalKey(for: url)
        meta.removeValue(forKey: key)
        try? FileManager.default.removeItem(at: responseFile(for: key))
        persistMetaLocked()
    }

    public func clearAll() throws {
        lock.lock(); defer { lock.unlock() }
        meta.removeAll()
        try? FileManager.default.removeItem(at: responsesDirectory)
        try FileManager.default.createDirectory(at: responsesDirectory,
                                                withIntermediateDirectories: true)
        persistMetaLocked()
    }

    // MARK: - Internals

    private func responseFile(for key: String) -> URL {
        responsesDirectory.appendingPathComponent("\(key).json")
    }

    /// Canonical key: SHA-style stable hash of URL.absoluteString. We use a
    /// hex digest of the host + path + query to keep filenames safe across
    /// macOS file systems (no slashes, no colons).
    private func canonicalKey(for url: URL) -> String {
        let s = url.absoluteString
        // Lightweight FNV-1a 64-bit hash. Collisions across the few hundred
        // URLs the app sees are vanishingly unlikely; we don't need crypto.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016x", hash)
    }

    private func persistMetaLocked() {
        guard let data = try? JSONEncoder.iso8601.encode(meta) else { return }
        let tmp = metaURL.appendingPathExtension("tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: metaURL.path) {
                _ = try FileManager.default.replaceItemAt(metaURL, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: metaURL)
            }
        } catch {
            // Persistence failure is non-fatal — the next write retries.
        }
    }
}

extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
