import SwiftUI

/// The sub-tabs within the library section.
enum LibraryTab: String, CaseIterable {
    case watchlist = "Watchlist"
    case favorites = "Favorites"
    case downloads = "Downloads"
}

/// The Library Screen hosting the user's customized Watchlist, Favorites, and Downloads.
struct LibraryView: View {
    @State private var activeLibraryTab: LibraryTab = .watchlist
    @Namespace private var segmentAnimation
    
    @State private var watchlistItems: [MediaItem] = []
    @State private var favoriteItems: [MediaItem] = []
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Screen Title Header
            HStack {
                Text("Library")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // Premium Sliding Segment Control (Glass Capsule)
            HStack(spacing: 4) {
                ForEach(LibraryTab.allCases, id: \.self) { tab in
                    Button {
                        HapticManager.shared.impact(style: .soft)
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                            activeLibraryTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(activeLibraryTab == tab ? .white : .white.opacity(0.5))
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                ZStack {
                                    if activeLibraryTab == tab {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(.white.opacity(0.12))
                                            .background(.ultraThinMaterial)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                            )
                                            .matchedGeometryEffect(id: "activeTabBackground", in: segmentAnimation)
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)
            
            // Tab Contents List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    switch activeLibraryTab {
                    case .watchlist:
                        if watchlistItems.isEmpty {
                            emptyStateView(message: "Watchlist is empty.\nAdd titles from their details page.")
                        } else {
                            ForEach(watchlistItems) { item in
                                LibraryRowView(item: item, rowType: .watchlist, onUpdate: loadLibraryData)
                             }
                        }
                    case .favorites:
                        if favoriteItems.isEmpty {
                            emptyStateView(message: "No favorites saved.\nTap the heart icon on any title.")
                        } else {
                            ForEach(favoriteItems) { item in
                                LibraryRowView(item: item, rowType: .favorite, onUpdate: loadLibraryData)
                            }
                        }
                    case .downloads:
                        if downloadManager.tasks.isEmpty {
                            emptyStateView(message: "No downloads found.\nTap the download icon on a title.")
                        } else {
                            ForEach(downloadManager.tasks) { task in
                                DownloadRowView(task: task)
                            }
                        }
                    }
                    
                    Spacer()
                        .frame(height: 100)
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            loadLibraryData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("WatchlistUpdated"))) { _ in
            loadLibraryData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FavoritesUpdated"))) { _ in
            loadLibraryData()
        }
    }
    
    private func emptyStateView(message: String) -> some View {
        let systemName: String
        switch activeLibraryTab {
        case .watchlist: systemName = "bookmark.fill"
        case .favorites: systemName = "heart.fill"
        case .downloads: systemName = "arrow.down.circle.fill"
        }
        
        return VStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.15))
                .padding(.top, 40)
            
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private func loadLibraryData() {
        if let data = UserDefaults.standard.data(forKey: "watchlist_items"),
           let decoded = try? JSONDecoder().decode([MediaItem].self, from: data) {
            self.watchlistItems = decoded
        } else {
            self.watchlistItems = []
        }
        
        if let data = UserDefaults.standard.data(forKey: "favorite_items"),
           let decoded = try? JSONDecoder().decode([MediaItem].self, from: data) {
            self.favoriteItems = decoded
        } else {
            self.favoriteItems = []
        }
    }
}

enum LibraryRowType {
    case watchlist, favorite
}

/// A row component inside the Library list displaying poster icon, metadata, and type-specific actions.
struct LibraryRowView: View {
    let item: MediaItem
    let rowType: LibraryRowType
    var onUpdate: () -> Void
    
    @State private var isPressed = false
    @State private var showDetail = false
    @State private var showPlayer = false
    
