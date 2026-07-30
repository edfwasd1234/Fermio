import Foundation
import Observation

/// Single source of truth for the user's library: watchlist, favorites, and
/// continue-watching progress. Replaces the ad-hoc `UserDefaults` blob access
/// and `NotificationCenter` string events that used to be scattered across the
/// views. Data is persisted as JSON files in Application Support (UserDefaults
/// is not meant to hold growing record arrays).
@MainActor
@Observable
final class LibraryStore {
    static let shared = LibraryStore()

    private(set) var watchlist: [MediaItem] = []
    private(set) var favorites: [MediaItem] = []
    private(set) var continueWatching: [WatchProgress] = []

    /// Cap so the continue-watching list can't grow without bound.
    private let maxContinueWatching = 40

    private let watchlistFile = "watchlist.json"
    private let favoritesFile = "favorites.json"
    private let continueFile = "continue_watching.json"

    private init() {
        migrateFromUserDefaultsIfNeeded()
        watchlist = load([MediaItem].self, from: watchlistFile) ?? []
        favorites = load([MediaItem].self, from: favoritesFile) ?? []
        continueWatching = load([WatchProgress].self, from: continueFile) ?? []
    }

    // MARK: - Watchlist

    func isInWatchlist(_ item: MediaItem) -> Bool {
        watchlist.contains { $0.id == item.id && $0.type == item.type }
    }

    /// Toggles membership. Returns `true` if the item is now in the watchlist.
    @discardableResult
    func toggleWatchlist(_ item: MediaItem) -> Bool {
        if let idx = watchlist.firstIndex(where: { $0.id == item.id && $0.type == item.type }) {
            watchlist.remove(at: idx)
            save(watchlist, to: watchlistFile)
            return false
        }
        watchlist.insert(item, at: 0)
        save(watchlist, to: watchlistFile)
        return true
    }

    func removeFromWatchlist(_ item: MediaItem) {
        watchlist.removeAll { $0.id == item.id && $0.type == item.type }
        save(watchlist, to: watchlistFile)
    }

    // MARK: - Favorites

    func isFavorite(_ item: MediaItem) -> Bool {
        favorites.contains { $0.id == item.id && $0.type == item.type }
    }

    /// Toggles membership. Returns `true` if the item is now a favorite.
    @discardableResult
    func toggleFavorite(_ item: MediaItem) -> Bool {
        if let idx = favorites.firstIndex(where: { $0.id == item.id && $0.type == item.type }) {
            favorites.remove(at: idx)
            save(favorites, to: favoritesFile)
            return false
        }
        favorites.insert(item, at: 0)
        save(favorites, to: favoritesFile)
        return true
    }

    func removeFromFavorites(_ item: MediaItem) {
        favorites.removeAll { $0.id == item.id && $0.type == item.type }
        save(favorites, to: favoritesFile)
    }

    // MARK: - Continue watching

    func savedPosition(mediaId: String, type: MediaType, season: Int, episode: Int) -> Double {
        continueWatching.first {
            matches($0, mediaId: mediaId, type: type, season: season, episode: episode)
        }?.currentPosition ?? 0
    }

    /// Records playback progress. Drops the record entirely once the title is
    /// effectively finished (>= 95%), and only writes a single file.
    func updateProgress(item: MediaItem, season: Int, episode: Int, current: Double, total: Double) {
        guard current > 10 else { return }

        continueWatching.removeAll {
            matches($0, mediaId: item.id, type: item.type, season: season, episode: episode)
        }

        if total <= 0 || current < total * 0.95 {
            let progress = WatchProgress(
                mediaId: item.id,
                title: item.title,
                type: item.type,
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                posterColorHex: item.posterColorHex,
                posterSymbol: item.posterSymbol,
                genre: item.genre,
                rating: item.rating,
                releaseYear: item.releaseYear,
                duration: item.duration,
                description: item.description,
                season: season,
                episode: episode,
                currentPosition: current,
                totalDuration: total,
                lastWatched: Date()
            )
            continueWatching.insert(progress, at: 0)
        }

        if continueWatching.count > maxContinueWatching {
            continueWatching = Array(continueWatching.prefix(maxContinueWatching))
        }

        save(continueWatching, to: continueFile)
    }

    private func matches(_ p: WatchProgress, mediaId: String, type: MediaType, season: Int, episode: Int) -> Bool {
        if type == .movie {
            return p.mediaId == mediaId && p.type == .movie
        }
        return p.mediaId == mediaId && p.season == season && p.episode == episode
    }

    // MARK: - Persistence

    private var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private func load<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let url = directory?.appendingPathComponent(file),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to file: String) {
        guard let url = directory?.appendingPathComponent(file),
              let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// One-time import of pre-existing data from the old UserDefaults keys.
    private func migrateFromUserDefaultsIfNeeded() {
        migrate(userDefaultsKey: "watchlist_items", to: watchlistFile)
        migrate(userDefaultsKey: "favorite_items", to: favoritesFile)
        migrate(userDefaultsKey: "continue_watching_items", to: continueFile)
    }

    private func migrate(userDefaultsKey: String, to file: String) {
        guard let url = directory?.appendingPathComponent(file),
              !FileManager.default.fileExists(atPath: url.path),
              let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        // The old data is JSON for the same Codable types, so the bytes copy directly.
        try? data.write(to: url, options: .atomic)
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
