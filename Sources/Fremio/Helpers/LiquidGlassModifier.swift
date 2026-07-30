import SwiftUI

/// A view modifier that applies a premium native liquid glassmorphism effect
/// using Apple's iOS 26+ API, layered with a subtle fill, hairline border, and
/// colored glow so every parameter actually affects the rendered result.
struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    var borderWidth: CGFloat
    var fillOpacity: CGFloat
    var shadowRadius: CGFloat
    var glowColor: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(fillOpacity))
            )
            .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: borderWidth)
            )
            .shadow(color: glowColor.opacity(0.25), radius: shadowRadius, x: 0, y: 6)
    }
}

extension View {
    /// Applies a native liquid glass style to the view.
    func liquidGlass(
        cornerRadius: CGFloat = 20,
        borderWidth: CGFloat = 0.5,
        fillOpacity: CGFloat = 0.04,
        shadowRadius: CGFloat = 12,
        glowColor: Color = .white
    ) -> some View {
        self.modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            borderWidth: borderWidth,
            fillOpacity: fillOpacity,
            shadowRadius: shadowRadius,
            glowColor: glowColor
        ))
    }
}

/// A subtle ambient background: a near-black base with two soft colored glows
/// bleeding in from opposite corners, so the glass overlays have something to
/// react to (previously this was a flat black fill).
struct LiquidBackgroundView: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [Color.blue.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.purple.opacity(0.20), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

