import XCTest
@testable import MetadataDomain

final class TitleNameParserTests: XCTestCase {

    // MARK: - Fixture-driven coverage (≥ 50 cases)

    func test_allFixtures_parseToExpected() throws {
        let fixtures = try Self.loadFixtures()
        XCTAssertGreaterThanOrEqual(fixtures.count, 50,
                                    "Need at least 50 fixture cases per design § Test shape.")

        var failures: [String] = []
        for (input, expected) in fixtures {
            let actual = TitleNameParser.parse(input)
            if !Self.matches(actual: actual, expected: expected) {
                failures.append(
                    "\nInput: \(input)\n  expected: \(expected)\n  actual:   \(Self.describe(actual))"
                )
            }
        }
        if !failures.isEmpty {
            XCTFail("Parser fixture mismatches (\(failures.count)):\n" + failures.joined())
        }
    }

    // MARK: - Targeted unit tests for specific shapes

    func test_movie_dotSeparated_extractsTitleAndYear() {
        let p = TitleNameParser.parse("The.Matrix.1999.1080p.BluRay.x264-GROUP.mkv")
        XCTAssertEqual(p.title, "The Matrix")
        XCTAssertEqual(p.year, 1999)
        XCTAssertNil(p.season)
        XCTAssertNil(p.episode)
        XCTAssertEqual(p.releaseGroup, "GROUP")
        XCTAssertTrue(p.qualityHints.contains(.p1080))
        XCTAssertTrue(p.qualityHints.contains(.bluRay))
        XCTAssertTrue(p.qualityHints.contains(.x264))
    }

    func test_show_seasonEpisodeMarker_extractsBoth() {
        let p = TitleNameParser.parse("Friends.S01E01.The.One.Where.Monica.Gets.A.Roommate.1080p.BluRay.x264-PSYCHD.mkv")
        XCTAssertEqual(p.title, "Friends")
        XCTAssertEqual(p.season, 1)
        XCTAssertEqual(p.episode, 1)
        XCTAssertNil(p.year)
        XCTAssertEqual(p.releaseGroup, "PSYCHD")
    }

    func test_anime_bracketGroup_dashEpisode_assignsSeasonOne() {
        let p = TitleNameParser.parse("[SubsPlease] Spy x Family - 12 (1080p) [ABCDEF12].mkv")
        XCTAssertEqual(p.title, "Spy x Family")
        XCTAssertEqual(p.season, 1)
        XCTAssertEqual(p.episode, 12)
        XCTAssertEqual(p.releaseGroup, "SubsPlease")
        XCTAssertTrue(p.qualityHints.contains(.p1080))
    }

    func test_romanNumeralSequel_isPreservedInTitle() {
        let p = TitleNameParser.parse("Rocky.II.1979.1080p.BluRay.x264-AMIABLE.mkv")
        XCTAssertEqual(p.title, "Rocky II")
        XCTAssertEqual(p.year, 1979)
    }

    func test_arabicNumeralSequel_isPreservedInTitle() {
        let p = TitleNameParser.parse("Rocky.2.1979.1080p.BluRay.x264-FAKE.mkv")
        XCTAssertEqual(p.title, "Rocky 2")
        XCTAssertEqual(p.year, 1979)
    }

    func test_seasonOnlyMarker_seasonSetEpisodeNil() {
        let p = TitleNameParser.parse("Westworld.Season.1.Complete.1080p.BluRay.x264-DEFLATE.mkv")
        XCTAssertEqual(p.season, 1)
        XCTAssertNil(p.episode)
    }

    func test_qualityHints_remuxAndHDR_detected() {
        let p = TitleNameParser.parse("Avatar.The.Way.of.Water.2022.2160p.UHD.BluRay.x265.10bit.HDR-TERMINAL.mkv")
        XCTAssertTrue(p.qualityHints.contains(.p2160))
        XCTAssertTrue(p.qualityHints.contains(.hdr))
        XCTAssertTrue(p.qualityHints.contains(.bluRay))
        XCTAssertTrue(p.qualityHints.contains(.x265))
        XCTAssertTrue(p.qualityHints.contains(.uhd))
    }

    func test_unknownExtension_keepsExtensionInName() {
        // Defensive: weird extension shouldn't crash; title still extracted.
        let p = TitleNameParser.parse("Some.Movie.2010.bin")
        XCTAssertEqual(p.year, 2010)
    }

    func test_emptyString_returnsEmptyTitle() {
        let p = TitleNameParser.parse("")
        XCTAssertEqual(p.title, "")
        XCTAssertNil(p.year)
        XCTAssertNil(p.season)
        XCTAssertNil(p.episode)
    }

    // MARK: - Fixture loading

    struct ExpectedParse: Codable {
        let title: String
        let year: Int?
        let season: Int?
        let episode: Int?
        let releaseGroup: String?
        let qualityHints: [String]
    }

    static func loadFixtures() throws -> [(String, ExpectedParse)] {
        let jsonURL = try XCTUnwrap(
            Bundle.module.url(forResource: "release-names",
                              withExtension: "json",
                              subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: "release-names.expected",
                                 withExtension: "json",
                                 subdirectory: "Fixtures")
        )
        let data = try Data(contentsOf: jsonURL)
        let dict = try JSONDecoder().decode([String: ExpectedParse].self, from: data)

        let txtURL = try XCTUnwrap(
            Bundle.module.url(forResource: "release-names",
                              withExtension: "txt",
                              subdirectory: "Fixtures")
        )
        let lines = try String(contentsOf: txtURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Preserve order from the text file so failures are easier to triage.
        return try lines.map { line in
            let expected = try XCTUnwrap(dict[line], "Missing expected entry for: \(line)")
            return (line, expected)
        }
    }

    static func matches(actual: ParsedTitle, expected: ExpectedParse) -> Bool {
        let actualHints = Set(actual.qualityHints.map(\.rawValue))
        let expectedHints = Set(expected.qualityHints)
        return actual.title == expected.title
            && actual.year == expected.year
            && actual.season == expected.season
            && actual.episode == expected.episode
            && actual.releaseGroup == expected.releaseGroup
            && actualHints == expectedHints
    }

    static func describe(_ p: ParsedTitle) -> String {
        let hints = p.qualityHints.map(\.rawValue).sorted().joined(separator: ",")
        return "title=\(p.title) year=\(String(describing: p.year)) " +
               "S=\(String(describing: p.season)) E=\(String(describing: p.episode)) " +
               "group=\(String(describing: p.releaseGroup)) hints=[\(hints)]"
    }
}
