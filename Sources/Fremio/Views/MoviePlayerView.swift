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
    @State var season: Int
    @State var episode: Int
    var dialogueMode: String
    var offlineUrl: URL?
    var onClose: (() -> Void)?
    
    init(item: MediaItem, season: Int = 1, episode: Int = 1, dialogueMode: String = "Subbed", offlineUrl: URL? = nil, onClose: (() -> Void)? = nil) {
        self.item = item
        self._season = State(initialValue: season)
        self._episode = State(initialValue: episode)
        self.dialogueMode = dialogueMode
        self.offlineUrl = offlineUrl
        self.onClose = onClose
    }
    @Environment(\.dismiss) var dismiss
    
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var timeObserver: Any?
    
    @State private var availableStreams: [WCOTVStreamOption] = []
    @State private var selectedLanguage: String = "Subbed"
    @State private var selectedQuality: String = "1080p"
    @State private var selectedServer: ServerOption = {
        let saved = UserDefaults.standard.integer(forKey: "preferred_server")
        return ServerOption(rawValue: saved) ?? .flux
    }()
    
    @State private var introData: (start: Double, end: Double)? = nil
    @State private var showSkipIntro: Bool = false
    
    let playerItemEnded = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)

    // YouTube custom player states
    @State private var isPlaying: Bool = true
    @State private var currentTime: Double = 0
    @State private var totalDuration: Double = 0.1
    @State private var isDraggingSlider: Bool = false
    @State private var controlsVisible: Bool = true
    @State private var showLeftRipple: Bool = false
    @State private var showRightRipple: Bool = false
    @State private var controlTimeoutTask: Task<Void, Never>? = nil

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "00:00" }
        let secs = Int(seconds)
        let h = secs / 3600
        let m = (secs % 3600) / 60
        let s = secs % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    private func seekRelative(by seconds: Double) {
        guard let player = player else { return }
        let current = player.currentTime().seconds
        let target = max(0, min(current + seconds, totalDuration))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 1))
        self.currentTime = target
        resetControlTimeout()
    }

    private func triggerDoubleTapIndicator(isLeft: Bool) {
        HapticManager.shared.impact(style: .light)
        if isLeft {
            showLeftRipple = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showLeftRipple = false
            }
        } else {
            showRightRipple = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showRightRipple = false
            }
        }
    }

    private func resetControlTimeout() {
        controlTimeoutTask?.cancel()
        controlTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                controlsVisible = false
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            playerContent
            
            skipIntroButton
        }
        .preferredColorScheme(.dark)
        .onAppear {
            resolveAndPlay()
        }
        .onDisappear {
            cleanupObserver()
        }
        .onReceive(playerItemEnded) { notification in
            guard let currentItem = player?.currentItem,
                  let obj = notification.object as? AVPlayerItem,
                  obj == currentItem,
                  item.type == .show else { return }
            
            episode += 1
            resolveAndPlay()
        }
    }
    
    @ViewBuilder
    private var playerContent: some View {
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
            ZStack {
                NativeVideoPlayer(player: avPlayer)
                    .ignoresSafeArea()
                    .onTapGesture(count: 2) { location in
                        let width = UIScreen.main.bounds.width
                        if location.x < width / 2 {
                            seekRelative(by: -10)
                            triggerDoubleTapIndicator(isLeft: true)
                        } else {
                            seekRelative(by: 10)
                            triggerDoubleTapIndicator(isLeft: false)
                        }
                    }
                    .onTapGesture(count: 1) {
                        withAnimation {
                            controlsVisible.toggle()
                            if controlsVisible {
                                resetControlTimeout()
                            }
                        }
                    }
                
                doubleTapRipples
                
                if controlsVisible {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                controlsVisible = false
                            }
                        }
                    
                    centerControls
                    
                    bottomControls
                    
                    controlsOverlay
                }
            }
        }
    }
    
    @ViewBuilder
    private var doubleTapRipples: some View {
        HStack {
            // Left Ripple
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .scaleEffect(showLeftRipple ? 1.5 : 0.8)
                    .opacity(showLeftRipple ? 0 : 1)
                
                VStack(spacing: 4) {
                    Image(systemName: "backward.fill")
                    Text("10s")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
            }
            .opacity(showLeftRipple ? 1 : 0)
            .animation(.easeOut(duration: 0.5), value: showLeftRipple)
            .frame(maxWidth: .infinity)
            
            // Right Ripple
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .scaleEffect(showRightRipple ? 1.5 : 0.8)
                    .opacity(showRightRipple ? 0 : 1)
                
                VStack(spacing: 4) {
                    Image(systemName: "forward.fill")
                    Text("10s")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.white)
            }
            .opacity(showRightRipple ? 1 : 0)
            .animation(.easeOut(duration: 0.5), value: showRightRipple)
            .frame(maxWidth: .infinity)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var centerControls: some View {
        HStack(spacing: 50) {
            Button(action: {
                seekRelative(by: -10)
            }) {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
            
            Button(action: {
                if isPlaying {
                    player?.pause()
                } else {
                    player?.play()
                }
                isPlaying.toggle()
                resetControlTimeout()
            }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white)
            }
            
            Button(action: {
                seekRelative(by: 10)
            }) {
                Image(systemName: "goforward.10")
                    .font(.system(size: 32))
                    .foregroundColor(.white)
            }
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        VStack {
            Spacer()
            VStack(spacing: 8) {
                HStack {
                    Text(formatTime(currentTime))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text(formatTime(totalDuration))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 8)
                
                Slider(value: $currentTime, in: 0...totalDuration, onEditingChanged: { editing in
                    isDraggingSlider = editing
                    if editing {
                        controlTimeoutTask?.cancel()
                    } else {
                        player?.seek(to: CMTime(seconds: currentTime, preferredTimescale: 1))
                        resetControlTimeout()
                    }
                })
                .accentColor(.red)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }
    
    @ViewBuilder
    private var skipIntroButton: some View {
        if showSkipIntro {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        if let end = introData?.end {
                            player?.seek(to: CMTime(seconds: end, preferredTimescale: 1))
                            showSkipIntro = false
                        }
                    }) {
                        Text("Skip Intro")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(8)
                            .shadow(radius: 5)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 80)
                }
            }
        }
    }
    
    @ViewBuilder
    private var controlsOverlay: some View {
        VStack {
            HStack(alignment: .center) {
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
                
                HStack(spacing: 10) {
                    Menu {
                        ForEach(ServerOption.allCases) { server in
                            Button {
                                switchServer(to: server)
                            } label: {
                                HStack {
                                    Text("\(server.displayName) (\(server.serverName))")
                                    if selectedServer == server {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "server.rack")
                            Text("\(selectedServer.displayName) (\(selectedServer.serverName))")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    
                    if !availableStreams.isEmpty {
                        Menu {
                            ForEach(Array(Set(availableStreams.map { $0.language })).sorted(), id: \.self) { lang in
                                Button {
                                    HapticManager.shared.impact(style: .medium)
                                    self.selectedLanguage = lang
                                    if let best = availableStreams.filter({ $0.language == lang && $0.quality == selectedQuality }).first ?? availableStreams.filter({ $0.language == lang }).sorted(by: { $0.quality > $1.quality }).first {
                                        self.selectedQuality = best.quality
                                        loadStreamOption(best)
                                    }
                                } label: {
                                    HStack {
                                        Text(lang)
                                        if selectedLanguage == lang {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left.and.bubble.right.fill")
                                Text(selectedLanguage)
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        
                        Menu {
                            ForEach(Array(Set(availableStreams.filter { $0.language == selectedLanguage }.map { $0.quality })).sorted(), id: \.self) { qual in
                                Button {
                                    HapticManager.shared.impact(style: .medium)
                                    self.selectedQuality = qual
                                    if let option = availableStreams.first(where: { $0.language == selectedLanguage && $0.quality == qual }) {
                                        loadStreamOption(option)
                                    }
                                } label: {
                                    HStack {
                                        Text(qual)
                                        if selectedQuality == qual {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape.fill")
                                Text(selectedQuality)
                            }
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(12)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }

    private func cleanupObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    private func loadStreamOption(_ option: WCOTVStreamOption) {
        isLoading = true
        errorMessage = nil
        
        let savedPosition = getSavedPosition()
        cleanupObserver()
        player?.pause()
        
        Task {
            let (resolvedUrl, resolvedReferer) = await StreamResolver.shared.getFinalStreamUrl(from: option.url, referer: option.referer)
            let headers: [String: String] = [
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                "Referer": resolvedReferer
            ]
            let asset = AVURLAsset(url: resolvedUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            
            guard let _ = try? await asset.load(.tracks),
                  let _ = try? await asset.load(.duration) else {
                await MainActor.run {
                    self.errorMessage = "Failed to load streaming options for \(option.language) (\(option.quality))."
                    self.isLoading = false
                }
                return
            }
            
            await MainActor.run {
                let playerItem = AVPlayerItem(asset: asset)
                if let p = self.player {
                    p.replaceCurrentItem(with: playerItem)
                    if savedPosition > 10 {
                        p.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 1))
                    }
                    setupObserver(p)
                    p.play()
                } else {
                    let avPlayer = AVPlayer(playerItem: playerItem)
                    self.player = avPlayer
                    setupObserver(avPlayer)
                    avPlayer.play()
                }
                
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
                try? AVAudioSession.sharedInstance().setActive(true)
                self.isLoading = false
            }
        }
    }
    
    private func setupObserver(_ avPlayer: AVPlayer) {
        // Restore watch progress if not already seeking
        let savedPosition = getSavedPosition()
        if savedPosition > 10 && avPlayer.currentTime().seconds < 5 {
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
                if let intro = self.introData {
                    self.showSkipIntro = current >= intro.start && current < intro.end
                }
            }
        }
    }
    
    private func switchServer(to server: ServerOption) {
        HapticManager.shared.impact(style: .medium)
        selectedServer = server
        UserDefaults.standard.set(server.rawValue, forKey: "preferred_server")
        
        cleanupObserver()
        player?.pause()
        player = nil
        
        resolveAndPlay()
    }
    
    private func loadDirectStream(resolver: @escaping () async throws -> URL) {
        Task {
            do {
                let streamUrl = try await resolver()
                let headers: [String: String] = [
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                    "Referer": "https://vidvault.ru/"
                ]
                let asset = AVURLAsset(url: streamUrl, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
                
                await MainActor.run {
                    let playerItem = AVPlayerItem(asset: asset)
                    let avPlayer = AVPlayer(playerItem: playerItem)
                    self.player = avPlayer
                    setupObserver(avPlayer)
                    avPlayer.play()
                    
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
    
    private func loadWcoTvStream() {
        Task {
            do {
                let streams = try await WCOTVResolver.shared.resolveAnimeStreams(
                    title: item.title,
                    season: season,
                    episode: episode
                )
                
                guard !streams.isEmpty else {
                    await MainActor.run {
                        self.errorMessage = "No streams found on WCOTV for this item."
                        self.isLoading = false
                    }
                    return
                }
                
                await MainActor.run {
                    self.availableStreams = streams
                    self.selectedLanguage = dialogueMode
                    
                    let langStreams = streams.filter { $0.language == dialogueMode }
                    if let best = langStreams.sorted(by: { $0.quality > $1.quality }).first {
                        self.selectedQuality = best.quality
                        loadStreamOption(best)
                    } else if let fallback = streams.sorted(by: { $0.quality > $1.quality }).first {
                        self.selectedLanguage = fallback.language
                        self.selectedQuality = fallback.quality
                        loadStreamOption(fallback)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "WCOTV resolution failed: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func resolveAndPlay() {
        isLoading = true
        errorMessage = nil
        availableStreams = []
        
        if let offlineUrl = offlineUrl {
            let playerItem = AVPlayerItem(url: offlineUrl)
            let avPlayer = AVPlayer(playerItem: playerItem)
            self.player = avPlayer
            setupObserver(avPlayer)
            avPlayer.play()
            
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            self.isLoading = false
            return
        }
        
        switch selectedServer {
        case .flux:
            loadDirectStream {
                try await StreamResolver.shared.resolveFlux(
                    type: item.type,
                    tmdbId: item.id,
                    season: season,
                    episode: episode
                )
            }
        case .cineby:
            loadDirectStream {
                try await StreamResolver.shared.resolveCineby(
                    type: item.type,
                    tmdbId: item.id,
                    season: season,
                    episode: episode
                )
            }
        case .wcoTv:
            loadWcoTvStream()
        }
        
        if item.type == .show {
            fetchIntroData()
        }
    }
    
    private func fetchIntroData() {
        introData = nil
        showSkipIntro = false
        Task {
            do {
                let apiKey = "3d421899d5ce93db8ad4ae4591ccc130"
                var tmdbId = item.id
                if Int(item.id) == nil {
                    let searchUrl = URL(string: "https://api.themoviedb.org/3/search/tv?api_key=\(apiKey)&query=\(item.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
                    let (data, _) = try await URLSession.shared.data(from: searchUrl)
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let results = json["results"] as? [[String: Any]],
                       let first = results.first,
                       let id = first["id"] as? Int {
                        tmdbId = String(id)
                    }
                }
                
                guard Int(tmdbId) != nil else { return }
                
                let extUrl = URL(string: "https://api.themoviedb.org/3/tv/\(tmdbId)/external_ids?api_key=\(apiKey)")!
                let (extData, _) = try await URLSession.shared.data(from: extUrl)
                if let json = try JSONSerialization.jsonObject(with: extData) as? [String: Any],
                   let imdbId = json["imdb_id"] as? String {
                    
                    let introUrl = URL(string: "https://api.introdb.app/segments?imdb_id=\(imdbId)&season=\(season)&episode=\(episode)")!
                    let (introRaw, _) = try await URLSession.shared.data(from: introUrl)
                    if let introArray = try JSONSerialization.jsonObject(with: introRaw) as? [[String: Any]] {
                        if let intro = introArray.first(where: { ($0["type"] as? String) == "intro" }),
                           let start = intro["start"] as? Double,
                           let end = intro["end"] as? Double {
                            await MainActor.run {
                                self.introData = (start: start / 1000.0, end: end / 1000.0)
                            }
                        }
                    }
                }
            } catch {
                print("IntroDB fetch error: \(error)")
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
        controller.showsPlaybackControls = false
        return controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}
