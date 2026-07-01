import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A full-screen "screensaver" built from every fil. It hosts multiple visual
/// *modes* over one shared set of fil blobs: a right-to-left wave field, and a
/// liquid metaball goo. Tap anywhere to exit; swipe horizontally to switch modes.
/// All other UI disappears and the idle timer is held off while it's open.
struct FilScreensaverView: View {
    var onExit: () -> Void

    private let blobs: [Blob]
    @State private var mode: Mode = .wave

    init(notes: [Note], initialMode: Mode = .wave, onExit: @escaping () -> Void) {
        self.onExit = onExit
        self.blobs = Self.buildBlobs(from: notes)
        self._mode = State(initialValue: initialMode)
    }

    enum Mode: CaseIterable {
        case wave
        case liquid

        var next: Mode {
            let all = Mode.allCases
            let index = all.firstIndex(of: self) ?? 0
            return all[(index + 1) % all.count]
        }
    }

    var body: some View {
        ZStack {
            switch mode {
            case .wave:
                WaveScreensaverLayer(blobs: blobs)
                    .transition(.opacity)
            case .liquid:
                LiquidScreensaverLayer(blobs: blobs)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { onExit() }
        .gesture(
            // Horizontal swipe cycles to the next mode.
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 60 else { return }
                    withAnimation(.easeInOut(duration: 0.5)) {
                        mode = mode.next
                    }
                }
        )
        .onAppear { setIdleTimer(disabled: true) }
        .onDisappear { setIdleTimer(disabled: false) }
    }

    // MARK: - Shared blob model

    /// Immutable per-fil visual data shared by every mode. Blob paths are generated
    /// once (they're static per fil). Built in `init` — not `onAppear` — so the very
    /// first render closure captures them (SwiftUI can't diff the closure to pick up
    /// a later `@State` change).
    struct Blob {
        /// Chronological position (oldest = 0).
        let order: Int
        let startColor: Color
        let endColor: Color
        /// The fil's blob outline in a unit (0...1) rect.
        let unitPath: Path
        /// Blend of the fil's gradient, used as its single color in liquid mode.
        let midColor: Color
        let phase: Double
    }

    /// Fils ordered chronologically (oldest first), laid out left-to-right, top-to-bottom.
    private static func buildBlobs(from notes: [Note]) -> [Blob] {
        let ordered = notes.sorted { $0.timestamp < $1.timestamp }
        guard !ordered.isEmpty else { return [] }
        let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)

        return ordered.enumerated().map { index, note in
            let start = Color(hex: note.gradientStartHex)
            let end = Color(hex: note.gradientEndHex)
            return Blob(
                order: index,
                startColor: start,
                endColor: end,
                unitPath: NoteBlobShape(seed: note.blobShapeSeed).path(in: unitRect),
                midColor: start.mix(with: end, by: 0.5),
                phase: note.blobShapeSeed
            )
        }
    }

    private func setIdleTimer(disabled: Bool) {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #endif
    }
}

// MARK: - Wave mode

/// A tight lattice of tiny blobs (sized like the home page's collapsed dots) with a
/// single tilted swell sweeping right-to-left, and a faint resting breath.
private struct WaveScreensaverLayer: View {
    let blobs: [FilScreensaverView.Blob]

