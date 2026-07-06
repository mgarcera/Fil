import SwiftUI
import UniformTypeIdentifiers

/// A shareable, branded image of a fil — the fil's own gradient blob, its title, a short excerpt,
/// and the wordmark — so every share is a free, on-brand impression. Rendered on demand at share
/// time (not eagerly) via `ImageRenderer`.
///
/// The data is a plain value type so it's `Sendable`/`Transferable`; the actual bitmap is produced
/// only when the user picks a share destination.
nonisolated struct FilShareCardData: Transferable {
    let title: String
    let excerpt: String
    let startHex: String
    let endHex: String
    let seed: Double

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            await card.renderPNG()
        }
        .suggestedFileName("fil.png")
    }

    /// Renders the card to PNG data. `ImageRenderer` is main-actor-only, hence the isolation.
    @MainActor
    func renderPNG() -> Data {
        let renderer = ImageRenderer(content: FilShareCard(data: self).frame(width: 1080, height: 1080))
        renderer.scale = 2
        return renderer.uiImage?.pngData() ?? Data()
    }
}

/// The visual card. Fixed dark canvas + the fil's gradient blob, so it reads consistently wherever
/// it's shared regardless of the sharer's appearance settings.
struct FilShareCard: View {
    let data: FilShareCardData

    var body: some View {
        ZStack {
            Color(hex: "#0E0E12")

            VStack(spacing: 44) {
                NoteBlobShape(seed: data.seed)
                    .fill(Theme.gradient(startHex: data.startHex, endHex: data.endHex, seed: data.seed))
                    .frame(width: 380, height: 380)
                    .shadow(color: .black.opacity(0.35), radius: 40, y: 16)

                VStack(spacing: 20) {
                    Text(data.title)
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.white)

                    if !data.excerpt.isEmpty {
                        Text(data.excerpt)
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 96)
            }
            .padding(80)

            VStack {
                Spacer()
                Text("fil · let thoughts be")
                    .font(.system(size: 26, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 60)
            }
        }
        .frame(width: 1080, height: 1080)
    }
}
