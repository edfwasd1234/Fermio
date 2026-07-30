import Foundation

/// A fresh, value-typed description of what should play. Passing this into the
/// player (rather than mutating shared state) guarantees the correct episode
/// loads instead of a stale one.
struct PlaybackContext: Identifiable {
    var id: String { "\(mediaItem.id)-\(season)-\(episode)-\(dialogueMode)" }
    let mediaItem: MediaItem
    let season: Int
    let episode: Int
    var dialogueMode: String = "Subbed"
}
