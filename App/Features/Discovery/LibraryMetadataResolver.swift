import Foundation
import EngineInterface
import LibraryDomain
import MetadataDomain

// MARK: - LibraryMetadataResolver
//
// #17 — Continue-watching projection enricher. Joins Phase 1's playback
// history + Phase 4's metadata foundation into the rows the home screen
// renders. See `docs/design/discovery-metadata-foundation.md § D9`.
//
// Pure orchestration: takes engine state + a `MetadataProvider`, returns
// `[ContinueWatchingItem]`. No SwiftUI imports; the caller owns publication.
//
// Caching:
// - Match results are cached by file name (per § D9 step 6) for 30 days
//   (`MetadataCacheTTL.matchResult`). Clock is injectable so tests can
//   assert TTL behaviour without sleeping.
// - A negative result (no match cleared the threshold) is cached too, so a
//   miss doesn't re-search every render.

@MainActor
final class LibraryMetadataResolver {

    /// Default minimum confidence for a candidate to be considered a match.
    /// Mirrors `MatchRanker.defaultThreshold` (`0.6`) but lifted into the
    /// resolver so tests can override.
    static let defaultThreshold: Double = MatchRanker.defaultThreshold

    /// Default cap on the number of items shown in the row. Per AC: 10.
    static let defaultMaxItems: Int = 10

    private let provider: MetadataProvider
    private let clock: () -> Date
    private let threshold: Double
    private let maxItems: Int
    private let ttl: TimeInterval

    /// Match cache, keyed by file name. Holds both positive matches (a
    /// `MediaItem` cleared the threshold) and negative matches (`nil` —
    /// nothing did). Both entry kinds expire under the same TTL.
    private var cache: [String: CachedMatch] = [:]

    init(provider: MetadataProvider,
         clock: @escaping () -> Date = Date.init,
         threshold: Double = LibraryMetadataResolver.defaultThreshold,
         maxItems: Int = LibraryMetadataResolver.defaultMaxItems,
         ttl: TimeInterval = MetadataCacheTTL.matchResult) {
        self.provider = provider
        self.clock = clock
        self.threshold = threshold
        self.maxItems = maxItems
        self.ttl = ttl
    }

    // MARK: - Resolve

    /// Build the continue-watching projection. The caller supplies:
    /// - `history`: every `playback_history` row currently held by the engine.
    /// - `torrents`: the corresponding torrents (for `name` + `totalBytes`).
    /// - `fileNameLookup`: closure that resolves a `(torrentID, fileIndex)`
    ///   to the file's path string. Wraps `engineClient.listFiles` at the
    ///   call site so the resolver remains test-friendly. Returning `nil`
    ///   falls back to the torrent name.
    ///
    /// Pipeline (per design § D9):
    ///   1. Filter to `.inProgress` / `.reWatching`.
    ///   2. Sort desc by `lastPlayedAt`. Cap at `maxItems`. Doing this
    ///      *before* metadata enrichment bounds the network work.
    ///   3. For each survivor: file name → parser → search → ranker.
    ///   4. Cache the match (positive or negative) under the file name.
    ///   5. Build the `ContinueWatchingItem` (matched fields if confidence
    ///      ≥ threshold; raw torrent name otherwise).
    func resolve(
        history: [PlaybackHistoryDTO],
        torrents: [TorrentSummaryDTO],
        fileNameLookup: (String, Int) async -> String?
    ) async -> [ContinueWatchingItem] {
        let torrentByID = Dictionary(uniqueKeysWithValues: torrents.map {
            ($0.torrentID as String, $0)
        })

        // Step 1+2: filter to in-progress / re-watching, sort desc, cap.
        let rows: [Row] = history.compactMap { dto in
            guard let torrent = torrentByID[dto.torrentID as String] else {
                return nil
            }
            let status = WatchStatus.from(history: dto, totalBytes: torrent.totalBytes)
            switch status {
            case .inProgress(let p, let t):
                return Row(torrent: torrent, history: dto,
                           progressBytes: p, totalBytes: t,
                           isReWatching: false)
            case .reWatching(let p, let t, _):
                return Row(torrent: torrent, history: dto,
                           progressBytes: p, totalBytes: t,
                           isReWatching: true)
            case .unwatched, .watched:
                return nil
            }
        }
        .sorted { $0.history.lastPlayedAt > $1.history.lastPlayedAt }
        .prefix(maxItems)
        .map { $0 }

        // Step 3+4+5: enrich each surviving row with metadata.
        var items: [ContinueWatchingItem] = []
        items.reserveCapacity(rows.count)

        for row in rows {
            let torrentID = row.torrent.torrentID as String
            let fileIndex = Int(row.history.fileIndex)
            let fileName = await fileNameLookup(torrentID, fileIndex)
                ?? (row.torrent.name as String)
            let match = await match(forFileName: fileName)
            items.append(buildItem(row: row, fileIndex: fileIndex, match: match))
        }

        return items
    }

