import SwiftUI

/// The Home Screen containing trending content, movie carousels, and the primary app hero.
struct HomeView: View {
    @State private var trendingItems: [MediaItem] = []
    @State private var popularMovies: [MediaItem] = []
    @State private var popularShows: [MediaItem] = []
    @State private var continueWatchingItems: [WatchProgress] = []
    @State private var isLoading = true
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 28) {
                // Customized Header Navigation Bar (Liquid Glass Profile + Title)
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Fremio")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                        Text("Discover movies & shows")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    
                    // Glassmorphic User Profile Avatar
                    Button {
                        HapticManager.shared.impact(style: .soft)
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 34))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(6)
                            .liquidGlass(cornerRadius: 25, fillOpacity: 0.1)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                
                if isLoading {
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                            .padding(.top, 40)
                        
                        Text("Loading discover feed...")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .padding(.top, 12)
                    }
                } else {
                    // Featured Hero Banner
                    if let featured = trendingItems.first {
                        HeroBanner(item: featured)
                    }
                    
                    // Continue Watching Carousel Section
                    if !continueWatchingItems.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Continue Watching")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(continueWatchingItems) { progress in
                                        ContinueWatchingCard(progress: progress, onUpdate: loadContinueWatching)
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                    
                    // Trending Carousel Section
                    if !trendingItems.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Trending Now")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(trendingItems) { item in
                                        MediaCard(item: item)
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                    
                    // Popular Movies Carousel Section
                    if !popularMovies.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Popular Movies")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(popularMovies) { item in
                                        MediaCard(item: item)
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                    
                    // Popular TV Shows Carousel Section
                    if !popularShows.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Popular TV Shows")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(popularShows) { item in
                                        MediaCard(item: item)
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                }
                
                // Padding at the bottom to clear the floating Tab Bar
                Spacer()
                    .frame(height: 100)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            loadHomeData()
            loadContinueWatching()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ContinueWatchingUpdated"))) { _ in
            loadContinueWatching()
        }
    }
    
    private func loadHomeData() {
        guard trendingItems.isEmpty else { return } // Avoid double load
        isLoading = true
        
        Task {
            do {
                let trending = try await TMDBService.shared.fetchTrending(type: .movie)
                let popMovies = try await TMDBService.shared.fetchPopular(type: .movie)
                let popShows = try await TMDBService.shared.fetchPopular(type: .show)
                
                await MainActor.run {
                    self.trendingItems = trending
                    self.popularMovies = popMovies
                    self.popularShows = popShows
                    self.isLoading = false
                }
            } catch {
                print("Error loading home data: \(error)")
                await MainActor.run {
                    self.isLoading = false
                    // Fallback to mock data in case of failure so app doesn't go blank
                    self.trendingItems = MediaItem.mockData.filter { $0.isTrending }
                    self.popularMovies = MediaItem.mockData.filter { $0.type == .movie }
                    self.popularShows = MediaItem.mockData.filter { $0.type == .show }
                }
            }
        }
    }
    
    private func loadContinueWatching() {
        if let data = UserDefaults.standard.data(forKey: "continue_watching_items"),
           let decoded = try? JSONDecoder().decode([WatchProgress].self, from: data) {
            self.continueWatchingItems = decoded
        } else {
            self.continueWatchingItems = []
        }
    }
}

/// A card component for items that the user is currently watching.
struct ContinueWatchingCard: View {
    let progress: WatchProgress
    var onUpdate: () -> Void
    
    @State private var isPressed = false
    @State private var playbackContext: PlaybackContext? = nil
    
