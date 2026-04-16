// Self-test exercising every TorrentBridge method.
// Activated when the EngineService process is launched with the argument
//   --bridge-self-test
// Exits 0 on pass, 1 on failure.
//
// SUPERSEDED: this test's coverage is fully exercised by
// `--stream-e2e-self-test` against a real public-domain torrent, which calls
// addMagnet/addTorrentFile, listFiles, pieceLength, havePieces, readBytes,
// fileByteRange, and subscribeAlerts end-to-end. The original implementation
// here relied on the synthetic `createTestTorrent` helper which (a) fails
// inside the XPC sandbox and (b) produces single-file fixed-byte content that
// tells you nothing about real torrents (GitHub #94).
//
// Retained as a no-op shim so the launch argument continues to exit 0 for any
// scripts wired to it, while directing readers toward the real test.

#if DEBUG

import Foundation

/// Runs the (now-superseded) bridge self-test. Returns no failures.
func runBridgeSelfTests() -> [String] {
    NSLog("[BridgeSelfTest] superseded by --stream-e2e-self-test " +
          "(GitHub #94). Skipping; run --stream-e2e-self-test <magnet> for " +
          "real bridge coverage against a real torrent.")
    return []
}

/// Entry point called from main.swift when --bridge-self-test is passed.
func runBridgeSelfTestAndExit() {
    _ = runBridgeSelfTests()
    NSLog("[BridgeSelfTest] Shim exit — no assertions run.")
    exit(0)
}

#endif // DEBUG
