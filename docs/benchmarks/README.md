# Planner Seek Bench

## What this measures

Replay wall-clock time for `DefaultPiecePlanner.handle(event:)` across each of the four
trace fixtures. This is a **planner-only** bench — no real network, no libtorrent, no
AVFoundation. It catches planner-side regressions such as accidental O(N²) algorithms or
allocation storms.

The planner path is synchronous and deterministic: given an event stream it produces an
action list in a single pass. Typical replay time for the current fixture set is in the
sub-millisecond range on Apple silicon.

True user-visible seek latency (from `PlayerEvent.get` to first decoded frame) also
includes libtorrent piece fetch and AVFoundation decode time. That end-to-end measurement
is not captured here; it is deferred to a follow-up task once a numerical SLA is defined.

## How to run

**XCTest measure bench** (5 iterations, XCTest stores baseline on acceptance in Xcode UI):

```bash
./scripts/run-seek-bench.sh
# or directly:
swift test --package-path Packages/PlannerCore --filter PlannerSeekBench
```

**Baseline recorder** (20 iterations, writes `docs/benchmarks/seek-baseline.json`):

```bash
./scripts/run-seek-bench.sh --record
# or directly:
BUTTERBAR_RECORD_SEEK_BASELINE=1 swift test \
  --package-path Packages/PlannerCore \
  --filter PlannerSeekBenchRecorder
```

The recorder test is skipped unless `BUTTERBAR_RECORD_SEEK_BASELINE=1` is set, so normal
`swift test` runs do not touch the baseline file.

## Where the baseline lives

`docs/benchmarks/seek-baseline.json` — committed to the repo. The file records p50, p90,
and max replay time in milliseconds per fixture, along with the git commit hash and host
info at recording time.

The baseline reflects the hardware it was recorded on. Numbers will differ across machines;
the file is advisory, not a hard gate.

## Regression threshold

`regression_threshold_pct` is **50.0** (per `00-addendum.md` A25). Applied uniformly across
fixtures: a regression is anything where replay time exceeds `(1 + 50/100) * p90` of the
committed baseline. Tight enough to catch O(N²) or allocation-storm regressions (both
move replay ≥ 10×); generous enough to absorb sub-ms measurement noise and host-drift
between local arm64 and CI macos-26 runners.

**CI policy: advisory only.** The bench runs on PRs for visibility but does not gate
merges. Sub-ms measurements across heterogeneous silicon produce flaky signal unrelated to
code quality. Headline regressions are triaged manually by Opus.

**End-to-end seek SLA** (from `PlayerEvent.get` to first decoded frame) is explicitly
deferred to v1.5+ — it requires a real-network harness and a decoder-side measurement,
neither of which exist in v1. See A25 for the full reasoning.
