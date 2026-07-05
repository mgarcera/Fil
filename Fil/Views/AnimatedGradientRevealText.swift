import SwiftUI

struct AnimatedGradientRevealText: View {
    let text: String
    var elementDuration: TimeInterval = 0.28
    var perElementDelay: TimeInterval = 0.016
    var minDuration: TimeInterval = 1.0
    var maxDuration: TimeInterval? = nil
    var extraSlices: Int = 12
    /// Opacity each glyph settles to once its reveal finishes. Defaults to 1 (fully
    /// opaque). Lower it to let the colors read vividly during the reveal while the
    /// resting text fades back to a muted, placeholder-like level.
    var settledOpacity: Double = 1

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
                        perElementDelay: perElementDelay,
                        settledOpacity: settledOpacity
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

/// Text whose glyphs are filled with the accent gradient slowly drifting sideways — a
/// looping "thinking" shimmer (e.g. while a fil's title is being regenerated). Pairs
/// with `AnimatedGradientRevealText`, which then reveals the settled result.
struct AccentShimmerText: View {
    let text: String
    var period: TimeInterval = 1.6

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period) / period
            Text(text)
                .hidden()
                .overlay {
                    GeometryReader { geometry in
                        let width = max(geometry.size.width, 1)
                        // Accent colors doubled so the leftward drift loops seamlessly.
                        LinearGradient(
                            colors: Theme.accentGradientColors + Theme.accentGradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 2)
                        .offset(x: -width * CGFloat(phase))
                        .mask(alignment: .leading) { Text(text) }
                    }
                }
        }
    }
}

/// The inverse of `AnimatedGradientRevealText`: each glyph starts solid and then
/// blurs, rises, and fades out in accent colors — a one-shot "dissolve" used when a
/// typed fil is sent, so the text appears to scatter into the new blob.
struct GradientDissolveText: View {
    let text: String
    var elementDuration: TimeInterval = 0.26
    var perElementDelay: TimeInterval = 0.012
    var duration: TimeInterval = 0.55

    @State private var animationStartDate = Date()

    var body: some View {
        TimelineView(.animation) { context in
            Text(text)
                .textRenderer(
                    GradientDissolveTextRenderer(
                        elapsedTime: min(
                            max(0, context.date.timeIntervalSince(animationStartDate)),
                            duration
                        ),
                        elementDuration: elementDuration,
                        totalDuration: duration,
                        perElementDelay: perElementDelay
                    )
                )
        }
        .onAppear {
            animationStartDate = Date()
        }
    }
}

private struct GradientDissolveTextRenderer: TextRenderer {
    var elapsedTime: TimeInterval
    let elementDuration: TimeInterval
    let totalDuration: TimeInterval
    let perElementDelay: TimeInterval

    var animatableData: Double {
        get { elapsedTime }
        set { elapsedTime = newValue }
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
        // `progress` runs 0 (intact) -> 1 (fully dissolved).
        let progress = max(0, min(time / elementDuration, 1))
        let opacity = 1 - UnitCurve.easeIn.value(at: progress)
        let blurRadius = progress * max(1, slice.typographicBounds.rect.height / 18)
        let translationY = -progress * min(12, slice.typographicBounds.rect.height * 0.35)

        ctx.translateBy(x: 0, y: translationY)
        if blurRadius > 0.1 {
            ctx.addFilter(.blur(radius: blurRadius))
        }
        ctx.opacity = opacity

        if progress > 0 {
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
            ctx.addFilter(.brightness(progress * 0.08), options: .linearColor)
        } else {
            ctx.draw(slice, options: .disablesSubpixelQuantization)
        }
    }
}

private struct GradientRevealTextRenderer: TextRenderer {
    var elapsedTime: TimeInterval
    let elementDuration: TimeInterval
    let totalDuration: TimeInterval
    let perElementDelay: TimeInterval
    let settledOpacity: Double

    var animatableData: Double {
        get { elapsedTime }
        set { elapsedTime = newValue }
    }

    init(
        elapsedTime: TimeInterval,
        elementDuration: TimeInterval = 0.28,
        totalDuration: TimeInterval,
        perElementDelay: TimeInterval = 0.016,
        settledOpacity: Double = 1
    ) {
        self.elapsedTime = min(elapsedTime, totalDuration)
        self.elementDuration = elementDuration
        self.totalDuration = totalDuration
        self.perElementDelay = perElementDelay
        self.settledOpacity = settledOpacity
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
            // Reveal finished: settle to the resting opacity (kept full during the
            // reveal so the accent colors read vividly).
            ctx.opacity = settledOpacity
            ctx.draw(slice, options: .disablesSubpixelQuantization)
        }
    }
}
