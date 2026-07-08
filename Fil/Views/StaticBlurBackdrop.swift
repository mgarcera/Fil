import SwiftUI

/// Rasterizes an expensive, blurred decorative backdrop into a single static image, then stretches
/// that one image as its container resizes — so a sheet detent drag (e.g. 0.6 → full) doesn't re-run
/// layout for every blurred circle/stroke each frame. The heavy blur hides the stretch, so the look
/// is preserved.
///
/// Re-renders when the width changes (a vertical resize just stretches the image) OR when `contentID`
/// changes — the latter matters because the presenting sheet reuses this view instance across
/// different fils; without it, switching fils quickly (same width) would keep the previous fil's
/// cached gradient. Pass the fil's identity (e.g. `note.uuid`) as `contentID`.
///
/// Shared by the article view and the filaments (keyword) sheet.
struct StaticBlurBackdrop<Content: View>: View {
    /// Must be passed explicitly: ImageRenderer does NOT inherit the SwiftUI environment,
    /// so without this the snapshot renders in light mode (Theme.background → white).
    let colorScheme: ColorScheme
    /// Identity of the content being rendered. When it changes, the snapshot is regenerated even if
    /// the width is unchanged.
    let contentID: AnyHashable
    @ViewBuilder let content: () -> Content

    @Environment(\.displayScale) private var displayScale
    @State private var snapshot: Image?
    @State private var renderedKey: RenderKey?

    private struct RenderKey: Equatable {
        let width: CGFloat
        let id: AnyHashable
    }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let snapshot {
                    snapshot.resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: RenderKey(width: proxy.size.width, id: contentID)) {
                render(size: proxy.size)
            }
        }
    }

    @MainActor
    private func render(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let key = RenderKey(width: size.width, id: contentID)
        guard key != renderedKey else { return }
        let renderer = ImageRenderer(
            content: content()
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            snapshot = Image(uiImage: uiImage)
            renderedKey = key
        }
    }
}
