import EsperSim
import SpriteKit

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
}

/// Runs the match at a fixed 60 steps a second and draws the last state. Nothing in here
/// writes back into the match except the inputs it hands to `advance`.
final class GameScene: SKScene {
    private static let stepSeconds = 1.0 / 60
    private static let maxStepsPerFrame = 4
    private static let pixelsPerTile = CGFloat(Stage.tileSize * SpriteLibrary.pixelsPerUnit)
    private static let headScale: CGFloat = 1.25
    /// Pixels above the feet the dribble's ball counts as in the hand, where a drop below
    /// the platform stops mattering.
    private static let dribbleHandHeight: CGFloat = 16
    /// Pixels the head floats above its place on the body, so scaling it up doesn't sink it in.
    private static let headLift: CGFloat = 1
    /// Where to put the catch spark's feet so its ring lands on the snatch's hand: the ring
    /// sits 7 art pixels ahead and 20 up on its own canvas, the hand 18 ahead and 19 up.
    private static let snatchSparkOffset = Vec2(x: 11, y: -1)
    /// A score's lightning favours vertical: it leans this share of the way the ball came
    /// in off vertical, and never past the cap, so it never lies flat.
    private static let strikeLeanShare = 0.5
    private static let strikeMaxLean = degrees(45)
    /// The bolt's size over its sheet.
    private static let strikeScale: CGFloat = 1.5

    private var match = Match()
    private var headVariant = HeadVariant.b
    private var powerVariant = PowerVariant.none
    private let sprites = SpriteLibrary()
    private let hub = InputHub()
    private let cameraNode = SKCameraNode()
    private let world = SKNode()
    /// The world in three layers so the glow can render the bodies on their own: the
    /// court, the bodies, and everything that glows.
    private let ground = SKNode()
    private let bodies = SKNode()
    private let glowers = SKNode()
    /// Sits at the camera's position, scaled to cancel the camera, so its children are laid
    /// out in screen points from the centre and a touch maps onto them with no arithmetic.
    private let hud = SKNode()
    private var controls: TouchControls?
    private var playerNodes: [SKSpriteNode] = []
    /// Each head, drawn apart from its body and following it loosely.
    private var headNodes: [SKSpriteNode] = []
    /// Each body's energy, the slash's blade and the sheets' puffs and streaks, drawn over
    /// the body among the glowers so it blooms.
    private var energyNodes: [SKSpriteNode] = []
    /// The charge round each player's ball while a throw is held, and whether it showed
    /// last frame, so the throw's release can be caught.
    private var chargeNodes: [SKSpriteNode] = []
    private var charging: [Bool] = []
    private var headShown: [CGPoint] = []
    /// Each body's lean in flight, radians, eased toward where it's going, and how much of
    /// the hover it's showing.
    private var bodyTilt: [CGFloat] = []
    private var hover: [CGFloat] = []
    private static let flightTilt: CGFloat = .pi / 6
    /// A still flight drifts round a small circle: this radius, this many seconds a lap.
    private static let hoverRadius: CGFloat = 3
    private static let hoverSeconds = 1.6
    /// The ball in each player's hands, its glow, and the fire off each head.
    private var handBalls: [SKSpriteNode] = []
    private var handHalos: [SKSpriteNode] = []
    private var headFires: [SKEmitterNode] = []
    private var wings: [Wing] = []
    /// Each player's webs: the swing's and the shot's.
    private var swingWebs: [SKShapeNode] = []
    private var shotWebs: [SKShapeNode] = []
    /// Each player's made platform.
    private var platformNodes: [SKSpriteNode] = []
    private var ballNode = SKSpriteNode()
    private var ballHalo = SKSpriteNode()
    private var ballTrail = SKEmitterNode()
    /// The ball's colour: a team's for a while after it's let go, then back to neutral.
    private var ballTeam = SKColor(rgb: BallLook.neutral)
    private var ballHold = 0
    private var ballShift = 0
    private var chevrons: [SKSpriteNode] = []
    /// Over the rim the holder scores on.
    private var targetChevrons: [SKSpriteNode] = []
    /// The floor and walls, coloured for whoever holds the ball.
    private var courtTiles: [SKSpriteNode] = []
    private var courtColour = SKColor(rgb: CourtLook.neutral)
    private var courtTarget = SKColor(rgb: CourtLook.neutral)
    private var courtShift = 0
    private var rimNodes: [SKSpriteNode] = []
    private var rimFlash: [Int] = []
    private var previewDots: [SKSpriteNode] = []
    private let scoreLabel = SKLabelNode()
    private let debugLabel = SKLabelNode()
    private let fpsLabel = SKLabelNode()
    private var lastTime: TimeInterval?
    private var accumulator = 0.0
    private var built = false
    private var ready = false
    /// A texture reaches the GPU the first time it's drawn, and until then it draws as a
    /// white square. So every texture is drawn once, tiny and all but invisible, for a few
    /// frames before the game starts.
    private let warmNode = SKNode()
    private var warmFramesLeft = 3
    private var preloaded = false
    private(set) var safeInsets = UIEdgeInsets.zero
    /// What the Metal view measured, shown in the corner.
    var framesPerSecond = 0
    var worstFrameMilliseconds = 0

