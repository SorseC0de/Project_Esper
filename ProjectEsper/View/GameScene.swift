import EsperSim
import SpriteKit
import simd

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, factor: CGFloat) -> CGPoint { CGPoint(x: a.x * factor, y: a.y * factor) }
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
    private var session = RollbackSession(match: Match(stage: .court, countdown: GameScene.countdownFrames), localIndex: 0)
    private var match: Match { session.match }
    /// The computer on the other side, when the AI switch is on; never online.
    private var opponent = Opponent(index: 1)
    /// VS CPU: the computer plays player 2, whatever pads are in; off, player 2 is the
    /// second pad. The title's toggle, the AI button and R3 all set it, kept between launches.
    static let vsCPUKey = InputHub.vsCPUKey
    private var aiOn: Bool {
        get { UserDefaults.standard.object(forKey: GameScene.vsCPUKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: GameScene.vsCPUKey) }
    }

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
        var theirColour: EnergyColour?
        var theirMode: GameMode?
        var theirStageVote: (stagesPlayed: Int, choice: Int)?
    }
    private var online: Online?
    private var localIndex: Int { online?.localIndex ?? 0 }
    /// Who drinks this round, and the frames left to choose online.
    private var picker = 1
    private var pickFramesLeft = 0

    /// The game loop round the sim: the title, the stage select, a best of seven, a drink
    /// between rounds for whoever was scored on, the pause, and the win.
    private enum Flow { case title, stageSelect, playing, picking, paused, won }
    private var flow = Flow.title
    private var series = Series(seed: 1)
    /// What the match is played to; online, the host's.
    private var gameMode = GameMode.rounds
    /// The mode multiplayer asks for, kept between launches.
    static let onlineModeKey = "esper.onlineMode"
    static var savedOnlineMode: GameMode {
        GameMode(rawValue: UInt8(UserDefaults.standard.integer(forKey: onlineModeKey))) ?? .rounds
    }
    private var screen: Screen?
    /// The bottles on offer while picking, kept so a re-laid-out screen shows the same.
    private var pickOffers: [Greateraid] = []
    /// A flow change held back for the strike to play, until the sim reaches this frame;
    /// online both phones stop the sim on that frame and change together.
    private var pendingFlow: Flow?
    private var pendingFlowFrame = 0
    /// The stage select: who votes, the votes in, the coin flip's landing and its frames
    /// left, whether the drink pick follows it, and the stage the series started on.
    private var stageVoters: [Int] = []
    private var stageVotes: [Int: StageChoice] = [:]
    private var stageLanding: StageChoice?
    private var stageFlipFrames = 0
    private static let stageFlipLength = 90
    private var pickAfterStage = false
    private var firstStage = StageChoice.wreckCenter
    /// What the computer drank at the end of a stage, lettered once play is back.
    private var heldBanner: String?
    /// Each side's energy colour, for the names on the screens.
    private var sideColours = EnergyColour.pair(first: EnergyColour.saved, second: .teal)
    private static let flowDelayFrames = 60
    /// Frames the bodies stay hidden while the bolts bring them in, and the count's last
    /// value, to catch it reaching zero.
    private var roundIntro = 0
    private var lastCount = 0
    private var lastCountSounded = 0
    /// Title lettering over the court: the count, BALL OUT, BUCKET, what the computer
    /// drank, one after another; the round circles; and each side's drinks beside them.
    private let banner = SKSpriteNode()
    private var bannerFrames = 0
    private var bannerQueue: [(text: String, size: CGFloat)] = []
    private static let bannerHold = 45
    private let circles = SKNode()
    /// The same circles in the HUD, over the ball cam, which is laid down after the world;
    /// shown only while it is, the glowing ones beneath.
    private let circlesOverCam = SKNode()
    private var drinkLabels: [SKLabelNode] = []
    private var menuLast = PlayerInput.idle
    /// After a menu press, nothing more is picked until A has been let go: a press is one
    /// pick, on this screen or whatever it opens.
    private var menuNeedsRelease = false
    /// This phone's input as last read, for the corner readout.
    private var lastLocalInput = PlayerInput.idle
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
    /// The line round each body, a child of it so it rides the body exactly, drawn in white
    /// and coloured each frame: the look's outline, or the zone's.
    private var outlineNodes: [SKSpriteNode] = []
    /// Each player's figure, all of it, in one layer; the one in front a little higher.
    private var figureLayers: [SKNode] = []
    private var frontFigure = 0
    /// Pulsepistol Punch's snipe cursor, one a player, shown while they're prone.
    private var snipeCursors: [SKSpriteNode] = []
    private static let snipeCursorSize: CGFloat = 20
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
    /// Titan Tea's running steps shake the screen this much.
    private static let titanStepShake = 3
    /// Titan Tea after its port-in: frames before it grows, and its growth from the
    /// ordinary size to its own, 0 to 1, over `titanGrowFrames`, drawn white while it grows.
    private var titanGrowDelay: [Int] = []
    private var titanGrowth: [CGFloat] = []
    private static let titanGrowFrames = 30
    private var cameraBase = CGPoint.zero
    private var cameraBaseScale: CGFloat = 1
    /// The HUD's scale for this screen, and the ice everything frozen goes.
    private var hudScale: CGFloat = 1
    private var displayScale: CGFloat = 1
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
    /// The opponent off the screen sideways: a chevron in their energy at that edge, at
    /// their chest's height, pointing at them.
    private var opponentChevron = SKSpriteNode()
    /// The ball's chevrons: yellow over it at rest, purple outlined in dark purple at the
    /// screen's edge when it's off it.
    private lazy var ballChevronOver = sprites.symbol("chevron.down", pointSize: 14)
    private lazy var ballChevronOffScreen = sprites.outlinedSymbol("chevron.down", pointSize: 14,
                                                                   fill: SKColor(rgb: BallLook.neutral), stroke: SKColor(rgb: BallLook.darkPurple))
    /// The floor and walls, coloured for whoever holds the ball.
    private var courtTiles: [SKSpriteNode] = []
    private var courtColour = SKColor(rgb: CourtLook.neutral)
    private var courtTarget = SKColor(rgb: CourtLook.neutral)
    private var courtShift = 0
    /// A score's flash on the floor and walls: frames until it, then how white they are, fading.
    private var courtWhiteIn = 0
    private var courtWhite: CGFloat = 0
    /// Each hoop in two layers under the bodies: its backboard, then the net, then its rim.
    private var backboardNodes: [SKSpriteNode] = []
    private var rimNodes: [SKSpriteNode] = []
    private var rimFlash: [Int] = []
    private var previewDots: [SKSpriteNode] = []
    private static let webAimDots = 12
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
    /// Each render stage's milliseconds a frame, CPU and GPU, from the Metal view.
    var frameReadout = ""
    /// Where `update` spends its time, by section, for the readout; taken once a second.
    private var sectionTimes: [String: Double] = [:]
    private var sectionMark = 0.0
    private func section(_ name: String) {
        let now = CACurrentMediaTime()
        sectionTimes[name, default: 0] += now - sectionMark
        sectionMark = now
    }
    func takeSectionTimes() -> [String: Double] {
        defer { sectionTimes = [:] }
        return sectionTimes
    }

    /// The bodies as drawn this frame, for the mask scene to copy.
    var bodySnapshots: [BodySnapshot] {
        playerNodes.filter { !$0.isHidden }.compactMap { node in
            // A human's energy-coloured parts left out, so they glow.
            node.texture.map { BodySnapshot(texture: sprites.glowMask(for: $0), position: node.position, anchor: node.anchorPoint, xScale: node.xScale, size: node.size, zRotation: node.zRotation) }
        }
    }

    /// The bodies and their lines whole, for the cubes behind the players to keep out of.
    var occluderSnapshots: [BodySnapshot] {
        var bodies: [BodySnapshot] = []
        for (body, outline) in zip(playerNodes, outlineNodes) where !body.isHidden {
            for texture in [body.texture, outline.isHidden ? nil : outline.texture].compactMap({ $0 }) {
                bodies.append(BodySnapshot(texture: texture, position: body.position, anchor: body.anchorPoint, xScale: body.xScale,
                                           size: body.size, zRotation: body.zRotation))
            }
        }
        return bodies
    }

    /// What's drawn in the world but must not glow, for the mask to mark: the hoops and the banner.
    var flatSnapshots: [BodySnapshot] {
        // The hoops: their backboards read too hot with the glow on them.
        var flat = (backboardNodes + rimNodes).filter { !$0.isHidden }.compactMap { rim in
            rim.texture.map { BodySnapshot(texture: $0, position: rim.position, anchor: rim.anchorPoint, xScale: rim.xScale, size: rim.size) }
        }
        // The snipe's cursors, drawn as they are.
        for cursor in snipeCursors where !cursor.isHidden {
            if let texture = cursor.texture {
                flat.append(BodySnapshot(texture: texture, position: cursor.position, anchor: cursor.anchorPoint, xScale: 1, size: cursor.size))
            }
        }
        // The bodies' lines, which are drawn as they are and never glow.
        for (body, outline) in zip(playerNodes, outlineNodes) where !body.isHidden && !outline.isHidden {
            if let texture = outline.texture {
                flat.append(BodySnapshot(texture: texture, position: body.position, anchor: body.anchorPoint, xScale: body.xScale,
                                         size: body.size, zRotation: body.zRotation))
            }
        }
        guard !banner.isHidden, let texture = banner.texture else { return flat }
        let scale = glowHud.xScale
        flat.append(BodySnapshot(texture: texture,
                                 position: CGPoint(x: glowHud.position.x + banner.position.x * scale, y: glowHud.position.y + banner.position.y * scale),
                                 anchor: banner.anchorPoint, xScale: 1,
                                 size: CGSize(width: banner.size.width * scale, height: banner.size.height * scale)))
        return flat
    }

    // MARK: Ball cam

    /// Only in play: not on the title, the drink pick or the win.
    var ballCamEnabled: Bool { match.stage.features.ballCam && playing && flow == .playing }
    private var playing: Bool { built && !playerNodes.isEmpty }

    /// Where the ball is, in art pixels, held or loose.
    var ballCamCentre: CGPoint {
        let ball = match.ball
        let at = ball.holder.map { match.players[$0].heldBallPoint } ?? ball.position
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

    /// The cam's middle across the screen, 0 to 1: the centre, wherever the local player is.
    let ballCamScreenX: CGFloat = 0.5

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
        if ballCamStale {
            camScene.scenery.removeAllChildren()
            camScene.built = false
            ballCamStale = false
        }
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
            for name in ["backboard", "hoop"] {
                let art = SKSpriteNode(texture: sprites.texture(name, 0))
                art.position = GameScene.hoopArtPoint(for: hoop)
                art.xScale = hoop.backboard == .left ? -1 : 1
                art.zPosition = name == "hoop" ? 6 : 5
                camScene.scenery.addChild(art)
            }
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
        self.displayScale = displayScale
        layout(displayScale: displayScale)
    }

    // MARK: Building

    private func build() {
        // The vehicles' shapes as last set in the bounds gallery, offline.
        BoundsGallery.loadSaved()
        // The colours as last picked, before anything is drawn in them.
        for (index, colour) in EnergyColour.pair(first: EnergyColour.saved, second: .teal).enumerated() {
            sprites.setLook(colour.look, for: index)
        }
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
        // One of each way of drawing the game uses, so SpriteKit builds their pipelines now
        // and not the first time one appears mid-match: additive and tinted sprites, a
        // stroked and a filled shape, an emitter, a crop and a label.
        if let sample = sprites.allTextures.first {
            let additive = SKSpriteNode(texture: sample)
            additive.blendMode = .add
            let tinted = SKSpriteNode(texture: sample)
            tinted.color = .white
            tinted.colorBlendFactor = 1
            let additiveTinted = SKSpriteNode(texture: sample)
            additiveTinted.blendMode = .add
            additiveTinted.color = .white
            additiveTinted.colorBlendFactor = 1
            // The energy's toning shader, compiled now rather than on the first slash.
            let toned = SKSpriteNode(texture: sample)
            toned.shader = energyToneShader
            setGlow(toned, .white)
            for sprite in [additive, tinted, additiveTinted, toned] {
                sprite.size = CGSize(width: 1, height: 1)
                sprite.alpha = 0.02
                warmNode.addChild(sprite)
            }
            let crop = SKCropNode()
            crop.maskNode = SKSpriteNode(texture: sample, size: CGSize(width: 1, height: 1))
            let cropped = SKSpriteNode(texture: sample, size: CGSize(width: 1, height: 1))
            cropped.alpha = 0.02
            crop.addChild(cropped)
            warmNode.addChild(crop)
        }
        let stroke = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 2, height: 2))
        stroke.strokeColor = SKColor(white: 1, alpha: 0.02)
        let fill = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 2, height: 2))
        fill.fillColor = SKColor(white: 1, alpha: 0.02)
        fill.strokeColor = .clear
        let label = SKLabelNode(text: "0")
        label.fontName = "Menlo-Bold"
        label.fontSize = 2
        label.alpha = 0.02
        let emitter = makeTrail()
        emitter.particleAlpha = 0.02
        emitter.particleBirthRate = 30
        for node in [stroke, fill, label, emitter] as [SKNode] { warmNode.addChild(node) }
        warmNode.zPosition = 90
        glowHud.addChild(warmNode)

        ground.addChild(stageGround)
        glowers.addChild(stageGlowers)
        buildStage()

        for player in match.players {
            // Everything drawn on one figure in one layer, so a whole body is in front of or
            // behind the other, its line and all; the figure's own depths packed under 0.1.
            let figure = SKNode()
            bodies.addChild(figure)
            figureLayers.append(figure)
            let node = SKSpriteNode(texture: sprites.texture(player.animationFrame, player: player.index))
            figure.addChild(node)
            playerNodes.append(node)
            let outline = SKSpriteNode()
            outline.colorBlendFactor = 1
            outline.zPosition = 0.005
            node.addChild(outline)
            outlineNodes.append(outline)
            let cursor = SKSpriteNode(texture: SKTexture(imageNamed: "Crosshair"))
            cursor.size = CGSize(width: GameScene.snipeCursorSize, height: GameScene.snipeCursorSize)
            cursor.zPosition = 40
            cursor.isHidden = true
            glowers.addChild(cursor)
            snipeCursors.append(cursor)
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
            head.zPosition = 0.04
            figure.addChild(head)
            headNodes.append(head)
            let energy = SKSpriteNode()
            energy.zPosition = 0.03
            energy.isHidden = true
            energy.shader = energyToneShader
            figure.addChild(energy)
            energyNodes.append(energy)
            let charge = SKSpriteNode()
            charge.zPosition = 0.05
            charge.isHidden = true
            charge.setScale(EnergyEffect.chargeScale)
            figure.addChild(charge)
            chargeNodes.append(charge)
            let overlay = SKSpriteNode()
            overlay.zPosition = 0.06
            overlay.isHidden = true
            figure.addChild(overlay)
            chargeOverlays.append(overlay)
            charging.append(false)
            for flashes in [\GameScene.stunBodies, \GameScene.stunHeads] {
                // Stunned, the body flickers to a dark shade of its energy.
                let flash = SKSpriteNode()
                flash.color = SKColor(rgb: sprites.look(for: player.index).energyTone(luminance: 0.15))
                flash.colorBlendFactor = 1
                flash.blendMode = .alpha
                flash.alpha = 0.85
                flash.zPosition = 0.09
                flash.isHidden = true
                figure.addChild(flash)
                self[keyPath: flashes].append(flash)
            }
            headShown.append(.zero)
            bodyTilt.append(0)
            hover.append(0)
            titanGrowDelay.append(0)
            titanGrowth.append(1)
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
                segment.zPosition = 0.02
                segment.isHidden = true
                figure.addChild(segment)
                segments.append(segment)
            }
            capes.append(segments)
            capeTrails.append([])
            let colour = SKColor(rgb: sprites.look(for: player.index).glow)
            let handBall = SKSpriteNode(texture: sprites.texture("ball", 0))
            handBall.color = colour
            handBall.colorBlendFactor = 1
            handBall.zPosition = 0.03
            figure.addChild(handBall)
            handBalls.append(handBall)
            let halo = makeHalo(colour)
            halo.zPosition = 0.02
            figure.addChild(halo)
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
        opponentChevron = SKSpriteNode(texture: sprites.outlinedSymbol("chevron.down", pointSize: 14, fill: .white, stroke: SKColor(rgb: PixelPalette.outline)))
        opponentChevron.colorBlendFactor = 1
        opponentChevron.zPosition = 6
        opponentChevron.isHidden = true
        glowers.addChild(opponentChevron)
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
        circlesOverCam.zPosition = 5
        circlesOverCam.isHidden = true
        hud.addChild(circlesOverCam)
        for index in 0..<2 {
            let label = SKLabelNode()
            label.fontName = "Menlo-Bold"
            label.fontSize = 8
            label.fontColor = SKColor(rgb: sprites.look(for: index).glow)
            sideLabels.append(label)
            label.horizontalAlignmentMode = index == 0 ? .right : .left
            label.verticalAlignmentMode = .top
            label.numberOfLines = 0
            label.zPosition = 5
            hud.addChild(label)
            drinkLabels.append(label)
        }
        drawSeries()
        flowState?.startSeries = { [weak self] mode in self?.startSeries(mode: mode) }
        flowState?.net.onConnected = { [weak self] in
            // Connected: the multiplayer screen gives way to the match.
            self?.flowState?.multiplayerOpen = false
            self?.startOnline()
        }
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
        fpsLabel.numberOfLines = 0
        hud.addChild(fpsLabel)
    }

    // MARK: The stage

    /// Everything drawn for one stage, in its own layers so a stage change can take it all
    /// away: the tiles or the scenery, the rims and their nets.
    private let stageGround = SKNode()
    private let stageGlowers = SKNode()
    /// Cropped to the court's inside, the walls and the floor cutting the lines off.
    private let threePointArcs = SKCropNode()
    private var threePointArcSides: [(node: SKShapeNode, side: Int)] = []
    /// The stage the world is drawn for, and the ball cam's scenery due a redraw.
    private var builtStage = StageChoice.wreckCenter
    private var ballCamStale = false

    private func buildStage() {
        // The floor and walls take the holder's colour, the backboard blocks keep their rim's
        // owner's, and the ledge is magenta.
        let stage = match.stage
        if stage.features.look == .highway {
            HighwayArt.build(for: stage, into: stageGround) { [sprites] size in sprites.flatSquare(size: Int(size), alpha: 1) }
        }
        if stage.features.look == .footballField {
            // The field: scenery in place of tiles, the floor invisible through the turf.
            let handles = FieldArt.build(for: stage, into: stageGround, flat: { [sprites] size in sprites.flatSquare(size: Int(size), alpha: 1) },
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
                    stageGround.addChild(call)
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
                    stageGround.addChild(chevron)
                    railChevrons.append(chevron)
                    railChevronHomes.append(x)
                    x += 14
                }
            }
            goalpostShadows.shouldRasterize = true
            goalpostShadows.alpha = FieldArt.shadowAlpha
            goalpostShadows.zPosition = -6
            stageGround.addChild(goalpostShadows)
            stageGround.addChild(goalposts)
            buildGoalposts()
            stageGlowers.addChild(backboards)
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
                    blockTiles.append((node, 1 - hoop.owner))
                } else {
                    node.color = courtColour
                    courtTiles.append(node)
                }
                stageGround.addChild(node)
            }
        }

        // 47's three-point lines: the half of a circle round each rim that faces the middle,
        // dim, glowing, in the colour of the side guarding that rim. Shown in 47 only.
        threePointArcs.removeAllChildren()
        threePointArcs.zPosition = -30
        threePointArcs.isHidden = gameMode != .fortySeven
        let inside = CGRect(x: GameScene.pixelsPerTile, y: GameScene.pixelsPerTile,
                            width: CGFloat(stage.columns - 2) * GameScene.pixelsPerTile,
                            height: CGFloat(stage.rows + Stage.skyRows) * GameScene.pixelsPerTile)
        let mask = SKSpriteNode(color: .white, size: inside.size)
        mask.anchorPoint = .zero
        mask.position = inside.origin
        threePointArcs.maskNode = mask
        stageGlowers.addChild(threePointArcs)
        // Under the floor's row, the outline black, all the way down and out.
        if !stage.features.scenic {
            let under = SKSpriteNode(color: SKColor(rgb: PixelPalette.outline), size: CGSize(width: CGFloat(stage.columns) * GameScene.pixelsPerTile + 4000, height: 2000))
            under.anchorPoint = CGPoint(x: 0.5, y: 1)
            under.position = CGPoint(x: CGFloat(stage.columns) * GameScene.pixelsPerTile / 2, y: 0)
            under.zPosition = -20
            stageGround.addChild(under)
        }
        for hoop in stage.hoops {
            let radius = CGFloat(FortySevenRules.threePointRadius(for: hoop, on: stage) * SpriteLibrary.pixelsPerUnit)
            let facingMiddle: CGFloat = hoop.backboard == .left ? 0 : .pi
            // Each end runs on straight to the screen's edge on the rim's side, well past the
            // wall, as a real line meets the baseline.
            let run = CGFloat(hoop.backboard.sign) * 1000
            let path = CGMutablePath()
            path.move(to: CGPoint(x: run, y: -radius))
            path.addLine(to: CGPoint(x: 0, y: -radius))
            path.addArc(center: .zero, radius: radius, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: facingMiddle != 0)
            path.addLine(to: CGPoint(x: run, y: radius))
            let arc = SKShapeNode(path: path)
            arc.position = SpriteLibrary.point(hoop.position)
            arc.strokeColor = SKColor(rgb: sprites.look(for: 1 - hoop.owner).glow)
            arc.lineWidth = ThreePointTuning.lineWidth
            arc.alpha = 0
            arc.blendMode = .add
            threePointArcs.addChild(arc)
            threePointArcSides.append((arc, 1 - hoop.owner))
        }
        for hoop in stage.hoops {
            // `backboard`, the net, then `hoop`, the rim, all under the bodies, drawn to the
            // players' scale on one canvas that keeps them together, the backboard on the right.
            // TODO: twitch physics on the rim, its own layer for it.
            let backboard = SKSpriteNode(texture: sprites.texture("backboard", 0))
            backboard.position = GameScene.hoopArtPoint(for: hoop)
            backboard.zPosition = 5
            backboard.xScale = hoop.backboard == .left ? -1 : 1
            stageGround.addChild(backboard)
            backboardNodes.append(backboard)
            let rim = SKSpriteNode(texture: sprites.texture("hoop", 0))
            rim.position = GameScene.hoopArtPoint(for: hoop)
            rim.xScale = hoop.backboard == .left ? -1 : 1
            rim.zPosition = 6
            stageGround.addChild(rim)
            rimNodes.append(rim)
            rimFlash.append(0)
            nets.append(HoopNet(at: GameScene.netPoint(for: hoop), mirrored: hoop.backboard == .left, colour: SKColor(rgb: sprites.look(for: 1 - hoop.owner).glow),
                                into: stageGround, depth: 5.5))
        }
        warmDrawnArt()
    }

    /// The world redrawn for the series' stage, if it isn't the one drawn.
    private func showStage() {
        guard built, series.stage != builtStage else { return }
        stageGround.removeAllChildren()
        stageGlowers.removeAllChildren()
        courtTiles = []
        blockTiles = []
        threePointArcSides = []
        backboardNodes = []
        rimNodes = []
        rimFlash = []
        nets = []
        fieldBlooms = []
        lightPanels = []
        yardNumbers = []
        railCalls = []
        railChevrons = []
        railChevronHomes = []
        helmetNodes = [:]
        carNodes = [:]
        carFlash = [:]
        carDip = [:]
        helicopterNode = nil
        portalNode = nil
        riftPlates = []
        downMarker = nil
        closeBoundsGallery()
        buildStage()
        builtStage = series.stage
        ballCamStale = true
        cameraBase = .zero
        cameraZone = nil
        layout(displayScale: displayScale)
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
        cameraBaseScale = cameraNode.xScale
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
        controls.onPause = { [weak self] in
            guard let self, self.online == nil, self.flow == .playing else { return }
            self.enter(.paused)
        }
        controls.showHitboxes = showHitboxes
        controls.onToggleHitboxes = { [weak self] on in self?.showHitboxes = on }
        controls.aiOn = aiOn
        controls.onToggleAI = { [weak self] on in self?.aiOn = on }
        controls.addPicker(title: "HEAD", options: HeadVariant.allCases.map(\.label), selected: headVariant.rawValue) { [weak self] index in
            self?.headVariant = HeadVariant(rawValue: index)!
        }
        controls.addPicker(title: "POWER", options: PowerVariant.allCases.map(\.label), selected: powerVariant.rawValue, perRow: 6) { [weak self] index in
            self?.powerVariant = PowerVariant(rawValue: index)!
            self?.applyPower()
        }
        controls.addPicker(title: "COUNT", options: ["A", "B"], selected: UserDefaults.standard.integer(forKey: SoundBoard.countSetKey)) { index in
            UserDefaults.standard.set(index, forKey: SoundBoard.countSetKey)
        }
        controls.addPicker(title: "LEVEL", options: PowerLevelVariant.allCases.map(\.label), selected: powerLevelVariant.rawValue) { [weak self] index in
            self?.powerLevelVariant = PowerLevelVariant(rawValue: index)!
            self?.applyPower()
        }
        // The bounds gallery only means anything on the highway.
        if match.stage.features.traffic {
            controls.addPicker(title: "BOUNDS", options: ["OFF", "ON"], selected: boundsGallery == nil ? 0 : 1) { [weak self] index in
                index == 1 ? self?.openBoundsGallery() : self?.closeBoundsGallery()
            }
        }
        if ParticleLook.cubes && ParticleLook.cubeSliders {
            controls.addSlider(title: "CUBE SIZE", range: 1...8, notch: 1, value: ParticleLook.cubeSize) { ParticleLook.cubeSize = $0 }
            controls.addSlider(title: "CUBE SPREAD", range: 0...16, notch: 1, value: ParticleLook.cubeSpread) { ParticleLook.cubeSpread = $0 }
            controls.addSlider(title: "LEG CUBE SIZE", range: 1...8, notch: 1, value: ParticleLook.legCubeSize) { ParticleLook.legCubeSize = $0 }
            controls.addSlider(title: "LEG CUBE SPREAD", range: 0...16, notch: 1, value: ParticleLook.legCubeSpread) { ParticleLook.legCubeSpread = $0 }
            if HumanLook.enabled {
                // How far down the head the energy's grade reaches; every frame redrawn to it.
                controls.addSlider(title: "HEAD GRADIENT", range: 0...1, notch: 0.01, value: Float(HumanLook.headEnergyShare)) { [weak self] value in
                    guard Double(value) != HumanLook.headEnergyShare else { return }
                    HumanLook.headEnergyShare = Double(value)
                    self?.sprites.redrawPlayers()
                }
            }
        }
        if DunkTuning.enabled {
            // The court's rims lowered, the hanging body and the hoop's art with them.
            controls.addSlider(title: "RIM DROP", range: 0...40, notch: 1, value: Float(Stage.courtRimDrop)) { [weak self] value in
                Stage.courtRimDrop = Double(value)
                self?.moveCourtRims()
            }
            // Toward the block, the rim, the body and the art with it.
            controls.addSlider(title: "RIM DEPTH", range: -20...20, notch: 1, value: Float(Stage.courtRimDepth)) { [weak self] value in
                Stage.courtRimDepth = Double(value)
                self?.moveCourtRims()
            }
            let last = Float(Animation.dunkSequence.count - 1)
            let xSlider = controls.addSlider(title: "DUNK X", range: -32...32, notch: 1, value: Float(DunkArt.offsets[DunkTuning.frame].x)) {
                DunkArt.offsets[DunkTuning.frame].x = CGFloat($0)
            }
            let ySlider = controls.addSlider(title: "DUNK Y", range: -32...32, notch: 1, value: Float(DunkArt.offsets[DunkTuning.frame].y)) {
                DunkArt.offsets[DunkTuning.frame].y = CGFloat($0)
            }
            controls.addSlider(title: "HOOP X", range: -24...24, notch: 1, value: Float(HoopTuning.offset.x)) { HoopTuning.offset.x = CGFloat($0) }
            controls.addSlider(title: "HOOP Y", range: -24...24, notch: 1, value: Float(HoopTuning.offset.y)) { HoopTuning.offset.y = CGFloat($0) }
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
        circlesOverCam.position = circles.position
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
        accumulator += min(currentTime - last, 0.1) * (finishFrames > 0 && online == nil ? GameScene.finishTimeScale : 1)
        guard accumulator >= GameScene.stepSeconds else { return }

        if let next = pendingFlow, match.frame >= pendingFlowFrame {
            pendingFlow = nil
            enter(next)
        }
        if roundIntro > 0 { roundIntro -= 1 }
        hub.touch = flow == .playing ? controls?.sample() ?? .idle : .idle
        let inputs = hub.frames(players: match.players.count)
        lastLocalInput = inputs.first ?? .idle
        tickOnline()
        // Start or delete pauses a match offline, and again resumes it.
        if hub.consumePause(), online == nil {
            if flow == .playing {
                menuLast = inputs.first ?? .idle
                enter(.paused)
            } else if flow == .paused {
                SoundBoard.shared.play(.menuBack)
                enter(.playing)
            }
        }
        if flow == .stageSelect { tickStageSelect(inputs) }
        if flow != .playing {
            // A screen is up: the stick moves its cursor and jump picks; the sim waits. On
            // the title, which the SwiftUI layer draws, the stick moves the title's cursor.
            let pad = inputs.first ?? .idle
            // Circle or square (B or X) is back.
            let backDown = pad.shootButtons & 1 != 0 || pad.throwBall
            let backWasDown = menuLast.shootButtons & 1 != 0 || menuLast.throwBall
            if menuNeedsRelease, !pad.jump, !backDown { menuNeedsRelease = false }
            let picked = pad.jump && !menuLast.jump && !menuNeedsRelease
            let backed = backDown && !backWasDown && !menuNeedsRelease
            let right = pad.stick.x >= 0.5 && menuLast.stick.x < 0.5, left = pad.stick.x <= -0.5 && menuLast.stick.x > -0.5
            let down = pad.stick.y <= -0.5 && menuLast.stick.y > -0.5, up = pad.stick.y >= 0.5 && menuLast.stick.y < 0.5
            if let screen {
                if right || down { screen.move(1) }
                if left || up { screen.move(-1) }
                if picked {
                    menuNeedsRelease = true
                    screen.fire()
                } else if backed, screen.back != nil {
                    menuNeedsRelease = true
                    screen.goBack()
                }
            } else if flow == .title, online == nil, let flowState, flowState.multiplayerOpen {
                // The multiplayer screen over the title: its own column of choices, B back.
                if down || right { flowState.moveMultiplayerCursor(1) }
                if up || left { flowState.moveMultiplayerCursor(-1) }
                if picked, let item = flowState.multiplayerSelection {
                    menuNeedsRelease = true
                    flowState.activate(item)
                } else if backed {
                    menuNeedsRelease = true
                    flowState.multiplayerBack()
                }
            } else if flow == .title, online == nil, let flowState, !flowState.tuningOpen {
                if right { flowState.moveTitleCursor(across: 1, down: 0) }
                if left { flowState.moveTitleCursor(across: -1, down: 0) }
                if down { flowState.moveTitleCursor(across: 0, down: 1) }
                if up { flowState.moveTitleCursor(across: 0, down: -1) }
                if picked {
                    menuNeedsRelease = true
                    flowState.activate(flowState.titleCursor)
                }
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
        if hub.consumeCycle() { controls?.cyclePicker(titled: "POWER") }
        if online == nil, hub.consumeAIToggle() {
            aiOn.toggle()
            controls?.aiOn = aiOn
        }
        if hub.consumeHitboxToggle() {
            showHitboxes.toggle()
            controls?.showHitboxes = showHitboxes
        }
        var steps = 0
        sectionMark = CACurrentMediaTime()
        while accumulator >= GameScene.stepSeconds, steps < GameScene.maxStepsPerFrame {
            let tick: SessionTick
            if online != nil {
                tick = session.tick(local: inputs[0])
                send(.inputs(session.outgoing()), reliable: false)
            } else {
                var remote = inputs.count > 1 ? inputs[1] : .idle
                if aiOn { remote = opponent.decide(match) }
                section("ai")
                tick = session.tick(local: inputs[0], remote: remote)
            }
            section("sim")
            show(tick.shown)
            confirm(tick.confirmed)
            section("events")
            tickBallColour()
            tickCourtColour()
            section("colours")
            accumulator -= GameScene.stepSeconds
            steps += 1
        }
        if accumulator >= GameScene.stepSeconds {
            accumulator = 0
        }
        render()
    }

    /// Where the hoop's art sits for a rim, backboard and rim together: the rim's point, moved
    /// by `HoopTuning.offset` in art pixels, across mirrored for a backboard on the left.
    static func hoopArtPoint(for hoop: Hoop) -> CGPoint {
        let at = SpriteLibrary.point(hoop.position)
        let across = HoopTuning.offset.x * (hoop.backboard == .left ? -1 : 1)
        return CGPoint(x: at.x + across, y: at.y + HoopTuning.offset.y)
    }

    /// Where the net hangs from: the rim's point, moved by NET X and NET Y.
    static func netPoint(for hoop: Hoop) -> CGPoint {
        let at = SpriteLibrary.point(hoop.position)
        let across = NetTuning.offset.x * (hoop.backboard == .left ? -1 : 1)
        return CGPoint(x: at.x + across, y: at.y + NetTuning.offset.y)
    }

    /// The court's rims to where the RIM sliders have them, in the match as it stands.
    private func moveCourtRims() {
        session.mutate { match in
            guard match.stage.features.look == Stage.court.features.look, match.stage.columns == Stage.court.columns else { return }
            match.stage.hoops = Stage.court.hoops
        }
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
    private func startSeries(mode: GameMode? = nil) {
        guard online == nil else { return }
        if let mode { gameMode = mode }
        applySavedColours()
        startSeries(seed: UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970)))
    }

    /// The series, held still on the court until the first stage is chosen.
    private func startSeries(seed: UInt32) {
        pendingFlow = nil
        heldBanner = nil
        series = Series(seed: seed)
        // The debug strip is built for the mode (47 has its sliders), so again for this one.
        if built { layout(displayScale: displayScale) }
        if gameMode == .fortySeven {
            // 47 is the court's alone for now, straight into play.
            series.stage = .wreckCenter
            firstStage = .wreckCenter
            startRound()
            enter(.playing)
            return
        }
        // The port-in waits for the stage select to close.
        startRound(portingIn: false)
        session.stopAt = session.frame
        pickAfterStage = false
        enter(.stageSelect)
    }

    /// The pause's RESTART MATCH: a fresh best of seven on the stage this one started on.
    private func restartMatch() {
        pendingFlow = nil
        heldBanner = nil
        series = Series(seed: UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970)))
        series.stage = firstStage
        startRound()
        enter(.playing)
    }

    /// A round: bodies with their drinks in them at their spawns, the count, and the
    /// port-in, unless a screen is to come first.
    private func startRound(portingIn: Bool = true) {
        fortySevenScores = [0, 0]
        session = RollbackSession(match: freshMatch(), localIndex: localIndex, delay: online == nil ? 0 : NetRules.inputDelay)
        showStage()
        controls?.setOnline(online != nil)
        freshRoundView()
        if portingIn { bringPlayersIn() }
    }

    /// The view's hold on the last round let go: the computer, the rim flashes, the ball's colour.
    private func freshRoundView() {
        // The camera picks up the zone the local player starts in.
        cameraZone = nil
        opponent = Opponent(index: 1)
        rimFlash = rimFlash.map { _ in 0 }
        ballTeam = SKColor(rgb: BallLook.neutral)
        ballHold = 0
        ballShift = 0
        lastCount = match.countdown
        drawSeries()
    }

    /// A match on the series' stage with the drinks in it, and the picker's power offline.
    private func freshMatch() -> Match {
        // The field's dice and coin flip come off the series' dice, the same on both phones.
        let fieldSeed = UInt32(series.dice.roll(1 << 16)) &+ 1
        let pickerOn = online == nil && powerVariant != .none && gameMode != .fortySeven
        let drinks = series.drinks.indices.map { drinksInPlay($0, pickerOn: pickerOn) }
        var fresh = Match(stage: series.stage.stage, specs: drinks.map { $0.spec() }, countdown: GameScene.countdownFrames, seed: fieldSeed,
                          mode: gameMode)
        for index in fresh.players.indices {
            fresh.players[index].power = drinks[index].power
            fresh.players[index].powerLevel = drinks[index].powerLevel
        }
        return fresh
    }

    /// A side's drinks, with the POWER picker's biomorph and level in place of this phone's
    /// player's, so a biomorph that changes the body, Titan Tea, changes it from the picker
    /// too. The other side keeps its own.
    private func drinksInPlay(_ index: Int, pickerOn: Bool) -> Drinks {
        var drinks = series.drinks[index]
        if pickerOn, index == 0, let bottle = Greateraid.biomorphs.first(where: { $0.power == powerVariant.power }) {
            drinks.biomorph = bottle
            drinks.biomorphLevel = powerLevelVariant.level
        }
        return drinks
    }

    // MARK: The stage select

    /// Who votes and who of them is on this phone. Online the first stage is a vote and
    /// after that the loser of the stage picks; offline this phone picks, with a second
    /// pad voting too.
    private var localStageVoters: [Int] {
        online == nil ? stageVoters : stageVoters.filter { $0 == localIndex }
    }

    private func openStageSelect() {
        if online != nil {
            stageVoters = series.stageWinner.map { [1 - $0] } ?? [0, 1]
        } else {
            stageVoters = hub.playerTwoHasController ? [0, 1] : [0]
        }
        stageVotes = [:]
        stageLanding = nil
    }

    /// Every frame on the stage select: the second pad's cursor offline, the other phone's
    /// vote, the settle, and the coin flip.
    private func tickStageSelect(_ inputs: [PlayerInput]) {
        guard let select = screen as? StageSelectScreen else { return }
        if online == nil, stageVoters.contains(1), inputs.count > 1 {
            let pad = inputs[1]
            if pad.stick.x >= 0.5, secondMenuLast.stick.x < 0.5 { select.move(voter: 1, by: 1) }
            if pad.stick.x <= -0.5, secondMenuLast.stick.x > -0.5 { select.move(voter: 1, by: -1) }
            if pad.jump, !secondMenuLast.jump { select.lock(voter: 1) }
            secondMenuLast = pad
        }
        if let landing = stageLanding {
            stageFlipFrames -= 1
            let tail = 30
            let other = stageVoters.compactMap { stageVotes[$0] }.first { $0 != landing } ?? landing
            let step = max(stageFlipFrames - tail, 0) / 6
            select.showFlip(lit: (step % 2 == 0 ? landing : other).rawValue)
            if stageFlipFrames <= 0 { settleStage(landing) }
            return
        }
        let remote = 1 - localIndex
        if let theirs = online?.theirStageVote, theirs.stagesPlayed == series.stagesPlayed,
           stageVoters.contains(remote), let choice = StageChoice(rawValue: theirs.choice) {
            online?.theirStageVote = nil
            stageVotes[remote] = choice
            select.show(vote: choice.rawValue, by: remote)
        }
        guard stageVoters.allSatisfy({ stageVotes[$0] != nil }) else { return }
        // Online the stage goes in only once every frame before the stop is confirmed.
        if online != nil, !session.settled { return }
        let votes = stageVoters.compactMap { stageVotes[$0] }
        let landing = series.settle(votes: votes)
        if Set(votes).count > 1 {
            stageLanding = landing
            stageFlipFrames = GameScene.stageFlipLength
        } else {
            settleStage(landing)
        }
    }
    private var secondMenuLast = PlayerInput.idle

    private func voteStage(_ choice: StageChoice, by voter: Int) {
        guard flow == .stageSelect, stageVoters.contains(voter), stageVotes[voter] == nil else { return }
        stageVotes[voter] = choice
        if online != nil { send(.stage(stagesPlayed: series.stagesPlayed, choice: choice.rawValue), reliable: true) }
    }

    /// The chosen stage in: a fresh match on it in place of the stopped one, keeping the
    /// frame so the session runs on; then the drink pick if one is due, or play.
    private func settleStage(_ choice: StageChoice) {
        stageLanding = nil
        if series.rounds.isEmpty {
            series.stage = choice
            firstStage = choice
        } else {
            series.move(to: choice)
        }
        let fresh = freshMatch()
        session.mutate { match in
            let frame = match.frame
            match = fresh
            match.frame = frame
        }
        showStage()
        freshRoundView()
        if pickAfterStage {
            enter(.picking)
            return
        }
        session.stopAt = nil
        bringPlayersIn()
        if let heldBanner {
            bannerQueue.append((heldBanner, 26))
            self.heldBanner = nil
        }
        enter(.playing)
    }

    /// The drinks onto the bodies as they stand, for the round about to count. The POWER
    /// picker's choice, offline, stands over the drinks.
    private func applyDrinks() {
        let pickerOn = online == nil && powerVariant != .none
        let drinks = series.drinks.indices.map { drinksInPlay($0, pickerOn: pickerOn) }
        session.mutate { match in
            for index in match.players.indices {
                match.players[index].spec = drinks[index].spec()
                match.players[index].power = drinks[index].power
                match.players[index].powerLevel = drinks[index].powerLevel
            }
        }
    }

    /// Both bodies ported in at their spawns in a flash cluster in their colours, hidden
    /// until it's up.
    private func bringPlayersIn() {
        roundIntro = 12
        // Once for both, as loud as the nearer of the two is.
        let nearest = match.players.map { audibility(at: $0.position) }.max() ?? 1
        SoundBoard.shared.play(.portIn, volume: nearest)
        lastCountSounded = 0
        for player in match.players {
            if player.power == .titanTea {
                // Titan Tea comes in on the bolt at the ordinary size, then grows.
                boltEntry(player)
                titanGrowDelay[player.index] = roundIntro
                titanGrowth[player.index] = 0
            } else if player.power == .blazingBoba, EffectSheets.frames[GameScene.explosionEntrySheet] != nil {
                explosionEntry(player)
            } else {
                portIn(player)
            }
        }
    }

    /// The port-in: a cluster of `flashspark2` over the body in its energy, the backboards'
    /// grid unskewed, held while the body is hidden and then faded out.
    private func portIn(_ player: Player) {
        let frameCount = EffectSheets.frames[EnergyEffect.flashSpark2.name] ?? 1
        let frames = sprites.effectFrames(EnergyEffect.flashSpark2, player: player.index)
        let step = BackboardTuning.spacing * BackboardTuning.size * 2
        let cluster = flashCluster(frames: frames, frameCount: frameCount, columns: BackboardTuning.columns, rows: BackboardTuning.rows,
                                   step: step, scale: BackboardTuning.size, shear: 0)
        cluster.position = SpriteLibrary.point(player.chest)
        cluster.zPosition = 45
        cluster.run(.sequence([.wait(forDuration: Double(roundIntro) / 60), .fadeOut(withDuration: 0.3), .removeFromParent()]))
        glowers.addChild(cluster)
    }

    /// Blazing Boba's entry: the explosion, painted as it is, standing on the feet.
    private static let explosionEntrySheet = "explosion_v2"
    private func explosionEntry(_ player: Player) {
        let name = GameScene.explosionEntrySheet
        let frames = (0..<(EffectSheets.frames[name] ?? 1)).map { sprites.texture(name, $0) }
        let node = SKSpriteNode(texture: frames[0])
        node.anchorPoint = CGPoint(x: 0.5, y: EffectSheets.anchorY[name] ?? 0)
        node.position = SpriteLibrary.point(player.position)
        node.zPosition = 45
        node.run(.sequence([.animate(with: frames, timePerFrame: 1.0 / 24), .removeFromParent()]))
        glowers.addChild(node)
    }

    /// The old entry, a bolt from the top of the screen and the crown: Titan Tea's.
    private func boltEntry(_ player: Player) {
        let top = cameraNode.position.y + size.height * cameraNode.yScale / 2
        let point = SpriteLibrary.point(player.position)
        let bolt = EnergyEffect.strikes.randomElement()!.node(sprites, player: player.index, at: point)
        bolt.zPosition = 45
        bolt.yScale = max((top - point.y) * 1.1, 64) / bolt.size.height
        glowers.addChild(bolt)
        let crown = EnergyEffect.spark3.node(sprites, player: player.index, at: point)
        crown.zPosition = 46
        glowers.addChild(crown)
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
            session.mutate { $0.finished = true }
            pendingFlow = .won
            pendingFlowFrame = frame + GameScene.flowDelayFrames
        } else if online == nil, scorer == 0 {
            let offers = series.offers(for: 1)
            let drink = offers[series.dice.roll(offers.count)]
            series.drink(drink, by: 1)
            drawSeries()
            let banner = "\(sideName(1)) DRINKS \(drink.name.uppercased())"
            if series.stageSelectDue {
                // The stage is done: the select, and what the computer drank once play is back.
                heldBanner = banner
                pickAfterStage = false
                pendingFlow = .stageSelect
                pendingFlowFrame = frame + GameScene.flowDelayFrames
                session.stopAt = pendingFlowFrame
            } else {
                applyDrinks()
                bringPlayersIn()
                bannerQueue.append((banner, 26))
            }
        } else {
            picker = 1 - scorer
            pickAfterStage = true
            pendingFlow = series.stageSelectDue ? .stageSelect : .picking
            pendingFlowFrame = frame + GameScene.flowDelayFrames
        }
        if online != nil, pendingFlow != nil { session.stopAt = pendingFlowFrame }
    }

    /// 47's basket, confirmed on both sides: the tally, and the win at 47, the sim stopped on
    /// the same frame online for the screen. Nothing else stops play.
    private func fortySevenScored(by scorer: Int, points: Int, at frame: Int) {
        guard flow == .playing, scorer < fortySevenScores.count else { return }
        fortySevenScores[scorer] += points
        drawSeries()
        if fortySevenScores[scorer] >= FortySevenRules.target {
            session.mutate { $0.finished = true }
            pendingFlow = .won
            pendingFlowFrame = frame + GameScene.flowDelayFrames
            if online != nil { session.stopAt = pendingFlowFrame }
        }
    }
    /// 47's score as confirmed, which the screen shows.
    private var fortySevenScores = [0, 0]

    private func enter(_ next: Flow) {
        // The ball cam's edge is in the HUD, so it goes with the screens that aren't play.
        ballCamFrame.isHidden = next != .playing
        // The winner's line once, as the win screen goes up, not each time it's redrawn.
        if next == .won, flow != .won { SoundBoard.shared.play(SoundBoard.winners.randomElement()!) }
        flow = next
        if next == .stageSelect { openStageSelect() }
        if next == .picking {
            // Both phones roll the same offers off the shared dice.
            pickOffers = series.offers(for: picker)
            pickFramesLeft = Series.pickSeconds * 60
        }
        flowState?.showsTitle = next == .title
        presentScreen()
    }

    private func sideName(_ index: Int) -> String {
        sideColours.indices.contains(index) ? sideColours[index].rawValue.uppercased() : "TEAL"
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

    // MARK: UI tuning

    /// The screen the UI tuning panel shows behind itself, if not the title: built as it
    /// would be, its buttons doing nothing.
    private var previewing: UIScreenKind?

    func preview(_ kind: UIScreenKind?) {
        previewing = kind
        refreshPreview()
    }

    func refreshPreview() {
        guard flow == .title else { return }
        screen?.removeFromParent()
        screen = nil
        let halfWidth = size.width / 2 / hudScale, halfHeight = size.height / 2 / hudScale
        // The HUD and the touch pad are tuned where they are: over the court, as in play.
        let inPlace = previewing == .hud || previewing == .touch
        if inPlace, built { layout(displayScale: displayScale) }
        controls?.isHidden = !(inPlace && GameScene.touchControlsShown)
        switch previewing {
        case .stageSelect:
            screen = StageSelectScreen(halfWidth: halfWidth, halfHeight: halfHeight, stages: StageChoice.allCases.map { $0.name.uppercased() },
                                       voters: [0], localVoters: [0], colours: [0, 1].map { SKColor(rgb: sprites.look(for: $0).glow) },
                                       heading: nil, start: 0) { _, _ in }
        case .pick:
            screen = PickScreen(halfWidth: halfWidth, halfHeight: halfHeight, offers: Array(Greateraid.boosters.prefix(3)), drinks: .none,
                                colour: SKColor(rgb: sprites.look(for: 0).glow), timed: true) { _ in }
        case .pause:
            screen = PauseScreen(halfWidth: halfWidth, halfHeight: halfHeight, onRestart: {}, onTitle: {}, onResume: {})
        case .win:
            screen = WinScreen(halfWidth: halfWidth, halfHeight: halfHeight, winner: sideName(1), score: [1, 4], again: "NEW MATCH",
                               onAgain: {}, onTitle: {})
        default:
            break
        }
        if let screen { hud.addChild(screen) }
        drawSeries()
        flowState?.blackGround = screen is PickScreen
        flowState?.winGround = screen is WinScreen
        flowState?.showsTitle = previewing == nil
        flowState?.veiled = screen != nil
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
        case .stageSelect:
            let colours = [0, 1].map { SKColor(rgb: sprites.look(for: $0).glow) }
            let heading = online != nil && stageVoters.count == 1 ? "\(sideName(stageVoters[0])) PICKS" : nil
            let select = StageSelectScreen(halfWidth: halfWidth, halfHeight: halfHeight, stages: StageChoice.allCases.map { $0.name.uppercased() },
                                           voters: stageVoters, localVoters: localStageVoters, colours: colours, heading: heading,
                                           start: series.stage.rawValue) { [weak self] voter, index in
                self?.voteStage(StageChoice(rawValue: index) ?? .wreckCenter, by: voter)
            }
            for (voter, vote) in stageVotes { select.show(vote: vote.rawValue, by: voter) }
            // Back to the title from the first pick offline, before anything's been played.
            if online == nil, series.stagesPlayed == 0 { select.back = { [weak self] in self?.enter(.title) } }
            screen = select
        case .paused:
            let pause = PauseScreen(halfWidth: halfWidth, halfHeight: halfHeight,
                                    onRestart: { [weak self] in self?.restartMatch() },
                                    onTitle: { [weak self] in self?.enter(.title) },
                                    onResume: { [weak self] in self?.enter(.playing) })
            pause.back = { [weak self] in self?.enter(.playing) }
            screen = pause
        case .won:
            let winner = gameMode == .fortySeven ? (fortySevenScores.firstIndex { $0 >= FortySevenRules.target } ?? 0) : (series.winner ?? 0)
            screen = WinScreen(halfWidth: halfWidth, halfHeight: halfHeight, winner: sideName(winner),
                               score: gameMode == .fortySeven ? fortySevenScores : series.wins,
                               again: online == nil ? "NEW MATCH" : "REMATCH",
                               onAgain: { [weak self] in self?.playAgain() },
                               onTitle: { [weak self] in self?.leaveToTitle() })
            if online?.rematchRandom != nil { (screen as? WinScreen)?.showWaiting() }
        case .playing:
            break
        }
        if let screen { hud.addChild(screen) }
        controls?.isHidden = flow != .playing || !GameScene.touchControlsShown
        flowState?.blackGround = screen is PickScreen || screen is WaitScreen
        flowState?.winGround = screen is WinScreen
        flowState?.veiled = screen != nil
    }

    /// The black plate under the round circles or 47's score, as dark as it is so the glow
    /// passes it by; at the HUD's panels scale.
    private func addHUDPlate(width: CGFloat, height: CGFloat) {
        let panels = UITuning.shared.scale(.hud, .panels)
        let plate = UIPiece.plateBlack.node(size: CGSize(width: width, height: height).scaled(by: panels), corners: panels * 0.5)
        plate.position = CGPoint(x: 0, y: -UIPiece.plateBlack.faceRise * panels * 0.5)
        plate.zPosition = -1
        circles.addChild(plate)
        circlesOverCam.addChild(plate.copy() as! SKSpriteNode)
    }

    /// The rounds across the top: five circles in dark purple, filled in the round
    /// winner's colour as they go, a sixth and seventh added if the series gets there;
    /// and to either side of them each side's drinks, with their levels.
    private func drawSeries() {
        threePointArcs.isHidden = gameMode != .fortySeven && previewing != .hud
        for arc in threePointArcSides { arc.node.lineWidth = ThreePointTuning.lineWidth }
        if gameMode == .fortySeven {
            // 47: each side's points either side of the middle, in its colour, no circles, no drinks.
            for label in drinkLabels { label.text = "" }
            circles.removeAllChildren()
            circlesOverCam.removeAllChildren()
            for (index, score) in fortySevenScores.enumerated() {
                let label = SKLabelNode(text: "\(score)")
                label.fontName = "Menlo-Bold"
                label.fontSize = 18 * UITuning.shared.scale(.hud, .text)
                label.fontColor = SKColor(rgb: sprites.look(for: index).glow)
                label.verticalAlignmentMode = .center
                label.horizontalAlignmentMode = index == 0 ? .right : .left
                label.position = CGPoint(x: index == 0 ? -12 : 12, y: 0)
                circles.addChild(label)
            }
            addHUDPlate(width: 120, height: 34)
            let target = SKLabelNode(text: "\(FortySevenRules.target)")
            target.fontName = "Menlo-Bold"
            target.fontSize = 8
            target.fontColor = SKColor(white: 1, alpha: 0.5)
            target.verticalAlignmentMode = .center
            circles.addChild(target)
            return
        }
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
        circlesOverCam.removeAllChildren()
        let count = series.circles
        let circleScale = UITuning.shared.scale(.hud, .buttons)
        let spacing: CGFloat = 18 * circleScale
        let radius: CGFloat = 6 * circleScale
        let halfRow = CGFloat(count - 1) / 2 * spacing + radius
        addHUDPlate(width: halfRow * 2 + 36, height: 30 * circleScale)
        for label in drinkLabels { label.fontSize = 8 * UITuning.shared.scale(.hud, .text) }
        for (index, label) in drinkLabels.enumerated() {
            label.position = CGPoint(x: (halfRow + 8) * (index == 0 ? -1 : 1), y: circles.position.y + radius)
        }
        for index in 0..<count {
            let circle = SKShapeNode(circleOfRadius: radius)
            circle.position = CGPoint(x: (CGFloat(index) - CGFloat(count - 1) / 2) * spacing, y: 0)
            circle.fillColor = index < series.rounds.count ? SKColor(rgb: sprites.look(for: series.rounds[index]).glow) : SKColor(rgb: BallLook.darkPurple)
            circle.strokeColor = SKColor(rgb: PixelPalette.outline).withAlphaComponent(0.6)
            circle.lineWidth = 1
            circles.addChild(circle)
            circlesOverCam.addChild(circle.copy() as! SKShapeNode)
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

    /// The picker's power onto this phone's player, live, with the body it brings (Titan
    /// Tea's size). Offline only.
    private func applyPower() {
        guard online == nil else { return }
        applyDrinks()
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
                sendHello(online.random)
                self.online?.helloAgainIn = 60
            }
            if let online, let theirs = online.theirRandom {
                self.online?.started = true
                // The host, player one, keeps their colour; the other gives way if they match.
                let mine = EnergyColour.saved, other = online.theirColour ?? .teal
                applyColours(online.localIndex == 0 ? EnergyColour.pair(first: mine, second: other) : EnergyColour.pair(first: other, second: mine))
                // The host's mode is played.
                gameMode = online.localIndex == 0 ? GameScene.savedOnlineMode : (online.theirMode ?? .rounds)
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

    private func sendHello(_ random: UInt32) {
        let colour = UInt8(EnergyColour.allCases.firstIndex(of: EnergyColour.saved) ?? 0)
        send(.hello(random: random, version: NetRules.protocolVersion, colour: colour, mode: GameScene.savedOnlineMode.rawValue), reliable: true)
    }

    // MARK: Colours

    /// The block tiles by the side whose colour they wear, and the side labels, recoloured
    /// when the colours change.
    private var blockTiles: [(node: SKSpriteNode, side: Int)] = []
    private var sideLabels: [SKLabelNode] = []

    /// Offline: this phone's pick for player one, the computer or the second pad in teal,
    /// or the opposite if that's the pick.
    func applySavedColours() {
        applyColours(EnergyColour.pair(first: EnergyColour.saved, second: .teal))
    }

    /// Both sides' colours onto everything drawn in them.
    func applyColours(_ colours: [EnergyColour]) {
        for (index, colour) in colours.enumerated() { sprites.setLook(colour.look, for: index) }
        sideColours = colours
        headStreamsCache = [:]
        for (index, flashes) in zip(stunBodies.indices, zip(stunBodies, stunHeads)) {
            let dark = SKColor(rgb: sprites.look(for: index).energyTone(luminance: 0.15))
            flashes.0.color = dark
            flashes.1.color = dark
        }
        for (index, segments) in capes.enumerated() {
            for segment in segments { segment.color = SKColor(rgb: sprites.look(for: index).glow) }
        }
        for (index, web) in swingWebs.enumerated() { web.strokeColor = SKColor(rgb: sprites.look(for: index).glow) }
        for (index, web) in shotWebs.enumerated() { web.strokeColor = SKColor(rgb: sprites.look(for: index).glow) }
        for tile in blockTiles { tile.node.color = SKColor(rgb: CourtLook.shaded(sprites.look(for: tile.side).glow)) }
        for arc in threePointArcSides { arc.node.strokeColor = SKColor(rgb: sprites.look(for: arc.side).glow) }
        for (index, label) in sideLabels.enumerated() { label.fontColor = SKColor(rgb: sprites.look(for: index).glow) }
        for (net, hoop) in zip(nets, match.stage.hoops) { net.recolour(SKColor(rgb: sprites.look(for: 1 - hoop.owner).glow)) }
        warmDrawnArt()
        drawSeries()
    }

    private func send(_ message: NetMessage, reliable: Bool) {
        flowState?.net.send(message.data, reliable: reliable)
    }

    private func handle(_ data: Data) {
        guard online != nil, let message = NetMessage(data: data) else { return }
        switch message {
        case .hello(let random, let version, let colour, let mode):
            guard version == NetRules.protocolVersion else {
                endOnline("VERSIONS DIFFER")
                return
            }
            if online?.theirRandom == nil {
                online?.theirRandom = random
                online?.theirColour = EnergyColour.allCases.indices.contains(Int(colour)) ? EnergyColour.allCases[Int(colour)] : .teal
                online?.theirMode = GameMode(rawValue: mode) ?? .rounds
                if let mine = online?.random { sendHello(mine) }
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
        case .stage(let stagesPlayed, let choice):
            online?.theirStageVote = (stagesPlayed, choice)
        }
    }

    /// The networked series is over, with why if the other side ended it; back to the title.
    private func endOnline(_ why: String?) {
        guard online != nil else { return }
        online = nil
        applySavedColours()
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

    // MARK: Sound

    /// The sounds for a frame's events, shown once like the effects.
    private func playSounds(_ events: [MatchEvent]) {
        func body(_ index: Int) -> Vec2 { match.players.indices.contains(index) ? match.players[index].position : match.ball.position }
        for event in events {
            switch event {
            case .jumped(let index), .doubleJumped(let index), .wallJumped(let index, _): play(.jump, at: body(index))
            case .shot(let index), .thrown(let index), .fireballThrown(let index), .boltFired(let index): play(.shootV2, at: body(index))
            case .slashed(let index): play(.esperSlash, at: body(index))
            case .slashClanked(let index): play(.slashWallClank, at: body(index))
            case .snatchReached(let index): play(.snatch, at: body(index))
            case .caught(let index): play(.catchBall, at: body(index))
            case .struck(let victim, _), .popped(let victim, _): play(.playerHit, at: body(victim))
            case .parried(let victim, _): play(.parry, at: body(victim))
            case .dunked: dunkScoring = true
            // Quiet for a soft bounce, silent once it's only settling.
            case .ballBounced(let position, let speed) where speed > GameScene.bounceSoundFloor:
                play(.ballBounce, at: position, volume: Float(min(speed / GameScene.bounceSoundFull, 1)))
            default: break
            }
        }
    }

    /// A sound from somewhere in the world: full on the screen, fading out over a margin
    /// past its edge, so nothing off the screen is heard.
    private func play(_ effect: SoundBoard.Effect, at point: Vec2, volume: Float = 1) {
        SoundBoard.shared.play(effect, volume: volume * audibility(at: point))
    }

    private func audibility(at point: Vec2) -> Float {
        let at = SpriteLibrary.point(point)
        let halfWidth = size.width * cameraNode.xScale / 2, halfHeight = size.height * cameraNode.yScale / 2
        let beyond = max(abs(at.x - cameraNode.position.x) - halfWidth, abs(at.y - cameraNode.position.y) - halfHeight, 0)
        return Float(max(1 - beyond / GameScene.soundFadeMargin, 0))
    }
    /// A dunk went down, so the point it scores sounds as one.
    private var dunkScoring = false

    /// The announcer's odds: the generic score's weight, a unique line's, and a unique line's
    /// where it fits best (a dunk's on a dunk, the wrist work on a floater, 47's three).
    private static let scoreWeight = 4
    private static let uniqueWeight = 1
    private static let likelyWeight = 2

    /// The announcer on a basket, over the crowd's cheer. The game's last is "that'll do it"
    /// and the finish slows and closes in on the ball. Otherwise a line drawn by weight: the
    /// generic score always in, and the unique lines, fewer, a little more where they fit.
    private func announce(dunk: Bool, three: Bool, floater: Bool, winning: Bool) {
        SoundBoard.shared.play(.crowdCheer)
        if winning {
            SoundBoard.shared.play(SoundBoard.gameWinners.randomElement()!)
            startFinish()
            return
        }
        var pool: [(lines: [SoundBoard.Effect], weight: Int)] = [(SoundBoard.scores, GameScene.scoreWeight)]
        if dunk {
            pool.append((SoundBoard.dunks, GameScene.likelyWeight))
        } else {
            pool.append((SoundBoard.wristWorks, floater ? GameScene.likelyWeight : GameScene.uniqueWeight))
        }
        if three { pool.append(([.itsAThree], GameScene.likelyWeight)) }
        var roll = Int.random(in: 0..<pool.reduce(0) { $0 + $1.weight })
        for entry in pool {
            if roll < entry.weight {
                SoundBoard.shared.play(entry.lines.randomElement()!)
                return
            }
            roll -= entry.weight
        }
    }

    /// The game-winning basket's finish: the game slowed (offline; online both sides must
    /// keep time) and the camera easing in on the ball, until the win screen.
    private var finishFrames = 0
    private static let finishZoomFrames = 40
    private static let finishZoom: CGFloat = 0.55
    private static let finishTimeScale = 0.35
    private var finishTarget: CGPoint?
    private func startFinish() { finishFrames = 1 }
    /// Art pixels past the screen's edge over which a sound fades to nothing.
    private static let soundFadeMargin: CGFloat = 32
    private static let bounceSoundFloor = 0.6
    private static let bounceSoundFull = 4.0

    /// The sounds a body's sheet makes as it reaches a frame, on the ground: a footfall on
    /// the walk and run sheets' frames 0 and 4, and the ball's bounce on each frame of a
    /// sheet with the ball in hand where it's lowest, as the landmarks draw it.
    private var lastSoundFrames: [AnimationFrame?] = [nil, nil]
    private func playFrameSounds(_ index: Int, frame: AnimationFrame, grounded: Bool, at feet: Vec2) {
        guard lastSoundFrames.indices.contains(index), lastSoundFrames[index] != frame else { return }
        lastSoundFrames[index] = frame
        guard grounded else { return }
        let walking: Set<Animation> = [.walk, .dribbleWalk, .run, .dribbleRun, .gunRun, .gunRunShoot]
        if walking.contains(frame.animation), frame.frame % 4 == 0 {
            play(.step, at: feet)
            // Titan Tea's running steps shake the screen a little.
            if match.players.indices.contains(index), match.players[index].power == .titanTea,
               [Animation.run, .dribbleRun].contains(frame.animation) {
                shake = max(shake, GameScene.titanStepShake)
            }
        }
        // The dribble's bounce, under a loose ball's.
        if GameScene.dribbleBounceFrames(of: frame.animation).contains(frame.frame) { play(.ballBounce, at: feet, volume: GameScene.dribbleVolume) }
    }

    /// The frames of a sheet where the ball in hand is at its lowest, under five art pixels
    /// off the floor and no higher than the frames either side: where it meets the floor.
    /// The dribble's bounce at this share of a loose ball's.
    private static let dribbleVolume: Float = 0.5
    private static var bounceFramesCache: [Animation: Set<Int>] = [:]
    private static func dribbleBounceFrames(of animation: Animation) -> Set<Int> {
        if let cached = bounceFramesCache[animation] { return cached }
        let count = animation.frameCount
        let heights = (0..<count).map { BallLandmarks.offset(AnimationFrame(animation, $0))?.y }
        var frames = Set<Int>()
        for index in 0..<count {
            guard let height = heights[index], height < 5 else { continue }
            let neighbours = [heights[(index + count - 1) % count], heights[(index + 1) % count]].compactMap { $0 }
            if neighbours.allSatisfy({ height <= $0 }) { frames.insert(index) }
        }
        bounceFramesCache[animation] = frames
        return frames
    }

    /// The events of frames both sides' inputs have confirmed: the point.
    private func confirm(_ frames: [FrameEvents]) {
        for frameEvents in frames {
            for case .scored(let scorer, let hoop, let entry, let points, let floater) in frameEvents.events {
                rimFlash[hoop] = 8
                let dunk = dunkScoring
                strike(hoop: hoop, by: scorer, entry: entry)
                if gameMode == .fortySeven {
                    showBanner(points >= 3 ? "THREE!!" : "BUCKET!!", size: 48)
                    fortySevenScored(by: scorer, points: points, at: frameEvents.frame)
                } else {
                    showBanner("BUCKET!!", size: 48)
                    pointScored(by: scorer, at: frameEvents.frame)
                }
                announce(dunk: dunk, three: gameMode == .fortySeven && points >= 3, floater: floater, winning: pendingFlow == .won)
            }
        }
    }

    private func show(_ events: [MatchEvent]) {
        playSounds(events)
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
                case .zeusJuice:
                    // Bottom-aligned, twelve art pixels under the feet.
                    glowers.addChild(EnergyEffect.lightningJump.node(sprites, player: index, at: SpriteLibrary.point(player.position + Vec2(x: 0, y: -7.5)), scale: 0.42))
                case .surfSoda:
                    // A cloud of bubbles off the board, in place of the spark.
                    spawnBubbles(at: SpriteLibrary.point(player.position), count: 8, spread: 10)
                case .frostTea where EffectSheets.frames["ice_jumpspark"] != nil:
                    // The ice jump spark in the snowflake's blues, under the feet like the others.
                    let frames = (0..<(EffectSheets.frames["ice_jumpspark"] ?? 1)).map { sprites.iceTexture("ice_jumpspark", $0) }
                    let spark = SKSpriteNode(texture: frames[0])
                    spark.anchorPoint = CGPoint(x: 0.5, y: EffectSheets.anchorY["ice_jumpspark"] ?? 0)
                    spark.position = SpriteLibrary.point(player.position + Vec2(x: 0, y: (EffectSheets.anchorY["ice_jumpspark"] ?? 0) == 0 ? -3.75 : 0))
                    spark.xScale = player.facing == .left ? -GameScene.iceJumpSparkScale : GameScene.iceJumpSparkScale
                    spark.yScale = GameScene.iceJumpSparkScale
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
                spawnHitSpark(player: popper, at: match.players[victim].heldBallPoint)
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
                spawnJumpRings(at: SpriteLibrary.point(player.position), colour: SKColor(rgb: sprites.look(for: index).glow))
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
                let whole = match.players[index].power == .quakeUp && match.players[index].powerLevel >= 2
                shake = whole ? 18 : 14
                spawnRocks(at: SpriteLibrary.point(match.players[index].position), whole: whole)
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
            case .surfLanded(let index):
                spawnBubbles(at: SpriteLibrary.point(match.players[index].position), count: 10, spread: 14)
            case .boardBlocked(_, let at):
                spawnBubbles(at: SpriteLibrary.point(at), count: 6, spread: 8)
            case .carHit(let id):
                carFlash[id] = GameScene.carFlashFrames
            case .carWrecked(_, let at):
                let burst = Effect.fireExplosion.node(sprites, at: SpriteLibrary.point(at), flipped: false)
                burst.setScale(1)
                glowers.addChild(burst)
            case .landed(let index):
                // Landing on a car dips it on its springs.
                let feet = match.players[index].position
                if let car = match.cars.first(where: { car in car.boxes.contains { abs($0.max.y - feet.y) < 0.5 && feet.x >= $0.min.x - 5 && feet.x <= $0.max.x + 5 } }) {
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
            case .sniped:
                // As kinetic as the pulse: the cursor is all there is to see.
                break
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
    /// Frost Tea's jump spark: half its sheet's size, and a quarter more.
    private static let iceJumpSparkScale: CGFloat = 0.625

    /// The double jump: oval rings of energy under the feet, one after another, each
    /// widening as it fades.
    private static let jumpRingCount = 3
    private static let jumpRingSize = CGSize(width: 14, height: 4)
    private static let jumpRingGrowth: CGFloat = 2.5
    private static let jumpRingSeconds = 0.3
    private static let jumpRingStagger = 0.06
    private func spawnJumpRings(at point: CGPoint, colour: SKColor) {
        for ring in 0..<GameScene.jumpRingCount {
            let size = GameScene.jumpRingSize
            let shape = SKShapeNode(ellipseOf: size)
            shape.strokeColor = colour
            shape.lineWidth = 1
            shape.fillColor = .clear
            shape.isAntialiased = false
            shape.position = point
            shape.zPosition = 30
            shape.alpha = 0
            glowers.addChild(shape)
            let grow = SKAction.scale(to: GameScene.jumpRingGrowth, duration: GameScene.jumpRingSeconds)
            grow.timingMode = .easeOut
            let fade = SKAction.fadeOut(withDuration: GameScene.jumpRingSeconds)
            shape.run(.sequence([.wait(forDuration: Double(ring) * GameScene.jumpRingStagger), .fadeAlpha(to: 0.9, duration: 0),
                                 .group([grow, fade]), .removeFromParent()]))
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
            // Blazing Boba's hits spark in fire, painted as it is, and sound as fire.
            play(.fireHit, at: position)
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
        if zeus, let crack = SoundBoard.lightning.randomElement() { play(crack, at: position) }
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
        // A shot goes in with the net's swish; a dunk's sound is the announcer's.
        if !dunkScoring { play(.swish, at: match.stage.hoops[hoop].position) }
        dunkScoring = false
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
        /// Tints to pick from for each particle, in place of the one tint.
        var tints: [SKColor] = []
        /// The regular energy's stream: in the zone its particles take the zone's colours.
        var zoneTinted = false
        /// Its particles are cubes, drawn by the Metal layer.
        var cubes = false
        /// Off a leg: the leg cubes' size and spread.
        var legs = false
        /// Drawn behind the players: the back leg's.
        var behind = false
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
        /// Rises and sways in the wind, as off a head; a ball's trail doesn't.
        var drifts = true
        /// A cube's turn, its spin, and its colour; its node, hidden, carries the rest.
        var cube: (orientation: simd_quatf, spin: SIMD3<Float>, colour: SIMD4<Float>)?
        var legCube = false
        var behind = false
    }

    private var headParticles: [HeadParticle] = []

    /// The cube particles as the Metal layer draws them: where each is, turned, at its
    /// dissolve's size, in its colour and fade.
    var cubeInstances: [CubeInstance] {
        headParticles.compactMap { particle in
            guard let cube = particle.cube else { return nil }
            let node = particle.node
            let size = (particle.legCube ? ParticleLook.legCubeSize : ParticleLook.cubeSize) * Float(node.xScale)
            let model = simd_float4x4.translation(SIMD3<Float>(Float(node.position.x), Float(node.position.y), 0))
                * simd_float4x4(cube.orientation) * simd_float4x4.scale(SIMD3<Float>(repeating: size))
            var colour = cube.colour
            colour.w = Float(node.alpha)
            return CubeInstance(model: model, color: colour, flags: SIMD4<Float>(particle.behind ? 1 : 0, 0, 0, 0))
        }
    }
    /// A leg's cubes, in the leg's own colour, the back leg's behind the players; each leg's
    /// credit apart from the head's.
    private static let legCreditKey = 1000
    private func legStream(_ index: Int, part: BodyPart) -> HeadStream {
        let look = sprites.look(for: index)
        return HeadStream(frames: [sprites.flatSquare(size: 4, alpha: 1)], size: ParticleLook.energySize,
                          tint: SKColor(rgb: look.colours[part] ?? look.glow), rate: Double(ParticleLook.legCubeRate),
                          zoneTinted: true, cubes: true, legs: true, behind: part == .backLeg)
    }

    /// The ball's fire trail: its credit apart from the heads', at twice a head's rate.
    private static let ballFireCreditKey = -1
    private static let ballFireRate = 2.0
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
                                size: ParticleLook.energySize, tint: colour, rate: 24, zoneTinted: true, cubes: ParticleLook.cubes)
        var streams = [energy]
        // A power's own particles come half and half with the energy's, as Frost Tea's snowflakes do.
        var halfEnergy = energy
        halfEnergy.rate = 12
        switch power {
        case .blazingBoba where EffectSheets.frames["fire_particle"] != nil:
            streams = [halfEnergy, HeadStream(frames: sheetFrames("fire_particle"), size: ParticleLook.fireSize, tint: nil, rate: 12)]
        case .frostTea:
            // Snowflakes among the energy.
            streams = [halfEnergy, HeadStream(frames: [sprites.snowflake], size: ParticleLook.snowflakeSize, tint: GameScene.ice, rate: 12)]
        case .surfSoda where EffectSheets.frames["bubble_particle"] != nil:
            streams = [halfEnergy, HeadStream(frames: sheetFrames("bubble_particle"), size: ParticleLook.bubbleSize, tint: nil, rate: 12, tints: ParticleLook.sodas)]
        case .zeusJuice where EffectSheets.frames["lightning_particle"] != nil:
            // The two bolts, a quarter each, toned in the energy colour.
            streams = [halfEnergy, HeadStream(frames: sheetFrames("lightning_particle", toned: index), size: ParticleLook.lightningSize, tint: nil, rate: 6)]
            if EffectSheets.frames["lightning_particle2"] != nil {
                streams.append(HeadStream(frames: sheetFrames("lightning_particle2", toned: index), size: ParticleLook.lightningSize, tint: nil, rate: 6))
            } else {
                streams[1].rate = 12
            }
        default:
            break
        }
        headStreamsCache[index] = (power, streams)
        return streams
    }

    /// New particles off a head at `point` this frame, by its streams' rates; the ball's
    /// fire trail uses the same, under its own credit and at its own rate, `trailing` the
    /// way the particles go, back along the ball's path and turned to it.
    private func emitHeadParticles(_ index: Int, power: Power, at point: CGPoint, creditKey: Int? = nil, rateScale: Double = 1,
                                   trailing: CGVector? = nil, streams given: [HeadStream]? = nil) {
        let streams = given ?? headStreams(index, power: power)
        let creditKey = creditKey ?? index
        var credit = headCredit[creditKey] ?? []
        while credit.count < streams.count { credit.append(0) }
        for (slot, stream) in streams.enumerated() {
            // Cubes come at the slider's rate, a power's half-stream at half of it.
            let rate = stream.cubes ? stream.rate / 24 * Double(ParticleLook.cubeRate) : stream.rate
            credit[slot] += rate * rateScale / 60
            while credit[slot] >= 1 {
                credit[slot] -= 1
                let node = SKSpriteNode(texture: stream.frames[0])
                node.size = CGSize(width: stream.size, height: stream.size)
                // In the zone a head's particles come out in the zone's colours.
                let zoneTint = ZoneTuning.inTheZone && stream.zoneTinted && trailing == nil ? ZoneTuning.colours.randomElement().map { SKColor(rgb: $0) } : nil
                if let tint = zoneTint ?? stream.tints.randomElement() ?? stream.tint {
                    node.color = tint
                    node.colorBlendFactor = 1
                }
                // Drawn over, not added: added on top of the head they saturate to white.
                node.blendMode = .alpha
                node.zPosition = 1
                // Cubes let go across the spread, so they don't rise in one tail.
                let spread = stream.legs ? CGFloat(ParticleLook.legCubeSpread) : (stream.cubes ? CGFloat(ParticleLook.cubeSpread) : 1)
                node.position = CGPoint(x: point.x + CGFloat.random(in: -spread...spread), y: point.y + CGFloat.random(in: -spread / 2...spread / 2))
                if stream.frames.count == 1 { node.zRotation = CGFloat.random(in: 0...(2 * .pi)) }
                glowers.addChild(node)
                var cube: (orientation: simd_quatf, spin: SIMD3<Float>, colour: SIMD4<Float>)?
                if stream.cubes {
                    // Drawn by the Metal layer as a cube; the node only carries where it is.
                    node.isHidden = true
                    var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
                    (zoneTint ?? stream.tints.randomElement() ?? stream.tint ?? .white).getRed(&r, green: &g, blue: &b, alpha: &a)
                    let axis = simd_normalize(SIMD3<Float>.random(in: -1...1) + SIMD3<Float>(0, 0, 0.001))
                    cube = (simd_quatf(angle: Float.random(in: 0..<(2 * .pi)), axis: axis),
                            SIMD3<Float>.random(in: -ParticleLook.cubeSpin...ParticleLook.cubeSpin),
                            SIMD4<Float>(Float(r), Float(g), Float(b), 1))
                }
                let heading = trailing.map { atan2(Double($0.dy), Double($0.dx)) } ?? Double.pi / 2
                let angle = heading + Double.random(in: -Double.pi / 28...Double.pi / 28)
                let speed = 24 + Double.random(in: -2...2)
                // The sheet's flame points up; turned so it points the way it goes.
                if trailing != nil { node.zRotation = CGFloat(heading - Double.pi / 2) }
                // A sheet plays through once over the life; a single frame, or a cube, lives 0.6 s
                // and steps down in size.
                let frames = cube != nil ? [stream.frames[0]] : stream.frames
                let life = frames.count > 1 ? Double(frames.count) / 24 : 0.6 + Double.random(in: -0.05...0.05)
                headParticles.append(HeadParticle(node: node, owner: index, velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                                                  age: 0, life: life, frames: frames,
                                                  startFrame: Int.random(in: 0..<frames.count), drifts: trailing == nil, cube: cube, legCube: stream.legs, behind: stream.behind))
            }
        }
        headCredit[creditKey] = credit
    }

    /// Every head particle a frame on: the sheet's frame for its age, the rise, the wind, a
    /// cube's turn.
    private func stepHeadParticles() {
        let step = 1.0 / 60
        headParticles = headParticles.compactMap { particle in
            var particle = particle
            particle.age += step
            if var cube = particle.cube {
                let rate = simd_length(cube.spin)
                if rate > 0 { cube.orientation = simd_normalize(simd_quatf(angle: rate * Float(step), axis: cube.spin / rate) * cube.orientation) }
                particle.cube = cube
            }
            guard particle.age < particle.life else {
                particle.node.removeFromParent()
                return nil
            }
            if particle.drifts {
                let wind = sin(Double(match.frame) / 60 * 2 * .pi * 1.1 + Double(particle.owner) * 2) * 140
                particle.velocity.dx += wind * step
                particle.velocity.dy += 10 * step
            }
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
    /// The field's camera, zonal as Mega Man's and Nidhogg's: the field in zones a court
    /// wide, the camera on one zone's centre, held inside the field's ends. Within the
    /// buffer of the screen's edge the local player sends it on to the next zone, if its
    /// centre is the nearer of the two, so it never flips back and forth at the line.
    private var cameraZone: Int?
    private func cameraTargetX() -> CGFloat {
        guard match.players.indices.contains(localIndex) else { return cameraBase.x }
        let feet = SpriteLibrary.point(match.players[localIndex].position).x
        let halfView = size.width * cameraNode.xScale / 2
        let width = CGFloat(match.stage.columns) * GameScene.pixelsPerTile
        let zoneWidth = CGFloat(Stage.court.columns) * GameScene.pixelsPerTile
        let zones = max(Int((width / zoneWidth).rounded()), 1)
        func centre(_ zone: Int) -> CGFloat { min(max((CGFloat(zone) + 0.5) * zoneWidth, halfView), max(width - halfView, halfView)) }
        guard let zone = cameraZone else {
            let start = min(max(Int(feet / zoneWidth), 0), zones - 1)
            cameraZone = start
            return centre(start)
        }
        let buffer = halfView * 2 * CameraTuning.zoneBufferShare
        var next = zone
        if feet > centre(zone) + halfView - buffer, zone < zones - 1 { next = zone + 1 }
        if feet < centre(zone) - halfView + buffer, zone > 0 { next = zone - 1 }
        if next != zone, abs(feet - centre(next)) < abs(feet - centre(zone)) { cameraZone = next }
        return centre(cameraZone ?? zone)
    }
    /// The slide to a new zone's centre: from where the camera was, eased out over
    /// `CameraTuning.slideSeconds`, a new target starting a new slide from where it is.
    private var slide: (from: CGFloat, to: CGFloat, elapsed: Double)?
    private func slideCamera(to target: CGFloat) {
        if slide?.to != target {
            guard cameraBase.x != target else { slide = nil; return }
            slide = (cameraBase.x, target, 0)
        }
        guard var current = slide else { return }
        current.elapsed += GameScene.stepSeconds
        let share = min(current.elapsed / max(CameraTuning.slideSeconds, 0.01), 1)
        let eased = 1 - pow(1 - share, 3)
        cameraBase.x = current.from + (current.to - current.from) * CGFloat(eased)
        slide = share < 1 ? current : nil
        if share >= 1 { cameraBase.x = current.to }
    }

    private var helmetNodes: [Int: SKSpriteNode] = [:]

    // MARK: Surf Soda

    private var boards: [Int: SKSpriteNode] = [:]
    private var surfTrailFrames: [Int: Int] = [:]
    private var boardWasOut: [Int: Bool] = [:]

    /// The board as a silhouette in a bright purple, bright enough for the glow to take,
    /// its tail's shadow a shade darker.
    private var boardTextureMade: SKTexture?
    private func boardTexture(for index: Int) -> SKTexture? {
        if let boardTextureMade { return boardTextureMade }
        boardTextureMade = drawBoardTexture()
        return boardTextureMade
    }

    private func drawBoardTexture() -> SKTexture? {
        guard let image = UIImage(named: "Surfboard") else { return nil }
        let width = 400, height = 46
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let cg = drawn.cgImage, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return SKTexture(image: drawn) }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let white = ParticleLook.boardPurple, shadow = ParticleLook.boardShadow
        for pixel in 0..<(width * height) {
            let at = pixel * 4
            let alpha = Int(pixels[at + 3])
            guard alpha > 0 else { continue }
            // The tail's shadow is the drawing's darker blue, #147A99; the rest is its #0C91C4.
            let red = Int(pixels[at]) * 255 / alpha, green = Int(pixels[at + 1]) * 255 / alpha
            let tone = abs(red - 0x14) + abs(green - 0x7A) < abs(red - 0x0C) + abs(green - 0x91) ? shadow : white
            pixels[at] = UInt8(Int((tone >> 16) & 0xFF) * alpha / 255)
            pixels[at + 1] = UInt8(Int((tone >> 8) & 0xFF) * alpha / 255)
            pixels[at + 2] = UInt8(Int(tone & 0xFF) * alpha / 255)
        }
        guard let toned = context.makeImage() else { return SKTexture(image: drawn) }
        return SKTexture(cgImage: toned)
    }

    /// A line of bubbles along where the board lies, as it comes and goes.
    private func bubbleLine(along centre: CGPoint, angle: CGFloat, length: CGFloat) {
        for step in 0..<6 {
            let along = (CGFloat(step) / 5 - 0.5) * length
            spawnBubbles(at: centre + CGPoint(x: cos(angle) * along, y: sin(angle) * along), count: 1, spread: 3)
        }
    }

    /// The board left behind on a dunk: it falls flat to the floor under it and goes there
    /// in a line of bubbles.
    private func dropBoard(_ board: SKSpriteNode, player: Player) {
        guard let texture = board.texture else { return }
        let falling = SKSpriteNode(texture: texture)
        falling.size = CGSize(width: board.size.width / abs(board.xScale == 0 ? 1 : board.xScale), height: board.size.height)
        falling.position = board.position
        falling.zRotation = board.zRotation
        falling.xScale = board.xScale
        falling.zPosition = board.zPosition
        bodies.addChild(falling)
        let feet = board.position.y
        let floor = feet - CGFloat(match.stage.drop(fromX: player.position.x, y: Double(feet) / SpriteLibrary.pixelsPerUnit) * SpriteLibrary.pixelsPerUnit)
        let fall = SKAction.group([.moveTo(y: floor + 2, duration: 0.35), .rotate(toAngle: 0, duration: 0.35)])
        fall.timingMode = .easeIn
        falling.run(.sequence([fall, .run { [weak self, weak falling] in
            guard let self, let falling else { return }
            self.bubbleLine(along: falling.position, angle: 0, length: falling.size.width)
        }, .removeFromParent()]))
    }

    /// The board under a Surf Soda body and the ride on it: riding the ground, the body and
    /// board float a little and bob two pixels, leaving a trail of bubbles; up on a surf
    /// jump, body, head and board turn together about the body's middle.
    private func placeSurf(_ index: Int, player: Player, body: SKSpriteNode, head: SKSpriteNode) {
        let board = boards[index] ?? {
            let node = SKSpriteNode(texture: boardTexture(for: index))
            let length = CGFloat(SurfRules.boardLength * SpriteLibrary.pixelsPerUnit)
            node.size = CGSize(width: length, height: length * 92 / 800)
            node.zPosition = -0.5
            bodies.addChild(node)
            boards[index] = node
            return node
        }()
        let out = player.boardOut
        if out != (boardWasOut[index] ?? false) {
            boardWasOut[index] = out
            if !out, player.state == .dunking {
                // Onto the rim: the board drops away to the floor and pops there.
                dropBoard(board, player: player)
            } else if !board.isHidden || out {
                // In or out in a line of bubbles along it.
                bubbleLine(along: out ? SpriteLibrary.point(player.board.centre) : board.position, angle: out ? CGFloat(player.surfAngle) : board.zRotation, length: board.size.width)
            }
        }
        guard out else { board.isHidden = true; return }
        board.isHidden = false
        let riding = player.riding
        // Floating, and bobbing on the ground.
        let bob: CGFloat = riding ? 3 + round(sin(Double(match.frame) / 60 * 2 * .pi * 1.5)) : 0
        // Riding, the body turns about the board's tail on the floor, a wheelie; in the air,
        // about its own middle.
        let pivot = (riding ? SpriteLibrary.point(player.boardTail)
                            : SpriteLibrary.point(Vec2(x: player.position.x, y: player.position.y + player.spec.bodyHeight / 2)))
            + CGPoint(x: 0, y: bob)
        let angle = CGFloat(player.surfAngle)
        func turned(_ point: CGPoint) -> CGPoint {
            let offset = point - pivot
            return pivot + CGPoint(x: offset.x * cos(angle) - offset.y * sin(angle), y: offset.x * sin(angle) + offset.y * cos(angle))
        }
        body.position = turned(body.position + CGPoint(x: 0, y: bob))
        body.zRotation += angle
        if !head.isHidden {
            head.position = turned(head.position + CGPoint(x: 0, y: bob))
            head.zRotation += angle
        }
        // Whatever rides the body turns with it: the ball in hand, its glow, the energy, the charge.
        for rider in [handBalls[index], handHalos[index], energyNodes[index], chargeNodes[index]] where !rider.isHidden {
            rider.position = turned(rider.position + CGPoint(x: 0, y: bob))
            rider.zRotation += angle
        }
        board.position = SpriteLibrary.point(player.board.centre) + CGPoint(x: 0, y: bob)
        board.zRotation = angle
        board.xScale = CGFloat(player.facing.sign)
        // Coming down past the crescent's top, bubbles off the underside of the board.
        if !riding, player.surfPath == 0, player.velocity.y < 0, match.frame % 4 == index {
            // Anywhere along the board's length, as it lies.
            for _ in 0..<2 {
                let along = CGFloat.random(in: -0.5...0.5) * board.size.width
                let at = board.position + CGPoint(x: cos(angle) * along, y: sin(angle) * along)
                spawnBubbles(at: at, count: 1, spread: 4, downward: true)
            }
        }
        // The trail on the ground.
        if riding {
            let frames = (surfTrailFrames[index] ?? 0) + 1
            surfTrailFrames[index] = frames
            if frames % 6 == 0, EffectSheets.frames["bubbles"] != nil {
                let sheet = (0..<(EffectSheets.frames["bubbles"] ?? 1)).map { sprites.texture("bubbles", $0) }
                let trail = SKSpriteNode(texture: sheet[0])
                trail.anchorPoint = CGPoint(x: 0.5, y: EffectSheets.anchorY["bubbles"] ?? 0)
                trail.position = SpriteLibrary.point(player.position) + CGPoint(x: -CGFloat(player.facing.sign) * 8, y: 0)
                trail.setScale(0.25)
                // Some the other way round, so the trail isn't one drawing over and over.
                if Bool.random() { trail.xScale = -trail.xScale }
                trail.color = ParticleLook.sodas.randomElement()!
                trail.colorBlendFactor = 1
                trail.zPosition = 4
                // Each from its own early frame, played out to the end, so the trail never pulses
                // in step and never shows the sheet's empty last frames mid-trail.
                let start = Int.random(in: 0..<max(sheet.count / 4, 1))
                trail.texture = sheet[start]
                trail.run(.sequence([.animate(with: Array(sheet[start...]), timePerFrame: 1.0 / 24), .removeFromParent()]))
                glowers.addChild(trail)
            }
        }
    }

    /// A burst of soda bubbles from a point, each playing the bubble sheet as it drifts off.
    private func spawnBubbles(at point: CGPoint, count: Int, spread: CGFloat, downward: Bool = false) {
        guard EffectSheets.frames["bubble_particle"] != nil else { return }
        let sheet = (0..<(EffectSheets.frames["bubble_particle"] ?? 1)).map { sprites.texture("bubble_particle", $0) }
        for step in 0..<count {
            let start = Int.random(in: 0..<max(sheet.count / 3, 1))
            let looped = Array(sheet[start...])
            let bubble = SKSpriteNode(texture: looped[0])
            // Each its own size, and some the other way round.
            let side = ParticleLook.bubbleSize * CGFloat.random(in: 0.8...1.8)
            bubble.size = CGSize(width: side, height: side)
            if Bool.random() { bubble.xScale = -1 }
            bubble.color = ParticleLook.sodas.randomElement()!
            bubble.colorBlendFactor = 1
            bubble.position = point
            bubble.zPosition = 31
            glowers.addChild(bubble)
            // Up and out from a landing, or down and out from under a falling board.
            let angle = (CGFloat(step) + 0.5) / CGFloat(count) * .pi * (downward ? -1 : 1) + (downward ? 0 : .pi * 0.05)
            // Spread wide along the ground more than up.
            let out = SKAction.move(by: CGVector(dx: cos(angle) * spread * 2.2, dy: sin(angle) * spread * 0.5 + (downward ? -2 : 3)), duration: 0.4)
            out.timingMode = .easeOut
            // Each on its own frame, so the burst isn't one pulse.
            bubble.run(.sequence([.group([out, .animate(with: looped, timePerFrame: 1.0 / 30)]), .removeFromParent()]))
        }
    }
    /// The bounds gallery, while it's open.
    private var boundsGallery: BoundsGallery?

    private func openBoundsGallery() {
        guard boundsGallery == nil, online == nil else { return }
        let gallery = BoundsGallery(halfWidth: size.width / 2 / hudScale, halfHeight: size.height / 2 / hudScale,
                                    onChange: { [weak self] in self?.session.mutate { $0.refreshExtras() } },
                                    onClose: { [weak self] in self?.closeBoundsGallery() })
        hud.addChild(gallery)
        boundsGallery = gallery
    }

    private func closeBoundsGallery() {
        boundsGallery?.removeFromParent()
        boundsGallery = nil
    }

    // MARK: Traffic

    /// Each car as its wheels and its body over them, by the sim's id; frames of the black
    /// flash after a hit and of the dip after a landing.
    private var carNodes: [Int: (body: SKSpriteNode, wheels: SKSpriteNode?)] = [:]
    private var carFlash: [Int: Int] = [:]
    private var carDip: [Int: Int] = [:]
    private static let carFlashFrames = 12
    private static let carDipFrames = 14
    private static let farLaneShade: CGFloat = 0.35
    private var helicopterNode: SKNode?
    private var helicopterId = 0

    /// The helicopter's layers: as drawn, then dark tones of the guarding side's energy, so
    /// the glow doesn't wash them out.
    private func helicopterTones(for hoop: Hoop) -> [SKColor?] {
        let look = sprites.look(for: 1 - hoop.owner)
        return [nil, SKColor(rgb: look.energyTone(luminance: 0.42)),
                SKColor(rgb: look.energyTone(luminance: 0.3)), SKColor(rgb: look.energyTone(luminance: 0.2))]
    }
    private static let helicopterParts = ["hull", "propeller", "spin_me"]

    /// The art drawn from vectors made now, before play, and sent to the GPU: the board,
    /// the helmets in both colours, and on the highway every vehicle and the helicopter in
    /// its rims' colours. Each is drawn once and kept, not on its first appearance.
    private func warmDrawnArt() {
        var made: [SKTexture] = []
        if let board = boardTexture(for: 0) { made.append(board) }
        made += snipeCursors.compactMap(\.texture)
        for index in match.players.indices {
            for variant in 0..<FieldRules.helmetVariants {
                if let helmet = helmetTexture(variant: variant, colour: SKColor(rgb: sprites.look(for: index).glow)) { made.append(helmet) }
            }
        }
        if match.stage.features.traffic {
            for vehicle in Vehicle.allCases {
                for part in ["body", "wheels"] {
                    if let texture = HighwayArt.texture("vehicle_\(vehicle.art)_\(part)", art: vehicle.art) { made.append(texture) }
                }
            }
            for hoop in match.stage.hoops {
                for part in GameScene.helicopterParts {
                    for (index, tint) in helicopterTones(for: hoop).enumerated() {
                        let name = "helicopter_\(part)_" + (index == 0 ? "plain" : "red\(index - 1)")
                        if let texture = HighwayArt.texture(name, art: "helicopter", tint: tint) { made.append(texture) }
                    }
                }
            }
        }
        SKTexture.preload(made) {}
    }

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
                // The far lane behind everything that plays, and darker for being further off.
                let far = car.level == 1
                body.zPosition = far ? -7 : 3
                stageGround.addChild(body)
                var wheels: SKSpriteNode?
                if let texture = HighwayArt.texture("vehicle_\(art)_wheels", art: art) {
                    let node = SKSpriteNode(texture: texture)
                    node.size = size
                    node.anchorPoint = CGPoint(x: 0.5, y: 0)
                    // The wheels over the body, so the body's shiver never covers them.
                    node.zPosition = far ? -6.9 : 3.1
                    if far {
                        node.color = .black
                        node.colorBlendFactor = GameScene.farLaneShade
                    }
                    stageGround.addChild(node)
                    wheels = node
                }
                // The drawings face right; the sim says which way this one faces.
                if car.facesLeft {
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
                nodes.body.color = .black
                nodes.body.colorBlendFactor = car.level == 1 ? GameScene.farLaneShade : 0
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
                stageGround.addChild(helicopterNode!)
                helicopterId = flying.id
            }
            helicopterNode?.position = SpriteLibrary.point(Vec2(x: flying.x, y: flying.y))
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
        node.xScale = flying.speed > 0 ? 1 : -1
        let hoop = match.stage.hoops[flying.hoop]
        let width = 96 * CGFloat(TrafficTuning.helicopterScale)
        let rows = HighwayArt.artRows["helicopter"]!
        let height = width * (rows.bottom - rows.top)
        let tones = helicopterTones(for: hoop)
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
    /// A grey energy frame toned as `Look.energyTone` does: black to the colour over the
    /// dark half, the colour to a quarter of the way to white over the light half; the
    /// colour each node's own `a_glow`.
    private lazy var energyToneShader: SKShader = {
        let shader = SKShader(source: """
        void main() {
            vec4 texel = texture2D(u_texture, v_tex_coord);
            float level = texel.a > 0.0 ? texel.r / texel.a : 0.0;
            vec3 toned = level <= 0.5 ? a_glow * (level * 2.0) : mix(a_glow, vec3(1.0), (level * 2.0 - 1.0) * 0.25);
            gl_FragColor = vec4(toned * texel.a, texel.a) * v_color_mix.a;
        }
        """)
        shader.attributes = [SKAttribute(name: "a_glow", type: .vectorFloat3)]
        return shader
    }()

    private func setGlow(_ node: SKSpriteNode, _ colour: SKColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        node.setValue(SKAttributeValue(vectorFloat3: SIMD3<Float>(Float(r), Float(g), Float(b))), forAttribute: "a_glow")
    }

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
        // Upright whatever the body's lean.
        shadow.zRotation = 0
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
    private var nets: [HoopNet] = []

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
                stageGlowers.addChild(node)
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
                stageGround.addChild(marker)
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
                stageGlowers.addChild(portalNode!)
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
        let texture = sprites.snowflake
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
                // Left in the air, any frame of the jump or the double jump, not just the one it was in.
                let jumpSheets: [Animation] = [owner.hasBall ? .airBall : .air, .doubleJump]
                let frame = owner.grounded ? owner.animationFrame
                    : jumpSheets.flatMap { sheet in (0..<sheet.frameCount).map { AnimationFrame(sheet, $0) } }.randomElement()!
                let node = SKSpriteNode(texture: sprites.texture(frame, player: clone.owner))
                node.size = node.texture!.size()
                if let outline = sprites.outlineTexture(frame, player: clone.owner) {
                    // Its line too, in ice like the rest of it.
                    let line = SKSpriteNode(texture: outline)
                    line.size = node.size
                    line.anchorPoint = sprites.anchor(for: frame.animation)
                    line.color = GameScene.ice
                    line.colorBlendFactor = 1
                    line.zPosition = 0.1
                    node.addChild(line)
                }
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
        sectionMark = CACurrentMediaTime()
        stepHeadParticles()
        section("particles")
        // The figure in front: the one with the ball, else the last to touch it.
        if let front = match.ball.holder ?? match.ball.lastTouched { frontFigure = front }
        for (index, figure) in figureLayers.enumerated() { figure.zPosition = index == frontFigure ? 0.5 : 0 }
        for (index, player) in match.players.enumerated() {
            let node = playerNodes[index]
            let frame = player.animationFrame
            section("bodies")
            playFrameSounds(index, frame: frame, grounded: player.grounded, at: player.position)
            section("sounds")
            // Zeus Juice's bolt throw with nothing in hand plays the whole sheet, its ball as energy.
            let wholeSheet = player.boltPose > 0 && !player.hasBall
            node.texture = sprites.texture(frame, player: index, ballAsEnergy: wholeSheet)
            // Titan Tea's size, grown into after its port-in.
            if titanGrowDelay[index] > 0 {
                titanGrowDelay[index] -= 1
            } else if titanGrowth[index] < 1 {
                titanGrowth[index] = min(titanGrowth[index] + 1 / CGFloat(GameScene.titanGrowFrames), 1)
            }
            let drawScale = 1 + (CGFloat(player.spec.scale) - 1) * titanGrowth[index]
            let growing = player.spec.scale != 1 && titanGrowth[index] < 1
            node.size = node.texture!.size().scaled(by: drawScale)
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
                node.position = node.position + CGPoint(x: nudge.x * CGFloat(player.facing.sign), y: nudge.y) * drawScale
            }
            node.xScale = CGFloat(player.facing.sign)
            // Frozen, the body goes ice; in the throw stance's parry frames, and growing, white.
            let tint: SKColor = player.throwParrying || growing ? .white : GameScene.ice
            let tintShare: CGFloat = growing ? 1 : (player.throwParrying ? 0.85 : (player.frozen > 0 ? 0.6 : 0))
            node.color = tint
            node.colorBlendFactor = tintShare
            headNodes[index].color = tint
            headNodes[index].colorBlendFactor = tintShare

            // In flight the body leans into its motion: forward tips it ahead, backward tips
            // it back, up to thirty degrees, eased so it doesn't snap.
            var wantedTilt: CGFloat = 0
            if player.state == .flying {
                let ahead = player.velocity.x * player.facing.sign / SmoothieRules.flightSpeed(level: player.powerLevel, withBall: false)
                wantedTilt = -CGFloat(min(max(ahead, -1), 1)) * GameScene.flightTilt * CGFloat(player.facing.sign)
            }
            bodyTilt[index] += (wantedTilt - bodyTilt[index]) * 0.2
            node.zRotation = bodyTilt[index]

            // Hit by the blade, the body and head flicker a dark shade of their energy, every
            // other pair of frames; locked out after a 47 basket, black, every other four.
            let stunned = player.hitStun > 0 && (player.hitStun / 2) % 2 == 0
            let lockedOut = player.hitStun == 0 && player.pickupLockout > 0 && (player.pickupLockout / 4) % 2 == 0
            let flashColour = lockedOut ? SKColor(rgb: PixelPalette.outline) : SKColor(rgb: sprites.look(for: index).energyTone(luminance: 0.15))
            for (flash, source) in [(stunBodies[index], node), (stunHeads[index], headNodes[index])] {
                flash.isHidden = !(stunned || lockedOut) || source.isHidden
                guard stunned || lockedOut else { continue }
                flash.color = flashColour
                flash.texture = source.texture
                flash.size = source.size
                flash.anchorPoint = source.anchorPoint
                flash.position = source.position
                flash.xScale = source.xScale
                flash.yScale = source.yScale
                flash.zRotation = source.zRotation
            }

            // Prone in the snipe, the cursor where it's aimed.
            snipeCursors[index].isHidden = player.state != .gunSnipe
            if player.state == .gunSnipe { snipeCursors[index].position = SpriteLibrary.point(player.snipeCursor) }

            // The line round the body, in the look's outline or cycling through the zone's.
            let outlineNode = outlineNodes[index]
            if let outline = sprites.outlineTexture(frame, player: index, ballAsEnergy: wholeSheet) {
                outlineNode.isHidden = false
                outlineNode.texture = outline
                outlineNode.size = node.size
                outlineNode.anchorPoint = node.anchorPoint
                // White as the body is, growing or parrying; ice, frozen; else the look's or the zone's.
                let lineColour = ZoneTuning.inTheZone ? ZoneTuning.outline(at: CACurrentMediaTime()) : SKColor(rgb: sprites.look(for: index).outline)
                outlineNode.color = growing || player.throwParrying ? .white : (player.frozen > 0 ? GameScene.ice : lineColour)
            } else {
                outlineNode.isHidden = true
            }

            // The frame's energy rides exactly where the body is drawn.
            let energyNode = energyNodes[index]
            if let energy = sprites.energyTexture(frame, player: index, ballAsEnergy: wholeSheet) {
                energyNode.isHidden = false
                energyNode.texture = energy
                // In the zone the energy (the slash's blade among it) runs the zone's colours.
                setGlow(energyNode, ZoneTuning.inTheZone ? ZoneTuning.outline(at: CACurrentMediaTime()) : SKColor(rgb: sprites.look(for: index).glow))
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
            // In the zone the ball in hand runs the zone's colours.
            let teamColour = ZoneTuning.inTheZone ? ZoneTuning.outline(at: CACurrentMediaTime()) : SKColor(rgb: sprites.look(for: index).glow)
            handBall.color = player.hasFireball ? GameScene.fireballColour : teamColour
            halo.color = player.hasFireball ? GameScene.fireballColour : teamColour
            if player.holding, let landmark = sprites.landmark(.ball, in: frame, player: index) {
                let inHand = landmark * drawScale
                let ballX = player.position.x + Double(inHand.x) * player.facing.sign / SpriteLibrary.pixelsPerUnit
                let dribbling = [Animation.dribbleIdle, .dribbleWalk, .dribbleRun].contains(frame.animation)
                let drop = player.grounded && dribbling ? match.stage.drop(fromX: ballX, y: player.position.y) * SpriteLibrary.pixelsPerUnit : 0
                let phase = min(max(inHand.y / (CGFloat(BallRules.dribbleHandHeight) * drawScale), 0), 1)
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
            if let landmark = sprites.landmark(.head, in: frame, player: index),
               let headTexture = sprites.headTexture(frame, player: index),
               let anchor = sprites.headAnchor(frame, player: index) {
                let head = landmark * drawScale
                let target = node.position + leaned(CGPoint(x: head.x * CGFloat(player.facing.sign), y: head.y))
                if headShown[index] == .zero { headShown[index] = target }
                let lag = headVariant.lag
                headShown[index] = CGPoint(x: headShown[index].x + (target.x - headShown[index].x) * lag,
                                           y: headShown[index].y + (target.y - headShown[index].y) * lag)
                var offset = headShown[index] - target
                if headVariant.reversedAcross { offset.x = -offset.x }
                let bob = (sin(Double(match.frame) / 60 * 2 * .pi * 1.2) * 1).rounded()
                let shown = CGPoint(x: (target.x + offset.x).rounded(), y: (target.y + offset.y).rounded() + (bob + GameScene.headLift) * drawScale)
                headNode.isHidden = false
                headNode.texture = headTexture
                // Sized outright rather than scaled, and only ever flipped.
                headNode.size = headTexture.size().scaled(by: GameScene.headScale * drawScale)
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
                // A human's head is on the body: its particles still rise off it.
                if HumanLook.enabled, let landmark = sprites.landmark(.head, in: frame, player: index) {
                    let head = landmark * drawScale
                    let at = node.position + leaned(CGPoint(x: head.x * CGFloat(player.facing.sign), y: head.y))
                    emitHeadParticles(index, power: player.power, at: CGPoint(x: at.x, y: at.y + 4))
                }
            }
            // A human's legs, in the energy's colours, give off smaller cubes of their own.
            if HumanLook.enabled, ParticleLook.cubes {
                for (slot, part) in [BodyPart.frontLeg, .backLeg].enumerated() {
                    guard let landmark = sprites.landmark(part, in: frame, player: index) else { continue }
                    let leg = landmark * drawScale
                    let at = node.position + leaned(CGPoint(x: leg.x * CGFloat(player.facing.sign), y: leg.y))
                    emitHeadParticles(index, power: player.power, at: at, creditKey: GameScene.legCreditKey + index * 2 + slot,
                                      streams: [legStream(index, part: part)])
                }
            }

            placeSurf(index, player: player, body: node, head: headNode)
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
        section("bodies")
        drawPowersLeavings()
        section("powers")
        drawField()
        section("field")
        drawTraffic()
        section("traffic")
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
                // Drawn on past the anchor off the top of the screen, as if hung from the sky.
                let hung = SpriteLibrary.point(anchor)
                let top = cameraNode.position.y + size.height * cameraNode.yScale / 2 + 16
                let rise = hung.y - chest.y
                let reach = rise > 0 ? max((top - chest.y) / rise, 1) : 1
                swing.path = line(from: CGPoint(x: chest.x + (hung.x - chest.x) * reach, y: chest.y + rise * reach), to: chest)
            } else {
                swing.isHidden = true
            }
            let shot = shotWebs[index]
            if let web = player.webLine {
                var end: CGPoint
                switch web.target {
                case .point(let point):
                    end = SpriteLibrary.point(point)
                    // A miss goes out to its tip over the first half of its frames and back over the rest.
                    if web.frames <= WebRules.missFrames {
                        let half = CGFloat(WebRules.missFrames) / 2
                        let out = CGFloat(WebRules.missFrames - web.frames)
                        let share = out < half ? (out + 1) / half : CGFloat(web.frames) / half
                        end = CGPoint(x: chest.x + (end.x - chest.x) * share, y: chest.y + (end.y - chest.y) * share)
                    }
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
        section("webs")

        let ball = match.ball
        ballNode.isHidden = ball.holder != nil
        ballNode.position = SpriteLibrary.point(ball.position)
        // Frozen it goes ice; burning it goes fire.
        let colour = ball.frozen > 0 ? GameScene.ice : (ball.burning ? GameScene.fireballColour : ballColour)
        ballNode.color = colour
        ballHalo.color = colour
        // The field's camera: level, sliding from zone to zone.
        if match.stage.features.look == .footballField { slideCamera(to: cameraTargetX()) }
        placeBallCamFrame()
        circlesOverCam.isHidden = !ballCamEnabled
        // 47's lines breathe, slowly, between gone and a quarter.
        if !threePointArcs.isHidden {
            let breath = CGFloat(0.5 - 0.5 * cos(CACurrentMediaTime() / ThreePointTuning.breathSeconds * 2 * .pi))
            for arc in threePointArcSides { arc.node.alpha = ThreePointTuning.breathMax * breath }
        }
        // Quake-Up Coffee's shake: the camera a pixel or two off, a few frames.
        if shake > 0 {
            shake -= 1
            let wobble = CGFloat(shake % 2 == 0 ? 1 : -1) * CGFloat(min(shake, 4))
            cameraNode.position = CGPoint(x: cameraBase.x + wobble, y: cameraBase.y + wobble * 0.75)
        } else {
            cameraNode.position = cameraBase
        }
        // The game-winner's finish, easing in on the ball; the HUD kept its size.
        if finishFrames > 0 {
            if flow == .playing {
                finishFrames += 1
                let share = min(Double(finishFrames) / Double(GameScene.finishZoomFrames), 1)
                let eased = CGFloat(0.5 - 0.5 * cos(share * .pi))
                // On the ball wherever it's drawn, in a hand or loose, and where it was last
                // seen while it's drawn nowhere.
                if let holder = match.ball.holder, handBalls.indices.contains(holder), !handBalls[holder].isHidden {
                    finishTarget = handBalls[holder].position
                } else if !ballNode.isHidden {
                    finishTarget = ballNode.position
                }
                let ballAt = finishTarget ?? cameraBase
                cameraNode.position = cameraBase + (ballAt - cameraBase) * eased
                cameraNode.setScale(cameraBaseScale * (1 - (1 - GameScene.finishZoom) * eased))
            } else {
                finishFrames = 0
                finishTarget = nil
                cameraNode.setScale(cameraBaseScale)
            }
            glowHud.setScale(cameraNode.xScale * hudScale)
        }
        glowHud.position = cameraNode.position
        ballTrail.position = ballNode.position
        ballTrail.particleColor = colour
        ballTrail.particleBirthRate = ball.isLive && !ball.resting && ball.velocity.length > 1 ? 90 : 0
        // Blazing Boba's burning shot trails the head's fire as well.
        if ball.burning, ball.holder == nil, ball.isLive, !ball.resting, ball.velocity.length > 1 {
            emitHeadParticles(ball.lastTouched ?? 0, power: .blazingBoba, at: ballNode.position,
                              creditKey: GameScene.ballFireCreditKey, rateScale: GameScene.ballFireRate,
                              trailing: CGVector(dx: -ball.velocity.x, dy: -ball.velocity.y))
        }

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
                chevron.texture = ballChevronOffScreen
                chevron.size = ballChevronOffScreen.size()
                chevron.colorBlendFactor = 0
                chevron.zRotation = side > 0 ? .pi / 2 : -.pi / 2
                chevron.position = CGPoint(x: cameraNode.position.x + side * (halfView - 10 - CGFloat(index) * 7), y: ballAt.y)
                chevron.alpha = step == index ? 1 : 0.3
                continue
            }
            chevron.zRotation = 0
            chevron.texture = ballChevronOver
            chevron.size = ballChevronOver.size()
            chevron.colorBlendFactor = 1
            chevron.isHidden = !showChevrons
            chevron.position = ballNode.position + CGPoint(x: 0, y: 32 - CGFloat(index) * 7)
            chevron.alpha = step == index ? 1 : 0.3
        }
        let rival = 1 - localIndex
        if match.players.indices.contains(rival) {
            let chest = SpriteLibrary.point(match.players[rival].chest)
            let side: CGFloat? = chest.x > cameraNode.position.x + halfView ? 1 : (chest.x < cameraNode.position.x - halfView ? -1 : nil)
            opponentChevron.isHidden = side == nil
            if let side {
                opponentChevron.color = SKColor(rgb: sprites.look(for: rival).glow)
                opponentChevron.zRotation = side > 0 ? .pi / 2 : -.pi / 2
                opponentChevron.position = CGPoint(x: cameraNode.position.x + side * (halfView - 10), y: chest.y)
            }
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
            // A basket flashes the hoop white, rim and backboard; the art is one frame.
            for art in [rimNodes[index], backboardNodes[index]] {
                art.color = .white
                art.colorBlendFactor = rimFlash[index] > 0 ? 0.8 : 0
            }
            // A rim that moves, under the highway's helicopter, and its net with it; the art
            // and the net each at their tuned offset from the rim.
            if index < match.stage.hoops.count {
                rimNodes[index].position = GameScene.hoopArtPoint(for: match.stage.hoops[index])
                rimNodes[index].xScale = match.stage.hoops[index].backboard == .left ? -1 : 1
                backboardNodes[index].position = rimNodes[index].position
                backboardNodes[index].xScale = rimNodes[index].xScale
                if index < nets.count {
                    nets[index].step(rim: GameScene.netPoint(for: match.stage.hoops[index]), ball: ballNode.isHidden ? nil : ballNode.position,
                                     ballRadius: CGFloat(BallRules.radius) * SpriteLibrary.pixelsPerUnit + 1,
                                     bodies: match.players.map { SpriteLibrary.point($0.chest) })
                }
            }
        }

        section("net")

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
        // Web Water's aim, held: dots out along it to the line's reach, like the shot's.
        for player in match.players where player.webAiming {
            let spacing = WebRules.lineRange / Double(GameScene.webAimDots)
            for step in 1...GameScene.webAimDots where shownDots < previewDots.count {
                let dot = previewDots[shownDots]
                dot.isHidden = false
                dot.alpha = step == 1 ? 0.9 : 0.35
                dot.position = SpriteLibrary.point(player.chest + player.webAimDirection * (spacing * Double(step)))
                shownDots += 1
            }
        }
        for dot in previewDots[shownDots...] { dot.isHidden = true }
        section("ball")

        drawHitboxes()
        section("hitbox")
        // The count in title lettering, BALL OUT as it ends, and any other banner for its frames.
        // With a screen up or on its way, the count waits: it starts again as play comes back.
        let counting = flow == .playing && pendingFlow == nil
        if match.countdown > 0, !counting {
            // BUCKET and the rest play out meanwhile.
            tickBanner()
        } else if match.countdown > 0 {
            let number = (match.countdown + 59) / 60
            // Each number's own sound as it goes up, in play only, not under a screen.
            if number != lastCountSounded {
                lastCountSounded = number
                if let sound = SoundBoard.count[number] { SoundBoard.shared.play(sound) }
            }
            TitleText.set(banner, to: "\(number)", size: 80)
            banner.isHidden = false
            bannerFrames = 0
        } else if lastCount > 0 {
            lastCountSounded = 0
            showBanner("BALL OUT!!!", size: 48)
            // Both his takes at once, each half toward its own side.
            SoundBoard.shared.play(.ballOut, pan: -0.5)
            SoundBoard.shared.play(.ballOut2, pan: 0.5)
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
        fpsLabel.text = "\(framesPerSecond) fps  worst \(worstFrameMilliseconds) ms\n\(frameReadout)"
        let p = match.players[localIndex]
        let side: String
        if online != nil {
            side = "  net lead \(session.frame - session.remoteFrame) rollbacks \(session.rollbacks)/\(session.framesRerun)\(session.desynced ? "  DESYNC" : "")"
        } else {
            side = aiOn ? "  ai \(String(describing: opponent.current))" : "  vs pad"
        }
        debugLabel.text = String(format: "%@ %d  v %.2f %.2f  stick %.2f %.2f  jumps %d%@%@%@",
                                 String(describing: p.state), p.stateTimer, p.velocity.x, p.velocity.y,
                                 lastLocalInput.stick.x, lastLocalInput.stick.y, p.jumpsLeft,
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
        if let gallery = boundsGallery {
            _ = gallery.tap(at: hudPoint(point, viewSize: viewSize))
            return
        }
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