    private let blobDiameter: CGFloat = 24
    private let blobSpacing: CGFloat = 10

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(&context, size: size, time: time)
            }
        }
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, time: Double) {
        guard !blobs.isEmpty else { return }

        let count = blobs.count
        let cell = blobDiameter + blobSpacing
        let columns = max(1, Int(size.width / cell))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let gridWidth = cell * CGFloat(columns)
        let gridHeight = cell * CGFloat(rows)
        let originX = (size.width - gridWidth) / 2
        let originY = max(cell / 2, (size.height - gridHeight) / 2)

        let lastRowCount = count - (rows - 1) * columns
        let lastRowIndent = CGFloat(columns - lastRowCount) / 2

        // A single swell entering from the right, leaning "\" as it sweeps left.
        let tilt = 0.35
        let reach = Double(columns - 1) + tilt * Double(rows - 1)
        let lead = 3.0
        let sweepSeconds = 7.0
        let cycle = (time / sweepSeconds).truncatingRemainder(dividingBy: 1)
        let waveHead = cycle * (reach + 2 * lead) - lead
        let sigma = 1.7

        for blob in blobs {
            let column = blob.order % columns
            let row = blob.order / columns
            let distance = Double(columns - 1 - column) + tilt * Double(row) - waveHead
            let band = exp(-(distance * distance) / (2 * sigma * sigma))
            let breath = 0.5 + 0.5 * sin(time * 0.7 + blob.phase * .pi * 2)
            let scale = 0.9 + 0.16 * band + 0.04 * breath

            let indent = row == rows - 1 ? lastRowIndent : 0
            let centerX = originX + (CGFloat(column) + indent + 0.5) * cell
            let centerY = originY + (CGFloat(row) + 0.5) * cell
            let blobSize = blobDiameter * scale
            let minX = centerX - blobSize / 2
            let minY = centerY - blobSize / 2

            let transform = CGAffineTransform(scaleX: blobSize, y: blobSize)
                .concatenating(CGAffineTransform(translationX: minX, y: minY))
            let path = blob.unitPath.applying(transform)

            context.fill(
                path,
                with: .linearGradient(
                    Gradient(colors: [blob.startColor, blob.endColor]),
                    startPoint: CGPoint(x: minX, y: minY),
                    endPoint: CGPoint(x: minX + blobSize, y: minY + blobSize)
                )
            )

            if band > 0.02 {
                context.blendMode = .plusLighter
                context.fill(path, with: .color(.white.opacity(0.28 * band)))
                context.blendMode = .normal
            }
        }
    }
}

// MARK: - Liquid mode

/// Every fil becomes a slowly drifting metaball. Where blobs overlap they merge into
/// flowing goo (a Metal metaball shader), and their gradient colors blend at the seams.
private struct LiquidScreensaverLayer: View {
    let blobs: [FilScreensaverView.Blob]

    /// Blob influence radius as a fraction of screen width. With the compact kernel a
    /// fil's visible droplet is ~0.42x this; larger = fatter droplets that merge sooner.
    private let radiusFactor: CGFloat = 0.16
    /// Field isovalue for the goo surface (a single fil peaks at 1.0).
    private let threshold: Float = 0.55
    /// Edge width in pixels (screen-space antialiased). ~1 = razor-sharp vector-like
    /// outline; raise for a softer goo edge.
    private let edge: Float = 1.0

    private var colors: [Color] { blobs.map(\.midColor) }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Rectangle()
                    .fill(.black)
                    .colorEffect(
                        ShaderLibrary.filMetaball(
                            .floatArray(centers(size: size, time: time)),
                            .colorArray(colors),
                            .float(Float(size.width * radiusFactor)),
                            .float(threshold),
                            .float(edge)
                        )
                    )
            }
        }
    }

    /// Flat [x0, y0, x1, y1, ...] centers in points. Each blob has a stable base
    /// position (hashed from its order) and drifts on a slow independent orbit.
    private func centers(size: CGSize, time: Double) -> [Float] {
        var out: [Float] = []
        out.reserveCapacity(blobs.count * 2)
        let margin = 0.14
        for blob in blobs {
            let o = Double(blob.order)
            let hx = fract(sin(o * 12.9898 + 1.3) * 43758.5453)
            let hy = fract(sin(o * 78.2330 + 2.7) * 24634.6345)
            let hp = fract(sin(o * 39.4250 + 0.7) * 19349.1940)
            let baseX = (margin + (1 - 2 * margin) * hx) * Double(size.width)
            let baseY = (margin + (1 - 2 * margin) * hy) * Double(size.height)
            let ampX = Double(size.width) * 0.16
            let ampY = Double(size.height) * 0.16
            let speedX = 0.08 + hx * 0.06
            let speedY = 0.07 + hy * 0.06
            let x = baseX + ampX * sin(time * speedX + hp * 6.2831853)
            let y = baseY + ampY * cos(time * speedY + hp * 6.2831853)
            out.append(Float(x))
            out.append(Float(y))
        }
        return out
    }

    private func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}
