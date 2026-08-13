import SwiftUI

/// A folder-summary fragment rendered as a little postage stamp: perforated edge, cream paper frame,
/// a soft folder-gradient wash panel, handwritten (Caveat) text, and a paper grain. Used by the home
/// hero to scatter the summary into pieces around the pinned folder.
struct StampSnippet: View {
    let text: String
    let start: String
    let end: String
    var seed: Double = 0.42
    var width: CGFloat = 210

    private static let paper = Color.white
    private let panelShape = RoundedRectangle(cornerRadius: 3, style: .continuous)

    private var wash: LinearGradient {
        let p = Theme.gradientUnitPoints(seed: seed)
        return LinearGradient(colors: [Color(hex: start), Color(hex: end)], startPoint: p.start, endPoint: p.end)
    }

    var body: some View {
        let deco = stampDeco(for: text)
        return ZStack {
            if let region = deco.smudge {
                TextSmudge(text: text, font: Theme.caveat(18, weight: .bold), region: region)
            }
            Text(text)
                .font(Theme.caveat(18, weight: .bold))
                .foregroundStyle(.black.opacity(0.86))
                .mask { inkMask }   // spotty pen-ink: sparse flecks of the letters drop out
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(11)
        .frame(width: width - 18)
        .background { ZStack { Self.paper; wash.opacity(0.20) } }
        .overlay { doodleLayer(deco.placed) }
        .overlay(panelShape.stroke(.black.opacity(0.10)))
        .clipShape(panelShape)
        .padding(9)
        .background(Self.paper)
        .overlay { grain }
        .modifier(PerforatedEdge())
        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 4)
    }

    /// The seeded placed doodles, each pinned to its corner/edge of the panel.
    private func doodleLayer(_ placed: [StampDoodleSpec]) -> some View {
        ZStack {
            ForEach(Array(placed.enumerated()), id: \.offset) { _, d in
                stampDoodleView(d.kind)
                    .scaleEffect(d.scale)
                    .rotationEffect(.degrees(d.rot))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: d.alignment)
                    .padding(6)
            }
        }
    }

    private var grain: some View {
        Image("PaperNoise")
            .resizable(resizingMode: .tile)
            .blendMode(.multiply)
            .opacity(0.15)
            .allowsHitTesting(false)
    }

    /// Mostly-opaque noise (brightened → luminance→alpha), so the ink shows almost fully with sparse
    /// transparent flecks — like pen ink not fully saturating the paper.
    private var inkMask: some View {
        Rectangle()
            .overlay { Image("PaperNoise").resizable(resizingMode: .tile).brightness(0.42) }
            .luminanceToAlpha()
    }
}

/// The summary stamps as a swipeable card deck — the top stamp reads fully, the next couple peek
/// behind it for depth. Swipe the top card aside to send it to the back and bring the next forward.
struct StampDeck: View {
    let parts: [String]
    let start: String
    let end: String
    var seed: Double = 0.42
    var cardWidth: CGFloat = 196

    @State private var order: [Int]
    @State private var drag: CGSize = .zero

    init(parts: [String], start: String, end: String, seed: Double = 0.42, cardWidth: CGFloat = 196) {
        self.parts = parts
        self.start = start
        self.end = end
        self.seed = seed
        self.cardWidth = cardWidth
        _order = State(initialValue: Array(parts.indices))
    }

    private let threshold: CGFloat = 64
    /// A resting angle per stamp (keyed by part index, so it stays with the card as the deck cycles).
    private let tilts: [Double] = [-4, 3, -2.5, 5]

    /// A render order guaranteed valid for the CURRENT `parts`: keep the live shuffle where it still
    /// points at real parts, then append any new indices. `order` is @State and survives a `parts`
    /// change (same view identity), so rendering it raw would index a stale/shorter array and crash —
    /// this is the fix for the "Index out of range" when a folder summary is overwritten.
    private var displayOrder: [Int] {
        let live = order.filter { parts.indices.contains($0) }
        let missing = parts.indices.filter { !live.contains($0) }
        return live + missing
    }

    var body: some View {
        ZStack {
            ForEach(Array(displayOrder.enumerated()), id: \.element) { depth, index in
                let front = depth == 0
                let d = min(depth, 2)
                StampSnippet(text: parts[index], start: start, end: end, seed: seed, width: cardWidth)
                    .scaleEffect(1 - CGFloat(d) * 0.05, anchor: .top)
                    .offset(y: CGFloat(d) * 8)
                    .offset(front ? drag : .zero)
                    .rotationEffect(.degrees(tilts[index % tilts.count] + (front ? Double(drag.width / 22) : 0)))
                    .zIndex(Double(displayOrder.count - depth))
                    .allowsHitTesting(front)
                    .gesture(front ? swipe : nil)
            }
        }
        // Resync the shuffle when the summary changes (parts replaced) so swipes stay correct.
        .onChange(of: parts) { _, newParts in
            order = Array(newParts.indices)
            drag = .zero
        }
    }

    private var swipe: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > threshold {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                        order.append(order.removeFirst())
                        drag = .zero
                    }
                    Haptics.navigate()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }
}

/// Punches evenly-spaced semicircle notches around all four edges — the postage-stamp perforation.
private struct PerforatedEdge: ViewModifier {
    var holeRadius: CGFloat = 4.5
    func body(content: Content) -> some View {
        content
            .overlay { GeometryReader { geo in perforations(geo.size).blendMode(.destinationOut) } }
            .compositingGroup()
    }

    private func perforations(_ size: CGSize) -> some View {
        let d = holeRadius * 2
        let countX = max(3, Int((size.width / (d * 1.25)).rounded()))
        let countY = max(3, Int((size.height / (d * 1.25)).rounded()))
        let stepX = size.width / CGFloat(countX)
        let stepY = size.height / CGFloat(countY)
        return ZStack {
            ForEach(0...countX, id: \.self) { i in
                Circle().frame(width: d, height: d).position(x: stepX * CGFloat(i), y: 0)
                Circle().frame(width: d, height: d).position(x: stepX * CGFloat(i), y: size.height)
            }
            ForEach(0...countY, id: \.self) { i in
                Circle().frame(width: d, height: d).position(x: 0, y: stepY * CGFloat(i))
                Circle().frame(width: d, height: d).position(x: size.width, y: stepY * CGFloat(i))
            }
        }
    }
}
