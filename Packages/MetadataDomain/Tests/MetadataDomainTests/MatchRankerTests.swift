import XCTest
@testable import MetadataDomain

final class MatchRankerTests: XCTestCase {

    // MARK: - Top match exceeds threshold

    func test_perfectMatch_movie_topResultAboveThreshold() {
        let parsed = parsedTitle("The Matrix", year: 1999)
        let matrix1999 = movieItem(id: 603, title: "The Matrix", year: 1999)
        let bullets = movieItem(id: 604, title: "Bulletproof", year: 1996)
        let ranked = MatchRanker.rank(parsed: parsed, candidates: [bullets, matrix1999])
        XCTAssertEqual(ranked.first?.item, matrix1999)
        XCTAssertGreaterThanOrEqual(ranked.first?.confidence ?? 0, MatchRanker.defaultThreshold)
    }

    func test_perfectMatch_show_topResultAboveThreshold() {
        let parsed = parsedTitle("Friends", season: 1, episode: 1)
        let friends = showItem(id: 1668, name: "Friends", firstAirYear: 1994)
        let ranked = MatchRanker.rank(parsed: parsed, candidates: [friends])
        XCTAssertGreaterThanOrEqual(ranked.first?.confidence ?? 0, MatchRanker.defaultThreshold)
    }

    // MARK: - Wrong-year demotion

    func test_wrongYear_demotedBelowSameYearMatch() {
        let parsed = parsedTitle("The Matrix", year: 1999)
        let matrix1999 = movieItem(id: 603, title: "The Matrix", year: 1999)
        let matrix2010 = movieItem(id: 999, title: "The Matrix", year: 2010)
        let ranked = MatchRanker.rank(parsed: parsed, candidates: [matrix2010, matrix1999])
        XCTAssertEqual(ranked.first?.item, matrix1999)
        XCTAssertGreaterThan(ranked[0].confidence, ranked[1].confidence)
        XCTAssertTrue(ranked.last?.reasons.contains(where: { $0.contains("year=miss") }) ?? false)
    }

    // MARK: - Different show with same title

    func test_differentShowSameTitle_yearBreaksTie() {
        let parsed = parsedTitle("Doctor Who", year: 2005, season: 1, episode: 1)
        let classic = showItem(id: 76285, name: "Doctor Who", firstAirYear: 1963)
        let modern = showItem(id: 57243, name: "Doctor Who", firstAirYear: 2005)
        let ranked = MatchRanker.rank(parsed: parsed, candidates: [classic, modern])
        XCTAssertEqual(ranked.first?.item, modern)
    }

    // MARK: - Roman numerals

    func test_romanNumeralSequel_doesNotMatchArabic() {
        let parsed = parsedTitle("Rocky II", year: 1979)
        let rocky2 = movieItem(id: 1366, title: "Rocky 2", year: 1979)
        let rockyII = movieItem(id: 1259, title: "Rocky II", year: 1979)
        let ranked = MatchRanker.rank(parsed: parsed, candidates: [rocky2, rockyII])
        XCTAssertEqual(ranked.first?.item, rockyII)
        XCTAssertGreaterThan(ranked[0].confidence, ranked[1].confidence)
    }

    // MARK: - Show-vs-movie shape

    func test_parsedIsShowShape_movieCandidateDemoted() {
        let parsed = parsedTitle("Westworld", season: 1, episode: 1)
        let movieWW = movieItem(id: 11, title: "Westworld", year: 1973)
        let showWW = showItem(id: 63247, name: "Westworld", firstAirYear: 2016)
        let ranked = MatchRanker.rank(parsed: parsed, candidates: [movieWW, showWW])
        XCTAssertEqual(ranked.first?.item, showWW)
    }

    // MARK: - Reasons surfaced

    func test_rankedMatch_reasons_includeTitleAndYear() {
        let parsed = parsedTitle("Inception", year: 2010)
        let item = movieItem(id: 27205, title: "Inception", year: 2010)
        let r = MatchRanker.rank(parsed: parsed, candidates: [item]).first!
        XCTAssertTrue(r.reasons.contains(where: { $0.contains("title-sim=") }))
        XCTAssertTrue(r.reasons.contains(where: { $0.contains("year=") }))
        XCTAssertTrue(r.reasons.contains(where: { $0.contains("shape=") }))
    }

    func test_rank_orderingIsDeterministic_acrossInvocations() {
        let parsed = parsedTitle("The Matrix", year: 1999)
        let candidates: [MediaItem] = [
            movieItem(id: 1, title: "The Matrix", year: 1999),
            movieItem(id: 2, title: "The Matrix", year: 2010),
            movieItem(id: 3, title: "Bulletproof", year: 1996)
        ]
        let a = MatchRanker.rank(parsed: parsed, candidates: candidates).map(\.item)
        let b = MatchRanker.rank(parsed: parsed, candidates: candidates).map(\.item)
        XCTAssertEqual(a, b)
    }

    // MARK: - Empty candidates

    func test_emptyCandidates_returnsEmpty() {
        let parsed = parsedTitle("Nothing")
        XCTAssertEqual(MatchRanker.rank(parsed: parsed, candidates: []).count, 0)
    }

    // MARK: - Helpers

    private func parsedTitle(_ title: String,
                             year: Int? = nil,
                             season: Int? = nil,
                             episode: Int? = nil) -> ParsedTitle {
        ParsedTitle(title: title, year: year, season: season, episode: episode,
                    releaseGroup: nil, qualityHints: [])
    }

    private func movieItem(id: Int64, title: String, year: Int?) -> MediaItem {
        .movie(Movie(
            id: MediaID(provider: .tmdb, id: id),
            title: title,
            originalTitle: title,
            releaseYear: year,
            runtimeMinutes: nil,
            overview: "",
            genres: [],
            posterPath: nil,
            backdropPath: nil,
            voteAverage: nil,
            popularity: nil
        ))
    }

    private func showItem(id: Int64, name: String, firstAirYear: Int?) -> MediaItem {
        .show(Show(
            id: MediaID(provider: .tmdb, id: id),
            name: name,
            originalName: name,
            firstAirYear: firstAirYear,
            lastAirYear: nil,
            status: .returning,
            overview: "",
            genres: [],
            posterPath: nil,
            backdropPath: nil,
            voteAverage: nil,
            popularity: nil,
            seasons: []
        ))
    }
}
