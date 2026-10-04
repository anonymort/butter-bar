import XCTest
import MetadataDomain
import ProviderDomain
@testable import ButterBar

final class JackettProviderTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RecordingURLProtocol.reset()
    }

    override func tearDown() {
        RecordingURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - testSearch_movie_parsesTorznabFixture

    func testSearch_movie_parsesTorznabFixture() async throws {
        RecordingURLProtocol.responseData = torznabMovieFixture
        let session = Self.makeSession()
        let provider = JackettProvider(
            baseURL: URL(string: "http://localhost:9117")!,
            apiKey: "secret",
            session: session
        )

        let results = try await provider.search(
            for: .movie(makeMovie(title: "Blade Runner 2049", tmdbID: 335984, imdbID: "tt1856101")),
            page: 1
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.providerName == "Jackett" })
        XCTAssertTrue(results.allSatisfy { $0.id.hasPrefix("jackett:") })

        // First item: magnet + torznab attrs (seeders, peers, size, infohash).
        let first = results[0]
        XCTAssertEqual(first.infoHash, "aaaabbbbccccdddd1111222233334444aaaabbbb")
        XCTAssertEqual(first.seeders, 123)
        XCTAssertEqual(first.leechers, 12)
        XCTAssertEqual(first.sizeBytes, 2_147_483_648)
        XCTAssertNotNil(first.magnetURI)
        XCTAssertEqual(first.quality, .bluRay) // "1080p" in title

        // Second item: .torrent URL via enclosure, size parsed from <size>.
        let second = results[1]
        XCTAssertNotNil(second.torrentURL)
        XCTAssertNil(second.magnetURI)
        XCTAssertEqual(second.quality, .remux) // "2160p" in title
        XCTAssertEqual(second.sizeBytes, 9_876_543_210)
    }

    // MARK: - testSearch_movie_usesCategory2000

    func testSearch_movie_usesCategory2000() async throws {
        RecordingURLProtocol.responseData = emptyRSSFixture
        let session = Self.makeSession()
        let provider = JackettProvider(
            baseURL: URL(string: "http://localhost:9117")!,
            apiKey: "secret",
            session: session
        )

        _ = try await provider.search(
            for: .movie(makeMovie(title: "Arrival", tmdbID: 329865, imdbID: "tt2543164")),
            page: 1
        )

        let last = try XCTUnwrap(RecordingURLProtocol.lastRequestURL)
        let items = URLComponents(url: last, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "cat" })?.value, "2000")
        XCTAssertEqual(items.first(where: { $0.name == "t" })?.value, "search")
        XCTAssertEqual(items.first(where: { $0.name == "apikey" })?.value, "secret")
        XCTAssertEqual(items.first(where: { $0.name == "q" })?.value, "Arrival")
        // TMDb + IMDb ID should ride along for indexers that support them.
        XCTAssertEqual(items.first(where: { $0.name == "tmdbid" })?.value, "329865")
        XCTAssertEqual(items.first(where: { $0.name == "imdbid" })?.value, "2543164")
    }

    // MARK: - testSearch_show_usesCategory5000AndIDs

    func testSearch_show_usesCategory5000AndIDs() async throws {
        RecordingURLProtocol.responseData = emptyRSSFixture
        let session = Self.makeSession()
        let provider = JackettProvider(
            baseURL: URL(string: "http://localhost:9117")!,
            apiKey: "secret",
            session: session
        )

        _ = try await provider.search(
            for: .show(makeShow(name: "Severance", tmdbID: 95396, imdbID: "tt11280740")),
            page: 1
        )

        let last = try XCTUnwrap(RecordingURLProtocol.lastRequestURL)
        let items = URLComponents(url: last, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "cat" })?.value, "5000")
        XCTAssertEqual(items.first(where: { $0.name == "q" })?.value, "Severance")
        XCTAssertEqual(items.first(where: { $0.name == "tmdbid" })?.value, "95396")
        XCTAssertEqual(items.first(where: { $0.name == "imdbid" })?.value, "11280740")
    }

    // MARK: - testSearch_movie_omitsImdbParamWhenUnknown

    func testSearch_movie_omitsImdbParamWhenUnknown() async throws {
        RecordingURLProtocol.responseData = emptyRSSFixture
        let session = Self.makeSession()
        let provider = JackettProvider(
            baseURL: URL(string: "http://localhost:9117")!,
            apiKey: "secret",
            session: session
        )

        _ = try await provider.search(
            for: .movie(makeMovie(title: "No Imdb Id", tmdbID: 42, imdbID: nil)),
            page: 1
        )

        let last = try XCTUnwrap(RecordingURLProtocol.lastRequestURL)
        let items = URLComponents(url: last, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first(where: { $0.name == "tmdbid" })?.value, "42")
        XCTAssertNil(items.first(where: { $0.name == "imdbid" }))
    }

    // MARK: - testSearch_offline_surfacesNetworkError

    func testSearch_offline_surfacesNetworkError() async {
        RecordingURLProtocol.simulatedError = URLError(.cannotConnectToHost)
        let session = Self.makeSession()
        let provider = JackettProvider(
            baseURL: URL(string: "http://localhost:9117")!,
            apiKey: "secret",
            session: session
        )

        do {
            _ = try await provider.search(
                for: .movie(makeMovie(title: "Dune", tmdbID: 438631, imdbID: nil)),
                page: 1
            )
            XCTFail("Expected network error")
        } catch let error as MediaProviderError {
            guard case .networkError = error else {
                XCTFail("Expected .networkError, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected MediaProviderError, got \(error)")
        }
    }

    // MARK: - testSearch_authRejection_surfacesAuthRequired

    func testSearch_authRejection_surfacesAuthRequired() async {
        RecordingURLProtocol.responseData = Data()
        RecordingURLProtocol.responseStatusCode = 403
        let session = Self.makeSession()
        let provider = JackettProvider(
            baseURL: URL(string: "http://localhost:9117")!,
            apiKey: "bad-key",
            session: session
        )

        do {
            _ = try await provider.search(
                for: .movie(makeMovie(title: "Anything", tmdbID: 1, imdbID: nil)),
                page: 1
            )
            XCTFail("Expected auth error")
        } catch let error as MediaProviderError {
            XCTAssertEqual(error.localizedDescription, MediaProviderError.authRequired.localizedDescription)
        } catch {
            XCTFail("Expected MediaProviderError, got \(error)")
        }
    }

    // MARK: - testNormaliseIMDb_stripsPrefix

    func testNormaliseIMDb_stripsPrefix() {
        XCTAssertEqual(JackettProvider.normaliseIMDbID("tt1856101"), "1856101")
        XCTAssertEqual(JackettProvider.normaliseIMDbID("1856101"), "1856101")
        XCTAssertNil(JackettProvider.normaliseIMDbID(nil))
        XCTAssertNil(JackettProvider.normaliseIMDbID(""))
        XCTAssertNil(JackettProvider.normaliseIMDbID("not-an-id"))
    }

    // MARK: - testTorznabParser_handlesAttrNamespacedAndBare

    func testTorznabParser_handlesAttrNamespacedAndBare() {
        let items = TorznabXMLParser.parse(data: torznabMovieFixture)
        XCTAssertEqual(items.count, 2)
        // Both namespaced and unnamespaced forms land in the same item model.
        XCTAssertEqual(items[0].seeders, 123)
        XCTAssertEqual(items[0].infoHash, "aaaabbbbccccdddd1111222233334444aaaabbbb")
    }

    // MARK: - Fixtures

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecordingURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeMovie(title: String, tmdbID: Int64, imdbID: String?) -> Movie {
        Movie(
            id: MediaID(provider: .tmdb, id: tmdbID),
            title: title,
            originalTitle: title,
            releaseYear: 2020,
            runtimeMinutes: nil,
            overview: "",
            genres: [],
            posterPath: nil,
            backdropPath: nil,
            voteAverage: nil,
            popularity: nil,
            imdbID: imdbID
        )
    }

    private func makeShow(name: String, tmdbID: Int64, imdbID: String?) -> Show {
        Show(
            id: MediaID(provider: .tmdb, id: tmdbID),
            name: name,
            originalName: name,
            firstAirYear: 2022,
            lastAirYear: nil,
            status: .returning,
            overview: "",
            genres: [],
            posterPath: nil,
            backdropPath: nil,
            voteAverage: nil,
            popularity: nil,
            seasons: [],
            imdbID: imdbID
        )
    }

    /// Mixed fixture: one item with a magnet + torznab:attr style, one with
    /// an enclosure pointing at a .torrent and a plain <size> element.
    private let torznabMovieFixture = Data(#"""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:torznab="http://torznab.com/schemas/2015/feed">
      <channel>
        <title>Jackett</title>
        <item>
          <title>Blade Runner 2049 2017 1080p BluRay x264</title>
          <guid>abc-123</guid>
          <link>magnet:?xt=urn:btih:aaaabbbbccccdddd1111222233334444aaaabbbb&amp;dn=Blade+Runner</link>
          <torznab:attr name="seeders" value="123"/>
          <torznab:attr name="peers" value="12"/>
          <torznab:attr name="size" value="2147483648"/>
          <torznab:attr name="infohash" value="aaaabbbbccccdddd1111222233334444aaaabbbb"/>
        </item>
        <item>
          <title>Blade Runner 2049 2017 2160p UHD BluRay REMUX</title>
          <guid>def-456</guid>
          <link>https://tracker.example/download/xyz.torrent</link>
          <enclosure url="https://tracker.example/download/xyz.torrent" length="9876543210" type="application/x-bittorrent"/>
          <size>9876543210</size>
          <attr name="seeders" value="45"/>
          <attr name="leechers" value="8"/>
        </item>
      </channel>
    </rss>
    """#.utf8)

    private let emptyRSSFixture = Data(#"""
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:torznab="http://torznab.com/schemas/2015/feed">
      <channel><title>Jackett</title></channel>
    </rss>
    """#.utf8)
}

// MARK: - RecordingURLProtocol

/// Local URL-protocol stub that records the outgoing request URL so
/// assertions can inspect the query string and can optionally inject a URL
/// error to simulate an offline Jackett instance. Kept local to the test
/// file so the shared `MockURLProtocol` remains unchanged.
final class RecordingURLProtocol: URLProtocol {
    static var responseData: Data = Data()
    static var responseStatusCode: Int = 200
    static var simulatedError: Error?
    static var lastRequestURL: URL?

    static func reset() {
        responseData = Data()
        responseStatusCode = 200
        simulatedError = nil
        lastRequestURL = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        RecordingURLProtocol.lastRequestURL = request.url

        if let error = RecordingURLProtocol.simulatedError {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        let url = request.url ?? URL(string: "about:blank")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: RecordingURLProtocol.responseStatusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/rss+xml"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: RecordingURLProtocol.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
