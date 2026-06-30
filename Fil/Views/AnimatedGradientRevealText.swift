import SwiftUI

struct AnimatedGradientRevealText: View {
    let text: String
    var elementDuration: TimeInterval = 0.28
    var perElementDelay: TimeInterval = 0.016
    var minDuration: TimeInterval = 1.0
    var maxDuration: TimeInterval? = nil
    var extraSlices: Int = 12

    @State private var animationStartDate = Date()

    private var animationDuration: TimeInterval {
        let sliceCount = max(text.count, 1)
        let uncappedDuration = max(
            minDuration,
            elementDuration + (Double(sliceCount + extraSlices) * perElementDelay)
        )

        if let maxDuration {
            return min(maxDuration, uncappedDuration)
        }

        return uncappedDuration
    }

    var body: some View {
        TimelineView(.animation) { context in
            Text(text)
                .textRenderer(
                    GradientRevealTextRenderer(
                        elapsedTime: min(
                            max(0, context.date.timeIntervalSince(animationStartDate)),
                            animationDuration
                        ),
                        elementDuration: elementDuration,
                        totalDuration: animationDuration,
                        perElementDelay: perElementDelay
                    )
                )
        }
        .onAppear {
            startAnimation()
        }
        .onChange(of: text) { _, _ in
            startAnimation()
        }
    }

    private func startAnimation() {
        animationStartDate = Date()
    }
}

private struct GradientRevealTextRenderer: TextRenderer {
    var elapsedTime: TimeInterval
    let elementDuration: TimeInterval
    let totalDuration: TimeInterval
    let perElementDelay: TimeInterval

    var animatableData: Double {
        get { elapsedTime }
        set { elapsedTime = newValue }
    }

    init(
        elapsedTime: TimeInterval,
        elementDuration: TimeInterval = 0.28,
        totalDuration: TimeInterval,
        perElementDelay: TimeInterval = 0.016
    ) {
        self.elapsedTime = min(elapsedTime, totalDuration)
        self.elementDuration = elementDuration
        self.totalDuration = totalDuration
        self.perElementDelay = perElementDelay
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var sliceIndex = 0

        for line in layout {
            for run in line {
                for slice in run {
                    let timeOffset = TimeInterval(sliceIndex) * perElementDelay
                    let sliceTime = max(0, min(elapsedTime - timeOffset, elementDuration))
                    var copy = ctx
                    draw(slice, at: sliceTime, sliceIndex: sliceIndex, in: &copy)
                    sliceIndex += 1
                }
            }
        }
    }

    private func draw(
        _ slice: Text.Layout.RunSlice,
        at time: TimeInterval,
        sliceIndex: Int,
        in ctx: inout GraphicsContext
    ) {
        let progress = max(0, min(time / elementDuration, 1))
        let opacity = UnitCurve.easeOut.value(at: progress)
        let blurRadius = (1 - progress) * max(1, slice.typographicBounds.rect.height / 18)
        let translationY = (1 - progress) * min(12, slice.typographicBounds.rect.height * 0.35)

        ctx.translateBy(x: 0, y: translationY)
        if blurRadius > 0.1 {
            ctx.addFilter(.blur(radius: blurRadius))
        }
        ctx.opacity = opacity
        if progress < 1 {
            let tailRect = slice.typographicBounds.rect.insetBy(dx: -6, dy: -6)
            let startColor = Theme.accentGradientColors[sliceIndex % Theme.accentGradientColors.count]
            let endColor = Theme.accentGradientColors[(sliceIndex + 1) % Theme.accentGradientColors.count]

            ctx.clipToLayer { layer in
                layer.draw(slice, options: .disablesSubpixelQuantization)
            }
            ctx.fill(
                Path(tailRect),
                with: .linearGradient(
                    Gradient(colors: [startColor, endColor]),
                    startPoint: CGPoint(x: tailRect.minX, y: tailRect.minY),
                    endPoint: CGPoint(x: tailRect.maxX, y: tailRect.maxY)
                )
            )
            ctx.addFilter(.brightness((1 - progress) * 0.08), options: .linearColor)
        } else {
            ctx.draw(slice, options: .disablesSubpixelQuantization)
        }
    }
}