    var body: some View {
        Button {
            HapticManager.shared.impact(style: .light)
            showDetail = true
        } label: {
            HStack(spacing: 16) {
                // Mini Poster Graphic
                ZStack {
                    if let posterPath = item.posterPath, !posterPath.isEmpty {
                        AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w300\(posterPath)")) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(width: 54, height: 74)
                        .cornerRadius(12)
                        .clipped()
                    } else {
                        placeholderIcon
                    }
                }
                .frame(width: 54, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                
                // Description metadata
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(item.genre)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    
                    Text(item.duration)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                // Action Buttons based on type
                HStack(spacing: 12) {
                    switch rowType {
                    case .watchlist:
                        Button {
                            HapticManager.shared.notification(type: .success)
                            showPlayer = true
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.black)
                                .padding(10)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            HapticManager.shared.impact(style: .medium)
                            removeFromWatchlist()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        
                    case .favorite:
                        Button {
                            HapticManager.shared.impact(style: .medium)
                            removeFromFavorites()
                        } label: {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.pink)
                                .padding(10)
                                .background(Color.pink.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(12)
            .liquidGlass(cornerRadius: 18, fillOpacity: 0.05)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(PressActionsButtonStyle(isPressed: $isPressed))
        .sheet(isPresented: $showDetail) {
            MediaDetailView(item: item)
        }
        .fullScreenCover(isPresented: $showPlayer) {
            MoviePlayerView(item: item, season: 1, episode: 1)
        }
    }
    
    private var placeholderIcon: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: item.posterColorHex), Color(hex: item.posterColorHex).opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: item.posterSymbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 54, height: 74)
        .cornerRadius(12)
    }
    
    private func removeFromWatchlist() {
        var list = fetchList(key: "watchlist_items")
        list.removeAll(where: { $0.id == item.id && $0.type == item.type })
        saveList(list, key: "watchlist_items")
        NotificationCenter.default.post(name: NSNotification.Name("WatchlistUpdated"), object: nil)
        onUpdate()
    }
    
    private func removeFromFavorites() {
        var list = fetchList(key: "favorite_items")
        list.removeAll(where: { $0.id == item.id && $0.type == item.type })
        saveList(list, key: "favorite_items")
        NotificationCenter.default.post(name: NSNotification.Name("FavoritesUpdated"), object: nil)
        onUpdate()
    }
    
    private func fetchList(key: String) -> [MediaItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([MediaItem].self, from: data) else {
            return []
        }
        return list
    }
    
    private func saveList(_ list: [MediaItem], key: String) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// A row component inside the Library list displaying download status, speed, progress bar and play button.
struct DownloadRowView: View {
    let task: DownloadTask
    
    @State private var isPressed = false
    @State private var showPlayer = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                // Mini Poster Graphic
                ZStack {
                    if let posterPath = task.posterPath, !posterPath.isEmpty {
                        AsyncImage(url: URL(string: "https://image.tmdb.org/t/p/w300\(posterPath)")) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            }
                        }
                        .frame(width: 54, height: 74)
                        .cornerRadius(12)
                        .clipped()
                    } else {
                        placeholderIcon
                    }
                }
                .frame(width: 54, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                
                // Metadata Description
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(task.genre)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    
                    if task.status == .downloading {
                        Text(task.timeRemainingString)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.yellow)
                    } else if task.status == .completed {
                        Text("Offline watch ready")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.cyan)
                    } else if task.status == .failed {
                        Text("Failed")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.red)
                    } else {
                        Text("Pending")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                // Action Buttons based on status
                HStack(spacing: 12) {
                    if task.status == .completed {
                        Button {
                            HapticManager.shared.notification(type: .success)
                            showPlayer = true
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.black)
                                .padding(10)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button {
                        HapticManager.shared.impact(style: .medium)
                        if task.status == .downloading {
                            DownloadManager.shared.cancelDownload(taskId: task.id)
                        } else {
                            DownloadManager.shared.deleteDownload(taskId: task.id)
                        }
                    } label: {
                        Image(systemName: task.status == .downloading ? "xmark" : "trash")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Progress Bar for downloading/pending tasks
            if task.status == .downloading || task.status == .pending {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        
                        Rectangle()
                            .fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(task.progress), height: 6)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 6)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .liquidGlass(cornerRadius: 18, fillOpacity: 0.05)
        .fullScreenCover(isPresented: $showPlayer) {
            let mediaItem = MediaItem(
                id: task.mediaId,
                title: task.title,
                type: task.type,
                posterPath: task.posterPath,
                backdropPath: task.backdropPath,
                posterSymbol: task.posterSymbol,
                posterColorHex: task.posterColorHex,
                genre: task.genre,
                rating: task.rating,
                releaseYear: task.releaseYear,
                duration: task.duration,
                description: task.description,
                isTrending: false,
                isNewRelease: false
            )
            
            if let localUrl = DownloadManager.shared.getLocalFileUrl(for: task) {
                MoviePlayerView(item: mediaItem, season: task.season, episode: task.episode, offlineUrl: localUrl)
            } else {
                MoviePlayerView(item: mediaItem, season: task.season, episode: task.episode)
            }
        }
    }
    
    private var placeholderIcon: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: task.posterColorHex), Color(hex: task.posterColorHex).opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Image(systemName: task.posterSymbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 54, height: 74)
        .cornerRadius(12)
    }
}
