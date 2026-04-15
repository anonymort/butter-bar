# 05 — Cache Policy

> **Revision 2** — resume offset weakened to byte-last-served (addendum A6, no byte→time map in v1); `settings` and `pinned_files` table schemas added (addendum A7). Baseline revision was rev 1.

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

libtorrent doesn't have a direct "delete piece" API, but it does have per-piece priority. Eviction works as:

1. Set priority of target pieces to `0` (do not download).
2. Call libtorrent's file-level API to truncate regions where possible, or mark them for future overwrite.
3. Update in-memory `havePieces()` view accordingly so the planner sees the eviction immediately.

Note: libtorrent may retain some piece data in its buffer cache temporarily. That's fine — the accounting is based on our view of the sparse file, not libtorrent's internal buffers.

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
- Talk to libtorrent for anything other than piece priorities and file truncation.
- Make UI decisions about "are you sure?" prompts — it just reports pressure.

## Test obligations

- Unit tests for eviction ordering with synthetic sparse-file state.
- Test that pinned pieces are never selected, regardless of LRU position.
- Test that crossing thresholds emits exactly one `DiskPressureDTO` per crossing (not a storm).
- Test resume offset restoration across engine restarts.
