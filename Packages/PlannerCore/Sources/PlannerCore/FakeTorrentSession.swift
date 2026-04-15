// FakeTorrentSession.swift — Test-support fake driven by pre-recorded schedules.
//
// Designed for deterministic replay tests: no real clocks, no threading, no I/O.
// The caller advances time via step(to:) and then queries state; the fake returns
// values from the most recent schedule entry at or before the current time.
//
// Availability schedule semantics: each entry's have_pieces list is a cumulative
// addition. Pieces, once present, are never lost. The returned BitSet is the
// union of all entries up to and including the current time.

// MARK: - Schedule entry types

/// A single entry in the availability schedule.
public struct AvailabilityEntry: Sendable {
    /// Time of this entry in milliseconds (relative to stream open).
    public let tMs: Int
    /// Pieces that become available at this timestamp. Cumulative additions only.
    public let havePieces: [Int]

    public init(tMs: Int, havePieces: [Int]) {
        self.tMs = tMs
        self.havePieces = havePieces
    }
}

/// A single entry in a scalar (rate or count) schedule.
public struct ScalarEntry: Sendable {
    /// Time of this entry in milliseconds.
    public let tMs: Int
    /// The value in effect from this timestamp onward.
    public let value: Int64

    public init(tMs: Int, value: Int64) {
        self.tMs = tMs
        self.value = value
    }
}

// MARK: - FakeTorrentSession

/// A fake TorrentSessionView driven by recorded schedules.
///
/// All schedules must be sorted ascending by tMs before passing to the initialiser.
/// step(to:) only moves time forward; passing a time earlier than the current
/// time is a no-op (not a fatal error, so callers do not need to guard against it).
public final class FakeTorrentSession: TorrentSessionView {

    // MARK: - TorrentSessionView static properties

    public let pieceLength: Int64
    public let fileByteRange: ByteRange

    // MARK: - Schedules (sorted ascending by tMs)

    private let availabilitySchedule: [AvailabilityEntry]
    private let downloadRateSchedule: [ScalarEntry]
    private let peerCountSchedule: [ScalarEntry]

    // MARK: - Mutable state

    /// Current virtual time in milliseconds.
    private var currentTimeMs: Int = 0

    /// Pieces available at or before currentTimeMs, accumulated incrementally.
    private var accumulatedPieces: BitSet = BitSet()

    /// Index of the last availability entry that has been applied.
    private var lastAppliedAvailabilityIndex: Int = -1

    // MARK: - Init

    public init(
        pieceLength: Int64,
        fileByteRange: ByteRange,
        availabilitySchedule: [AvailabilityEntry],
        downloadRateSchedule: [ScalarEntry],
        peerCountSchedule: [ScalarEntry]
    ) {
        self.pieceLength = pieceLength
        self.fileByteRange = fileByteRange
        self.availabilitySchedule = availabilitySchedule
        self.downloadRateSchedule = downloadRateSchedule
        self.peerCountSchedule = peerCountSchedule

        // Apply any entries at t=0 immediately so the initial state is correct.
        applyAvailabilityUpTo(timeMs: 0)
    }

    // MARK: - Time advancement

    /// Advances the virtual clock to timeMs. No-op if timeMs <= current time.
    public func step(to timeMs: Int) {
        guard timeMs > currentTimeMs else { return }
        currentTimeMs = timeMs
        applyAvailabilityUpTo(timeMs: timeMs)
    }

    // MARK: - TorrentSessionView queries

    public func havePieces() -> BitSet {
        accumulatedPieces
    }

    public func downloadRateBytesPerSec() -> Int64 {
        latestValue(in: downloadRateSchedule, at: currentTimeMs)
    }

    public func peerCount() -> Int {
        Int(latestValue(in: peerCountSchedule, at: currentTimeMs))
    }

    // MARK: - Private helpers

    /// Applies all availability entries with tMs <= timeMs that have not yet been applied.
    private func applyAvailabilityUpTo(timeMs: Int) {
        let startIndex = lastAppliedAvailabilityIndex + 1
        for i in startIndex..<availabilitySchedule.count {
            let entry = availabilitySchedule[i]
            guard entry.tMs <= timeMs else { break }
            for piece in entry.havePieces {
                accumulatedPieces.insert(piece)
            }
            lastAppliedAvailabilityIndex = i
        }
    }

    /// Returns the value from the most recent entry at or before timeMs.
    /// Returns 0 if no entry has tMs <= timeMs (safe default for both rate and count).
    private func latestValue(in schedule: [ScalarEntry], at timeMs: Int) -> Int64 {
        var result: Int64 = 0
        for entry in schedule {
            guard entry.tMs <= timeMs else { break }
            result = entry.value
        }
        return result
    }
}
