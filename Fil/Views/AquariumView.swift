import SwiftUI
import SpriteKit
import GameplayKit
#if canImport(UIKit)
import UIKit
#endif

/// A living side-view aquarium built on SpriteKit + GameplayKit. Pixel-art fish swim
/// left/right (flipping to face their heading) and hunt for food; the food is your fils —
/// blob-shaped gradient pellets that sink from where you tap. A reef of coral, anemone,
/// starfish, crabs and shells lines the floor, with a jellyfish and seahorse drifting.
struct AquariumView: View {
    var onExit: () -> Void
    @State private var scene: AquariumScene

    init(blobs: [FilScreensaverView.Blob], onExit: @escaping () -> Void) {
        self.onExit = onExit
        _scene = State(initialValue: AquariumScene(blobs: blobs))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            GeometryReader { geometry in
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .onAppear { scene.configure(size: geometry.size) }
                    .onChange(of: geometry.size) { _, newSize in scene.resize(to: newSize) }
            }
        }
        .ignoresSafeArea()
        // Tap feeds the fish, so exit is an explicit (subtle) control rather than a tap.
        .overlay(alignment: .topLeading) {
            Button(action: onExit) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(in: .circle)
            .padding(.top, 100)
            .padding(.leading, 16)
        }
    }
}

final class AquariumScene: SKScene {
    private let blobs: [FilScreensaverView.Blob]
    private var swimmers: [Swimmer] = []
    private var pellets: [Pellet] = []
    private var pelletTextures: [SKTexture] = []
    private var waterNode: SKSpriteNode?

    private var didConfigure = false
    private var lastUpdate: TimeInterval = 0
    private let edgeMargin: CGFloat = 24
    private var floorY: CGFloat { edgeMargin }

    private let fishCount = 6
    private let minFish = 5
    private let maxFish = 7
    private let ambientFood = 6

    /// The fish roster: sprite name plus whether the source art faces right (the
    /// left-facers are flipped to face right on load so swim logic stays uniform).
    private static let fishRoster: [(name: String, facesRight: Bool)] = [
        ("fish_9", true), ("fish_13", true), ("fish_75", true), ("fish_93", true),
        ("fish_104", true), ("fish_105", true), ("fish_107", true), ("fish_157", true),
        ("fish_52", false), ("fish_56", false), ("fish_58", false), ("fish_80", false),
        ("fish_100", false), ("fish_101", false), ("fish_102", false), ("fish_109", false)
    ]

