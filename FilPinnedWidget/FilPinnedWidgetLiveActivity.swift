import ActivityKit
import WidgetKit
import SwiftUI

/// Widget-side mirror of the app's `PinnedFolderLiveActivityAttributes`. Must stay structurally
/// identical so ActivityKit can decode the shared content state.
struct PinnedFolderLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var name: String
        var count: Int
        var blobs: [FilActivityBlob]
        var gradientStartHex: String
        var gradientEndHex: String
        var updatedAt: Date
    }

    var folderID: UUID
}

struct FilPinnedWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PinnedFolderLiveActivityAttributes.self) { context in
            PinnedFolderLockScreenView(state: context.state)
                .activityBackgroundTint(nil)   // system default (adaptive/translucent) rather than a solid fill
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "fil://folder?id=\(context.attributes.folderID.uuidString)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FolderMark(size: 24, startHex: context.state.gradientStartHex, endHex: context.state.gradientEndHex)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.count)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    FilActivityBlobRow(blobs: context.state.blobs)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                        .padding(.bottom, 12)
                }
            } compactLeading: {
                FolderMark(size: 18, startHex: context.state.gradientStartHex, endHex: context.state.gradientEndHex)
            } compactTrailing: {
                Text("\(context.state.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            } minimal: {
                FolderMark(size: 16, startHex: context.state.gradientStartHex, endHex: context.state.gradientEndHex)
            }
            .widgetURL(URL(string: "fil://folder?id=\(context.attributes.folderID.uuidString)"))
            .keylineTint(Color(red: 0.2, green: 0.75, blue: 0.6))
            .contentMargins(.all, 0, for: .expanded)
        }
    }
}

private struct PinnedFolderLockScreenView: View {
    let state: PinnedFolderLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FolderMark(size: 22, startHex: state.gradientStartHex, endHex: state.gradientEndHex)
                Text(state.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Text(countLabel)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.72))

            FilActivityBlobRow(blobs: state.blobs)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .bottom) {
            FilLiveActivityBottomGlow(startHex: state.gradientStartHex, endHex: state.gradientEndHex)
        }
    }

    private var countLabel: String {
        let n = state.count
        return "\(n) \(n == 1 ? "item" : "items")"
    }
}

/// A small gradient blob (matching the note-card blobs) used in place of the logo.
struct FilBlobMark: View {
    let size: CGFloat
    let startHex: String
    let endHex: String

    private var seed: Double {
        let scalars = (startHex + endHex).unicodeScalars
        let hash = scalars.reduce(UInt32(2166136261)) { partial, scalar in
            (partial ^ scalar.value) &* 16777619
        }
        return Double(hash % 10_000) / 10_000
    }

