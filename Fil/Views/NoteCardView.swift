import SwiftUI

struct NoteCardView: View {
    let note: Note
    var cardHeight: CGFloat = 98
    var selectionStrokeColor: Color?
    var selectionStrokeLineWidth: CGFloat = 0
    var selectionStrokeShadowOpacity: Double = 0

    var body: some View {
        ZStack {
            if note.isImageFil {
                NoteBlobBackground(
                    startColor: Color(hex: note.gradientStartHex),
                    endColor: Color(hex: note.gradientEndHex),
                    seed: note.blobShapeSeed
                )

                if let firstImageData = note.sortedImageFilImages.first?.data,
                   let image = Image(data: firstImageData) {
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(NoteBlobShape(seed: note.blobShapeSeed))
                        .padding(5)
                }
            } else if let imageData = note.imageData, let image = Image(data: imageData) {
                image
                    .resizable()
                    .scaledToFill()
                    .clipShape(NoteBlobShape(seed: note.blobShapeSeed))
            } else {
                NoteBlobBackground(
                    startColor: Color(hex: note.gradientStartHex),
                    endColor: Color(hex: note.gradientEndHex),
                    seed: note.blobShapeSeed
                )
            }

            VStack(spacing: 4) {
                if note.isImageFil {
                    EmptyView()
                } else if note.isLinkFil {
                    linkBlobIcon
                } else if note.audioFilePath.isEmpty {
                    // Mirrors the audio fil: the word count is the prominent content
                    // (like the waveform) with the DM Mono unit underneath (like the duration).
                    Text("\(blobWordCount)")
                        .font(Theme.dmMono(12, weight: .bold))
                        .foregroundStyle(blobTextColor.opacity(0.95))
                    Text(blobWordCount == 1 ? "word" : "words")
                        .font(Theme.dmMono(10))
                        .foregroundStyle(blobTextColor.opacity(0.75))
                } else {
                    CompactWaveformView(duration: note.duration, color: blobTextColor)
                    Text(formatDuration(note.duration))
                        .font(Theme.dmMono(10))
                        .foregroundStyle(blobTextColor.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, note.audioFilePath.isEmpty ? 0 : 16)
            // The card is a fixed 98pt; clamp its blob content (word count / duration) so it can't
            // clip at large accessibility text sizes.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
        .frame(height: cardHeight)
        .overlay(selectionStroke)
    }

    @ViewBuilder
    private var linkBlobIcon: some View {
        if let faviconData = note.sourceFaviconData, let favicon = Image(data: faviconData) {
            favicon
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
        } else {
            Image(systemName: "link")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    @ViewBuilder
    private var selectionStroke: some View {
        if let selectionStrokeColor {
            NoteBlobShape(seed: note.blobShapeSeed)
                .stroke(selectionStrokeColor, lineWidth: selectionStrokeLineWidth)
                .shadow(color: .black.opacity(selectionStrokeShadowOpacity), radius: 5, x: 0, y: 2)
        }
    }

    /// Words of the note's text content (transcript preferred, else title), used for
    /// both the snippet and the word-count metric so the two always agree.
    private var blobSourceWords: [String] {
        let source = [note.transcript, note.title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "fil"
        return source
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    private var blobWordCount: Int {
        blobSourceWords.count
    }

    /// Near-black on light blobs, white on dark ones, so the word count stays legible
    /// across every gradient. Averages the two gradient stops' luminance.
    private var blobTextColor: Color {
        let start = Color(hex: note.gradientStartHex).luminance
        let end = Color(hex: note.gradientEndHex).luminance
        return (start + end) / 2 > 0.55 ? .black : .white
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct NoteBlobBackground: View {
    let startColor: Color
    let endColor: Color
    let seed: Double

    var body: some View {
        let points = Theme.gradientUnitPoints(seed: seed)
        NoteBlobShape(seed: seed)
            .fill(
                LinearGradient(
                    colors: [startColor, endColor],
                    startPoint: points.start,
                    endPoint: points.end
                )
            )
    }
}

struct NoteBlobShape: Shape {
    let seed: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let squareSide = min(rect.width, rect.height)
        let squareRect = CGRect(
            x: rect.midX - squareSide / 2,
            y: rect.midY - squareSide / 2,
            width: squareSide,
            height: squareSide
        )
        let points = 5 + Int(seed * 4.999)
        let amplitude = CGFloat(0.055 + (seed * 0.055))
        let secondaryFrequency = CGFloat(2 + Int(Self.unitNoise(seed, salt: 17) * 4))
        let tertiaryFrequency = CGFloat(3 + Int(Self.unitNoise(seed, salt: 23) * 4))
        let phaseA = CGFloat(seed * .pi * 2)
        let phaseB = CGFloat((1 - seed) * .pi * 2)
        let rotation = CGFloat((Self.unitNoise(seed, salt: 29) - 0.5) * 0.7)
        let asymmetryPhase = CGFloat(Self.unitNoise(seed, salt: 37) * .pi * 2)
        let asymmetryStrength = CGFloat((Self.unitNoise(seed, salt: 41) - 0.5) * 0.18)
        let center = CGPoint(x: squareRect.midX, y: squareRect.midY)
        let radiusX = squareRect.width * 0.50
        let radiusY = squareRect.height * 0.46
        let blobPoints = (0..<points).map { index in
            let angle = (CGFloat(index) / CGFloat(points) * .pi * 2) + rotation
            let pointOffset = CGFloat((Self.unitNoise(seed, salt: Double(index) + 101) - 0.5) * 0.22)
            let waveOffset = (
                sin(angle * secondaryFrequency + phaseA) * 0.65
                + sin(angle * tertiaryFrequency + phaseB) * 0.45
            ) * amplitude
            let asymmetryOffset = cos(angle + asymmetryPhase) * asymmetryStrength
            let radiusMultiplier = max(0.72, 1 + pointOffset + waveOffset + asymmetryOffset)
            return CGPoint(
                x: center.x + cos(angle) * radiusX * radiusMultiplier,
                y: center.y + sin(angle) * radiusY * radiusMultiplier
            )
        }

        guard let firstPoint = blobPoints.first else { return path }
        path.move(to: firstPoint)

        for index in 0..<points {
            let current = blobPoints[index]
            let next = blobPoints[(index + 1) % points]
            let previous = blobPoints[(index - 1 + points) % points]
            let following = blobPoints[(index + 2) % points]
            path.addCurve(
                to: next,
                control1: CGPoint(
                    x: current.x + (next.x - previous.x) * 0.2,
                    y: current.y + (next.y - previous.y) * 0.2
                ),
                control2: CGPoint(
                    x: next.x - (following.x - current.x) * 0.2,
                    y: next.y - (following.y - current.y) * 0.2
                )
            )
        }

        path.closeSubpath()
        return path
    }

    private static func unitNoise(_ seed: Double, salt: Double) -> Double {
        let value = sin((seed + 0.137) * (salt + 12.9898) * 78.233) * 43758.5453
        return value - floor(value)
    }
}

extension Note {
    var blobShapeSeed: Double {
        let scalars = uuid.uuidString.unicodeScalars
        let hash = scalars.reduce(UInt32(2166136261)) { partial, scalar in
            (partial ^ scalar.value) &* 16777619
        }
        return Double(hash % 10_000) / 10_000
    }
}