    init(blobs: [FilScreensaverView.Blob]) {
        self.blobs = blobs
        super.init(size: CGSize(width: 400, height: 800))
        scaleMode = .resizeFill
        backgroundColor = .clear
        anchorPoint = .zero
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(size: CGSize) {
        guard !didConfigure, size.width > 0, size.height > 0 else { return }
        didConfigure = true
        self.size = size

        pelletTextures = blobs.map { Pellet.makeTexture(unitPath: $0.unitPath, start: UIColor($0.startColor), end: UIColor($0.endColor)) }

        addWater()
        addReef()
        spawnFish()
        for _ in 0..<ambientFood { dropPellet() }

        run(.repeatForever(.sequence([
            .wait(forDuration: 3.0),
            .run { [weak self] in self?.topUpFood() }
        ])), withKey: "topUp")
    }

    func resize(to newSize: CGSize) {
        guard newSize.width > 0, newSize.height > 0 else { return }
        size = newSize
        waterNode?.size = newSize
        waterNode?.position = CGPoint(x: newSize.width / 2, y: newSize.height / 2)
    }

    // MARK: - Scenery

    private func addWater() {
        let top = UIColor(red: 0.04, green: 0.16, blue: 0.20, alpha: 1)
        let bottom = UIColor(red: 0.02, green: 0.06, blue: 0.09, alpha: 1)
        let node = SKSpriteNode(texture: AquariumScene.verticalGradient(top: top, bottom: bottom))
        node.size = size
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        node.zPosition = -100
        addChild(node)
        waterNode = node
    }

    private func addReef() {
        let floorDecor = ["coral1", "coral2",
                          "coral_1", "coral_2", "coral_3", "coral_4", "coral_5",
                          "coral_6", "coral_7", "coral_8", "coral_9"]
        var x: CGFloat = CGFloat.random(in: 20...60)
        while x < size.width - 20 {
            let name = floorDecor.randomElement()!
            guard let texture = AquariumScene.loadTexture(name) else { x += 70; continue }
            let targetHeight = size.height * CGFloat.random(in: 0.08...0.14)
            let node = SKSpriteNode(texture: texture)
            node.size = AquariumScene.size(for: texture, targetHeight: targetHeight)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.position = CGPoint(x: x, y: floorY)
            node.zPosition = -10
            node.alpha = 0.95
            addChild(node)

            // Coral and anemone sway gently.
            if name.hasPrefix("coral") || name == "anemone" {
                let sway = SKAction.sequence([
                    .rotate(toAngle: 0.05, duration: Double.random(in: 2.4...3.4)),
                    .rotate(toAngle: -0.05, duration: Double.random(in: 2.4...3.4))
                ])
                sway.timingMode = .easeInEaseOut
                node.run(.repeatForever(sway))
            }
            x += node.size.width * CGFloat.random(in: 0.7...1.1) + 12
        }
    }

    // MARK: - Fish

    private func spawnFish() {
        for _ in 0..<fishCount {
            _ = makeSwimmer(at: randomPoint(), state: .normal)
        }
        rebuildBehaviors()
        scheduleRotation()
    }

    @discardableResult
    private func makeSwimmer(at point: CGPoint, state: Swimmer.State) -> Swimmer? {
        let kind = AquariumScene.fishRoster.randomElement()!
        guard let texture = AquariumScene.loadFishTexture(kind.name, facesRight: kind.facesRight) else { return nil }
        let depth = CGFloat.random(in: 0.82...1.1)
        let targetHeight = size.height * 0.09 * depth
        let swimmer = Swimmer(texture: texture, size: AquariumScene.size(for: texture, targetHeight: targetHeight))
        swimmer.state = state
        swimmer.node.alpha = 0.75 + 0.25 * depth
        swimmer.node.zPosition = depth * 10
        swimmer.node.position = point
        swimmer.lastX = point.x
        swimmer.lastY = point.y
        swimmer.agent.position = vector_float2(Float(point.x), Float(point.y))
        swimmer.agent.rotation = point.x < size.width / 2 ? 0 : .pi
        swimmer.agent.radius = Float(swimmer.node.size.height * 0.5)
        swimmer.agent.mass = 0.3
        swimmer.agent.maxSpeed = Float(size.width * 0.10 * depth)
        swimmer.agent.maxAcceleration = Float(size.width * 0.18)
        addChild(swimmer.node)
        swimmers.append(swimmer)
        return swimmer
    }

    /// (Re)installs steering goals for every fish against the current cast. Entering and
    /// leaving fish steer hard toward their destination and barely wander.
    private func rebuildBehaviors() {
        let agents = swimmers.map(\.agent)
        for swimmer in swimmers {
            let others = agents.filter { $0 !== swimmer.agent }
            let len = Float(swimmer.node.size.width)
            let wander = GKGoal(toWander: swimmer.agent.maxSpeed)
            let separate = GKGoal(toSeparateFrom: others, maxDistance: len * 1.6, maxAngle: .pi * 2)
            let cruise = GKGoal(toReachTargetSpeed: swimmer.agent.maxSpeed * 0.55)
            let seek = GKGoal(toSeekAgent: swimmer.foodTarget)
            swimmer.seekGoal = seek

            let transiting = swimmer.state != .normal
            let behavior = GKBehavior()
            behavior.setWeight(transiting ? 0.2 : 1.0, for: wander)
            behavior.setWeight(1.8, for: separate)
            behavior.setWeight(0.5, for: cruise)
            behavior.setWeight(transiting ? 5.0 : 0.0, for: seek)
            swimmer.agent.behavior = behavior
        }
    }

    // MARK: - Cast rotation (fish swim out, newcomers swim in)

    private func scheduleRotation() {
        let wait = SKAction.wait(forDuration: Double.random(in: 12...22))
        run(.sequence([wait, .run { [weak self] in
            self?.rotationTick()
            self?.scheduleRotation()
        }]), withKey: "rotate")
    }

    /// Let the population breathe between minFish and maxFish: sometimes a fish leaves,
    /// sometimes a newcomer arrives, sometimes both (a swap).
    private func rotationTick() {
        let population = swimmers.count
        if population <= minFish {
            spawnNewcomer()
        } else if population >= maxFish {
            sendOneFishAway()
        } else {
            switch Int.random(in: 0..<3) {
            case 0: sendOneFishAway()
            case 1: spawnNewcomer()
            default: sendOneFishAway(); spawnNewcomer()
            }
        }
    }

    private func sendOneFishAway() {
        guard let leaver = swimmers.filter({ $0.state == .normal }).randomElement() else { return }
        leaver.state = .leaving
        let exitRight = leaver.node.position.x > size.width / 2
        let exitX = exitRight ? size.width + 140 : -140
        let exitY = min(max(leaver.node.position.y, size.height * 0.4), size.height * 0.78)
        leaver.foodTarget.position = vector_float2(Float(exitX), Float(exitY))
        leaver.agent.maxSpeed *= 1.5
        rebuildBehaviors()
    }

    private func spawnNewcomer() {
        let fromRight = Bool.random()
        let y = CGFloat.random(in: (size.height * 0.4)...(size.height * 0.78))
        let startX = fromRight ? size.width + 120 : -120
        guard let newcomer = makeSwimmer(at: CGPoint(x: startX, y: y), state: .entering) else { return }
        let insideX = fromRight
            ? CGFloat.random(in: (size.width * 0.55)...(size.width * 0.8))
            : CGFloat.random(in: (size.width * 0.2)...(size.width * 0.45))
        newcomer.foodTarget.position = vector_float2(Float(insideX), Float(y))
        rebuildBehaviors()
    }

    private func isInsideBounds(_ p: CGPoint) -> Bool {
        p.x > edgeMargin && p.x < size.width - edgeMargin &&
        p.y > floorY + 10 && p.y < size.height - edgeMargin
    }

    // MARK: - Food (fils)

    private func dropPellet(at point: CGPoint? = nil) {
        guard !pelletTextures.isEmpty else { return }
        let spawn = point ?? CGPoint(
            x: CGFloat.random(in: edgeMargin...(size.width - edgeMargin)),
            y: size.height - edgeMargin
        )
        let pellet = Pellet(texture: pelletTextures.randomElement()!)
        pellet.node.position = spawn
        addChild(pellet.node)
        pellets.append(pellet)
    }

    private func topUpFood() {
        guard pellets.count < ambientFood else { return }
        dropPellet()
    }

    private func consume(_ pellet: Pellet) {
        guard !pellet.eaten else { return }
        pellet.eaten = true
        pellets.removeAll { $0 === pellet }

        let ripple = SKShapeNode(circleOfRadius: 5)
        ripple.position = pellet.node.position
        ripple.strokeColor = .white.withAlphaComponent(0.3)
        ripple.lineWidth = 1.5
        ripple.zPosition = 20
        addChild(ripple)
        ripple.run(.sequence([
            .group([.scale(to: 3, duration: 0.5), .fadeOut(withDuration: 0.5)]),
            .removeFromParent()
        ]))
        pellet.node.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        guard didConfigure else { return }
        let dt = lastUpdate == 0 ? 0 : currentTime - lastUpdate
        lastUpdate = currentTime
        guard dt > 0, dt < 0.5 else { return }

        // Sink the food; remove any that reaches the floor.
        for pellet in pellets {
            pellet.advance(dt: dt, time: currentTime)
            if pellet.node.position.y <= floorY {
                pellet.eaten = true
                pellet.node.run(.sequence([.fadeOut(withDuration: 0.4), .removeFromParent()]))
            }
        }
        pellets.removeAll { $0.eaten }

        let sightRange = min(size.width, size.height) * 0.5
        var departed: [Swimmer] = []

        for swimmer in swimmers {
            switch swimmer.state {
            case .normal:
                let here = swimmer.node.position
                if let nearest = nearestPellet(to: here, within: sightRange) {
                    swimmer.foodTarget.position = vector_float2(Float(nearest.node.position.x), Float(nearest.node.position.y))
                    if let seek = swimmer.seekGoal { swimmer.agent.behavior?.setWeight(4.5, for: seek) }
                    if here.distance(to: nearest.node.position) < swimmer.node.size.height * 0.7 {
                        consume(nearest)
                    }
                } else if let seek = swimmer.seekGoal {
                    swimmer.agent.behavior?.setWeight(0, for: seek)
                }
                swimmer.agent.update(deltaTime: dt)
                reflectAtEdges(swimmer)

            case .entering:
                swimmer.agent.update(deltaTime: dt)
                if isInsideBounds(swimmer.node.position) {
                    swimmer.state = .normal
                    rebuildBehaviors()
                }

            case .leaving:
                swimmer.agent.update(deltaTime: dt)
                let x = swimmer.node.position.x
                if x < -110 || x > size.width + 110 {
                    departed.append(swimmer)
                }
            }

            let p = swimmer.agent.position
            swimmer.node.position = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
            // Face by actual movement this frame (the agent's steering velocity can lag,
            // which made fish appear to swim backwards).
            let dx = swimmer.node.position.x - swimmer.lastX
            let dy = swimmer.node.position.y - swimmer.lastY
            swimmer.lastX = swimmer.node.position.x
            swimmer.lastY = swimmer.node.position.y
            swimmer.updateFacing(dx: dx, dy: dy)
        }

        // Retire fish that swam off-screen; the rotation tick manages replacements so the
        // population can breathe between minFish and maxFish.
        if !departed.isEmpty {
            for swimmer in departed {
                swimmer.node.removeFromParent()
                swimmers.removeAll { $0 === swimmer }
            }
            rebuildBehaviors()
        }
    }

    private func nearestPellet(to point: CGPoint, within range: CGFloat) -> Pellet? {
        var best: Pellet?
        var bestDist = range
        for pellet in pellets where !pellet.eaten {
            let d = point.distance(to: pellet.node.position)
            if d < bestDist { bestDist = d; best = pellet }
        }
        return best
    }

    private func reflectAtEdges(_ swimmer: Swimmer) {
        var p = swimmer.agent.position
        var heading = swimmer.agent.rotation
        let minX = Float(edgeMargin), maxX = Float(size.width - edgeMargin)
        let minY = Float(floorY + 10), maxY = Float(size.height - edgeMargin)
        if p.x < minX { p.x = minX; heading = .pi - heading }
        else if p.x > maxX { p.x = maxX; heading = .pi - heading }
        if p.y < minY { p.y = minY; heading = -heading }
        else if p.y > maxY { p.y = maxY; heading = -heading }
        swimmer.agent.position = p
        swimmer.agent.rotation = heading
    }

    private func randomPoint() -> CGPoint {
        CGPoint(
            x: CGFloat.random(in: edgeMargin...(size.width - edgeMargin)),
            y: CGFloat.random(in: (size.height * 0.35)...(size.height - edgeMargin))
        )
    }

    // MARK: - Feeding

    #if canImport(UIKit)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let p = touch.location(in: self)
        for _ in 0..<4 {
            dropPellet(at: CGPoint(
                x: min(max(p.x + CGFloat.random(in: -24...24), edgeMargin), size.width - edgeMargin),
                y: min(max(p.y + CGFloat.random(in: -10...20), floorY), size.height - edgeMargin)
            ))
        }
    }
    #endif

