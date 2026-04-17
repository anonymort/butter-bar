import XCTest
import Combine
import EngineInterface
import PlayerDomain
@testable import ButterBar

/// VM-level coverage of the failure → retry → re-open path (#26).
///
/// Contract per design `docs/design/player-state-foundation.md § D6` and
/// issue #26 AC:
///
/// 1. `userTappedRetry` from `.error(_)` projects through the state machine
///    to `.buffering(.openingStream)`.
/// 2. The VM re-issues `engine.openStream` with the original
///    `(torrentID, fileIndex)` captured at first open.
/// 3. On success the VM projects `.engineReturnedDescriptor` (back to `.open`).
/// 4. On failure the VM projects `.engineReturnedOpenError(_)` (back to
///    `.error(.streamOpenFailed(_))`). Retry remains available.
/// 5. Reconnect alone does NOT re-issue openStream — only the user can.
@MainActor
final class PlayerRetryPathTests: XCTestCase {

    // MARK: - Fixtures

    private static let torrentID = RetryFixtures.torrentID
    private static let fileIndex: Int32 = RetryFixtures.fileIndex

    // MARK: - Helper: drive VM into .error(.streamOpenFailed) without XPC

    /// Build a VM with a recording streamOpener that succeeds the first call
    /// (so the VM lands in `.open`) then forces `.error(.playbackFailed)` via
    /// the `injectFailure` event handle. We can't directly drive `.error`
    /// without exposing the seam; instead the VM exposes a test-only init.
    private func vmInError(
        opener: @escaping @Sendable (String, Int32) async throws -> StreamDescriptorDTO,
        historyProvider: @escaping () async throws -> [PlaybackHistoryDTO] = { [] }
    ) -> PlayerViewModel {
        let engine = EngineClient()
        let vm = PlayerViewModel(
            streamDescriptor: RetryFixtures.descriptor(),
            engineClient: engine,
            torrentID: Self.torrentID,
            fileIndex: Self.fileIndex,
            historyProvider: historyProvider,
            streamOpener: opener
        )
        // Force the VM into `.error(_)` by projecting `.avPlayerFailed` —
        // a `.open → .error(.playbackFailed)` edge that exists in the
        // state machine. `injectEventForTesting` is internal, exposed
        // only to the test target via `@testable`.
        vm.injectEventForTesting(.avPlayerFailed)
        return vm
    }

    // MARK: - 1. State transition

    func test_userTappedRetry_fromError_transitionsToBufferingOpeningStream() async throws {
        let opener: @Sendable (String, Int32) async throws -> StreamDescriptorDTO = { _, _ in
            // Block forever so we can observe the intermediate state.
            try await Task.sleep(for: .seconds(60))
            throw RetryFixtures.makeError()
        }
        let vm = vmInError(opener: opener)
        XCTAssertEqual(vm.state, .error(.playbackFailed))

        vm.retry()

        // Immediately after retry the VM must be back in
        // `.buffering(.openingStream)` per state machine.
        XCTAssertEqual(vm.state, .buffering(reason: .openingStream))
    }

    // MARK: - 2 + 3. Successful re-open

    func test_userTappedRetry_onSuccess_reissuesOpenStreamAndTransitionsToOpen() async throws {
        let callCount = AsyncCounter()
        let receivedID = AsyncBox<String>()
        let receivedIndex = AsyncBox<Int32>()
        let dto = RetryFixtures.descriptor(stream: "retry-success-stream")

        let opener: @Sendable (String, Int32) async throws -> StreamDescriptorDTO = { tid, idx in
            await callCount.increment()
            await receivedID.set(tid)
            await receivedIndex.set(idx)
            return dto
        }
        let vm = vmInError(opener: opener)

        // Record every state the VM publishes so we can assert it passed
        // through `.open` even if AVPlayer's reaction to the unreachable
        // test URL bumps it back out of `.open` quickly (which it does:
        // KVO on `AVPlayerItem.status` fires `.failed` after the loopback
        // request errors).
        let recorder = StateRecorder()
        let cancellable = vm.$state.sink { state in
            Task { await recorder.record(state) }
        }
        defer { cancellable.cancel() }

        vm.retry()

        try await assertEventually("openStream must be re-issued") {
            await callCount.value == 1
        }
        try await assertEventually("state stream should include .open after retry") {
            await recorder.contains(.open)
        }

        let observedID = await receivedID.value
        let observedIndex = await receivedIndex.value
        let count = await callCount.value
        XCTAssertEqual(observedID, Self.torrentID,
                       "openStream must be re-issued with the original torrentID")
        XCTAssertEqual(observedIndex, Self.fileIndex,
                       "openStream must be re-issued with the original fileIndex")
        XCTAssertEqual(count, 1, "exactly one openStream re-issue per retry")
    }

