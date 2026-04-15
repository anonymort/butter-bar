# Test Content for Stream E2E Verification

## Self-test approach

The automated E2E self-test (`--stream-e2e-self-test`) requires no external network access.
It creates a 256 KB file of sequential bytes (`UInt8(offset & 0xFF)`) in a temp directory,
builds a `.torrent` from it using `TorrentBridge.createTestTorrent`, and immediately adds
it to a `TorrentBridge` session. Because the source data is local, libtorrent marks all
pieces as available within seconds (no peer connections required).

The test then exercises the full stack:

```
TorrentBridge → ByteReader → PlaybackSession → StreamRegistry → GatewayListener → URLSession
```

Verified assertions:
- HEAD → 200, correct `Content-Length`
- GET `bytes=0-1023` → 206, correct `Content-Range`, exact sequential bytes
- GET `bytes=1024-2047` → 206, exact sequential bytes at that offset
- GET (no Range header) → 200 or 206, full file body
- Spot-check byte values at offsets 0, 256, 1024, and end-of-file

### How to run

Build and run the EngineService product with the launch argument:

```
xcodebuild -scheme EngineService build CODE_SIGN_IDENTITY=- 2>&1 | tail -5
```

Then locate the built product and run:

```bash
/path/to/EngineService.xpc/Contents/MacOS/EngineService --stream-e2e-self-test
```

Or set `--stream-e2e-self-test` as a launch argument in the Xcode scheme
(Product → Scheme → Edit Scheme → Arguments Passed On Launch).

Exit code 0 means all tests passed. Exit code 1 prints the specific failure
messages and exits.

The earlier `--gateway-planner-self-test` mode runs a broader set of wiring
tests using a 10 MB file and is a superset of this test; both modes are
available for targeted debugging.

---

## Manual testing with real public-domain content

For human-in-the-loop playback verification (AVPlayer smoke test with a real
torrent), use a small public-domain video from the Internet Archive.

### Suggested test torrent

**Elephants Dream** (Blender Foundation, CC BY 2.5)
- Internet Archive page: <https://archive.org/details/ElephantsDream>
- Direct `.torrent`: <https://archive.org/download/ElephantsDream/ElephantsDream_archive.torrent>
- Size: ~100 MB, single-file `.mp4`, AVFoundation-native codec (H.264)

**Big Buck Bunny** (Blender Foundation, CC BY 3.0)
- Internet Archive page: <https://archive.org/details/BigBuckBunny_124>
- Magnet: `magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplorer.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com`
- Size: ~276 MB, H.264/AAC `.mp4`, no transcoding needed

Both are confirmed AVFoundation-compatible. Neither requires any tracker or DHT
connection when sourced from the Internet Archive `.torrent` file directly.

### Manual verification checklist

1. Add the torrent via the XPC `addMagnet:` or `addTorrentFileAtPath:` call.
2. Wait for the gateway URL to be available (stream registered in `StreamRegistry`).
3. Open the gateway URL in `AVPlayer`: `AVPlayer(url: gatewayURL)`.
4. Verify:
   - [ ] Video begins playing within 5 seconds of pieces becoming available.
   - [ ] Seeking works (AVPlayer issues Range requests; verify 206 responses in logs).
   - [ ] No stalls longer than 2 seconds during normal playback.
   - [ ] Audio and video are in sync.
5. Check Console.app / `NSLog` output for `[GatewayListener]`, `[StreamRegistry]`,
   and `[ByteReader]` messages — no errors expected under normal conditions.
