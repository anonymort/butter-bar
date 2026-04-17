import AppKit
import SnapshotTesting
import SubtitleDomain
import SwiftUI
import XCTest
@testable import ButterBar

// MARK: - SubtitleErrorBannerSnapshotTests
//
// Snapshot cases: light + dark × 4 error variants = 8 snapshots.
// Baselines in __Snapshots__/SubtitleErrorBannerSnapshotTests/.
//
// First run: set record: .all to write baselines.

@MainActor
final class SubtitleErrorBannerSnapshotTests: XCTestCase {

    private let snapshotSize = CGSize(width: 480, height: 56)

    private func rendered<V: View>(_ view: V, colorScheme: ColorScheme) -> NSImage {
        let renderer = ImageRenderer(
            content: view
                .environment(\.colorScheme, colorScheme)
                .frame(width: snapshotSize.width, height: snapshotSize.height)
                .background(colorScheme == .dark ? Color.black : BrandColors.cream)
        )
        renderer.proposedSize = ProposedViewSize(snapshotSize)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage else {
            XCTFail("Could not render snapshot")
            return NSImage(size: snapshotSize)
        }
        return NSImage(cgImage: cgImage, size: snapshotSize)
    }

    private func banner(error: SubtitleLoadError, colorScheme: ColorScheme) -> some View {
        let store = SubtitlePreferenceStore(
            defaults: UserDefaults(suiteName: "SnapshotBanner-\(UUID().uuidString)")!
        )
        let c = SubtitleController(preferenceStore: store)
        c.activeError = error
        return SubtitleErrorBanner(controller: c)
            .environment(\.colorScheme, colorScheme)
    }

    // MARK: - .decoding

    func testDecoding_dark() {
        assertSnapshot(
            of: rendered(banner(error: .decoding(reason: "Movie.en.srt"), colorScheme: .dark), colorScheme: .dark),
            as: .image, named: "dark-decoding"
        )
    }

    func testDecoding_light() {
        assertSnapshot(
            of: rendered(banner(error: .decoding(reason: "Movie.en.srt"), colorScheme: .light), colorScheme: .light),
            as: .image, named: "light-decoding"
        )
    }

    // MARK: - .fileUnavailable

    func testFileUnavailable_dark() {
        assertSnapshot(
            of: rendered(banner(error: .fileUnavailable(reason: "Missing"), colorScheme: .dark), colorScheme: .dark),
            as: .image, named: "dark-fileUnavailable"
        )
    }

    func testFileUnavailable_light() {
        assertSnapshot(
            of: rendered(banner(error: .fileUnavailable(reason: "Missing"), colorScheme: .light), colorScheme: .light),
            as: .image, named: "light-fileUnavailable"
        )
    }

    // MARK: - .unsupportedFormat

    func testUnsupportedFormat_dark() {
        assertSnapshot(
            of: rendered(banner(error: .unsupportedFormat(reason: ".vtt"), colorScheme: .dark), colorScheme: .dark),
            as: .image, named: "dark-unsupportedFormat"
        )
    }

    func testUnsupportedFormat_light() {
        assertSnapshot(
            of: rendered(banner(error: .unsupportedFormat(reason: ".vtt"), colorScheme: .light), colorScheme: .light),
            as: .image, named: "light-unsupportedFormat"
        )
    }

    // MARK: - .systemTrackFailed

    func testSystemTrackFailed_dark() {
        assertSnapshot(
            of: rendered(banner(error: .systemTrackFailed(reason: "Option not found"), colorScheme: .dark), colorScheme: .dark),
            as: .image, named: "dark-systemTrackFailed"
        )
    }

    func testSystemTrackFailed_light() {
        assertSnapshot(
            of: rendered(banner(error: .systemTrackFailed(reason: "Option not found"), colorScheme: .light), colorScheme: .light),
            as: .image, named: "light-systemTrackFailed"
        )
    }
}
