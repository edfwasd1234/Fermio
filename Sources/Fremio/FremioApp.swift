import SwiftUI

@main
struct FremioApp: App {
    init() {
        // Give AsyncImage (which uses URLSession.shared) a real disk cache so
        // TMDB posters/backdrops aren't re-downloaded on every launch.
        URLCache.shared = URLCache(
            memoryCapacity: 50 * 1024 * 1024,      // 50 MB
            diskCapacity: 300 * 1024 * 1024,       // 300 MB
            directory: nil
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
