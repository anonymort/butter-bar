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

## Deferred: regression gate threshold

The `regression_threshold_pct` field in the baseline JSON is currently `null`. Specs
02/04/05 do not name a numerical seek-to-first-frame SLA. Follow-up issue
[#107](https://github.com/anonymort/butter-bar/issues/107) (tagged `[opus]`) will define:

- A numerical SLA per fixture
- A regression threshold percentage for CI
- Whether to gate PRs on regressions

Until that issue is resolved, the bench is **advisory only** — it does not fail builds.
