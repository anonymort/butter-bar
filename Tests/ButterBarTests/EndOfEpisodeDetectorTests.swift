import XCTest
import MetadataDomain
import PlayerDomain
@testable import ButterBar

// MARK: - EndOfEpisodeDetectorTests
//
// Pure tests for `EndOfEpisodeDetector.detect(...)`. The detector is a
// sibling observer of `PlayerState` (per `docs/design/player-state-foundation.md`
// § Out of scope) — it does not extend the state machine. The trigger is
// `.playing → .closed` while the asset is an `Episode` and the playhead is
// within the threshold of the asset's end. See issue #20 for the AC table.

final class EndOfEpisodeDetectorTests: XCTestCase {

    // MARK: - Fixtures

    private func makeEpisode() -> Episode {
        Episode(
            id: MediaID(provider: .tmdb, id: 1001),
            showID: MediaID(provider: .tmdb, id: 42),
            seasonNumber: 1,
            episodeNumber: 1,
            name: "Pilot",
            overview: "",
            stillPath: nil,
            runtimeMinutes: 45,
            airDate: nil
        )
    }

    // MARK: - Positive: genuine episode-end fires

    func testFires_whenPlayingClosesNearAssetEnd() {
        let episode = makeEpisode()
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .playing, to: .closed),
            playheadSeconds: 2_695, // 5s before 45-min asset end
            durationSeconds: 2_700,
            episode: episode
        )
        XCTAssertEqual(signal?.episode, episode)
    }

    func testFires_whenPlayingClosesExactlyAtAssetEnd() {
        let episode = makeEpisode()
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .playing, to: .closed),
            playheadSeconds: 2_700,
            durationSeconds: 2_700,
            episode: episode
        )
        XCTAssertNotNil(signal)
    }

    // MARK: - Negative: movies (episode == nil)

    func testDoesNotFire_forMovies() {
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .playing, to: .closed),
            playheadSeconds: 2_695,
            durationSeconds: 2_700,
            episode: nil
        )
        XCTAssertNil(signal)
    }

    // MARK: - Negative: user mid-episode close

    func testDoesNotFire_onUserMidEpisodeClose() {
        let episode = makeEpisode()
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .playing, to: .closed),
            playheadSeconds: 600, // 10 minutes in, far from end
            durationSeconds: 2_700,
            episode: episode
        )
        XCTAssertNil(signal)
    }

    // MARK: - Negative: error transition

    func testDoesNotFire_onErrorTransition() {
        let episode = makeEpisode()
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .playing, to: .error(.playbackFailed)),
            playheadSeconds: 2_695,
            durationSeconds: 2_700,
            episode: episode
        )
        XCTAssertNil(signal)
    }

    // MARK: - Negative: paused transition

    func testDoesNotFire_onPlayingToPaused() {
        let episode = makeEpisode()
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .playing, to: .paused),
            playheadSeconds: 2_695,
            durationSeconds: 2_700,
            episode: episode
        )
        XCTAssertNil(signal)
    }

    // MARK: - Negative: non-playing → closed

    func testDoesNotFire_whenComingFromPaused() {
        // Paused → closed: user explicitly closed; not a natural episode end.
        let episode = makeEpisode()
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .paused, to: .closed),
            playheadSeconds: 2_695,
            durationSeconds: 2_700,
            episode: episode
        )
        XCTAssertNil(signal)
    }

    // MARK: - Threshold edges

    func testFires_atThresholdBoundary() {
        // Default threshold = 30s. 30s remaining is exactly on the edge → fire.
        let episode = makeEpisode()
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .playing, to: .closed),
            playheadSeconds: 2_670, // 30s before end
            durationSeconds: 2_700,
            episode: episode
        )
        XCTAssertNotNil(signal)
    }

    func testDoesNotFire_justOutsideThreshold() {
        // 31s remaining is just outside default 30s threshold → do not fire.
        let episode = makeEpisode()
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .playing, to: .closed),
            playheadSeconds: 2_669,
            durationSeconds: 2_700,
            episode: episode
        )
        XCTAssertNil(signal)
    }

    func testThresholdIsTunable() {
        // With a wider threshold, the previously-rejected case fires.
        let episode = makeEpisode()
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .playing, to: .closed),
            playheadSeconds: 2_400, // 5 minutes from end
            durationSeconds: 2_700,
            episode: episode,
            threshold: 600 // 10 minutes
        )
        XCTAssertNotNil(signal)
    }

    // MARK: - Defensive: bad inputs

    func testDoesNotFire_withZeroDuration() {
        // Duration unknown / not yet loaded — never fire.
        let episode = makeEpisode()
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .playing, to: .closed),
            playheadSeconds: 0,
            durationSeconds: 0,
            episode: episode
        )
        XCTAssertNil(signal)
    }

    func testDoesNotFire_withNegativeRemaining() {
        // Playhead past duration — should still fire (treated as "at end").
        let episode = makeEpisode()
        let signal = EndOfEpisodeDetector.detect(
            stateTransition: (from: .playing, to: .closed),
            playheadSeconds: 2_750,
            durationSeconds: 2_700,
            episode: episode
        )
        XCTAssertNotNil(signal)
    }
}
