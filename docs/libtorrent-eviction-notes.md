# libtorrent eviction probe — investigation notes

## Probe run (2026-04-16)

First attempt to run `EngineService --cache-eviction-probe` revealed a blocker upstream of eviction itself.

### pbxproj fixes applied before run

1. **UUID collision** — the T-UI-LIBRARY follow-up added a `PBXContainerItemProxy` with UUID `AA11BB22CC33DD44EE55FF66`, which collided with an existing `PBXBuildFile` entry for `EngineClient.swift`. Xcode refused to open the project with "unrecognized selector sent to instance" on PBXContainerItemProxy. Fixed by reassigning the proxy to `D1000001000000000000DD01`.

2. **Missing target registration** — `CacheEvictionProbe.swift` existed on disk but was never added to the EngineService Xcode target (no PBXFileReference, no PBXBuildFile, no group membership, no Sources build phase entry). Added under UUIDs `E1000001000000000000EE01` (build file) and `E1000002000000000000EE02` (file reference).

3. **Swift compile error** — `data.withUnsafeMutableBytes { ptr in ... ptr[i] = ... }` was ambiguous. Fixed with explicit `(ptr: UnsafeMutableRawBufferPointer)` annotation.

### Probe failure: createTestTorrent returns "Operation canceled"

After fixing the above, the probe runs but fails immediately on the `createTestTorrent` step:

```
[CacheEvictionProbe] === T-CACHE-EVICTION probe starting ===
[CacheEvictionProbe] Setup: wrote 262144 byte source file at /Users/.../source/probe.bin
[CacheEvictionProbe] ERROR: createTestTorrent failed: Error Domain=com.butterbar.engine Code=4 "Operation canceled"
```

### Root cause: T-STREAM-E2E was never runtime-verified

Running the same helper via `--stream-e2e-self-test`:

```
[StreamE2ESelfTest] Starting end-to-end stream self-test…
[StreamE2ESelfTest] FAILED — 1 failure(s):
[StreamE2ESelfTest]   FAIL: createTestTorrent threw: Error Domain=com.butterbar.engine Code=4 "Operation canceled" (line 66)
```

Both the probe and T-STREAM-E2E fail with the exact same error. This means the `createTestTorrent` helper added in T-BRIDGE-API has never actually executed successfully — Phase 5's Opus review of T-STREAM-E2E was a code review only, not a runtime verification. The task acceptance criteria ("recorded video of successful playback committed") was always going to surface this.

### Where the error comes from

Error code 4 = `TorrentBridgeErrorReadError`, returned from `createTestTorrent` in `TorrentBridge.mm` when `lt::set_piece_hashes(ct, sourceDir, ec)` writes into `ec`. The message "Operation canceled" is libtorrent/boost asio's generic cancellation error, returned nearly instantly (microseconds between the file-write log and the error), which suggests libtorrent bails before doing any real hashing work.

### Hypotheses to investigate

1. **Sandbox / entitlements.** EngineService is an XPC service with App Sandbox enabled. Container path is `~/Library/Containers/com.butterbar.app.EngineService/Data/tmp/...`. libtorrent's `add_files` might enumerate the directory successfully (returning `num_files() > 0`), but `set_piece_hashes` might then hit a permission denial when opening the file for hashing — and on macOS APFS through boost asio, this can surface as "Operation canceled" rather than EPERM.

2. **libtorrent 2.0.12 API change.** The 2.x series may require a disk_io_thread or explicit session/ioc to be set up before `set_piece_hashes` can run. The synchronous overload may have been removed or require extra setup.

3. **Entitlement missing.** The EngineService may need `com.apple.security.temporary-exception.files.absolute-path.read-only` or similar to read its own sandbox container paths under `~/Library/Containers/`.

### Resolution: probe rewritten to bypass createTestTorrent

The probe no longer uses `createTestTorrent`. Instead it accepts a real magnet link or
`.torrent` file path on the command line, bypassing the sandboxed hash-creation step
entirely. `addMagnet` is already known to work in the XPC sandbox (used by XPC tests).

## Running the probe (new interface)

Build EngineService in Debug configuration first:

```
xcodebuild -scheme EngineService -configuration Debug build
```

Then run with a magnet link. The Internet Archive Big Buck Bunny torrent (~160 MB MP4)
is well-seeded and small enough to make a practical probe target:

```
/path/to/EngineService.xpc/Contents/MacOS/EngineService \
  --cache-eviction-probe \
  "magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969"
```

To probe a specific file (e.g. file index 2 in a multi-file torrent):

```
EngineService --cache-eviction-probe "magnet:..." --file-index 2
```

To probe a local `.torrent` file:

```
EngineService --cache-eviction-probe /path/to/file.torrent
```

Running without arguments prints usage and exits 1.

### What the probe logs

1. **Setup** — torrent ID, save path, piece length
2. **File list** — all files with index, path, size
3. **Selected file** — which file was probed (largest by default)
4. **Metadata wait** — times out at 60s with exit 2 if no metadata arrives
5. **Download wait** — waits up to 120s for ≥8 pieces; reports progress every 10s
6. **Probe A** — baseline stat before priority change
7. **Probe B** — stat immediately and 2s after `setFilePriority(0)`
8. **Probe C** — F_PUNCHHOLE + ftruncate attempts, libtorrent's view after each
9. **Probe D** — stat after restoring `setFilePriority(1)`, re-fetch wait

### Where downloaded content lives

Downloaded files are saved to `NSTemporaryDirectory()` — the same save path
`addMagnet` always uses (hardcoded in `TorrentBridge.mm`). On macOS inside the
EngineService sandbox this is typically:

```
~/Library/Containers/com.butterbar.app.EngineService/Data/tmp/
```

The probe intentionally leaves content there after finishing so re-runs are fast.

### Timeout exit codes

- `exit(1)` — bad arguments / usage error
- `exit(2)` — `METADATA_TIMEOUT` (60s) or `DOWNLOAD_TIMEOUT` (120s)
- `exit(0)` — probes ran to completion

### Pending observations

Paste NSLog output here after running:

- Probe A: baseline file size + on-disk bytes before eviction
- Probe B: behavior when `setFilePriority(priority:0)` is called
- Probe C: fcntl F_PUNCHHOLE + ftruncate attempts against the real file
- Probe D: re-fetch behavior when priority restored to 1

### Implications for Phase 5

The `createTestTorrent` blocker is now bypassed at the probe level. T-STREAM-E2E
still needs a fix for `createTestTorrent` if it is to run end-to-end — that is a
separate task. The cache-eviction probe can now run independently using a real magnet.

