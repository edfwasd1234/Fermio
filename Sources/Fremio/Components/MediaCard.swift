import SwiftUI

/// A premium glassmorphic card component representing a Movie or Show.
struct MediaCard: View {
    let item: MediaItem
    var cardWidth: CGFloat = 145
    var cardHeight: CGFloat = 210
    
    @State private var isPressed = false
    @State private var showDetail = false
    
    var body: some View {
        Button {
            HapticManager.shared.impact(style: .light)
            showDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Movie Poster with AsyncImage & Liquid Gradients as fallback
                ZStack {
                    if let posterPath = item.posterPath, !posterPath.isEmpty {
                        AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w300\(posterPath)")) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: cardWidth, height: cardHeight)
                                    .clipped()
                            case .failure, .empty:
                                placeholderView
                            @unknown default:
                                placeholderView
                            }
                        }
                    } else {
                        placeholderView
                    }
                    
                    // Overlay for Movie or TV Show Badge
                    VStack {
                        HStack {
                            Spacer()
                            Text(item.type.rawValue)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.6))
                                .clipShape(Capsule())
                                .foregroundColor(.white)
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: Color(hex: item.posterColorHex).opacity(0.2), radius: 8, x: 0, y: 6)
                
                // Content Description
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundColor(.white)
                    
                    HStack {
                        Text(item.genre)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", item.rating))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(width: cardWidth)
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(PressActionsButtonStyle(isPressed: $isPressed))
        .sheet(isPresented: $showDetail) {
            AnyView(MediaDetailView(item: item))
        }
    }
    
    private var placeholderView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: item.posterColorHex),
                    Color(hex: item.posterColorHex).opacity(0.3),
                    Color.black.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Glass Ambient Glow
            RadialGradient(
                colors: [Color.white.opacity(0.2), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 100
            )
            
            Image(systemName: item.posterSymbol)
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

/// A SwiftUI ButtonStyle helper to capture press triggers for custom scale effects and haptic responses.
struct PressActionsButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { newValue in
                isPressed = newValue
            }
    }
}

/// Custom SwiftUI representation of a full details page, designed with liquid glass themes.
struct MediaDetailView: View {
    let item: MediaItem
    @Environment(\.dismiss) var dismiss
    
    @State private var detailedItem: MediaItem?
    @State private var selectedSeason: Int = 1
    @State private var episodes: [TMDBEpisode] = []
    @State private var isEpisodesLoading = false
    @State private var similarItems: [MediaItem] = []
    
    @State private var showPlayer = false
    @State private var selectedEpisode: Int = 1
    @State private var animateGlow = false
    
    private var isWatchlist: Bool {
        watchlistContains(id: item.id, type: item.type)
    }
    
