import Testing
import Foundation
@testable import ProviderDomain
import MetadataDomain

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

/// Builds a minimal `SourceCandidate` for test use.
private func makeCandidate(
    id: String = UUID().uuidString,
    infoHash: String = UUID().uuidString,
    quality: SourceQuality,
    seeders: Int,
    sizeBytes: Int64? = nil,
    providerName: String = "test"
) -> SourceCandidate {
    SourceCandidate(
        id: id,
        infoHash: infoHash,
        magnetURI: "magnet:?xt=urn:btih:\(infoHash)",
        torrentURL: nil,
        title: "Test Title",
        quality: quality,
        seeders: seeders,
        leechers: 0,
        sizeBytes: sizeBytes,
        providerName: providerName
    )
}

// ---------------------------------------------------------------------------
// MARK: - SourceQuality rank mapping
// ---------------------------------------------------------------------------

@Suite("SourceQuality.rank")
struct SourceQualityRankTests {

    @Test("rank values follow spec ordering")
    func rankValues() {
        #expect(SourceQuality.remux.rank   == 7)
        #expect(SourceQuality.bluRay.rank  == 6)
        #expect(SourceQuality.webDL.rank   == 5)
        #expect(SourceQuality.dvdRip.rank  == 4)
        #expect(SourceQuality.unknown.rank == 3)
        #expect(SourceQuality.ts.rank      == 2)
        #expect(SourceQuality.cam.rank     == 1)
    }
}

// ---------------------------------------------------------------------------
// MARK: - SourceCandidate.rank
// ---------------------------------------------------------------------------

@Suite("SourceCandidate.rank")
struct SourceCandidateRankTests {

    @Test("quality dominates rank comparison")
    func rankingOrder() {
        let high = makeCandidate(quality: .remux,  seeders: 0)
        let mid  = makeCandidate(quality: .webDL,  seeders: 9_999)
        let low  = makeCandidate(quality: .cam,    seeders: 9_999)

        // remux > webDL even with 0 seeders vs 9999
        #expect(high.rank > mid.rank)
        // webDL > cam even with equal seeders
        #expect(mid.rank  > low.rank)
    }

    @Test("seeder count breaks tie within same quality")
    func seederTieBreak() {
        let moreSeeders  = makeCandidate(quality: .bluRay, seeders: 500)
        let fewerSeeders = makeCandidate(quality: .bluRay, seeders: 100)

        #expect(moreSeeders.rank > fewerSeeders.rank)
    }

    @Test("sizeBytes breaks final tie")
    func sizeTieBreak() {
        let withSize    = makeCandidate(quality: .dvdRip, seeders: 50, sizeBytes: 1_073_741_824)
        let withoutSize = makeCandidate(quality: .dvdRip, seeders: 50, sizeBytes: nil)

        #expect(withSize.rank > withoutSize.rank)
    }

    @Test("seeders are capped at 9999 for ranking")
    func seederCap() {
        let capped    = makeCandidate(quality: .ts, seeders: 100_000)
        let atCap     = makeCandidate(quality: .ts, seeders: 9_999)

        // Both should score identically since cap applies
        #expect(capped.rank == atCap.rank)
    }
}

// ---------------------------------------------------------------------------
// MARK: - ProviderAuthModel
// ---------------------------------------------------------------------------

@Suite("ProviderAuthModel")
struct ProviderAuthModelTests {

    @Test("codable round-trip for all cases")
    func codableRoundTrip() throws {
        let cases: [ProviderAuthModel] = [
            .none,
            .apiKey(key: "abc123"),
            .oauth(clientID: "client-xyz")
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for model in cases {
            let data = try encoder.encode(model)
            let decoded = try decoder.decode(ProviderAuthModel.self, from: data)
            #expect(decoded == model)
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Fake providers for pipeline tests
// ---------------------------------------------------------------------------

/// Returns a fixed list of candidates instantly.
private struct FakeProvider: MediaProvider {
    let name: String
    var authModel: ProviderAuthModel { .none }
    let results: [SourceCandidate]

    func search(for item: MediaItem, page: Int) async throws -> [SourceCandidate] {
        results
    }
}

/// Blocks indefinitely — simulates a hung provider.
private struct SlowProvider: MediaProvider {
    let name: String
    var authModel: ProviderAuthModel { .none }

    func search(for item: MediaItem, page: Int) async throws -> [SourceCandidate] {
        // Sleep for a very long time; the pipeline should cancel this task.
        try await Task.sleep(for: .seconds(300))
        return []
    }
}

/// Throws a deterministic error.
private struct ErrorProvider: MediaProvider {
    let name: String
    var authModel: ProviderAuthModel { .apiKey(key: "bad") }
    let error: Error

    func search(for item: MediaItem, page: Int) async throws -> [SourceCandidate] {
        throw error
    }
}

// ---------------------------------------------------------------------------
// MARK: - ProviderSearchPipeline
// ---------------------------------------------------------------------------
//
// Note: `ProviderSearchPipeline` is declared `@MainActor` and lives in the App
// target, not in this package. These tests exercise the *domain types* that
// feed the pipeline (ranking, deduplication logic) without depending on the
// App target. Full pipeline integration tests belong in the App test suite
// once the Xcode project wires the target dependency.
//
// The tests below that *do* need pipeline behaviour use a lightweight inline
// reimplementation of the de-duplicate+rank logic so they remain independent.

@Suite("De-duplication and ranking logic (domain-level)")
struct PipelineDomainTests {

    // Mirrors the pipeline's merge logic so the test doesn't depend on the App target.
    private func mergeAndRank(_ batches: [[SourceCandidate]]) -> [SourceCandidate] {
        var seen = Set<String>()
        let flat = batches.flatMap { $0 }
        let unique = flat.filter { seen.insert($0.infoHash).inserted }
        return unique.sorted { $0.rank > $1.rank }
    }

    @Test("deduplication keeps first occurrence of duplicate infoHash")
    func testDeduplicate() {
        let hash = "aabbcc112233"
        let fromProvider1 = makeCandidate(id: "p1:\(hash)", infoHash: hash, quality: .webDL, seeders: 100, providerName: "P1")
        let fromProvider2 = makeCandidate(id: "p2:\(hash)", infoHash: hash, quality: .webDL, seeders: 100, providerName: "P2")
        let other         = makeCandidate(quality: .bluRay, seeders: 50, providerName: "P1")

        let result = mergeAndRank([[fromProvider1, other], [fromProvider2]])

        // Only two unique info hashes → two candidates
        #expect(result.count == 2)
        // The retained duplicate should be the first-seen one (P1)
        let deduped = result.first { $0.infoHash == hash }!
        #expect(deduped.providerName == "P1")
    }

    @Test("results sorted descending by rank")
    func testRankingOrder() {
        let cam   = makeCandidate(quality: .cam,   seeders: 9_999)
        let remux = makeCandidate(quality: .remux, seeders: 0)
        let webDL = makeCandidate(quality: .webDL, seeders: 500)

        let result = mergeAndRank([[cam, remux, webDL]])

        #expect(result[0].quality == .remux)
        #expect(result[1].quality == .webDL)
        #expect(result[2].quality == .cam)
    }
}
