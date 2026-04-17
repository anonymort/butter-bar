import Combine
import EngineInterface
import Foundation
import MetadataDomain

struct EpisodeLibraryMatch: Equatable, Sendable {
    let torrentID: String
    let fileIndex: Int32
    let displayName: String
}

enum EpisodeWatchBadge: Equatable, Sendable {
    case unwatched
    case inProgress
    case watched

    var label: String? {
        switch self {
        case .unwatched: return nil
        case .inProgress: return "In progress"
        case .watched: return "Watched"
        }
    }
}

struct EpisodeRow: Identifiable, Equatable, Sendable {
    var id: MediaID { episode.id }
    let episode: Episode
    let badge: EpisodeWatchBadge
    let match: EpisodeLibraryMatch?
}

enum SeasonEpisodeSelectorState: Equatable {
    case loading
    case loaded
    case error
}

@MainActor
final class SeasonEpisodeSelectorViewModel: ObservableObject {
    @Published private(set) var state: SeasonEpisodeSelectorState = .loading
    @Published private(set) var selectedSeasonNumber: Int
    @Published private(set) var episodeRows: [EpisodeRow] = []

    let show: Show
    var seasons: [Season] { availableSeasons }

    private let provider: MetadataProvider
    private let historyProvider: () async throws -> [PlaybackHistoryDTO]
    private let torrentProvider: () async throws -> [TorrentSummaryDTO]
    private let fileProvider: (String) async throws -> [TorrentFileDTO]
    private let eventsProvider: () async -> EngineEventHandler?
    private let threshold: Double

    private var availableSeasons: [Season]
    private var loadedSeasons: [Int: Season]
    private var playbackHistory: [PlaybackHistoryDTO] = []
    private var libraryFiles: [LibraryFile] = []
    private var historySubscription: AnyCancellable?

    init(show: Show,
         provider: MetadataProvider,
         engineClient: EngineClient? = nil,
         historyProvider: (() async throws -> [PlaybackHistoryDTO])? = nil,
         torrentProvider: (() async throws -> [TorrentSummaryDTO])? = nil,
         fileProvider: (((String) async throws -> [TorrentFileDTO]))? = nil,
         eventsProvider: (() async -> EngineEventHandler?)? = nil,
         threshold: Double = MatchRanker.defaultThreshold) {
        self.show = show
        self.provider = provider
        self.availableSeasons = show.seasons.sorted { lhs, rhs in
            if lhs.seasonNumber == 0 { return false }
            if rhs.seasonNumber == 0 { return true }
            return lhs.seasonNumber < rhs.seasonNumber
        }
        self.loadedSeasons = Dictionary(uniqueKeysWithValues: show.seasons.map { ($0.seasonNumber, $0) })
        self.selectedSeasonNumber = Self.defaultSeasonNumber(from: show.seasons)
        self.threshold = threshold

        if let historyProvider {
            self.historyProvider = historyProvider
        } else if let engineClient {
            self.historyProvider = { try await engineClient.listPlaybackHistory() }
        } else {
            self.historyProvider = { [] }
        }

        if let torrentProvider {
            self.torrentProvider = torrentProvider
        } else if let engineClient {
            self.torrentProvider = { try await engineClient.listTorrents() }
        } else {
            self.torrentProvider = { [] }
        }

        if let fileProvider {
            self.fileProvider = fileProvider
        } else if let engineClient {
            self.fileProvider = { torrentID in
                try await engineClient.listFiles(torrentID as NSString)
            }
        } else {
            self.fileProvider = { _ in [] }
        }

        if let eventsProvider {
            self.eventsProvider = eventsProvider
        } else if let engineClient {
            self.eventsProvider = { await engineClient.events }
        } else {
            self.eventsProvider = { nil }
        }
    }

    func load() async {
        await refreshWatchState()
        await subscribeToHistoryChanges()
        await selectSeason(selectedSeasonNumber)
    }

    func selectSeason(_ seasonNumber: Int) async {
        selectedSeasonNumber = seasonNumber
        state = .loading
        do {
            let season = try await seasonDetail(seasonNumber)
            loadedSeasons[seasonNumber] = season
            mergeSeason(season)
            episodeRows = buildRows(for: season)
            state = .loaded
        } catch {
            state = .error
        }
    }

    func retry() async {
        await selectSeason(selectedSeasonNumber)
    }

    func posterURL(_ path: String) -> URL {
        provider.imageURL(path: path, size: .w300)
    }

