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
