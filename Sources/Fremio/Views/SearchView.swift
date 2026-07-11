import SwiftUI

/// The Search screen containing a glassmorphic input field, category cards, and dynamic filtering.
struct SearchView: View {
    @State private var searchQuery = ""
    @State private var searchResults: [MediaItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>? = nil
    
    let categories = [
        SearchCategory(name: "Action & Adventure", icon: "bolt.fill", gradientColors: [.orange, .red]),
        SearchCategory(name: "Sci-Fi & Fantasy", icon: "sparkles", gradientColors: [.blue, .purple]),
        SearchCategory(name: "Comedy", icon: "face.smiling.fill", gradientColors: [.yellow, .orange]),
        SearchCategory(name: "Thriller & Mystery", icon: "theatermasks.fill", gradientColors: [.purple, .pink]),
        SearchCategory(name: "Documentaries", icon: "doc.text.fill", gradientColors: [.teal, .green]),
        SearchCategory(name: "Anime", icon: "flame.fill", gradientColors: [.pink, .purple])
    ]
    
    // Grid columns layout
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Search")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            // Glassmorphic Search Bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.4))
                
                TextField("Search movies, shows, genres...", text: $searchQuery)
                    .foregroundColor(.white)
                    .font(.system(size: 15))
                    .accentColor(.blue)
                    .onChange(of: searchQuery) { newValue in
                        HapticManager.shared.impact(style: .soft)
                        runSearch(query: newValue)
                    }
                
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        searchResults = []
                        HapticManager.shared.impact(style: .light)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.system(size: 16))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .liquidGlass(cornerRadius: 18, fillOpacity: 0.08)
            .padding(.horizontal, 24)
            
            // Search Results or Categories Grid
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    if searchQuery.isEmpty {
                        // Category Selection Grid
                        Text("Browse Categories")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundColor(.white)
                        
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(categories) { category in
                                Button {
                                    HapticManager.shared.impact(style: .medium)
                                    // Extract first word to trigger search
                                    searchQuery = category.name.components(separatedBy: " ").first ?? category.name
                                } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Image(systemName: category.icon)
                                            .font(.system(size: 24))
                                            .foregroundColor(.white)
                                        
                                        Spacer()
                                        
                                        Text(category.name)
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundColor(.white)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .frame(height: 110)
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(
                                                LinearGradient(
                                                    colors: category.gradientColors.map { $0.opacity(0.7) },
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                    )
                                    .shadow(color: category.gradientColors.first?.opacity(0.2) ?? .clear, radius: 10, x: 0, y: 5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        // Search Results List
                        HStack {
                            Text("Search Results for \"\(searchQuery)\"")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            Spacer()
                            
                            if isSearching {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                        }
                        
                        if searchResults.isEmpty && !isSearching {
                            VStack(spacing: 12) {
                                Image(systemName: "film")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.2))
                                Text("No items match your search")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                        } else {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(searchResults) { item in
                                    MediaCard(item: item, cardWidth: 160, cardHeight: 230)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                        .frame(height: 100)
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    private func runSearch(query: String) {
        searchTask?.cancel()
        
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        
        searchTask = Task {
            // Debounce for 400ms
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            
            do {
                let results = try await TMDBService.shared.search(query: trimmed)
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.isSearching = false
                }
            }
        }
    }
}

/// Search categories data structure
struct SearchCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let gradientColors: [Color]
}
