import EsperSim
import SpriteKit

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
}

/// Runs the match at a fixed 60 steps a second and draws the last state. Nothing in here
/// writes back into the match except the inputs it hands to `advance`.
final class GameScene: SKScene {
    private static let stepSeconds = 1.0 / 60
    private static let maxStepsPerFrame = 4
    private static let pixelsPerTile = CGFloat(Stage.tileSize * SpriteLibrary.pixelsPerUnit)

    private var match = Match()
    private var airVariant = AirVariant.a
    private let sprites = SpriteLibrary()
    private let hub = InputHub()
    private let cameraNode = SKCameraNode()
    private let world = SKNode()
    /// Sits at the camera's position, scaled to cancel the camera, so its children are laid
    /// out in screen points from the centre and a touch maps onto them with no arithmetic.
    private let hud = SKNode()
    private var controls: TouchControls?
    private var playerNodes: [SKSpriteNode] = []
    /// The glow on the ball in each player's hands, and the fire off each head.
    private var handHalos: [SKSpriteNode] = []
    private var headFires: [SKEmitterNode] = []
    private var ballNode = SKSpriteNode()
    private var pointerNode = SKSpriteNode()
    private var rimNodes: [SKSpriteNode] = []
    private var rimFlash: [Int] = []
    private var previewNodes: [SKShapeNode] = []
    private let scoreLabel = SKLabelNode()
    private let debugLabel = SKLabelNode()
    private var lastTime: TimeInterval?
    private var accumulator = 0.0
    private var built = false

