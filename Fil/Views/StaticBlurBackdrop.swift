import SwiftUI

/// Rasterizes an expensive, blurred decorative backdrop into a single static image, then stretches
/// that one image as its container resizes — so a sheet detent drag (e.g. 0.6 → full) doesn't re-run
/// layout for every blurred circle/stroke each frame. The heavy blur hides the stretch, so the look
/// is preserved. Only re-renders when the width changes (a vertical resize just stretches the image).
///
/// Shared by the article view and the filaments (keyword) sheet.
struct StaticBlurBackdrop<Content: View>: View {
    /// Must be passed explicitly: ImageRenderer does NOT inherit the SwiftUI environment,
    /// so without this the snapshot renders in light mode (Theme.background → white).
    let colorScheme: ColorScheme
    @ViewBuilder let content: () -> Content

    @Environment(\.displayScale) private var displayScale
    @State private var snapshot: Image?
    @State private var renderedWidth: CGFloat = 0

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
            .task(id: proxy.size.width) {
                render(size: proxy.size)
            }
        }
    }

    @MainActor
    private func render(size: CGSize) {
        guard size.width > 0, size.height > 0, size.width != renderedWidth else { return }
        let renderer = ImageRenderer(
            content: content()
                .frame(width: size.width, height: size.height)
                .environment(\.colorScheme, colorScheme)
        )
        renderer.scale = displayScale
        if let uiImage = renderer.uiImage {
            snapshot = Image(uiImage: uiImage)
            renderedWidth = size.width
        }
    }
}
