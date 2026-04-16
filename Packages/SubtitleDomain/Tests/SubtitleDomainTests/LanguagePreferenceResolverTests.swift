import XCTest
@testable import SubtitleDomain

/// Covers every row of the resolution matrix in
/// `docs/design/subtitle-foundation.md` § Resolution matrix.
final class LanguagePreferenceResolverTests: XCTestCase {

    // MARK: - Fixtures

    private func embedded(_ id: String, _ lang: String?) -> SubtitleTrack {
        SubtitleTrack(
            id: id,
            source: .embedded(identifier: id),
            language: lang,
            label: "Embedded \(id)"
        )
    }

    private func sidecar(_ id: String, _ lang: String?) -> SubtitleTrack {
        SubtitleTrack(
            id: id,
            source: .sidecar(url: URL(fileURLWithPath: "/tmp/\(id).srt"),
                             format: .srt,
                             cues: []),
            language: lang,
            label: "Sidecar \(id)"
        )
    }

    // MARK: - Matrix rows

    func test_preferredNil_returnsNil() {
        let tracks = [embedded("e1", "en"), sidecar("s1", "en")]
        XCTAssertNil(LanguagePreferenceResolver.pick(from: tracks, preferred: nil))
    }

    func test_preferredOff_returnsNil_evenWithMatchingTracks() {
        let tracks = [embedded("e1", "en")]
        XCTAssertNil(LanguagePreferenceResolver.pick(from: tracks, preferred: "off"))
    }

    func test_preferredOff_isCaseInsensitive() {
        let tracks = [embedded("e1", "en")]
        XCTAssertNil(LanguagePreferenceResolver.pick(from: tracks, preferred: "OFF"))
        XCTAssertNil(LanguagePreferenceResolver.pick(from: tracks, preferred: "Off"))
    }

    func test_exactMatch_returnsTrack() {
        let tracks = [embedded("e1", "en")]
        let pick = LanguagePreferenceResolver.pick(from: tracks, preferred: "en")
        XCTAssertEqual(pick?.id, "e1")
    }

    func test_primarySubtagMatch_enMatchesEnUS() {
        let tracks = [embedded("e1", "en-US")]
        let pick = LanguagePreferenceResolver.pick(from: tracks, preferred: "en")
        XCTAssertEqual(pick?.id, "e1")
    }

    func test_primarySubtagMatch_ptBRPickedByPt() {
        let tracks = [embedded("e1", "pt-BR")]
        let pick = LanguagePreferenceResolver.pick(from: tracks, preferred: "pt")
        XCTAssertEqual(pick?.id, "e1")
    }

    func test_primarySubtagMatch_sharedPrimary_ptBRPickedByPtPT() {
        // User pref "pt-PT", track "pt-BR" — both share primary "pt".
        let tracks = [embedded("e1", "pt-BR")]
        let pick = LanguagePreferenceResolver.pick(from: tracks, preferred: "pt-PT")
        XCTAssertEqual(pick?.id, "e1")
    }

    func test_caseInsensitiveMatch() {
        let tracks = [embedded("e1", "en")]
        let pick = LanguagePreferenceResolver.pick(from: tracks, preferred: "EN")
        XCTAssertEqual(pick?.id, "e1")
    }

    func test_noMatch_returnsNil() {
        let tracks = [embedded("e1", "en"), sidecar("s1", "fr")]
        XCTAssertNil(LanguagePreferenceResolver.pick(from: tracks, preferred: "de"))
    }

    func test_bothMatch_embeddedWinsOverSidecar() {
        let tracks = [embedded("e1", "en"), sidecar("s1", "en")]
        let pick = LanguagePreferenceResolver.pick(from: tracks, preferred: "en")
        XCTAssertEqual(pick?.id, "e1")
    }

    func test_sidecarOnly_match_returnsSidecar() {
        let tracks = [sidecar("s1", "en")]
        let pick = LanguagePreferenceResolver.pick(from: tracks, preferred: "en")
        XCTAssertEqual(pick?.id, "s1")
    }

    /// D8 step 3 guarantee: resolver partitions internally. Input order
    /// doesn't matter — if an embedded match exists anywhere in the list,
    /// it wins.
    func test_callerOrderIndependence_sidecarFirstInput_embeddedStillWins() {
        let tracks = [sidecar("s1", "en"), embedded("e1", "en")]
        let pick = LanguagePreferenceResolver.pick(from: tracks, preferred: "en")
        XCTAssertEqual(pick?.id, "e1", "Resolver must partition by source type, not trust caller order.")
    }

    func test_scriptSubtagCounts_asPrefixHit_zhHansMatchesZh() {
        let tracks = [embedded("e1", "zh-Hans")]
        let pick = LanguagePreferenceResolver.pick(from: tracks, preferred: "zh")
        XCTAssertEqual(pick?.id, "e1")
    }

    func test_trackLanguageNil_notMatched() {
        let tracks = [embedded("e1", nil)]
        XCTAssertNil(LanguagePreferenceResolver.pick(from: tracks, preferred: "en"))
    }

    // MARK: - Primary subtag helper

    func test_primarySubtag_extractsPrimary() {
        XCTAssertEqual(LanguagePreferenceResolver.primarySubtag(of: "en-US"), "en")
        XCTAssertEqual(LanguagePreferenceResolver.primarySubtag(of: "pt-BR"), "pt")
        XCTAssertEqual(LanguagePreferenceResolver.primarySubtag(of: "zh-Hans"), "zh")
        XCTAssertEqual(LanguagePreferenceResolver.primarySubtag(of: "en"), "en")
    }
}
