# 05 — Cache Policy

> **Revision 4** — § Piece eviction mechanism rewritten again after probe run #3 (2026-04-16) empirically disproved the addPiece/hash-fail hot path in libtorrent 2.0.12. The new mechanism is `F_PUNCHHOLE` + `force_recheck()` (addendum A24). Rev 3 proposed add_piece+punch (A23, now retracted). Rev 2 weakened resume offset to byte-last-served (A6) and added `settings` + `pinned_files` schemas (A7).

Cache eviction is piece-granular, not file-granular. The unit of value is "pieces the user is likely to need next," not "whole torrents."

## Storage model

- Each torrent has a sparse file on disk (managed by libtorrent).
- `playback_history` table records per-file state including `resumeByteOffset`.
- `CacheManager` maintains an in-memory pinned set and an LRU of evictable piece ranges.

## Budgeting

Two thresholds, both user-configurable:

- **High-water mark** — when `usedBytes >= highWater`, eviction starts.
- **Low-water mark** — eviction runs until `usedBytes <= lowWater`.

Defaults: `highWater = 50 GB`, `lowWater = 40 GB`. Settings UI exposes both.

## Pinned set (never evictable)

The following pieces are pinned:

1. **Active stream window.** For every open `StreamSession`, the pieces covering `[playheadByte - 5 MB, playheadByte + readaheadBytes]`.
2. **Resume cushion.** For every file with `resumeByteOffset > 0`, the pieces covering `[0, resumeByteOffset + 16 MB]`. This means "you can resume watching and get 16 MB of runway before eviction bites."
3. **Explicitly kept files.** Items the user has marked "keep" in the UI. Stored in the `pinned_files` table (see Schema below) as `(torrent_id, file_index)` rows.

Everything else is evictable.

## Eviction order

When eviction runs (`usedBytes > highWater`), remove pieces in this order until `usedBytes <= lowWater`:

1. Pieces belonging to files that are **not pinned**, **not marked keep**, and have **no playback history**. Oldest first by torrent-added-time.
2. Pieces belonging to files that **have playback history** but are **fully watched** (`resumeByteOffset == 0` after completion marker). Oldest first by `lastPlayedAt`.
3. Pieces in the tail of partially-watched files — everything beyond the resume cushion. Oldest first by `lastPlayedAt`.
4. Pieces in the head of partially-watched files (before `resumeByteOffset`). Last resort. Should almost never happen at reasonable budget sizes.

At no point does eviction touch a pinned piece.

## Piece eviction mechanism

Per addendum A24. Probe run #3 (2026-04-16) empirically disproved the A23 hot path: `add_piece(zeros, overwrite_existing)` does not emit `hash_failed_alert` in libtorrent 2.0.12 at any file priority, so that sequencing cannot drive `async_clear_piece`. What the probe did prove works:

- `fcntl(F_PUNCHHOLE)` over a **block-aligned sub-range** within a piece reclaims APFS blocks cleanly. Piece-aligned alone is insufficient for multi-file torrents where the target file does not start on a piece boundary — the offset must be 4 KiB-aligned relative to the file's byte space. A small amount (up to ~8 KiB per piece) is forfeited at the boundary for correctness.
- `torrent_handle::force_recheck()` rereads the sparse file and updates the have-bitmap accordingly. A punched piece hashes differently, so libtorrent removes it from the bitmap. On a 275 MB, fully-resident torrent, the recheck completes in ~0.5 s on Apple silicon.
- `hash_failed_alert` is NOT emitted during `force_recheck` — it is only raised for peer-download hash failures. The eviction path therefore does not depend on alerts; it waits on `statusSnapshot` state transitions instead.

### The eviction primitive

For each eviction batch:

1. For every piece to evict in the batch: compute the piece's byte range in the file (`[piece * pieceLength - fileStart, (piece + 1) * pieceLength - fileStart)`), then derive the block-aligned sub-range:
   - `alignedStart = ceil(pieceStartInFile / 4096) * 4096`
   - `alignedEnd = floor(pieceEndInFile / 4096) * 4096`
   - `alignedLen = alignedEnd - alignedStart`
   If `alignedLen > 0`, `fcntl(fd, F_PUNCHHOLE, {offset: alignedStart, length: alignedLen})`. Pieces whose aligned sub-range collapses to zero bytes are skipped (extremely rare — requires pieceLength < 8 KiB).
2. Before punching, set the file's `setFilePriority` to 0 (if not already) so peers do not immediately re-request the missing pieces. CacheManager enforces that only files outside the pinned set are eligible — those files are already at priority=0 or will be set to 0 as part of the eviction batch.
3. After punching every piece in the batch: `TorrentBridge.forceRecheck(torrentID)`. Poll `statusSnapshot` every 500 ms until `state` is neither `checkingResumeData` nor `checkingFiles`.
4. The have-bitmap now reflects disk reality. `AlertDispatcher` observes the resulting `state_changed` alerts and pushes an update to the planner.
5. When the user later wants to play an evicted file, CacheManager restores priority and libtorrent re-fetches the missing pieces through the normal deadline/priority pipeline.

