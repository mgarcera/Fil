import SwiftUI

struct MeshGradientView: View {
    @State private var points: [SIMD2<Float>] = MeshGradientView.initialPoints
    private let animationSpeed: Double = 4
    private let timerDuration: UInt64 = 3_000_000_000

    private static let initialPoints: [SIMD2<Float>] = [
        SIMD2(0.0, 0.0), SIMD2(0.5, 0.0), SIMD2(1.0, 0.0),
        SIMD2(0.0, 0.5), SIMD2(0.5, 0.5), SIMD2(1.0, 0.5),
        SIMD2(0.0, 1.0), SIMD2(0.5, 1.0), SIMD2(1.0, 1.0)
    ]

    private let colors: [Color] = [
        .green.opacity(0.7),  .blue.opacity(0.6),   .indigo.opacity(0.7),
        .orange.opacity(0.6), .pink.opacity(0.5),    .blue.opacity(0.6),
        .indigo.opacity(0.7), .green.opacity(0.7),   .orange.opacity(0.6)
    ]

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: points,
            colors: colors,
            smoothsColors: true
        )
        .background(.black)
        .task {
            randomizePoints()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: timerDuration)
                randomizePoints()
            }
        }
    }

    private func randomizePoints() {
        withAnimation(.easeInOut(duration: animationSpeed)) {
            points = [
                SIMD2(0.0, 0.0),
                SIMD2(Float.random(in: 0.3...0.7), 0.0),
                SIMD2(1.0, 0.0),

                SIMD2(0.0, Float.random(in: 0.3...0.7)),
                SIMD2(Float.random(in: 0.3...0.7), Float.random(in: 0.3...0.7)),
                SIMD2(1.0, Float.random(in: 0.3...0.7)),

                SIMD2(0.0, 1.0),
                SIMD2(Float.random(in: 0.3...0.7), 1.0),
                SIMD2(1.0, 1.0)
            ]
        }
    }
}
