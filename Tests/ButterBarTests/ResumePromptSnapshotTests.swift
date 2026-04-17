import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
@testable import ButterBar

/// Snapshot baselines for `ResumePromptView` light + dark per
/// `06-brand.md § Test obligations`.
///
/// First run: set `record: .all` to write baselines, then re-run to diff.
@MainActor
final class ResumePromptSnapshotTests: XCTestCase {

    private let snapshotSize = CGSize(width: 480, height: 320)

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

    private func snapshotView(offer: ResumePromptOffer,
                              colorScheme: ColorScheme) -> some View {
        ZStack {
            // Background mimics the player letterbox.
            BrandColors.videoLetterbox
            ResumePromptView(
                offer: offer,
                onContinue: {},
                onStartOver: {},
                onDismiss: {}
            )
        }
    }

    // MARK: - With known resume time

    func testResumePrompt_withTime_dark() {
        assertSnapshot(
            of: render(
                snapshotView(offer: ResumePromptOffer(resumeTimeLabel: "23m"),
                             colorScheme: .dark),
                colorScheme: .dark
            ),
            as: .image,
            named: "dark-with-time"
        )
    }

    func testResumePrompt_withTime_light() {
        assertSnapshot(
            of: render(
                snapshotView(offer: ResumePromptOffer(resumeTimeLabel: "23m"),
                             colorScheme: .light),
                colorScheme: .light
            ),
            as: .image,
            named: "light-with-time"
        )
    }

    // MARK: - Without resume time (duration unknown)

    func testResumePrompt_noTime_dark() {
        assertSnapshot(
            of: render(
                snapshotView(offer: ResumePromptOffer(resumeTimeLabel: nil),
                             colorScheme: .dark),
                colorScheme: .dark
            ),
            as: .image,
            named: "dark-no-time"
        )
    }

    func testResumePrompt_noTime_light() {
        assertSnapshot(
            of: render(
                snapshotView(offer: ResumePromptOffer(resumeTimeLabel: nil),
                             colorScheme: .light),
                colorScheme: .light
            ),
            as: .image,
            named: "light-no-time"
        )
    }
}