    func _setWatchStateForTesting(history: [PlaybackHistoryDTO], files: [LibraryFile]) {
        playbackHistory = history
        libraryFiles = files
        if let season = loadedSeasons[selectedSeasonNumber] {
            episodeRows = buildRows(for: season)
        }
    }

    private static func defaultSeasonNumber(from seasons: [Season]) -> Int {
        if let withEpisodes = seasons
            .filter({ !$0.episodes.isEmpty && $0.seasonNumber != 0 })
            .max(by: { $0.seasonNumber < $1.seasonNumber }) {
            return withEpisodes.seasonNumber
        }
        if let newest = seasons
            .filter({ $0.seasonNumber != 0 })
            .max(by: { $0.seasonNumber < $1.seasonNumber }) {
            return newest.seasonNumber
        }
        return seasons.max(by: { $0.seasonNumber < $1.seasonNumber })?.seasonNumber ?? 1
    }

    private func seasonDetail(_ seasonNumber: Int) async throws -> Season {
        if let cached = loadedSeasons[seasonNumber], !cached.episodes.isEmpty {
            return cached
        }
        return try await provider.seasonDetail(showID: show.id, season: seasonNumber)
    }

    private func mergeSeason(_ season: Season) {
        if !availableSeasons.contains(where: { $0.seasonNumber == season.seasonNumber }) {
            availableSeasons.append(season)
        } else {
            availableSeasons = availableSeasons.map {
                $0.seasonNumber == season.seasonNumber ? season : $0
            }
        }
        availableSeasons.sort { lhs, rhs in
            if lhs.seasonNumber == 0 { return false }
            if rhs.seasonNumber == 0 { return true }
            return lhs.seasonNumber < rhs.seasonNumber
        }
    }

    private func refreshWatchState() async {
        do {
            playbackHistory = try await historyProvider()
            let torrents = try await torrentProvider()
            var files: [LibraryFile] = []
            for torrent in torrents {
                let torrentID = torrent.torrentID as String
                let torrentFiles = (try? await fileProvider(torrentID)) ?? []
                for file in torrentFiles where file.isPlayableByAVFoundation {
                    files.append(LibraryFile(
                        torrentID: torrentID,
                        fileIndex: file.fileIndex,
                        displayName: file.path as String
                    ))
                }
            }
            libraryFiles = files
        } catch {
            playbackHistory = []
            libraryFiles = []
        }
    }

    private func subscribeToHistoryChanges() async {
        guard historySubscription == nil else { return }
        guard let events = await eventsProvider() else { return }
        historySubscription = events.playbackHistoryChangedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] row in
                guard let self else { return }
                self.applyHistoryChange(row)
            }
    }

    private func applyHistoryChange(_ row: PlaybackHistoryDTO) {
        playbackHistory.removeAll {
            ($0.torrentID as String) == (row.torrentID as String)
                && $0.fileIndex == row.fileIndex
        }
        playbackHistory.append(row)
        if let season = loadedSeasons[selectedSeasonNumber] {
            episodeRows = buildRows(for: season)
        }
    }

    private func buildRows(for season: Season) -> [EpisodeRow] {
        season.episodes
            .sorted { $0.episodeNumber < $1.episodeNumber }
            .map { episode in
                let match = matchLibraryFile(for: episode)
                let badge = watchBadge(for: match)
                return EpisodeRow(episode: episode, badge: badge, match: match)
            }
    }

    private func matchLibraryFile(for episode: Episode) -> EpisodeLibraryMatch? {
        for file in libraryFiles {
            let parsed = TitleNameParser.parse(file.displayName)
            guard parsed.season == episode.seasonNumber,
                  parsed.episode == episode.episodeNumber else {
                continue
            }
            let ranked = MatchRanker.rank(parsed: parsed, candidates: [.show(show)])
            guard let top = ranked.first, top.confidence >= threshold else { continue }
            return EpisodeLibraryMatch(
                torrentID: file.torrentID,
                fileIndex: file.fileIndex,
                displayName: file.displayName
            )
        }
        return nil
    }

    private func watchBadge(for match: EpisodeLibraryMatch?) -> EpisodeWatchBadge {
        guard let match else { return .unwatched }
        guard let row = playbackHistory.first(where: {
            ($0.torrentID as String) == match.torrentID && $0.fileIndex == match.fileIndex
        }) else {
            return .unwatched
        }
        if row.completed { return .watched }
        if row.resumeByteOffset > 0 { return .inProgress }
        return .unwatched
    }
}

struct LibraryFile: Equatable, Sendable {
    let torrentID: String
    let fileIndex: Int32
    let displayName: String
}