    // MARK: - Texture helpers

    #if canImport(UIKit)
    static func loadUIImage(_ name: String) -> UIImage? {
        if let image = UIImage(named: name) { return image }
        for sub in [nil, "Aquarium", "Resources/Aquarium"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: sub),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        return nil
    }
    #endif

    static func loadTexture(_ name: String) -> SKTexture? {
        #if canImport(UIKit)
        guard let image = loadUIImage(name) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest    // crisp pixel art
        return texture
        #else
        return nil
        #endif
    }

    /// Loads a fish sprite normalized to face right (left-facing art is mirrored), with
    /// smooth (linear) filtering since these are realistic illustrations, not pixel art.
    static func loadFishTexture(_ name: String, facesRight: Bool) -> SKTexture? {
        #if canImport(UIKit)
        var image = UIImage(named: name)
        if image == nil {
            for sub in [nil, "Aquarium", "Resources/Aquarium"] {
                if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: sub) {
                    image = UIImage(contentsOfFile: url.path)
                    if image != nil { break }
                }
            }
        }
        guard var image else { return nil }

        if !facesRight {
            let renderer = UIGraphicsImageRenderer(size: image.size)
            image = renderer.image { ctx in
                ctx.cgContext.translateBy(x: image.size.width, y: 0)
                ctx.cgContext.scaleBy(x: -1, y: 1)
                image.draw(at: .zero)
            }
        }

        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
        #else
        return nil
        #endif
    }

    static func size(for texture: SKTexture, targetHeight: CGFloat) -> CGSize {
        let s = texture.size()
        let aspect = s.height > 0 ? s.width / s.height : 1
        return CGSize(width: targetHeight * aspect, height: targetHeight)
    }

    private static func verticalGradient(top: UIColor, bottom: UIColor) -> SKTexture {
        let size = CGSize(width: 4, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
        }
        return SKTexture(image: image)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(other.x - x, other.y - y) }
}

