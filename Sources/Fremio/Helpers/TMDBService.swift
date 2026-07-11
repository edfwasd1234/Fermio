import Foundation

/// A service to query movie and show metadata from TMDB and cache responses.
@MainActor
class TMDBService {
    static let shared = TMDBService()
    
    private let cacheDirectoryName = "tmdb_cache"
    
    // Default API Key from fluxtv.cc fallback
    private var apiKey: String {
        UserDefaults.standard.string(forKey: "tmdbApiKey") ?? "3d421899d5ce93db8ad4ae4591ccc130"
    }
    
    private var baseUrl: String {
        "https://api.themoviedb.org/3"
    }
    
    private init() {
        createCacheDirectoryIfNeeded()
    }
    
    // MARK: - Caching Logic
    
    private var cacheDirectoryURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(cacheDirectoryName)
    }
    
    private func createCacheDirectoryIfNeeded() {
        guard let url = cacheDirectoryURL else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    /// Clears all files in the metadata cache directory.
    func clearCache() {
        guard let url = cacheDirectoryURL else { return }
        let fileURLs = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for fileURL in fileURLs {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    private struct CacheEntry<T: Codable>: Codable {
        let date: Date
        let value: T
    }
    
    private func saveToCache<T: Codable>(key: String, value: T) {
        guard let dirURL = cacheDirectoryURL else { return }
        let fileURL = dirURL.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
        let entry = CacheEntry(date: Date(), value: value)
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: fileURL)
        }
    }
    
    private func loadFromCache<T: Codable>(key: String, expiration: TimeInterval = 86400) -> T? {
        guard let dirURL = cacheDirectoryURL else { return nil }
        let fileURL = dirURL.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let entry = try? JSONDecoder().decode(CacheEntry<T>.self, from: data) else { return nil }
        
        // Check if cache has expired
        if Date().timeIntervalSince(entry.date) > expiration {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return entry.value
    }
    
    // MARK: - API Calls
    
    private func fetch<T: Codable>(path: String, queryParams: [String: String] = [:], cacheKey: String, expiration: TimeInterval = 86400) async throws -> T {
        if let cached: T = loadFromCache(key: cacheKey, expiration: expiration) {
            return cached
        }
        
        var urlComponents = URLComponents(string: "\(baseUrl)\(path)")
        var queryItems = [URLQueryItem(name: "api_key", value: apiKey)]
        for (k, v) in queryParams {
            queryItems.append(URLQueryItem(name: k, value: v))
        }
        urlComponents?.queryItems = queryItems
        
        guard let url = urlComponents?.url else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        let decoded = try JSONDecoder().decode(T.self, from: data)
        saveToCache(key: cacheKey, value: decoded)
        return decoded
    }
    
    // MARK: - Public Endpoints
    
    func fetchTrending(type: MediaType) async throws -> [MediaItem] {
        let path = type == .movie ? "/trending/movie/week" : "/trending/tv/week"
        let response: TMDBPageResponse = try await fetch(path: path, cacheKey: "trending_\(type.rawValue)", expiration: 43200) // 12 hours
        return response.results.map { mapResultToMediaItem($0, type: type, isTrending: true, isNewRelease: false) }
    }
    
    func fetchPopular(type: MediaType) async throws -> [MediaItem] {
        let path = type == .movie ? "/movie/popular" : "/tv/popular"
        let response: TMDBPageResponse = try await fetch(path: path, cacheKey: "popular_\(type.rawValue)", expiration: 43200) // 12 hours
        return response.results.map { mapResultToMediaItem($0, type: type, isTrending: false, isNewRelease: true) }
    }
    
    func search(query: String) async throws -> [MediaItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let path = "/search/multi"
        let response: TMDBPageResponse = try await fetch(
            path: path,
            queryParams: ["query": query, "include_adult": "false"],
            cacheKey: "search_\(query)",
            expiration: 3600 // 1 hour for search queries
        )
        
        return response.results.compactMap { result in
            guard let mediaTypeStr = result.media_type else { return nil }
            let type: MediaType
            if mediaTypeStr == "movie" {
                type = .movie
            } else if mediaTypeStr == "tv" {
                type = .show
            } else {
                return nil
            }
            return mapResultToMediaItem(result, type: type, isTrending: false, isNewRelease: false)
        }
    }
    
    func fetchDetails(type: MediaType, id: String) async throws -> MediaItem {
        let path = "/\(type == .movie ? "movie" : "tv")/\(id)"
        let detail: TMDBDetailResponse = try await fetch(path: path, cacheKey: "detail_\(type.rawValue)_\(id)", expiration: 86400 * 7) // 1 week
        
        let durationStr: String
        if type == .movie {
            if let runtime = detail.runtime, runtime > 0 {
                let hours = runtime / 60
                let minutes = runtime % 60
                durationStr = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
            } else {
                durationStr = "Unknown"
            }
        } else {
            let seasonCount = detail.number_of_seasons ?? 1
            durationStr = seasonCount == 1 ? "1 Season" : "\(seasonCount) Seasons"
        }
        
        let yearStr = (type == .movie ? detail.release_date : detail.first_air_date) ?? ""
        let year = Int(yearStr.prefix(4)) ?? 2026
        
        let genreStr = detail.genres?.first?.name ?? "Drama"
        
        return MediaItem(
            id: id,
            title: (type == .movie ? detail.title : detail.name) ?? "Untitled",
            type: type,
            posterPath: detail.poster_path,
            backdropPath: detail.backdrop_path,
            posterSymbol: type == .movie ? "film" : "tv",
            posterColorHex: getColorForGenre(genreStr),
            genre: genreStr,
            rating: (detail.vote_average ?? 0) / 2.0, // scale 0-10 to 0-5
            releaseYear: year,
            duration: durationStr,
            description: detail.overview ?? "",
            isTrending: false,
            isNewRelease: false
        )
    }
    
    func fetchEpisodes(tvId: String, seasonNumber: Int) async throws -> [TMDBEpisode] {
        let path = "/tv/\(tvId)/season/\(seasonNumber)"
        let response: TMDBSeasonResponse = try await fetch(path: path, cacheKey: "episodes_\(tvId)_\(seasonNumber)", expiration: 86400) // 24 hours
        return response.episodes ?? []
    }
    
    func fetchSimilar(type: MediaType, id: String) async throws -> [MediaItem] {
        let path = "/\(type == .movie ? "movie" : "tv")/\(id)/similar"
        let response: TMDBPageResponse = try await fetch(path: path, cacheKey: "similar_\(type.rawValue)_\(id)", expiration: 86400) // 24 hours
        return response.results.map { mapResultToMediaItem($0, type: type, isTrending: false, isNewRelease: false) }
    }
    
    // MARK: - Mappings
    
    private func mapResultToMediaItem(_ result: TMDBResult, type: MediaType, isTrending: Bool, isNewRelease: Bool) -> MediaItem {
        let title = (type == .movie ? result.title : result.name) ?? "Untitled"
        let yearStr = (type == .movie ? result.release_date : result.first_air_date) ?? ""
        let year = Int(yearStr.prefix(4)) ?? 2026
        let genreStr = result.genre_ids?.first.flatMap { getGenreName(from: $0) } ?? "Drama"
        
        return MediaItem(
            id: String(result.id),
            title: title,
            type: type,
            posterPath: result.poster_path,
            backdropPath: result.backdrop_path,
            posterSymbol: type == .movie ? "film" : "tv",
            posterColorHex: getColorForGenre(genreStr),
            genre: genreStr,
            rating: (result.vote_average ?? 0) / 2.0, // scale 0-10 to 0-5
            releaseYear: year,
            duration: type == .movie ? "Movie" : "TV Show",
            description: result.overview ?? "",
            isTrending: isTrending,
            isNewRelease: isNewRelease
        )
    }
    
    private func getGenreName(from id: Int) -> String {
        let genres: [Int: String] = [
            28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy",
            80: "Crime", 99: "Documentary", 18: "Drama", 10751: "Family",
            14: "Fantasy", 36: "History", 27: "Horror", 10402: "Music",
            9648: "Mystery", 10749: "Romance", 878: "Sci-Fi", 10770: "TV Movie",
            53: "Thriller", 10752: "War", 37: "Western",
            // TV Specific Genres
            10759: "Action & Adventure", 10762: "Kids", 10763: "News",
            10764: "Reality", 10765: "Sci-Fi & Fantasy", 10766: "Soap",
            10767: "Talk", 10768: "War & Politics"
        ]
        return genres[id] ?? "Drama"
    }
    
    private func getColorForGenre(_ genre: String) -> String {
        switch genre {
        case "Action", "Horror", "Thriller", "Action & Adventure":
            return "FF5E62" // Red-orange
        case "Sci-Fi", "Fantasy", "Sci-Fi & Fantasy", "Cyberpunk":
            return "00F2FE" // Cyan
        case "Mystery", "Drama", "Crime", "Romance":
            return "5E50F9" // Indigo
        case "Animation", "Comedy", "Family", "Kids":
            return "F39C12" // Amber
        default:
            return "1D976C" // Emerald
        }
    }
}

// MARK: - Decodable TMDB structures

struct TMDBPageResponse: Codable {
    let results: [TMDBResult]
}

struct TMDBResult: Codable {
    let id: Int
    let title: String?
    let name: String?
    let poster_path: String?
    let backdrop_path: String?
    let release_date: String?
    let first_air_date: String?
    let vote_average: Double?
    let overview: String?
    let genre_ids: [Int]?
    let media_type: String?
}

struct TMDBDetailResponse: Codable {
    let id: Int
    let title: String?
    let name: String?
    let poster_path: String?
    let backdrop_path: String?
    let release_date: String?
    let first_air_date: String?
    let vote_average: Double?
    let overview: String?
    let runtime: Int?
    let number_of_seasons: Int?
    let genres: [TMDBGenre]?
}

struct TMDBGenre: Codable {
    let id: Int
    let name: String?
}

struct TMDBSeasonResponse: Codable {
    let episodes: [TMDBEpisode]?
}

struct TMDBEpisode: Codable, Identifiable {
    var id: Int { episode_number }
    let name: String?
    let overview: String?
    let episode_number: Int
    let season_number: Int
    let still_path: String?
}
