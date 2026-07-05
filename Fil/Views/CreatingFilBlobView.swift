import SwiftUI

/// The gooey, animated blob shown in a grid slot (and, smaller, near the composer)
/// while a fil is being created. It solidifies and morphs into the real fil card via
/// matched geometry once creation completes.
struct CreatingFilBlobView: View {
    var gradientColors: [Color] = Theme.accentGradientColors

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = CGFloat(timeline.date.timeIntervalSinceReferenceDate) * 0.9
            let rotation = time * 0.6
            let spread = 0.16 + ((sin(time * 1.15) + 1) * 0.16)
            let overlayStart = UnitPoint(x: 0.5 + cos(rotation) * spread, y: 0.5 + sin(rotation) * spread)
            let overlayEnd = UnitPoint(x: 0.5 - cos(rotation) * spread, y: 0.5 - sin(rotation) * spread)

            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)

                ZStack {
                    BlobShape(points: 5, amplitude: max(2, side * 0.03), time: time)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    BlobShape(points: 6, amplitude: max(1.4, side * 0.022), time: time * 0.82 + 1.3)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.7), .orange.opacity(0.7)],
                                startPoint: overlayStart,
                                endPoint: overlayEnd
                            )
                        )
                        .blendMode(.plusLighter)
                        .blur(radius: max(4, side * 0.06))
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityLabel("Creating fil")
    }
}

/// A smoothly wobbling blob outline whose points drift over `time` — used for the
/// gooey fil-creation animation above.
struct BlobShape: Shape {
    let points: Int
    let deformation: CGFloat
    let time: CGFloat

    init(points: Int = 6, amplitude: CGFloat = 4, time: CGFloat = 0) {
        self.points = max(3, min(points, 32))
        self.deformation = amplitude
        self.time = time
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        var blobPoints: [CGPoint] = []
        for index in 0..<points {
            let angle = CGFloat(index) / CGFloat(points) * .pi * 2
            let s1 = sin(angle * 5.0 - time + 512.0) * 2.0
            let s2 = sin(angle * 2.0 + time * 1.8 + 21.0) * 2.0
            let noise = (s1 + s2) * deformation
            let dynamicRadius = radius + noise
            let x = center.x + cos(angle) * dynamicRadius
            let y = center.y + sin(angle) * dynamicRadius
            blobPoints.append(CGPoint(x: x, y: y))
        }

        guard let firstPoint = blobPoints.first else {
            return path
        }

        path.move(to: firstPoint)

        for index in 0..<points {
            let currentPoint = blobPoints[index]
            let nextPoint = blobPoints[(index + 1) % points]
            let previousPoint = blobPoints[(index - 1 + points) % points]

            let control1 = CGPoint(
                x: currentPoint.x + (nextPoint.x - previousPoint.x) * 0.2,
                y: currentPoint.y + (nextPoint.y - previousPoint.y) * 0.2
            )

            let control2 = CGPoint(
                x: nextPoint.x - (blobPoints[(index + 2) % points].x - currentPoint.x) * 0.2,
                y: nextPoint.y - (blobPoints[(index + 2) % points].y - currentPoint.y) * 0.2
            )

            path.addCurve(to: nextPoint, control1: control1, control2: control2)
        }

        path.closeSubpath()
        return path
    }
}

/// Applies `matchedGeometryEffect` only when a namespace is available, so views can
/// opt into the fil-creation morph without every call site owning a `@Namespace`.
private struct FilCreationMatchedGeometry: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?
    var isSource: Bool = true

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            content
        }
    }
}

extension View {
    func filCreationMorph(id: UUID, in namespace: Namespace.ID?, isSource: Bool = true) -> some View {
        modifier(FilCreationMatchedGeometry(id: id, namespace: namespace, isSource: isSource))
    }

    /// Associates a Liquid Glass effect ID only when a namespace is available, so glass
    /// shapes can morph into each other (e.g. the composer pill ↔ expanded panel).
    @ViewBuilder
    func glassMorphID(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}
