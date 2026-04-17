import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
import EngineInterface
import PlayerDomain
@testable import ButterBar

/// Snapshot baselines for `PlayerErrorChrome` per `PlayerError` case in
/// light + dark, per `06-brand.md § Test obligations` and issue #26 AC.
///
/// Snapshots are CI-advisory (`continue-on-error: true` in ci.yml) — pixel
/// diffs between local and the hosted runner won't fail the merge. The
/// content under test is the brand voice / layout, not raster fidelity.
@MainActor
final class PlayerErrorChromeTests: XCTestCase {

    private let snapshotSize = CGSize(width: 960, height: 540)

    private func render<V: View>(_ view: V, colorScheme: ColorScheme) -> NSImage {
        let renderer = ImageRenderer(
            content: view
                .environment(\.colorScheme, colorScheme)
                .frame(width: snapshotSize.width, height: snapshotSize.height)
        )
        renderer.proposedSize = ProposedViewSize(snapshotSize)
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            XCTFail("Could not render SwiftUI snapshot image")
            return NSImage(size: snapshotSize)
        }
        return NSImage(cgImage: cgImage, size: snapshotSize)
    }

    private func chrome(error: PlayerError,
                        lastTier: StreamHealthTier? = nil) -> some View {
        ZStack {
            BrandColors.videoLetterbox
            PlayerErrorChrome(
                error: error,
                lastKnownTier: lastTier,
                onRetry: {},
                onClose: {}
            )
        }
    }

    private func snap(_ name: String, view: some View, colorScheme: ColorScheme) {
        assertSnapshot(
            of: render(view, colorScheme: colorScheme),
            as: .image,
            named: name
        )
    }

    // MARK: - .streamOpenFailed (one variant per representative code)

    func testErrorStreamOpenFailed_streamOpenFailed_dark() {
        snap("dark-streamOpenFailed-streamOpenFailed",
             view: chrome(error: .streamOpenFailed(.streamOpenFailed)),
             colorScheme: .dark)
    }
    func testErrorStreamOpenFailed_streamOpenFailed_light() {
        snap("light-streamOpenFailed-streamOpenFailed",
             view: chrome(error: .streamOpenFailed(.streamOpenFailed)),
             colorScheme: .light)
    }

    func testErrorStreamOpenFailed_torrentNotFound_dark() {
        snap("dark-streamOpenFailed-torrentNotFound",
             view: chrome(error: .streamOpenFailed(.torrentNotFound)),
             colorScheme: .dark)
    }
    func testErrorStreamOpenFailed_torrentNotFound_light() {
        snap("light-streamOpenFailed-torrentNotFound",
             view: chrome(error: .streamOpenFailed(.torrentNotFound)),
             colorScheme: .light)
    }

    // MARK: - .xpcDisconnected

    func testErrorXpcDisconnected_dark() {
        snap("dark-xpcDisconnected",
             view: chrome(error: .xpcDisconnected),
             colorScheme: .dark)
    }
    func testErrorXpcDisconnected_light() {
        snap("light-xpcDisconnected",
             view: chrome(error: .xpcDisconnected),
             colorScheme: .light)
    }

    // MARK: - .playbackFailed (with + without engine tier hint)

    func testErrorPlaybackFailed_noTier_dark() {
        snap("dark-playbackFailed-noTier",
             view: chrome(error: .playbackFailed),
             colorScheme: .dark)
    }
    func testErrorPlaybackFailed_noTier_light() {
        snap("light-playbackFailed-noTier",
             view: chrome(error: .playbackFailed),
             colorScheme: .light)
    }

    func testErrorPlaybackFailed_starvingTier_dark() {
        snap("dark-playbackFailed-starving",
             view: chrome(error: .playbackFailed, lastTier: .starving),
             colorScheme: .dark)
    }
    func testErrorPlaybackFailed_starvingTier_light() {
        snap("light-playbackFailed-starving",
             view: chrome(error: .playbackFailed, lastTier: .starving),
             colorScheme: .light)
    }

    // MARK: - .streamLost (rendered as xpcDisconnected per AC; baseline in
    //          place for when O1 lands a real edge.)

    func testErrorStreamLost_dark() {
        snap("dark-streamLost",
             view: chrome(error: .streamLost),
             colorScheme: .dark)
    }
    func testErrorStreamLost_light() {
        snap("light-streamLost",
             view: chrome(error: .streamLost),
             colorScheme: .light)
    }
}

// MARK: - PlayerCopy voice review
//
// Cheap unit-test pass over the copy file so the audit surface is one place
// (per #26 AC: "every copy string in this PR appears in a single
// `PlayerCopy.swift` file ... so it can be audited against `06-brand.md` in
// one place"). Keeps the brand voice review honest: any new copy string is
// covered by an automated check that catches the obvious failures (system
// jargon, exclamation marks, all-caps).

@MainActor
final class PlayerCopyVoiceTests: XCTestCase {

    /// All `EngineErrorCode` cases. Listed by hand because the enum is
    /// `@objc` (no automatic `CaseIterable` conformance). Keep in sync with
    /// `EngineErrorCode.swift` — adding a case there should mean adding it
    /// here so the brand voice gate scans the new copy.
    private var allEngineErrorCodes: [EngineErrorCode] {
        [
            .notImplemented,
            .invalidInput,
            .torrentNotFound,
            .fileIndexOutOfRange,
            .streamNotFound,
            .streamOpenFailed,
            .bookmarkInvalid,
            .storageError,
            .engineShuttingDown,
        ]
    }

    /// Every error title + body string. Centralised so `forbiddenTokens`
    /// only needs to scan one list.
    private var allErrorStrings: [String] {
        var out: [String] = []
        for code in allEngineErrorCodes {
            out.append(PlayerCopy.errorTitle(for: .streamOpenFailed(code)))
            out.append(PlayerCopy.errorBody(for: .streamOpenFailed(code)))
        }
        for err: PlayerError in [.xpcDisconnected, .playbackFailed, .streamLost] {
            out.append(PlayerCopy.errorTitle(for: err))
            out.append(PlayerCopy.errorBody(for: err))
        }
        for reason: BufferingReason in [.openingStream, .engineStarving, .playerRebuffering] {
            out.append(PlayerCopy.bufferingPrimary(for: reason))
        }
        out.append(PlayerCopy.bufferingLongStarvingSecondary)
        out.append(PlayerCopy.retryButtonLabel)
        out.append(PlayerCopy.closeButtonLabel)
        return out
    }

    func test_noExclamationMarks() {
        for s in allErrorStrings where s.contains("!") {
            XCTFail("Brand voice violation — exclamation mark in: \"\(s)\"")
        }
    }

    func test_noAllCapsScreaming() {
        // Allow up to 4 consecutive uppercase chars for acronyms. Anything
        // longer is a brand voice failure.
        let pattern = "[A-Z]{5,}"
        let regex = try? NSRegularExpression(pattern: pattern)
        for s in allErrorStrings {
            let range = NSRange(s.startIndex..., in: s)
            if let regex, regex.firstMatch(in: s, range: range) != nil {
                XCTFail("Brand voice violation — all-caps run in: \"\(s)\"")
            }
        }
    }

    func test_noSystemErrorJargon() {
        // Quick guard against the obvious offenders. Calm voice rules out
        // these tokens; acceptable substitutes live in PlayerCopy itself.
        let banned = ["ERROR", "Failed:", "Fatal", "Crash", "Panic"]
        for s in allErrorStrings {
            for token in banned where s.contains(token) {
                XCTFail("Brand voice violation — banned token \"\(token)\" in: \"\(s)\"")
            }
        }
    }
}