    // MARK: - Cache invalidation

    /// Drop a single cache entry. Called when the engine reports a file
    /// rename so the next resolve re-parses + re-searches.
    func invalidate(fileName: String) {
        cache.removeValue(forKey: fileName)
    }

    /// Drop everything. Called when the metadata source itself changes
    /// (provider swap, manual refresh).
    func invalidateAll() {
        cache.removeAll()
    }

    // MARK: - Match pipeline

    /// Resolve a file name to a (possibly nil) match. Hits the cache first;
    /// a fresh entry — even a negative one — short-circuits the search.
    private func match(forFileName fileName: String) async -> MatchResolution {
        if let cached = cache[fileName],
           cached.expiresAt > clock().timeIntervalSince1970 {
            return cached.resolution
        }

        let parsed = TitleNameParser.parse(fileName)
        let candidates: [MediaItem]
        do {
            candidates = try await provider.searchMulti(query: parsed.title)
        } catch {
            // Transport / rate-limit / 4xx — render unmatched. We don't
            // poison the cache on transient failures: the next render gets
            // another chance.
            return .unmatched
        }

        let ranked = MatchRanker.rank(parsed: parsed, candidates: candidates)
        let resolution: MatchResolution
        if let top = ranked.first, top.confidence >= threshold {
            let designator = episodeDesignator(parsed: parsed, candidate: top.item)
            resolution = .matched(item: top.item, episodeDesignator: designator)
        } else {
            resolution = .unmatched
        }

        cache[fileName] = CachedMatch(
            resolution: resolution,
            expiresAt: clock().timeIntervalSince1970 + ttl
        )
        return resolution
    }

    /// "S01E04" / "S02" / nil. Only emitted when the parsed input has the
    /// markers AND the matched candidate is a show.
    private func episodeDesignator(parsed: ParsedTitle, candidate: MediaItem) -> String? {
        guard case .show = candidate else { return nil }
        guard let season = parsed.season else { return nil }
        if let episode = parsed.episode {
            return String(format: "S%02dE%02d", season, episode)
        }
        return String(format: "S%02d", season)
    }

    private struct CachedMatch {
        let resolution: MatchResolution
        /// Wall-clock seconds since 1970.
        let expiresAt: TimeInterval
    }

    private enum MatchResolution {
        case matched(item: MediaItem, episodeDesignator: String?)
        case unmatched
    }

    private func buildItem(row: Row, fileIndex: Int, match: MatchResolution) -> ContinueWatchingItem {
        switch match {
        case .matched(let item, let designator):
            let posterPath: String?
            switch item {
            case .movie(let m): posterPath = m.posterPath
            case .show(let s): posterPath = s.posterPath
            }
            return ContinueWatchingItem(
                torrent: row.torrent,
                fileIndex: fileIndex,
                progressBytes: row.progressBytes,
                totalBytes: row.totalBytes,
                lastPlayedAtMillis: row.history.lastPlayedAt,
                isReWatching: row.isReWatching,
                media: item,
                posterPath: posterPath,
                episodeDesignator: designator
            )
        case .unmatched:
            return ContinueWatchingItem(
                torrent: row.torrent,
                fileIndex: fileIndex,
                progressBytes: row.progressBytes,
                totalBytes: row.totalBytes,
                lastPlayedAtMillis: row.history.lastPlayedAt,
                isReWatching: row.isReWatching,
                media: nil,
                posterPath: nil,
                episodeDesignator: nil
            )
        }
    }

    // MARK: - Internal types lifted out for resolve()'s closure capture

    private struct Row {
        let torrent: TorrentSummaryDTO
        let history: PlaybackHistoryDTO
        let progressBytes: Int64
        let totalBytes: Int64
        let isReWatching: Bool
    }
}
