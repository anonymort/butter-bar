// Self-test for gateway ↔ planner wiring.
// Activated when the EngineService process is launched with the argument
//   --gateway-planner-self-test
// Exits 0 on pass, 1 on failure.
//
// SUPERSEDED: this test's coverage (HTTP parse → planner event → bridge calls
// → byte read) is fully exercised by `--stream-e2e-self-test` against a real
// public-domain torrent. The original implementation relied on the synthetic
// `createTestTorrent` helper, which is known to fail inside the XPC sandbox
// (GitHub #94). Synthetic 10 MB single-file content was also a weaker
// validation than a real multi-file torrent.
//
// Retained as a no-op shim so the launch argument continues to exit 0 for any
// scripts wired to it, while directing readers toward the real test.

#if DEBUG

import Foundation

/// Runs the (now-superseded) gateway-planner self-test. Returns no failures.
func runGatewayPlannerSelfTests() -> [String] {
    NSLog("[GatewayPlannerSelfTest] superseded by --stream-e2e-self-test " +
          "(GitHub #94). Skipping; run --stream-e2e-self-test <magnet> for " +
          "real end-to-end coverage.")
    return []
}

/// Entry point called from main.swift when --gateway-planner-self-test is passed.
func runGatewayPlannerSelfTestAndExit() {
    _ = runGatewayPlannerSelfTests()
    NSLog("[GatewayPlannerSelfTest] Shim exit — no assertions run.")
    exit(0)
}

#endif // DEBUG
