import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Image {
    init?(data: Data) {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        self.init(uiImage: uiImage)
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data) else { return nil }
        self.init(nsImage: nsImage)
        #endif
    }
}

enum Theme {
    // MARK: - Core Colors

    static let background = Color("Background")
    static let primaryText = Color("PrimaryText")
    static let secondaryText = Color("SecondaryText")
    static let tertiaryText = Color("TertiaryText")
    static let divider = Color("Divider")
    static let cardBackground = Color("CardBackground")

    // MARK: - Tab Colors

    static let activeTabText = Color("ActiveTabText")
    static let activeTabBackground = Color("ActiveTabBackground")
    static let inactiveTabText = Color("InactiveTabText")
    static let inactiveTabBackground = Color("InactiveTabBackground")

    static let cardRadius: CGFloat = 22
    static let recordRed = Color(red: 0.9, green: 0.2, blue: 0.2)
    static let accentGradientColors: [Color] = [Color(hex: "#33BF99"), .green, .blue, .pink, .orange, .indigo]

    static func dmSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func dmMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static let filGradientPalettes: [[String]] = [
        [
            "#F24D59",  // coral red
            "#E67333",  // burnt orange
            "#D9A626",  // amber
            "#33BF99",  // teal
            "#408CD9",  // ocean blue
            "#6659CC",  // indigo
            "#E8196A",  // electric crimson
            "#4DB366",  // emerald
        ],
        [
            "#5C2318",  // mahogany
            "#355E3B",  // deep leaf
            "#B85C38",  // burnt sienna
            "#1E5265",  // deep teal
            "#A3B18A",  // soft moss
            "#4F7C72",  // eucalyptus
            "#D99A5B",  // warm amber
            "#E0C27A",  // faded gold
            "#EAD5A3",  // pollen
        ],
    ]

    static func randomGradientPair(
        avoidingRecentPairs recentPairs: Set<String> = [],
        avoidingRecentColors recentColors: Set<String> = []
    ) -> (start: String, end: String) {
        let candidates = filGradientPalettes.flatMap { palette in
            palette.indices.flatMap { i in
                palette.indices.compactMap { j -> (start: String, end: String)? in
                    guard i != j else { return nil }
                    return (start: palette[i], end: palette[j])
                }
            }
        }
        guard !candidates.isEmpty else { return (start: "#408CD9", end: "#6659CC") }

        let filtered = candidates.filter { candidate in
            !recentPairs.contains(pairKey(candidate))
            && !recentPairs.contains(pairKey((start: candidate.end, end: candidate.start)))
            && !(recentColors.contains(candidate.start) && recentColors.contains(candidate.end))
        }

        return (filtered.isEmpty ? candidates : filtered).randomElement() ?? candidates[0]
    }

    private static func pairKey(_ pair: (start: String, end: String)) -> String {
        "\(pair.start)|\(pair.end)"
    }

    static func gradient(startHex: String, endHex: String) -> LinearGradient {
        let startColor = Color(hex: startHex)
        let endColor = Color(hex: endHex)
        return LinearGradient(
            gradient: Gradient(stops: smoothGradientStops(from: startColor, to: endColor)),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: accentGradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private static func smoothGradientStops(from startColor: Color, to endColor: Color, steps: Int = 16) -> [Gradient.Stop] {
        guard steps > 1 else {
            return [
                .init(color: startColor, location: 0),
                .init(color: endColor, location: 1)
            ]
        }

        return (0..<steps).map { index in
            let progress = Double(index) / Double(steps - 1)
            let eased = easedProgress(progress)
            return Gradient.Stop(
                color: startColor.mix(with: endColor, by: eased),
                location: progress
            )
        }
    }

    private static func easedProgress(_ progress: Double) -> Double {
        // Holds onto the edge colors longer than a linear blend, which keeps
        // saturated note gradients from collapsing into a dull midpoint.
        progress * progress * (3 - 2 * progress)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    var luminance: Double {
        let resolved = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: nil)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    func mix(with other: Color, by progress: Double) -> Color {
        let start = UIColor(self)
        let end = UIColor(other)

        var r1: CGFloat = 0
        var g1: CGFloat = 0
        var b1: CGFloat = 0
        var a1: CGFloat = 0
        start.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)

        var r2: CGFloat = 0
        var g2: CGFloat = 0
        var b2: CGFloat = 0
        var a2: CGFloat = 0
        end.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        let t = max(0, min(1, progress))
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t),
            opacity: Double(a1 + (a2 - a1) * t)
        )
    }
}
