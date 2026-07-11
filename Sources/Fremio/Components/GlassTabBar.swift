import SwiftUI

/// Tab enum items for application navigation
enum TabItem: Int, CaseIterable {
    case home
    case search
    case library
    case settings
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .library: return "Library"
        case .settings: return "Settings"
        }
    }
    
    var iconName: String {
        switch self {
        case .home: return "popcorn.fill"
        case .search: return "magnifyingglass"
        case .library: return "play.square.stack.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// A floating, capsule-shaped glassmorphic Tab Bar for high-end look and feel.
struct GlassTabBar: View {
    @Binding var activeTab: TabItem
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(TabItem.allCases, id: \.self) { tab in
                TabBarButton(tab: tab, activeTab: $activeTab)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Apply liquid glassmorphic effect
        .liquidGlass(
            cornerRadius: 32,
            borderWidth: 0.6,
            fillOpacity: 0.08,
            shadowRadius: 18,
            glowColor: .blue.opacity(0.2)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
}

/// Helper button for the GlassTabBar representing a single navigation destination.
struct TabBarButton: View {
    let tab: TabItem
    @Binding var activeTab: TabItem
    @State private var bounceScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.0
    
    var isSelected: Bool {
        activeTab == tab
    }
    
    var body: some View {
        Button {
            if activeTab != tab {
                // Play standard iOS selection haptic feedback
                HapticManager.shared.selection()
                
                // Animate selection transition
                withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.7)) {
                    activeTab = tab
                }
                
                // Animate tab icon spring bounce
                withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) {
                    bounceScale = 1.3
                    glowOpacity = 0.8
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        bounceScale = 1.0
                        glowOpacity = 0.0
                    }
                }
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Custom selection aura/glow behind the icon
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 40, height: 40)
                        .blur(radius: 6)
                        .opacity(isSelected ? 1.0 : 0.0)
                        .scaleEffect(bounceScale)
                    
                    Image(systemName: tab.iconName)
                        .font(.system(size: 21, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.45))
                        .scaleEffect(bounceScale)
                        .shadow(color: isSelected ? .blue.opacity(0.7) : .clear, radius: 10)
                }
                
                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