// MARK: - Swimmer

/// A sprite fish driven by a GameplayKit agent. Base art faces right; it flips to face
/// its travel direction and tilts slightly with vertical motion.
private final class Swimmer {
    enum State { case normal, entering, leaving }

    let node: SKSpriteNode
    let agent = GKAgent2D()
    let foodTarget = GKAgent2D()
    var seekGoal: GKGoal?
    var state: State = .normal
    var lastX: CGFloat = 0
    var lastY: CGFloat = 0

    init(texture: SKTexture, size: CGSize) {
        node = SKSpriteNode(texture: texture)
        node.size = size
    }

    /// Face the direction of travel (base art faces right) with a slight tilt for climbs/dives.
    func updateFacing(dx: CGFloat, dy: CGFloat) {
        guard abs(dx) > 0.05 else { return }
        node.xScale = dx < 0 ? -1 : 1
        let slope = dy / max(abs(dx), 0.001)
        let tilt = max(-0.35, min(0.35, atan(Double(slope)) * 0.5))
        node.zRotation = CGFloat(dx < 0 ? -tilt : tilt)
    }
}

// MARK: - Food pellet (a fil)

private final class Pellet {
    let node: SKSpriteNode
    var eaten = false
    private let sinkSpeed: CGFloat
    private let wobbleAmp: CGFloat
    private let wobbleFreq: CGFloat
    private let phase: CGFloat
    private let spin: CGFloat

