import SwiftUI

struct FilrTopEdgeGlow: View {
    let startColor: Color
    let endColor: Color

    private var strokeGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                startColor,
                startColor.mix(with: endColor, by: 0.35),
                endColor,
                startColor
            ]),
            center: .top
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(strokeGradient, lineWidth: 4)
                .blur(radius: 1)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(strokeGradient, lineWidth: 10)
                .blur(radius: 10)
                .opacity(0.72)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(strokeGradient, lineWidth: 18)
                .blur(radius: 15)
                .opacity(1.0)
        }
        .padding(.horizontal, -25)
        .padding(.top, -25)
        .allowsHitTesting(false)
        .mask(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0.0),
                    .init(color: .white, location: 0.012),
                    .init(color: .white, location: 0.028),
                    .init(color: .clear, location: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

struct FilrStageBackdrop: View {
    let startColor: Color
    let endColor: Color
    let isGenerating: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(startColor.opacity(isGenerating ? 0.24 : 0.16))
                .frame(width: isGenerating ? 180 : 150, height: isGenerating ? 180 : 150)
                .blur(radius: isGenerating ? 44 : 34)
                .offset(x: -54, y: -58)
                .animation(.easeInOut(duration: 1.2), value: isGenerating)

            Circle()
                .fill(endColor.opacity(isGenerating ? 0.22 : 0.14))
                .frame(width: isGenerating ? 190 : 160, height: isGenerating ? 190 : 160)
                .blur(radius: isGenerating ? 46 : 36)
                .offset(x: 126, y: -12)
                .animation(.easeInOut(duration: 1.1), value: isGenerating)

            Circle()
                .fill(startColor.mix(with: endColor, by: 0.5).opacity(isGenerating ? 0.2 : 0.12))
                .frame(width: isGenerating ? 220 : 180, height: isGenerating ? 220 : 180)
                .blur(radius: isGenerating ? 48 : 38)
                .offset(x: 40, y: 114)
                .animation(.easeInOut(duration: 1.3), value: isGenerating)
        }
        .frame(height: 240)
        .allowsHitTesting(false)
    }
}

struct FilrSheetBackground: View {
    let startColor: Color
    let endColor: Color
    let isLightMode: Bool

    private func adjustedOpacity(_ value: Double) -> Double {
        isLightMode ? min(value * 1.35, 1.0) : value
    }

    var body: some View {
        ZStack {
            Theme.background

            FilrStageBackdrop(
                startColor: startColor,
                endColor: endColor,
                isGenerating: false
            )
            .scaleEffect(1.5)
            .offset(y: 250)
            .opacity(adjustedOpacity(0.95))

            FilrStageBackdrop(
                startColor: startColor,
                endColor: endColor,
                isGenerating: false
            )
            .scaleEffect(1.15)
            .offset(x: 70, y: 160)
            .opacity(adjustedOpacity(0.55))

            FilrStageBackdrop(
                startColor: startColor,
                endColor: endColor,
                isGenerating: false
            )
            .scaleEffect(1.05)
            .offset(x: -90, y: 210)
            .opacity(adjustedOpacity(0.4))

            FilrStageBackdrop(
                startColor: startColor,
                endColor: endColor,
                isGenerating: false
            )
            .scaleEffect(0.9)
            .offset(x: 150, y: 120)
            .opacity(adjustedOpacity(0.42))

            FilrStageBackdrop(
                startColor: startColor.mix(with: endColor, by: 0.55),
                endColor: endColor.mix(with: startColor, by: 0.2),
                isGenerating: false
            )
            .scaleEffect(0.75)
            .offset(x: 120, y: 90)
            .opacity(adjustedOpacity(0.34))

            FilrStageBackdrop(
                startColor: startColor,
                endColor: endColor,
                isGenerating: false
            )
            .scaleEffect(0.95)
            .offset(x: -140, y: 240)
            .opacity(adjustedOpacity(0.4))
        }
    }
}
