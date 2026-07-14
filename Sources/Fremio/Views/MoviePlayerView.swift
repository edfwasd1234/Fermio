import SwiftUI
import AVKit
import AVFoundation

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

struct MoviePlayerView: View {
    let item: MediaItem
    var season: Int = 1
    var episode: Int = 1
    var dialogueMode: String = "Subbed"
    var offlineUrl: URL? = nil
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss
    
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var timeObserver: Any?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if isLoading {
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text(offlineUrl != nil ? "Loading offline video..." : "Resolving secure MP4 stream...")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(item.type == .movie ? item.title : "\(item.title) - Season \(season) Episode \(episode)")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                .padding(30)
                .liquidGlass(cornerRadius: 20, fillOpacity: 0.1)
                .padding(24)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.orange)
                    
                    Text("Playback Error")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(error)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Button {
                        resolveAndPlay()
                    } label: {
                        Text("Retry Connection")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                }
                .padding(30)
                .liquidGlass(cornerRadius: 24)
            } else if let avPlayer = player {
                NativeVideoPlayer(player: avPlayer)
                    .ignoresSafeArea()
            }
            
            // Close Button
            VStack {
                HStack {
                    Button {
                        HapticManager.shared.impact(style: .medium)
                        cleanupObserver()
                        player?.pause()
                        player = nil
                        if let onClose = onClose {
                            onClose()
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(12)
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            resolveAndPlay()
        }
        .onDisappear {
            cleanupObserver()
        }
    }
    
    private func cleanupObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    private func resolveAndPlay() {
        isLoading = true
        errorMessage = nil
        
        if let offlineUrl = offlineUrl {
            let playerItem = AVPlayerItem(url: offlineUrl)
            let avPlayer = AVPlayer(playerItem: playerItem)
            self.player = avPlayer
            
            let savedPosition = getSavedPosition()
            if savedPosition > 10 {
                avPlayer.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 1))
            }
            
            let interval = CMTime(seconds: 5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            self.timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak avPlayer] time in
                guard let p = avPlayer, let currentItem = p.currentItem else { return }
                let current = CMTimeGetSeconds(time)
                let durationTime = currentItem.duration
                guard durationTime.isValid else { return }
                let total = CMTimeGetSeconds(durationTime)
                guard total > 0 else { return }
                
                Task { @MainActor in
                    self.saveProgress(current: current, total: total)
                }
            }
            
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            self.isLoading = false
            return
        }
        
        let isAnime = item.genre.lowercased().contains("anime") || item.genre.lowercased().contains("animation")
        
        Task {
            do {
                let playerItem: AVPlayerItem
                if isAnime {
                    do {
                        playerItem = try await StreamResolver.shared.resolveAnimeComposition(
                            title: item.title,
                            season: season,
                            episode: episode
                        )
                    } catch {
                        print("WCOTV resolution failed: \(error). Falling back to default resolver.")
                        let streamUrl = try await StreamResolver.shared.resolveStream(
                            type: item.type,
                            tmdbId: item.id,
                            season: season,
                            episode: episode
                        )
                        let headers: [String: String] = [
                            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                            "Referer": "https://vidvault.ru/"
                        ]
                        let asset = AVURLAsset(url: streamUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                        playerItem = await MainActor.run {
                            AVPlayerItem(asset: asset)
                        }
                    }
                } else {
                    let streamUrl = try await StreamResolver.shared.resolveStream(
                        type: item.type,
                        tmdbId: item.id,
                        season: season,
                        episode: episode
                    )
                    let headers: [String: String] = [
                        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                        "Referer": "https://vidvault.ru/"
                    ]
                    let asset = AVURLAsset(url: streamUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                    playerItem = await MainActor.run {
                        AVPlayerItem(asset: asset)
                    }
                }
                
                await MainActor.run {
                    if isAnime, let group = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
                        let languageCode = (dialogueMode == "Dubbed") ? "en-US" : "ja-JP"
                        let options = AVMediaSelectionGroup.mediaSelectionOptions(withLocale: Locale(identifier: languageCode), from: group)
                        if let option = options.first {
                            playerItem.select(option, in: group)
                        }
                    }
                    
                    let avPlayer = AVPlayer(playerItem: playerItem)
                    self.player = avPlayer
                    
                    // Restore watch progress
                    let savedPosition = getSavedPosition()
                    if savedPosition > 10 {
                        avPlayer.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 1))
                    }
                    
                    // Manage periodic watcher progress saves (every 5 seconds)
                    let interval = CMTime(seconds: 5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                    self.timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak avPlayer] time in
                        guard let p = avPlayer, let currentItem = p.currentItem else { return }
                        let current = CMTimeGetSeconds(time)
                        let durationTime = currentItem.duration
                        guard durationTime.isValid else { return }
                        let total = CMTimeGetSeconds(durationTime)
                        guard total > 0 else { return }
                        
                        Task { @MainActor in
                            self.saveProgress(current: current, total: total)
                        }
                    }
                    
                    // Request audio session management
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                    try? AVAudioSession.sharedInstance().setActive(true)
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
    
    // Watch Progress Storage Helpers
    private func getSavedPosition() -> Double {
        guard let data = UserDefaults.standard.data(forKey: "continue_watching_items"),
              let list = try? JSONDecoder().decode([WatchProgress].self, from: data) else {
            return 0
        }
        if item.type == .movie {
            return list.first(where: { $0.mediaId == item.id })?.currentPosition ?? 0
        } else {
            return list.first(where: { $0.mediaId == item.id && $0.season == season && $0.episode == episode })?.currentPosition ?? 0
        }
    }

    private func saveProgress(current: Double, total: Double) {
        guard current > 10 else { return }
        
        var list: [WatchProgress] = []
        if let data = UserDefaults.standard.data(forKey: "continue_watching_items"),
           let decoded = try? JSONDecoder().decode([WatchProgress].self, from: data) {
            list = decoded
        }
        
        list.removeAll(where: { p in
            if item.type == .movie {
                return p.mediaId == item.id
            } else {
                return p.mediaId == item.id && p.season == season && p.episode == episode
            }
        })
        
        // Save if user hasn't finished the video (95% rule)
        if current < (total * 0.95) {
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
            list.insert(progress, at: 0)
        }
        
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "continue_watching_items")
            NotificationCenter.default.post(name: NSNotification.Name("ContinueWatchingUpdated"), object: nil)
        }
    }
}

/// Native AVPlayerViewController representable supporting Picture-in-Picture, Fullscreen, and Aspect Ratio preservation.
struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect // Keeps correct aspect ratio to fix stretching
        controller.allowsPictureInPicturePlayback = true
        controller.showsPlaybackControls = true
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