    init(texture: SKTexture) {
        let side = CGFloat.random(in: 16...22)
        node = SKSpriteNode(texture: texture, size: CGSize(width: side, height: side))
        node.zPosition = 5
        sinkSpeed = CGFloat.random(in: 16...30)
        wobbleAmp = CGFloat.random(in: 10...22)
        wobbleFreq = CGFloat.random(in: 1.2...2.2)
        phase = CGFloat.random(in: 0...(2 * .pi))
        spin = CGFloat.random(in: -0.5...0.5)
    }

    func advance(dt: TimeInterval, time: TimeInterval) {
        node.position.y -= sinkSpeed * CGFloat(dt)
        node.position.x += sin(CGFloat(time) * wobbleFreq + phase) * wobbleAmp * CGFloat(dt)
        node.zRotation += spin * CGFloat(dt)
    }

    /// The fil's own blob shape, filled with its gradient.
    static func makeTexture(unitPath: Path, start: UIColor, end: UIColor) -> SKTexture {
        let side: CGFloat = 56
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let scaled = unitPath.applying(CGAffineTransform(scaleX: side, y: side))
            cg.saveGState()
            cg.addPath(scaled.cgPath)
            cg.clip()
            let colors = [start.cgColor, end.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
            cg.restoreGState()
        }
        return SKTexture(image: image)
    }
}