    override init() {
        super.init(size: CGSize(width: 640, height: 288))
        scaleMode = .fill
        backgroundColor = SKColor(red: 0.18, green: 0.12, blue: 0.24, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The Metal view calls this with its size in points whenever that changes.
    func attach(size: CGSize, displayScale: CGFloat) {
        self.size = size
        hub.activate()
        if !built {
            build()
            built = true
        }
        layout(displayScale: displayScale)
    }

    // MARK: Building

    private func build() {
        addChild(world)
        camera = cameraNode
        addChild(cameraNode)
        hud.zPosition = 100
        addChild(hud)
        applyTuning()

        let stage = match.stage
        for row in 0..<stage.rows {
            for column in 0..<stage.columns {
                let tile = stage.tile(column: column, row: row)
                guard tile != .empty else { continue }
                let node = SKSpriteNode(texture: sprites.texture(tile == .solid ? "solid" : "solid_oneway", 0))
                node.anchorPoint = .zero
                node.position = CGPoint(x: CGFloat(column) * GameScene.pixelsPerTile, y: CGFloat(row) * GameScene.pixelsPerTile)
                world.addChild(node)
            }
        }

        for hoop in stage.hoops {
            let rim = SKSpriteNode(texture: sprites.texture("hoop_rim", 0))
            rim.position = SpriteLibrary.point(hoop.position)
            rim.zPosition = 5
            // The sheet draws the rim with its backboard on the right.
            rim.xScale = hoop.backboard == .left ? -1 : 1
            world.addChild(rim)
            rimNodes.append(rim)
            rimFlash.append(0)
            world.addChild(net(at: rim.position))
        }

        for player in match.players {
            let node = SKSpriteNode(texture: sprites.texture(player.animationFrame, player: player.index))
            node.zPosition = 20
            world.addChild(node)
            playerNodes.append(node)
            let colour = SKColor(rgb: sprites.look(for: player.index).glow)
            let halo = makeHalo(colour)
            halo.zPosition = 19
            world.addChild(halo)
            handHalos.append(halo)
            let fire = makeFire(colour)
            fire.zPosition = 18
            world.addChild(fire)
            headFires.append(fire)
        }

        ballNode = SKSpriteNode(texture: sprites.texture("ball", 0))
        ballNode.zPosition = 25
        world.addChild(ballNode)
        let halo = makeHalo(SKColor(rgb: BallLook.colour))
        halo.zPosition = -1
        ballNode.addChild(halo)
        pointerNode = SKSpriteNode(texture: sprites.symbol("chevron.down", pointSize: 14))
        pointerNode.zPosition = 25
        world.addChild(pointerNode)

        scoreLabel.fontName = "Menlo-Bold"
        scoreLabel.fontSize = 16
        scoreLabel.fontColor = .white
        scoreLabel.verticalAlignmentMode = .top
        hud.addChild(scoreLabel)

        debugLabel.fontName = "Menlo"
        debugLabel.fontSize = 8
        debugLabel.fontColor = SKColor(white: 1, alpha: 0.6)
        debugLabel.horizontalAlignmentMode = .left
        debugLabel.verticalAlignmentMode = .top
        debugLabel.numberOfLines = 0
        hud.addChild(debugLabel)

    }

    /// A soft glow in the colour, added, which the glow pass then picks up.
    private func makeHalo(_ colour: SKColor) -> SKSpriteNode {
        let halo = SKSpriteNode(texture: sprites.softGlow(diameter: 32, colour: colour))
        halo.size = CGSize(width: 18, height: 18)
        halo.alpha = 0.5
        halo.blendMode = .add
        return halo
    }

    /// Sparks rising off a head as if it were burning, in the colour.
    private func makeFire(_ colour: SKColor) -> SKEmitterNode {
        let fire = SKEmitterNode()
        fire.particleTexture = sprites.softGlow(diameter: 8, colour: .white)
        fire.particleBirthRate = 24
        fire.particleLifetime = 0.45
        fire.particleLifetimeRange = 0.2
        fire.particlePositionRange = CGVector(dx: 6, dy: 2)
        fire.particleSpeed = 24
        fire.particleSpeedRange = 10
        fire.emissionAngle = .pi / 2
        fire.emissionAngleRange = .pi / 5
        fire.yAcceleration = 30
        fire.particleSize = CGSize(width: 4, height: 4)
        fire.particleScaleSpeed = -1.5
        fire.particleAlpha = 0.9
        fire.particleAlphaSpeed = -1.6
        fire.particleColor = colour
        fire.particleColorBlendFactor = 1
        fire.particleBlendMode = .add
        return fire
    }

    /// The rim's net, as GMS2 built it: six columns, five rows, tapering to half width.
    private func net(at rim: CGPoint) -> SKShapeNode {
        let columns = 6, rows = 5
        let width = 18.0, height = 14.0
        var points: [[CGPoint]] = []
        for column in 0..<columns {
            var line: [CGPoint] = []
            for row in 0..<rows {
                var x = -width / 2 + Double(column) / Double(columns - 1) * width
                if row % 2 == 1 { x += width / Double(columns * 2) }
                let taper = Double(row) / Double(rows - 1) * 0.5
                x += (0 - x) * taper
                line.append(CGPoint(x: rim.x + x, y: rim.y - Double(row) / Double(rows - 1) * height))
            }
            points.append(line)
        }
        let path = CGMutablePath()
        for column in 0..<columns {
            path.addLines(between: points[column])
        }
        for row in 0..<rows {
            path.addLines(between: (0..<columns).map { points[$0][row] })
        }
        let node = SKShapeNode(path: path)
        node.strokeColor = SKColor(white: 1, alpha: 0.6)
        node.lineWidth = 1
        node.zPosition = 4
        return node
    }

    /// One game pixel is a whole number of screen pixels, as many as fit the whole court.
    private func layout(displayScale screenScale: CGFloat) {
        let stageWidth = CGFloat(match.stage.columns) * GameScene.pixelsPerTile
        let stageHeight = CGFloat(match.stage.rows) * GameScene.pixelsPerTile
        let fitHeight = (screenScale * size.height / stageHeight).rounded(.down)
        let fitWidth = (screenScale * size.width / stageWidth).rounded(.down)
        let screenPixelsPerGamePixel = max(1, min(fitHeight, fitWidth))
        let pointsPerGamePixel = screenPixelsPerGamePixel / screenScale
        cameraNode.setScale(1 / pointsPerGamePixel)
        cameraNode.position = CGPoint(x: stageWidth / 2, y: stageHeight / 2)
        hud.position = cameraNode.position
        hud.setScale(cameraNode.xScale)

        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        controls?.removeFromParent()
        let controls = TouchControls(halfWidth: halfWidth, halfHeight: halfHeight)
        controls.onReset = { [weak self] in self?.reset() }
        controls.addPicker(title: "AIR", options: AirVariant.allCases.map(\.label), selected: airVariant.rawValue) { [weak self] index in
            self?.airVariant = AirVariant(rawValue: index)!
            self?.applyTuning()
        }
        hud.addChild(controls)
        self.controls = controls
        scoreLabel.position = CGPoint(x: 0, y: halfHeight - 8)
        debugLabel.position = CGPoint(x: -halfWidth + 8, y: controls.pickerBottom - 6)
    }

    // MARK: Stepping

    override func update(_ currentTime: TimeInterval) {
        defer { lastTime = currentTime }
        guard let last = lastTime else { return }
        accumulator += min(currentTime - last, 0.1)
        guard accumulator >= GameScene.stepSeconds else { return }

        hub.touch = controls?.sample() ?? .idle
        let inputs = hub.frames(players: match.players.count)
        if hub.consumeReset() { reset() }
        if hub.consumeCycle() { controls?.cycleTopPicker() }
        var steps = 0
        while accumulator >= GameScene.stepSeconds, steps < GameScene.maxStepsPerFrame {
            match.advance(inputs: inputs)
            show(match.events)
            accumulator -= GameScene.stepSeconds
            steps += 1
        }
        if accumulator >= GameScene.stepSeconds {
            accumulator = 0
        }
        render()
    }

    /// Everyone back to the start, scores cleared.
    private func reset() {
        match = Match()
        rimFlash = rimFlash.map { _ in 0 }
        applyTuning()
    }

    /// The pickers' choices onto both players, live.
    private func applyTuning() {
        for index in match.players.indices {
            match.players[index].spec = airVariant.apply(to: .baseline)
        }
    }

    private func show(_ events: [MatchEvent]) {
        for event in events {
            switch event {
            case .jumped(let index):
                spawn(.jumpSpark, at: match.players[index].position, flipped: match.players[index].facing == .left)
            case .dashed(let index):
                spawn(.smoke, at: match.players[index].position, flipped: match.players[index].facing == .left)
            case .wallJumped(let index, let wall):
                let player = match.players[index]
                spawn(.wallJumpSpark, at: player.position + Vec2(x: wall.sign * 4, y: 5), flipped: wall == .right)
            case .caught(let index):
                let player = match.players[index]
                spawn(.catchSpark, at: player.position + Vec2(x: player.facing.sign * 2, y: 0), flipped: player.facing == .left)
            case .scored(_, let hoop):
                rimFlash[hoop] = 8
            default:
                break
            }
        }
    }

    private func spawn(_ effect: Effect, at position: Vec2, flipped: Bool) {
        world.addChild(effect.node(sprites, at: SpriteLibrary.point(position), flipped: flipped))
    }

    // MARK: Drawing

    private func render() {
        for (index, player) in match.players.enumerated() {
            let node = playerNodes[index]
            let frame = player.animationFrame
            node.texture = sprites.texture(frame, player: index)
            node.size = node.texture!.size()
            node.anchorPoint = sprites.anchor(for: frame.animation)
            node.position = SpriteLibrary.point(player.position)
            node.xScale = CGFloat(player.facing.sign)
            let halo = handHalos[index]
            if player.hasBall, let inHand = sprites.landmark(.ball, in: frame, player: index) {
                halo.isHidden = false
                halo.position = CGPoint(x: node.position.x + inHand.x * CGFloat(player.facing.sign), y: node.position.y + inHand.y)
            } else {
                halo.isHidden = true
            }
            if let head = sprites.landmark(.head, in: frame, player: index) {
                headFires[index].position = CGPoint(x: node.position.x + head.x * CGFloat(player.facing.sign), y: node.position.y + head.y + 3)
            }
        }

        ballNode.isHidden = match.ball.holder != nil
        ballNode.position = SpriteLibrary.point(match.ball.position)
        // The chevron steps down three times and blinks off, seven steps a second, as the pixel one did.
        let step = (match.frame * 7 / 60) % 4
        pointerNode.isHidden = !(match.ball.isLive && match.ball.resting) || step == 3
        pointerNode.position = SpriteLibrary.point(match.ball.position) + CGPoint(x: 0, y: 30 - CGFloat(step) * 6)

        for index in rimNodes.indices {
            if rimFlash[index] > 0 { rimFlash[index] -= 1 }
            rimNodes[index].texture = sprites.texture("hoop_rim", rimFlash[index] > 0 ? 1 : 0)
        }

        previewNodes.forEach { $0.removeFromParent() }
        previewNodes = []
        for player in match.players where player.state == .shootStance && player.shotAim != .zero {
            for (step, point) in match.shotPreview(for: player.index).enumerated() {
                let dot = SKShapeNode(circleOfRadius: 1)
                dot.fillColor = SKColor(white: 1, alpha: step == 0 ? 0.9 : 0.35)
                dot.strokeColor = .clear
                dot.position = SpriteLibrary.point(point)
                dot.zPosition = 15
                world.addChild(dot)
                previewNodes.append(dot)
            }
        }

        scoreLabel.text = "\(match.scores[0])  -  \(match.scores[1])"
        let p = match.players[0]
        debugLabel.text = String(format: "%@ %d  v %.2f %.2f  jumps %d%@%@",
                                 String(describing: p.state), p.stateTimer, p.velocity.x, p.velocity.y, p.jumpsLeft,
                                 p.hasBall ? "  ball" : "", hub.playerOneHasController ? "  pad" : "")
    }

    // MARK: Touches, from the Metal view in points

    /// A point in the view as a point in the HUD's space: the same points, from the centre, y up.
    private func hudPoint(_ point: CGPoint, viewSize: CGSize) -> CGPoint {
        CGPoint(x: point.x - viewSize.width / 2, y: viewSize.height / 2 - point.y)
    }

    func touchBegan(_ touch: UITouch, at point: CGPoint, viewSize: CGSize) {
        controls?.began(touch, at: hudPoint(point, viewSize: viewSize))
    }

    func touchMoved(_ touch: UITouch, to point: CGPoint, viewSize: CGSize) {
        controls?.moved(touch, to: hudPoint(point, viewSize: viewSize))
    }

    func touchEnded(_ touch: UITouch) {
        controls?.ended(touch)
    }
}
