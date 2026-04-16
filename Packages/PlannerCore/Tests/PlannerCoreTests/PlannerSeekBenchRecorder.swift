// PlannerSeekBenchRecorder.swift — Opt-in recorder that writes docs/benchmarks/seek-baseline.json.
//
// Skipped in normal test runs. Enable with:
//   BUTTERBAR_RECORD_SEEK_BASELINE=1 swift test \
//     --package-path Packages/PlannerCore \
//     --filter PlannerSeekBenchRecorder
//
// Or via the convenience wrapper:
//   ./scripts/run-seek-bench.sh --record

import XCTest
import Foundation
@testable import PlannerCore
import TestFixtures

final class PlannerSeekBenchRecorder: XCTestCase {

    private static let fixtureNames = [
        "front-moov-mp4-001",
        "back-moov-mp4-001",
        "mkv-cues-001",
        "immediate-seek-001",
    ]

    private static let sampleCount = 20

    func test_recordSeekBaseline() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["BUTTERBAR_RECORD_SEEK_BASELINE"] != "1",
            "Set BUTTERBAR_RECORD_SEEK_BASELINE=1 to record the seek baseline."
        )

        var fixtureResults: [String: FixtureResult] = [:]

        for name in Self.fixtureNames {
            let trace = try FixtureLoader.loadTrace(named: name)
            var samples: [Double] = []

            for _ in 0..<Self.sampleCount {
                let start = DispatchTime.now()
                replayTrace(trace)
                let end = DispatchTime.now()
                let elapsed = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
                samples.append(elapsed)
            }

            samples.sort()
            let p50 = percentile(samples, pct: 0.50)
            let p90 = percentile(samples, pct: 0.90)
            let maxMs = samples.last ?? 0

            // Count events and total actions for the baseline metadata.
            let eventCount = trace.events.count
            let actionCount = countActions(trace)

            fixtureResults[name] = FixtureResult(
                events: eventCount,
                actions: actionCount,
                replayMsP50: round3(p50),
                replayMsP90: round3(p90),
                replayMsMax: round3(maxMs),
                samples: Self.sampleCount
            )

            // Print per-fixture summary for CI visibility.
            print("[\(name)] events=\(eventCount) actions=\(actionCount) p50=\(round3(p50))ms p90=\(round3(p90))ms max=\(round3(maxMs))ms")
        }

        let baseline = Baseline(
            measuredAt: isoTimestamp(),
            plannerCommit: gitHead(),
            host: HostInfo(arch: uname_m(), osVersion: swVers()),
            fixtures: fixtureResults,
            regressionThresholdPct: nil,
            notes: "Threshold to be set by opus once SLA is defined. Bench currently advisory."
        )

        let outputURL = try outputFileURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(baseline)
        try data.write(to: outputURL, options: .atomic)

        print("Baseline written to \(outputURL.path)")
    }

    // MARK: - Replay

    private func replayTrace(_ trace: Trace) {
        let session = makeSession(from: trace)
        let planner = DefaultPiecePlanner()
        for event in trace.events {
            session.step(to: event.tMs)
            let plannerEvent = playerEvent(from: event)
            _ = planner.handle(event: plannerEvent, at: Instant(event.tMs), session: session)
        }
    }

    private func countActions(_ trace: Trace) -> Int {
        let session = makeSession(from: trace)
        let planner = DefaultPiecePlanner()
        var total = 0
        for event in trace.events {
            session.step(to: event.tMs)
            let plannerEvent = playerEvent(from: event)
            let actions = planner.handle(event: plannerEvent, at: Instant(event.tMs), session: session)
            total += actions.count
        }
        return total
    }

    private func makeSession(from trace: Trace) -> FakeTorrentSession {
        FakeTorrentSession(
            pieceLength: trace.pieceLength,
            fileByteRange: ByteRange(start: trace.fileByteRange.start, end: trace.fileByteRange.end),
            availabilitySchedule: trace.availabilitySchedule.map {
                AvailabilityEntry(tMs: $0.tMs, havePieces: $0.havePieces)
            },
            downloadRateSchedule: trace.downloadRateSchedule.map {
                ScalarEntry(tMs: $0.tMs, value: $0.bytesPerSec)
            },
            peerCountSchedule: trace.peerCountSchedule.map {
                ScalarEntry(tMs: $0.tMs, value: Int64($0.count))
            }
        )
    }

    private func playerEvent(from traceEvent: TraceEvent) -> PlayerEvent {
        switch traceEvent.kind {
        case .head:
            return .head
        case .get(let requestID, let rangeStart, let rangeEnd):
            return .get(requestID: requestID, range: ByteRange(start: rangeStart, end: rangeEnd))
        case .cancel(let requestID):
            return .cancel(requestID: requestID)
        }
    }

    // MARK: - Math helpers

    private func percentile(_ sorted: [Double], pct: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let idx = max(0, min(sorted.count - 1, Int((pct * Double(sorted.count)).rounded()) - 1))
        return sorted[idx]
    }

    private func round3(_ v: Double) -> Double {
        (v * 1000).rounded() / 1000
    }

    // MARK: - System info helpers

    private func isoTimestamp() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]
        return fmt.string(from: Date())
    }

    private func gitHead() -> String {
        shell("git", "rev-parse", "HEAD") ?? "unknown"
    }

    private func uname_m() -> String {
        shell("uname", "-m") ?? "unknown"
    }

    private func swVers() -> String {
        shell("sw_vers", "-productVersion") ?? "unknown"
    }

    private func shell(_ cmd: String, _ args: String...) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [cmd] + args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Output path

    /// Resolves docs/benchmarks/seek-baseline.json relative to the package root.
    /// The package root is the directory containing Package.swift for PlannerCore.
    private func outputFileURL() throws -> URL {
        // Walk up from the test bundle to find the repo root (contains scripts/).
        let repoRoot = try findRepoRoot()
        let dir = repoRoot.appendingPathComponent("docs/benchmarks", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("seek-baseline.json")
    }

    private func findRepoRoot() throws -> URL {
        // Start from the current working directory or the test bundle path.
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<10 {
            let marker = url.appendingPathComponent("scripts/pr-lifecycle-hook.sh")
            if FileManager.default.fileExists(atPath: marker.path) {
                return url
            }
            url = url.deletingLastPathComponent()
        }
        // Fallback: use current directory.
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

// MARK: - Codable output types

private struct Baseline: Encodable {
    let measuredAt: String
    let plannerCommit: String
    let host: HostInfo
    let fixtures: [String: FixtureResult]
    let regressionThresholdPct: Double?
    let notes: String

    enum CodingKeys: String, CodingKey {
        case measuredAt = "measured_at"
        case plannerCommit = "planner_commit"
        case host
        case fixtures
        case regressionThresholdPct = "regression_threshold_pct"
        case notes
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(measuredAt, forKey: .measuredAt)
        try container.encode(plannerCommit, forKey: .plannerCommit)
        try container.encode(host, forKey: .host)
        try container.encode(fixtures, forKey: .fixtures)
        // Encode nil explicitly so the field appears as `null` in JSON.
        try container.encode(regressionThresholdPct, forKey: .regressionThresholdPct)
        try container.encode(notes, forKey: .notes)
    }
}

private struct HostInfo: Encodable {
    let arch: String
    let osVersion: String

    enum CodingKeys: String, CodingKey {
        case arch
        case osVersion = "os_version"
    }
}

private struct FixtureResult: Encodable {
    let events: Int
    let actions: Int
    let replayMsP50: Double
    let replayMsP90: Double
    let replayMsMax: Double
    let samples: Int

    enum CodingKeys: String, CodingKey {
        case events
        case actions
        case replayMsP50 = "replay_ms_p50"
        case replayMsP90 = "replay_ms_p90"
        case replayMsMax = "replay_ms_max"
        case samples
    }
}
