import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A full-screen "screensaver" that arranges every fil as a blob in a centered
/// square lattice. A gentle swell travels corner-to-corner and reflects back,
/// like fluid settling in a tray, brightening each diagonal band as it passes.
/// Every other interaction point disappears; a tap anywhere returns home.
struct FilScreensaverView: View {
    var onExit: () -> Void

    /// Precomputed, immutable per-fil visual data. Blob paths are generated once
    /// (they're static per fil) so each animation frame only applies transforms.
    /// Built in `init` rather than `onAppear` so the very first `Canvas` render
    /// closure captures them — SwiftUI can't diff the closure to pick up a later
    /// `@State` change, so state set in `onAppear` would never reach the Canvas.
    private let tiles: [Tile]

    init(notes: [Note], onExit: @escaping () -> Void) {
        self.onExit = onExit
        self.tiles = Self.buildTiles(from: notes)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(&context, size: size, time: time)
            }
        }
        .background(Theme.background)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onExit() }
        .onAppear { setIdleTimer(disabled: true) }
        .onDisappear { setIdleTimer(disabled: false) }
    }

    // MARK: - Drawing

    /// Target resting blob diameter and the gap around it — matched to the collapsed
    /// blob dots on the home grid (24pt dots, ~10pt spacing).
    private let blobDiameter: CGFloat = 24
    private let blobSpacing: CGFloat = 10

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        guard !tiles.isEmpty else { return }

        let count = tiles.count

        // Cells are a fixed small size so blobs stay tiny and tightly packed (like the
        // home page's collapsed dots). Columns are however many fit across the width;
        // the resulting block is centered on screen.
        let cell = blobDiameter + blobSpacing
        let columns = max(1, Int(size.width / cell))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let gridWidth = cell * CGFloat(columns)
        let gridHeight = cell * CGFloat(rows)
        let originX = (size.width - gridWidth) / 2
        let originY = max(cell / 2, (size.height - gridHeight) / 2)

        // Fils in the final (possibly partial) row are centered so the block stays balanced.
        let lastRowCount = count - (rows - 1) * columns
        let lastRowIndent = CGFloat(columns - lastRowCount) / 2

        // A single swell that enters from the right edge, travels to the left, exits,
        // and repeats from the right — one directional sweep, not a reflecting slosh.
        // A small row-proportional term tilts the wavefront into a gentle "\" lean.
        let tilt = 0.35
        let reach = Double(columns - 1) + tilt * Double(rows - 1)
        let lead = 3.0            // room for the band to fully enter/exit off-screen
        let sweepSeconds = 7.0    // seconds for one right-to-left pass
        let cycle = (time / sweepSeconds).truncatingRemainder(dividingBy: 1)
        let waveHead = cycle * (reach + 2 * lead) - lead
        let sigma = 1.7

        for tile in tiles {
            let column = tile.order % columns
            let row = tile.order / columns
            // Distance from the right edge, tilted by row so the crest leans "\".
            let distance = Double(columns - 1 - column) + tilt * Double(row) - waveHead
            let band = exp(-(distance * distance) / (2 * sigma * sigma))
            // A faint, ever-present breath keeps resting fils alive between swells.
            let breath = 0.5 + 0.5 * sin(time * 0.7 + tile.phase * .pi * 2)
            let scale = 0.9 + 0.16 * band + 0.04 * breath

            let indent = row == rows - 1 ? lastRowIndent : 0
            let centerX = originX + (CGFloat(column) + indent + 0.5) * cell
            let centerY = originY + (CGFloat(row) + 0.5) * cell
            let blobSize = blobDiameter * scale
            let minX = centerX - blobSize / 2
            let minY = centerY - blobSize / 2

            let transform = CGAffineTransform(scaleX: blobSize, y: blobSize)
                .concatenating(CGAffineTransform(translationX: minX, y: minY))
            let path = tile.unitPath.applying(transform)

            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [tile.startColor, tile.endColor]),
                    startPoint: CGPoint(x: minX, y: minY),
                    endPoint: CGPoint(x: minX + blobSize, y: minY + blobSize)
                )
            )

            // The passing swell lifts brightness with an additive glow.
            if band > 0.02 {
                context.blendMode = .plusLighter
                context.fill(path, with: .color(.white.opacity(0.28 * band)))
                context.blendMode = .normal
            }
        }
    }

    // MARK: - Tile model

    private struct Tile {
        /// Chronological position (oldest = 0). Row/column are derived at draw time
        /// from the current column count, so the grid can reshape to the screen.
        let order: Int
        let startColor: Color
        let endColor: Color
        let unitPath: Path
        let phase: Double
    }

    /// Fils are ordered chronologically (oldest first) and laid out left-to-right,
    /// top-to-bottom, so the corner-to-corner swell sweeps through the user's history.
    private static func buildTiles(from notes: [Note]) -> [Tile] {
        let ordered = notes.sorted { $0.timestamp < $1.timestamp }
        guard !ordered.isEmpty else { return [] }
        let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)

        return ordered.enumerated().map { index, note in
            Tile(
                order: index,
                startColor: Color(hex: note.gradientStartHex),
                endColor: Color(hex: note.gradientEndHex),
                unitPath: NoteBlobShape(seed: note.blobShapeSeed).path(in: unitRect),
                phase: note.blobShapeSeed
            )
        }
    }

    // MARK: - Idle timer

    private func setIdleTimer(disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}
