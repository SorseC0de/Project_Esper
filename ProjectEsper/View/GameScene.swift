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

    /// The count before play, at the start and after every point.
    private static let countdownFrames = 180
    /// The on-screen pad is for a phone; the TV has a controller and nothing to touch.
    #if os(tvOS)
    private static let touchControlsShown = false
    #else
    private static let touchControlsShown = true
    #endif

    /// The match runs inside a rollback session offline as well as online, so there is
    /// one path: offline the other side's input is handed in each tick and every frame
    /// confirms at once; online the other phone's inputs arrive by frame and the sim
    /// rolls back when a prediction was wrong.
    private var session = RollbackSession(match: Match(stage: .current, countdown: GameScene.countdownFrames), localIndex: 0)
    private var match: Match { session.match }
    /// The computer on the other side, when the AI switch is on; never online.
    private var opponent = Opponent(index: 1)
    private var aiOn = true

    /// A networked series: this phone's side, the two randoms that seed the series, the
    /// pick waiting to be applied, and the rematch randoms after a win.
    private struct Online {
        var localIndex: Int
        var random: UInt32
        var theirRandom: UInt32?
        var started = false
        var helloAgainIn = 0
        var pendingPick: (round: Int, choice: Int)?
        var rematchRandom: UInt32?
        var theirRematch: UInt32?
    }
    private var online: Online?
    private var localIndex: Int { online?.localIndex ?? 0 }
    /// Who drinks this round, and the frames left to choose online.
    private var picker = 1
    private var pickFramesLeft = 0

    /// The game loop round the sim: the title, a best of seven, a drink between rounds
    /// for whoever was scored on, and the win.
    private enum Flow { case title, playing, picking, won }
    private var flow = Flow.title
    private var series = Series(seed: 1)
    private var screen: Screen?
    /// The bottles on offer while picking, kept so a re-laid-out screen shows the same.
    private var pickOffers: [Greateraid] = []
    /// A flow change held back for the strike to play, until the sim reaches this frame;
    /// online both phones stop the sim on that frame and change together.
    private var pendingFlow: Flow?
    private var pendingFlowFrame = 0
    private static let flowDelayFrames = 60
    /// Frames the bodies stay hidden while the bolts bring them in, and the count's last
    /// value, to catch it reaching zero.
    private var roundIntro = 0
    private var lastCount = 0
    /// Title lettering over the court: the count, BALL OUT, BUCKET, what the computer
    /// drank, one after another; the round circles; and each side's drinks beside them.
    private let banner = SKSpriteNode()
    private var bannerFrames = 0
    private var bannerQueue: [(text: String, size: CGFloat)] = []
    private static let bannerHold = 45
    private let circles = SKNode()
    private var drinkLabels: [SKLabelNode] = []
    private var menuLast = PlayerInput.idle
    /// The SwiftUI layer, which shows the title over the Metal view and the material
    /// under a screen.
    weak var flowState: FlowState?
    private var headVariant = HeadVariant.b
    private var powerVariant = PowerVariant.none
    private var powerLevelVariant = PowerLevelVariant.two
    private let sprites = SpriteLibrary()
    private let hub = InputHub()
    private let cameraNode = SKCameraNode()
    private let world = SKNode()
    /// The world in three layers so the glow can render the bodies on their own: the
    /// court, the bodies, and everything that glows.
    private let ground = SKNode()
    private let bodies = SKNode()
    private let glowers = SKNode()
    /// The sim's boxes drawn over the world while the HITBOX toggle is on: bodies, the
    /// loose ball, the catch reach round each chest, and any live leg, blade or reach.
    private let hitboxLayer = SKNode()
    private var showHitboxes = false
    /// The HUD lives in its own scene, drawn over the Metal view by a plain SpriteKit view
    /// so none of it glows; its children are laid out in screen points from the centre
    /// and a touch maps onto them with no arithmetic. What should glow, the round circles
    /// and the warm-up, sits in `glowHud` here, at the camera's position and scaled to
    /// cancel it, in the same points.
    let hudScene = HudScene()
    private var hud: SKNode { hudScene.hud }
    private let glowHud = SKNode()
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
    /// Blazing Boba's second charge sheet, small on the ball itself.
    private var chargeOverlays: [SKSpriteNode] = []
    private var charging: [Bool] = []
    /// A white copy of each body and head, added over them, flickering while the body is
    /// stunned by the blade.
    private var stunBodies: [SKSpriteNode] = []
    private var stunHeads: [SKSpriteNode] = []
    private var headShown: [CGPoint] = []
    /// Each body's lean in flight, radians, eased toward where it's going, and how much of
    /// the hover it's showing.
    private var bodyTilt: [CGFloat] = []
    private var hover: [CGFloat] = []
    /// What the powers leave in the world, by the sim's ids: bolts, ice clones, flames,
    /// fireballs; each player's cape, segment by segment, and the points it trails.
    private var boltNodes: [Int: SKSpriteNode] = [:]
    private var cloneNodes: [Int: SKSpriteNode] = [:]
    private var flameNodes: [Int: SKSpriteNode] = [:]
    private var fireballNodes: [Int: SKSpriteNode] = [:]
    private var capes: [[SKSpriteNode]] = []
    private var capeTrails: [[CGPoint]] = []
    private static let capeSegments = 7
    /// Each body's state last frame, to catch the skid's start.
    private var lastStates: [PlayerState] = []
    /// Effects that ride a body while they play, at an offset from its feet: the snatch's
    /// spark, so it stays on the hand however the body moves.
    private var riders: [(node: SKSpriteNode, player: Int, offset: Vec2)] = []
    /// Frames of screenshake left, and where the camera sits unshaken.
    private var shake = 0
    private var cameraBase = CGPoint.zero
    /// The HUD's scale for this screen, and the ice everything frozen goes.
    private var hudScale: CGFloat = 1
    private static let ice = SKColor(red: 0.62, green: 0.86, blue: 1, alpha: 1)
    private static let fireballColour = SKColor(red: 1, green: 0.45, blue: 0.15, alpha: 1)
    private static let flightTilt: CGFloat = .pi / 6
    /// A still flight drifts round a small circle: this radius, this many seconds a lap.
    private static let hoverRadius: CGFloat = 3
    private static let hoverSeconds = 1.6
    /// The ball in each player's hands, its glow, and the esper energy off each head.
    private var handBalls: [SKSpriteNode] = []
    private var handHalos: [SKSpriteNode] = []
    private var headEspers: [SKEmitterNode] = []
    /// A second stream off each head, for a power that mixes two particles: Frost Tea's
    /// snowflakes among the energy, Zeus Juice's second bolt.
    private var headEsperMixes: [SKEmitterNode] = []
    private var wings: [Wing] = []
    /// Each player's webs: the swing's and the shot's.
    private var swingWebs: [SKShapeNode] = []
    private var shotWebs: [SKShapeNode] = []
    /// Each player's made platform.
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
    /// A score's flash on the floor and walls: frames until it, then how white they are, fading.
    private var courtWhiteIn = 0
    private var courtWhite: CGFloat = 0
    private var rimNodes: [SKSpriteNode] = []
    private var rimFlash: [Int] = []
    private var previewDots: [SKSpriteNode] = []
    private let scoreLabel = SKLabelNode()
    private let debugLabel = SKLabelNode()
    /// The local side's power and level, lettered top-left under the pickers.
    private let powerLabel = SKSpriteNode()
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
        playerNodes.filter { !$0.isHidden }.compactMap { node in
            node.texture.map { BodySnapshot(texture: $0, position: node.position, anchor: node.anchorPoint, xScale: node.xScale, size: node.size) }
        }
    }

    /// What's drawn in the world but must not glow, for the mask to mark: the banner.
    var flatSnapshots: [BodySnapshot] {
        guard !banner.isHidden, let texture = banner.texture else { return [] }
        let scale = glowHud.xScale
        return [BodySnapshot(texture: texture,
                             position: CGPoint(x: glowHud.position.x + banner.position.x * scale, y: glowHud.position.y + banner.position.y * scale),
                             anchor: banner.anchorPoint, xScale: 1,
                             size: CGSize(width: banner.size.width * scale, height: banner.size.height * scale))]
    }

    // MARK: Ball cam

    /// Only in play: not on the title, the drink pick or the win.
    var ballCamEnabled: Bool { match.stage.features.ballCam && playing && flow == .playing }
    private var playing: Bool { built && !playerNodes.isEmpty }

    /// Where the ball is, in art pixels, held or loose.
    var ballCamCentre: CGPoint {
        let ball = match.ball
        let at = ball.holder.map { match.players[$0].chest + Vec2(x: 0, y: 3) } ?? ball.position
        return SpriteLibrary.point(at)
    }

    /// Flashes lining the cam's edges, in the HUD over it, each on its own frame.
    private var ballCamFrame = SKNode()
    private var ballCamFrameSparks: [(node: SKSpriteNode, edge: Int, share: CGFloat)] = []

    private func buildBallCamFrame() {
        ballCamFrame.removeFromParent()
        ballCamFrame = SKNode()
        ballCamFrame.zPosition = 1
        ballCamFrameSparks = []
        let frames = sprites.effectFrames(EnergyEffect.flashSpark2, player: localIndex)
        let count = frames.count
        // Edges: top, right, bottom, left, round the trapezoid's corners.
        let perEdge = [9, 4, 8, 4]
        for (edge, sparks) in perEdge.enumerated() {
            for step in 0..<sparks {
                let spark = SKSpriteNode(texture: frames[0])
                spark.setScale(BackboardTuning.size)
                spark.alpha = BallCamScene.opacity
                let start = (edge * 5 + step * 7) % max(count, 1)
                let looped: [SKTexture] = Array(frames[start...]) + Array(frames[..<start])
                spark.run(SKAction.repeatForever(SKAction.animate(with: looped, timePerFrame: 1.0 / 24)))
                ballCamFrame.addChild(spark)
                ballCamFrameSparks.append((spark, edge, CGFloat(step) / CGFloat(sparks)))
            }
        }
        hudScene.addChild(ballCamFrame)
    }

    /// The flashes along the trapezoid as it sits now, in the HUD's points.
    private func placeBallCamFrame() {
        guard ballCamEnabled, size.width > 0 else { ballCamFrame.isHidden = true; return }
        if ballCamFrameSparks.isEmpty { buildBallCamFrame() }
        ballCamFrame.isHidden = false
        let corners = BallCamScene.corners(centre: ballCamScreenX * 2 - 1, screenAspect: size.width / size.height)
            .map { CGPoint(x: $0.x * size.width / 2, y: $0.y * size.height / 2) }
        // Round the outline clockwise from the top left.
        let ring = [corners[0], corners[1], corners[3], corners[2]]
        for spark in ballCamFrameSparks {
            let from = ring[spark.edge], to = ring[(spark.edge + 1) % 4]
            spark.node.position = CGPoint(x: from.x + (to.x - from.x) * spark.share, y: from.y + (to.y - from.y) * spark.share)
        }
    }

    /// The cam's middle across the screen, 0 to 1, easing after the local player.
    private(set) var ballCamScreenX: CGFloat = 0.5
    private func easeBallCam() {
        guard match.players.indices.contains(localIndex), size.width > 0 else { return }
        let feet = SpriteLibrary.point(match.players[localIndex].position)
        let onScreen = (feet.x - cameraNode.position.x) / (size.width * cameraNode.xScale) + 0.5
        let wanted = min(max(onScreen, 0.2), 0.8)
        ballCamScreenX += (wanted - ballCamScreenX) * 0.1
    }

    /// Everything that moves and is drawn near the ball, for the ball cam to copy: every
    /// sprite in the bodies and effects layers and the shadows, but only those within its
    /// window round the ball, with a margin for the ones that straddle its edge. The rest
    /// are passed over after one position check each, so a busy field costs it little.
    var ballCamSnapshots: [SpriteSnapshot] {
        let centre = ballCamCentre
        let margin: CGFloat = 64
        let window = CGRect(x: centre.x - BallCamScene.view.width / 2 - margin, y: centre.y - BallCamScene.view.height / 2 - margin,
                            width: BallCamScene.view.width + margin * 2, height: BallCamScene.view.height + margin * 2)
        var snapshots: [SpriteSnapshot] = []
        func take(_ node: SKNode, offset: CGPoint, z: CGFloat, alpha: CGFloat) {
            guard !node.isHidden else { return }
            let at = CGPoint(x: offset.x + node.position.x, y: offset.y + node.position.y)
            let depth = z + node.zPosition
            if let sprite = node as? SKSpriteNode, let texture = sprite.texture {
                guard window.contains(at) else { return }
                let xScale = sprite.xScale == 0 ? 1 : sprite.xScale, yScale = sprite.yScale == 0 ? 1 : sprite.yScale
                snapshots.append(SpriteSnapshot(texture: texture, position: at, anchor: sprite.anchorPoint,
                                                size: CGSize(width: sprite.size.width / abs(xScale), height: sprite.size.height / abs(yScale)),
                                                xScale: sprite.xScale, yScale: sprite.yScale, zRotation: sprite.zRotation,
                                                colour: sprite.color, colourBlend: sprite.colorBlendFactor, alpha: alpha * sprite.alpha,
                                                zPosition: depth, blendMode: sprite.blendMode, shader: sprite.shader, warp: sprite.warpGeometry))
            }
            // A plain container (a flash cluster, the backboards) passes its place on; it's
            // skipped whole when it and its reach are nowhere near.
            guard !node.children.isEmpty, !(node is SKSpriteNode) || node.children.count > 0 else { return }
            if !(node is SKSpriteNode), node !== glowers, node !== bodies, node.position != .zero,
               !window.insetBy(dx: -200, dy: -200).contains(at) { return }
            for child in node.children { take(child, offset: at, z: depth, alpha: alpha * node.alpha) }
        }
        take(bodies, offset: .zero, z: 0, alpha: 1)
        take(glowers, offset: .zero, z: 0, alpha: 1)
        for shadow in shadowBodies + shadowHeads { take(shadow, offset: .zero, z: 0, alpha: 1) }
        return snapshots
    }

    /// The field's scenery and goalposts into the ball cam's own scene, once.
    func fillBallCam(_ camScene: BallCamScene) {
        guard !camScene.built, match.stage.features.ballCam else { return }
        camScene.built = true
        _ = FieldArt.build(for: match.stage, into: camScene.scenery, flat: { [sprites] size in sprites.flatSquare(size: Int(size), alpha: 1) },
                           glow: sprites.softGlow(diameter: 64))
        for hoop in match.stage.hoops {
            let postX = hoop.backboard == .left ? Stage.fieldPostInset : match.stage.width - Stage.fieldPostInset
            FieldArt.goalpost(at: SpriteLibrary.point(Vec2(x: postX, y: GoalpostTuning.postRimHeight)), backboard: hoop.backboard, into: camScene.scenery,
                              crossbarBelowRim: GoalpostTuning.crossbarBelowRim, prongHeight: GoalpostTuning.prongHeight,
                              angle: GoalpostTuning.crossbarAngle * .pi / 180, thickness: GoalpostTuning.thickness, outline: GoalpostTuning.outline,
                              padColour: SKColor(rgb: CourtLook.shaded(sprites.look(for: 1 - hoop.owner).glow)))
            let rim = SKSpriteNode(texture: sprites.texture("hoop_rim", 0))
            rim.position = SpriteLibrary.point(hoop.position)
            rim.xScale = hoop.backboard == .left ? -1 : 1
            rim.zPosition = 5
            camScene.scenery.addChild(rim)
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
        hudScene.size = size
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
        hitboxLayer.zPosition = 30
        world.addChild(hitboxLayer)
        camera = cameraNode
        addChild(cameraNode)
        glowHud.zPosition = 100
        addChild(glowHud)

        // Every frame in both looks, made before anything is drawn, then drawn once each.
        sprites.warmUp(players: match.players.count) { [weak self] in self?.preloaded = true }
        for texture in sprites.allTextures {
            let sprite = SKSpriteNode(texture: texture)
            sprite.size = CGSize(width: 1, height: 1)
            sprite.alpha = 0.02
            warmNode.addChild(sprite)
        }
        warmNode.zPosition = 90
        glowHud.addChild(warmNode)

        // The floor and walls take the holder's colour, the backboard blocks keep their rim's
        // owner's, and the ledge is magenta.
        let stage = match.stage
        if stage.features.look == .highway {
            HighwayArt.build(for: stage, into: ground) { [sprites] size in sprites.flatSquare(size: Int(size), alpha: 1) }
        }
        if stage.features.look == .footballField {
            // The field: scenery in place of tiles, the floor invisible through the turf.
            let handles = FieldArt.build(for: stage, into: ground, flat: { [sprites] size in sprites.flatSquare(size: Int(size), alpha: 1) },
                                         glow: sprites.softGlow(diameter: 64))
            // The rail and the floodlights wear the possession's colour like the court's walls.
            for rail in handles.rails {
                rail.color = courtColour
                courtTiles.append(rail)
            }
            fieldBlooms = handles.blooms
            lightPanels = handles.panels
            for panel in lightPanels { panel.fillColor = courtColour }
            yardNumbers = handles.numbers
            for number in yardNumbers { number.setScale(HelmetTuning.numberScale) }
            for bloom in fieldBlooms { bloom.color = courtColour }
            // Chevrons along the rail, pointing at the rim the holder attacks.
            for (rail, line) in FieldArt.railLines.enumerated() {
                var callX: CGFloat = 0
                while callX < CGFloat(stage.columns) * GameScene.pixelsPerTile + GameScene.railCallSpacing {
                    let call = TitleText.node(GameScene.railCall, size: 7)
                    call.position = CGPoint(x: callX, y: line + FieldArt.railHeight / 2)
                    call.zPosition = -16
                    call.isHidden = true
                    ground.addChild(call)
                    railCalls.append((call, rail, callX))
                    callX += GameScene.railCallSpacing
                }
                var x: CGFloat = 8
                while x < CGFloat(stage.columns) * GameScene.pixelsPerTile {
                    let chevron = SKSpriteNode(texture: sprites.symbol("chevron.right", pointSize: 9))
                    chevron.color = SKColor(white: 1, alpha: 1)
                    chevron.colorBlendFactor = 1
                    chevron.alpha = 0.55
                    chevron.position = CGPoint(x: x, y: line + FieldArt.railHeight / 2)
                    chevron.zPosition = -16
                    chevron.isHidden = true
                    ground.addChild(chevron)
                    railChevrons.append(chevron)
                    railChevronHomes.append(x)
                    x += 14
                }
            }
            goalpostShadows.shouldRasterize = true
            goalpostShadows.alpha = FieldArt.shadowAlpha
            goalpostShadows.zPosition = -6
            ground.addChild(goalpostShadows)
            ground.addChild(goalposts)
            buildGoalposts()
            glowers.addChild(backboards)
            buildBackboards()
        }
        for row in 0..<(stage.rows + Stage.skyRows) where !stage.features.scenic {
            for column in 0..<stage.columns {
                // The side walls run on up through the sky, so a tall screen never sees their top.
                let tile = row < stage.rows ? stage.tile(column: column, row: row) : ((column == 0 || column == stage.columns - 1) ? Tile.solid : Tile.empty)
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
            // Drawn round nothing and placed, so it can follow a rim that moves.
            let hanging = net(at: .zero)
            hanging.position = rim.position
            ground.addChild(hanging)
            netNodes.append(hanging)
        }

        for player in match.players {
            let node = SKSpriteNode(texture: sprites.texture(player.animationFrame, player: player.index))
            bodies.addChild(node)
            playerNodes.append(node)
            for shadows in [\GameScene.shadowBodies, \GameScene.shadowHeads] {
                let shadow = SKSpriteNode()
                shadow.shader = shadowShader
                shadow.alpha = FieldArt.shadowAlpha
                shadow.zPosition = -6
                shadow.isHidden = true
                ground.addChild(shadow)
                self[keyPath: shadows].append(shadow)
            }
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
            let overlay = SKSpriteNode()
            overlay.zPosition = 6
            overlay.isHidden = true
            glowers.addChild(overlay)
            chargeOverlays.append(overlay)
            charging.append(false)
            for flashes in [\GameScene.stunBodies, \GameScene.stunHeads] {
                // Stunned, the body flickers to a dark shade of its energy.
                let flash = SKSpriteNode()
                flash.color = SKColor(rgb: sprites.look(for: player.index).energyTone(luminance: 0.15))
                flash.colorBlendFactor = 1
                flash.blendMode = .alpha
                flash.alpha = 0.85
                flash.zPosition = 9
                flash.isHidden = true
                glowers.addChild(flash)
                self[keyPath: flashes].append(flash)
            }
            headShown.append(.zero)
            bodyTilt.append(0)
            hover.append(0)
            lastStates.append(.idle)
            // Super Smoothie's cape: short rectangles in the energy colour, chained.
            var segments: [SKSpriteNode] = []
            for step in 0..<GameScene.capeSegments {
                let segment = SKSpriteNode(texture: sprites.flatSquare(size: 4, alpha: 1))
                segment.size = CGSize(width: 7, height: max(5 - CGFloat(step) / 2, 2))
                segment.color = SKColor(rgb: sprites.look(for: player.index).glow)
                segment.colorBlendFactor = 1
                segment.blendMode = .add
                segment.alpha = 0.9 - CGFloat(step) * 0.1
                segment.zPosition = 2
                segment.isHidden = true
                glowers.addChild(segment)
                segments.append(segment)
            }
            capes.append(segments)
            capeTrails.append([])
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
            let esper = makeEsper(colour)
            esper.particleBirthRate = 0
            esper.targetNode = glowers
            glowers.addChild(esper)
            headEspers.append(esper)
            let mix = makeEsper(colour)
            mix.zPosition = 1
            mix.targetNode = glowers
            mix.particleBirthRate = 0
            glowers.addChild(mix)
            headEsperMixes.append(mix)
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
        scoreLabel.isHidden = true
        hud.addChild(scoreLabel)

        // The banner is in the world, under the material, so the count shows through a
        // screen; the mask keeps it out of the glow.
        banner.zPosition = 5
        banner.isHidden = true
        glowHud.addChild(banner)
        circles.zPosition = 5
        glowHud.addChild(circles)
        for index in 0..<2 {
            let label = SKLabelNode()
            label.fontName = "Menlo-Bold"
            label.fontSize = 8
            label.fontColor = SKColor(rgb: sprites.look(for: index).glow)
            label.horizontalAlignmentMode = index == 0 ? .right : .left
            label.verticalAlignmentMode = .top
            label.numberOfLines = 0
            label.zPosition = 5
            hud.addChild(label)
            drinkLabels.append(label)
        }
        drawSeries()
        flowState?.startSeries = { [weak self] in self?.startSeries() }
        flowState?.net.onConnected = { [weak self] in self?.startOnline() }
        flowState?.net.onData = { [weak self] data in self?.handle(data) }
        flowState?.net.onDisconnect = { [weak self] why in self?.endOnline(why) }

        powerLabel.anchorPoint = CGPoint(x: 0, y: 1)
        powerLabel.zPosition = 5
        hud.addChild(powerLabel)

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

    /// Esper energy rising off a head: fire-like but of no element; bits in the colour
    /// that step down in size as they go, a digital dissolve.
    private func makeEsper(_ colour: SKColor) -> SKEmitterNode {
        let esper = SKEmitterNode()
        // The hard square, or a frame of the spark scaled down to the square's size.
        esper.particleTexture = ParticleLook.sprites ? sprites.texture("esper_particle", (EffectSheets.frames["esper_particle"] ?? 1) / 3) : sprites.flatSquare(size: 4, alpha: 1)
        esper.particleBirthRate = 40
        esper.particleLifetime = 0.6
        esper.particleLifetimeRange = 0.1
        esper.particlePositionRange = CGVector(dx: 2, dy: 1)
        esper.particleSpeed = 24
        esper.particleSpeedRange = 4
        esper.emissionAngle = .pi / 2
        esper.emissionAngleRange = .pi / 14
        esper.yAcceleration = 10
        esper.particleSize = CGSize(width: ParticleLook.energySize, height: ParticleLook.energySize)
        if ParticleLook.sprites { esper.particleRotationRange = .pi * 2 }
        let steps = SKKeyframeSequence(keyframeValues: [1, 0.66, 0.33], times: [0, 0.45, 0.75])
        steps.interpolationMode = .step
        esper.particleScaleSequence = steps
        let fade = SKKeyframeSequence(keyframeValues: [0.9, 0.9, 0.5, 0], times: [0, 0.6, 0.85, 1])
        fade.interpolationMode = .step
        esper.particleAlphaSequence = fade
        esper.particleColor = colour
        esper.particleColorBlendFactor = 1
        // Drawn over, not added: hard squares added on top of the head saturate to white.
        esper.particleBlendMode = .alpha
        return esper
    }

    /// The floor and walls shift toward whoever holds the ball, or whose it still is in
    /// the air until its first bounce, and back to neutral; on a score they go white with
    /// the bolt's flash and fade back.
    private func tickCourtColour() {
        let owner = match.ball.holder ?? match.ball.owner
        let wanted = owner.map { SKColor(rgb: CourtLook.shaded(sprites.look(for: $0).glow)) } ?? SKColor(rgb: CourtLook.neutral)
        if wanted != courtTarget {
            courtTarget = wanted
            courtShift = CourtLook.shiftFrames
        }
        var changed = false
        if courtShift > 0 {
            courtShift -= 1
            let share = 1 / CGFloat(courtShift + 1)
            var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
            var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
            courtColour.getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
            courtTarget.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
            courtColour = SKColor(red: cr + (tr - cr) * share, green: cg + (tg - cg) * share, blue: cb + (tb - cb) * share, alpha: 1)
            changed = true
        }
        if courtWhiteIn > 0 {
            courtWhiteIn -= 1
            if courtWhiteIn == 0 {
                courtWhite = 1
                changed = true
            }
        } else if courtWhite > 0 {
            courtWhite = max(courtWhite - 1 / CGFloat(CourtLook.strikeFadeFrames), 0)
            changed = true
        }
        guard changed else { return }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        courtColour.getRed(&r, green: &g, blue: &b, alpha: &a)
        let shown = SKColor(red: r + (1 - r) * courtWhite, green: g + (1 - g) * courtWhite, blue: b + (1 - b) * courtWhite, alpha: 1)
        for tile in courtTiles { tile.color = shown }
        for bloom in fieldBlooms { bloom.color = shown }
        for panel in lightPanels { panel.fillColor = shown }
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
        let scrolls = match.stage.features.look == .footballField
        // The field scrolls sideways, so only its height is fitted; a scenic stage counts the
        // ground below the floor in, so the players stand in the middle of it.
        let below = match.stage.features.scenic ? FieldArt.viewBelowFloor : 0
        let stageHeight = CGFloat(match.stage.rows) * GameScene.pixelsPerTile + below
        let fitHeight = (screenScale * size.height / stageHeight).rounded(.down)
        let fitWidth = (screenScale * size.width / stageWidth).rounded(.down)
        let screenPixelsPerGamePixel = max(1, scrolls ? fitHeight : min(fitHeight, fitWidth))
        let pointsPerGamePixel = screenPixelsPerGamePixel / screenScale
        cameraNode.setScale(1 / pointsPerGamePixel)
        cameraNode.position = CGPoint(x: scrolls ? cameraBase.x : stageWidth / 2, y: stageHeight / 2 - below)
        if scrolls, cameraBase.x == 0 { cameraNode.position.x = cameraTargetX() }
        cameraBase = cameraNode.position
        // The HUD is laid out in the phone's points and scaled up for a bigger screen.
        hudScale = HudScene.scale(forHeight: size.height)
        TitleText.renderScale = hudScale
        hud.setScale(hudScale)
        glowHud.position = cameraNode.position
        glowHud.setScale(cameraNode.xScale * hudScale)

        let halfWidth = size.width / 2 / hudScale
        let halfHeight = size.height / 2 / hudScale
        let insets = UIEdgeInsets(top: safeInsets.top / hudScale, left: safeInsets.left / hudScale,
                                  bottom: safeInsets.bottom / hudScale, right: safeInsets.right / hudScale)
        controls?.removeFromParent()
        let controls = TouchControls(halfWidth: halfWidth, halfHeight: halfHeight, insets: insets)
        controls.onReset = { [weak self] in self?.reset() }
        controls.showHitboxes = showHitboxes
        controls.onToggleHitboxes = { [weak self] on in self?.showHitboxes = on }
        controls.aiOn = aiOn
        controls.onToggleAI = { [weak self] on in self?.aiOn = on }
        controls.addPicker(title: "HEAD", options: HeadVariant.allCases.map(\.label), selected: headVariant.rawValue) { [weak self] index in
            self?.headVariant = HeadVariant(rawValue: index)!
        }
        controls.addPicker(title: "POWER", options: PowerVariant.allCases.map(\.label), selected: powerVariant.rawValue) { [weak self] index in
            self?.powerVariant = PowerVariant(rawValue: index)!
            self?.applyPower()
        }
        controls.addPicker(title: "LEVEL", options: PowerLevelVariant.allCases.map(\.label), selected: powerLevelVariant.rawValue) { [weak self] index in
            self?.powerLevelVariant = PowerLevelVariant(rawValue: index)!
            self?.applyPower()
        }
        if DunkTuning.enabled {
            let last = Float(Animation.dunkSequence.count - 1)
            let xSlider = controls.addSlider(title: "DUNK X", range: -32...32, notch: 1, value: Float(DunkArt.offsets[DunkTuning.frame].x)) {
                DunkArt.offsets[DunkTuning.frame].x = CGFloat($0)
            }
            let ySlider = controls.addSlider(title: "DUNK Y", range: -32...32, notch: 1, value: Float(DunkArt.offsets[DunkTuning.frame].y)) {
                DunkArt.offsets[DunkTuning.frame].y = CGFloat($0)
            }
            controls.addSlider(title: "DUNK FRAME", range: 0...last, notch: 1, value: Float(DunkTuning.frame)) { value in
                DunkTuning.frame = Int(value)
                xSlider.set(Float(DunkArt.offsets[DunkTuning.frame].x))
                ySlider.set(Float(DunkArt.offsets[DunkTuning.frame].y))
            }
        }
        controls.setOnline(online != nil)
        controls.isHidden = !GameScene.touchControlsShown
        hud.addChild(controls)
        self.controls = controls
        scoreLabel.position = CGPoint(x: 0, y: halfHeight - insets.top - 8)
        circles.position = CGPoint(x: 0, y: halfHeight - insets.top - 16)
        drawSeries()
        presentScreen()
        powerLabel.position = CGPoint(x: -halfWidth + insets.left + TouchControls.padding, y: controls.pickerBottom - 4)
        debugLabel.position = CGPoint(x: -halfWidth + insets.left + TouchControls.padding, y: controls.pickerBottom - 26)
        fpsLabel.position = CGPoint(x: -halfWidth + insets.left + TouchControls.padding, y: -halfHeight + insets.bottom + TouchControls.padding)
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
        if DunkTuning.enabled {
            holdDunkPose()
            render()
            return
        }
        accumulator += min(currentTime - last, 0.1)
        guard accumulator >= GameScene.stepSeconds else { return }

        if let next = pendingFlow, match.frame >= pendingFlowFrame {
            pendingFlow = nil
            enter(next)
        }
        if roundIntro > 0 { roundIntro -= 1 }
        hub.touch = flow == .playing ? controls?.sample() ?? .idle : .idle
        let inputs = hub.frames(players: match.players.count)
        tickOnline()
        if flow != .playing {
            // A screen is up: the stick moves its cursor and jump picks; the sim waits. On
            // the title, which the SwiftUI layer draws, jump starts the series.
            let pad = inputs.first ?? .idle
            if let screen {
                if pad.stick.x >= 0.5, menuLast.stick.x < 0.5 { screen.move(1) }
                if pad.stick.x <= -0.5, menuLast.stick.x > -0.5 { screen.move(-1) }
                if pad.stick.y <= -0.5, menuLast.stick.y > -0.5 { screen.move(1) }
                if pad.stick.y >= 0.5, menuLast.stick.y < 0.5 { screen.move(-1) }
                if pad.jump, !menuLast.jump { screen.fire() }
            } else if flow == .title, pad.jump, !menuLast.jump, online == nil {
                startSeries()
            }
            menuLast = pad
            accumulator = 0
            // Online the session ticks in place while a screen is up, so the last inputs
            // cross and the other side's arrive.
            if online?.started == true {
                _ = session.tick(local: .idle)
                send(.inputs(session.outgoing()), reliable: false)
            }
            tickBallColour()
            tickCourtColour()
            render()
            return
        }
        if online == nil, hub.consumeReset() { reset() }
        if hub.consumeCycle() { controls?.cycleTopPicker() }
        if online == nil, hub.consumeAIToggle() {
            aiOn.toggle()
            controls?.aiOn = aiOn
        }
        if hub.consumeHitboxToggle() {
            showHitboxes.toggle()
            controls?.showHitboxes = showHitboxes
        }
        var steps = 0
        while accumulator >= GameScene.stepSeconds, steps < GameScene.maxStepsPerFrame {
            let tick: SessionTick
            if online != nil {
                tick = session.tick(local: inputs[0])
                send(.inputs(session.outgoing()), reliable: false)
            } else {
                var remote = inputs.count > 1 ? inputs[1] : .idle
                if aiOn, !hub.playerTwoHasController { remote = opponent.decide(match) }
                tick = session.tick(local: inputs[0], remote: remote)
            }
            show(tick.shown)
            confirm(tick.confirmed)
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

    /// The dunk tuning pose: the match held still, player 1 hanging on the right rim at the
    /// sliders' offset, facing the backboard, the ball out of the way.
    private func holdDunkPose() {
        let hoop = match.stage.hoops.first { $0.owner == 0 } ?? match.stage.hoops[0]
        flowState?.showsTitle = false
        screen?.removeFromParent()
        screen = nil
        controls?.isHidden = !GameScene.touchControlsShown
        session.mutate { match in
            match.countdown = 0
            match.players[0].position = hoop.position + Vec2(x: BallRules.dunkOffset.x * hoop.backboard.sign, y: BallRules.dunkOffset.y)
            match.players[0].facing = hoop.backboard
            match.players[0].hasBall = DunkTuning.frame < 3
            match.players[0].state = .dunking
            match.players[0].stateTimer = Animation.dunkStart(of: DunkTuning.frame)
            match.ball.holder = match.players[0].hasBall ? 0 : nil
            if match.ball.holder == nil { match.ball.respawn(at: Vec2(x: 170, y: 12.5)) }
        }
        let table = DunkArt.offsets.map { "(\(Int($0.x)), \(Int($0.y)))" }.joined(separator: " ")
        debugLabel.text = "dunk frame \(DunkTuning.frame)  offsets \(table)"
    }

    /// The round again from the start, drinks kept. Offline only.
    private func reset() {
        guard online == nil else { return }
        startRound()
    }

    // MARK: The game loop

    /// A new best of seven against the computer: the drinks gone, the dice rolled on,
    /// the first round.
    private func startSeries() {
        guard online == nil else { return }
        startSeries(seed: UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970)))
    }

    private func startSeries(seed: UInt32) {
        series = Series(seed: seed)
        startRound()
        enter(.playing)
    }

    /// A round: bodies with their drinks in them at their spawns, the count, and the
    /// bolts that bring them in.
    private func startRound() {
        // The field's dice and coin flip come off the series' dice, the same on both phones.
        let fieldSeed = UInt32(series.dice.roll(1 << 16)) &+ 1
        var fresh = Match(stage: .current, specs: series.drinks.map { $0.spec() }, countdown: GameScene.countdownFrames, seed: fieldSeed)
        for index in fresh.players.indices {
            fresh.players[index].power = series.drinks[index].power
            fresh.players[index].powerLevel = series.drinks[index].powerLevel
        }
        if online == nil, powerVariant != .none {
            for index in fresh.players.indices {
                fresh.players[index].power = powerVariant.power
                fresh.players[index].powerLevel = powerLevelVariant.level
            }
        }
        session = RollbackSession(match: fresh, localIndex: localIndex, delay: online == nil ? 0 : NetRules.inputDelay)
        controls?.setOnline(online != nil)
        opponent = Opponent(index: 1)
        rimFlash = rimFlash.map { _ in 0 }
        ballTeam = SKColor(rgb: BallLook.neutral)
        ballHold = 0
        ballShift = 0
        lastCount = match.countdown
        drawSeries()
        bringPlayersIn()
    }

    /// The drinks onto the bodies as they stand, for the round about to count. The POWER
    /// picker's choice, offline, stands over the drinks.
    private func applyDrinks() {
        let drinks = series.drinks
        let picked = online == nil && powerVariant != .none ? powerVariant.power : nil
        session.mutate { match in
            for index in match.players.indices {
                match.players[index].spec = drinks[index].spec()
                match.players[index].power = picked ?? drinks[index].power
                match.players[index].powerLevel = picked == nil ? drinks[index].powerLevel : powerLevelVariant.level
            }
        }
    }

    /// Both bodies struck in at their spawns by a bolt and the crown in their colours,
    /// hidden until the flash.
    private func bringPlayersIn() {
        roundIntro = 12
        let top = cameraNode.position.y + size.height * cameraNode.yScale / 2
        for player in match.players {
            let point = SpriteLibrary.point(player.position)
            let bolt = EnergyEffect.strikes.randomElement()!.node(sprites, player: player.index, at: point)
            bolt.zPosition = 45
            bolt.yScale = max((top - point.y) * 1.1, 64) / bolt.size.height
            glowers.addChild(bolt)
            let crown = EnergyEffect.spark3.node(sprites, player: player.index, at: point)
            crown.zPosition = 46
            glowers.addChild(crown)
        }
    }

    /// A point, confirmed on both sides: the round to the scorer. The winner's screen
    /// after the strike; otherwise whoever was scored on drinks, the computer at once
    /// and a person on the pick screen once the strike has played. Online the sim stops
    /// on the same frame on both phones for the screen.
    private func pointScored(by scorer: Int, at frame: Int) {
        guard flow == .playing else { return }
        series.record(pointFor: scorer)
        drawSeries()
        if series.winner != nil {
            pendingFlow = .won
            pendingFlowFrame = frame + GameScene.flowDelayFrames
        } else if online == nil, scorer == 0 {
            let offers = series.offers(for: 1)
            let drink = offers[series.dice.roll(offers.count)]
            series.drink(drink, by: 1)
            applyDrinks()
            drawSeries()
            bringPlayersIn()
            bannerQueue.append(("\(sideName(1)) DRINKS \(drink.name.uppercased())", 26))
        } else {
            picker = 1 - scorer
            pendingFlow = .picking
            pendingFlowFrame = frame + GameScene.flowDelayFrames
        }
        if online != nil, pendingFlow != nil { session.stopAt = pendingFlowFrame }
    }

    private func enter(_ next: Flow) {
        // The ball cam's edge is in the HUD, so it goes with the screens that aren't play.
        ballCamFrame.isHidden = next != .playing
        flow = next
        if next == .picking {
            // Both phones roll the same offers off the shared dice.
            pickOffers = series.offers(for: picker)
            pickFramesLeft = Series.pickSeconds * 60
        }
        flowState?.showsTitle = next == .title
        presentScreen()
    }

    private func sideName(_ index: Int) -> String {
        index == 0 ? "ORANGE" : "TEAL"
    }

    /// The pick, ours: applied at once offline, sent and then applied once the sim has
    /// settled online.
    private func choose(_ drink: Greateraid) {
        guard let choice = pickOffers.firstIndex(of: drink) else { return }
        if online != nil {
            guard online?.pendingPick == nil else { return }
            online?.pendingPick = (series.rounds.count, choice)
            send(.pick(round: series.rounds.count, choice: choice), reliable: true)
        } else {
            applyPick(choice: choice)
        }
    }

    /// The round's drink onto the body, the count again, and play on.
    private func applyPick(choice: Int) {
        guard flow == .picking, pickOffers.indices.contains(choice) else { return }
        let drink = pickOffers[choice]
        series.drink(drink, by: picker)
        applyDrinks()
        drawSeries()
        session.mutate { $0.countdown = $0.countdownLength }
        session.stopAt = nil
        lastCount = match.countdown
        bringPlayersIn()
        if picker != localIndex {
            bannerQueue.append(("\(sideName(picker)) DRINKS \(drink.name.uppercased())", 26))
        }
        enter(.playing)
    }

    /// NEW MATCH offline; REMATCH online, which starts once both sides have pressed it.
    private func playAgain() {
        guard online != nil else {
            startSeries()
            return
        }
        guard online?.rematchRandom == nil else { return }
        let random = UInt32.random(in: .min ... .max)
        online?.rematchRandom = random
        send(.rematch(random: random), reliable: true)
        (screen as? WinScreen)?.showWaiting()
        startRematchIfBothIn()
    }

    private func startRematchIfBothIn() {
        guard let mine = online?.rematchRandom, let theirs = online?.theirRematch else { return }
        online?.rematchRandom = nil
        online?.theirRematch = nil
        startSeries(seed: mine ^ theirs)
    }

    private func leaveToTitle() {
        if online != nil {
            send(.bye, reliable: true)
            endOnline(nil)
        } else {
            enter(.title)
        }
    }

    /// The screen for the flow, built for the view's size.
    private func presentScreen() {
        screen?.removeFromParent()
        screen = nil
        let halfWidth = size.width / 2 / hudScale, halfHeight = size.height / 2 / hudScale
        switch flow {
        case .title:
            // The SwiftUI layer draws the title.
            break
        case .picking:
            if picker == localIndex {
                screen = PickScreen(halfWidth: halfWidth, halfHeight: halfHeight, offers: pickOffers, drinks: series.drinks[picker],
                                    colour: SKColor(rgb: sprites.look(for: picker).glow), timed: online != nil) { [weak self] drink in
                    self?.choose(drink)
                }
            } else {
                screen = WaitScreen(halfWidth: halfWidth, halfHeight: halfHeight, who: sideName(picker))
            }
        case .won:
            let winner = series.winner ?? 0
            screen = WinScreen(halfWidth: halfWidth, halfHeight: halfHeight, winner: sideName(winner),
                               again: online == nil ? "NEW MATCH" : "REMATCH",
                               onAgain: { [weak self] in self?.playAgain() },
                               onTitle: { [weak self] in self?.leaveToTitle() })
            if online?.rematchRandom != nil { (screen as? WinScreen)?.showWaiting() }
        case .playing:
            break
        }
        if let screen { hud.addChild(screen) }
        controls?.isHidden = flow != .playing || !GameScene.touchControlsShown
        flowState?.veiled = screen != nil
    }

    /// The rounds across the top: five circles in dark purple, filled in the round
    /// winner's colour as they go, a sixth and seventh added if the series gets there;
    /// and to either side of them each side's drinks, with their levels.
    private func drawSeries() {
        for (index, label) in drinkLabels.enumerated() where index < series.drinks.count {
            let drinks = series.drinks[index]
            var lines: [String] = []
            for booster in Greateraid.boosters where drinks.level(of: booster) > 0 {
                lines.append(drinks.level(of: booster) > 1 ? "\(booster.name) ×2" : booster.name)
            }
            if let biomorph = drinks.biomorph {
                lines.append(drinks.biomorphLevel > 1 ? "\(biomorph.name) L2" : biomorph.name)
            }
            label.text = lines.joined(separator: "\n")
        }
        circles.removeAllChildren()
        let count = series.circles
        let spacing: CGFloat = 18
        let radius: CGFloat = 6
        let halfRow = CGFloat(count - 1) / 2 * spacing + radius
        for (index, label) in drinkLabels.enumerated() {
            label.position = CGPoint(x: (halfRow + 8) * (index == 0 ? -1 : 1), y: circles.position.y + radius)
        }
        for index in 0..<count {
            let circle = SKShapeNode(circleOfRadius: radius)
            circle.position = CGPoint(x: (CGFloat(index) - CGFloat(count - 1) / 2) * spacing, y: 0)
            circle.fillColor = index < series.rounds.count ? SKColor(rgb: sprites.look(for: series.rounds[index]).glow) : SKColor(rgb: 0x3A2A48)
            circle.strokeColor = SKColor(white: 0, alpha: 0.6)
            circle.lineWidth = 1
            circles.addChild(circle)
        }
    }

    private func showBanner(_ text: String, size: CGFloat) {
        TitleText.set(banner, to: text, size: size)
        banner.isHidden = false
        bannerFrames = GameScene.bannerHold
    }

    /// The next queued banner, once the one up has had its frames.
    private func tickBanner() {
        guard bannerFrames > 0 else {
            if !bannerQueue.isEmpty, banner.isHidden {
                let next = bannerQueue.removeFirst()
                showBanner(next.text, size: next.size)
            }
            return
        }
        bannerFrames -= 1
        if bannerFrames == 0 {
            banner.isHidden = true
            if !bannerQueue.isEmpty {
                let next = bannerQueue.removeFirst()
                showBanner(next.text, size: next.size)
            }
        }
    }

    /// The picker's power onto both players, live. Offline only.
    private func applyPower() {
        guard online == nil else { return }
        let power = powerVariant.power
        let level = powerLevelVariant.level
        session.mutate { match in
            for index in match.players.indices {
                match.players[index].power = power
                match.players[index].powerLevel = level
            }
        }
    }

    // MARK: Online

    /// Both phones are connected: this side's place by Game Center's ordering, and hello
    /// goes out until theirs is in.
    private func startOnline() {
        guard let net = flowState?.net else { return }
        online = Online(localIndex: net.localIsFirst ? 0 : 1, random: UInt32.random(in: .min ... .max))
        // Whatever was on, off: the title holds until the series starts.
        pendingFlow = nil
        session.stopAt = nil
        enter(.title)
    }

    /// Every frame online: the hello until the other's random is in, then the series;
    /// a pick waiting for the sim to settle; the pick clock.
    private func tickOnline() {
        guard online != nil else { return }
        if online?.started != true {
            online?.helloAgainIn -= 1
            if let online, online.helloAgainIn <= 0 {
                send(.hello(random: online.random, version: NetRules.protocolVersion), reliable: true)
                self.online?.helloAgainIn = 60
            }
            if let online, let theirs = online.theirRandom {
                self.online?.started = true
                startSeries(seed: online.random ^ theirs)
            }
            return
        }
        guard flow == .picking else { return }
        if let pending = online?.pendingPick {
            if pending.round == series.rounds.count, session.settled {
                online?.pendingPick = nil
                applyPick(choice: pending.choice)
            }
            return
        }
        pickFramesLeft -= 1
        let seconds = (pickFramesLeft + 59) / 60
        if picker == localIndex {
            (screen as? PickScreen)?.showSeconds(seconds)
            if pickFramesLeft <= 0 { screen?.fire() }
        } else {
            (screen as? WaitScreen)?.showSeconds(seconds)
        }
    }

    private func send(_ message: NetMessage, reliable: Bool) {
        flowState?.net.send(message.data, reliable: reliable)
    }

    private func handle(_ data: Data) {
        guard online != nil, let message = NetMessage(data: data) else { return }
        switch message {
        case .hello(let random, let version):
            guard version == NetRules.protocolVersion else {
                endOnline("VERSIONS DIFFER")
                return
            }
            if online?.theirRandom == nil {
                online?.theirRandom = random
                if let mine = online?.random { send(.hello(random: mine, version: NetRules.protocolVersion), reliable: true) }
            }
        case .inputs(let packet):
            guard online?.started == true else { return }
            session.receive(packet)
        case .pick(let round, let choice):
            guard picker != localIndex || flow != .picking else { return }
            online?.pendingPick = (round, choice)
        case .rematch(let random):
            online?.theirRematch = random
            startRematchIfBothIn()
        case .bye:
            endOnline("THEY LEFT")
        }
    }

    /// The networked series is over, with why if the other side ended it; back to the title.
    private func endOnline(_ why: String?) {
        guard online != nil else { return }
        online = nil
        session.stopAt = nil
        pendingFlow = nil
        flowState?.net.leave()
        if let why { flowState?.net.fail(why) }
        controls?.setOnline(false)
        enter(.title)
    }

    /// The events of frames just run, first time or run again with something new: the
    /// effects. A point isn't among them; that waits for both sides' inputs.
    private func show(_ frames: [FrameEvents]) {
        for frameEvents in frames { show(frameEvents.events) }
    }

    /// The events of frames both sides' inputs have confirmed: the point.
    private func confirm(_ frames: [FrameEvents]) {
        for frameEvents in frames {
            for case .scored(let scorer, let hoop, let entry) in frameEvents.events {
                rimFlash[hoop] = 8
                strike(hoop: hoop, by: scorer, entry: entry)
                showBanner("BUCKET!!", size: 48)
                pointScored(by: scorer, at: frameEvents.frame)
            }
        }
    }

    private func show(_ events: [MatchEvent]) {
        for event in events {
            switch event {
            case .jumped(let index):
                let player = match.players[index]
                switch player.power {
                case .blazingBoba:
                    // Four pixels down from the feet, and over the body.
                    let spark = Effect.fireJump.node(sprites, at: SpriteLibrary.point(player.position + Vec2(x: 0, y: -3.75)), flipped: player.facing == .left)
                    spark.zPosition = 40
                    glowers.addChild(spark)
                case .zeusJuice: glowers.addChild(EnergyEffect.lightningJump.node(sprites, player: index, at: SpriteLibrary.point(player.position), scale: 0.42))
                case .frostTea where EffectSheets.frames["ice_jumpspark"] != nil:
                    // The ice jump spark in the snowflake's blues, under the feet like the others.
                    let frames = (0..<(EffectSheets.frames["ice_jumpspark"] ?? 1)).map { sprites.iceTexture("ice_jumpspark", $0) }
                    let spark = SKSpriteNode(texture: frames[0])
                    spark.anchorPoint = CGPoint(x: 0.5, y: EffectSheets.anchorY["ice_jumpspark"] ?? 0)
                    spark.position = SpriteLibrary.point(player.position + Vec2(x: 0, y: (EffectSheets.anchorY["ice_jumpspark"] ?? 0) == 0 ? -3.75 : 0))
                    spark.xScale = player.facing == .left ? -0.5 : 0.5
                    spark.yScale = 0.5
                    spark.zPosition = 30
                    spark.run(.sequence([.animate(with: frames, timePerFrame: 1.0 / 24), .removeFromParent()]))
                    glowers.addChild(spark)
                default:
                    let drop = Effect.jumpSpark.bottomAligned ? -3.75 : 0
                    let spark = Effect.jumpSpark.node(sprites, at: SpriteLibrary.point(player.position + Vec2(x: 0, y: drop)), flipped: player.facing == .left, player: index)
                    spark.xScale *= 0.75
                    spark.yScale *= 0.75
                    glowers.addChild(spark)
                }
                if player.power == .frostTea { spawnSnowflakes(at: SpriteLibrary.point(player.position), count: 3, spread: 10) }
            case .dashed(let index), .slid(let index):
                let player = match.players[index]
                if player.power == .blazingBoba {
                    spawn(.fireDash, at: player.position, flipped: player.facing == .left)
                } else {
                    spawn(.smoke, at: player.position, flipped: player.facing == .left, player: index)
                }
                if player.power == .frostTea { spawnSnowflakes(at: SpriteLibrary.point(player.position), count: 3, spread: 10) }
            case .snatchReached(let index):
                let player = match.players[index]
                let offset = Vec2(x: GameScene.snatchSparkOffset.x * player.facing.sign, y: GameScene.snatchSparkOffset.y) / SpriteLibrary.pixelsPerUnit
                switch player.power {
                case .frostTea:
                    // A sphere of snowflakes off the hand.
                    spawnSnowflakes(at: SpriteLibrary.point(player.handCatchPoint), count: 14, spread: 20)
                case .zeusJuice where player.powerLevel >= 2:
                    spawnHitSpark(player: index, at: player.handCatchPoint)
                default:
                    // On the hand, and riding the body from there.
                    let spark = Effect.catchSpark.node(sprites, at: SpriteLibrary.point(player.position + offset), flipped: player.facing == .left)
                    glowers.addChild(spark)
                    riders.append((spark, index, offset))
                }
            case .popped(let victim, let popper):
                // A spark off the ball as it leaves the hands, in the colour of whoever knocked it.
                spawnHitSpark(player: popper, at: match.players[victim].chest + Vec2(x: 0, y: 3))
            case .swatted(let index, hit: true):
                spawnHitSpark(player: index, at: match.ball.position)
            case .wallJumped(let index, let wall):
                let player = match.players[index]
                // The sheet's spark flies left, away from a wall on the right.
                // Blazing Boba's is the fire skid sheet; everyone else's the fire wall spark as
                // a silhouette in their energy. Both painted the other way round from the old spark.
                let at = SpriteLibrary.point(player.position + Vec2(x: wall.sign * 4, y: 5))
                if player.power == .blazingBoba {
                    spawn(.fireSkid, at: player.position + Vec2(x: wall.sign * 4, y: 5), flipped: wall == .right)
                } else {
                    let frames = (0..<Effect.fireWallSpark.frameCount).map { sprites.silhouetteTexture(Effect.fireWallSpark.name, $0, player: index) }
                    let spark = SKSpriteNode(texture: frames[0])
                    spark.anchorPoint = Effect.fireWallSpark.anchor
                    spark.position = at
                    spark.xScale = (wall == .right ? -1 : 1) * Effect.fireWallSpark.scale
                    spark.yScale = Effect.fireWallSpark.scale
                    spark.zPosition = 30
                    spark.run(.sequence([.animate(with: frames, timePerFrame: 1 / Effect.fireWallSpark.fps), .removeFromParent()]))
                    glowers.addChild(spark)
                }
                if player.power == .frostTea { spawnSnowflakes(at: SpriteLibrary.point(player.position + Vec2(x: 0, y: 5)), count: 4, spread: 10) }
            case .caught(let index):
                let player = match.players[index]
                spawn(.catchSpark, at: player.position + Vec2(x: player.facing.sign * 2, y: 0), flipped: player.facing == .left)
            case .doubleJumped(let index):
                let player = match.players[index]
                spawnJumpPlatform(at: SpriteLibrary.point(player.position), colour: SKColor(rgb: sprites.look(for: index).glow))
            case .warped(let flasher, let from, let to), .flashed(let flasher, let from, let to):
                // The flash's spark at both ends, the sheet at half size.
                // The flash sheet at both ends, in the energy colour, at half size.
                // Drawn over rather than added, or the white saturates past the tone.
                for end in [from, to] {
                    let point = SpriteLibrary.point(end + Vec2(x: 0, y: BallRules.chestHeight))
                    let flash = EnergyEffect.flashSpark2.node(sprites, player: flasher, at: point, scale: 0.66)
                    glowers.addChild(flash)
                    if showHitboxes {
                        // The tear's reach at each end, where a held ball is popped.
                        let ring = SKShapeNode(circleOfRadius: CGFloat(FizzRules.tearRadius * SpriteLibrary.pixelsPerUnit))
                        ring.position = point
                        ring.strokeColor = .cyan
                        ring.lineWidth = 1
                        ring.zPosition = 60
                        glowers.addChild(ring)
                        ring.run(.sequence([.wait(forDuration: Double(FizzRules.tearFrames) / 60), .removeFromParent()]))
                    }
                }
            case .struck(let victim, let striker):
                spawnHitSpark(player: striker, at: match.players[victim].chest)
            case .parried(let victim, let by):
                spawnHitSpark(player: by, at: match.players[victim].chest)
                spawnHitSpark(player: by, at: match.players[by].handCatchPoint)
            case .quaked(let index):
                shake = match.players[index].powerLevel >= 2 ? 18 : 14
                spawnRocks(at: SpriteLibrary.point(match.players[index].position), whole: match.players[index].powerLevel >= 2)
            case .boltLanded(let at):
                let owner = match.ball.lastTouched ?? 0
                // Twice the size on a wall.
                let onWall = match.stage.overlapsSolid(Box(center: at, width: 6, height: 6))
                spawnHitSpark(player: owner, at: at, scale: onWall ? 2.0 / 3 : 1.0 / 3)
            case .boltStruck(let index, let x, let bottom):
                strikeColumn(at: SpriteLibrary.point(Vec2(x: x, y: bottom)), by: index)
            case .frozen(let index):
                spawnSnowflakes(at: SpriteLibrary.point(match.players[index].chest), count: 10, spread: 14)
            case .ballFrozen:
                spawnSnowflakes(at: SpriteLibrary.point(match.ball.position), count: 8, spread: 10)
            case .cloneShattered(let at):
                spawnSnowflakes(at: SpriteLibrary.point(at), count: 12, spread: 16)
            case .helmetsCollided(let at, let owner), .helmetSpawned(let at, let owner), .helmetRemoved(let at, let owner):
                // A burst of flashes in the helmet's colour.
                for step in 0..<6 {
                    let angle = CGFloat(step) / 6 * 2 * .pi
                    let point = SpriteLibrary.point(at) + CGPoint(x: cos(angle) * 18, y: sin(angle) * 18)
                    glowers.addChild(EnergyEffect.flashSpark2.node(sprites, player: owner, at: point, scale: 0.66))
                }
            case .portalWarped(let from, let to):
                for end in [from, to] {
                    glowers.addChild(EnergyEffect.flashSpark2.node(sprites, player: match.ball.lastTouched ?? 0, at: SpriteLibrary.point(end), scale: 0.5))
                }
            case .carHit(let id):
                carFlash[id] = GameScene.carFlashFrames
            case .carWrecked(_, let at):
                let burst = Effect.fireExplosion.node(sprites, at: SpriteLibrary.point(at), flipped: false)
                burst.setScale(1)
                glowers.addChild(burst)
            case .landed(let index):
                // Landing on a car dips it on its springs.
                let feet = match.players[index].position
                if let car = match.cars.first(where: { abs($0.box.max.y - feet.y) < 0.5 && feet.x >= $0.box.min.x && feet.x <= $0.box.max.x }) {
                    carDip[car.id] = GameScene.carDipFrames
                }
            case .fireballMade(let index):
                // The fire swirling into the hand.
                let player = match.players[index]
                // Where the throw's hold frame draws the ball.
                let pose = AnimationFrame(player.grounded ? .throwForward : .throwAir, 3)
                let hand = BallLandmarks.offset(pose).map { player.position + Vec2(x: $0.x / 1.6 * player.facing.sign, y: $0.y / 1.6) }
                    ?? Vec2(x: player.position.x + player.facing.sign * 4, y: player.position.y + BallRules.throwReleaseHeight)
                let swirl = Effect.fireCharge.node(sprites, at: SpriteLibrary.point(hand), flipped: player.facing == .left)
                swirl.zPosition = 40
                glowers.addChild(swirl)
                let summon = Effect.fireballSummon.node(sprites, at: SpriteLibrary.point(hand), flipped: player.facing == .left)
                summon.zPosition = 41
                glowers.addChild(summon)
            case .fireballBurst(let at):
                let burst = Effect.fireExplosion.node(sprites, at: SpriteLibrary.point(at + Vec2(x: 0, y: -4)), flipped: false)
                // Twice the size on a wall.
                if match.stage.overlapsSolid(Box(center: at, width: 8, height: 8)) {
                    burst.xScale *= 2
                    burst.yScale *= 2
                }
                glowers.addChild(burst)
            case .pulsed(let index, let pull):
                // Kinetic and unseen: the bar shows only with the hitboxes on.
                if showHitboxes { spawnPulse(by: index, pull: pull) }
            case .shot(let index), .thrown(let index), .dunked(let index):
                ballTeam = SKColor(rgb: sprites.look(for: index).glow)
                ballHold = 1
                ballShift = BallLook.shiftFrames
            default:
                break
            }
        }
    }

    /// The ball keeps the team colour while it's still the thrower's, until its first
    /// bounce, then shifts to neutral.
    private func tickBallColour() {
        if match.ball.owner != nil {
            ballHold = 1
        } else if ballHold > 0 {
            ballHold = 0
            ballShift = BallLook.shiftFrames
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
            let square = SKSpriteNode(texture: ParticleLook.sprites ? sprites.texture("esper_particle", (EffectSheets.frames["esper_particle"] ?? 1) / 3 + index % 3) : sprites.flatSquare(size: 4, alpha: 1))
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
            // The particle sheet played through as it drops, or the squares' step down.
            let frames = sheetFrames("esper_particle")
            let shrink = ParticleLook.sprites && frames.count > 1
                ? SKAction.animate(with: frames, timePerFrame: 0.3 / Double(frames.count))
                : SKAction.sequence([.wait(forDuration: 0.15), .scale(to: 0.66, duration: 0), .wait(forDuration: 0.1), .scale(to: 0.33, duration: 0)])
            square.run(.sequence([.wait(forDuration: hold), .group([drop, shrink]), .removeFromParent()]))
        }
    }

    /// Flash Fizz's blink: a bright diamond, wide and low, that flares out and is gone;
    /// `lingering`, it holds for the tear's frames and fades three times as slowly.
    private func spawnBlink(at point: CGPoint, colour: SKColor, lingering: Bool = false) {
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
            if lingering {
                let hold = Double(FizzRules.tearFrames) / 60
                blink.run(.sequence([flare, .wait(forDuration: hold), .fadeOut(withDuration: 0.6), .removeFromParent()]))
            } else {
                blink.run(.sequence([.group([flare, .fadeOut(withDuration: 0.2)]), .removeFromParent()]))
            }
        }
    }

    /// One of the two sparks, either each time, on the ball in the hitter's colour.
    private func spawnHitSpark(player: Int, at position: Vec2, scale: CGFloat = 1) {
        // Zeus Juice's hits spark in lightning; everyone else's in energy.
        let power = match.players.indices.contains(player) ? match.players[player].power : .none
        if power == .blazingBoba, let name = ["fire_spark", "fire_spark2", "fire_spark3"].filter({ EffectSheets.frames[$0] != nil }).randomElement() {
            // Blazing Boba's hits spark in fire, painted as it is.
            let frames = (0..<(EffectSheets.frames[name] ?? 1)).map { sprites.texture(name, $0) }
            let node = SKSpriteNode(texture: frames[0])
            node.anchorPoint = CGPoint(x: 0.5, y: EffectSheets.anchorY[name] ?? 0.5)
            node.position = SpriteLibrary.point(position)
            // Painted at twice their playing size.
            node.setScale(scale * 0.5)
            node.zPosition = 30
            node.run(.sequence([.animate(with: frames, timePerFrame: 1.0 / 24), .removeFromParent()]))
            glowers.addChild(node)
            return
        }
        let zeus = power == .zeusJuice
        let spark = (zeus ? EnergyEffect.lightningSparks : EnergyEffect.hitSparks).randomElement()!
        glowers.addChild(spark.node(sprites, player: player, at: SpriteLibrary.point(position), scale: scale * (zeus ? 0.5 : 1)))
    }

    /// A score: lightning strikes the rim from the way the ball came in, leaning half as
    /// far as the ball did and never past the cap, one of the four bolts each time, at the
    /// sheet's own width and stretched tall enough to run past the top of the screen at
    /// that lean. On the sheet's two full-frame flash frames the whole screen flashes in
    /// the same tone and the floor and walls go white, fading back. The crown erupts off
    /// the rim with it.
    private func strike(hoop: Int, by scorer: Int, entry velocity: Vec2) {
        let rim = SpriteLibrary.point(match.stage.hoops[hoop].position)
        let lean = min(max(atan2(velocity.x, -velocity.y) * GameScene.strikeLeanShare, -GameScene.strikeMaxLean), GameScene.strikeMaxLean)
        let bolt = EnergyEffect.strikes.randomElement()!
        let node = bolt.node(sprites, player: scorer, at: rim)
        node.zRotation = CGFloat(lean)
        node.zPosition = 45
        let top = cameraNode.position.y + size.height * cameraNode.yScale / 2
        node.yScale = (top - rim.y) / CGFloat(cos(lean)) * 1.1 / node.size.height
        glowers.addChild(node)

        let frame = 1 / bolt.fps
        let flash = SKSpriteNode(texture: sprites.flatSquare(size: 16, alpha: 1))
        flash.color = SKColor(rgb: sprites.look(for: scorer).energyTone(luminance: EnergyEffect.strikeLuminance))
        flash.colorBlendFactor = 1
        flash.size = CGSize(width: size.width * cameraNode.xScale, height: size.height * cameraNode.yScale)
        flash.position = cameraNode.position
        flash.zPosition = 44
        flash.isHidden = true
        glowers.addChild(flash)
        flash.run(.sequence([.wait(forDuration: Double(EnergyEffect.strikeFlashFrames.lowerBound) * frame), .unhide(),
                             .wait(forDuration: Double(EnergyEffect.strikeFlashFrames.count) * frame), .removeFromParent()]))
        courtWhiteIn = Int((Double(EnergyEffect.strikeFlashFrames.lowerBound) * frame * 60).rounded())

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

    private func spawn(_ effect: Effect, at position: Vec2, flipped: Bool, player: Int? = nil) {
        glowers.addChild(effect.node(sprites, at: SpriteLibrary.point(position), flipped: flipped, player: player))
    }

    /// The head's particles, sprites of their own rather than an emitter, since an emitter
    /// can't play a sheet: each one plays its sheet through at 24 a second over its life,
    /// rising and bending with one wind. A stream is a sheet, its size and its colour;
    /// a power may mix two streams, half the rate each.
    private struct HeadStream {
        var frames: [SKTexture]
        var size: CGFloat
        var tint: SKColor?
        var rate: Double
    }

    private struct HeadParticle {
        var node: SKSpriteNode
        var owner: Int
        var velocity: CGVector
        var age: Double
        var life: Double
        var frames: [SKTexture]
        /// The sheet frame it started on, so a stream's particles don't play in step.
        var startFrame: Int
    }

    private var headParticles: [HeadParticle] = []
    private var headCredit: [Int: [Double]] = [:]
    private var headStreamsCache: [Int: (power: Power, streams: [HeadStream])] = [:]

    private func sheetFrames(_ name: String, toned player: Int? = nil) -> [SKTexture] {
        let count = EffectSheets.frames[name] ?? 1
        return (0..<count).map { frame in player.map { sprites.effectTexture(name, frame, player: $0) } ?? sprites.texture(name, frame) }
    }

    private func headStreams(_ index: Int, power: Power) -> [HeadStream] {
        if let cached = headStreamsCache[index], cached.power == power { return cached.streams }
        let colour = SKColor(rgb: sprites.look(for: index).glow)
        let energy = HeadStream(frames: ParticleLook.sprites ? sheetFrames("esper_particle") : [sprites.flatSquare(size: 4, alpha: 1)],
                                size: ParticleLook.energySize, tint: colour, rate: 24)
        var streams = [energy]
        switch power {
        case .blazingBoba where EffectSheets.frames["fire_particle"] != nil:
            streams = [HeadStream(frames: sheetFrames("fire_particle"), size: ParticleLook.fireSize, tint: nil, rate: 24)]
        case .frostTea:
            // Snowflakes among the energy.
            streams = [HeadStream(frames: energy.frames, size: energy.size, tint: colour, rate: 12),
                       HeadStream(frames: [SKTexture(imageNamed: "Snowflake")], size: ParticleLook.snowflakeSize, tint: GameScene.ice, rate: 12)]
        case .zeusJuice where EffectSheets.frames["lightning_particle"] != nil:
            // The two bolts, half each, toned in the energy colour.
            streams = [HeadStream(frames: sheetFrames("lightning_particle", toned: index), size: ParticleLook.lightningSize, tint: nil, rate: 12)]
            if EffectSheets.frames["lightning_particle2"] != nil {
                streams.append(HeadStream(frames: sheetFrames("lightning_particle2", toned: index), size: ParticleLook.lightningSize, tint: nil, rate: 12))
            } else {
                streams[0].rate = 24
            }
        default:
            break
        }
        headStreamsCache[index] = (power, streams)
        return streams
    }

    /// New particles off a head at `point` this frame, by its streams' rates.
    private func emitHeadParticles(_ index: Int, power: Power, at point: CGPoint) {
        let streams = headStreams(index, power: power)
        var credit = headCredit[index] ?? []
        while credit.count < streams.count { credit.append(0) }
        for (slot, stream) in streams.enumerated() {
            credit[slot] += stream.rate / 60
            while credit[slot] >= 1 {
                credit[slot] -= 1
                let node = SKSpriteNode(texture: stream.frames[0])
                node.size = CGSize(width: stream.size, height: stream.size)
                if let tint = stream.tint {
                    node.color = tint
                    node.colorBlendFactor = 1
                }
                // Drawn over, not added: added on top of the head they saturate to white.
                node.blendMode = .alpha
                node.zPosition = 1
                node.position = CGPoint(x: point.x + CGFloat.random(in: -1...1), y: point.y + CGFloat.random(in: -0.5...0.5))
                if stream.frames.count == 1 { node.zRotation = CGFloat.random(in: 0...(2 * .pi)) }
                glowers.addChild(node)
                let angle = Double.pi / 2 + Double.random(in: -Double.pi / 28...Double.pi / 28)
                let speed = 24 + Double.random(in: -2...2)
                // A sheet plays through once over the life; a single frame lives 0.6 s.
                let life = stream.frames.count > 1 ? Double(stream.frames.count) / 24 : 0.6 + Double.random(in: -0.05...0.05)
                headParticles.append(HeadParticle(node: node, owner: index, velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                                                  age: 0, life: life, frames: stream.frames,
                                                  startFrame: Int.random(in: 0..<stream.frames.count)))
            }
        }
        headCredit[index] = credit
    }

    /// Every head particle a frame on: the sheet's frame for its age, the rise, the wind.
    private func stepHeadParticles() {
        let step = 1.0 / 60
        headParticles = headParticles.compactMap { particle in
            var particle = particle
            particle.age += step
            guard particle.age < particle.life else {
                particle.node.removeFromParent()
                return nil
            }
            let wind = sin(Double(match.frame) / 60 * 2 * .pi * 1.1 + Double(particle.owner) * 2) * 140
            particle.velocity.dx += wind * step
            particle.velocity.dy += 10 * step
            particle.node.position = CGPoint(x: particle.node.position.x + particle.velocity.dx * step,
                                             y: particle.node.position.y + particle.velocity.dy * step)
            let share = particle.age / particle.life
            if particle.frames.count > 1 {
                particle.node.texture = particle.frames[(particle.startFrame + Int(particle.age * 24)) % particle.frames.count]
            } else {
                // A single frame steps down in size and fades, the digital dissolve.
                particle.node.setScale(share < 0.45 ? 1 : (share < 0.75 ? 0.66 : 0.33))
            }
            particle.node.alpha = share < 0.85 ? 0.9 : 0.9 * (1 - share) / 0.15
            return particle
        }
    }

    /// A helmet vector filled in a colour: drawn, then painted over with the colour through
    /// its own alpha, since a vector's black won't take a tint.
    private var helmetTextures: [String: SKTexture] = [:]
    private func helmetTexture(variant: Int, colour: SKColor) -> SKTexture? {
        let key = "\(variant)|\(colour)"
        if let cached = helmetTextures[key] { return cached }
        guard let image = UIImage(named: "FootballHelmet\(variant + 1)") else { return nil }
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let filled = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            image.draw(in: rect)
            context.cgContext.setBlendMode(.sourceIn)
            colour.setFill()
            context.cgContext.fill(rect)
        }
        let texture = SKTexture(image: filled)
        helmetTextures[key] = texture
        return texture
    }

    /// Where the field's camera wants to be: the local player, led by where they're heading,
    /// kept inside the field's ends.
    private func cameraTargetX() -> CGFloat {
        guard match.players.indices.contains(localIndex) else { return cameraBase.x }
        let player = match.players[localIndex]
        let lead = CGFloat(player.velocity.x) * GameScene.cameraLeadFrames * CGFloat(SpriteLibrary.pixelsPerUnit)
        let wanted = SpriteLibrary.point(player.position).x + lead
        let halfView = size.width * cameraNode.xScale / 2
        let width = CGFloat(match.stage.columns) * GameScene.pixelsPerTile
        return min(max(wanted, halfView), max(width - halfView, halfView))
    }
    private static let cameraEase: CGFloat = 0.08
    private static let cameraLeadFrames: CGFloat = 20

    private var helmetNodes: [Int: SKSpriteNode] = [:]

    // MARK: Traffic

    /// Each car as its wheels and its body over them, by the sim's id; frames of the black
    /// flash after a hit and of the dip after a landing.
    private var carNodes: [Int: (body: SKSpriteNode, wheels: SKSpriteNode?)] = [:]
    private var carFlash: [Int: Int] = [:]
    private var carDip: [Int: Int] = [:]
    private static let carFlashFrames = 12
    private static let carDipFrames = 14
    private var helicopterNode: SKNode?
    private var helicopterId = 0

    /// The cars idling, the body shivering a pixel over wheels that stay put, dipping when
    /// someone lands on it, flashing black when hit; and the helicopter over its rim.
    private func drawTraffic() {
        guard match.stage.features.traffic else { return }
        var seen = Set<Int>()
        for car in match.cars {
            seen.insert(car.id)
            let art = car.vehicle.art
            let nodes = carNodes[car.id] ?? {
                let size = CGSize(width: CGFloat(car.box.width * SpriteLibrary.pixelsPerUnit), height: CGFloat(car.box.height * SpriteLibrary.pixelsPerUnit))
                let body = SKSpriteNode(texture: HighwayArt.texture("vehicle_\(art)_body", art: art))
                body.size = size
                body.anchorPoint = CGPoint(x: 0.5, y: 0)
                body.zPosition = 3
                ground.addChild(body)
                var wheels: SKSpriteNode?
                if let texture = HighwayArt.texture("vehicle_\(art)_wheels", art: art) {
                    let node = SKSpriteNode(texture: texture)
                    node.size = size
                    node.anchorPoint = CGPoint(x: 0.5, y: 0)
                    node.zPosition = 2.9
                    ground.addChild(node)
                    wheels = node
                }
                // Facing the other way, half the time, by its id.
                if car.id % 2 == 1 {
                    body.xScale = -1
                    wheels?.xScale = -1
                }
                let made = (body: body, wheels: wheels)
                carNodes[car.id] = made
                return made
            }()
            let foot = SpriteLibrary.point(Vec2(x: car.box.center.x, y: car.box.min.y))
            // The idle: a pixel up and down, each car on its own beat.
            let idle: CGFloat = ((match.frame + car.id * 7) / 4) % 2 == 0 ? 0 : 1
            var dip: CGFloat = 0
            if let left = carDip[car.id], left > 0 {
                dip = -3 * CGFloat(left) / CGFloat(GameScene.carDipFrames)
                carDip[car.id] = left - 1
            }
            nodes.body.position = CGPoint(x: foot.x, y: foot.y + idle + dip)
            nodes.wheels?.position = foot
            if let left = carFlash[car.id], left > 0 {
                let on = (left / 2) % 2 == 0
                nodes.body.color = .black
                nodes.body.colorBlendFactor = on ? 0.85 : 0
                carFlash[car.id] = left - 1
            } else {
                nodes.body.colorBlendFactor = 0
            }
        }
        for (id, nodes) in carNodes where !seen.contains(id) {
            nodes.body.removeFromParent()
            nodes.wheels?.removeFromParent()
            carNodes[id] = nil
            carFlash[id] = nil
            carDip[id] = nil
        }

        if let flying = match.helicopter {
            if helicopterNode == nil || helicopterId != flying.id {
                helicopterNode?.removeFromParent()
                helicopterNode = makeHelicopter(for: flying)
                ground.addChild(helicopterNode!)
                helicopterId = flying.id
            }
            helicopterNode?.position = SpriteLibrary.point(Vec2(x: flying.x, y: HighwayRules.helicopterHeight))
        } else {
            helicopterNode?.removeFromParent()
            helicopterNode = nil
        }
    }

    /// The helicopter, its reds in the energy of the side whose basket it carries, facing the
    /// way it flies: the hull, the tail rotor spinning about its hub, and the top rotor
    /// flipped end over end every other frame so it reads as turning.
    private func makeHelicopter(for flying: Helicopter) -> SKNode {
        let node = SKNode()
        node.zPosition = 6
        node.xScale = flying.speed > 0 ? -1 : 1
        let hoop = match.stage.hoops[flying.hoop]
        let look = sprites.look(for: 1 - hoop.owner)
        let width: CGFloat = 96
        let rows = HighwayArt.artRows["helicopter"]!
        let height = width * (rows.bottom - rows.top)
        let tones: [SKColor?] = [nil, SKColor(rgb: look.energyTone(luminance: 0.75)),
                                 SKColor(rgb: look.energyTone(luminance: 0.55)), SKColor(rgb: look.energyTone(luminance: 0.4))]
        // A point on the drawing's 800 square, in the node's own space.
        func place(_ share: CGPoint) -> CGPoint {
            CGPoint(x: (share.x - 0.5) * width, y: (1 - (share.y - rows.top) / (rows.bottom - rows.top) - 0.5) * height)
        }
        for (part, hub) in [("hull", CGPoint?.none), ("propeller", HighwayArt.topRotorHub), ("spin_me", HighwayArt.tailRotorHub)] {
            // A rotor turns about its hub: its layers hang off a pivot there.
            let pivot = SKNode()
            let at = hub.map(place) ?? .zero
            pivot.position = at
            node.addChild(pivot)
            for (index, tint) in tones.enumerated() {
                let name = "helicopter_\(part)_" + (index == 0 ? "plain" : "red\(index - 1)")
                guard let texture = HighwayArt.texture(name, art: "helicopter", tint: tint) else { continue }
                let layer = SKSpriteNode(texture: texture)
                layer.size = CGSize(width: width, height: height)
                layer.position = CGPoint(x: -at.x, y: -at.y)
                pivot.addChild(layer)
            }
            switch part {
            case "spin_me":
                pivot.run(.repeatForever(.rotate(byAngle: -.pi * 2, duration: 0.25)))
            case "propeller":
                pivot.run(.repeatForever(.sequence([.scaleY(to: -1, duration: 0), .wait(forDuration: 1.0 / 30),
                                                    .scaleY(to: 1, duration: 0), .wait(forDuration: 1.0 / 30)])))
            default:
                break
            }
        }
        return node
    }
    private var fieldBlooms: [SKSpriteNode] = []
    private var lightPanels: [SKShapeNode] = []
    private let goalposts = SKNode()
    private let backboards = SKNode()

    /// Behind each rim a cluster of `flashspark2` in the guarding side's energy, each on its
    /// own frame, laid out on a grid sheared to the crossbar's lean.
    private func buildBackboards() {
        backboards.removeAllChildren()
        let frameCount = EffectSheets.frames[EnergyEffect.flashSpark2.name] ?? 1
        for hoop in match.stage.hoops {
            let owner = 1 - hoop.owner
            let frames = sprites.effectFrames(EnergyEffect.flashSpark2, player: owner)
            let back = CGFloat(hoop.backboard.sign)
            let rim = SpriteLibrary.point(hoop.position)
            let centre = CGPoint(x: rim.x + back * BackboardTuning.x, y: rim.y + BackboardTuning.y)
            let shear = tan(BackboardTuning.skew * .pi / 180) * -back
            let step = BackboardTuning.spacing * BackboardTuning.size * 2
            let cluster = flashCluster(frames: frames, frameCount: frameCount, columns: BackboardTuning.columns, rows: BackboardTuning.rows,
                                       step: step, scale: BackboardTuning.size, shear: shear)
            cluster.position = centre
            cluster.alpha = BackboardTuning.alpha
            backboards.addChild(cluster)
        }
    }

    /// A grid of `flashspark2` round its middle, each spark on its own frame so the whole
    /// shimmers rather than blinks, sheared up by `shear` a pixel across.
    private func flashCluster(frames: [SKTexture], frameCount: Int, columns: Int, rows: Int, step: CGFloat, scale: CGFloat, shear: CGFloat) -> SKNode {
        let cluster = SKNode()
        for column in 0..<columns {
            for row in 0..<rows {
                let across = (CGFloat(column) - CGFloat(columns - 1) / 2) * step
                let up = (CGFloat(row) - CGFloat(rows - 1) / 2) * step
                let spark = SKSpriteNode(texture: frames[0])
                spark.setScale(scale)
                spark.position = CGPoint(x: across, y: up + across * shear)
                spark.zPosition = 4
                let start = (column * 7 + row * 5) % max(frameCount, 1)
                let looped: [SKTexture] = Array(frames[start...]) + Array(frames[..<start])
                spark.run(SKAction.repeatForever(SKAction.animate(with: looped, timePerFrame: 1.0 / 24)))
                cluster.addChild(spark)
            }
        }
        return cluster
    }

    /// Made slabs and walls as flash clusters in their maker's energy, by where they stand.
    private var platformClusters: [String: SKNode] = [:]
    private func drawPlatforms() {
        var seen = Set<String>()
        let frameCount = EffectSheets.frames[EnergyEffect.flashSpark2.name] ?? 1
        for platform in match.platforms {
            let key = "\(platform.owner)|\(platform.box.min.x)|\(platform.box.min.y)"
            seen.insert(key)
            let cluster = platformClusters[key] ?? {
                let width = CGFloat(platform.box.width * SpriteLibrary.pixelsPerUnit)
                let height = CGFloat(platform.box.height * SpriteLibrary.pixelsPerUnit)
                let step = BackboardTuning.spacing * BackboardTuning.size * 2
                let cluster = flashCluster(frames: sprites.effectFrames(EnergyEffect.flashSpark2, player: platform.owner), frameCount: frameCount,
                                           columns: max(Int((width / step).rounded()), 1), rows: max(Int((height / step).rounded()), 1),
                                           step: step, scale: BackboardTuning.size, shear: 0)
                cluster.position = SpriteLibrary.point(platform.box.center)
                glowers.addChild(cluster)
                platformClusters[key] = cluster
                return cluster
            }()
            // Thinning out over its last quarter second.
            cluster.alpha = BackboardTuning.alpha * min(CGFloat(platform.framesLeft) / 15, 1)
        }
        for (key, cluster) in platformClusters where !seen.contains(key) {
            cluster.removeFromParent()
            platformClusters[key] = nil
        }
    }
    /// The goalposts' shadows, one flat group at two thirds so overlaps don't darken, and
    /// each player's body and head shadow.
    private let goalpostShadows = SKEffectNode()
    private var shadowBodies: [SKSpriteNode] = []
    private var shadowHeads: [SKSpriteNode] = []
    private lazy var shadowShader: SKShader = {
        let shader = SKShader(source: """
        void main() {
            float alpha = texture2D(u_texture, v_tex_coord).a;
            gl_FragColor = vec4(u_shade.rgb * alpha, alpha) * v_color_mix.a;
        }
        """)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        FieldArt.shadow.getRed(&r, green: &g, blue: &b, alpha: &a)
        shader.uniforms = [SKUniform(name: "u_shade", vectorFloat4: SIMD4<Float>(Float(r), Float(g), Float(b), 1))]
        return shader
    }()

    /// A sprite's shadow: the same frame in the shadow colour, mirrored under its anchor and
    /// sheared with the turf, `height` pixels of it above the anchor at `x`.
    /// `ground` is the floor under the body and `rise` how far up off it the feet are: the
    /// shadow stays on the ground, thinner and smaller the higher the body.
    private func castShadow(_ shadow: SKSpriteNode, of source: SKSpriteNode, anchorY: CGFloat, facing: CGFloat, ground: CGFloat, rise: CGFloat) {
        guard let texture = source.texture else { shadow.isHidden = true; return }
        let height = max(rise, 0)
        let share = min(height / FieldArt.shadowFadeHeight, 1)
        let scale = 1 - (1 - FieldArt.shadowSmallest) * share
        shadow.isHidden = source.isHidden || share >= 1
        shadow.alpha = FieldArt.shadowAlpha * (1 - share)
        shadow.texture = texture
        shadow.setScale(1)
        shadow.size = source.size
        shadow.anchorPoint = source.anchorPoint
        shadow.xScale = facing * scale
        shadow.yScale = -scale
        shadow.zRotation = -source.zRotation
        let centre = CGFloat(match.stage.columns) * GameScene.pixelsPerTile / 2
        let slope = FieldArt.slope(at: source.position.x, centre: centre)
        // Local shift across per unit up the sprite, turned into its own normalised units.
        let shear = -slope * source.size.height / source.size.width / facing
        let rowTop = 1 - source.anchorPoint.y, rowBottom = -source.anchorPoint.y
        shadow.warpGeometry = SKWarpGeometryGrid(columns: 1, rows: 1,
                                                 sourcePositions: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)],
                                                 destinationPositions: [SIMD2(Float(shear * rowBottom), 0), SIMD2(Float(1 + shear * rowBottom), 0),
                                                                        SIMD2(Float(shear * rowTop), 1), SIMD2(Float(1 + shear * rowTop), 1)])
        // Its place below the feet, mirrored and shrunk, set down on the ground.
        let above = (source.position.y - anchorY) * scale
        shadow.position = CGPoint(x: source.position.x - slope * above, y: ground - above)
    }
    private var netNodes: [SKShapeNode] = []

    /// The goalposts drawn at their rims.
    private func buildGoalposts() {
        goalposts.removeAllChildren()
        goalpostShadows.removeAllChildren()
        for hoop in match.stage.hoops where match.stage.features.shadows {
            let postX = hoop.backboard == .left ? Stage.fieldPostInset : match.stage.width - Stage.fieldPostInset
            FieldArt.goalpost(at: SpriteLibrary.point(Vec2(x: postX, y: GoalpostTuning.postRimHeight)), backboard: hoop.backboard, into: goalpostShadows,
                              crossbarBelowRim: GoalpostTuning.crossbarBelowRim, prongHeight: GoalpostTuning.prongHeight,
                              angle: GoalpostTuning.crossbarAngle * .pi / 180, thickness: GoalpostTuning.thickness, outline: 0,
                              padColour: FieldArt.shadow, shadowOf: CGFloat(match.stage.columns) * GameScene.pixelsPerTile / 2)
        }
        for hoop in match.stage.hoops {
            let postX = hoop.backboard == .left ? Stage.fieldPostInset : match.stage.width - Stage.fieldPostInset
            FieldArt.goalpost(at: SpriteLibrary.point(Vec2(x: postX, y: GoalpostTuning.postRimHeight)), backboard: hoop.backboard, into: goalposts,
                              crossbarBelowRim: GoalpostTuning.crossbarBelowRim, prongHeight: GoalpostTuning.prongHeight,
                              angle: GoalpostTuning.crossbarAngle * .pi / 180,
                              thickness: GoalpostTuning.thickness, outline: GoalpostTuning.outline,
                              // The rim's defender's colour, as the court's backboard blocks wear it.
                              padColour: SKColor(rgb: CourtLook.shaded(sprites.look(for: 1 - hoop.owner).glow)))
        }
    }
    private var yardNumbers: [SKNode] = []
    private var railChevrons: [SKSpriteNode] = []
    /// The down marker, stood on the top of the grass under a loose ball at rest.
    private var downMarker: SKSpriteNode?
    /// With nobody holding it, the rails call for the ball instead, the lettering running
    /// one way on one rail and the other way on the other.
    private var railCalls: [(node: SKSpriteNode, rail: Int, home: CGFloat)] = []
    private static let railCall = "\u{2B29} GET THE BALL!  \u{2B29}"
    private static let railCallSpacing: CGFloat = 150
    private var railChevronHomes: [CGFloat] = []
    private var portalNode: SKNode?
    private var riftPlates: [(node: SKSpriteNode, salt: Int, outer: Bool)] = []

    /// The portal is Gemini's rift from Project Stars, without its lean: both drawings as
    /// a tall pair, and the same pair again half as wide, turned end over end, the two
    /// pairs trading length back and forth. Each plate jumps to a new place and opacity
    /// twelve times a second, held, never eased, so it reads as a picture failing.
    private func makeRift() -> SKNode {
        let rift = SKNode()
        rift.zPosition = 5
        riftPlates = []
        let plates: [(name: String, outer: Bool, salt: Int)] = [
            ("gemini_rift_v1", true, 3), ("gemini_rift_v2", true, 11), ("gemini_rift_v1", false, 21), ("gemini_rift_v2", false, 31),
        ]
        for plate in plates {
            let frames = (0..<(EffectSheets.frames[plate.name] ?? 1)).map { sprites.texture(plate.name, $0) }
            let node = SKSpriteNode(texture: frames[0])
            node.zRotation = plate.outer ? 0 : .pi
            node.run(.repeatForever(.animate(with: frames, timePerFrame: 1.0 / 24)))
            rift.addChild(node)
            riftPlates.append((node, plate.salt, plate.outer))
        }
        return rift
    }

    /// Stars' `jitter`: a value from -1 to 1 for a step, different for each salt.
    private func riftJitter(_ step: Double, salt: Int) -> Double {
        let frequency = 12.9898 + Double(salt) * 4.1357
        let hashed = sin(step * frequency + Double(salt) * 78.233) * 43758.5453
        return (hashed - hashed.rounded(.down)) * 2 - 1
    }

    private func stepRift(fading: CGFloat) {
        let now = Double(match.frame) / 60
        let trade = (1 - cos(now / RiftLook.tradePeriod * 2 * .pi)) / 2
        let outerLength = RiftLook.innerScale + (1 - RiftLook.innerScale) * (1 - trade)
        let innerLength = RiftLook.innerScale + (1 - RiftLook.innerScale) * trade
        let step = (now * RiftLook.jumpRate).rounded(.down)
        let side = CGFloat(FieldRules.portalHalfHeight * 2 * SpriteLibrary.pixelsPerUnit)
        for plate in riftPlates {
            let width = plate.outer ? 1 : RiftLook.innerScale
            let length = plate.outer ? outerLength : innerLength
            plate.node.setScale(1)
            plate.node.size = CGSize(width: side, height: side)
            plate.node.xScale = 0.375 * width
            plate.node.yScale = 1.25 * length
            plate.node.position = CGPoint(x: RiftLook.jumpReach * riftJitter(step, salt: plate.salt),
                                          y: RiftLook.jumpReach * riftJitter(step, salt: plate.salt + 1))
            let roll = (riftJitter(step, salt: plate.salt + 2) + 1) / 2
            plate.node.alpha = CGFloat(RiftLook.faintest + (1 - RiftLook.faintest) * roll) * fading
        }
    }
    private var portalId = 0

    /// Helmets in their defender's colour, facing the way they travel and tipped back 15
    /// degrees, and the portal's loop.
    private func drawField() {
        var seen = Set<Int>()
        for helmet in match.helmets {
            seen.insert(helmet.id)
            let node = helmetNodes[helmet.id] ?? {
                // The vector as a template, filled in the defender's energy colour.
                let colour = SKColor(rgb: sprites.look(for: helmet.owner).glow)
                let node = SKSpriteNode(texture: helmetTexture(variant: helmet.variant, colour: colour))
                node.zPosition = 6
                glowers.addChild(node)
                helmetNodes[helmet.id] = node
                return node
            }()
            // Facing the way it goes, tipped back, at the slider's scale over its box.
            let side = CGFloat(FieldRules.helmetSize * SpriteLibrary.pixelsPerUnit) * HelmetTuning.scale
            let forward: CGFloat = helmet.speed > 0 ? 1 : -1
            node.setScale(1)
            node.size = CGSize(width: side, height: side)
            node.xScale = -forward
            node.zRotation = -HelmetTuning.tilt * forward
            // A slow circle, each on its own phase, like a hover; the drawing only.
            let phase = Double(match.frame) / 60 * 2 * .pi * 0.6 + Double(helmet.id) * 1.7
            node.position = SpriteLibrary.point(helmet.box.center)
                + CGPoint(x: cos(phase) * HelmetTuning.orbit, y: sin(phase) * HelmetTuning.orbit)
        }
        for (id, node) in helmetNodes where !seen.contains(id) {
            node.removeFromParent()
            helmetNodes[id] = nil
        }
        // The rail's chevrons: shown with the ball in hand, pointing and drifting toward the
        // rim the holder attacks.
        let attacking = match.ball.holder.flatMap { holder in match.stage.hoops.first { $0.owner == holder } }
        // The down marker: where a loose ball last came to rest, on the top edge of the grass.
        if match.stage.features.ballCam {
            if downMarker == nil, let image = UIImage(named: "FootballMarker") {
                let marker = SKSpriteNode(texture: SKTexture(image: image))
                marker.size = CGSize(width: FieldArt.markerHeight * 121 / 512, height: FieldArt.markerHeight)
                marker.anchorPoint = CGPoint(x: 0.5, y: 0)
                marker.zPosition = -12
                ground.addChild(marker)
                downMarker = marker
            }
            // It stays at the last spot a loose ball rested, until the next, or the point ends.
            let resting = match.ball.holder == nil && match.ball.isLive && match.ball.resting
            if resting {
                downMarker?.isHidden = false
                downMarker?.position = CGPoint(x: SpriteLibrary.point(match.ball.position).x, y: FieldArt.turfTop)
            } else if match.countdown > 0 {
                downMarker?.isHidden = true
            }
        }
        // Loose: the call, drifting one way on the top rail and the other on the bottom.
        let loose = attacking == nil && match.ball.holder == nil
        let callShift = CGFloat(match.frame % Int(GameScene.railCallSpacing * 2)) / 2
        for call in railCalls {
            call.node.isHidden = !loose
            guard loose else { continue }
            let way: CGFloat = call.rail == 0 ? 1 : -1
            call.node.position.x = call.home + way * callShift - (way < 0 ? 0 : GameScene.railCallSpacing)
        }
        for (index, chevron) in railChevrons.enumerated() {
            chevron.isHidden = attacking == nil
            guard let attacking else { continue }
            let right = attacking.position.x > match.stage.width / 2
            chevron.zRotation = right ? 0 : .pi
            let drift = CGFloat(match.frame % 28) / 2 * (right ? 1 : -1)
            chevron.position.x = railChevronHomes[index] + drift
        }
        if let portal = match.portal {
            if portalNode == nil || portalId != portal.id {
                portalNode?.removeFromParent()
                portalNode = makeRift()
                glowers.addChild(portalNode!)
                portalId = portal.id
            }
            portalNode?.position = SpriteLibrary.point(portal.centre)
            stepRift(fading: min(CGFloat(portal.framesLeft) / 30, 1))
        } else {
            portalNode?.removeFromParent()
            portalNode = nil
        }
    }

    /// Frost Tea's snowflakes: the vector, small, thrown out from a point and fading.
    private func spawnSnowflakes(at point: CGPoint, count: Int, spread: CGFloat) {
        let texture = SKTexture(imageNamed: "Snowflake")
        for step in 0..<count {
            let flake = SKSpriteNode(texture: texture)
            let size = CGFloat(4 + step % 3)
            flake.size = CGSize(width: size, height: size * 381 / 333)
            flake.position = point
            flake.zPosition = 31
            flake.color = GameScene.ice
            flake.colorBlendFactor = 0.5
            flake.blendMode = .add
            glowers.addChild(flake)
            let angle = CGFloat(step) / CGFloat(count) * 2 * .pi + CGFloat(step % 2) * 0.3
            let out = CGPoint(x: cos(angle) * spread, y: sin(angle) * spread * 0.8)
            let fly = SKAction.move(by: CGVector(dx: out.x, dy: out.y), duration: 0.35)
            fly.timingMode = .easeOut
            let spin = SKAction.rotate(byAngle: .pi * (step % 2 == 0 ? 1 : -1), duration: 0.5)
            flake.run(.sequence([.group([fly, spin, .sequence([.wait(forDuration: 0.2), .fadeOut(withDuration: 0.3)])]), .removeFromParent()]))
        }
    }

    /// Quake-Up Coffee's rocks: little squares of floor thrown up and falling back.
    private func spawnRocks(at point: CGPoint, whole: Bool) {
        let count = whole ? 24 : 10
        let width: CGFloat = whole ? size.width * cameraNode.xScale : 40
        for step in 0..<count {
            let rock = SKSpriteNode(texture: sprites.flatSquare(size: 4, alpha: 1))
            let side = CGFloat(2 + step % 3)
            rock.size = CGSize(width: side, height: side)
            rock.color = SKColor(red: 0.42, green: 0.3, blue: 0.2, alpha: 1)
            rock.colorBlendFactor = 1
            rock.position = CGPoint(x: point.x + (CGFloat(step) / CGFloat(max(count - 1, 1)) - 0.5) * width, y: point.y + 1)
            rock.zPosition = 29
            glowers.addChild(rock)
            let up = SKAction.moveBy(x: CGFloat(step % 3 - 1) * 3, y: CGFloat(8 + step % 4 * 3), duration: 0.18)
            up.timingMode = .easeOut
            let down = SKAction.moveBy(x: CGFloat(step % 3 - 1) * 3, y: -CGFloat(10 + step % 4 * 3), duration: 0.22)
            down.timingMode = .easeIn
            rock.run(.sequence([up, down, .removeFromParent()]))
        }
    }

    /// Zeus Juice's strike: a bolt down from the top of the screen to the point, in the
    /// player's colour, and a spark where it lands.
    private func strikeColumn(at point: CGPoint, by index: Int) {
        let bolt = EnergyEffect.strikes.randomElement()!
        let node = bolt.node(sprites, player: index, at: point)
        node.zPosition = 45
        let top = cameraBase.y + size.height * cameraNode.yScale / 2
        // A sixth of the sheet's width: a bolt, not a scoring strike.
        node.xScale = 1.0 / 6
        node.yScale = (top - point.y) * 1.1 / node.size.height
        glowers.addChild(node)
        spawnHitSpark(player: index, at: Vec2(x: Double(point.x) / SpriteLibrary.pixelsPerUnit, y: Double(point.y) / SpriteLibrary.pixelsPerUnit), scale: 0.25)
    }

    /// Pulsepistol Punch's pulse: a bar from the hand to the edge of the screen, eight
    /// pixels tall, in the player's colour, gone in a few frames; the pull runs it back
    /// toward the body.
    private func spawnPulse(by index: Int, pull: Bool) {
        let player = match.players[index]
        let hand = SpriteLibrary.point(Vec2(x: player.position.x, y: player.position.y + PulseRules.handHeight))
        let edge = player.facing == .right ? CGFloat(match.stage.columns) * GameScene.pixelsPerTile : 0
        let bar = SKSpriteNode(texture: sprites.flatSquare(size: 4, alpha: 1))
        bar.anchorPoint = CGPoint(x: player.facing == .right ? 0 : 1, y: 0.5)
        bar.position = hand
        bar.size = CGSize(width: abs(edge - hand.x), height: CGFloat(PulseRules.halfHeight * 2) * SpriteLibrary.pixelsPerUnit)
        bar.color = SKColor(rgb: sprites.look(for: index).glow)
        bar.colorBlendFactor = 1
        bar.blendMode = .add
        bar.alpha = pull ? 0.6 : 0.9
        bar.zPosition = 32
        bar.xScale = pull ? 1 : 0.05
        glowers.addChild(bar)
        let sweep = SKAction.scaleX(to: pull ? 0.05 : 1, duration: 0.08)
        bar.run(.sequence([sweep, .fadeOut(withDuration: 0.12), .removeFromParent()]))
    }

    /// The cape: its segments trail the body's last few positions while gliding, each a
    /// little behind the one before, so it flows.
    private func drawCape(_ index: Int, player: Player, behind body: CGPoint) {
        let segments = capes[index]
        guard player.power == .superSmoothie, player.state == .flying else {
            for segment in segments { segment.isHidden = true }
            capeTrails[index] = []
            return
        }
        let back = -CGFloat(player.facing.sign)
        let shoulder = CGPoint(x: body.x + back * 3, y: body.y + 22)
        var trail = capeTrails[index]
        trail.insert(shoulder, at: 0)
        if trail.count > GameScene.capeSegments * 2 { trail.removeLast(trail.count - GameScene.capeSegments * 2) }
        capeTrails[index] = trail
        var previous = shoulder
        for (step, segment) in segments.enumerated() {
            let at = min(step * 2, trail.count - 1)
            // Each segment hangs behind the shoulder and follows where the body has been,
            // with a wave running down the length so it flows even hovering still.
            let hang = CGPoint(x: shoulder.x + back * CGFloat(step) * 4, y: shoulder.y - CGFloat(step) * 0.8)
            let followed = CGPoint(x: (trail[at].x - shoulder.x) * 0.6, y: (trail[at].y - shoulder.y) * 0.6)
            let phase = Double(match.frame) / 5 - Double(step) * 0.8
            let wave = CGPoint(x: CGFloat(cos(phase)) * CGFloat(step) * 0.4, y: CGFloat(sin(phase)) * (1 + CGFloat(step) * 0.5))
            let here = CGPoint(x: hang.x + followed.x + wave.x, y: hang.y + followed.y + wave.y)
            segment.isHidden = false
            segment.position = here
            segment.zRotation = atan2(here.y - previous.y, here.x - previous.x)
            previous = here
        }
    }

    /// Bolts, ice clones, flames and fireballs, one node each by the sim's id, made when
    /// they appear and gone when they go.
    private func drawPowersLeavings() {
        var seen = Set<Int>()
        for bolt in match.bolts {
            seen.insert(bolt.id)
            let node = boltNodes[bolt.id] ?? {
                let node = SKSpriteNode(texture: sprites.symbol("bolt.fill", pointSize: 12))
                node.color = SKColor(rgb: sprites.look(for: bolt.owner).glow)
                node.colorBlendFactor = 1
                node.blendMode = .add
                node.zPosition = 8
                glowers.addChild(node)
                boltNodes[bolt.id] = node
                return node
            }()
            // An afterimage where it was, fading.
            if node.position != .zero {
                let ghost = SKSpriteNode(texture: node.texture)
                ghost.size = node.size
                ghost.color = node.color
                ghost.colorBlendFactor = 1
                ghost.blendMode = .add
                ghost.alpha = 0.45
                ghost.position = node.position
                ghost.zRotation = node.zRotation
                ghost.zPosition = 7
                glowers.addChild(ghost)
                ghost.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
            }
            node.position = SpriteLibrary.point(bolt.position)
            node.zRotation = CGFloat(Trig.atan2(bolt.velocity.y, bolt.velocity.x)) - .pi / 2 + (Double(match.frame % 2) == 0 ? 0.08 : -0.08)
        }
        for (id, node) in boltNodes where !seen.contains(id) {
            node.removeFromParent()
            boltNodes[id] = nil
        }

        seen = []
        for clone in match.clones {
            seen.insert(clone.id)
            let node = cloneNodes[clone.id] ?? {
                let owner = match.players[clone.owner]
                let frame = owner.animationFrame
                let node = SKSpriteNode(texture: sprites.texture(frame, player: clone.owner))
                node.size = node.texture!.size()
                node.anchorPoint = sprites.anchor(for: frame.animation)
                node.xScale = CGFloat(owner.facing.sign)
                node.color = GameScene.ice
                node.colorBlendFactor = 0.75
                node.alpha = 0.8
                node.position = SpriteLibrary.point(Vec2(x: clone.box.center.x, y: clone.box.min.y))
                node.zPosition = 6
                // Its head, where the body's sat that frame; the body's space is already flipped.
                if let head = sprites.landmark(.head, in: frame, player: clone.owner),
                   let headTexture = sprites.headTexture(frame, player: clone.owner),
                   let anchor = sprites.headAnchor(frame, player: clone.owner) {
                    let headNode = SKSpriteNode(texture: headTexture)
                    headNode.size = CGSize(width: headTexture.size().width * GameScene.headScale, height: headTexture.size().height * GameScene.headScale)
                    headNode.anchorPoint = anchor
                    headNode.color = GameScene.ice
                    headNode.colorBlendFactor = 0.75
                    headNode.position = CGPoint(x: head.x, y: head.y + GameScene.headLift)
                    headNode.zPosition = 1
                    node.addChild(headNode)
                }
                glowers.addChild(node)
                cloneNodes[clone.id] = node
                return node
            }()
            node.alpha = 0.3 + 0.5 * CGFloat(clone.framesLeft) / CGFloat(FrostRules.cloneFrames)
        }
        for (id, node) in cloneNodes where !seen.contains(id) {
            node.removeFromParent()
            cloneNodes[id] = nil
        }

        seen = []
        for flame in match.flames {
            seen.insert(flame.id)
            if flameNodes[flame.id] == nil {
                let frames = sprites.frames(Effect.fireTrail.name, count: Effect.fireTrail.frameCount)
                let node = SKSpriteNode(texture: frames[0])
                node.anchorPoint = Effect.fireTrail.anchor
                node.setScale(Effect.fireTrail.scale)
                node.position = SpriteLibrary.point(Vec2(x: flame.box.center.x, y: flame.box.min.y))
                node.zPosition = 4
                node.run(.repeatForever(.animate(with: frames, timePerFrame: 1 / Effect.fireTrail.fps)))
                glowers.addChild(node)
                flameNodes[flame.id] = node
            }
            flameNodes[flame.id]?.alpha = min(CGFloat(flame.framesLeft) / 12, 1)
        }
        for (id, node) in flameNodes where !seen.contains(id) {
            node.removeFromParent()
            flameNodes[id] = nil
        }

        seen = []
        for fireball in match.fireballs {
            seen.insert(fireball.id)
            let node = fireballNodes[fireball.id] ?? {
                let node = SKSpriteNode(texture: sprites.texture("ball", 0))
                node.color = GameScene.fireballColour
                node.colorBlendFactor = 1
                node.zPosition = 7
                let halo = makeHalo(GameScene.fireballColour)
                halo.zPosition = -1
                node.addChild(halo)
                glowers.addChild(node)
                fireballNodes[fireball.id] = node
                return node
            }()
            node.position = SpriteLibrary.point(fireball.position)
        }
        for (id, node) in fireballNodes where !seen.contains(id) {
            node.removeFromParent()
            fireballNodes[id] = nil
        }
    }

    // MARK: Drawing

    private func render() {
        stepHeadParticles()
        for (index, player) in match.players.enumerated() {
            let node = playerNodes[index]
            let frame = player.animationFrame
            // Zeus Juice's bolt throw with nothing in hand plays the whole sheet, its ball as energy.
            let wholeSheet = player.boltPose > 0 && !player.hasBall
            node.texture = sprites.texture(frame, player: index, ballAsEnergy: wholeSheet)
            node.size = node.texture!.size()
            node.anchorPoint = sprites.anchor(for: frame.animation)
            // A flight holding still hovers round a small circle, eased in and out.
            let stillFlight = player.state == .flying && player.velocity.length < 0.2
            hover[index] += ((stillFlight ? 1 : 0) - hover[index]) * 0.1
            let lap = Double(match.frame) / 60 / GameScene.hoverSeconds * 2 * .pi
            let drift = CGPoint(x: (cos(lap) * Double(GameScene.hoverRadius * hover[index])).rounded(),
                                y: (sin(lap) * Double(GameScene.hoverRadius * hover[index])).rounded())
            node.position = SpriteLibrary.point(player.position) + drift
            if player.state == .dunking {
                // Each frame of the dunk sits where its art was placed on the rim.
                let nudge = DunkArt.offsets[Animation.dunkEntry(at: player.stateTimer).index]
                node.position = node.position + CGPoint(x: nudge.x * CGFloat(player.facing.sign), y: nudge.y)
            }
            node.xScale = CGFloat(player.facing.sign)
            // Frozen, the body goes ice.
            node.color = GameScene.ice
            node.colorBlendFactor = player.frozen > 0 ? 0.6 : 0
            headNodes[index].color = GameScene.ice
            headNodes[index].colorBlendFactor = player.frozen > 0 ? 0.6 : 0

            // In flight the body leans into its motion: forward tips it ahead, backward tips
            // it back, up to thirty degrees, eased so it doesn't snap.
            var wantedTilt: CGFloat = 0
            if player.state == .flying {
                let ahead = player.velocity.x * player.facing.sign / SmoothieRules.flightSpeed(level: player.powerLevel, withBall: false)
                wantedTilt = -CGFloat(min(max(ahead, -1), 1)) * GameScene.flightTilt * CGFloat(player.facing.sign)
            }
            bodyTilt[index] += (wantedTilt - bodyTilt[index]) * 0.2
            node.zRotation = bodyTilt[index]

            // Hit by the blade, the body and head flicker white, every other pair of frames.
            let stunned = player.hitStun > 0 && (player.hitStun / 2) % 2 == 0
            for (flash, source) in [(stunBodies[index], node), (stunHeads[index], headNodes[index])] {
                flash.isHidden = !stunned || source.isHidden
                guard stunned else { continue }
                flash.texture = source.texture
                flash.size = source.size
                flash.anchorPoint = source.anchorPoint
                flash.position = source.position
                flash.xScale = source.xScale
                flash.yScale = source.yScale
                flash.zRotation = source.zRotation
            }

            // The frame's energy rides exactly where the body is drawn.
            let energyNode = energyNodes[index]
            if let energy = sprites.energyTexture(frame, player: index, ballAsEnergy: wholeSheet) {
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

            // The ball in hand rides the frame's ball, and when a dribble's ball hangs off a
            // ledge it reaches down to the real floor under it, over the same frames. Only
            // the dribble sheets do that: a stance or a throw keeps the ball where the frame
            // put it, so nothing sags off the edge of a slab.
            let halo = handHalos[index]
            let handBall = handBalls[index]
            // A fireball in hand rides where the ball would, in fire.
            let teamColour = SKColor(rgb: sprites.look(for: index).glow)
            handBall.color = player.hasFireball ? GameScene.fireballColour : teamColour
            halo.color = player.hasFireball ? GameScene.fireballColour : teamColour
            if player.holding, let inHand = sprites.landmark(.ball, in: frame, player: index) {
                let ballX = player.position.x + Double(inHand.x) * player.facing.sign / SpriteLibrary.pixelsPerUnit
                let dribbling = [Animation.dribbleIdle, .dribbleWalk, .dribbleRun].contains(frame.animation)
                let drop = player.grounded && dribbling ? match.stage.drop(fromX: ballX, y: player.position.y) * SpriteLibrary.pixelsPerUnit : 0
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
                // A sprite's size is set in its parent's units, so it's divided by whatever
                // scale the node has on: back to 1 first, or the scale below does nothing.
                charge.setScale(1)
                switch player.power {
                case .blazingBoba:
                    // Fire round the ball, the sheet looped, as painted.
                    let frame = player.stateTimer * Int(Effect.fireCharge.fps) / 60 % Effect.fireCharge.frameCount
                    charge.texture = sprites.texture(Effect.fireCharge.name, frame)
                    charge.size = charge.texture!.size()
                    charge.anchorPoint = Effect.fireCharge.anchor
                    charge.setScale(Effect.fireCharge.scale)
                case .zeusJuice:
                    let frame = player.stateTimer * Int(EnergyEffect.lightningCharge.fps) / 60 % EnergyEffect.lightningCharge.frameCount
                    charge.texture = sprites.effectTexture(EnergyEffect.lightningCharge.name, frame, player: index)
                    charge.size = charge.texture!.size()
                    charge.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    charge.setScale(CGFloat(ZeusTuning.chargeScale))
                default:
                    let played = player.stateTimer * Int(EnergyEffect.charge.fps) / 60
                    let loopStart = EnergyEffect.chargeLoopStart, loopEnd = EnergyEffect.chargeLoopEnd
                    let frame = played <= loopEnd ? played : loopStart + (played - loopStart) % (loopEnd - loopStart + 1)
                    charge.texture = sprites.effectTexture(EnergyEffect.charge.name, frame, player: index)
                    charge.size = charge.texture!.size()
                    charge.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                    charge.setScale(EnergyEffect.chargeScale)
                }
                charge.position = handBall.position
                charge.isHidden = false
                let overlay = chargeOverlays[index]
                if player.power == .blazingBoba {
                    let frame = player.stateTimer * Int(Effect.fireCharge2.fps) / 60 % Effect.fireCharge2.frameCount
                    overlay.setScale(1)
                    overlay.texture = sprites.texture(Effect.fireCharge2.name, frame)
                    overlay.size = overlay.texture!.size()
                    overlay.anchorPoint = Effect.fireCharge2.anchor
                    overlay.setScale(Effect.fireCharge2.scale)
                    overlay.position = handBall.position
                    overlay.isHidden = false
                } else {
                    overlay.isHidden = true
                }
            } else {
                charge.isHidden = true
                chargeOverlays[index].isHidden = true
                if charging[index], player.power != .blazingBoba, player.power != .zeusJuice,
                   player.state == .throwing || player.state == .dunking {
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
                emitHeadParticles(index, power: player.power, at: CGPoint(x: shown.x, y: shown.y + 4))
            } else {
                headNode.isHidden = true
                headEspers[index].particleBirthRate = 0
                headEsperMixes[index].particleBirthRate = 0
            }

            if match.stage.features.shadows {
                // The body and head cast down from the feet, flipped and sheared with the turf.
                let feet = SpriteLibrary.point(player.position).y
                let drop = CGFloat(match.stage.drop(fromX: player.position.x, y: player.position.y) * SpriteLibrary.pixelsPerUnit)
                castShadow(shadowBodies[index], of: node, anchorY: feet, facing: node.xScale, ground: feet - drop, rise: drop)
                castShadow(shadowHeads[index], of: headNode, anchorY: feet, facing: headNode.xScale, ground: feet - drop, rise: drop)
            }
            drawCape(index, player: player, behind: node.position)
            if player.power == .frostTea, player.state == .slide, match.frame % 3 == 0 {
                spawnSnowflakes(at: SpriteLibrary.point(player.position + Vec2(x: -player.facing.sign * 4, y: 2)), count: 2, spread: 6)
            }
            // Blazing Boba's skid: the fire sheet as the run stops.
            if player.power == .blazingBoba, player.state == .idle, lastStates[index] == .run || lastStates[index] == .dash {
                // The sheet skids the other way from the run sheets.
                spawn(.fireSkid, at: player.position, flipped: player.facing == .right)
            }
            lastStates[index] = player.state
        }
        drawPowersLeavings()
        drawField()
        drawTraffic()
        // Riders follow their body, the offset turned with it.
        riders.removeAll { $0.node.parent == nil }
        for rider in riders {
            let player = match.players[rider.player]
            let offset = Vec2(x: abs(rider.offset.x) * player.facing.sign, y: rider.offset.y)
            rider.node.position = SpriteLibrary.point(player.position + offset)
            rider.node.xScale = player.facing == .left ? -1 : 1
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

        drawPlatforms()

        let ball = match.ball
        ballNode.isHidden = ball.holder != nil
        ballNode.position = SpriteLibrary.point(ball.position)
        // Frozen it goes ice; burning it goes fire.
        let colour = ball.frozen > 0 ? GameScene.ice : (ball.burning ? GameScene.fireballColour : ballColour)
        ballNode.color = colour
        ballHalo.color = colour
        // The field's camera: level, gliding after the local player and leading them.
        if match.stage.features.look == .footballField {
            cameraBase.x += (cameraTargetX() - cameraBase.x) * GameScene.cameraEase
        }
        if match.stage.features.ballCam { easeBallCam() }
        placeBallCamFrame()
        // Quake-Up Coffee's shake: the camera a pixel or two off, a few frames.
        if shake > 0 {
            shake -= 1
            let wobble = CGFloat(shake % 2 == 0 ? 1 : -1) * CGFloat(min(shake, 4))
            cameraNode.position = CGPoint(x: cameraBase.x + wobble, y: cameraBase.y + wobble * 0.75)
        } else {
            cameraNode.position = cameraBase
        }
        glowHud.position = cameraNode.position
        ballTrail.position = ballNode.position
        ballTrail.particleColor = colour
        ballTrail.particleBirthRate = ball.isLive && !ball.resting && ball.velocity.length > 1 ? 90 : 0

        // Three dim chevrons stacked over a resting ball, lit one after another from the top, then
        // a beat with none, four steps a second so each one reads as a step.
        let step = (match.frame * 4 / 60) % 4
        let showChevrons = ball.isLive && ball.resting
        // Off the screen sideways, the chevrons sit at its edge at the ball's height, pointing at it.
        let halfView = size.width * cameraNode.xScale / 2
        let ballAt = SpriteLibrary.point(ball.position)
        let offSide: CGFloat? = ballAt.x > cameraNode.position.x + halfView ? 1 : (ballAt.x < cameraNode.position.x - halfView ? -1 : nil)
        for (index, chevron) in chevrons.enumerated() {
            if let side = offSide {
                chevron.isHidden = false
                chevron.zRotation = side > 0 ? .pi / 2 : -.pi / 2
                chevron.position = CGPoint(x: cameraNode.position.x + side * (halfView - 10 - CGFloat(index) * 7), y: ballAt.y)
                chevron.alpha = step == index ? 1 : 0.3
                continue
            }
            chevron.zRotation = 0
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
            // A rim that moves, under the highway's helicopter, and its net with it.
            if index < match.stage.hoops.count {
                let at = SpriteLibrary.point(match.stage.hoops[index].position)
                rimNodes[index].position = at
                if index < netNodes.count { netNodes[index].position = at }
            }
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

        drawHitboxes()
        // The count in title lettering, BALL OUT as it ends, and any other banner for its frames.
        if match.countdown > 0 {
            TitleText.set(banner, to: "\((match.countdown + 59) / 60)", size: 80)
            banner.isHidden = false
            bannerFrames = 0
        } else if lastCount > 0 {
            showBanner("BALL OUT!!!", size: 48)
        } else {
            tickBanner()
        }
        lastCount = match.countdown
        if roundIntro > 0 {
            for index in match.players.indices {
                playerNodes[index].isHidden = true
                headNodes[index].isHidden = true
                energyNodes[index].isHidden = true
                handBalls[index].isHidden = true
                handHalos[index].isHidden = true
                headEspers[index].particleBirthRate = 0
                headEsperMixes[index].particleBirthRate = 0
            }
        } else {
            for node in playerNodes { node.isHidden = false }
        }
        fpsLabel.text = "\(framesPerSecond) fps  worst \(worstFrameMilliseconds) ms"
        let p = match.players[localIndex]
        let side: String
        if online != nil {
            side = "  net lead \(session.frame - session.remoteFrame) rollbacks \(session.rollbacks)/\(session.framesRerun)\(session.desynced ? "  DESYNC" : "")"
        } else {
            side = aiOn ? "  ai \(String(describing: opponent.current))" : ""
        }
        debugLabel.text = String(format: "%@ %d  v %.2f %.2f  jumps %d%@%@%@",
                                 String(describing: p.state), p.stateTimer, p.velocity.x, p.velocity.y, p.jumpsLeft,
                                 p.hasBall ? "  ball" : "", hub.playerOneHasController ? "  pad" : "", side)
        let labels = buttonLabels(for: p)
        controls?.setLabels(jump: labels.jump, shoot: labels.shoot, throwBall: labels.throwBall)
        let powerName = Greateraid.biomorphs.first { $0.power == p.power }?.name.uppercased() ?? "NO POWER"
        TitleText.set(powerLabel, to: p.power == .none ? powerName : "\(powerName) L\(p.powerLevel)", size: 12)
    }

    /// What each button would do for this player right now.
    private func buttonLabels(for player: Player) -> (jump: String, shoot: String, throwBall: String) {
        let airborne = !player.grounded && !player.state.isGroundState
        let jump: String
        switch player.power {
        case .superSmoothie where airborne: jump = "FLY"
        case .webWater where airborne: jump = "SWING"
        case .flashFizz where airborne: jump = "FLASH"
        default: jump = "JUMP"
        }
        let shoot: String
        if player.holding {
            shoot = "SHOOT"
        } else if player.state == .crouch || player.state == .crouchWalk {
            shoot = "SLIDE"
        } else {
            switch player.power {
            case .flashFizz where match.ball.owner == player.index: shoot = "WARP"
            case .platformShake where player.powerLevel >= 2: shoot = "WALL"
            case .zeusJuice: shoot = "BOLT"
            case .pulsepistol: shoot = "PULSE"
            default: shoot = "SLASH"
            }
        }
        let throwBall: String
        if player.holding {
            throwBall = "THROW"
        } else {
            switch player.power {
            case .webWater where player.powerLevel >= 2: throwBall = "WEB"
            case .pulsepistol where player.powerLevel >= 2: throwBall = "PULL"
            default: throwBall = "SNATCH"
            }
        }
        return (jump, shoot, throwBall)
    }

    /// The sim's boxes, rebuilt each frame while the toggle is on: bodies white, the loose
    /// ball purple, the catch reach a faint ring, the slide's leg and the slash's blade
    /// red, the snatch's reach green.
    private func drawHitboxes() {
        hitboxLayer.removeAllChildren()
        guard showHitboxes else { return }
        func outline(_ box: Box, _ colour: SKColor) {
            let low = SpriteLibrary.point(box.min), high = SpriteLibrary.point(box.max)
            let node = SKShapeNode(rect: CGRect(x: low.x, y: low.y, width: high.x - low.x, height: high.y - low.y))
            node.strokeColor = colour
            node.lineWidth = 1
            hitboxLayer.addChild(node)
        }
        for player in match.players {
            outline(player.body, .white)
            for (centre, radius) in [(player.chest, BallRules.catchRadius), (player.handCatchPoint, BallRules.handCatchRadius)] {
                let reach = SKShapeNode(circleOfRadius: CGFloat(radius * SpriteLibrary.pixelsPerUnit))
                reach.position = SpriteLibrary.point(centre)
                reach.strokeColor = SKColor(white: 1, alpha: 0.3)
                reach.lineWidth = 1
                hitboxLayer.addChild(reach)
            }
            if let leg = player.slideHitbox { outline(leg, .red) }
            if let blade = player.slashHitbox { outline(blade, .red) }
            if let hand = player.snatchHitbox {
                outline(hand, .green)
                let ring = SKShapeNode(circleOfRadius: CGFloat(BallRules.handCatchRadius * SpriteLibrary.pixelsPerUnit))
                ring.position = SpriteLibrary.point(player.handCatchPoint)
                ring.strokeColor = .green
                ring.lineWidth = 1
                hitboxLayer.addChild(ring)
            }
            if let tear = player.tear {
                let ring = SKShapeNode(circleOfRadius: CGFloat(FizzRules.tearRadius * SpriteLibrary.pixelsPerUnit))
                ring.position = SpriteLibrary.point(tear.position)
                ring.strokeColor = .cyan
                ring.lineWidth = 1
                hitboxLayer.addChild(ring)
            }
        }
        if match.ball.holder == nil {
            outline(match.ball.box, SKColor(rgb: BallLook.neutral))
        }
    }

    // MARK: Touches, from the HUD's view in points

    /// A point in the view as a point in the HUD's space: the same points, from the centre, y up.
    private func hudPoint(_ point: CGPoint, viewSize: CGSize) -> CGPoint {
        CGPoint(x: (point.x - viewSize.width / 2) / hudScale, y: (viewSize.height / 2 - point.y) / hudScale)
    }

    func touchBegan(_ touch: UITouch, at point: CGPoint, viewSize: CGSize) {
        if flow != .playing, let screen {
            _ = screen.tap(at: hudPoint(point, viewSize: viewSize))
            return
        }
        controls?.began(touch, at: hudPoint(point, viewSize: viewSize))
    }

    func touchMoved(_ touch: UITouch, to point: CGPoint, viewSize: CGSize) {
        controls?.moved(touch, to: hudPoint(point, viewSize: viewSize))
    }

    func touchEnded(_ touch: UITouch) {
        controls?.ended(touch)
    }
}
