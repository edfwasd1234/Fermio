import SwiftUI

/// Main coordinator view that anchors the custom GlassTabBar, views, and liquid backgrounds together.
struct ContentView: View {
    @State private var activeTab: TabItem = .home
    
    var body: some View {
        GlassEffectContainer(spacing: 20.0) {
            ZStack(alignment: .bottom) {
                // Liquid Mesh Ambient Background bleeding through all overlay glass elements
                LiquidBackgroundView()
                    .ignoresSafeArea()
                
                // Screen contents
                Group {
                    switch activeTab {
                    case .home:
                        HomeView()
                    case .search:
                        SearchView()
                    case .library:
                        LibraryView()
                    case .settings:
                        SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Custom Floating Capsule Liquid Glass Tab Bar
                GlassTabBar(activeTab: $activeTab)
            }
            .preferredColorScheme(.dark) // Force dark mode for optimal glow/glass pop
            .ignoresSafeArea(.keyboard, edges: .bottom) // Avoid tab bar shifting when typing in Search
        }
    }
}

#Preview {
    ContentView()
}
