import Foundation

/// Represents a Movie or TV Show in the Fremio app.
struct MediaItem: Identifiable, Hashable, Codable {
    let id: String // TMDB ID
    let title: String
    let type: MediaType
    let posterPath: String? // TMDB poster path
    let backdropPath: String? // TMDB backdrop path
    let posterSymbol: String // Fallback SF Symbol name
    let posterColorHex: String // Fallback Color theme hex
    let genre: String
    let rating: Double
    let releaseYear: Int
    let duration: String
    let description: String
    let isTrending: Bool
    let isNewRelease: Bool
}

enum MediaType: String, CaseIterable, Codable {
    case movie = "Movie"
    case show = "TV Show"
}

extension MediaItem {
    static let mockData: [MediaItem] = [
        MediaItem(
            id: "550",
            title: "Fight Club",
            type: .movie,
            posterPath: nil,
            backdropPath: nil,
            posterSymbol: "sparkles",
            posterColorHex: "FF5E62",
            genre: "Drama",
            rating: 4.8,
            releaseYear: 1999,
            duration: "2h 19m",
            description: "An insomniac office worker and a devil-care soap maker form an underground fight club.",
            isTrending: true,
            isNewRelease: false
        ),
        MediaItem(
            id: "1339713",
            title: "Obsession",
            type: .movie,
            posterPath: nil,
            backdropPath: nil,
            posterSymbol: "sparkles",
            posterColorHex: "FF5E62",
            genre: "Sci-Fi",
            rating: 4.8,
            releaseYear: 2026,
            duration: "2h 34m",
            description: "An astronaut's journey to the outer rim of the galaxy, finding unexpected anomalies that threaten space-time.",
            isTrending: true,
            isNewRelease: true
        ),
        MediaItem(
            id: "603",
            title: "The Matrix",
            type: .movie,
            posterPath: nil,
            backdropPath: nil,
            posterSymbol: "bolt.car.fill",
            posterColorHex: "00F2FE",
            genre: "Sci-Fi",
            rating: 4.9,
            releaseYear: 1999,
            duration: "2h 16m",
            description: "A computer hacker learns from mysterious rebels about the true nature of his reality.",
            isTrending: true,
            isNewRelease: true
        ),
        MediaItem(
            id: "fake_noir",
            title: "Chronicles of Noir",
            type: .show,
            posterPath: nil,
            backdropPath: nil,
            posterSymbol: "moon.stars.fill",
            posterColorHex: "5E50F9",
            genre: "Mystery",
            rating: 4.5,
            releaseYear: 2025,
            duration: "3 Seasons",
            description: "A dark detective series set in a neo-steampunk city where dreams can be sold on the black market.",
            isTrending: true,
            isNewRelease: false
        ),
        MediaItem(
            id: "fake_velocity",
            title: "Velocity Shift",
            type: .movie,
            posterPath: nil,
            backdropPath: nil,
            posterSymbol: "bolt.car.fill",
            posterColorHex: "00F2FE",
            genre: "Action",
            rating: 4.2,
            releaseYear: 2026,
            duration: "1h 58m",
            description: "Underground street racers get caught up in an international espionage plot that requires high-octane skill.",
            isTrending: false,
            isNewRelease: true
        ),
        MediaItem(
            id: "fake_forest",
            title: "The Silent Forest",
            type: .movie,
            posterPath: nil,
            backdropPath: nil,
            posterSymbol: "leaf.fill",
            posterColorHex: "1D976C",
            genre: "Thriller",
            rating: 4.6,
            releaseYear: 2024,
            duration: "2h 05m",
            description: "A biologist discovers an intelligence inside an ancient forest that communicates through mycelial networks.",
            isTrending: true,
            isNewRelease: false
        ),
        MediaItem(
            id: "fake_pioneers",
            title: "Pixel Pioneers",
            type: .show,
            posterPath: nil,
            backdropPath: nil,
            posterSymbol: "gamecontroller.fill",
            posterColorHex: "F39C12",
            genre: "Documentary",
            rating: 4.9,
            releaseYear: 2025,
            duration: "1 Season",
            description: "The history and rapid evolution of the early game developers who transformed lines of code into a multi-billion dollar medium.",
            isTrending: false,
            isNewRelease: true
        ),
        MediaItem(
            id: "fake_cyber",
            title: "Cyber City: Edge",
            type: .show,
            posterPath: nil,
            backdropPath: nil,
            posterSymbol: "cpu",
            posterColorHex: "FF007F",
            genre: "Cyberpunk",
            rating: 4.7,
            releaseYear: 2026,
            duration: "2 Seasons",
            description: "A hacker and a rogue AI team up to overthrow a megacorporation controlling the city's neural network.",
            isTrending: true,
            isNewRelease: true
        )
    ]
}
