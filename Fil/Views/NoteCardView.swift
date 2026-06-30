import SwiftUI

struct NoteCardView: View {
    let note: Note
    var showsKeywordBadge: Bool = true
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
                    Text(blobPreviewText)
                        .font(Theme.dmMono(8))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
                } else {
                    CompactWaveformView(duration: note.duration)
                    Text(formatDuration(note.duration))
                        .font(Theme.dmMono(10))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, note.audioFilePath.isEmpty ? 0 : 16)
        }
        .frame(height: 98)
        .overlay(selectionStroke)
        .overlay(alignment: .topTrailing) {
            let badgeText = note.displayBadgeText
            let linkBadgeColor = Color(hex: "#408CD9")
            if showsKeywordBadge, !badgeText.isEmpty {
                Text(badgeText)
                    .font(Theme.dmSans(9, weight: .semibold))
                    .foregroundStyle(note.isLinkFil ? .white : .black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(note.isLinkFil ? linkBadgeColor : .white, in: Capsule())
                    .overlay(Capsule().stroke(note.isLinkFil ? linkBadgeColor.opacity(0.85) : Theme.primaryText.opacity(0.5), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.6), radius: 6, x: 0, y: 4)
                    .padding(.trailing, 8)
            }
        }
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

    private var blobPreviewText: String {
        let source = [note.transcript, note.title]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "fil"
        let words = source
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let preview = words.prefix(4).joined(separator: " ")
        guard words.count > 4 || preview.count < source.count else { return preview }
        return "\(preview)..."
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
        NoteBlobShape(seed: seed)
            .fill(
                LinearGradient(
                    colors: [startColor, endColor],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
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
        let radiusX = squareRect.width * 0.46
        let radiusY = squareRect.height * 0.42
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