### Cost and batching

- Punch: O(1) per piece, completes in a few milliseconds.
- `force_recheck`: O(on-disk bytes). The probe measured ~0.5 s / 275 MB. Scales roughly linearly with data volume.

Eviction runs are therefore batched: when `usedBytes > highWater`, CacheManager selects enough pieces to push below `lowWater`, punches them all, then issues a single `forceRecheck` per affected torrent. The cost of `force_recheck` is paid once per batch per torrent, not once per piece.

`force_recheck` disconnects peers and stops tracker announcements during the check; the torrent is placed at the end of the session queue when the check completes. Eviction runs are therefore scheduled away from the streaming hot path — during idle periods or as part of "user opened the pause/settings screen." CacheManager never runs a recheck on a torrent that has an active stream. If disk pressure crosses `highWater` while every torrent is actively streaming, CacheManager emits `DiskPressureDTO(state: critical)` and defers; once the streams close, eviction runs immediately.

### Why this beats rev 3's design

- No dependency on `hash_failed_alert`, which turned out not to fire in the `add_piece`/overwrite path in 2.0.12.
- No dependency on an implementation detail of libtorrent's write-then-verify ordering; we control the verify explicitly via `force_recheck`.
- Simpler: one primitive (`forceRecheck`) plus a POSIX syscall (`fcntl(F_PUNCHHOLE)`) is the entire mechanism.
- `TorrentBridge.addPiece` is retained as a general wrapper but is not part of the eviction path; its header doc was updated in A24 to reflect this.

### Budget accounting

`CacheManager` tracks `usedBytes` as the sum of on-disk allocated bytes across every sparse file it manages, sampled via `stat().st_blocks * 512` after each eviction batch. Per-piece accounting is not maintained — libtorrent's buffer cache and APFS block-granularity rounding make per-piece byte counts unreliable. The budget is enforced against the aggregate.

## Disk pressure signalling

Engine emits `DiskPressureDTO` when:

- Crossing from `ok` → `warn` (used > 80% of highWater).
- Crossing from `warn` → `critical` (used > highWater, eviction running).
- Crossing back down.

Throttle: at most 1 emission per 5 seconds.

## Resume offset persistence (v1)

**Scope:** v1 does not implement a byte→time map. `resume_byte_offset` is persisted as **the last byte offset successfully served to the player** during a stream session. On resume, the UI offers "continue from where you stopped" which issues a fresh stream open; AVPlayer seeks to a reasonable keyframe near that byte offset. This is approximate but good enough for v1.

A true byte→time map is deferred to v1.5+. It will require container parsing (MP4 `mvhd`/`stbl`, Matroska cues) which is out of scope for v1.

### Schema

```sql
CREATE TABLE playback_history (
    torrent_id TEXT NOT NULL,
    file_index INTEGER NOT NULL,
    resume_byte_offset INTEGER NOT NULL,        -- last byte served, not time-accurate
    last_played_at INTEGER NOT NULL,            -- unix ms
    total_watched_seconds REAL NOT NULL DEFAULT 0,  -- populated from CMTime observations
    completed INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (torrent_id, file_index)
);

CREATE TABLE pinned_files (
    torrent_id TEXT NOT NULL,
    file_index INTEGER NOT NULL,
    pinned_at INTEGER NOT NULL,                 -- unix ms
    PRIMARY KEY (torrent_id, file_index)
);

CREATE TABLE settings (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL,                        -- JSON-encoded
    updated_at INTEGER NOT NULL                 -- unix ms
);
```

### Update rules

- Engine updates `resume_byte_offset` on stream close and on a 15-second interval during active playback.
- `total_watched_seconds` is incremented from AVPlayer's time observer callbacks on the app side and forwarded to the engine via a dedicated XPC method (deferred to v1.1; the column exists but stays at 0 in v1).
- `completed = 1` when `resume_byte_offset >= 0.95 * file_size`. On the next stream open, reset `resume_byte_offset = 0`.

### What this means for the UI

- "Continue watching" is byte-accurate, not time-accurate. A two-hour film resumed at 40 minutes will open at roughly the right place, give or take one keyframe.
- Progress bars in the library view should use `resume_byte_offset / file_size`, not any time-based computation, in v1.

## What CacheManager does not do

- Decide which torrents to add or remove.
- Serve bytes.
- Talk to libtorrent for anything other than piece priorities, add_piece, and force_recheck (see § Piece eviction mechanism).
- Make UI decisions about "are you sure?" prompts — it just reports pressure.

## Test obligations

- Unit tests for eviction ordering with synthetic sparse-file state.
- Test that pinned pieces are never selected, regardless of LRU position.
- Test that crossing thresholds emits exactly one `DiskPressureDTO` per crossing (not a storm).
- Test resume offset restoration across engine restarts.
- Test the eviction primitive: addPiece+punch cycle produces hash_failed_alert, removes the piece from havePieces, reduces on-disk bytes by one piece length. Covered by the revised `--cache-eviction-probe` run plus unit tests against a test double.
