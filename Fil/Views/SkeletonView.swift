import SwiftUI

/// A shimmering skeleton fill for any shape — a soft placeholder shown while content loads.
/// Ported from Balaji Venkatesh's Skeleton template; kept self-contained.
struct SkeletonView<S: Shape>: View {
    var shape: S
    var color: Color

    init(_ shape: S, _ color: Color = .gray.opacity(0.28)) {
        self.shape = shape
        self.color = color
    }

    @State private var isAnimating = false

    var body: some View {
        shape
            .fill(color)
            .overlay {
                GeometryReader {
                    let size = $0.size
                    let skeletonWidth = size.width / 2
                    let blurRadius = max(skeletonWidth / 2, 30)
                    let blurDiameter = blurRadius * 2
                    let minX = -(skeletonWidth + blurDiameter)
                    let maxX = size.width + skeletonWidth + blurDiameter

                    Rectangle()
                        .fill(.gray)
                        .frame(width: skeletonWidth, height: size.height * 2)
                        .frame(height: size.height)
                        .blur(radius: blurRadius)
                        .rotationEffect(.degrees(5))
                        .blendMode(.softLight)
                        .offset(x: isAnimating ? maxX : minX)
                }
            }
            .clipShape(shape)
            .compositingGroup()
            .task { @MainActor in
                guard !isAnimating else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
            .onDisappear { isAnimating = false }
            .transaction {
                if $0.animation != .easeInOut(duration: 1.5).repeatForever(autoreverses: false) {
                    $0.animation = .none
                }
            }
    }
}
