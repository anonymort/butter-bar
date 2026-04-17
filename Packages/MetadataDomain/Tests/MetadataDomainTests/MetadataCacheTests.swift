import XCTest
@testable import MetadataDomain

final class MetadataCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("MetadataCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        tempDir = base
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        tempDir = nil
    }

    // MARK: - Basic round-trip

    func test_storeAndLookup_freshHit() throws {
        let cache = try MetadataCache(baseDirectory: tempDir)
        let url = URL(string: "https://api.themoviedb.org/3/movie/1668")!
        try cache.store(url: url, data: Data("{\"id\":1668}".utf8), ttl: 60)

        let hit = try XCTUnwrap(cache.lookup(url: url))
        XCTAssertEqual(hit.freshness, .fresh)
        XCTAssertEqual(String(data: hit.data, encoding: .utf8), "{\"id\":1668}")
    }

    func test_lookup_missingURL_returnsNil() throws {
        let cache = try MetadataCache(baseDirectory: tempDir)
        XCTAssertNil(cache.lookup(url: URL(string: "https://example.com/missing")!))
    }

    // MARK: - TTL expiry (injected clock)

    func test_lookup_pastExpiry_returnsStale() throws {
        let instant = MutableInstant(Date(timeIntervalSince1970: 1_000_000))
        let clock = CacheClock(now: { instant.value })
        let cache = try MetadataCache(baseDirectory: tempDir, clock: clock)
        let url = URL(string: "https://api.themoviedb.org/3/trending/movie/week")!
        try cache.store(url: url, data: Data("{\"results\":[]}".utf8), ttl: 60)

        // 30 s later — still fresh.
        instant.advance(by: 30)
        let fresh = try XCTUnwrap(cache.lookup(url: url))
        XCTAssertEqual(fresh.freshness, .fresh)

        // 90 s later — stale.
        instant.advance(by: 60)
        let stale = try XCTUnwrap(cache.lookup(url: url))
        XCTAssertEqual(stale.freshness, .stale)
    }

    // MARK: - Stale-while-revalidate

    func test_staleEntry_thenStore_returnsFresh() throws {
        let instant = MutableInstant(Date(timeIntervalSince1970: 2_000_000))
        let clock = CacheClock(now: { instant.value })
        let cache = try MetadataCache(baseDirectory: tempDir, clock: clock)
        let url = URL(string: "https://api.themoviedb.org/3/trending/movie/week")!
        try cache.store(url: url, data: Data("{\"v\":1}".utf8), ttl: 60)

        // Walk past expiry → stale.
        instant.advance(by: 120)
        XCTAssertEqual(cache.lookup(url: url)?.freshness, .stale)

        // Background fetch completes → store fresh data.
        try cache.store(url: url, data: Data("{\"v\":2}".utf8), ttl: 60)
        let fresh = try XCTUnwrap(cache.lookup(url: url))
        XCTAssertEqual(fresh.freshness, .fresh)
        XCTAssertEqual(String(data: fresh.data, encoding: .utf8), "{\"v\":2}")
    }

    // MARK: - Atomic write

    func test_store_isAtomic_noStaleTmpLeftBehind() throws {
        let cache = try MetadataCache(baseDirectory: tempDir)
        let url = URL(string: "https://api.themoviedb.org/3/movie/1")!
        try cache.store(url: url, data: Data("{\"id\":1}".utf8), ttl: 60)

        let responses = tempDir.appendingPathComponent("responses")
        let entries = try FileManager.default.contentsOfDirectory(at: responses,
                                                                  includingPropertiesForKeys: nil)
        XCTAssertFalse(entries.contains(where: { $0.pathExtension == "tmp" }))
    }

    // MARK: - Corrupt-read fallback

    func test_corruptPayload_treatsAsMiss() throws {
        let cache = try MetadataCache(baseDirectory: tempDir)
        let url = URL(string: "https://api.themoviedb.org/3/movie/1")!
        try cache.store(url: url, data: Data("{\"id\":1}".utf8), ttl: 60)

        // Hand-corrupt the payload file.
        let responses = tempDir.appendingPathComponent("responses")
        let payload = try FileManager.default.contentsOfDirectory(at: responses,
                                                                  includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "json" })!
        try Data("not-valid-json".utf8).write(to: payload)

        XCTAssertNil(cache.lookup(url: url), "Corrupt payload should be treated as cache-miss.")
    }

    func test_corruptPayload_isPurgedOnNextLookup() throws {
        let cache = try MetadataCache(baseDirectory: tempDir)
        let url = URL(string: "https://api.themoviedb.org/3/movie/1")!
        try cache.store(url: url, data: Data("{\"id\":1}".utf8), ttl: 60)

        let responses = tempDir.appendingPathComponent("responses")
        let payload = try FileManager.default.contentsOfDirectory(at: responses,
                                                                  includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "json" })!
        try Data("garbage".utf8).write(to: payload)

        _ = cache.lookup(url: url)
        // After purge, the response file should be gone.
        let after = try FileManager.default.contentsOfDirectory(at: responses,
                                                                includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertTrue(after.isEmpty)
    }

    // MARK: - ETag round-trip

    func test_etag_isPersistedAndReturnedByLookup() throws {
        let cache = try MetadataCache(baseDirectory: tempDir)
        let url = URL(string: "https://api.themoviedb.org/3/movie/1668")!
        try cache.store(url: url,
                        data: Data("{\"id\":1668}".utf8),
                        ttl: 60,
                        etag: "\"abc123\"",
                        lastModified: "Thu, 01 Jan 2026 00:00:00 GMT")

        let hit = try XCTUnwrap(cache.lookup(url: url))
        XCTAssertEqual(hit.meta.etag, "\"abc123\"")
        XCTAssertEqual(hit.meta.lastModified, "Thu, 01 Jan 2026 00:00:00 GMT")
    }

    func test_etag_persistsAcrossCacheReinstantiation() throws {
        let url = URL(string: "https://api.themoviedb.org/3/movie/1668")!
        do {
            let cache = try MetadataCache(baseDirectory: tempDir)
            try cache.store(url: url,
                            data: Data("{\"id\":1668}".utf8),
                            ttl: 60,
                            etag: "\"def456\"")
        }

        let cache2 = try MetadataCache(baseDirectory: tempDir)
        let hit = try XCTUnwrap(cache2.lookup(url: url))
        XCTAssertEqual(hit.meta.etag, "\"def456\"")
    }

    func test_touch_updatesTTLWithoutRewritingPayload() throws {
        let instant = MutableInstant(Date(timeIntervalSince1970: 3_000_000))
        let clock = CacheClock(now: { instant.value })
        let cache = try MetadataCache(baseDirectory: tempDir, clock: clock)
        let url = URL(string: "https://api.themoviedb.org/3/movie/1")!
        try cache.store(url: url, data: Data("{\"v\":1}".utf8), ttl: 60, etag: "\"old\"")

        // Walk past expiry → stale.
        instant.advance(by: 120)
        XCTAssertEqual(cache.lookup(url: url)?.freshness, .stale)

        // Server says 304 Not Modified — touch with new TTL + same etag.
        cache.touch(url: url, ttl: 60, etag: "\"old\"")
        let hit = try XCTUnwrap(cache.lookup(url: url))
        XCTAssertEqual(hit.freshness, .fresh)
        XCTAssertEqual(String(data: hit.data, encoding: .utf8), "{\"v\":1}",
                       "Payload should be unchanged after touch.")
    }

    // MARK: - clearAll

    func test_clearAll_removesEverything() throws {
        let cache = try MetadataCache(baseDirectory: tempDir)
        let url = URL(string: "https://example.com/x")!
        try cache.store(url: url, data: Data("{\"a\":1}".utf8), ttl: 60)
        try cache.clearAll()
        XCTAssertNil(cache.lookup(url: url))
    }
}

/// Sendable mutable date for `CacheClock` injection in tests.
final class MutableInstant: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Date

    init(_ initial: Date) { self._value = initial }

    var value: Date {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _value = _value.addingTimeInterval(seconds)
    }
}
