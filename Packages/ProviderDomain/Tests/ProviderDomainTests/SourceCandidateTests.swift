import XCTest
@testable import ProviderDomain

final class SourceCandidateTests: XCTestCase {

    // MARK: - SourceCandidate Equatable / Hashable

    func test_equatable_sameCandidates_areEqual() {
        let a = makeCandidate()
        let b = makeCandidate()
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentID_notEqual() {
        let a = makeCandidate(id: "yts:aaa")
        let b = makeCandidate(id: "yts:bbb")
        XCTAssertNotEqual(a, b)
    }

    func test_hashable_equalCandidates_haveEqualHashes() {
        let a = makeCandidate()
        let b = makeCandidate()
        var set: Set<SourceCandidate> = []
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    func test_hashable_differentCandidates_haveDistinctHashes() {
        let a = makeCandidate(id: "yts:aaa")
        let b = makeCandidate(id: "yts:bbb")
        var set: Set<SourceCandidate> = [a, b]
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - SourceQuality ordering

    func test_quality_ordering_bluRayGreaterThanWebDL() {
        XCTAssertGreaterThan(SourceQuality.bluRay, SourceQuality.webDL)
    }

    func test_quality_ordering_webDLGreaterThanDVDRip() {
        XCTAssertGreaterThan(SourceQuality.webDL, SourceQuality.dvdRip)
    }

    func test_quality_ordering_dvdRipGreaterThanTS() {
        XCTAssertGreaterThan(SourceQuality.dvdRip, SourceQuality.ts)
    }

    func test_quality_ordering_tsGreaterThanCam() {
        XCTAssertGreaterThan(SourceQuality.ts, SourceQuality.cam)
    }

    func test_quality_ordering_remuxIsHighestNamed() {
        // remux sits above bluRay (lossless rip vs. re-encode)
        XCTAssertGreaterThan(SourceQuality.remux, SourceQuality.bluRay)
    }

    func test_quality_ordering_ascending() {
        let expected: [SourceQuality] = [.cam, .ts, .dvdRip, .webDL, .bluRay, .remux]
        let sorted = expected.shuffled().sorted()
        XCTAssertEqual(sorted, expected)
    }

    // MARK: - Helpers

    private func makeCandidate(
        id: String = "yts:abc123",
        infoHash: String = "abc1234567890abcdef1234567890abcdef123456",
        magnetURI: String? = "magnet:?xt=urn:btih:abc123",
        torrentURL: URL? = nil,
        title: String = "Some.Movie.2024.1080p.WEB-DL",
        quality: SourceQuality = .webDL,
        seeders: Int = 500,
        leechers: Int = 20,
        sizeBytes: Int64? = 2_147_483_648,
        providerName: String = "YTS"
    ) -> SourceCandidate {
        SourceCandidate(
            id: id,
            infoHash: infoHash,
            magnetURI: magnetURI,
            torrentURL: torrentURL,
            title: title,
            quality: quality,
            seeders: seeders,
            leechers: leechers,
            sizeBytes: sizeBytes,
            providerName: providerName
        )
    }
}