    /// The bodies as drawn this frame, for the mask scene to copy.
    var bodySnapshots: [BodySnapshot] {
        playerNodes.compactMap { node in
            node.texture.map { BodySnapshot(texture: $0, position: node.position, anchor: node.anchorPoint, xScale: node.xScale, size: node.size) }
        }
    }

    var cameraPosition: CGPoint { cameraNode.position }
    var cameraScale: CGFloat { cameraNode.xScale }

    private static let background = SKColor(red: 0.18, green: 0.12, blue: 0.24, alpha: 1)

    override init() {
        super.init(size: CGSize(width: 640, height: 288))
        scaleMode = .fill
        backgroundColor = GameScene.background
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The Metal view calls this with its size in points whenever that or the safe area changes.
    func attach(size: CGSize, displayScale: CGFloat, insets: UIEdgeInsets) {
        self.size = size
        safeInsets = insets
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
        world.addChild(ground)
        bodies.zPosition = 20
        world.addChild(bodies)
        glowers.zPosition = 21
        world.addChild(glowers)
        camera = cameraNode
        addChild(cameraNode)
        hud.zPosition = 100
        addChild(hud)

        // Every frame in both looks, made before anything is drawn, then drawn once each.
        sprites.warmUp(players: match.players.count) { [weak self] in self?.preloaded = true }
        for texture in sprites.allTextures {
            let sprite = SKSpriteNode(texture: texture)
            sprite.size = CGSize(width: 1, height: 1)
            sprite.alpha = 0.02
            warmNode.addChild(sprite)
        }
        warmNode.zPosition = 90
        hud.addChild(warmNode)

        // The floor and walls take the holder's colour, the backboard blocks keep their rim's
        // owner's, and the ledge is magenta.
        let stage = match.stage
        for row in 0..<stage.rows {
            for column in 0..<stage.columns {
                let tile = stage.tile(column: column, row: row)
                guard tile != .empty else { continue }
                let node = SKSpriteNode(texture: sprites.flatSquare(size: 16, alpha: 1))
                node.colorBlendFactor = 1
                node.anchorPoint = .zero
                node.position = CGPoint(x: CGFloat(column) * GameScene.pixelsPerTile, y: CGFloat(row) * GameScene.pixelsPerTile)
                let x = (Double(column) + 0.5) * Stage.tileSize, y = (Double(row) + 0.5) * Stage.tileSize
                let border = column == 0 || column == stage.columns - 1 || row == 0
                if tile == .oneWay {
                    node.color = SKColor(rgb: CourtLook.ledge)
                } else if !border, let hoop = stage.hoops.min(by: { $0.position.distance(to: Vec2(x: x, y: y)) < $1.position.distance(to: Vec2(x: x, y: y)) }) {
                    // You score on your opponent's basket, so the block wears the other colour.
                    node.color = SKColor(rgb: CourtLook.shaded(sprites.look(for: 1 - hoop.owner).glow))
                } else {
                    node.color = courtColour
                    courtTiles.append(node)
                }
                ground.addChild(node)
            }
        }

        for hoop in stage.hoops {
            let rim = SKSpriteNode(texture: sprites.texture("hoop_rim", 0))
            rim.position = SpriteLibrary.point(hoop.position)
            rim.zPosition = 5
            // The sheet draws the rim with its backboard on the right.
            rim.xScale = hoop.backboard == .left ? -1 : 1
            ground.addChild(rim)
            rimNodes.append(rim)
            rimFlash.append(0)
            ground.addChild(net(at: rim.position))
        }

        for player in match.players {
            let node = SKSpriteNode(texture: sprites.texture(player.animationFrame, player: player.index))
            bodies.addChild(node)
            playerNodes.append(node)
            let head = SKSpriteNode(texture: sprites.headTexture(player.animationFrame, player: player.index))
            head.zPosition = 4
            glowers.addChild(head)
            headNodes.append(head)
            let energy = SKSpriteNode()
            energy.zPosition = 3
            energy.isHidden = true
            glowers.addChild(energy)
            energyNodes.append(energy)
            let charge = SKSpriteNode()
            charge.zPosition = 5
            charge.isHidden = true
            charge.setScale(EnergyEffect.chargeScale)
            glowers.addChild(charge)
            chargeNodes.append(charge)
            charging.append(false)
            headShown.append(.zero)
            bodyTilt.append(0)
            hover.append(0)
            let colour = SKColor(rgb: sprites.look(for: player.index).glow)
            let handBall = SKSpriteNode(texture: sprites.texture("ball", 0))
            handBall.color = colour
            handBall.colorBlendFactor = 1
            handBall.zPosition = 3
            glowers.addChild(handBall)
            handBalls.append(handBall)
            let halo = makeHalo(colour)
            halo.zPosition = 2
            glowers.addChild(halo)
            handHalos.append(halo)
            let fire = makeFire(colour)
            fire.zPosition = 1
            fire.targetNode = glowers
            glowers.addChild(fire)
            headFires.append(fire)
            for webs in [\GameScene.swingWebs, \GameScene.shotWebs] {
                let web = SKShapeNode()
                web.strokeColor = colour
                web.lineWidth = 3
                web.lineCap = .round
                web.blendMode = .add
                web.zPosition = 0
                web.isHidden = true
                glowers.addChild(web)
                self[keyPath: webs].append(web)
            }
        }
        for player in match.players {
            let slab = SKSpriteNode(texture: sprites.flatSquare(size: 16, alpha: 1))
            slab.color = SKColor(rgb: CourtLook.shaded(sprites.look(for: player.index).glow))
            slab.colorBlendFactor = 1
            slab.anchorPoint = CGPoint(x: 0, y: 0)
            slab.zPosition = 1
            slab.isHidden = true
            ground.addChild(slab)
            platformNodes.append(slab)
        }
        // The wings are parked: `Wing.swift` stays, nothing is added to the scene.

        ballNode = SKSpriteNode(texture: sprites.texture("ball", 0))
        ballNode.colorBlendFactor = 1
        ballNode.zPosition = 6
        glowers.addChild(ballNode)
        ballHalo = makeHalo(ballTeam)
        ballHalo.zPosition = -1
        ballNode.addChild(ballHalo)
        ballTrail = makeTrail()
        ballTrail.zPosition = 5
        ballTrail.targetNode = glowers
        glowers.addChild(ballTrail)

        for _ in 0..<3 {
            let chevron = SKSpriteNode(texture: sprites.symbol("chevron.down", pointSize: 14))
            chevron.color = SKColor(rgb: BallLook.chevron)
            chevron.colorBlendFactor = 1
            chevron.zPosition = 6
            glowers.addChild(chevron)
            chevrons.append(chevron)
        }
        for _ in 0..<3 {
            let chevron = SKSpriteNode(texture: sprites.symbol("chevron.down", pointSize: 10))
            chevron.color = SKColor(rgb: CourtLook.targetChevron)
            chevron.colorBlendFactor = 1
            chevron.zPosition = 6
            glowers.addChild(chevron)
            targetChevrons.append(chevron)
        }

        // The aiming arc's dots, made once and moved.
        for _ in 0..<30 {
            let dot = SKSpriteNode(texture: sprites.softGlow(diameter: 8))
            dot.size = CGSize(width: 3, height: 3)
            dot.zPosition = 3
            dot.isHidden = true
            glowers.addChild(dot)
            previewDots.append(dot)
        }

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

        fpsLabel.fontName = "Menlo-Bold"
        fpsLabel.fontSize = 10
        fpsLabel.fontColor = SKColor(white: 1, alpha: 0.7)
        fpsLabel.horizontalAlignmentMode = .left
        fpsLabel.verticalAlignmentMode = .bottom
        hud.addChild(fpsLabel)
    }

    /// A soft glow in the colour, added, which the glow pass then picks up.
    private func makeHalo(_ colour: SKColor) -> SKSpriteNode {
        let halo = SKSpriteNode(texture: sprites.softGlow(diameter: 32))
        halo.size = CGSize(width: 18, height: 18)
        halo.color = colour
        halo.colorBlendFactor = 1
        halo.alpha = 0.5
        halo.blendMode = .add
        return halo
    }

    /// Bits rising off a head: hard little squares in the colour that step down in size as
    /// they go, more a digital dissolve than a flame.
    private func makeFire(_ colour: SKColor) -> SKEmitterNode {
        let fire = SKEmitterNode()
        fire.particleTexture = sprites.flatSquare(size: 4, alpha: 1)
        fire.particleBirthRate = 40
        fire.particleLifetime = 0.6
        fire.particleLifetimeRange = 0.1
        fire.particlePositionRange = CGVector(dx: 2, dy: 1)
        fire.particleSpeed = 24
        fire.particleSpeedRange = 4
        fire.emissionAngle = .pi / 2
        fire.emissionAngleRange = .pi / 14
        fire.yAcceleration = 10
        fire.particleSize = CGSize(width: 3, height: 3)
        let steps = SKKeyframeSequence(keyframeValues: [1, 0.66, 0.33], times: [0, 0.45, 0.75])
        steps.interpolationMode = .step
        fire.particleScaleSequence = steps
        let fade = SKKeyframeSequence(keyframeValues: [0.9, 0.9, 0.5, 0], times: [0, 0.6, 0.85, 1])
        fade.interpolationMode = .step
        fire.particleAlphaSequence = fade
        fire.particleColor = colour
        fire.particleColorBlendFactor = 1
        // Drawn over, not added: hard squares added on top of the head saturate to white.
        fire.particleBlendMode = .alpha
        return fire
    }

    /// The floor and walls shift toward whoever holds the ball, and back to neutral.
    private func tickCourtColour() {
        let wanted = match.ball.holder.map { SKColor(rgb: CourtLook.shaded(sprites.look(for: $0).glow)) } ?? SKColor(rgb: CourtLook.neutral)
        if wanted != courtTarget {
            courtTarget = wanted
            courtShift = CourtLook.shiftFrames
        }
        guard courtShift > 0 else { return }
        courtShift -= 1
        let share = 1 / CGFloat(courtShift + 1)
        var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        courtColour.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
        courtTarget.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        courtColour = SKColor(red: cr + (tr - cr) * share, green: cg + (tg - cg) * share, blue: cb + (tb - cb) * share, alpha: 1)
        for tile in courtTiles { tile.color = courtColour }
    }

    /// The streak a flying ball leaves: soft blobs dropped where it was, thinning out, so
    /// the trail runs like liquid light.
    private func makeTrail() -> SKEmitterNode {
        let trail = SKEmitterNode()
        trail.particleTexture = sprites.softGlow(diameter: 32)
        trail.particleBirthRate = 0
        trail.particleLifetime = 0.35
        trail.particleLifetimeRange = 0.1
        trail.particlePositionRange = CGVector(dx: 2, dy: 2)
        trail.particleSpeed = 0
        trail.particleSize = CGSize(width: 12, height: 12)
        trail.particleScale = 0.8
        trail.particleScaleRange = 0.2
        trail.particleScaleSpeed = -1.8
        trail.particleAlpha = 0.6
        trail.particleAlphaSpeed = -1.6
        trail.particleColorBlendFactor = 1
        trail.particleBlendMode = .add
        return trail
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
        let controls = TouchControls(halfWidth: halfWidth, halfHeight: halfHeight, insets: safeInsets)
        controls.onReset = { [weak self] in self?.reset() }
        controls.addPicker(title: "HEAD", options: HeadVariant.allCases.map(\.label), selected: headVariant.rawValue) { [weak self] index in
            self?.headVariant = HeadVariant(rawValue: index)!
        }
        controls.addPicker(title: "POWER", options: PowerVariant.allCases.map(\.label), selected: powerVariant.rawValue) { [weak self] index in
            self?.powerVariant = PowerVariant(rawValue: index)!
            self?.applyPower()
        }
        controls.addSlider(title: "GLOW THRESHOLD", range: 0.2...1.0, notch: 0.1, value: GlowSettings.threshold) { value in
            GlowSettings.threshold = value
        }
        hud.addChild(controls)
        self.controls = controls
        scoreLabel.position = CGPoint(x: 0, y: halfHeight - safeInsets.top - 8)
        debugLabel.position = CGPoint(x: -halfWidth + safeInsets.left + TouchControls.padding, y: controls.pickerBottom - 6)
        fpsLabel.position = CGPoint(x: -halfWidth + safeInsets.left + TouchControls.padding, y: -halfHeight + safeInsets.bottom + TouchControls.padding)
    }

    // MARK: Stepping

    override func update(_ currentTime: TimeInterval) {
        defer { lastTime = currentTime }
        if !ready {
            // Hold until the textures have all been drawn once.
            if preloaded, warmFramesLeft > 0 { warmFramesLeft -= 1 }
            if preloaded, warmFramesLeft == 0 {
                warmNode.removeFromParent()
                ready = true
            }
            return
        }
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
            tickBallColour()
            tickCourtColour()
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
        ballTeam = SKColor(rgb: BallLook.neutral)
        ballHold = 0
        ballShift = 0
        applyPower()
    }

    /// The picker's power onto both players, live.
    private func applyPower() {
        for index in match.players.indices {
            match.players[index].power = powerVariant.power
        }
    }

    private func show(_ events: [MatchEvent]) {
        for event in events {
            switch event {
            case .jumped(let index):
                spawn(.jumpSpark, at: match.players[index].position, flipped: match.players[index].facing == .left)
            case .dashed(let index), .slid(let index):
                spawn(.smoke, at: match.players[index].position, flipped: match.players[index].facing == .left)
            case .snatchReached(let index):
                let player = match.players[index]
                let offset = Vec2(x: GameScene.snatchSparkOffset.x * player.facing.sign, y: GameScene.snatchSparkOffset.y) / SpriteLibrary.pixelsPerUnit
                spawn(.catchSpark, at: player.position + offset, flipped: player.facing == .left)
            case .popped(let victim, let popper):
                // A spark off the ball as it leaves the hands, in the colour of whoever knocked it.
                spawnHitSpark(player: popper, at: match.players[victim].chest + Vec2(x: 0, y: 3))
            case .swatted(let index, hit: true):
                spawnHitSpark(player: index, at: match.ball.position)
            case .wallJumped(let index, let wall):
                let player = match.players[index]
                spawn(.wallJumpSpark, at: player.position + Vec2(x: wall.sign * 4, y: 5), flipped: wall == .right)
            case .caught(let index):
                let player = match.players[index]
                spawn(.catchSpark, at: player.position + Vec2(x: player.facing.sign * 2, y: 0), flipped: player.facing == .left)
            case .doubleJumped(let index):
                let player = match.players[index]
                spawnJumpPlatform(at: SpriteLibrary.point(player.position), colour: SKColor(rgb: sprites.look(for: index).glow))
            case .warped(let index, let from, let to):
                let colour = SKColor(rgb: sprites.look(for: index).glow)
                spawnBlink(at: SpriteLibrary.point(from + Vec2(x: 0, y: BallRules.chestHeight)), colour: colour)
                spawnBlink(at: SpriteLibrary.point(to + Vec2(x: 0, y: BallRules.chestHeight)), colour: colour)
            case .shot(let index), .thrown(let index), .dunked(let index):
                ballTeam = SKColor(rgb: sprites.look(for: index).glow)
                ballHold = BallLook.holdFrames
                ballShift = BallLook.shiftFrames
            case .scored(let scorer, let hoop):
                rimFlash[hoop] = 8
                strike(hoop: hoop, by: scorer)
            default:
                break
            }
        }
    }

    /// The ball keeps the team colour for a while after it's let go, then shifts to neutral.
    private func tickBallColour() {
        if ballHold > 0 {
            ballHold -= 1
        } else if ballShift > 0 {
            ballShift -= 1
        }
    }

    private var ballColour: SKColor {
        guard ballHold == 0 else { return ballTeam }
        let neutral = SKColor(rgb: BallLook.neutral)
        let toward = 1 - CGFloat(ballShift) / CGFloat(BallLook.shiftFrames)
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        var nr: CGFloat = 0, ng: CGFloat = 0, nb: CGFloat = 0, na: CGFloat = 0
        ballTeam.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        neutral.getRed(&nr, green: &ng, blue: &nb, alpha: &na)
        return SKColor(red: tr + (nr - tr) * toward, green: tg + (ng - tg) * toward, blue: tb + (nb - tb) * toward, alpha: 1)
    }

    /// A short platform of loose digital squares under the feet where a double jump was
    /// taken: they hang a moment, then drop away and cut out.
    private func spawnJumpPlatform(at feet: CGPoint, colour: SKColor) {
        let count = 9
        for index in 0..<count {
            let square = SKSpriteNode(texture: sprites.flatSquare(size: 4, alpha: 1))
            square.size = CGSize(width: 3, height: 3)
            square.color = colour
            square.colorBlendFactor = 1
            square.blendMode = .alpha
            square.zPosition = 3
            let spread = CGFloat(index - count / 2) * 4
            square.position = CGPoint(x: feet.x + spread, y: feet.y - 2 + CGFloat(index % 2))
            glowers.addChild(square)
            let hold = 0.12 + Double(abs(index - count / 2)) * 0.02
            let drop = SKAction.moveBy(x: spread * 0.3, y: -10 - CGFloat(index % 3) * 4, duration: 0.3)
            drop.timingMode = .easeIn
            let shrink = SKAction.sequence([.wait(forDuration: 0.15), .scale(to: 0.66, duration: 0), .wait(forDuration: 0.1), .scale(to: 0.33, duration: 0)])
            square.run(.sequence([.wait(forDuration: hold), .group([drop, shrink]), .removeFromParent()]))
        }
    }

    /// Flash Fizz's blink: a bright diamond, wide and low, that flares out and is gone.
    private func spawnBlink(at point: CGPoint, colour: SKColor) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -14, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 4))
        path.addLine(to: CGPoint(x: 14, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -4))
        path.closeSubpath()
        for (scale, tint) in [(1.0, SKColor.white), (1.8, colour)] {
            let blink = SKShapeNode(path: path)
            blink.fillColor = tint
            blink.strokeColor = .clear
            blink.blendMode = .add
            blink.position = point
            blink.zPosition = 8
            blink.setScale(0.2)
            glowers.addChild(blink)
            let flare = SKAction.scale(to: scale, duration: 0.12)
            flare.timingMode = .easeOut
            blink.run(.sequence([.group([flare, .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
        }
    }

    /// One of the two sparks, either each time, on the ball in the hitter's colour.
    private func spawnHitSpark(player: Int, at position: Vec2) {
        let spark = EnergyEffect.hitSparks.randomElement()!
        glowers.addChild(spark.node(sprites, player: player, at: SpriteLibrary.point(position)))
    }

    /// A score: lightning strikes the rim from the way the ball came in, leaning half as
    /// far as the ball did and never past the cap, one of the four bolts each time, at the
    /// strike scale. The sheet's two full-frame flash frames are matched by a flash over the whole screen in the same
    /// tone, and the half-frame flash after them by a band riding the bolt from that
    /// half's bottom edge out past the screen, so the sprite's own edges never show
    /// through them. The crown erupts off the rim with it.
    private func strike(hoop: Int, by scorer: Int) {
        let rim = SpriteLibrary.point(match.stage.hoops[hoop].position)
        let velocity = match.ball.velocity
        let lean = min(max(atan2(velocity.x, -velocity.y) * GameScene.strikeLeanShare, -GameScene.strikeMaxLean), GameScene.strikeMaxLean)
        let bolt = EnergyEffect.strikes.randomElement()!
        let node = bolt.node(sprites, player: scorer, at: rim)
        node.zRotation = CGFloat(lean)
        node.zPosition = 45
        let visible = CGRect(x: cameraNode.position.x - size.width * cameraNode.xScale / 2,
                             y: cameraNode.position.y - size.height * cameraNode.yScale / 2,
                             width: size.width * cameraNode.xScale, height: size.height * cameraNode.yScale)
        node.setScale(GameScene.strikeScale)
        glowers.addChild(node)

        let tone = SKColor(rgb: sprites.look(for: scorer).energyTone(luminance: EnergyEffect.strikeLuminance))
        let frame = 1 / bolt.fps
        let flash = SKSpriteNode(texture: sprites.flatSquare(size: 16, alpha: 1))
        flash.color = tone
        flash.colorBlendFactor = 1
        flash.size = visible.size
        flash.position = CGPoint(x: visible.midX, y: visible.midY)
        flash.zPosition = 44
        flash.isHidden = true
        glowers.addChild(flash)
        flash.run(.sequence([.wait(forDuration: Double(EnergyEffect.strikeFlashFrames.lowerBound) * frame), .unhide(),
                             .wait(forDuration: Double(EnergyEffect.strikeFlashFrames.count) * frame), .removeFromParent()]))
        // The band is the bolt's child, so it takes its scale and lean: its bottom edge sits
        // where the sheet's solid half ends, in the sheet's own pixels, and it runs on far
        // past the screen from there.
        let band = SKSpriteNode(texture: sprites.flatSquare(size: 16, alpha: 1))
        band.color = tone
        band.colorBlendFactor = 1
        band.anchorPoint = CGPoint(x: 0.5, y: 0)
        band.position = CGPoint(x: 0, y: CGFloat(EnergyEffect.strikeHalfFlashRows))
        band.size = CGSize(width: 4096, height: 4096)
        band.zPosition = -1
        band.isHidden = true
        node.addChild(band)
        band.run(.sequence([.wait(forDuration: Double(EnergyEffect.strikeHalfFlashFrame) * frame), .unhide(),
                            .wait(forDuration: frame), .hide()]))

        let crown = EnergyEffect.spark3.node(sprites, player: scorer, at: rim)
        crown.zPosition = 46
        glowers.addChild(crown)
    }

    private func line(from a: CGPoint, to b: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    private func spawn(_ effect: Effect, at position: Vec2, flipped: Bool) {
        glowers.addChild(effect.node(sprites, at: SpriteLibrary.point(position), flipped: flipped))
    }

    // MARK: Drawing

    private func render() {
        for (index, player) in match.players.enumerated() {
            let node = playerNodes[index]
            let frame = player.animationFrame
            node.texture = sprites.texture(frame, player: index)
            node.size = node.texture!.size()
            node.anchorPoint = sprites.anchor(for: frame.animation)
            // A flight holding still hovers round a small circle, eased in and out.
            let stillFlight = player.state == .flying && player.velocity.length < 0.2
            hover[index] += ((stillFlight ? 1 : 0) - hover[index]) * 0.1
            let lap = Double(match.frame) / 60 / GameScene.hoverSeconds * 2 * .pi
            let drift = CGPoint(x: (cos(lap) * Double(GameScene.hoverRadius * hover[index])).rounded(),
                                y: (sin(lap) * Double(GameScene.hoverRadius * hover[index])).rounded())
            node.position = SpriteLibrary.point(player.position) + drift
            node.xScale = CGFloat(player.facing.sign)

            // In flight the body leans into its motion: forward tips it ahead, backward tips
            // it back, up to thirty degrees, eased so it doesn't snap.
            var wantedTilt: CGFloat = 0
            if player.state == .flying {
                let ahead = player.velocity.x * player.facing.sign / SodaRules.flightSpeedWithoutBall
                wantedTilt = -CGFloat(min(max(ahead, -1), 1)) * GameScene.flightTilt * CGFloat(player.facing.sign)
            }
            bodyTilt[index] += (wantedTilt - bodyTilt[index]) * 0.2
            node.zRotation = bodyTilt[index]

            // The frame's energy rides exactly where the body is drawn.
            let energyNode = energyNodes[index]
            if let energy = sprites.energyTexture(frame, player: index) {
                energyNode.isHidden = false
                energyNode.texture = energy
                energyNode.size = node.size
                energyNode.anchorPoint = node.anchorPoint
                energyNode.position = node.position
                energyNode.xScale = node.xScale
                energyNode.zRotation = node.zRotation
            } else {
                energyNode.isHidden = true
            }
            let tilt = bodyTilt[index]
            func leaned(_ offset: CGPoint) -> CGPoint {
                CGPoint(x: offset.x * cos(tilt) - offset.y * sin(tilt), y: offset.x * sin(tilt) + offset.y * cos(tilt))
            }

            // The ball in hand rides the frame's ball, and when that hangs off a ledge the
            // dribble reaches down to the real floor under it, over the same frames.
            let halo = handHalos[index]
            let handBall = handBalls[index]
            if player.hasBall, let inHand = sprites.landmark(.ball, in: frame, player: index) {
                let ballX = player.position.x + Double(inHand.x) * player.facing.sign / SpriteLibrary.pixelsPerUnit
                // Only a dribble reaches for the floor; in the air the ball stays where the frame put it.
                let drop = player.grounded ? match.stage.drop(fromX: ballX, y: player.position.y) * SpriteLibrary.pixelsPerUnit : 0
                let phase = min(max(inHand.y / GameScene.dribbleHandHeight, 0), 1)
                let y = inHand.y - CGFloat(drop) * (1 - phase)
                let at = node.position + leaned(CGPoint(x: inHand.x * CGFloat(player.facing.sign), y: y.rounded()))
                halo.isHidden = false
                halo.position = at
                handBall.isHidden = false
                handBall.position = at
            } else {
                halo.isHidden = true
                handBall.isHidden = true
            }

            // A held throw charges: the swirl round the ball in hand, up to the loop's end,
            // then round the loop for as long as the throw is held. Let go into the throw,
            // the rest of the sheet plays out where the ball was.
            let charge = chargeNodes[index]
            let chargingNow = player.state == .throwStance && !handBall.isHidden
            if chargingNow {
                let played = player.stateTimer * Int(EnergyEffect.charge.fps) / 60
                let loopStart = EnergyEffect.chargeLoopStart, loopEnd = EnergyEffect.chargeLoopEnd
                let frame = played <= loopEnd ? played : loopStart + (played - loopStart) % (loopEnd - loopStart + 1)
                charge.texture = sprites.effectTexture(EnergyEffect.charge.name, frame, player: index)
                charge.size = charge.texture!.size()
                charge.position = handBall.position
                charge.isHidden = false
            } else {
                charge.isHidden = true
                if charging[index], player.state == .throwing || player.state == .dunking {
                    let tail = EnergyEffect.charge.node(sprites, player: index, at: charge.position,
                                                        frames: (EnergyEffect.chargeLoopEnd + 1)..<EnergyEffect.charge.frameCount,
                                                        scale: EnergyEffect.chargeScale)
                    tail.zPosition = 5
                    glowers.addChild(tail)
                }
            }
            charging[index] = chargingNow

            // The head follows its place on the body loosely and bobs, as if it only just belonged.
            let headNode = headNodes[index]
            if let head = sprites.landmark(.head, in: frame, player: index),
               let headTexture = sprites.headTexture(frame, player: index),
               let anchor = sprites.headAnchor(frame, player: index) {
                let target = node.position + leaned(CGPoint(x: head.x * CGFloat(player.facing.sign), y: head.y))
                if headShown[index] == .zero { headShown[index] = target }
                let lag = headVariant.lag
                headShown[index] = CGPoint(x: headShown[index].x + (target.x - headShown[index].x) * lag,
                                           y: headShown[index].y + (target.y - headShown[index].y) * lag)
                var offset = headShown[index] - target
                if headVariant.reversedAcross { offset.x = -offset.x }
                let bob = (sin(Double(match.frame) / 60 * 2 * .pi * 1.2) * 1).rounded()
                let shown = CGPoint(x: (target.x + offset.x).rounded(), y: (target.y + offset.y).rounded() + bob + GameScene.headLift)
                headNode.isHidden = false
                headNode.texture = headTexture
                // Sized outright rather than scaled, and only ever flipped.
                headNode.size = CGSize(width: headTexture.size().width * GameScene.headScale, height: headTexture.size().height * GameScene.headScale)
                headNode.anchorPoint = anchor
                headNode.xScale = CGFloat(player.facing.sign)
                headNode.yScale = 1
                headNode.zRotation = tilt
                headNode.position = shown
                headFires[index].position = CGPoint(x: shown.x, y: shown.y + 4)
                headFires[index].particleBirthRate = 24
                // One sideways wind on all the bits at once, swinging back and forth, so the
                // column bends as a whole like a scarf rather than scattering.
                headFires[index].xAcceleration = CGFloat(sin(Double(match.frame) / 60 * 2 * .pi * 1.1 + Double(index) * 2)) * 140
            } else {
                headNode.isHidden = true
                headFires[index].particleBirthRate = 0
            }
        }

        // The webs: a swing's from its anchor, a shot's to whatever it holds.
        for (index, player) in match.players.enumerated() {
            let chest = SpriteLibrary.point(player.chest)
            let swing = swingWebs[index]
            if let anchor = player.webAnchor {
                swing.isHidden = false
                swing.path = line(from: SpriteLibrary.point(anchor), to: chest)
            } else {
                swing.isHidden = true
            }
            let shot = shotWebs[index]
            if player.webAiming {
                // A faint line the way the shot would go.
                shot.isHidden = false
                shot.alpha = 0.3
                shot.path = line(from: chest, to: SpriteLibrary.point(player.chest + player.webAimDirection * WebRules.lineRange))
            } else if let web = player.webLine {
                shot.alpha = 1
                let end: CGPoint
                switch web.target {
                case .point(let point): end = SpriteLibrary.point(point)
                case .ball: end = SpriteLibrary.point(match.ball.position)
                case .opponent: end = SpriteLibrary.point(match.players[1 - index].chest)
                }
                shot.isHidden = false
                shot.path = line(from: chest, to: end)
            } else {
                shot.isHidden = true
            }
        }

        // Made platforms, in their maker's dark shade, thinning out over their last quarter second.
        for (index, slab) in platformNodes.enumerated() {
            if let platform = match.platforms.first(where: { $0.owner == index }) {
                slab.isHidden = false
                slab.position = SpriteLibrary.point(platform.box.min)
                slab.size = CGSize(width: (platform.box.width * SpriteLibrary.pixelsPerUnit).rounded(),
                                   height: (platform.box.height * SpriteLibrary.pixelsPerUnit).rounded())
                slab.alpha = min(CGFloat(platform.framesLeft) / 15, 1)
            } else {
                slab.isHidden = true
            }
        }

        let ball = match.ball
        ballNode.isHidden = ball.holder != nil
        ballNode.position = SpriteLibrary.point(ball.position)
        let colour = ballColour
        ballNode.color = colour
        ballHalo.color = colour
        ballTrail.position = ballNode.position
        ballTrail.particleColor = colour
        ballTrail.particleBirthRate = ball.isLive && !ball.resting && ball.velocity.length > 1 ? 90 : 0

        // Three dim chevrons stacked over a resting ball, lit one after another from the top, then
        // a beat with none, four steps a second so each one reads as a step.
        let step = (match.frame * 4 / 60) % 4
        let showChevrons = ball.isLive && ball.resting
        for (index, chevron) in chevrons.enumerated() {
            chevron.isHidden = !showChevrons
            chevron.position = ballNode.position + CGPoint(x: 0, y: 32 - CGFloat(index) * 7)
            chevron.alpha = step == index ? 1 : 0.3
        }
        // The same, smaller and fainter and green, over the rim the holder scores on.
        let targetHoop = ball.holder.flatMap { holder in match.stage.hoops.first { $0.owner == holder } }
        for (index, chevron) in targetChevrons.enumerated() {
            chevron.isHidden = targetHoop == nil
            if let targetHoop {
                chevron.position = SpriteLibrary.point(targetHoop.position) + CGPoint(x: 0, y: 30 - CGFloat(index) * 5)
            }
            chevron.alpha = step == index ? 0.6 : 0.2
        }

        for index in rimNodes.indices {
            if rimFlash[index] > 0 { rimFlash[index] -= 1 }
            rimNodes[index].texture = sprites.texture("hoop_rim", rimFlash[index] > 0 ? 1 : 0)
        }

        var shownDots = 0
        for player in match.players where player.state == .shootStance && player.shotAim != .zero {
            for (step, point) in match.shotPreview(for: player.index).enumerated() where shownDots < previewDots.count {
                let dot = previewDots[shownDots]
                dot.isHidden = false
                dot.alpha = step == 0 ? 0.9 : 0.35
                dot.position = SpriteLibrary.point(point)
                shownDots += 1
            }
        }
        for dot in previewDots[shownDots...] { dot.isHidden = true }

        scoreLabel.text = "\(match.scores[0])  -  \(match.scores[1])"
        fpsLabel.text = "\(framesPerSecond) fps  worst \(worstFrameMilliseconds) ms"
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
