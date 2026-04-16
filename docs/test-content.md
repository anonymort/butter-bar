# Test Content for Stream E2E Verification

## Automated self-test (`--stream-e2e-self-test`)

The self-test exercises the full HTTP serving path against a real torrent:

```
TorrentBridge → metadata → StreamRegistry.createStream → GatewayListener → URLSession
```

It requires a real magnet link or `.torrent` file — no synthetic content is generated.

### Invocation

```bash
# Using a magnet link (recommended):
/path/to/EngineService.xpc/Contents/MacOS/EngineService \
  --stream-e2e-self-test \
  'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969'

# Using a .torrent file:
/path/to/EngineService.xpc/Contents/MacOS/EngineService \
  --stream-e2e-self-test /path/to/file.torrent

# With explicit file index (default: largest file in torrent):
/path/to/EngineService.xpc/Contents/MacOS/EngineService \
  --stream-e2e-self-test <magnet-or-path> --file-index 0
```

Build the EngineService product first:

```bash
xcodebuild -scheme EngineService -configuration Debug build 2>&1 | tail -10
```

The built product is typically at:
```
~/Library/Developer/Xcode/DerivedData/ButterBar-*/Build/Products/Debug/EngineService.xpc/Contents/MacOS/EngineService
```

Exit code 0 = all tests passed. Exit code 1 = failure (FAIL lines in NSLog output).
Exit code 2 = timeout (no metadata or pieces within the wait window).

Downloaded content is left in `NSTemporaryDirectory()` after the test — reruns skip re-downloading.

### What the self-test verifies

- `HEAD` → 200, `Content-Length` matches the file size in the torrent
- `GET Range: bytes=0-65535` → 206, correct `Content-Range`, 65536 bytes
- `GET Range: bytes=<mid>-<mid+1023>` (inside first 8 downloaded pieces) → 206, correct body
- `GET /stream/<unknown-id>` → 404
- Byte accuracy: HTTP response bytes match `TorrentBridge.readBytes` exactly

### Suggested test magnet

**Big Buck Bunny** (Blender Foundation, CC BY 3.0) — Internet Archive, well-seeded ~276 MB MP4:

```
magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969
```

---

## Manual AVPlayer smoke test

For human-in-the-loop playback verification (AVPlayer with a real torrent), use a small
public-domain video from the Internet Archive.

### Suggested test torrents

**Elephants Dream** (Blender Foundation, CC BY 2.5)
- Internet Archive page: <https://archive.org/details/ElephantsDream>
- Direct `.torrent`: <https://archive.org/download/ElephantsDream/ElephantsDream_archive.torrent>
- Size: ~100 MB, single-file `.mp4`, AVFoundation-native codec (H.264)

**Big Buck Bunny** (Blender Foundation, CC BY 3.0)
- Internet Archive page: <https://archive.org/details/BigBuckBunny_124>
- Magnet: `magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplorer.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com`
- Size: ~276 MB, H.264/AAC `.mp4`, no transcoding needed

Both are confirmed AVFoundation-compatible.

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
