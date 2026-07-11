import SwiftUI

/// Settings management view with preference configurations, toggle actions, and haptic indicators.
struct SettingsView: View {
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("autoPlayPreviews") private var autoPlayPreviews = true
    @AppStorage("hdStreaming") private var hdStreaming = true
    @AppStorage("tmdbApiKey") private var tmdbApiKey = "3d421899d5ce93db8ad4ae4591ccc130"
    
    @State private var easterEggCount = 0
    @State private var showEasterEgg = false
    @State private var cacheCleared = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) {
                    
                    // Profile Header Card
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.85))
                                .shadow(color: .blue.opacity(0.3), radius: 8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Alex Morgan")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Premium Member")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.cyan)
                            }
                            Spacer()
                        }
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                  Text("Account Email")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.gray)
                                Text("alex.morgan@fremio.app")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                            Spacer()
                        }
                    }
                    .padding(20)
                    .liquidGlass(cornerRadius: 24, fillOpacity: 0.05, glowColor: .blue.opacity(0.15))
                    
                    // Preferences Group
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PREFERENCES")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 8)
                        
                        VStack(spacing: 0) {
                            settingsToggleRow(
                                title: "Haptic Feedback",
                                icon: "hand.tap.fill",
                                iconColor: .cyan,
                                isEnabled: $hapticsEnabled
                            ) {
                                HapticManager.shared.impact(style: .medium)
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            settingsToggleRow(
                                title: "Auto-play Previews",
                                icon: "play.circle.fill",
                                iconColor: .orange,
                                isEnabled: $autoPlayPreviews
                            )
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            settingsToggleRow(
                                title: "HD Video Streaming",
                                icon: "sparkles.tv.fill",
                                iconColor: .purple,
                                isEnabled: $hdStreaming
                            )
                        }
                        .liquidGlass(cornerRadius: 20, fillOpacity: 0.04)
                    }
                    
                    // TMDB Configuration Group
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TMDB METADATA CONFIGURATION")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 8)
                        
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.yellow.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                
                                Text("API Key")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                TextField("Enter TMDB API Key", text: $tmdbApiKey)
                                    .multilineTextAlignment(.trailing)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.8))
                                    .frame(width: 180)
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .accentColor(.cyan)
                                    .onChange(of: tmdbApiKey) { _ in
                                        TMDBService.shared.clearCache() // Clear cache so new API key fetches fresh content
                                    }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .liquidGlass(cornerRadius: 20, fillOpacity: 0.04)
                    }
                    
                    // Account & Management Group
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ACCOUNT & MANAGEMENT")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 8)
                        
                        VStack(spacing: 0) {
                            settingsNavigationRow(
                                title: "Manage Subscription",
                                icon: "creditcard.fill",
                                iconColor: .green
                            ) {
                                HapticManager.shared.impact(style: .light)
                            }
                            
                            Divider().background(Color.white.opacity(0.1))
                            
                            settingsNavigationRow(
                                title: cacheCleared ? "Cache Cleared!" : "Clear Offline Cache",
                                icon: "trash.fill",
                                iconColor: cacheCleared ? .green : .red
                            ) {
                                TMDBService.shared.clearCache()
                                withAnimation {
                                    cacheCleared = true
                                }
                                HapticManager.shared.notification(type: .success)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    withAnimation {
                                        cacheCleared = false
                                    }
                                }
                            }
                        }
                        .liquidGlass(cornerRadius: 20, fillOpacity: 0.04)
                    }
                    
                    // Branding Logo & Easter Egg (Cascade Haptics)
                    VStack(spacing: 8) {
                        Image(systemName: "popcorn.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.blue, .purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: .purple.opacity(0.4), radius: 8)
                            .onTapGesture {
                                easterEggCount += 1
                                if easterEggCount >= 5 {
                                    triggerHapticCascade()
                                    showEasterEgg = true
                                    easterEggCount = 0
                                } else {
                                    HapticManager.shared.impact(style: .light)
                                }
                            }
                        
                        Text("Fremio v1.0")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Crafted with Liquid Glass aesthetics")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        
                        if showEasterEgg {
                            Text("✨ Haptic cascade unlocked! ✨")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.cyan)
                                .padding(.top, 4)
                                .transition(.opacity)
                                .onAppear {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                        withAnimation {
                                            showEasterEgg = false
                                        }
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 16)
                    
                    Spacer()
                        .frame(height: 100)
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    // Toggles Settings Row
    private func settingsToggleRow(
        title: String,
        icon: String,
        iconColor: Color,
        isEnabled: Binding<Bool>,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(8)
                .background(iconColor.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .onChange(of: isEnabled.wrappedValue) { _ in
                    action?()
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // Action/Navigation Settings Row
    private func settingsNavigationRow(
        title: String,
        icon: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(iconColor.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
    
    // Custom trigger for cascade haptics easter egg
    private func triggerHapticCascade() {
        let delay = 0.15
        
        // Triggers initial success
        HapticManager.shared.notification(type: .success)
        
        // Sequentially queue various haptic responses
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            HapticManager.shared.impact(style: .light)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay * 2)) {
            HapticManager.shared.impact(style: .medium)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay * 3)) {
            HapticManager.shared.impact(style: .heavy)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay * 4)) {
            HapticManager.shared.impact(style: .rigid)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (delay * 5)) {
            HapticManager.shared.notification(type: .error)
        }
    }
}