    // MARK: - 4. Failed re-open

    func test_userTappedRetry_onFailure_transitionsBackToError() async throws {
        let opener: @Sendable (String, Int32) async throws -> StreamDescriptorDTO = { _, _ in
            throw NSError(
                domain: EngineErrorDomain,
                code: EngineErrorCode.torrentNotFound.rawValue,
                userInfo: nil
            )
        }
        let vm = vmInError(opener: opener)

        vm.retry()

        try await assertEventually("VM should land back in .error after failing retry") {
            if case .error(.streamOpenFailed) = vm.state { return true }
            return false
        }
        XCTAssertEqual(vm.state, .error(.streamOpenFailed(.torrentNotFound)),
                       "engine error code must be preserved in the new error state")
    }

    // MARK: - 4b. Retry remains available after a failed retry

    func test_retryRemainsAvailable_afterFailedRetry() async throws {
        let callCount = AsyncCounter()
        let opener: @Sendable (String, Int32) async throws -> StreamDescriptorDTO = { _, _ in
            await callCount.increment()
            throw NSError(
                domain: EngineErrorDomain,
                code: EngineErrorCode.streamOpenFailed.rawValue,
                userInfo: nil
            )
        }
        let vm = vmInError(opener: opener)

        vm.retry()
        try await assertEventually("first retry should fail back to .error") {
            if case .error(.streamOpenFailed) = vm.state { return true }
            return false
        }

        vm.retry()
        try await assertEventually("second retry must also re-issue openStream") {
            await callCount.value >= 2
        }
        let total = await callCount.value
        XCTAssertEqual(total, 2, "retry must be issuable repeatedly")
    }

    // MARK: - 5. Retry is a no-op when identity is unknown

    func test_retry_withoutIdentity_doesNotCrashAndStaysInBuffering() async throws {
        // VM constructed without torrentID / fileIndex — retry has nothing
        // to re-issue. The state machine still transitions; the VM must
        // not crash and the opener must NOT be called.
        let callCount = AsyncCounter()
        let opener: @Sendable (String, Int32) async throws -> StreamDescriptorDTO = { _, _ in
            await callCount.increment()
            return RetryFixtures.descriptor()
        }
        let engine = EngineClient()
        let vm = PlayerViewModel(
            streamDescriptor: RetryFixtures.descriptor(),
            engineClient: engine,
            torrentID: nil,
            fileIndex: nil,
            historyProvider: { [] },
            streamOpener: opener
        )
        vm.injectEventForTesting(.avPlayerFailed)
        vm.retry()
        try await Task.sleep(for: .milliseconds(100))
        let count = await callCount.value
        XCTAssertEqual(count, 0, "no openStream re-issue when identity is missing")
        XCTAssertEqual(vm.state, .buffering(reason: .openingStream),
                       "state machine still transitions per its pure rules")
    }

    // MARK: - Helper

    private func assertEventually(
        _ message: String,
        timeout: Duration = .seconds(2),
        poll: Duration = .milliseconds(10),
        condition: @escaping () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: poll)
        }
        XCTFail("Timed out: \(message)")
    }
}

// MARK: - Test-only helpers (actor-isolated mutable state for @Sendable closures)

private actor AsyncCounter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

private actor AsyncBox<T: Sendable> {
    private var stored: T?
    func set(_ v: T) { stored = v }
    var value: T? { stored }
}

private actor StateRecorder {
    private var seen: [PlayerState] = []
    func record(_ s: PlayerState) { seen.append(s) }
    func contains(_ s: PlayerState) -> Bool { seen.contains(s) }
    var states: [PlayerState] { seen }
}

/// Fixtures kept outside the `@MainActor` test class so `@Sendable` closures
/// can call them without inheriting actor isolation.
private enum RetryFixtures {
    static let torrentID = "torrent-retry-test"
    static let fileIndex: Int32 = 0

    static func descriptor(stream: String = "stream-retry-test") -> StreamDescriptorDTO {
        StreamDescriptorDTO(
            streamID: stream as NSString,
            // Unreachable URL — AVPlayer won't actually load anything; we
            // assert on VM state only.
            loopbackURL: "http://127.0.0.1:1/stream/retry-test" as NSString,
            contentType: "video/mp4",
            contentLength: 100_000
        )
    }

    static func makeError(_ code: EngineErrorCode = .streamOpenFailed) -> NSError {
        NSError(
            domain: EngineErrorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "synthetic test failure"]
        )
    }
}
