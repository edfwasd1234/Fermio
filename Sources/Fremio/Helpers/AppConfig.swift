import Foundation

/// Central place for app-wide configuration: the TMDB API key and a shared,
/// timeout-configured URLSession. Keeping these in one spot avoids the key being
/// duplicated across the codebase and gives every network call sane timeouts.
enum AppConfig {
    /// Fallback TMDB key used when the user hasn't entered their own in Settings.
    static let defaultTMDBApiKey = "3d421899d5ce93db8ad4ae4591ccc130"

    /// The TMDB API key currently in effect (user-provided override, else the default).
    static var tmdbApiKey: String {
        let key = UserDefaults.standard.string(forKey: "tmdbApiKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty == false ? key! : defaultTMDBApiKey)
    }

    static let tmdbBaseURL = "https://api.themoviedb.org/3"

    /// Shared session with request/resource timeouts so a dead upstream server
    /// can't hang a resolution chain indefinitely.
    static let httpSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
}
