import SwiftUI

// Hand-drawn doodle accents for the summary stamps: underline, arrow, a finger-smudge blob, and the
// text-smudge variants (whole / start / end). Placement + set are seeded per stamp so they're stable
// but varied, and often absent so the stamps stay sparse.

let stampInk = Color.black.opacity(0.72)

enum StampDoodleKind: CaseIterable { case smudge, textSmudge, textSmudgeStart, textSmudgeEnd }
enum SmudgeRegion { case full, start, end }

func smudgeRegion(_ k: StampDoodleKind) -> SmudgeRegion? {
    switch k {
    case .textSmudge:      return .full
    case .textSmudgeStart: return .start
    case .textSmudgeEnd:   return .end
    default:               return nil
    }
}

/// Deterministic pseudo-random in -1...1 (stable per index → no per-frame flicker).
func stampJit(_ i: Int) -> CGFloat {
    let x = sin(Double(i) * 127.1 + 311.7) * 43758.5453
    return CGFloat((x - x.rounded(.down)) * 2 - 1)
}

/// A small deterministic RNG so a stamp's doodle set/placement is stable per seed.
struct SeededRNG {
    var state: UInt64
    init(_ seed: Int) { state = UInt64(bitPattern: Int64(seed)) &* 2654435761 &+ 1 }
    mutating func unit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
    mutating func int(_ n: Int) -> Int { n <= 0 ? 0 : Int(unit() * Double(n)) % n }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + unit() * (b - a) }
}

/// Stable FNV-1a hash of a string (unlike Swift's per-launch-randomized hashValue).
func stableHash(_ s: String) -> Int {
    var h: UInt64 = 1469598103934665603
    for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
    return Int(bitPattern: UInt(truncatingIfNeeded: h))
}

// MARK: - Shapes

private struct SmudgeDoodle: View {
    var body: some View {
        ZStack {
            Ellipse().fill(stampInk.opacity(0.34)).frame(width: 26, height: 11).blur(radius: 2.5)
            Ellipse().fill(stampInk.opacity(0.26)).frame(width: 20, height: 8).offset(x: 7, y: 2).blur(radius: 3.5)
            Ellipse().fill(stampInk.opacity(0.18)).frame(width: 12, height: 6).offset(x: 12, y: 3).blur(radius: 3)
        }
        .frame(width: 30, height: 16)
        .rotationEffect(.degrees(-12))
        .mask(LinearGradient(colors: [.black, .black, .black.opacity(0.15)], startPoint: .leading, endPoint: .trailing))
    }
}

@ViewBuilder func stampDoodleView(_ k: StampDoodleKind) -> some View {
    switch k {
    case .smudge: SmudgeDoodle()
    default:      EmptyView()   // text-smudge variants are drawn behind the text
    }
}

/// The text itself dragged near-horizontally: progressively-offset, blurrier, fainter copies of the
/// words. `region` limits it to the whole phrase, its start (drags right), or its end (drags left).
struct TextSmudge: View {
    let text: String
    var font: Font = Theme.caveat(18, weight: .bold)
    var region: SmudgeRegion = .full

    var body: some View {
        let dir: CGFloat = region == .end ? -1 : 1
        ZStack {
            ForEach(1...4, id: \.self) { k in
                Text(text)
                    .font(font)
                    .foregroundStyle(stampInk)
                    .blur(radius: CGFloat(k) * 1.6)
                    .opacity(0.34 * Double(5 - k) / 4.0)
                    .offset(x: CGFloat(k) * 5.0 * dir, y: CGFloat(k) * 0.7)
            }
        }
        .mask(regionMask)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var regionMask: some View {
        switch region {
        case .full:  Color.black
        case .start: LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.34), .init(color: .clear, location: 0.64)],
                                    startPoint: .leading, endPoint: .trailing)
        case .end:   LinearGradient(stops: [.init(color: .clear, location: 0.36), .init(color: .black, location: 0.66), .init(color: .black, location: 1)],
                                    startPoint: .leading, endPoint: .trailing)
        }
    }
}

// MARK: - Per-stamp decoration

struct StampDoodleSpec { let kind: StampDoodleKind; let alignment: Alignment; let rot: Double; let scale: CGFloat }
struct StampDeco { let smudge: SmudgeRegion?; let placed: [StampDoodleSpec] }

/// The (deterministic) doodle set for a stamp: 0–2 doodles, often none, at most one text-smudge.
func stampDeco(for text: String) -> StampDeco {
    var rng = SeededRNG(stableHash(text))
    let roll = rng.unit()
    let count = roll < 0.34 ? 0 : (roll < 0.80 ? 1 : 2)   // often none, so it stays sparse

    var corners: [Alignment] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
    for i in stride(from: corners.count - 1, to: 0, by: -1) { corners.swapAt(i, rng.int(i + 1)) }

    var smudge: SmudgeRegion?
    var placed: [StampDoodleSpec] = []
    let pool = StampDoodleKind.allCases
    for _ in 0..<count {
        let kind = pool[rng.int(pool.count)]
        if let r = smudgeRegion(kind) {
            if smudge == nil { smudge = r }
            continue
        }
        let al = corners[placed.count % corners.count]
        placed.append(StampDoodleSpec(kind: kind, alignment: al, rot: rng.range(-14, 14), scale: CGFloat(rng.range(0.85, 1.15))))
    }
    return StampDeco(smudge: smudge, placed: placed)
}