    var body: some View {
        Button {
            HapticManager.shared.notification(type: .success)
            let mediaItem = MediaItem(
                id: progress.mediaId,
                title: progress.title,
                type: progress.type,
                posterPath: progress.posterPath,
                backdropPath: progress.backdropPath,
                posterSymbol: progress.posterSymbol,
                posterColorHex: progress.posterColorHex,
                genre: progress.genre,
                rating: progress.rating,
                releaseYear: progress.releaseYear,
                duration: progress.duration,
                description: progress.description,
                isTrending: false,
                isNewRelease: false
            )
            playbackContext = PlaybackContext(
                mediaItem: mediaItem,
                season: progress.season,
                episode: progress.episode
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottom) {
                    // Backdrop Image
                    ZStack {
                        if let backdropPath = progress.backdropPath, !backdropPath.isEmpty {
                            AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w300\(backdropPath)")) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 200, height: 110)
                                default:
                                    placeholderGradient
                                }
                            }
                        } else {
                            placeholderGradient
                        }
                    }
                    .frame(width: 200, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    
                    // Dark shade overlay
                    Color.black.opacity(0.2)
                    
                    // Play icon overlay
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(radius: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Progress Bar at the bottom
                    VStack(spacing: 0) {
                        Spacer()
                        GeometryReader { geo in
                            let percent: CGFloat = {
                                let ratio = progress.totalDuration > 0 ? (progress.currentPosition / progress.totalDuration) : 0
                                return CGFloat(max(0.0, min(1.0, ratio)))
                            }()
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 4)
                                
                                Rectangle()
                                    .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * percent, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
                .frame(width: 200, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 4)
                
                // Title and Episode Details
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if progress.type == .show {
                        Text("Season \(progress.season) Episode \(progress.episode)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gray)
                    } else {
                        Text(progress.genre)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(width: 200)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PressActionsButtonStyle(isPressed: $isPressed))
        .fullScreenCover(item: $playbackContext, onDismiss: onUpdate) { context in
            MoviePlayerView(item: context.mediaItem, season: context.season, episode: context.episode)
        }
    }
    
    private var placeholderGradient: some View {
        LinearGradient(
            colors: [Color(hex: progress.posterColorHex), Color(hex: progress.posterColorHex).opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: 200, height: 110)
    }
}

/// A premium visual banner component acting as the hero element for HomeView.
struct HeroBanner: View {
    let item: MediaItem
    @State private var pressScale: CGFloat = 1.0
    @State private var playbackContext: PlaybackContext? = nil
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Backdrop Image with fallback gradient
            ZStack {
                if let backdropPath = item.backdropPath, !backdropPath.isEmpty {
                    AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/original\(backdropPath)")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 360)
                                .clipped()
                        default:
                            placeholderGradient
                        }
                    }
                } else {
                    placeholderGradient
                }
            }
            .frame(height: 360)
            
            // Shading and overlay for readability
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.4),
                    .black.opacity(0.85),
                    .black.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Liquid Glass text plate
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("RECOMMENDED FOR YOU")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                    Spacer()
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text(String(format: "%.1f", item.rating))
                            .font(.system(size: 11, weight: .black))
                            .foregroundColor(.white)
                    }
                }
                
                Text(item.title)
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(item.description)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .lineSpacing(3)
                
                HStack(spacing: 12) {
                    Button {
                        HapticManager.shared.notification(type: .success)
                        playbackContext = PlaybackContext(mediaItem: item, season: 1, episode: 1)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Play Now")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(Capsule())
                    }
                    
                    Button {
                        HapticManager.shared.impact(style: .medium)
                        toggleWatchlist(item: item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isWatchlist ? "checkmark" : "plus")
                            Text("My List")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .liquidGlass(cornerRadius: 22, fillOpacity: 0.12)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 24, borderWidth: 0.7, fillOpacity: 0.05, shadowRadius: 15, glowColor: Color(hex: item.posterColorHex))
            .padding(14)
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 20)
        .shadow(color: Color(hex: item.posterColorHex).opacity(0.2), radius: 12, x: 0, y: 8)
        .fullScreenCover(item: $playbackContext) { context in
            MoviePlayerView(item: context.mediaItem, season: context.season, episode: context.episode)
        }
    }
    
    private var placeholderGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: item.posterColorHex),
                Color(hex: item.posterColorHex).opacity(0.4),
                .black.opacity(0.9)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 360)
    }
    
    private var isWatchlist: Bool {
        guard let data = UserDefaults.standard.data(forKey: "watchlist_items"),
              let list = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            return false
        }
        return list.contains(where: { $0.id == item.id && $0.type == item.type })
    }
    
    private func toggleWatchlist(item: MediaItem) {
        var list: [MediaItem] = []
        if let data = UserDefaults.standard.data(forKey: "watchlist_items"),
           let decoded = try? JSONDecoder().decode([MediaItem].self, from: data) {
            list = decoded
        }
        
        if let idx = list.firstIndex(where: { $0.id == item.id && $0.type == item.type }) {
            list.remove(at: idx)
            HapticManager.shared.impact(style: .soft)
        } else {
            list.insert(item, at: 0)
            HapticManager.shared.notification(type: .success)
        }
        
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "watchlist_items")
            NotificationCenter.default.post(name: NSNotification.Name("WatchlistUpdated"), object: nil)
        }
    }
}
