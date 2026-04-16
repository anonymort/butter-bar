#!/usr/bin/env bash
set -euo pipefail
# Runs the planner seek bench. Use --record to update docs/benchmarks/seek-baseline.json.
RECORD=0
for arg in "$@"; do
  case "$arg" in
    --record) RECORD=1 ;;
  esac
done
cd "$(dirname "$0")/.."
if [ "$RECORD" = "1" ]; then
  BUTTERBAR_RECORD_SEEK_BASELINE=1 swift test --package-path Packages/PlannerCore --filter PlannerSeekBenchRecorder
  echo "Baseline written to docs/benchmarks/seek-baseline.json"
else
  swift test --package-path Packages/PlannerCore --filter PlannerSeekBench
fi
