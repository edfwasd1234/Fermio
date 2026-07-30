import Foundation

/// A single "continue watching" record. For movies the identity is the media id;
/// for shows it also includes the season and episode.
struct WatchProgress: Codable, Identifiable {
    var id: String {
        type == .movie ? mediaId : "\(mediaId)_S\(season)_E\(episode)"
    }
    let mediaId: String
    let title: String
    let type: MediaType
    let posterPath: String?
    let backdropPath: String?
    let posterColorHex: String
    let posterSymbol: String
    let genre: String
    let rating: Double
    let releaseYear: Int
    let duration: String
    let description: String
    let season: Int
    let episode: Int
    let currentPosition: Double
    let totalDuration: Double
    let lastWatched: Date
}