    var body: some View {
        LiveActivityBlobShape(seed: seed)
            .fill(
                LinearGradient(
                    colors: [Color(hex: startHex), Color(hex: endHex)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Fil blobs (Lock Screen peek)

/// Widget-side mirror of the app's `FilActivityBlob`. Codable keys must match (startHex/endHex/seed).
struct FilActivityBlob: Codable, Hashable {
    var startHex: String
    var endHex: String
    var seed: Double

    static let samples: [FilActivityBlob] = [
        .init(startHex: "#33BF99", endHex: "#408CD9", seed: 0.12),
        .init(startHex: "#6659CC", endHex: "#E8196A", seed: 0.55),
        .init(startHex: "#F59E0B", endHex: "#F97316", seed: 0.78),
        .init(startHex: "#0EA5E9", endHex: "#22C55E", seed: 0.31),
        .init(startHex: "#E8196A", endHex: "#6659CC", seed: 0.91)
    ]
}

/// One fil drawn as its real gradient blob (same shape algorithm as the app's `NoteBlobShape`).
struct FilActivityBlobView: View {
    let blob: FilActivityBlob
    let size: CGFloat

    var body: some View {
        LiveActivityBlobShape(seed: blob.seed)
            .fill(
                LinearGradient(
                    colors: [Color(hex: blob.startHex), Color(hex: blob.endHex)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A left-aligned row of fil blobs — the peek shown under a Bin / pinned-folder headline.
struct FilActivityBlobRow: View {
    let blobs: [FilActivityBlob]
    var size: CGFloat = 28
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                FilActivityBlobView(blob: blob, size: size)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Bespoke marks (folder + bin)

/// The folder silhouette (tab + body), matching the app's `FolderShape`, filled with the folder's
/// own gradient. Used as the pinned-folder island glyph.
struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let radius = w * 0.28
        let tabHeight = h * 0.22
        let tabWidth = w * 0.5
        let bodyTop = rect.minY + tabHeight

        let tab = CGRect(x: rect.minX, y: rect.minY, width: tabWidth, height: tabHeight + radius * 2)
        path.addRoundedRect(in: tab, cornerSize: CGSize(width: radius, height: radius))

        let body = CGRect(x: rect.minX, y: bodyTop, width: w, height: rect.maxY - bodyTop)
        path.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius))

        return path
    }
}

struct FolderMark: View {
    let size: CGFloat
    let startHex: String
    let endHex: String

    var body: some View {
        FolderShape()
            .fill(
                LinearGradient(
                    colors: [Color(hex: startHex), Color(hex: endHex)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Fallback Bin gradient (teal → blue) when the Bin is empty of color data.
let binStartHex = "#33BF99"
let binEndHex = "#408CD9"

// MARK: - Chlorofil-style Bin coloration

/// Each fil's blended mid-color (start↔end), sampled across the Bin up to `cap` colors — the same
/// idea as the Chlorofil screensaver, which paints fils' mid-colors as light. Empty → the fallback.
func binGlowColors(_ blobs: [FilActivityBlob], cap: Int = 5) -> [Color] {
    let mids = blobs.map { midColor($0.startHex, $0.endHex) }
    guard !mids.isEmpty else { return [Color(hex: binStartHex), Color(hex: binEndHex)] }
    guard mids.count > cap else { return mids }
    return (0..<cap).map { mids[$0 * (mids.count - 1) / (cap - 1)] }
}

/// The 50/50 blend of two hex colors (widget-local — avoids depending on iOS 18's Color.mix).
private func midColor(_ startHex: String, _ endHex: String) -> Color {
    let a = rgbComponents(startHex), b = rgbComponents(endHex)
    return Color(.sRGB, red: (a.r + b.r) / 2, green: (a.g + b.g) / 2, blue: (a.b + b.b) / 2)
}

private func rgbComponents(_ hex: String) -> (r: Double, g: Double, b: Double) {
    let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    var value: UInt64 = 0
    guard Scanner(string: clean).scanHexInt64(&value), clean.count == 6 else {
        return (0.25, 0.55, 0.85)
    }
    return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
}

/// A soft multi-color glow pooled at the bottom — one blurred pool per sampled color, spread across
/// the width. The Bin's counterpart to the folder's single-gradient `FilLiveActivityBottomGlow`.
struct FilActivityColorGlow: View {
    let colors: [Color]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: (colors.first ?? .clear).opacity(0.28), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    Circle()
                        .fill(color.opacity(0.6))
                        .frame(width: 150, height: 150)
                        .blur(radius: 40)
                        .position(x: width * xFraction(index, of: colors.count), y: height + 28)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func xFraction(_ index: Int, of count: Int) -> CGFloat {
        guard count > 1 else { return 0.5 }
        return 0.15 + 0.7 * CGFloat(index) / CGFloat(count - 1)
    }
}

/// A soft gradient glow pooled at the bottom of the card, echoing the article view.
/// Fills whatever space it's given; the glow circles are centered just below the bottom
/// edge so only their soft upper falloff shows — no hard-clipped arcs.
struct FilLiveActivityBottomGlow: View {
    let startHex: String
    let endHex: String

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            ZStack {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: Color(hex: startHex).opacity(0.32), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(Color(hex: startHex).opacity(0.6))
                    .frame(width: 150, height: 150)
                    .blur(radius: 38)
                    .position(x: width * 0.28, y: height + 26)

                Circle()
                    .fill(Color(hex: endHex).opacity(0.6))
                    .frame(width: 160, height: 160)
                    .blur(radius: 40)
                    .position(x: width * 0.78, y: height + 30)
            }
        }
        .allowsHitTesting(false)
    }
}

struct LiveActivityBlobShape: Shape {
    let seed: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = 5 + Int(seed * 4.999)
        let amplitude = CGFloat(0.055 + (seed * 0.055))
        let secondaryFrequency = CGFloat(2 + Int(Self.unitNoise(seed, salt: 17) * 4))
        let tertiaryFrequency = CGFloat(3 + Int(Self.unitNoise(seed, salt: 23) * 4))
        let phaseA = CGFloat(seed * .pi * 2)
        let phaseB = CGFloat((1 - seed) * .pi * 2)
        let rotation = CGFloat((Self.unitNoise(seed, salt: 29) - 0.5) * 0.7)
        let asymmetryPhase = CGFloat(Self.unitNoise(seed, salt: 37) * .pi * 2)
        let asymmetryStrength = CGFloat((Self.unitNoise(seed, salt: 41) - 0.5) * 0.18)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radiusX = rect.width * 0.46
        let radiusY = rect.height * 0.42
        let blobPoints = (0..<points).map { index -> CGPoint in
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

extension Color {
    init(hex: String) {
        let cleanedHex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: cleanedHex)
        var rgb: UInt64 = 0

        guard scanner.scanHexInt64(&rgb), cleanedHex.count == 6 else {
            self.init(red: 0.25, green: 0.55, blue: 0.85)
            return
        }

        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

extension PinnedFolderLiveActivityAttributes {
    fileprivate static var preview: PinnedFolderLiveActivityAttributes {
        PinnedFolderLiveActivityAttributes(folderID: UUID())
    }
}

extension PinnedFolderLiveActivityAttributes.ContentState {
    fileprivate static var sample: PinnedFolderLiveActivityAttributes.ContentState {
        PinnedFolderLiveActivityAttributes.ContentState(
            name: "House move",
            count: 5,
            blobs: FilActivityBlob.samples,
            gradientStartHex: "#33BF99",
            gradientEndHex: "#408CD9",
            updatedAt: .now
        )
    }
}

#Preview("Pinned Folder", as: .content, using: PinnedFolderLiveActivityAttributes.preview) {
    FilPinnedWidgetLiveActivity()
} contentStates: {
    PinnedFolderLiveActivityAttributes.ContentState.sample
}
