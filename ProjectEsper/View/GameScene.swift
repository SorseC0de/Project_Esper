import EsperSim
import SpriteKit

/// Runs the match at a fixed 60 steps a second and draws the last state. Nothing in here
/// writes back into the match except the inputs it hands to `advance`.
final class GameScene: SKScene {
    private static let stepSeconds = 1.0 / 60
    private static let maxStepsPerFrame = 4
    private static let pixelsPerTile = CGFloat(Stage.tileSize * SpriteLibrary.pixelsPerUnit)

    private var match = Match()
    private let sprites = SpriteLibrary()
    private let hub = InputHub()
    private let cameraNode = SKCameraNode()
    private let world = SKNode()
    private var controls: TouchControls?
    private var playerNodes: [SKSpriteNode] = []
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
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.08, green: 0.09, blue: 0.14, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        hub.activate()
        if !built {
            build()
            built = true
        }
        layout(in: view)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        if let view, built { layout(in: view) }
    }

    // MARK: Building

    private func build() {
        addChild(world)
        camera = cameraNode
        addChild(cameraNode)

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
            world.addChild(rim)
            rimNodes.append(rim)
            rimFlash.append(0)
            world.addChild(net(at: rim.position))
        }

        for player in match.players {
            let node = SKSpriteNode(texture: sprites.texture(player.animationFrame))
            node.zPosition = 20
            world.addChild(node)
            playerNodes.append(node)
        }

        ballNode = SKSpriteNode(texture: sprites.texture("ball", 0))
        ballNode.zPosition = 25
        world.addChild(ballNode)
        pointerNode = SKSpriteNode(texture: sprites.texture("ball_pointer", 0))
        pointerNode.zPosition = 25
        world.addChild(pointerNode)

        scoreLabel.fontName = "Menlo-Bold"
        scoreLabel.fontSize = 12
        scoreLabel.fontColor = .white
        scoreLabel.verticalAlignmentMode = .top
        cameraNode.addChild(scoreLabel)

        debugLabel.fontName = "Menlo"
        debugLabel.fontSize = 6
        debugLabel.fontColor = SKColor(white: 1, alpha: 0.6)
        debugLabel.horizontalAlignmentMode = .left
        debugLabel.verticalAlignmentMode = .top
        debugLabel.numberOfLines = 0
        cameraNode.addChild(debugLabel)
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
    private func layout(in view: SKView) {
        let screenScale = view.traitCollection.displayScale
        let stageWidth = CGFloat(match.stage.columns) * GameScene.pixelsPerTile
        let stageHeight = CGFloat(match.stage.rows) * GameScene.pixelsPerTile
        let fitHeight = (screenScale * size.height / stageHeight).rounded(.down)
        let fitWidth = (screenScale * size.width / stageWidth).rounded(.down)
        let screenPixelsPerGamePixel = max(1, min(fitHeight, fitWidth))
        let pointsPerGamePixel = screenPixelsPerGamePixel / screenScale
        cameraNode.setScale(1 / pointsPerGamePixel)
        cameraNode.position = CGPoint(x: stageWidth / 2, y: stageHeight / 2)

        let halfWidth = size.width / pointsPerGamePixel / 2
        let halfHeight = size.height / pointsPerGamePixel / 2
        controls?.removeFromParent()
        let controls = TouchControls(halfWidth: halfWidth, halfHeight: halfHeight)
        cameraNode.addChild(controls)
        self.controls = controls
        scoreLabel.position = CGPoint(x: 0, y: halfHeight - 6)
        debugLabel.position = CGPoint(x: -halfWidth + 6, y: halfHeight - 6)
    }

    // MARK: Stepping

    override func update(_ currentTime: TimeInterval) {
        defer { lastTime = currentTime }
        guard let last = lastTime else { return }
        accumulator += min(currentTime - last, 0.1)
        guard accumulator >= GameScene.stepSeconds else { return }

        hub.touch = controls?.input ?? .idle
        let inputs = hub.frames(players: match.players.count)
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
            node.texture = sprites.texture(frame)
            node.size = node.texture!.size()
            node.anchorPoint = sprites.anchor(for: frame.animation)
            node.position = SpriteLibrary.point(player.position)
            node.xScale = CGFloat(player.facing.sign)
        }

        ballNode.isHidden = match.ball.holder != nil
        ballNode.position = SpriteLibrary.point(match.ball.position)
        pointerNode.isHidden = !(match.ball.isLive && match.ball.resting)
        pointerNode.position = SpriteLibrary.point(match.ball.position + Vec2(x: 0, y: 16))
        pointerNode.texture = sprites.texture("ball_pointer", (match.frame * 7 / 60) % 4)

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

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let controls else { return }
        for touch in touches {
            controls.began(touch, at: touch.location(in: controls))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let controls else { return }
        for touch in touches {
            controls.moved(touch, to: touch.location(in: controls))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touches.forEach { controls?.ended($0) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touches.forEach { controls?.ended($0) }
    }
}
