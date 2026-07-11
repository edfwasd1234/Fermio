import SwiftUI

/// A view modifier that applies a premium native liquid glassmorphism effect using Apple's iOS 26+ API.
struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat
    
    func body(content: Content) -> some View {
        content
            .glassEffect(in: RoundedRectangle(cornerRadius: cornerRadius))
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
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}

/// A background view helper that uses native dark system backgrounds.
struct LiquidBackgroundView: View {
    var body: some View {
        Color.black.ignoresSafeArea()
    }
}