    var body: some View {
        ZStack {
            // Liquid Mesh Background
            LiquidBackgroundView()
                .ignoresSafeArea()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 25) {
                    // Header Area with Back Button
                    HStack {
                        Button {
                            HapticManager.shared.impact(style: .medium)
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    // Large Poster Illustration
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.white.opacity(0.04))
                            .frame(width: 200, height: 280)
                            .liquidGlass(cornerRadius: 24, borderWidth: 1.0, glowColor: Color(hex: item.posterColorHex))
                        
                        ZStack {
                            if let posterPath = item.posterPath, !posterPath.isEmpty {
                                AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w500\(posterPath)")) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    default:
                                        placeholderBackground
                                    }
                                }
                            } else {
                                placeholderBackground
                            }
                        }
                        .frame(width: 190, height: 270)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .padding(.top, 10)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                            animateGlow.toggle()
                        }
                    }
                    
                    // Metadata Info Card (Liquid Glass)
                    VStack(spacing: 15) {
                        Text(detailedItem?.title ?? item.title)
                            .font(.system(size: 26, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                        
                        HStack(spacing: 15) {
                            Text(detailedItem?.genre ?? item.genre)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Circle()
                                .frame(width: 4, height: 4)
                                .foregroundColor(.gray)
                            
                            Text("\(detailedItem?.releaseYear ?? item.releaseYear)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                            
                            Circle()
                                .frame(width: 4, height: 4)
                                .foregroundColor(.gray)
                            
                            Text(detailedItem?.duration ?? item.duration)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        // Rating Badge
                        HStack(spacing: 5) {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text(String(format: "%.1f", detailedItem?.rating ?? item.rating))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text("/ 5.0")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 24)
                    
                    // Actions Bar
                    if item.type == .movie {
                        HStack(spacing: 15) {
                            Button {
                                HapticManager.shared.notification(type: .success)
                                selectedEpisode = 1
                                showPlayer = true
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Play Movie")
                                }
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            
                            Button {
                                HapticManager.shared.impact(style: .medium)
                                toggleWatchlist(item: item)
                            } label: {
                                Image(systemName: isWatchlist ? "checkmark" : "plus")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .liquidGlass(cornerRadius: 14, fillOpacity: 0.1)
                            }
                            
                            Button {
                                HapticManager.shared.impact(style: .medium)
                                toggleFavorite(item: item)
                            } label: {
                                Image(systemName: isFavorite ? "heart.fill" : "heart")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(isFavorite ? .pink : .white)
                                    .frame(width: 50, height: 50)
                                    .liquidGlass(cornerRadius: 14, fillOpacity: 0.1)
                            }
                        }
                        .padding(.horizontal, 24)
                    } else if item.type == .show {
                        HStack(spacing: 15) {
                            Button {
                                HapticManager.shared.impact(style: .medium)
                                toggleWatchlist(item: item)
                            } label: {
                                HStack {
                                    Image(systemName: isWatchlist ? "checkmark" : "plus")
                                    Text(isWatchlist ? "In Watchlist" : "Watchlist")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .liquidGlass(cornerRadius: 14, fillOpacity: 0.1)
                            }
                            
                            Button {
                                HapticManager.shared.impact(style: .medium)
                                toggleFavorite(item: item)
                            } label: {
                                HStack {
                                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                                    Text(isFavorite ? "Favorited" : "Favorite")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isFavorite ? .pink : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .liquidGlass(cornerRadius: 14, fillOpacity: 0.1)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Description Box
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Overview")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(detailedItem?.description ?? item.description)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .lineSpacing(4)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(cornerRadius: 20)
                    .padding(.horizontal, 24)
                    
                    // Similar Recommendations Carousel
                    if !similarItems.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("You May Also Like")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    ForEach(similarItems) { simItem in
                                        AnyView(MediaCard(item: simItem, cardWidth: 110, cardHeight: 160))
                                    }
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                        .padding(.top, 10)
                    }
                    
                    // TV Show Seasons & Episodes Section
                    if item.type == .show {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                Text("Episodes")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                // Season Picker
                                if let totalSeasons = getSeasonCount() {
                                    Picker("Season", selection: $selectedSeason) {
                                        ForEach(1...totalSeasons, id: \.self) { s in
                                            Text("Season \(s)").tag(s)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .foregroundColor(.cyan)
                                    .onChange(of: selectedSeason) { newValue in
                                        loadEpisodes(season: newValue)
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            
                            if isEpisodesLoading {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    Spacer()
                                }
                                .padding(.vertical, 20)
                            } else {
                                ForEach(episodes) { episode in
                                    Button {
                                        HapticManager.shared.notification(type: .success)
                                        selectedEpisode = episode.episode_number
                                        showPlayer = true
                                    } label: {
                                        HStack(spacing: 12) {
                                            // Episode thumbnail placeholder/icon
                                            ZStack {
                                                Color.white.opacity(0.05)
                                                    .frame(width: 80, height: 50)
                                                    .cornerRadius(6)
                                                
                                                if let stillPath = episode.still_path, !stillPath.isEmpty {
                                                    AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w400\(stillPath)")) { phase in
                                                        if case .success(let image) = phase {
                                                            image
                                                                .resizable()
                                                                .aspectRatio(contentMode: .fill)
                                                        }
                                                    }
                                                    .frame(width: 80, height: 50)
                                                    .cornerRadius(6)
                                                    .clipped()
                                                } else {
                                                    Image(systemName: "play.circle.fill")
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Episode \(episode.episode_number): \(episode.name ?? "Untitled")")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                
                                                if let overview = episode.overview, !overview.isEmpty {
                                                    Text(overview)
                                                        .font(.system(size: 11))
                                                        .foregroundColor(.gray)
                                                        .lineLimit(2)
                                                        .multilineTextAlignment(.leading)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.white.opacity(0.8))
                                                .padding(8)
                                                .background(Color.white.opacity(0.1))
                                                .clipShape(Circle())
                                        }
                                        .padding(10)
                                        .liquidGlass(cornerRadius: 12, fillOpacity: 0.05)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                    
                    Spacer()
                        .frame(height: 50)
                }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            MoviePlayerView(
                item: detailedItem ?? item,
                season: selectedSeason,
                episode: selectedEpisode
            )
        }
        .onAppear {
            loadDetails()
        }
    }
    
    private var placeholderBackground: some View {
        LinearGradient(
            colors: [Color(hex: item.posterColorHex), Color(hex: item.posterColorHex).opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: item.posterSymbol)
                .font(.system(size: 72, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: Color(hex: item.posterColorHex).opacity(0.8), radius: animateGlow ? 30 : 15, x: 0, y: 5)
        )
    }
    
    private func getSeasonCount() -> Int? {
        guard let duration = detailedItem?.duration else { return nil }
        let numbers = duration.filter(\.isNumber)
        return Int(numbers)
    }
    
    private func loadDetails() {
        Task {
            do {
                let details = try await TMDBService.shared.fetchDetails(type: item.type, id: item.id)
                let similar = try await TMDBService.shared.fetchSimilar(type: item.type, id: item.id)
                await MainActor.run {
                    self.detailedItem = details
                    self.similarItems = similar
                    if item.type == .show {
                        loadEpisodes(season: selectedSeason)
                    }
                }
            } catch {
                print("Error loading details: \(error)")
            }
        }
    }
    
    private func loadEpisodes(season: Int) {
        isEpisodesLoading = true
        Task {
            do {
                let list = try await TMDBService.shared.fetchEpisodes(tvId: item.id, seasonNumber: season)
                await MainActor.run {
                    self.episodes = list
                    self.isEpisodesLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isEpisodesLoading = false
                }
            }
        }
    }
    
    // Watchlist persistence helper
    private var isFavorite: Bool {
        let favorites = fetchFavorites()
        return favorites.contains(where: { $0.id == item.id && $0.type == item.type })
    }
    
    private func watchlistContains(id: String, type: MediaType) -> Bool {
        let watchlist = fetchWatchlist()
        return watchlist.contains(where: { $0.id == id && $0.type == type })
    }
    
    private func toggleWatchlist(item: MediaItem) {
        var watchlist = fetchWatchlist()
        if let idx = watchlist.firstIndex(where: { $0.id == item.id && $0.type == item.type }) {
            watchlist.remove(at: idx)
            HapticManager.shared.impact(style: .soft)
        } else {
            watchlist.insert(item, at: 0)
            HapticManager.shared.notification(type: .success)
        }
        saveWatchlist(watchlist)
    }
    
    private func fetchWatchlist() -> [MediaItem] {
        guard let data = UserDefaults.standard.data(forKey: "watchlist_items"),
              let list = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            return []
        }
        return list
    }
    
    private func saveWatchlist(_ list: [MediaItem]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "watchlist_items")
            NotificationCenter.default.post(name: NSNotification.Name("WatchlistUpdated"), object: nil)
        }
    }
    
    // Favorites persistence helper
    private func toggleFavorite(item: MediaItem) {
        var favorites = fetchFavorites()
        if let idx = favorites.firstIndex(where: { $0.id == item.id && $0.type == item.type }) {
            favorites.remove(at: idx)
            HapticManager.shared.impact(style: .soft)
        } else {
            favorites.insert(item, at: 0)
            HapticManager.shared.notification(type: .success)
        }
        saveFavorites(favorites)
    }
    
    private func fetchFavorites() -> [MediaItem] {
        guard let data = UserDefaults.standard.data(forKey: "favorite_items"),
              let list = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            return []
        }
        return list
    }
    
    private func saveFavorites(_ list: [MediaItem]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: "favorite_items")
            NotificationCenter.default.post(name: NSNotification.Name("FavoritesUpdated"), object: nil)
        }
    }
}
