import XCTest
@testable import MetadataDomain

final class ImageCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        tempDir = base
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
        tempDir = nil
    }

    // MARK: - URLCache configuration

    func test_init_configuresURLCacheWithBudgetAndDirectory() throws {
        let cache = try ImageCache(baseDirectory: tempDir)

        XCTAssertEqual(cache.urlCache.diskCapacity, ImageCacheConfig.diskCapacityBytes)
        XCTAssertEqual(cache.urlCache.memoryCapacity, ImageCacheConfig.memoryCapacityBytes)

        // Directory is `metadata/images/` relative to the base.
        XCTAssertEqual(cache.diskPath.lastPathComponent, "images")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.diskPath.path))
    }

    func test_diskCapacity_is500MB() {
        XCTAssertEqual(ImageCacheConfig.diskCapacityBytes, 500 * 1024 * 1024)
    }

    // MARK: - Failure-mode placeholder (typed error, not raw URL)

    func test_unreachableURL_returnsTransportFailure() async throws {
        let cache = try ImageCache(baseDirectory: tempDir)
        // Use a port that is essentially never listening.
        let url = URL(string: "http://127.0.0.1:1/nope.jpg")!
        let result = await cache.data(for: url)
        switch result {
        case .failure: break
        case .success:
            XCTFail("Unreachable URL should not succeed.")
        }
    }

    // MARK: - Size-suffix selection

    func test_posterCard_default_isW342() {
        XCTAssertEqual(TMDBImageSizes.size(for: .posterCard), .w342)
    }

    func test_posterCard_retina_isW500() {
        XCTAssertEqual(TMDBImageSizes.size(for: .posterCard, retina: true), .w500)
    }

    func test_posterDetail_default_isW500() {
        XCTAssertEqual(TMDBImageSizes.size(for: .posterDetail), .w500)
    }

    func test_posterDetail_retina_isW780() {
        XCTAssertEqual(TMDBImageSizes.size(for: .posterDetail, retina: true), .w780)
    }

    func test_backdrop_isW1280() {
        XCTAssertEqual(TMDBImageSizes.size(for: .backdrop), .w1280)
        XCTAssertEqual(TMDBImageSizes.size(for: .backdrop, retina: true), .w1280)
    }

    func test_episodeStill_default_isW300() {
        XCTAssertEqual(TMDBImageSizes.size(for: .episodeStill), .w300)
    }

    func test_episodeStill_retina_isW500() {
        XCTAssertEqual(TMDBImageSizes.size(for: .episodeStill, retina: true), .w500)
    }

    func test_size_rawValue_matchesTMDBPathSegment() {
        // Sanity: the rawValue is the literal TMDB path segment used to
        // build image URLs (e.g. `/t/p/w342/poster.jpg`).
        XCTAssertEqual(TMDBImageSize.w342.rawValue, "w342")
        XCTAssertEqual(TMDBImageSize.w1280.rawValue, "w1280")
        XCTAssertEqual(TMDBImageSize.original.rawValue, "original")
    }
}
