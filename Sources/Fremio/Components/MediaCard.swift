import SwiftUI

/// A premium glassmorphic card component representing a Movie or Show.
struct MediaCard: View {
    let item: MediaItem
    var cardWidth: CGFloat = 145
    var cardHeight: CGFloat = 210

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
        }
        .buttonStyle(PressActionsButtonStyle(scale: 0.95))
        .sheet(isPresented: $showDetail) {
            MediaDetailView(item: item)
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

/// A `ButtonStyle` that scales its label while pressed. It reads
/// `configuration.isPressed` directly rather than mutating an external binding
/// during the view update (which the previous version did).
struct PressActionsButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
