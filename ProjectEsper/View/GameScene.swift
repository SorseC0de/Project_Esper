import EsperSim
import SpriteKit
import CoreImage
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
    /// The energy form's head, drawn apart a quarter bigger, kept on its body without lag or bob.
    private static let headsRide = true
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
    private var sideColours = PlayerCustomization.sides.map(\.energy)
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
    /// The manga sound words on screen, kept out of the glow.
    private var soundWords: [SKNode] = []
    /// The sim's boxes drawn over the world while the HITBOX toggle is on: bodies, the
    /// loose ball, the catch reach round each chest, and any live leg, blade or reach.
    private let hitboxLayer = SKNode()
    private var showHitboxes = false
    /// The stage's solids over the world while the WALLS toggle is on: tiles red, one-ways
    /// yellow, the solid boxes (the backboards) cyan, where a ball goes back from magenta.
    private let wallsLayer = SKNode()
    private var showWalls = false
    private var drawnWalls: (tiles: [Tile], boxes: [Box], outOfReach: [Box])?
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
    /// Each human's hood over its head, and the frame it was drawn for.
    private var hoodNodes: [SKSpriteNode] = []
    private var hoodFlashes: [SKSpriteNode] = []
    private var hoodStrings: [HoodStrings] = []
    static let hoodDrawnFor = AnimationFrame(.idle, 2)
    /// Palette 37's grey level (#DAE0EA), the strings' second pixel from the tip.
    static let stringAccentLuminance = 0.876
    /// Over the body and under the head's own node, or behind the body.
    private static let hoodUpZ: CGFloat = 0.038
    /// Over the body's flash (0.09).
    private static let hoodFlashZ: CGFloat = 0.091
    /// Super Smoothie's head tipped flying up or down: radians, eased in a share a frame, and how
    /// many art pixels it's let down when tipped all the way.
    private static let flightHeadTip: CGFloat = .pi / 15
    private static let headTipEase: CGFloat = 0.2
    private static let flightHeadDrop: CGFloat = 2
    private var headTip: [Int: CGFloat] = [:]

    /// A hood turned `angle` about `pivot` on its 48-pixel canvas, where it stays put.
    private func turn(_ hood: SKSpriteNode, about pivot: CGPoint, by angle: CGFloat, scale: CGFloat) {
        let canvas: CGFloat = 48
        let flip: CGFloat = hood.xScale < 0 ? -1 : 1
        let offset = CGPoint(x: (pivot.x - canvas * hood.anchorPoint.x) * scale * flip, y: (canvas - pivot.y - canvas * hood.anchorPoint.y) * scale)
        let base = hood.zRotation
        hood.position = hood.position + CGPoint(x: offset.x * cos(base) - offset.y * sin(base), y: offset.x * sin(base) + offset.y * cos(base))
        hood.anchorPoint = CGPoint(x: pivot.x / canvas, y: (canvas - pivot.y) / canvas)
        hood.zRotation = base + angle
    }
    /// FloState's floating strings over the energy form's own head (0.04), so nothing of the body covers them.
    private static let floatingStringZ: CGFloat = 0.045
    /// The line round each body, a child of it so it rides the body exactly, drawn in white
    /// and coloured each frame: the look's outline, or the zone's.
    private var outlineNodes: [SKSpriteNode] = []
    /// The change's eyes, `transform_eyes` in the energy's colour over the body.
    private var eyesNodes: [SKSpriteNode] = []
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
    /// The skin alone over each body, flashing palette 17 while FloState is locked out.
    /// Locked out of FloState, the clothes flash grey, the hood's among them: over the clothes, and
    /// over the hood. Which players are grey this frame, for the glow's mask.
    private var lockoutClothes: [SKSpriteNode] = []
    private var lockoutHoods: [SKSpriteNode] = []
    private var greyedOut: Set<Int> = []
    private static let lockoutGrey = PixelPalette.colours[39]
    private var headShown: [CGPoint] = []
    /// Each body's lean in flight, radians, eased toward where it's going, and how much of
    /// the hover it's showing.
    private var bodyTilt: [CGFloat] = []
    private var hover: [CGFloat] = []
    /// What the powers leave in the world, by the sim's ids: bolts, ice clones, flames,
    /// fireballs.
    private var boltNodes: [Int: SKSpriteNode] = [:]
    private var cloneNodes: [Int: SKSpriteNode] = [:]
    /// Gale Ale's tornados as drawn, by id, and their bursts playing out.
    private var galeNodes: [Int: SKSpriteNode] = [:]
    private var beamNodes: [Int: SKNode] = [:]
    /// The beam's sheet's pieces, 16 pixels square.
    private static let beamPieceSide: CGFloat = 16
    /// The beam's halo: its strength, and its thickness over the beam's.
    private static let beamGlow: CGFloat = 0.5
    private static let beamGlowWidth: CGFloat = 3
    /// Z Tea's blast arms over each body, turned about the shoulder: where the arms meet the body
    /// on their canvas, and that point from the feet, in art pixels.
    private var blastArmNodes: [Int: SKSpriteNode] = [:]
    private static let blastArmsAnchor = CGPoint(x: 31.5 / 64, y: 33.5 / 64)
    private static let blastShoulder = CGSize(width: -0.5, height: 17.5)
    /// The firing loop's even frames, 4 and 6, have the body a pixel right and two down.
    private static let blastEvenFrameShift = CGPoint(x: 1, y: -2)
    private func blastArms(_ index: Int, on body: SKSpriteNode) -> SKSpriteNode {
        if let arms = blastArmNodes[index], arms.parent === body { return arms }
        let arms = SKSpriteNode()
        arms.anchorPoint = GameScene.blastArmsAnchor
        arms.zPosition = 0.2
        arms.isHidden = true
        body.addChild(arms)
        blastArmNodes[index] = arms
        return arms
    }
    /// The tornado's sheet squeezed to the gale's shape: two thirds as high, a third wider.
    private static let galeScale = CGSize(width: 4.0 / 3, height: 2.0 / 3)
    private var flameNodes: [Int: SKSpriteNode] = [:]
    private var fireballNodes: [Int: SKSpriteNode] = [:]
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
    /// The basketball's art: three 8x8 frames, painted as they are; the team's colour is the halo round it.
    private static let basketballSize = CGSize(width: 8, height: 8)
    /// Seconds a dribbling ball holds each of its frames.
    private static let dribbleFrameSeconds = 0.2
    /// Turns a second a shot or a throw leaves the hand spinning, backwards, and the most the ball ever turns.
    private static let backspinTurnsPerSecond = 1.5
    private static let mostSpinTurnsPerSecond = 4.0
    /// The loose ball's spin: its angle and rate (counter-clockwise up, radians), the frame it turns on,
    /// and what it was doing last update, to tell a launch and a bounce from a fall.
    private var ballSpin = (angle: CGFloat(0), rate: CGFloat(0), frame: 0)
    private var ballSeen: (velocity: Vec2, y: Double, held: Bool, time: Double)?
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
    /// The Wreck Center's hoop supports, one picture a hoop, behind the backboard.
    private var supportNodes: [SKSpriteNode] = []
    private var rimNodes: [SKSpriteNode] = []
    private var rimFlash: [Int] = []
    /// Each straight rim's front lip, drawn over the ball (in its layer, the glowers', past the
    /// ball's depth) while the rim itself is under it.
    private var rimFronts: [SKSpriteNode] = []
    private static let rimFrontZ: CGFloat = 6.5

    /// The rim's art with only its front lip left: the ring's lower half, the rows under its middle.
    private func frontLip(of rim: SKTexture) -> SKTexture? {
        let image = rim.cgImage()
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // Rows run down from the top in memory.
        let rows = (0..<height).filter { row in (0..<width).contains { pixels[(row * width + $0) * 4 + 3] != 0 } }
        guard let top = rows.first, let bottom = rows.last else { return nil }
        let middle = (top + bottom) / 2
        for row in 0...middle {
            for column in 0..<width { for channel in 0..<4 { pixels[(row * width + column) * 4 + channel] = 0 } }
        }
        guard let made = context.makeImage() else { return nil }
        let texture = SKTexture(cgImage: made)
        texture.filteringMode = .nearest
        return texture
    }
    /// Frames left of a hoop's shake: the rim's, off the ball on it, and the backboard's,
    /// off the ball against it, the rim riding it.
    private var rimJitter: [Int] = []
    private var boardJitter: [Int] = []
    /// Each rim's dip in degrees, down at the front, and how fast it's turning.
    private var rimDip: [CGFloat] = []
    private var rimSpin: [CGFloat] = []
    private var previewDots: [SKSpriteNode] = []
    private static let webAimDots = 12
    private let scoreLabel = SKLabelNode()
    private let debugLabel = SKLabelNode()
    /// The local side's power and level, lettered top-left under the pickers.
    private let powerLabel = SKSpriteNode()
    private let fpsLabel = SKLabelNode()
    /// The performance readout in the corner, parked until performance is being diagnosed.
    static let diagnosingPerformance = false
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

    /// The hooded heads' hoods, cut out of the glow's body mask in black so they glow as the
    /// energy does; and their faces, shielded in red, so no glow lands on them.
    var hoodSnapshots: [BodySnapshot] {
        // Every string with it, up or down: over skin, which never glows, they were swallowed. In
        // FloState the face is energy and glows with the hood.
        hoodMaskSnapshots(\.hood) + hoodMaskSnapshots(\.face, only: energyHoods)
            + hoodStrings.indices.filter { !greyedOut.contains($0) }.flatMap { hoodStrings[$0].snapshots }
    }
    var shieldedSnapshots: [BodySnapshot] { hoodMaskSnapshots(\.face, only: Set(hoodNodes.indices).subtracting(energyHoods)) }
    /// The players whose hooded head is FloState's, its face energy.
    private var energyHoods: Set<Int> = []
    private func hoodMaskSnapshots(_ part: KeyPath<(hood: SKTexture, face: SKTexture), SKTexture>, only: Set<Int>? = nil) -> [BodySnapshot] {
        hoodNodes.indices.filter { only?.contains($0) ?? true }.compactMap { index in
            let node = hoodNodes[index]
            // Only the hooded head has masks; the hood down behind has none. Greyed out, it glows not at all.
            guard !node.isHidden, !greyedOut.contains(index), let masks = hoodMasks[index] else { return nil }
            return BodySnapshot(texture: masks[keyPath: part], position: node.position, anchor: node.anchorPoint, xScale: node.xScale,
                                size: node.size, zRotation: node.zRotation)
        }
    }
    /// Each hooded head's hood and face alone this frame, by player.
    private var hoodMasks: [Int: (hood: SKTexture, face: SKTexture)] = [:]

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

    /// 47 on a stage whose rim swims: while the local player aims a shot, a short stretch of the
    /// three-point line round wherever the rim is, toward them, 5 tiles long and 2 pixels thick,
    /// fading in and out along its length in their energy.
    private var swimmingThreeLine: [SKSpriteNode] = []
    private static let swimmingThreeSegments = 20
    private static let swimmingThreeLength: CGFloat = 80

    private func drawSwimmingThreeLine() {
        if swimmingThreeLine.isEmpty {
            swimmingThreeLine = (0..<GameScene.swimmingThreeSegments).map { _ in
                let segment = SKSpriteNode(texture: sprites.flatSquare(size: 4, alpha: 1))
                segment.colorBlendFactor = 1
                // Over the water's tint.
                segment.zPosition = 96
                segment.isHidden = true
                world.addChild(segment)
                return segment
            }
        }
        let hoop = match.stage.hoops.first
        let aiming = match.players.indices.contains(localIndex) && match.players[localIndex].state == .shootStance
        guard gameMode == .fortySeven, aiming, let hoop, hoop.shared, hoop.position != HighwayRules.parked else {
            swimmingThreeLine.forEach { $0.isHidden = true }
            return
        }
        let rim = SpriteLibrary.point(hoop.position)
        let radius = CGFloat(FortySevenRules.threePointRadius(for: hoop, on: match.stage) * SpriteLibrary.pixelsPerUnit)
        let chest = SpriteLibrary.point(match.players[localIndex].chest)
        let toward = atan2(chest.y - rim.y, chest.x - rim.x)
        let half = GameScene.swimmingThreeLength / 2 / radius
        let count = CGFloat(swimmingThreeLine.count)
        let colour = SKColor(rgb: sprites.look(for: localIndex).glow)
        for (index, segment) in swimmingThreeLine.enumerated() {
            let share = (CGFloat(index) + 0.5) / count
            let angle = toward - half + share * half * 2
            segment.isHidden = false
            segment.color = colour
            segment.size = CGSize(width: 2, height: GameScene.swimmingThreeLength / count + 0.5)
            segment.position = CGPoint(x: rim.x + radius * cos(angle), y: rim.y + radius * sin(angle))
            segment.zRotation = angle
            // Clear at both ends, the energy's colour in the middle.
            segment.alpha = sin(.pi * share)
        }
    }

    /// How the Hoopfish's antenna nods this frame, as a turn of a world point about where it
    /// meets the body, mirrored as the fish faces; none off Wetshot Wake or with no fish.
    private func hoopfishNod(_ hoop: Int) -> (angle: CGFloat, turn: (CGPoint) -> CGPoint) {
        guard hoop == 0, let fish = match.hoopfish, let node = wetshotArt?.hoopfish, !wholeStageView else { return (0, { $0 }) }
        let dunkedOn = match.players.contains { $0.state == .dunking }
        let angle = WetshotArt.antennaTurn(at: CACurrentMediaTime(), dunkedOn: dunkedOn) * (fish.facesRight ? -1 : 1)
        let pivot = CGPoint(x: node.position.x + WetshotArt.antennaPivot.x * node.xScale, y: node.position.y + WetshotArt.antennaPivot.y)
        return (angle, { point in
            let offset = point - pivot
            return CGPoint(x: pivot.x + offset.x * cos(angle) - offset.y * sin(angle), y: pivot.y + offset.x * sin(angle) + offset.y * cos(angle))
        })
    }

    /// Wetshot Wake's sway over the whole screen, but not in the map maker: its reach in the
    /// drawable's pixels, how many waves down the screen, and where it is in them.
    /// The score's band across the top doesn't sway: how far down the screen it reaches, as a share.
    var screenWave: (reach: Double, waves: Double, phase: Double, calmTop: Double)? {
        guard match.stage.features.look == .wetshot, !wholeStageView else { return nil }
        let pixelsPerGamePixel = Double(displayScale / cameraNode.xScale)
        let calm = (safeInsets.top / hudScale + 40) * hudScale / max(size.height, 1)
        return (WaterTuning.swayPixels * pixelsPerGamePixel, WaterTuning.swayWaves, CACurrentMediaTime() * WaterTuning.swaySpeed, Double(calm))
    }

    /// The Elements' flat background, which never glows; nil elsewhere.
    var unglowedBackground: SKColor? { [StageLook.elements, .wetshot, .flight].contains(match.stage.features.look) ? backgroundColor : nil }

    /// The water's tint over the world, for what's drawn apart from the scene (the cubes); nil off Wetshot Wake.
    var waterTint: (top: RGB, bottom: RGB, alpha: CGFloat)? {
        match.stage.features.look == .wetshot ? (PixelPalette.colours[19], PixelPalette.colours[18], WaterTuning.overlayAlpha) : nil
    }

    /// What glows on Wetshot Wake over its background, which doesn't: the Hoopfish's rings and eye.
    var glowThroughSnapshots: [BodySnapshot] {
        guard let art = wetshotArt else { return [] }
        return art.fishGlowParts
    }

    /// Wetshot Wake's rims, in front of the Hoopfish, glowing through its mask.
    var glowThroughFrontSnapshots: [BodySnapshot] {
        guard wetshotArt != nil else { return [] }
        return rimNodes.filter { !$0.isHidden }.compactMap { rim in
            rim.texture.map { BodySnapshot(texture: $0, position: rim.position, anchor: rim.anchorPoint, xScale: rim.xScale, size: rim.size, zRotation: rim.zRotation) }
        }
    }

    /// Wetshot Wake's nets' strands, glowing through its mask.
    var glowThroughNets: [CGPath] {
        guard wetshotArt != nil else { return [] }
        return nets.compactMap(\.drawnPath)
    }

    /// The tornados as they look this frame, green under the bodies: they animate, so they can't
    /// live in the static layer.
    var tornadoSnapshots: [BodySnapshot] {
        // Gale Ale's tornados don't glow, as the Elements' don't, on any stage.
        let gales = galeNodes.values.compactMap { node in
            node.texture.map { BodySnapshot(texture: $0, position: node.position, anchor: node.anchorPoint, xScale: 1, size: node.size) }
        }
        return gales + stageTornadoSnapshots
    }

    private var stageTornadoSnapshots: [BodySnapshot] {
        if let wet = wetshotArt { return wet.fishFlats }
        // Only what's above the lava: sunk, the lava in front of them still glows.
        guard let art = elementsArt else { return [] }
        let hanging = hangingIcicles.values.compactMap { node in
            node.texture.map { BodySnapshot(texture: $0, position: node.position, anchor: node.anchorPoint, xScale: 1, size: node.size, zRotation: node.zRotation) }
        }
        return hanging + windSnapshots(windPuffs.back + rainSizzles + art.icicles + Array(fallingIcicles.values) + shatteringIcicles) + (art.tornados + art.tornadoOverlays).compactMap { GameScene.snapshot($0, above: ElementsArt.lavaTop) }
    }

    /// A node anchored at its lower left as the mask should draw it: only what's above `line`.
    private static func snapshot(_ node: SKSpriteNode, above line: CGFloat) -> BodySnapshot? {
        guard let texture = node.texture else { return nil }
        let visible = min(max((node.position.y + node.size.height - line) / node.size.height, 0), 1)
        guard visible > 0 else { return nil }
        if visible >= 1 { return BodySnapshot(texture: texture, position: node.position, anchor: .zero, xScale: 1, size: node.size) }
        return BodySnapshot(texture: SKTexture(rect: CGRect(x: 0, y: 1 - visible, width: 1, height: visible), in: texture),
                            position: CGPoint(x: node.position.x, y: line), anchor: .zero, xScale: 1,
                            size: CGSize(width: node.size.width, height: node.size.height * visible))
    }

    /// Wind puffs as drawn, for the mask to keep from glowing.
    private func windSnapshots(_ puffs: [SKSpriteNode]) -> [BodySnapshot] {
        puffs.compactMap { puff in
            puff.texture.map { BodySnapshot(texture: $0, position: puff.position, anchor: puff.anchorPoint, xScale: 1, size: puff.size) }
        }
    }

    /// The hoop supports and the sound words, drawn as they are: for the mask under the bodies,
    /// as they're drawn behind them.
    var soundWordSnapshots: [BodySnapshot] {
        var flat: [BodySnapshot] = supportNodes.filter { !$0.isHidden }.compactMap { node in
            node.texture.map { BodySnapshot(texture: $0, position: node.position, anchor: node.anchorPoint, xScale: node.xScale, size: node.size) }
        }
        for holder in soundWords where holder.parent != nil {
            guard let sprite = holder.children.first as? SKSpriteNode, let texture = sprite.texture else { continue }
            // The sprite sits out along the holder's turn, at the holder's scale.
            let turn = holder.zRotation, scale = holder.xScale
            let offset = CGPoint(x: (sprite.position.x * cos(turn) - sprite.position.y * sin(turn)) * scale,
                                 y: (sprite.position.x * sin(turn) + sprite.position.y * cos(turn)) * scale)
            flat.append(BodySnapshot(texture: texture, position: holder.position + offset, anchor: sprite.anchorPoint, xScale: 1,
                                     size: CGSize(width: sprite.size.width * scale, height: sprite.size.height * holder.yScale),
                                     zRotation: turn, warp: sprite.warpGeometry))
        }
        return flat
    }

    /// What's drawn in the world but must not glow, for the mask to mark: the hoops and the banner.
    var flatSnapshots: [BodySnapshot] {
        // Greyed out of FloState: the clothes, the hood and its strings, none glowing.
        let greys = greyedOut.flatMap { index -> [BodySnapshot] in
            let nodes = [lockoutClothes[index], lockoutHoods[index]].filter { !$0.isHidden }
            return nodes.compactMap { node in
                node.texture.map { BodySnapshot(texture: $0, position: node.position, anchor: node.anchorPoint, xScale: node.xScale, size: node.size, zRotation: node.zRotation) }
            } + hoodStrings[index].snapshots
        }
        return greys + flatSnapshotsLit
    }
    private var flatSnapshotsLit: [BodySnapshot] {
        // The hoops: their backboards read too hot with the glow on them.
        // Wetshot Wake's rim glows, as the Hoopfish's rings and eyes do.
        let unglowedRims = match.stage.features.look == .wetshot ? [] : rimNodes + rimFronts
        var flat = (backboardNodes + unglowedRims).filter { !$0.isHidden }.compactMap { rim in
            rim.texture.map { BodySnapshot(texture: $0, position: rim.position, anchor: rim.anchorPoint, xScale: rim.xScale, size: rim.size, zRotation: rim.zRotation) }
        }
        // The ball, in hand or loose: drawn as painted, its halo the glow.
        for node in handBalls + [ballNode] where !node.isHidden {
            if let texture = node.texture {
                flat.append(BodySnapshot(texture: texture, position: node.position,
                                         anchor: node.anchorPoint, xScale: 1, size: node.size, zRotation: node.zRotation))
            }
        }
        // The Elements' wind in front of everything.
        flat += windSnapshots(windPuffs.front + rainSplashes + lightningDots + lightningBolts)
        if let flash = lightningFlash, flash.parent != nil { flat += windSnapshots([flash]) }
        // And its rain, over everything.
        if !rainLayer.isHidden {
            flat += rainTiles.joined().filter { !$0.isHidden }.compactMap { GameScene.snapshot($0, above: ElementsArt.lavaSurfaceLine) }
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
            let pieces = HoopTuning.art(for: match.stage.features.look)
            for name in [pieces.backboard, pieces.rim] {
                let art = SKSpriteNode(texture: sprites.texture(name, 0))
                art.position = GameScene.hoopArtPoint(for: hoop, on: match.stage.features.look)
                art.xScale = hoop.backboard == .left ? -1 : 1
                art.zPosition = name == pieces.rim ? 6 : 5
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
        NetTuning.dropSavedIfStale()
        // The colours as last picked, before anything is drawn in them.
        for (index, side) in PlayerCustomization.sides.enumerated() {
            sprites.setLook(side.look, for: index)
        }
        addChild(world)
        world.addChild(ground)
        bodies.zPosition = 20
        world.addChild(bodies)
        glowers.zPosition = 21
        world.addChild(glowers)
        hitboxLayer.zPosition = 30
        world.addChild(hitboxLayer)
        wallsLayer.zPosition = 31
        world.addChild(wallsLayer)
        // The Elements' tornados again over the players, only above the lava.
        let overLava = SKSpriteNode(color: .white, size: CGSize(width: 100_000, height: 100_000))
        overLava.anchorPoint = CGPoint(x: 0.5, y: 0)
        overLava.position = CGPoint(x: 0, y: ElementsArt.lavaTop)
        tornadoOverlays.maskNode = overLava
        tornadoOverlays.zPosition = 22
        world.addChild(tornadoOverlays)
        // The rain over everything in the world, room left under it for more, stopping at the lava.
        let aboveLava = SKSpriteNode(color: .white, size: CGSize(width: 100_000, height: 100_000))
        aboveLava.anchorPoint = CGPoint(x: 0.5, y: 0)
        aboveLava.position = CGPoint(x: 0, y: ElementsArt.lavaSurfaceLine)
        rainLayer.maskNode = aboveLava
        rainLayer.zPosition = 90
        world.addChild(rainLayer)
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
        if DunkTuning.enabled {
            // Tuning holds the match from launch, so it starts on the stage being tuned.
            series.stage = DunkTuning.stage
            firstStage = DunkTuning.stage
            session = RollbackSession(match: Match(stage: series.stage.stage, countdown: GameScene.countdownFrames), localIndex: 0)
        }
        buildStage()
        builtStage = series.stage

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
            let hood = SKSpriteNode()
            hood.zPosition = GameScene.hoodUpZ
            hood.isHidden = true
            figure.addChild(hood)
            hoodNodes.append(hood)
            let hoodFlash = SKSpriteNode()
            hoodFlash.colorBlendFactor = 1
            hoodFlash.alpha = 0.85
            hoodFlash.isHidden = true
            figure.addChild(hoodFlash)
            hoodFlashes.append(hoodFlash)
            hoodStrings.append(HoodStrings(parent: figure, square: sprites.flatSquare(size: 1, alpha: 1)))
            let eyes = SKSpriteNode()
            eyes.zPosition = 0.035
            eyes.isHidden = true
            eyes.colorBlendFactor = 1
            figure.addChild(eyes)
            eyesNodes.append(eyes)
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
            for (layer, z) in [(\GameScene.lockoutClothes, CGFloat(0.037)), (\GameScene.lockoutHoods, GameScene.hoodUpZ + 0.0002)] {
                // The clothes under the hood, the hood's grey over it.
                let grey = SKSpriteNode()
                grey.color = SKColor(rgb: GameScene.lockoutGrey)
                grey.colorBlendFactor = 1
                grey.zPosition = z
                grey.isHidden = true
                figure.addChild(grey)
                self[keyPath: layer].append(grey)
            }
            headShown.append(.zero)
            bodyTilt.append(0)
            hover.append(0)
            titanGrowDelay.append(0)
            titanGrowth.append(1)
            lastStates.append(.idle)
            let colour = SKColor(rgb: sprites.look(for: player.index).glow)
            let handBall = SKSpriteNode(texture: sprites.basketballFrames[0])
            handBall.size = GameScene.basketballSize
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

        ballNode = SKSpriteNode(texture: sprites.basketballFrames[0])
        ballNode.size = GameScene.basketballSize
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

    // MARK: FLO

    /// The FLO meters along the bottom, the first player's left of the middle and the second's
    /// right of it: `FLO_meter` a point an art pixel, and over each bar's left end the word, in
    /// Bigdex as the sound words are drawn, big to small and flared. Shown in play. The bar
    /// shows what's been gathered: its empty share drawn over it, before its warp, as lines of
    /// the plum ramp's last, one a FLO; full, none and MAX on its top trailing corner; burning,
    /// its eight frames playing.
    private var floMeters: [SKSpriteNode] = []
    private var floBars: [SKSpriteNode] = []
    /// Each bar's holder, warped, its sparkles inside it with the bar so the warp takes them too.
    private var floBarHolders: [SKEffectNode] = []
    private var floMaxWords: [SKSpriteNode] = []
    /// Bar A's word, short of full and at it.
    private var floWordsShort: [SKSpriteNode] = []
    private var floWordsFull: [SKSpriteNode] = []
    /// What each bar shows now, its frame and FLO, so it's drawn again only when they change.
    private var floShown: [(frame: Int, flo: Int)] = []
    private static let floPointsPerPixel: CGFloat = 1
    private static let floGap: CGFloat = 20
    /// The scoreboard's middle under the screen's top edge (past its insets), in points.
    private static let scoreboardBelowTop: CGFloat = 16
    private static let floWordHeight: CGFloat = 14
    /// How far onto the bar the word reaches, and how far above its middle it sits, in points.
    private static let floWordOverlap: CGFloat = 6
    private static let floWordLift: CGFloat = 3
    /// The bar's inside, on its sheet: its first column, its top row, how tall; the last three
    /// columns shorter, as its end slants.
    private static let floFirstColumn = 6
    private static let floTopRow = 5
    private static let floLineHeights = [98: 4, 99: 3, 100: 2]
    /// The burn's frames a second.
    private static let floBurnFramesPerSecond = 12.0
    /// MAX: its cap height in points, before its slider's scale.
    private static let floMaxHeight: CGFloat = 6

    private var floStrokes: [SKSpriteNode] = []
    private let ciContext = CIContext()
    private var floBarTextures: [Int: SKTexture] = [:]

    /// A frame of the bar with `flo` gathered: one line over it for each FLO missing, from its
    /// first column on.
    private func floBarTexture(frame: Int, flo: Int) -> SKTexture {
        let variant = FloTuning.variant
        let key = (variant == .fillsFromWord ? 100_000 : 0) + frame * 1000 + flo
        if let made = floBarTextures[key] { return made }
        let sheet = sprites.texture("flo_meter", frame).cgImage()
        let width = sheet.width, height = sheet.height
        let empty = FloRules.full - min(max(flo, 0), FloRules.full)
        let texture: SKTexture
        if empty > 0, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.interpolationQuality = .none
            context.draw(sheet, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.setFillColor(SKColor(rgb: EsperPalette.plum.shadow).cgColor)
            // A: the missing from the first column on; B: from the last back.
            let columns = variant == .fillsFromWord ? (FloRules.full - empty + 1)...FloRules.full : 1...empty
            for column in columns {
                let tall = GameScene.floLineHeights[column] ?? 5
                // The picture's rows run up from its bottom: the inside's top row, down `tall`.
                context.fill(CGRect(x: GameScene.floFirstColumn + column - 1, y: height - GameScene.floTopRow - tall, width: 1, height: tall))
            }
            texture = context.makeImage().map { SKTexture(cgImage: $0) } ?? SKTexture(cgImage: sheet)
        } else {
            texture = SKTexture(cgImage: sheet)
        }
        texture.filteringMode = .nearest
        floBarTextures[key] = texture
        return texture
    }

    /// Where Z Tea's beam charges: between the hands as the charge's sheet draws them, or the
    /// one hand it shows, as the ball in hand is placed.
    private func chargeHands(_ frame: AnimationFrame, player index: Int, body: CGPoint, drawScale: CGFloat,
                             leaned: (CGPoint) -> CGPoint) -> CGPoint? {
        let hands = [BodyPart.frontHand, .backHand].compactMap { sprites.landmark($0, in: frame, player: index) }
        guard !hands.isEmpty else { return nil }
        let middle = CGPoint(x: hands.map(\.x).reduce(0, +) / CGFloat(hands.count), y: hands.map(\.y).reduce(0, +) / CGFloat(hands.count))
        let sign = CGFloat(match.players[index].facing.sign)
        return body + leaned(CGPoint(x: middle.x * drawScale * sign, y: middle.y * drawScale))
    }

    /// The FLO a meter shows: what the player has, less what's still on its way to them.
    private func shownFlo(_ index: Int) -> Int {
        guard match.players.indices.contains(index) else { return 0 }
        return max(match.players[index].flo - Int(floOnTheWay[index, default: 0].rounded()), 0)
    }

    /// Each bar drawn for what it shows now, and MAX up when it's full.
    private func updateFloMeters() {
        for index in floBars.indices where match.players.indices.contains(index) {
            let flo = shownFlo(index)
            let player = match.players[index]
            let now = CACurrentMediaTime()
            let frame = player.inFloState
                ? Int(now * GameScene.floBurnFramesPerSecond) % max(EffectSheets.frames["flo_meter"] ?? 1, 1) : 0
            // In FloState the stroke cycles its colours; else it's the player's glow.
            if floStrokes.indices.contains(index) {
                floStrokes[index].color = player.inFloState
                    ? ZoneTuning.cycle(FloTuning.floStateStroke, at: now, stepSeconds: FloTuning.floStateStrokeStepSeconds)
                    : SKColor(rgb: sprites.look(for: index).glow)
            }
            // Spending it, sparkles at the fill's end a moment after each FLO goes.
            if player.inFloState, let last = floLastSeen[index], player.flo < last { floSpendingUntil[index] = now + FloTuning.sparkleAfterSpendSeconds }
            floLastSeen[index] = player.flo
            if now < floSpendingUntil[index, default: 0], Double.random(in: 0..<1) < FloTuning.sparklesPerSecond * GameScene.stepSeconds {
                sparkleFloBar(index, flo: flo)
            }
            // MAX, steady, while it's full.
            floMaxWords[index].isHidden = flo < FloRules.full || floMeters[index].isHidden
            // Bar A's word goes from its short colours to its own at full, and is lit throughout FloState.
            if floWordsShort.indices.contains(index) {
                let lit = flo >= FloRules.full || player.inFloState
                floWordsShort[index].isHidden = lit
                floWordsFull[index].isHidden = !lit
            }
            guard floShown.indices.contains(index), floShown[index].frame != frame || floShown[index].flo != flo else { continue }
            floShown[index] = (frame, flo)
            floBars[index].texture = floBarTexture(frame: frame, flo: flo)
        }
    }

    /// FLO spent in FloState: tiny sparkles in the energy's colour, twinkling on the fill's end.
    private struct FloSparkle {
        var node: SKSpriteNode
        var age = 0.0
    }
    private var floSparkles: [FloSparkle] = []
    private var floLastSeen: [Int: Int] = [:]
    private var floSpendingUntil: [Int: Double] = [:]
    /// A five-pixel plus, its middle the brightest.
    private lazy var floSparkleTexture: SKTexture = {
        let side = 5
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for pixel in 0..<(side * side) where pixel % side == 2 || pixel / side == 2 {
            let level: UInt8 = pixel == 12 ? 255 : 170
            for channel in 0..<4 { pixels[pixel * 4 + channel] = level }
        }
        let texture = SKTexture(data: Data(pixels), size: CGSize(width: side, height: side))
        texture.filteringMode = .nearest
        return texture
    }()

    /// A sparkle where the bar's fill ends, in the bar's own pixels before its warp: the warp
    /// takes it as it takes the bar.
    private func sparkleFloBar(_ index: Int, flo: Int) {
        guard floBars.indices.contains(index), floBarHolders.indices.contains(index), flo > 0 else { return }
        let bar = floBars[index], holder = floBarHolders[index]
        let width = bar.size.width / GameScene.floPointsPerPixel, height = bar.size.height / GameScene.floPointsPerPixel
        let filled = min(flo, FloRules.full)
        // A's fill ends at its first filled column, B's after its last.
        let column = CGFloat(GameScene.floFirstColumn) + CGFloat(FloTuning.variant == .fillsFromWord ? filled : FloRules.full - filled)
        let row = CGFloat(GameScene.floTopRow) + CGFloat.random(in: 0...5)
        let node = SKSpriteNode(texture: floSparkleTexture)
        node.size = CGSize(width: FloTuning.sparkleSize, height: FloTuning.sparkleSize)
        node.color = SKColor(rgb: sprites.look(for: index).glow)
        node.colorBlendFactor = 1
        node.blendMode = .add
        node.position = CGPoint(x: (column + CGFloat.random(in: -1...1) - width / 2) * GameScene.floPointsPerPixel,
                                y: (height / 2 - row) * GameScene.floPointsPerPixel)
        node.zPosition = 1
        node.setScale(0)
        // Square before the warp, against the holder's squeeze.
        node.userData = ["xScale": 1 / holder.xScale, "yScale": 1 / holder.yScale]
        holder.addChild(node)
        floSparkles.append(FloSparkle(node: node))
    }

    /// Each sparkle a frame on: popping up and back to nothing as it rises a little.
    private func stepFloSparkles() {
        floSparkles = floSparkles.compactMap { sparkle in
            var sparkle = sparkle
            sparkle.age += GameScene.stepSeconds
            guard sparkle.age < FloTuning.sparkleSeconds, sparkle.node.parent != nil else { sparkle.node.removeFromParent(); return nil }
            let pop = CGFloat(sin(sparkle.age / FloTuning.sparkleSeconds * .pi))
            sparkle.node.xScale = pop * (sparkle.node.userData?["xScale"] as? CGFloat ?? 1)
            sparkle.node.yScale = pop * (sparkle.node.userData?["yScale"] as? CGFloat ?? 1)
            sparkle.node.position.y += 0.1
            return sparkle
        }
    }

    /// The stroke round a meter, the bar and the word as one shape: the meter drawn as it
    /// is, warp and all, made white, grown round by the stroke, set behind it and coloured the
    /// player's glow, or cycling in FloState. MAX has its own.
    private func floStroke(round meter: SKNode, colour rgb: RGB) -> SKSpriteNode? {
        let width = FloTuning.stroke
        guard width > 0, let view = hudScene.view else { return nil }
        let maxShown = floMaxWords.map(\.isHidden)
        floMaxWords.forEach { $0.isHidden = true }
        defer { for (word, hidden) in zip(floMaxWords, maxShown) { word.isHidden = hidden } }
        guard let drawn = view.texture(from: meter) else { return nil }
        let frame = meter.calculateAccumulatedFrame()
        let picture = drawn.cgImage()
        let pixels = CGFloat(picture.width) / max(frame.width, 1)
        let reach = (width * pixels).rounded(.up)
        let input = CIImage(cgImage: picture)
        let padded = input.extent.insetBy(dx: -reach, dy: -reach)
        // White wherever it's drawn, then grown.
        let white = input.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ]).applyingFilter("CIPremultiply")
        // Grown round, not square, so a slanted edge comes out smooth rather than stepped.
        let grown = white.composited(over: CIImage(color: .clear).cropped(to: padded))
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: width * pixels])
            .cropped(to: padded)
        guard let outline = ciContext.createCGImage(grown, from: padded) else { return nil }
        let texture = SKTexture(cgImage: outline)
        texture.filteringMode = .nearest
        // Drawn white and coloured on the node, so FloState can cycle it.
        let node = SKSpriteNode(texture: texture)
        node.color = SKColor(rgb: rgb)
        node.colorBlendFactor = 1
        node.size = CGSize(width: frame.width + reach * 2 / pixels, height: frame.height + reach * 2 / pixels)
        node.position = CGPoint(x: frame.midX, y: frame.midY)
        node.zPosition = meter.zPosition - 0.1
        return node
    }

    /// The strokes made once the meters are up and the HUD's view is there to draw them.
    private func strokeFloMeters() {
        guard floStrokes.isEmpty, FloTuning.stroke > 0, hudScene.view != nil, let first = floMeters.first, !first.isHidden else { return }
        for (index, meter) in floMeters.enumerated() {
            guard let stroke = floStroke(round: meter, colour: sprites.look(for: index).glow) else { continue }
            hud.addChild(stroke)
            floStrokes.append(stroke)
        }
    }

    private func layoutFloMeters() {
        floStrokes.forEach { $0.removeFromParent() }
        floStrokes = []
        floMeters.forEach { $0.removeFromParent() }
        floMeters = []
        floBars = []
        floBarHolders = []
        floMaxWords = []
        floWordsShort = []
        floWordsFull = []
        floShown = []
        guard (EffectSheets.frames["flo_meter"] ?? 0) > 0 else { return }
        let barA = FloTuning.variant == .emptiesFromWord
        for index in 0..<2 {
            // The second player's mirrored: the bar against the scoreboard, the word outside it.
            let mirrored = index == 1
            let bar = SKSpriteNode(texture: floBarTexture(frame: 0, flo: shownFlo(index)))
            bar.size = CGSize(width: bar.size.width * GameScene.floPointsPerPixel, height: bar.size.height * GameScene.floPointsPerPixel)
            // The meter: a holder at the whole meter's scale, the bar and the word each at their own.
            let side: CGFloat = index == 0 ? -1 : 1
            let meter = SKSpriteNode()
            let barWidth = bar.size.width * FloTuning.barScale * FloTuning.xScale, barHeight = bar.size.height * FloTuning.barScale * FloTuning.yScale
            // Either side of the scoreboard, level with it.
            meter.position = CGPoint(x: side * (scorePlateHalfWidth + GameScene.floGap + barWidth * FloTuning.meterScale / 2),
                                     y: circles.position.y - UIPiece.plateBlack.faceRise * UITuning.shared.scale(.hud, .panels) * 0.5 + FloTuning.meterY)
            meter.zPosition = 6
            // The bar in a warped holder, squeezed and mirrored there, so its sparkles warp with it.
            let holder = SKEffectNode()
            holder.shouldEnableEffects = true
            holder.xScale = FloTuning.barScale * FloTuning.xScale * (mirrored ? -1 : 1)
            holder.yScale = FloTuning.barScale * FloTuning.yScale
            holder.warpGeometry = Onomatopoeia.skew(left: FloTuning.barFront, right: FloTuning.barBack, bend: FloTuning.barBend, columns: 16)
            holder.addChild(bar)
            meter.addChild(holder)
            // The word skewed the same on both: only its place mirrors. Bar A's is in its short
            // colours until full.
            var words: [SKSpriteNode] = []
            for colours in barA ? [FloTuning.shortColours, FloTuning.colours] : [FloTuning.colours] {
                let word = Onomatopoeia.still("FLO", face: .englishDex, colours: colours, height: GameScene.floWordHeight, growsLeft: true,
                                              left: FloTuning.leftSkew, right: FloTuning.rightSkew)
                // Its small end on the bar's outer end, then moved, mirrored for the second.
                word.anchorPoint = CGPoint(x: mirrored ? 0 : 1, y: 0.5)
                word.position = CGPoint(x: side * (barWidth / 2 - GameScene.floWordOverlap - FloTuning.offsetX), y: GameScene.floWordLift + FloTuning.offsetY)
                word.setScale(FloTuning.wordScale)
                word.zPosition = 1
                meter.addChild(word)
                words.append(word)
            }
            if barA {
                floWordsShort.append(words[0])
                floWordsFull.append(words[1])
            }
            // MAX, lettered as a footstep is, in Bigdex: bar A's on the word's top outer corner,
            // on its sliders; bar B's on the bar's top trailing corner, against the scoreboard.
            let full = Onomatopoeia.still("MAX", face: .englishDex, colours: FloTuning.colours, height: GameScene.floMaxHeight, growsLeft: false,
                                          left: 1, right: 1)
            full.anchorPoint = CGPoint(x: 0.5, y: 0)
            if barA {
                // Centred on the corner, kept under the screen's top edge, which the meters sit just
                // below; then moved by the sliders, unclamped.
                full.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                full.setScale(FloTuning.cornerMaxScale)
                let wordFrame = words[0].frame
                let screenTop = (circles.position.y + GameScene.scoreboardBelowTop - meter.position.y) / FloTuning.meterScale
                full.position = CGPoint(x: (mirrored ? wordFrame.maxX : wordFrame.minX) - side * FloTuning.cornerMaxX,
                                        y: min(wordFrame.maxY, screenTop - full.frame.height / 2) + FloTuning.cornerMaxY)
            } else {
                full.position = CGPoint(x: -side * (barWidth / 2 + FloTuning.maxX), y: barHeight / 2 + FloTuning.maxY)
                full.setScale(FloTuning.maxScale)
            }
            full.zPosition = 2
            full.isHidden = shownFlo(index) < FloRules.full
            meter.addChild(full)
            meter.setScale(FloTuning.meterScale)
            hud.addChild(meter)
            floMeters.append(meter)
            floBars.append(bar)
            floBarHolders.append(holder)
            floMaxWords.append(full)
            floShown.append((0, shownFlo(index)))
        }
        showFloMeters()
    }

    // MARK: FLO's orbs

    /// FLO earned comes as orbs, as silk does off the Reaper crest: out of where it was earned
    /// they glide to a place round it and hang there a moment, bobbing, then zip to the player on
    /// a bent path, faster as they go, trailing; each one landing flashes the player their
    /// energy's colour, plays `flo_absorb` on them, and puts its share on their meter. Spheres,
    /// lit, drawn by the Metal layer and glowing.
    private struct FloOrb {
        var owner: Int
        var value: Double
        var source: CGPoint
        var hang: CGPoint
        var position: CGPoint
        var age = 0.0
        var hangSeconds: Double
        var zipFrom: CGPoint?
        var zipAge = 0.0
        var zipSeconds: Double
        /// How far the zip's path bows out, and which way.
        var bend: CGFloat
        /// Where round its circle it starts hovering, and which way it goes round.
        var spin: Double = .random(in: 0..<(2 * .pi))
        var turn: Double = Bool.random() ? 1 : -1
        var trail: [CGPoint] = []
    }
    private var floOrbs: [FloOrb] = []
    /// FLO still on its way to each player in orbs, kept off their meter till it lands.
    private var floOnTheWay: [Int: Double] = [:]
    /// Frames left of each player's flash on taking an orb.
    private var floFlash: [Int] = [0, 0]
    private static let floPerOrb = 1.0
    private static let floGlideSeconds = 0.3
    /// How long the first of a gain's orbs hangs, and how long after the one before each next
    /// one leaves, give or take a little: one by one, never together, after any still waiting.
    private static let floHangSeconds = 0.45
    private static let floZipGap = 0.12
    private static let floZipJitter = 0.05
    private static let floZipSeconds: ClosedRange<Double> = 0.3...0.45
    private static let floHangRadius: ClosedRange<CGFloat> = 12...24
    private static let floBend: ClosedRange<CGFloat> = 20...50
    private static let floOrbSize: Float = 5
    private static let floTrailLength = 8
    private static let floFlashFrames = 8
    /// Hovering, a circle this wide, round in this long.
    private static let floCircleRadius: CGFloat = 2
    private static let floCircleSeconds = 0.8

    private func spawnFloOrbs(for player: Int, amount: Int, at source: Vec2) {
        let count = max(Int((Double(amount) / GameScene.floPerOrb).rounded(.up)), 1)
        let from = SpriteLibrary.point(source)
        // After the last of this player's orbs still waiting to leave.
        let waiting = floOrbs.filter { $0.owner == player && $0.zipFrom == nil }.map { $0.hangSeconds - $0.age }.max()
        var leaves = max(GameScene.floHangSeconds, (waiting ?? 0) + GameScene.floZipGap)
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0..<(2 * .pi)), reach = CGFloat.random(in: GameScene.floHangRadius)
            floOrbs.append(FloOrb(owner: player, value: Double(amount) / Double(count), source: from,
                                  hang: CGPoint(x: from.x + cos(angle) * reach, y: from.y + sin(angle) * reach), position: from,
                                  hangSeconds: leaves, zipSeconds: .random(in: GameScene.floZipSeconds),
                                  bend: (Bool.random() ? 1 : -1) * .random(in: GameScene.floBend)))
            leaves += GameScene.floZipGap + .random(in: 0...GameScene.floZipJitter)
        }
        floOnTheWay[player, default: 0] += Double(amount)
    }

    /// The orbs a frame on, and those that have landed taken in.
    private func stepFloOrbs() {
        let step = GameScene.stepSeconds
        floOrbs = floOrbs.compactMap { orb in
            var orb = orb
            guard match.players.indices.contains(orb.owner) else { return nil }
            orb.age += step
            orb.trail.insert(orb.position, at: 0)
            if orb.trail.count > GameScene.floTrailLength { orb.trail.removeLast() }
            if orb.age < GameScene.floGlideSeconds {
                // Out to its place, slowing as it gets there.
                let t = 1 - pow(1 - orb.age / GameScene.floGlideSeconds, 3)
                orb.position = CGPoint(x: orb.source.x + (orb.hang.x - orb.source.x) * t, y: orb.source.y + (orb.hang.y - orb.source.y) * t)
            } else if orb.age < orb.hangSeconds {
                // Round and round a tight circle on its place.
                let angle = orb.spin + orb.turn * (orb.age - GameScene.floGlideSeconds) * 2 * .pi / GameScene.floCircleSeconds
                orb.position = CGPoint(x: orb.hang.x + GameScene.floCircleRadius * CGFloat(cos(angle)) - GameScene.floCircleRadius * CGFloat(cos(orb.spin)),
                                       y: orb.hang.y + GameScene.floCircleRadius * CGFloat(sin(angle)) - GameScene.floCircleRadius * CGFloat(sin(orb.spin)))
            } else {
                // The zip: a bowed path to the player as they are now, quickening.
                let from = orb.zipFrom ?? orb.position
                orb.zipFrom = from
                orb.zipAge += step
                let target = SpriteLibrary.point(match.players[orb.owner].chest)
                let t = min(orb.zipAge / orb.zipSeconds, 1)
                let eased = CGFloat(t * t)
                let middle = CGPoint(x: (from.x + target.x) / 2, y: (from.y + target.y) / 2)
                let across = CGPoint(x: target.x - from.x, y: target.y - from.y)
                let length = max(hypot(across.x, across.y), 1)
                let control = CGPoint(x: middle.x - across.y / length * orb.bend, y: middle.y + across.x / length * orb.bend)
                func mix(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat) -> CGFloat {
                    (1 - eased) * (1 - eased) * a + 2 * (1 - eased) * eased * b + eased * eased * c
                }
                orb.position = CGPoint(x: mix(from.x, control.x, target.x), y: mix(from.y, control.y, target.y))
                if t >= 1 {
                    takeFloOrb(orb)
                    return nil
                }
            }
            return orb
        }
    }

    private func takeFloOrb(_ orb: FloOrb) {
        floOnTheWay[orb.owner] = max(floOnTheWay[orb.owner, default: 0] - orb.value, 0)
        if floFlash.indices.contains(orb.owner) { floFlash[orb.owner] = GameScene.floFlashFrames }
    }

    /// Dropped FLO where a body burned, hovering: `flo_absorb` round and round on it, in the
    /// colour of whoever dropped it, till someone takes it.
    private var floBundleNodes: [Int: SKSpriteNode] = [:]
    private func drawFloBundles() {
        let bundles = match.floBundles
        for (id, node) in floBundleNodes where !bundles.contains(where: { $0.id == id }) {
            node.removeFromParent()
            floBundleNodes[id] = nil
        }
        guard EnergyEffect.floAbsorb.frameCount > 0 else { return }
        for bundle in bundles where floBundleNodes[bundle.id] == nil {
            let frames = sprites.effectFrames(.floAbsorb, player: bundle.owner)
            let node = SKSpriteNode(texture: frames[0])
            node.position = SpriteLibrary.point(bundle.position)
            node.zPosition = 30
            node.run(.repeatForever(.animate(with: frames, timePerFrame: 1 / EnergyEffect.floAbsorb.fps)))
            glowers.addChild(node)
            floBundleNodes[bundle.id] = node
        }
    }

    /// The orbs and their trails as spheres, in their player's glow lightened a little.
    var sphereInstances: [CubeInstance] {
        floOrbs.flatMap { orb -> [CubeInstance] in
            let glow = sprites.look(for: orb.owner).glow
            let colour = SIMD4<Float>(Float((glow >> 16) & 0xFF) / 255, Float((glow >> 8) & 0xFF) / 255, Float(glow & 0xFF) / 255, 1)
            let bright = colour + (SIMD4<Float>(1, 1, 1, 1) - colour) * 0.35
            func sphere(_ at: CGPoint, size: Float, alpha: Float) -> CubeInstance {
                var shade = bright
                shade.w = alpha
                return CubeInstance(model: .translation(SIMD3<Float>(Float(at.x), Float(at.y), 0)) * .scale(SIMD3<Float>(repeating: size)), color: shade)
            }
            let trail = orb.trail.enumerated().map { index, at in
                let share = 1 - Float(index + 1) / Float(GameScene.floTrailLength + 1)
                return sphere(at, size: GameScene.floOrbSize * (0.3 + 0.6 * share), alpha: 0.75 * share)
            }
            return trail.reversed() + [sphere(orb.position, size: GameScene.floOrbSize, alpha: 1)]
        }
    }

    private func showFloMeters() {
        for meter in floMeters + floStrokes { meter.isHidden = flow != .playing }
        floShown = floShown.map { _ in (-1, -1) }
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

    /// The Elements' placed tiles, while it's the stage drawn; Wetshot Wake's props likewise.
    private var elementsArt: ElementsArt.Handles?
    private var flightArt: FlightArt.Handles?
    private var wetshotArt: WetshotArt.Handles?
    private let tornadoOverlays = SKCropNode()

    /// What the stage draws that must not glow, its tiles, its mountains and its icicles, with
    /// a version for the glow's mask to redo them only when they change. The lava glows.
    private(set) var staticFlats: [BodySnapshot] = []
    private(set) var staticFlatsVersion = 0

    private func refreshStaticFlats() {
        var flats: [BodySnapshot] = []
        if let art = elementsArt {
            let nodes = ([art.mountains].compactMap { $0 }) + art.spareFills + art.shaftWalls + Array(art.tiles.values)
            flats = nodes.compactMap { node in
                node.texture.map { BodySnapshot(texture: $0, position: node.position, anchor: node.anchorPoint, xScale: 1, size: node.size) }
            }
        }
        if let art = wetshotArt { flats += art.flats }
        // Flight's tiles are painted, not lit: none of them glows.
        if let art = flightArt {
            flats += (Array(art.tiles.values) + [art.backdrop].compactMap { $0 }).compactMap { node in
                node.texture.map { BodySnapshot(texture: $0, position: node.position, anchor: node.anchorPoint, xScale: 1, size: node.size) }
            }
        }
        staticFlats = flats
        staticFlatsVersion += 1
    }

    private func buildStage() {
        // The floor and walls take the holder's colour, the backboard blocks keep their rim's
        // owner's, and the ledge is magenta.
        let stage = match.stage
        let isElements = stage.features.look == .elements
        Ambience.shared.play(isElements ? "thunderstorm" : nil)
        let isWetshot = stage.features.look == .wetshot
        backgroundColor = isElements ? SKColor(rgb: ElementsArt.background) : (isWetshot ? SKColor(rgb: WetshotArt.waterTop)
            : (stage.features.look == .flight ? SKColor(rgb: PixelPalette.colours[0]) : GameScene.background))
        elementsArt = nil
        wetshotArt = nil
        flightArt = nil
        fallingIcicles = [:]
        hangingIcicles = [:]
        // The Elements' tornados over the players live outside the stage's ground: gone with any other stage.
        tornadoOverlays.removeAllChildren()
        if isWetshot {
            wetshotArt = WetshotArt.build(stage: stage, map: StageMap.current[.wetshot], into: stageGround)
        }
        if stage.features.look == .flight {
            flightArt = FlightArt.build(map: StageMap.current[.flight], into: stageGround)
        }
        if isElements {
            elementsArt = ElementsArt.build(stage: stage, map: StageMap.current[.elements], into: stageGround, overlayParent: tornadoOverlays, sprites: sprites)
        }
        refreshStaticFlats()
        findRainSplashSpots()
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
            if GoalpostTuning.sceneryHidden {
                // Everything above the turf under flat black, over the scenery, under the turf's lines.
                let cover = SKSpriteNode(texture: sprites.flatSquare(size: 4, alpha: 1))
                cover.anchorPoint = .zero
                cover.position = CGPoint(x: -400, y: FieldArt.turfTop)
                cover.size = CGSize(width: CGFloat(stage.columns) * GameScene.pixelsPerTile + 800, height: 2000)
                cover.color = SKColor(rgb: PixelPalette.outline)
                cover.colorBlendFactor = 1
                cover.zPosition = -12.5
                stageGround.addChild(cover)
            }
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
        for row in 0..<(stage.rows + Stage.skyRows) where !stage.features.scenic && !isElements {
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
        // The line stays put; Wetshot Wake's rim swims, so it has none drawn.
        threePointArcs.isHidden = gameMode != .fortySeven || stage.features.look == .wetshot
        let inside = CGRect(x: GameScene.pixelsPerTile, y: GameScene.pixelsPerTile,
                            width: CGFloat(stage.columns - 2) * GameScene.pixelsPerTile,
                            height: CGFloat(stage.rows + Stage.skyRows) * GameScene.pixelsPerTile)
        let mask = SKSpriteNode(color: .white, size: inside.size)
        mask.anchorPoint = .zero
        mask.position = inside.origin
        threePointArcs.maskNode = mask
        stageGlowers.addChild(threePointArcs)
        // Under the floor's row, the outline black, all the way down and out.
        if !stage.features.scenic && !isElements {
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
            let art = HoopTuning.art(for: stage.features.look)
            let backboard = SKSpriteNode(texture: sprites.texture(art.backboard, 0))
            backboard.position = GameScene.hoopArtPoint(for: hoop, on: stage.features.look)
            backboard.zPosition = 5
            backboard.xScale = hoop.backboard == .left ? -1 : 1
            // Wetshot Wake's rim rides the Hoopfish, with no backboard.
            backboard.isHidden = stage.features.look == .wetshot
            stageGround.addChild(backboard)
            backboardNodes.append(backboard)
            if stage.features.look == .court {
                let support = SKSpriteNode()
                support.zPosition = 4.9
                stageGround.addChild(support)
                supportNodes.append(support)
            }
            let rim = SKSpriteNode(texture: sprites.texture(art.rim, 0))
            rim.position = GameScene.hoopArtPoint(for: hoop, on: stage.features.look)
            rim.xScale = hoop.backboard == .left ? -1 : 1
            rim.zPosition = 6
            stageGround.addChild(rim)
            rimNodes.append(rim)
            // A straight rim's front lip again over the ball, so the ball goes down through it.
            let front = SKSpriteNode(texture: art.rim == "hoop_straight" ? frontLip(of: sprites.texture(art.rim, 0)) : nil)
            front.zPosition = GameScene.rimFrontZ
            front.isHidden = front.texture == nil
            glowers.addChild(front)
            rimFronts.append(front)
            rimFlash.append(0)
            rimJitter.append(0)
            boardJitter.append(0)
            rimDip.append(0)
            rimSpin.append(0)
            nets.append(HoopNet(at: GameScene.netPoint(for: hoop, on: stage.features.look), mirrored: hoop.backboard == .left, colour: SKColor(rgb: sprites.look(for: 1 - hoop.owner).glow),
                                into: stageGround, depth: 5.5))
        }
        refreshSupports(HoopSupport.pieces)
        warmDrawnArt()
    }

    /// The supports' picture again, for a layout.
    private func refreshSupports(_ pieces: [HoopSupport.Piece]) {
        let assembled = HoopSupport.assembled(pieces)
        for node in supportNodes {
            node.isHidden = assembled == nil
            guard let assembled else { continue }
            node.texture = assembled.texture
            node.xScale = 1
            node.size = assembled.size
            node.anchorPoint = assembled.anchor
        }
    }

    /// The world redrawn for the series' stage, if it isn't the one drawn.
    private func showStage() {
        guard built, series.stage != builtStage else { return }
        closeMapEditor()
        closeSupportBuilder()
        redrawStage()
    }

    /// The world drawn again from the match's stage, everything for it taken away first.
    private func redrawStage() {
        stageGround.removeAllChildren()
        stageGlowers.removeAllChildren()
        courtTiles = []
        blockTiles = []
        threePointArcSides = []
        backboardNodes = []
        supportNodes = []
        rimNodes = []
        rimFronts.forEach { $0.removeFromParent() }
        rimFronts = []
        rimFlash = []
        rimJitter = []
        boardJitter = []
        rimDip = []
        rimSpin = []
        nets = []
        elementsArt = nil
        wetshotArt = nil
        flightArt = nil
        fallingIcicles = [:]
        hangingIcicles = [:]
        fieldBlooms = []
        lightPanels = []
        yardNumbers = []
        railCalls = []
        railChevrons = []
        railChevronHomes = []
        helmetNodes = [:]
        carNodes = [:]
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
        layout(displayScale: displayScale)
    }

    /// A soft glow in the colour, added, which the glow pass then picks up.
    // MARK: The Elements' lava, fireball and wind

    /// Into the lava: the lava's splash over a sizzle, either, over an explosion, and the fire's
    /// hit, at half size, a quarter for the ball; burned in a fire tornado, the same but the splash.
    private func splashLava(at position: Vec2, ball: Bool, splash: Bool = true, only: String? = nil) {
        if only == nil { play(.fireHit, at: position) }
        let scale: CGFloat = ball ? 0.25 : 0.5
        var layers: [(sheet: String, fps: Double, z: CGFloat)] = [
            ("explosion", 24, 40), (Bool.random() ? "sizzle1" : "sizzle2", 15, 41),
        ]
        if splash { layers.append(("lava_splash", 15, 42)) }
        if let only { layers = layers.filter { $0.sheet == only } }
        for layer in layers {
            guard let count = EffectSheets.frames[layer.sheet] else { continue }
            let frames = (0..<count).map { sprites.texture(layer.sheet, $0) }
            let node = SKSpriteNode(texture: frames[0])
            node.anchorPoint = CGPoint(x: 0.5, y: EffectSheets.anchorY[layer.sheet] ?? 0.5)
            node.position = SpriteLibrary.point(position)
            // The splash twice the others' size.
            node.setScale(layer.sheet == "lava_splash" ? scale * 2 : scale)
            node.zPosition = layer.z
            node.run(.sequence([.animate(with: frames, timePerFrame: 1 / layer.fps), .removeFromParent()]))
            glowers.addChild(node)
        }
    }

    /// The Elements' fireball where the sim has it, its four frames at fifteen a second, facing its way.
    private var stageFireballNode: SKSpriteNode?
    private var stageFireballLast: Vec2?
    private static let stageFireballFramesPerSecond = 15
    private func placeStageFireball() {
        // Only above the lava; coming out of it and going under, it splashes.
        let surface = Double(ElementsArt.lavaSurfaceLine) / SpriteLibrary.pixelsPerUnit
        let fireball = match.stageFireball
        if let was = stageFireballLast, let now = fireball?.position, (was.y >= surface) != (now.y >= surface) {
            splashLava(at: Vec2(x: now.x, y: surface), ball: false, splash: true, only: "lava_splash")
        }
        stageFireballLast = fireball?.position
        guard let fireball, fireball.position.y >= surface else {
            stageFireballNode?.isHidden = true
            return
        }
        let node = stageFireballNode ?? {
            let made = SKSpriteNode(texture: sprites.texture("fireball", 0))
            made.zPosition = 7
            glowers.addChild(made)
            stageFireballNode = made
            return made
        }()
        node.isHidden = false
        node.texture = sprites.texture("fireball", (match.frame * GameScene.stageFireballFramesPerSecond / 60) % (EffectSheets.frames["fireball"] ?? 1))
        node.size = node.texture?.size() ?? .zero
        node.position = SpriteLibrary.point(fireball.position)
        // Drawn pointing right: turned to where it's going next.
        let ahead = match.stageFireball(at: match.frame + 1)?.position ?? fireball.position + Vec2(x: fireball.heading.sign, y: 0)
        let way = ahead - fireball.position
        node.zRotation = CGFloat(atan2(way.y, way.x))
    }

    /// The Elements' wind: puffs of `wind` behind the stage's rock and in front of everything, each
    /// at 1, 0.75, 0.5 or 0.25, starting anywhere on screen and blowing leftward as it plays through
    /// at ten a second, fading out.
    private var windPuffs: (back: [SKSpriteNode], front: [SKSpriteNode]) = ([], [])
    private var windClock = 0.0
    private static let windSecondsBetween = 0.35
    private static let windFramesPerSecond = 10.0
    private static let windTravel: ClosedRange<CGFloat> = 64...160
    private func blowWind() {
        windPuffs.back.removeAll { $0.parent == nil }
        windPuffs.front.removeAll { $0.parent == nil }
        guard match.stage.features.look == .elements, let count = EffectSheets.frames["wind"] else { return }
        windClock += GameScene.stepSeconds
        guard windClock >= GameScene.windSecondsBetween else { return }
        windClock = 0
        let frames = (0..<count).map { sprites.texture("wind", $0) }
        let seconds = Double(count) / GameScene.windFramesPerSecond
        let halfWidth = size.width * cameraNode.xScale / 2, halfHeight = size.height * cameraNode.yScale / 2
        for front in [false, true] {
            let puff = SKSpriteNode(texture: frames[0])
            puff.position = CGPoint(x: cameraNode.position.x + .random(in: -halfWidth...halfWidth),
                                    y: cameraNode.position.y + .random(in: -halfHeight...halfHeight))
            puff.alpha = [1, 0.75, 0.5].randomElement()!
            puff.run(.sequence([
                .group([.animate(with: frames, timePerFrame: 1 / GameScene.windFramesPerSecond),
                        .moveBy(x: -.random(in: GameScene.windTravel), y: 0, duration: seconds),
                        .fadeOut(withDuration: seconds)]),
                .removeFromParent(),
            ]))
            if front {
                puff.zPosition = 23
                world.addChild(puff)
                windPuffs.front.append(puff)
            } else {
                puff.zPosition = -8.5
                stageGround.addChild(puff)
                windPuffs.back.append(puff)
            }
        }
    }

    /// The Elements' rain: streaks 2 to 5 pixels long at 45 degrees, falling from the top right
    /// to the bottom left, in palette 48 or 22 at any strength. Thousands of them, but drawn as
    /// two textures made once, each a tile repeated over the screen and slid along: a near layer
    /// and a far one, slower. Over everything in the world, under the HUD.
    private let rainLayer = SKCropNode()
    private var rainTiles: [[SKSpriteNode]] = [[], []]
    private static let rainTileSide = 256
    private static let rainSpeeds: [CGFloat] = [240, 360]
    private static let rainStreaksPerTile = [260, 200]
    private static var rainTextures: [SKTexture] = makeRainTextures()
    private static func makeRainTextures() -> [SKTexture] {
        rainStreaksPerTile.map { GameScene.makeRainTexture(streaks: Int((Double($0) * RainTuning.density).rounded())) }
    }

    private static func makeRainTexture(streaks: Int) -> SKTexture {
        let side = rainTileSide
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            for _ in 0..<streaks {
                let colour = SKColor(rgb: PixelPalette.colours[Bool.random() ? 48 : 22])
                colour.withAlphaComponent(.random(in: 0.2...1)).setFill()
                let x = Int.random(in: 0..<side), y = Int.random(in: 0..<side)
                let length = Int.random(in: 2...5)
                // Down and to the left, one pixel each, the tile's edges wrapping so it repeats.
                for step in 0..<length {
                    context.fill(CGRect(x: (x - step + side) % side, y: (y + step) % side, width: 1, height: 1))
                }
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return texture
    }

    private func fallRain() {
        let raining = match.stage.features.look == .elements
        rainLayer.isHidden = !raining
        guard raining else { return }
        let side = CGFloat(GameScene.rainTileSide)
        let halfWidth = size.width * cameraNode.xScale / 2, halfHeight = size.height * cameraNode.yScale / 2
        let left = cameraNode.position.x - halfWidth, bottom = cameraNode.position.y - halfHeight
        let across = Int((halfWidth * 2 / side).rounded(.up)) + 1, up = Int((halfHeight * 2 / side).rounded(.up)) + 1
        for layer in 0..<2 {
            while rainTiles[layer].count < across * up {
                let tile = SKSpriteNode(texture: GameScene.rainTextures[layer])
                tile.anchorPoint = .zero
                tile.size = CGSize(width: side, height: side)
                tile.zPosition = CGFloat(layer)
                rainLayer.addChild(tile)
                rainTiles[layer].append(tile)
            }
            // Slid down and left, whole pixels, wrapping every tile.
            let travel = (CGFloat(CACurrentMediaTime()) * GameScene.rainSpeeds[layer]).truncatingRemainder(dividingBy: side)
            let originX = ((left + travel) / side).rounded(.down) * side - travel
            let originY = ((bottom + travel) / side).rounded(.down) * side - travel
            for (index, tile) in rainTiles[layer].enumerated() {
                tile.isHidden = index >= across * up
                tile.position = CGPoint(x: (originX + CGFloat(index % across) * side).rounded(), y: (originY + CGFloat(index / across) * side).rounded())
            }
        }
    }

    /// Where rain splashes on the Elements: along every open top of rock, and up the left side's
    /// slopes, turned to lie on them; not the right side's.
    private var rainSplashSpots: [(x: ClosedRange<CGFloat>, y: (CGFloat) -> CGFloat, turn: CGFloat)] = []
    private var rainSplashes: [SKSpriteNode] = []
    private static let rainSplashesPerSecond = 24.0
    private static let rainSplashScale: CGFloat = 0.5

    private func findRainSplashSpots() {
        rainSplashSpots = []
        guard match.stage.features.look == .elements else { return }
        let map = StageMap.current[.elements], tile = ElementsArt.tileSide, stage = match.stage
        for wall in map.walls where wall.cell.row < stage.rows - 1 {
            let above = map.wall(at: .init(wall.cell.column, wall.cell.row + 1))
            let x = CGFloat(wall.cell.column) * tile, top = CGFloat(wall.cell.row + 1) * tile, bottom = CGFloat(wall.cell.row) * tile
            switch wall.kind {
            case .solid where above == nil:
                rainSplashSpots.append((x...(x + tile), { _ in top }, 0))
            case .lowerLeft, .slideLowerLeft where x < CGFloat(stage.columns) * tile / 2:
                rainSplashSpots.append((x...(x + tile), { at in bottom + (x + tile - at) }, -.pi / 4))
            case .lowerRight, .slideLowerRight where x < CGFloat(stage.columns) * tile / 2:
                rainSplashSpots.append((x...(x + tile), { at in bottom + (at - x) }, .pi / 4))
            default:
                break
            }
        }
    }

    /// Where the rain meets the lava it sizzles, small, here and there along its top on screen.
    private var rainSizzles: [SKSpriteNode] = []
    private static let rainSizzleScale: CGFloat = 0.25
    private static let rainSizzlesPerSecond = 20.0
    /// The FloState lockout's sizzles off the body: way down in size, two thirds seen.
    private static let lockoutSizzlesPerSecond = 12.0
    private static let lockoutSizzleScale: CGFloat = 0.1
    private static let lockoutSizzleAlpha: CGFloat = 0.66
    private func sizzle(at point: CGPoint, on body: SKNode) {
        let sheet = Bool.random() ? "sizzle1" : "sizzle2"
        guard let count = EffectSheets.frames[sheet] else { return }
        let frames = (0..<count).map { sprites.texture(sheet, $0) }
        let sizzle = SKSpriteNode(texture: frames[0])
        sizzle.anchorPoint = CGPoint(x: 0.5, y: EffectSheets.anchorY[sheet] ?? 0.5)
        sizzle.position = point
        sizzle.setScale(GameScene.lockoutSizzleScale)
        sizzle.alpha = GameScene.lockoutSizzleAlpha
        sizzle.zPosition = 0.095
        sizzle.run(.sequence([.animate(with: frames, timePerFrame: 1.0 / 15), .removeFromParent()]))
        body.addChild(sizzle)
    }

    private func sizzleRain() {
        rainSizzles.removeAll { $0.parent == nil }
        guard match.stage.features.look == .elements, RainTuning.density > 0,
              Double.random(in: 0..<1) < GameScene.rainSizzlesPerSecond * GameScene.stepSeconds else { return }
        let sheet = Bool.random() ? "sizzle1" : "sizzle2"
        guard let count = EffectSheets.frames[sheet] else { return }
        let halfWidth = size.width * cameraNode.xScale / 2
        let frames = (0..<count).map { sprites.texture(sheet, $0) }
        let sizzle = SKSpriteNode(texture: frames[0])
        sizzle.anchorPoint = CGPoint(x: 0.5, y: EffectSheets.anchorY[sheet] ?? 0.5)
        sizzle.position = CGPoint(x: cameraNode.position.x + .random(in: -halfWidth...halfWidth), y: ElementsArt.lavaSurfaceLine)
        sizzle.setScale(GameScene.rainSizzleScale)
        sizzle.zPosition = -7
        sizzle.run(.sequence([.animate(with: frames, timePerFrame: 1.0 / 15), .removeFromParent()]))
        stageGround.addChild(sizzle)
        rainSizzles.append(sizzle)
    }

    /// The Elements' lightning: the sky flashes, a column of dots floats up from where it'll
    /// strike, and two seconds on the bolt comes down there.
    private var lightningDots: [SKSpriteNode] = []
    private var lightningBolts: [SKSpriteNode] = []
    private var lightningFlash: SKSpriteNode?
    private static let lightningFlashAlpha: CGFloat = 0.6
    private static let lightningFlashSeconds = 0.3
    private static let lightningDotsPerSecond = 14.0
    private static let lightningDotRise: CGFloat = 16
    private static let lightningDotSeconds = 1.2

    private func flashLightning() {
        let flash = SKSpriteNode(texture: sprites.flatSquare(size: 16, alpha: 1))
        flash.color = .white
        flash.colorBlendFactor = 1
        flash.anchorPoint = .zero
        flash.size = CGSize(width: size.width * cameraNode.xScale, height: size.height * cameraNode.yScale)
        flash.position = cameraNode.position - CGPoint(x: flash.size.width / 2, y: flash.size.height / 2)
        flash.alpha = GameScene.lightningFlashAlpha
        flash.zPosition = 89
        flash.run(.sequence([.fadeOut(withDuration: GameScene.lightningFlashSeconds), .removeFromParent()]))
        world.addChild(flash)
        lightningFlash = flash
    }

    private func riseLightningDots() {
        lightningDots.removeAll { $0.parent == nil }
        lightningBolts.removeAll { $0.parent == nil }
        guard let warning = match.lightningWarning,
              Double.random(in: 0..<1) < GameScene.lightningDotsPerSecond * GameScene.stepSeconds else { return }
        let base = SpriteLibrary.point(warning.target)
        let dot = SKSpriteNode(texture: sprites.flatSquare(size: 4, alpha: 1))
        dot.color = SKColor(rgb: PixelPalette.colours[22])
        dot.colorBlendFactor = 1
        dot.size = CGSize(width: 1, height: 1)
        dot.anchorPoint = .zero
        dot.position = CGPoint(x: base.x + CGFloat(Int.random(in: -1...0)), y: base.y + CGFloat(Int.random(in: 0...6)))
        dot.zPosition = 24
        dot.run(.sequence([.group([.moveBy(x: 0, y: GameScene.lightningDotRise, duration: GameScene.lightningDotSeconds),
                                   .fadeOut(withDuration: GameScene.lightningDotSeconds)]), .removeFromParent()]))
        world.addChild(dot)
        lightningDots.append(dot)
    }

    private func strikeLightning(at target: Vec2) {
        guard let count = EffectSheets.frames["small_lightning"] else { return }
        let frames = (0..<count).map { sprites.texture("small_lightning", $0) }
        let bolt = SKSpriteNode(texture: frames[0])
        // Drawn standing on its frame's bottom.
        bolt.anchorPoint = CGPoint(x: 0.5, y: 0)
        bolt.position = SpriteLibrary.point(target)
        bolt.zPosition = 24
        bolt.run(.sequence([.animate(with: frames, timePerFrame: 1.0 / 15), .removeFromParent()]))
        world.addChild(bolt)
        lightningBolts.append(bolt)
    }

    /// The Elements' icicles as the sim has them: each socket empty or growing (`icicle_form`),
    /// then, grown, the empty socket with `icicle`'s first frame hanging behind it, wiggling about
    /// its top middle for a moment before it drops; each dropped one falling, and where one
    /// shatters the rest of `icicle` plays.
    private var fallingIcicles: [Int: SKSpriteNode] = [:]
    private var hangingIcicles: [Int: SKSpriteNode] = [:]
    /// The wiggle before the drop: how long, how far either way, and how quick.
    private static let icicleWiggleFrames = 40
    private static let icicleWiggleDegrees: CGFloat = 6
    private static let icicleWiggleSwingFrames = 6.0
    private var shatteringIcicles: [SKSpriteNode] = []
    private static let icicleFramesPerSecond = 15

    private func placeIcicles() {
        shatteringIcicles.removeAll { $0.parent == nil }
        guard let art = elementsArt, let formCount = EffectSheets.frames["icicle_form"] else { return }
        let empty = sprites.texture("icicle_empty", 0)
        for (index, socket) in art.icicles.enumerated() where index < match.icicles.count {
            let icicle = match.icicles[index]
            let formFrame = icicle.formedAt.map { (match.frame - $0) * GameScene.icicleFramesPerSecond / 60 }
            let grown = formFrame.map { $0 >= formCount - 1 } ?? false
            socket.texture = formFrame.map { grown ? empty : sprites.texture("icicle_form", $0) } ?? empty
            if grown, let tip = match.stage.icicleSockets.indices.contains(index) ? match.stage.icicleSockets[index] : nil {
                let hanging = hangingIcicles[index] ?? {
                    let made = SKSpriteNode(texture: sprites.texture("icicle", 0))
                    // Turned about its top middle, where it hangs from.
                    made.anchorPoint = CGPoint(x: 0.5, y: 1)
                    made.zPosition = socket.zPosition - 0.1
                    stageGround.addChild(made)
                    hangingIcicles[index] = made
                    return made
                }()
                let top = SpriteLibrary.point(tip)
                hanging.position = CGPoint(x: top.x, y: top.y + hanging.size.height)
                let left = icicle.dropAt - match.frame
                hanging.zRotation = left <= GameScene.icicleWiggleFrames
                    ? GameScene.icicleWiggleDegrees * .pi / 180 * CGFloat(sin(Double(match.frame) / GameScene.icicleWiggleSwingFrames * 2 * .pi)) : 0
            } else if let node = hangingIcicles.removeValue(forKey: index) {
                node.removeFromParent()
            }
            if let tip = icicle.falling {
                let node = fallingIcicles[index] ?? {
                    let made = SKSpriteNode(texture: sprites.texture("icicle", 0))
                    made.anchorPoint = CGPoint(x: 0.5, y: 0)
                    made.zPosition = -7
                    stageGround.addChild(made)
                    fallingIcicles[index] = made
                    return made
                }()
                node.position = SpriteLibrary.point(tip)
            } else if let node = fallingIcicles.removeValue(forKey: index) {
                node.removeFromParent()
            }
        }
    }

    private func shatterIcicle(at tip: Vec2) {
        guard let count = EffectSheets.frames["icicle"], count > 1 else { return }
        let frames = (1..<count).map { sprites.texture("icicle", $0) }
        let node = SKSpriteNode(texture: frames[0])
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.position = SpriteLibrary.point(tip)
        node.zPosition = -7
        node.run(.sequence([.animate(with: frames, timePerFrame: 1 / Double(GameScene.icicleFramesPerSecond)), .removeFromParent()]))
        stageGround.addChild(node)
        shatteringIcicles.append(node)
    }

    /// Splashes here and there, at random, on what's on screen.
    private func splashRain() {
        rainSplashes.removeAll { $0.parent == nil }
        guard match.stage.features.look == .elements, !rainSplashSpots.isEmpty, let count = EffectSheets.frames["splash"],
              Double.random(in: 0..<1) < GameScene.rainSplashesPerSecond * GameScene.stepSeconds else { return }
        let halfWidth = size.width * cameraNode.xScale / 2
        let seen = rainSplashSpots.filter { abs($0.x.lowerBound - cameraNode.position.x) < halfWidth }
        guard let spot = seen.randomElement() else { return }
        let x = CGFloat.random(in: spot.x)
        let frames = (0..<count).map { sprites.texture("splash", $0) }
        let splash = SKSpriteNode(texture: frames[0])
        splash.anchorPoint = CGPoint(x: 0.5, y: EffectSheets.anchorY["splash"] ?? 0)
        splash.position = CGPoint(x: x, y: spot.y(x))
        splash.zRotation = spot.turn
        splash.setScale(GameScene.rainSplashScale)
        // Over the players.
        splash.zPosition = 24
        splash.run(.sequence([.animate(with: frames, timePerFrame: 1.0 / 15), .removeFromParent()]))
        world.addChild(splash)
        rainSplashes.append(splash)
    }

    // MARK: Wetshot Wake's water

    /// The water over everything in the world, under the HUD: palette 18 at the bottom of the
    /// screen to 19 at the top, faint, so the play stays clear.
    private let waterOverlay = SKSpriteNode()
    private static let waterGradient: SKTexture = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let height = 64
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: height), format: format).image { context in
            let bottom = PixelPalette.colours[18], top = PixelPalette.colours[19]
            for row in 0..<height {
                // Row 0 is the image's top.
                let share = CGFloat(row) / CGFloat(height - 1)
                func channel(_ shift: RGB) -> CGFloat {
                    let from = CGFloat((top >> shift) & 0xFF), to = CGFloat((bottom >> shift) & 0xFF)
                    return (from + (to - from) * share) / 255
                }
                SKColor(red: channel(16), green: channel(8), blue: channel(0), alpha: 1).setFill()
                context.fill(CGRect(x: 0, y: row, width: 1, height: 1))
            }
        }
        return SKTexture(image: image)
    }()

    /// Bubbles rising here and there, sometimes a few at once, wobbling side to side as they
    /// fade; each one of the sheet's five bubbles, the first the commonest.
    private struct Bubble {
        var node: SKSpriteNode
        var baseX: CGFloat
        var age: Double
        var life: Double
        var rise: CGFloat
        var wobble: CGFloat
        var wobbleRate: Double
    }
    private var bubbles: [Bubble] = []
    private static let bubblesPerSecond = 8.0
    private static let bubbleClusterChance = 0.25
    private static let frontBubbleShare = 0.3
    /// Bubbles off a body's feet as it comes down, a second's worth.
    private static let footBubblesPerSecond = 12.0
    /// Off the Hoopfish's tail as it swims, and all round it while it spins.
    private static let trailBubblesPerSecond = 10.0
    private static let spinBubblesPerFrame = 3
    /// The bubble cells' weights: the first as likely as near half the others together.
    private static let bubbleCellWeights = [0.4, 0.15, 0.15, 0.15, 0.15]

    /// The sea life swimming across behind the Hoopfish, from one side to the other: jellyfish
    /// drifting lazily, one to three together, breathing between 0.9 and 1.1; fish in schools,
    /// commoner, either colour; and now and then a lone shark. Each kind keeps its own clock,
    /// one group of it across at a time, and a group sometimes swims behind the foreground.
    private enum SeaLife: CaseIterable {
        case jellyfish, fish, shark

        /// Seconds between groups, how many to a group, and art pixels a second.
        var secondsBetween: ClosedRange<Double> {
            switch self {
            case .jellyfish: 6...12
            case .fish: 3...7
            case .shark: 40...80
            }
        }
        var groupSize: ClosedRange<Int> {
            switch self {
            case .jellyfish: 1...3
            case .fish: 2...5
            case .shark: 1...1
            }
        }
        var speed: ClosedRange<CGFloat> {
            switch self {
            case .jellyfish: 8...14
            case .fish: 20...30
            case .shark: 24...32
            }
        }
        /// How far a group's members trail one another, and spread up and down.
        var spacing: CGFloat { self == .shark ? 0 : self == .fish ? 14 : 20 }
        var spread: CGFloat { self == .fish ? 10 : 14 }
        /// How much it bobs, and how often, a second.
        var bob: ClosedRange<CGFloat> { self == .jellyfish ? 6...12 : 2...4 }
        var bobRate: ClosedRange<Double> { self == .jellyfish ? 0.08...0.15 : 0.2...0.4 }
        /// Its sheet's frames a second; jellyfish breathe instead.
        var framesPerSecond: Double { self == .shark ? 6 : 8 }
        /// The way its art faces: the shark's left.
        var facesRight: Bool { self != .shark }
        /// Bubbles off its tail a second, each.
        var trailBubblesPerSecond: Double { self == .shark ? 6 : 3 }
    }

    /// Now and then, by `perSecond`, a small bubble off the back of `node`, the end away from
    /// `heading` (1 right, -1 left), in its layer.
    private func trailBubble(behind node: SKSpriteNode, heading: CGFloat, perSecond: Double, lift: CGFloat = 0) {
        guard let parent = node.parent, Double.random(in: 0..<1) < perSecond * GameScene.stepSeconds else { return }
        let back = node.frame.midX - heading * node.frame.width / 2
        let point = CGPoint(x: back + .random(in: -2...2), y: node.position.y + lift + .random(in: -3...3))
        let bubble = SKSpriteNode(texture: sprites.texture("bubbles_jellyfish", Int.random(in: 0...2)))
        bubble.position = point
        bubble.zPosition = node.zPosition + 0.01
        parent.addChild(bubble)
        bubbles.append(Bubble(node: bubble, baseX: point.x, age: 0, life: .random(in: 1...2), rise: .random(in: 8...16),
                              wobble: .random(in: 1...2), wobbleRate: .random(in: 0.5...1)))
    }
    private struct Swimmer {
        var kind: SeaLife
        var node: SKSpriteNode
        var frames: [SKTexture]
        var baseY: CGFloat
        var age: Double
        var speed: CGFloat
        var bob: CGFloat
        var bobRate: Double
        var phase: Double
    }
    private var swimmers: [Swimmer] = []
    private var seaLifeClocks: [SeaLife: Double] = [:]
    private var nextSeaLife: [SeaLife: Double] = [.jellyfish: 3, .fish: 1, .shark: 25]
    private static let breathSeconds = 2.5
    /// The share of groups behind the background's foreground, and the layers either side of it.
    private static let seaLifeBehindForegroundShare = 0.3
    private static let seaLifeBehindForegroundZ: CGFloat = -18.5
    private static let seaLifeZ: CGFloat = -10

    private func stepWater() {
        let wet = match.stage.features.look == .wetshot
        let halfWidth = size.width * cameraNode.xScale / 2, halfHeight = size.height * cameraNode.yScale / 2
        if waterOverlay.parent == nil {
            waterOverlay.texture = GameScene.waterGradient
            waterOverlay.zPosition = 95
            world.addChild(waterOverlay)
        }
        waterOverlay.isHidden = !wet
        waterOverlay.alpha = WaterTuning.overlayAlpha
        waterOverlay.size = CGSize(width: halfWidth * 2, height: halfHeight * 2)
        waterOverlay.position = cameraNode.position
        // The ball's and the hoop's chevrons stay clear of the water, over it (glowers sit at 21).
        for chevron in chevrons + targetChevrons + [opponentChevron] { chevron.zPosition = wet ? 80 : 6 }
        let step = GameScene.stepSeconds
        bubbles = bubbles.compactMap { bubble in
            var bubble = bubble
            bubble.age += step
            guard bubble.age < bubble.life, bubble.node.parent != nil else { bubble.node.removeFromParent(); return nil }
            bubble.node.position = CGPoint(x: (bubble.baseX + bubble.wobble * CGFloat(sin(bubble.age * bubble.wobbleRate * 2 * .pi))).rounded(),
                                           y: bubble.node.position.y + bubble.rise * CGFloat(step))
            bubble.node.alpha = CGFloat(1 - bubble.age / bubble.life)
            return bubble
        }
        if wet, let count = EffectSheets.frames["bubbles_jellyfish"], count >= 6,
           Double.random(in: 0..<1) < GameScene.bubblesPerSecond * step {
            let at = CGPoint(x: cameraNode.position.x + .random(in: -halfWidth...halfWidth), y: cameraNode.position.y + .random(in: -halfHeight...halfHeight))
            let many = Double.random(in: 0..<1) < GameScene.bubbleClusterChance ? Int.random(in: 3...6) : 1
            for _ in 0..<many {
                var pick = Double.random(in: 0..<1), cell = 0
                for (index, weight) in GameScene.bubbleCellWeights.enumerated() {
                    if pick < weight { cell = index; break }
                    pick -= weight
                }
                let node = SKSpriteNode(texture: sprites.texture("bubbles_jellyfish", cell))
                let x = at.x + (many > 1 ? .random(in: -8...8) : 0)
                node.position = CGPoint(x: x, y: at.y + (many > 1 ? .random(in: -8...8) : 0))
                // A share in a layer over the players and the props, twice the size.
                if Double.random(in: 0..<1) < GameScene.frontBubbleShare {
                    node.setScale(2)
                    node.zPosition = 24
                    world.addChild(node)
                } else {
                    node.zPosition = 4.5
                    stageGround.addChild(node)
                }
                bubbles.append(Bubble(node: node, baseX: x, age: 0, life: .random(in: 2...4), rise: .random(in: 12...24),
                                      wobble: .random(in: 1...3), wobbleRate: .random(in: 0.5...1)))
            }
        }
        // Off the feet of whoever's coming down.
        if wet, !wholeStageView {
            for player in match.players where !player.grounded && player.velocity.y < 0
                && Double.random(in: 0..<1) < GameScene.footBubblesPerSecond * step {
                let node = SKSpriteNode(texture: sprites.texture("bubbles_jellyfish", Int.random(in: 0...4)))
                let feet = SpriteLibrary.point(player.position)
                let x = feet.x + .random(in: -4...4)
                node.position = CGPoint(x: x, y: feet.y)
                node.zPosition = 21
                world.addChild(node)
                bubbles.append(Bubble(node: node, baseX: x, age: 0, life: .random(in: 1...2), rise: .random(in: 8...16),
                                      wobble: .random(in: 1...2), wobbleRate: .random(in: 0.5...1)))
            }
        }
        // The Hoopfish where the sim has it, swimming; in the map maker, where it's placed.
        WetshotArt.place(wetshotArt?.hoopfish, as: wholeStageView ? nil : match.hoopfish, placed: StageMap.current[.wetshot].hoopfish)
        let spin = wholeStageView ? 0 : match.hoopfish?.spin ?? 0
        let spinCount = EffectSheets.frames["hoopfish_spin"] ?? 0
        WetshotArt.spin(wetshotArt?.hoopfish, showing: spin > 0 && spinCount > 0
            ? sprites.texture("hoopfish_spin", min((HoopfishRules.spinFrames - spin) * spinCount / HoopfishRules.spinFrames, spinCount - 1)) : nil)
        if wet, !wholeStageView, let fish = match.hoopfish, !fish.away, let node = wetshotArt?.hoopfish {
            func bubble(at point: CGPoint, front: Bool, cells: ClosedRange<Int>, rise: ClosedRange<CGFloat>, life: ClosedRange<Double>) {
                let bubble = SKSpriteNode(texture: sprites.texture("bubbles_jellyfish", Int.random(in: cells)))
                bubble.position = point
                bubble.zPosition = front ? 5.6 : 5.05
                node.parent?.addChild(bubble)
                bubbles.append(Bubble(node: bubble, baseX: point.x, age: 0, life: .random(in: life), rise: .random(in: rise),
                                      wobble: .random(in: 1...2), wobbleRate: .random(in: 0.5...1)))
            }
            // A trail off the tail, behind it.
            if Double.random(in: 0..<1) < GameScene.trailBubblesPerSecond * step {
                bubble(at: CGPoint(x: node.position.x + (WetshotArt.tailTip.x + .random(in: -2...2)) * node.xScale, y: node.position.y + WetshotArt.tailTip.y + .random(in: -4...4)),
                       front: false, cells: 0...2, rise: 10...18, life: 1.5...3)
            }
            // Spinning: a burst all round it, some over it.
            if spin > 0 {
                for _ in 0..<GameScene.spinBubblesPerFrame {
                    bubble(at: CGPoint(x: node.position.x + .random(in: 0...CGFloat(HoopfishRules.pixelWidth)) * node.xScale, y: node.position.y + .random(in: 0...48)),
                           front: Bool.random(), cells: 0...4, rise: 14...30, life: 1...2.5)
                }
            }
        }
        WetshotArt.animate(wetshotArt?.hoopfish, at: CACurrentMediaTime(), dunkedOn: match.players.contains { $0.state == .dunking })
        WetshotArt.sway(wetshotArt?.props ?? [], at: CACurrentMediaTime())
        swimmers = swimmers.compactMap { swimmer in
            var swimmer = swimmer
            swimmer.age += step
            let x = swimmer.node.position.x + swimmer.speed * CGFloat(step)
            guard swimmer.node.parent != nil, abs(x - cameraNode.position.x) < halfWidth + 80 else { swimmer.node.removeFromParent(); return nil }
            swimmer.node.position = CGPoint(x: x, y: swimmer.baseY + swimmer.bob * CGFloat(sin(swimmer.age * swimmer.bobRate * 2 * .pi)))
            // Turned to face the way it swims; a jellyfish breathing, the rest swimming through their sheets.
            let facing: CGFloat = (swimmer.speed > 0) == swimmer.kind.facesRight ? 1 : -1
            if swimmer.kind == .jellyfish {
                let breath = CGFloat(1 + 0.1 * sin((swimmer.age + swimmer.phase) / GameScene.breathSeconds * 2 * .pi))
                swimmer.node.xScale = breath * facing
                swimmer.node.yScale = breath
            } else {
                swimmer.node.xScale = facing
                let frame = Int((swimmer.age + swimmer.phase) * swimmer.kind.framesPerSecond) % swimmer.frames.count
                swimmer.node.texture = swimmer.frames[frame]
                // A trail of bubbles off the tail, behind the way it swims.
                trailBubble(behind: swimmer.node, heading: swimmer.speed > 0 ? 1 : -1, perSecond: swimmer.kind.trailBubblesPerSecond)
            }
            return swimmer
        }
        stepCrab(wet: wet)
        guard wet else { return }
        for kind in SeaLife.allCases {
            // One group of each kind across at a time.
            guard !swimmers.contains(where: { $0.kind == kind }) else { seaLifeClocks[kind] = 0; continue }
            seaLifeClocks[kind, default: 0] += step
            guard seaLifeClocks[kind, default: 0] >= nextSeaLife[kind, default: 0] else { continue }
            seaLifeClocks[kind] = 0
            nextSeaLife[kind] = .random(in: kind.secondsBetween)
            let frames = seaLifeFrames(kind)
            guard !frames.isEmpty else { continue }
            let fromLeft = Bool.random()
            let baseY = cameraNode.position.y + .random(in: -halfHeight * 0.5...halfHeight * 0.8)
            let z = Double.random(in: 0..<1) < GameScene.seaLifeBehindForegroundShare ? GameScene.seaLifeBehindForegroundZ : GameScene.seaLifeZ
            let speed = (fromLeft ? 1 : -1) * CGFloat.random(in: kind.speed)
            // A school keeps one colour.
            let colour = Int.random(in: 0..<2)
            for member in 0..<Int.random(in: kind.groupSize) {
                let memberFrames = kind == .fish ? fishFrames(colour: colour, sheet: frames) : frames
                let node = SKSpriteNode(texture: memberFrames[0])
                let startX = cameraNode.position.x + (fromLeft ? -1 : 1) * (halfWidth + 40 + CGFloat(member) * kind.spacing)
                node.position = CGPoint(x: startX, y: baseY + (member == 0 ? 0 : CGFloat.random(in: -kind.spread...kind.spread)))
                node.zPosition = z
                stageGround.addChild(node)
                // Schoolmates keep nearly the leader's pace.
                swimmers.append(Swimmer(kind: kind, node: node, frames: memberFrames, baseY: node.position.y, age: 0,
                                        speed: speed * .random(in: 0.95...1.05), bob: .random(in: kind.bob),
                                        bobRate: .random(in: kind.bobRate), phase: .random(in: 0...GameScene.breathSeconds)))
            }
        }
    }

    /// The crab along the sea floor, in front of the rocks and behind the players: one crossing
    /// at a time, slowly, right to left first and then the other way each time, a while apart.
    private var crab: SKSpriteNode?
    private var crabLeftward = true
    private var crabClock = 0.0
    private static let crabSpeed: CGFloat = 16
    private static let crabSecondsBetween = 20.0
    private static let crabFramesPerSecond = 6.0
    private static let crabZ: CGFloat = 4.2
    private static let crabBubblesPerSecond = 3.0

    private func stepCrab(wet: Bool) {
        let frameCount = EffectSheets.frames["crab"] ?? 0
        guard wet, frameCount > 0, !wholeStageView else {
            crab?.removeFromParent()
            crab = nil
            return
        }
        let width = CGFloat(match.stage.columns) * WetshotArt.tileSide
        if let node = crab, node.parent != nil {
            let x = node.position.x + (crabLeftward ? -1 : 1) * GameScene.crabSpeed * CGFloat(GameScene.stepSeconds)
            node.position.x = x
            crabClock += GameScene.stepSeconds
            node.texture = sprites.texture("crab", Int(crabClock * GameScene.crabFramesPerSecond) % frameCount)
            trailBubble(behind: node, heading: crabLeftward ? -1 : 1, perSecond: GameScene.crabBubblesPerSecond, lift: node.size.height / 2)
            // Off the far side: done, and the next goes the other way.
            if x < -node.size.width || x > width + node.size.width {
                node.removeFromParent()
                crab = nil
                crabLeftward.toggle()
                crabClock = 0
            }
            return
        }
        crabClock += GameScene.stepSeconds
        guard crabClock >= GameScene.crabSecondsBetween else { return }
        crabClock = 0
        let node = SKSpriteNode(texture: sprites.texture("crab", 0))
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.position = CGPoint(x: crabLeftward ? width + node.size.width / 2 : -node.size.width / 2,
                                y: WetshotArt.tileSide * CGFloat(WetshotArt.floorRows))
        node.zPosition = GameScene.crabZ
        stageGround.addChild(node)
        crab = node
    }

    /// One colour of fish, its half of each frame, cut from the frame's own picture: a rect
    /// of an atlas texture is read against the whole atlas page, not the frame. Cut once.
    private var fishColours: [[SKTexture]] = []
    private func fishFrames(colour: Int, sheet: [SKTexture]) -> [SKTexture] {
        if fishColours.isEmpty {
            fishColours = (0..<2).map { side in
                sheet.compactMap { frame -> SKTexture? in
                    let picture = frame.cgImage()
                    let half = picture.width / 2
                    guard let cut = picture.cropping(to: CGRect(x: side * half, y: 0, width: half, height: picture.height)) else { return nil }
                    let texture = SKTexture(cgImage: cut)
                    texture.filteringMode = .nearest
                    return texture
                }
            }
        }
        let frames = fishColours[min(colour, fishColours.count - 1)]
        return frames.isEmpty ? sheet : frames
    }

    /// A sea creature's sheet: the jellyfish's one cell of the bubbles sheet, the fish's
    /// frames (both colours side by side), the shark's.
    private func seaLifeFrames(_ kind: SeaLife) -> [SKTexture] {
        switch kind {
        case .jellyfish:
            return EffectSheets.frames["bubbles_jellyfish"] != nil ? [sprites.texture("bubbles_jellyfish", 5)] : []
        case .fish, .shark:
            let name = kind == .fish ? "fish" : "shark"
            return (0..<(EffectSheets.frames[name] ?? 0)).map { sprites.texture(name, $0) }
        }
    }

    /// The loose ball's turning, from what it does: backspin off a shot or a throw, kept through the
    /// air, a bounce trading half of it for the roll the floor gives, and a ball rolling turning with its path.
    private func spinBall(_ ball: Ball) {
        let now = CACurrentMediaTime()
        defer { ballSeen = (ball.velocity, ball.position.y, ball.holder != nil, now) }
        guard ball.holder == nil else { ballSpin.rate = 0; ballSpin.angle = 0; return }
        let turnsToRadians = 2 * CGFloat.pi
        let mostSpin = GameScene.mostSpinTurnsPerSecond * turnsToRadians
        // Radians a second the ball would turn rolling at this speed, clockwise going right.
        let rolling = { (velocity: Vec2) in CGFloat(-velocity.x * 60 / BallRules.radius) }
        if let seen = ballSeen {
            let dt = CGFloat(min(max(now - seen.time, 0), 0.05))
            if seen.held, ball.velocity.length > 1 {
                ballSpin.frame = Int.random(in: 0..<SpriteLibrary.basketballFrameCount)
                ballSpin.rate = CGFloat(ball.velocity.x < 0 ? -1 : 1) * GameScene.backspinTurnsPerSecond * turnsToRadians
            } else if abs(ball.velocity.x - seen.velocity.x) > 0.25 || ball.velocity.y - seen.velocity.y > 0.5 {
                ballSpin.rate = ballSpin.rate * 0.5 + rolling(ball.velocity) * 0.5
            } else if abs(ball.position.y - seen.y) < 0.01, abs(ball.velocity.y) < 0.2, match.stage.isGrounded(ball.box) {
                ballSpin.rate = rolling(ball.velocity)
            }
            ballSpin.rate = min(max(ballSpin.rate, -mostSpin), mostSpin)
            // Frozen, it holds its turn.
            // Under water it turns at half the rate.
            if ball.frozen == 0 { ballSpin.angle += ballSpin.rate * dt * (match.stage.features.underwater ? 0.5 : 1) }
        }
        ballNode.texture = (ball.frozen > 0 ? sprites.basketballIceFrames : sprites.basketballFrames)[ballSpin.frame]
        ballNode.zRotation = ballSpin.angle
    }

    /// The ball's glow, and on the Hoopfish's antenna the most of its pulse and the pulse's length.
    private static let ballGlow: CGFloat = 0.5
    private static let antennaBallGlow: CGFloat = 0.9
    private static let antennaBallGlowSeconds = 2.0
    /// On the antenna, the halo's size over its usual and its share of the way to white.
    private static let antennaBallHaloScale: CGFloat = 2
    private static let antennaBallLighten: CGFloat = 0.5

    private func makeHalo(_ colour: SKColor) -> SKSpriteNode {
        let halo = SKSpriteNode(texture: sprites.softGlow(diameter: 32))
        halo.size = CGSize(width: 18, height: 18)
        halo.color = colour
        halo.colorBlendFactor = 1
        halo.alpha = GameScene.ballGlow
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
        let scrolls = [StageLook.footballField, .elements].contains(match.stage.features.look)
        // The field and the Elements scroll sideways, so only its height is fitted; a scenic stage counts the
        // ground below the floor in, so the players stand in the middle of it; not the Elements,
        // whose floor is the lava at the screen's bottom.
        let below = match.stage.features.scenic && ![StageLook.elements, .wetshot, .flight].contains(match.stage.features.look) ? FieldArt.viewBelowFloor : 0
        let stageHeight = CGFloat(match.stage.rows) * GameScene.pixelsPerTile + below
        let fitHeight = (screenScale * size.height / stageHeight).rounded(.down)
        let fitWidth = (screenScale * size.width / stageWidth).rounded(.down)
        let screenPixelsPerGamePixel = max(1, scrolls ? fitHeight : min(fitHeight, fitWidth))
        // The map maker sees the whole stage at once, as big as it fits, not by whole pixels.
        // Wetshot Wake fills the screen's width, its bottom on the screen's: a phone crops blank
        // water off the top, a squarer screen shows more of it.
        let fills = match.stage.features.look == .wetshot && !wholeStageView
        let pointsPerGamePixel = wholeStageView ? min(size.width / stageWidth, size.height / stageHeight)
            : (fills ? size.width / stageWidth : screenPixelsPerGamePixel / screenScale)
        cameraNode.setScale(1 / pointsPerGamePixel)
        cameraBaseScale = cameraNode.xScale
        cameraNode.position = CGPoint(x: scrolls && !wholeStageView ? cameraBase.x : stageWidth / 2,
                                      y: fills ? size.height * cameraNode.yScale / 2 : stageHeight / 2 - below)
        if scrolls, !wholeStageView, cameraBase.x == 0 { cameraNode.position.x = cameraTargetX() }
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
        controls.showWalls = showWalls
        controls.onToggleWalls = { [weak self] on in self?.showWalls = on }
        controls.aiOn = aiOn
        controls.onToggleAI = { [weak self] on in self?.aiOn = on }
        controls.addPicker(title: "HEAD", options: HeadVariant.allCases.map(\.label), selected: headVariant.rawValue) { [weak self] index in
            self?.headVariant = HeadVariant(rawValue: index)!
        }
        controls.addPicker(title: "POWER", options: PowerVariant.allCases.map(\.label), selected: powerVariant.rawValue, perRow: 7) { [weak self] index in
            self?.powerVariant = PowerVariant(rawValue: index)!
            self?.applyPower()
        }
        controls.addPicker(title: "COUNT", options: ["A", "B"], selected: UserDefaults.standard.integer(forKey: SoundBoard.countSetKey)) { index in
            UserDefaults.standard.set(index, forKey: SoundBoard.countSetKey)
        }
        controls.addPicker(title: "SFX", options: Onomatopoeia.pickable.map(\.label), selected: Onomatopoeia.pickable.firstIndex(of: Onomatopoeia.lettering) ?? 0, perRow: 3) { [weak self] index in
            Onomatopoeia.lettering = Onomatopoeia.pickable[index]
            SKTexture.preload(Onomatopoeia.warmed()) {}
            self?.previewSoundWord()
        }
        controls.addPicker(title: "LEVEL", options: PowerLevelVariant.allCases.map(\.label), selected: powerLevelVariant.rawValue) { [weak self] index in
            self?.powerLevelVariant = PowerLevelVariant(rawValue: index)!
            self?.applyPower()
        }
        // The map maker only means anything on a hand-laid stage, offline, with a mouse.
        #if !os(tvOS)
        if [StageLook.elements, .wetshot, .flight].contains(match.stage.features.look), online == nil {
            controls.addPicker(title: "MAP", options: ["OFF", "ON"], selected: mapEditor == nil ? 0 : 1) { [weak self] index in
                index == 1 ? self?.openMapEditor() : self?.closeMapEditor(restart: true)
            }
        }
        #endif
        // The hoop support builder, on the Wreck Center.
        #if !os(tvOS)
        if match.stage.features.look == .court, online == nil {
            controls.addPicker(title: "SUPPORT", options: ["OFF", "ON"], selected: supportBuilder == nil ? 0 : 1) { [weak self] index in
                index == 1 ? self?.openSupportBuilder() : self?.closeSupportBuilder()
            }
        }
        #endif
        // The bounds gallery only means anything on the highway.
        if match.stage.features.traffic {
            controls.addPicker(title: "BOUNDS", options: ["OFF", "ON"], selected: boundsGallery == nil ? 0 : 1) { [weak self] index in
                index == 1 ? self?.openBoundsGallery() : self?.closeBoundsGallery()
            }
        }
        // The net against the rim for a stage, and its shape, the same on every stage.
        func addNetSliders(_ look: StageLook) {
            controls.addSlider(title: "NET X", range: -20...20, notch: 1, value: Float(NetTuning.setting(for: look).x)) {
                UserDefaults.standard.set(Double($0), forKey: NetTuning.offsetXKey(for: look))
            }
            controls.addSlider(title: "NET Y", range: -20...20, notch: 1, value: Float(NetTuning.setting(for: look).y)) {
                UserDefaults.standard.set(Double($0), forKey: NetTuning.offsetYKey(for: look))
            }
            // The net's shape, the same on every stage: the cylinder's, or the flat net's as on
            // the UI tuning panel.
            let shared: [(String, String, CGFloat, Float, ClosedRange<Float>)] = [
                ("NET TOP", NetTuning.topScaleKey, NetTuning.topScale, 0.25, 0.25...4),
                ("NET BOTTOM", NetTuning.bottomScaleKey, NetTuning.bottomScale, 0.25, 0.25...4),
                ("NET ROWS", NetTuning.rowSpacingKey, NetTuning.rowSpacing, 0.25, 1...8),
            ]
            let flat: [(String, String, CGFloat, Float, ClosedRange<Float>)] = [
                ("NET SPREAD", NetTuning.spreadKey, NetTuning.spread, 1, 1...8),
                ("NET WEAVE", NetTuning.weaveKey, NetTuning.weave, 0.25, 0...1),
                ("NET TAPER", NetTuning.taperKey, NetTuning.taper, 0.25, 0...0.75),
                ("NET SKEW", NetTuning.skewKey, NetTuning.skew, 0.25, -4...4),
            ]
            let cylinder: [(String, String, CGFloat, Float, ClosedRange<Float>)] = [
                ("NET RADIUS TOP", NetTuning.radiusTopKey, NetTuning.radiusTop, 0.5, 1...20),
                ("NET RADIUS BOTTOM", NetTuning.radiusBottomKey, NetTuning.radiusBottom, 0.5, 1...20),
                ("NET RINGS", NetTuning.ringsKey, NetTuning.rings, 1, 1...12),
                ("NET AROUND", NetTuning.aroundKey, NetTuning.around, 1, 3...24),
                ("NET TILT X", NetTuning.tiltKey, NetTuning.tilt, 1, -90...90),
                ("NET TURN Y", NetTuning.turnKey, NetTuning.turn, 1, -180...180),
                ("NET ROLL Z", NetTuning.rollKey, NetTuning.roll, 1, -90...90),
            ]
            for (title, key, value, notch, range) in shared + (NetTuning.cylinder ? cylinder : flat) {
                controls.addSlider(title: title, range: range, notch: notch, value: Float(value)) { UserDefaults.standard.set(Double($0), forKey: key) }
            }
        }
        if series.stage.stage.features.look == .footballField {
            // Longball's net, tuned in play.
            addNetSliders(.footballField)
            controls.addSlider(title: "CROSSBAR ANGLE", range: -45...45, notch: 1, value: Float(GoalpostTuning.crossbarAngle)) { [weak self] value in
                GoalpostTuning.crossbarAngle = CGFloat(value)
                self?.buildGoalposts()
                self?.buildBackboards()
            }
        }
        if series.stage.stage.features.look == .elements {
            controls.addSlider(title: "RAIN DENSITY", range: 0...4, notch: 0.25, value: Float(RainTuning.density)) { [weak self] value in
                RainTuning.density = Double(value)
                GameScene.rainTextures = GameScene.makeRainTextures()
                self?.rainTiles.joined().enumerated().forEach { index, tile in tile.texture = GameScene.rainTextures[index < (self?.rainTiles[0].count ?? 0) ? 0 : 1] }
            }
        }
        if series.stage.stage.features.look == .wetshot, online == nil {
            controls.addSlider(title: "WATER TINT", range: 0...1, notch: 0.01, value: Float(WaterTuning.overlayAlpha)) { WaterTuning.overlayAlpha = CGFloat($0) }
            controls.addSlider(title: "WATER SWAY", range: 0...4, notch: 0.25, value: Float(WaterTuning.swayPixels)) { WaterTuning.swayPixels = Double($0) }
            // The rim's place across the Hoopfish, a whole art pixel at a time.
            // Where the ball hangs on the antenna, a whole art pixel at a time.
            controls.addSlider(title: "BALL X", range: 0...96, notch: 1, value: Float(WetshotRules.ballPixelsAcross)) { value in
                WetshotRules.ballPixelsAcross = Int(value.rounded())
            }
            controls.addSlider(title: "BALL Y", range: 0...48, notch: 1, value: Float(WetshotRules.ballPixelsUp)) { value in
                WetshotRules.ballPixelsUp = Int(value.rounded())
            }
            controls.addSlider(title: "HOOP X", range: 0...96, notch: 1, value: Float(WetshotRules.rimPixelsAcross)) { [weak self] value in
                let pixels = Int(value.rounded())
                guard pixels != WetshotRules.rimPixelsAcross else { return }
                WetshotRules.rimPixelsAcross = pixels
                self?.session.mutate { $0.stage = .wetshot; $0.refreshExtras() }
            }
        }
        if ChevronTuning.slider {
            controls.addSlider(title: "BASKET CHEVRON Y", range: 0...60, notch: 1, value: Float(ChevronTuning.basketLift)) { ChevronTuning.basketLift = CGFloat($0) }
        }
        // The FLO meters' look, while it's settled.
        let relayoutFlo: () -> Void = { [weak self] in self?.layoutFloMeters() }
        controls.addSlider(title: "FLO METER SCALE", range: 0.5...3, notch: 0.05, value: Float(FloTuning.meterScale)) { FloTuning.meterScale = CGFloat($0); relayoutFlo() }
        controls.addSlider(title: "FLO METER Y", range: -60...60, notch: 1, value: Float(FloTuning.meterY)) { FloTuning.meterY = CGFloat($0); relayoutFlo() }
        // The A/B test: A empties from the word's end, MAX on the word; B fills from it.
        controls.addPicker(title: "FLO BAR", options: ["A", "B"], selected: FloTuning.variant == .emptiesFromWord ? 0 : 1) { index in
            FloTuning.variant = index == 0 ? .emptiesFromWord : .fillsFromWord
            relayoutFlo()
        }
        controls.addSlider(title: "FLO MAX SCALE", range: 0.25...4, notch: 0.05, value: Float(FloTuning.cornerMaxScale)) { FloTuning.cornerMaxScale = CGFloat($0); relayoutFlo() }
        controls.addSlider(title: "FLO MAX X", range: -60...60, notch: 1, value: Float(FloTuning.cornerMaxX)) { FloTuning.cornerMaxX = CGFloat($0); relayoutFlo() }
        controls.addSlider(title: "FLO MAX Y", range: -30...30, notch: 1, value: Float(FloTuning.cornerMaxY)) { FloTuning.cornerMaxY = CGFloat($0); relayoutFlo() }
        if ParticleLook.cubes && ParticleLook.cubeSliders {
            controls.addSlider(title: "CUBE SIZE", range: 1...8, notch: 1, value: ParticleLook.cubeSize) { ParticleLook.cubeSize = $0 }
            controls.addSlider(title: "CUBE SPREAD", range: 0...16, notch: 1, value: ParticleLook.cubeSpread) { ParticleLook.cubeSpread = $0 }
            controls.addSlider(title: "LEG CUBE SIZE", range: 1...8, notch: 1, value: ParticleLook.legCubeSize) { ParticleLook.legCubeSize = $0 }
            controls.addSlider(title: "LEG CUBE SPREAD", range: 0...16, notch: 1, value: ParticleLook.legCubeSpread) { ParticleLook.legCubeSpread = $0 }
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
            let dunkLook = series.stage.stage.features.look
            let xSlider = controls.addSlider(title: "DUNK X", range: -32...32, notch: 1, value: Float(DunkArt.offsets(for: dunkLook)[DunkTuning.frame].x)) {
                let at = DunkArt.offsets(for: dunkLook)[DunkTuning.frame]
                DunkArt.set(CGPoint(x: CGFloat($0), y: at.y), frame: DunkTuning.frame, for: dunkLook)
            }
            let ySlider = controls.addSlider(title: "DUNK Y", range: -32...32, notch: 1, value: Float(DunkArt.offsets(for: dunkLook)[DunkTuning.frame].y)) {
                let at = DunkArt.offsets(for: dunkLook)[DunkTuning.frame]
                DunkArt.set(CGPoint(x: at.x, y: CGFloat($0)), frame: DunkTuning.frame, for: dunkLook)
            }
            // The hoop's art and the net against the rim, for the stage picked.
            let look = series.stage.stage.features.look
            controls.addSlider(title: "HOOP X", range: -24...24, notch: 1, value: Float(HoopTuning.offset(for: look).x)) {
                HoopTuning.set(CGPoint(x: CGFloat($0), y: HoopTuning.offset(for: look).y), for: look)
            }
            controls.addSlider(title: "HOOP Y", range: -24...24, notch: 1, value: Float(HoopTuning.offset(for: look).y)) {
                HoopTuning.set(CGPoint(x: HoopTuning.offset(for: look).x, y: CGFloat($0)), for: look)
            }
            if look != .footballField { addNetSliders(look) }
            controls.addSlider(title: "TITAN DUNK X", range: -32...32, notch: 1, value: Float(DunkArt.titanOffset.x)) { DunkArt.titanOffset.x = CGFloat($0) }
            controls.addSlider(title: "TITAN DUNK Y", range: -32...32, notch: 1, value: Float(DunkArt.titanOffset.y)) { DunkArt.titanOffset.y = CGFloat($0) }
            controls.addSlider(title: "DUNK FRAME", range: 0...last, notch: 1, value: Float(DunkTuning.frame)) { value in
                DunkTuning.frame = Int(value)
                xSlider.set(Float(DunkArt.offsets(for: dunkLook)[DunkTuning.frame].x))
                ySlider.set(Float(DunkArt.offsets(for: dunkLook)[DunkTuning.frame].y))
            }
        }
        controls.setOnline(online != nil)
        controls.isHidden = !GameScene.touchControlsShown
        hud.addChild(controls)
        self.controls = controls
        scoreLabel.position = CGPoint(x: 0, y: halfHeight - insets.top - 8)
        circles.position = CGPoint(x: 0, y: halfHeight - insets.top - GameScene.scoreboardBelowTop)
        circlesOverCam.position = circles.position
        drawSeries()
        presentScreen()
        layoutFloMeters()
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
        #if !os(tvOS)
        if mapEditor != nil || supportBuilder != nil {
            // The match held still while the map or the supports are being laid out.
            render()
            return
        }
        #endif
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
        // Start or delete pauses a match offline, and again resumes it; over the settings, it shuts them.
        if hub.consumePause(), online == nil {
            if let flowState, flowState.customizeOpen, !flowState.settingsOpen {
                flowState.startFromCustomize()
            } else if let flowState, flowState.settingsOpen {
                flowState.closeSettings()
            } else if flow == .playing {
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
            if let flowState, flowState.settingsOpen {
                // The settings, over the title or the pause: up and down a row, left and right
                // its choice, jump on BACK or B to shut them.
                if down { flowState.moveSettingsCursor(1) }
                if up { flowState.moveSettingsCursor(-1) }
                if right { flowState.stepSetting(1) }
                if left { flowState.stepSetting(-1) }
                if picked {
                    menuNeedsRelease = true
                    if flowState.settingsCursor >= GameSettings.Row.allCases.count { flowState.closeSettings() } else { flowState.stepSetting(1) }
                } else if backed {
                    menuNeedsRelease = true
                    flowState.closeSettings()
                }
            } else if let screen {
                if right || down { screen.move(1) }
                if left || up { screen.move(-1) }
                if picked {
                    menuNeedsRelease = true
                    screen.fire()
                } else if backed, screen.back != nil {
                    menuNeedsRelease = true
                    screen.goBack()
                }
            } else if flow == .title, let flowState, flowState.customizeOpen {
                // The customize screen: the first pad the first side's cursor, a second pad the second's.
                if right { flowState.moveCustomize(0, across: 1, down: 0) }
                if left { flowState.moveCustomize(0, across: -1, down: 0) }
                if down { flowState.moveCustomize(0, across: 0, down: 1) }
                if up { flowState.moveCustomize(0, across: 0, down: -1) }
                if picked {
                    menuNeedsRelease = true
                    flowState.activateCustomize(0, flowState.customizeCursors[0])
                } else if backed {
                    // B out of a picker to its box; else back to the title.
                    menuNeedsRelease = true
                    if !flowState.leaveCustomizePicker(0) { flowState.closeCustomize() }
                }
                if inputs.count > 1, hub.playerTwoHasController {
                    let second = inputs[1], last = secondMenuLast
                    if second.stick.x >= 0.5, last.stick.x < 0.5 { flowState.moveCustomize(1, across: 1, down: 0) }
                    if second.stick.x <= -0.5, last.stick.x > -0.5 { flowState.moveCustomize(1, across: -1, down: 0) }
                    if second.stick.y <= -0.5, last.stick.y > -0.5 { flowState.moveCustomize(1, across: 0, down: 1) }
                    if second.stick.y >= 0.5, last.stick.y < 0.5 { flowState.moveCustomize(1, across: 0, down: -1) }
                    if second.jump, !last.jump { flowState.activateCustomize(1, flowState.customizeCursors[1]) }
                    let secondBack = second.shootButtons & 1 != 0 || second.throwBall
                    if secondBack, !(last.shootButtons & 1 != 0 || last.throwBall) { _ = flowState.leaveCustomizePicker(1) }
                    secondMenuLast = second
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
        // Testing FLO, offline: 1 to 3 the first player's, 4 to 6 the second's.
        if let asked = hub.consumeFloSet(), online == nil {
            session.mutate { match in
                guard match.players.indices.contains(asked.player) else { return }
                match.players[asked.player].flo = asked.flo
            }
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
    /// by the stage's `HoopTuning.offset` in art pixels, across mirrored for a backboard on the left.
    static func hoopArtPoint(for hoop: Hoop, on look: StageLook) -> CGPoint {
        point(for: hoop, moved: HoopTuning.offset(for: look))
    }

    /// Where the net hangs from: the rim's point, moved by the stage's NET X and NET Y.
    static func netPoint(for hoop: Hoop, on look: StageLook) -> CGPoint {
        point(for: hoop, moved: NetTuning.offset(for: look))
    }

    private static func point(for hoop: Hoop, moved offset: CGPoint) -> CGPoint {
        let at = SpriteLibrary.point(hoop.position)
        let across = offset.x * (hoop.backboard == .left ? -1 : 1)
        return CGPoint(x: at.x + across, y: at.y + offset.y)
    }

    /// The court's rims to where the RIM sliders have them, in the match as it stands.
    /// The backboard blocks where the sliders have them, and the court drawn again round them.
    private func moveCourtBlocks() {
        session.mutate { match in
            guard match.stage.features.look == Stage.court.features.look, match.stage.columns == Stage.court.columns else { return }
            let court = Stage.court
            match.stage.tiles = court.tiles
            match.stage.hoops = court.hoops
            match.stage.fixedExtras = court.fixedExtras
            match.stage.outOfReach = court.outOfReach
            match.refreshExtras()
        }
        redrawStage()
    }

    private func moveCourtRims() {
        session.mutate { match in
            guard match.stage.features.look == Stage.court.features.look, match.stage.columns == Stage.court.columns else { return }
            let court = Stage.court
            match.stage.hoops = court.hoops
            match.stage.fixedExtras = court.fixedExtras
            match.refreshExtras()
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
        let table = DunkArt.offsets(for: match.stage.features.look).map { "(\(Int($0.x)), \(Int($0.y)))" }.joined(separator: " ")
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
        announceDoublePoints()
        enter(.playing)
    }

    /// A round: bodies with their drinks in them at their spawns, the count, and the
    /// port-in, unless a screen is to come first.
    private func startRound(portingIn: Bool = true) {
        fortySevenScores = [0, 0]
        session = RollbackSession(match: freshMatch(), localIndex: localIndex, delay: online == nil ? 0 : NetRules.inputDelay)
        // A fresh round's meters start from nothing on the way.
        floOrbs = []
        floOnTheWay = [:]
        floGainsShown = []
        floBundleNodes.values.forEach { $0.removeFromParent() }
        floBundleNodes = [:]
        showStage()
        controls?.setOnline(online != nil)
        freshRoundView()
        if portingIn { bringPlayersIn() }
    }

    /// The view's hold on the last round let go: the computer, the rim flashes, the ball's colour.
    private func freshRoundView() {
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
        // A hand-laid stage's map: the one every phone plays, but offline what the map maker last kept.
        for mapStage in MapStage.allCases {
            StageMap.current[mapStage] = online == nil ? (SavedStageMap.value(mapStage) ?? StageMap.baked(mapStage)) : StageMap.baked(mapStage)
        }
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

    /// The stages on the select: 47 plays on the Wreck Center or Wetshot Wake.
    private var stageList: [StageChoice] { gameMode == .fortySeven ? StageChoice.fortySeven : StageChoice.selectable }

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
        announceDoublePoints()
        enter(.playing)
    }

    /// In 47 on a stage where points are worth double, it says so as play starts there.
    private func announceDoublePoints() {
        guard gameMode == .fortySeven, series.stage.stage.features.doublePoints else { return }
        bannerQueue.append(("Points Are Worth Double!", 26))
    }

    /// The drinks onto the bodies as they stand, for the round about to count. The POWER
    /// picker's choice, offline, stands over the drinks.
    private func applyDrinks() {
        let pickerOn = online == nil && powerVariant != .none
        let drinks = series.drinks.indices.map { drinksInPlay($0, pickerOn: pickerOn) }
        session.mutate { match in
            for index in match.players.indices {
                match.players[index].spec = match.stage.sized(drinks[index].spec())
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

    /// "2X" over the rim a basket went through, where points are worth double: from a tenth of
    /// its size up, fading as it grows.
    private func showDoubleMark(at hoop: Int) {
        guard hoop < rimNodes.count, let parent = rimNodes[hoop].parent else { return }
        let texture = TitleText.markTexture("2X", size: 48, upper: 7, lower: 20, outline: 29)
        let mark = SKSpriteNode(texture: texture)
        let height = GameScene.doubleMarkHeight
        mark.size = CGSize(width: height * texture.size().width / max(texture.size().height, 1), height: height)
        mark.position = rimNodes[hoop].position + CGPoint(x: 0, y: GameScene.doubleMarkLift)
        // Over the water's tint.
        mark.zPosition = 97
        mark.setScale(0.1)
        let grow = SKAction.scale(to: 1, duration: 0.3)
        grow.timingMode = .easeOut
        // Up to size, held there a while, then on out a little more as it fades.
        mark.run(.sequence([grow, .wait(forDuration: GameScene.doubleMarkHoldSeconds),
                            .group([.scale(to: 1.2, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        parent.addChild(mark)
    }
    /// The made basket's sound out of the net, toward the court and a little up.
    private func exclaimBasket(at hoop: Int, dunk: Bool, three: Bool) {
        guard hoop < rimNodes.count else { return }
        let rim = rimNodes[hoop].position
        let courtward: CGFloat = rim.x < SpriteLibrary.point(Vec2(x: match.stage.width / 2, y: 0)).x ? 1 : -1
        let sound: Onomatopoeia.Sound = dunk ? .dunk : three ? .three : .swish
        say(sound, from: rim + CGPoint(x: 0, y: GameScene.netDrop), away: courtward, rise: dunk ? 25 : 15, gap: GameScene.basketWordGap)
    }
    /// How far under the rim the net's middle hangs, and how far out of it a basket's word starts, in art pixels.
    private static let netDrop: CGFloat = -10
    private static let basketWordGap: CGFloat = 8
    /// How far ahead of the chest a slash's blade meets a wall, in units.
    private static let bladeReach = 8.0
    /// How far out of its source a word starts, in art pixels.
    private static let wordGap: CGFloat = 2
    /// Words are drawn behind the bodies (20) and the effects (21), so they can sit close.
    private static let wordZ: CGFloat = 19

    /// Footfalls: on the frames of the walk and run cycles a foot comes down, a puff of dust
    /// off it in the player's energy colour (not under water), and every other cycle a
    /// footstep word beside the feet.
    private var footPhases: [Int: Int] = [:]
    private var footfallCounts: [Int: Int] = [:]
    private static let walkFootfalls: Set<Int> = [2, 6]
    private static let runFootfalls: Set<Int> = [1, 5]
    /// Footfalls to a footstep word.
    private static let footfallsPerWord = 2
    private func stepFootfalls() {
        guard !wholeStageView else { return }
        for (index, player) in match.players.enumerated() {
            let running = player.state == .run || player.state == .dash
            guard player.grounded, running || player.state == .walk else { footPhases[index] = nil; footfallCounts[index] = 0; continue }
            let frame = Int(player.animationPhase) % 8
            defer { footPhases[index] = frame }
            guard footPhases[index] != frame, (running ? GameScene.runFootfalls : GameScene.walkFootfalls).contains(frame) else { continue }
            let dust: Effect = running ? .dustRun : .dustWalk
            // A power's own trail, Blazing Boba's flames, stands in for the dust.
            if dust.available, GameSettings.walkTrails, !match.stage.features.underwater, !player.layingFlames {
                // Kicked up behind the feet.
                spawn(dust, at: player.position + Vec2(x: -player.facing.sign * GameScene.dustBehind, y: 0),
                      flipped: player.facing == .left, player: index, scale: bodyScale(index))
            }
            let count = footfallCounts[index, default: 0]
            footfallCounts[index] = count + 1
            if count % GameScene.footfallsPerWord == 0 {
                // Out of the dust, back the way it came, low.
                soundWords.removeAll { $0.parent == nil }
                say(running ? .run : .walk, at: player.position + Vec2(x: -player.facing.sign * GameScene.dustBehind, y: 0),
                    away: -player.facing.sign, rise: 10)
            }
        }
    }
    /// How far behind the feet the dust starts, in units.
    private static let dustBehind = 2.0

    /// A sound word out of where its sound is made, Jump Ultimate Stars style: small at the
    /// source, growing `away` (1 right, -1 left), turned up `rise` degrees as it goes; turned
    /// back the other way when that would run it off the screen.
    private func say(_ sound: Onomatopoeia.Sound, at source: Vec2, away given: CGFloat, rise degrees: CGFloat, gap: CGFloat = GameScene.wordGap) {
        say(sound, from: SpriteLibrary.point(source), away: given, rise: degrees, gap: gap)
    }
    private func say(_ sound: Onomatopoeia.Sound, from source: CGPoint, away given: CGFloat, rise degrees: CGFloat, gap: CGFloat = GameScene.wordGap) {
        // As many as the settings want: all, the biggest only, or none.
        switch GameSettings.words {
        case .on: break
        case .some: guard sound.isBiggest else { return }
        case .off: return
        }
        let halfWidth = size.width * cameraNode.xScale / 2
        var away: CGFloat = given < 0 ? -1 : 1
        if (source.x - cameraNode.position.x) * away > halfWidth - GameScene.wordRoom { away = -away }
        soundWords.append(Onomatopoeia.show(sound, from: source, away: away, rise: degrees * .pi / 180, gap: gap, in: world, z: GameScene.wordZ))
    }
    /// How fast a bounce has to be to be said: not the settling ones.
    private static let bounceWordFloor = 1.5
    /// The room a word wants on its side before the screen's edge, in art pixels.
    private static let wordRoom: CGFloat = 70

    /// The manga sounds for a frame's events, shown once like the effects, each out of where
    /// it's made and away from whoever made it.
    private func exclaim(_ events: [MatchEvent]) {
        soundWords.removeAll { $0.parent == nil }
        let players = match.players
        func side(_ at: Vec2, from cause: Vec2) -> CGFloat { at.x >= cause.x ? 1 : -1 }
        // A fireball's burst says its own word; the hit it lands doesn't say another.
        let fireballBurst = events.contains { if case .fireballBurst = $0 { return true } else { return false } }
        for event in events {
            switch event {
            case .struck(let victim, let striker) where !fireballBurst:
                let at = players[victim].chest
                say(.hit, at: at, away: side(at, from: players[striker].chest), rise: 25)
            case .popped(let victim, let popper):
                let at = players[victim].heldBallPoint
                say(.steal, at: at, away: side(at, from: players[popper].chest), rise: 20)
            case .swatted(let index, hit: true):
                let at = match.ball.position
                say(.spike, at: at, away: side(at, from: players[index].chest), rise: -15)
            case .parried(let victim, let by):
                let at = players[victim].chest
                say(.parry, at: at, away: side(at, from: players[by].chest), rise: 25)
            case .slashClanked(let index):
                // Where the blade meets the wall, back off it.
                let player = players[index]
                say(.clang, at: player.chest + Vec2(x: player.facing.sign * GameScene.bladeReach, y: 0), away: -player.facing.sign, rise: 30)
            case .wallJumped(let index, let wall):
                // Out of the wall spark at the shoe, away from the wall.
                say(.squeak, at: players[index].position + Vec2(x: wall.sign * 4, y: 5), away: -wall.sign, rise: 15)
            case .beamFired(_, let from, let direction):
                let degrees = CGFloat(Trig.atan2(direction.y, abs(direction.x)) * 180 / .pi)
                say(.beam, at: from, away: direction.x < 0 ? -1 : 1, rise: degrees + 15)
            case .zBurst(let index, let at): say(.burst, at: at, away: players[index].facing.sign, rise: 25)
            case .quaked(let index): say(.quake, at: players[index].position, away: players[index].facing.sign, rise: 10)
            case .frozen(let index): say(.freeze, at: players[index].chest, away: players[index].facing.sign, rise: 20)
            case .fireballBurst(let at), .stageFireballBurst(let at): say(.explosion, at: at, away: 1, rise: 30)
            case .lavaBurned(let index): say(.sizzle, at: players[index].position, away: -players[index].facing.sign, rise: 20)
            case .lavaSplashed(let at, true): say(.sizzle, at: at, away: 1, rise: 20)
            case .icicleShattered(let at): say(.shatter, at: at, away: 1, rise: 20)
            case .lightningStruck(let at): say(.thunder, at: at, away: 1, rise: 30)
            case .ballBounced(let position, let speed) where speed > GameScene.bounceWordFloor:
                // Out of where it hit, the way it's going.
                say(.bounce, at: position, away: match.ball.velocity.x < 0 ? -1 : 1, rise: 20)
            default: break
            }
        }
    }

    /// A sample word in the middle of the screen, for trying the SFX picker's faces.
    private func previewSoundWord() {
        soundWords.removeAll { $0.parent == nil }
        say(.three, from: cameraNode.position, away: 1, rise: 15)
    }

    /// The 2X mark's height, and how far over the rim it stands, in art pixels.
    private static let doubleMarkHeight: CGFloat = 20
    private static let doubleMarkLift: CGFloat = 20
    private static let doubleMarkHoldSeconds = 1.2

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
        showFloMeters()
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
            screen = StageSelectScreen(halfWidth: halfWidth, halfHeight: halfHeight, stages: stageList.map { $0.name.uppercased() },
                                       voters: [0], localVoters: [0], colours: [0, 1].map { SKColor(rgb: sprites.look(for: $0).glow) },
                                       heading: nil, start: 0) { _, _ in }
        case .pick:
            screen = PickScreen(halfWidth: halfWidth, halfHeight: halfHeight, offers: Array(Greateraid.boosters.prefix(3)), drinks: .none,
                                colour: SKColor(rgb: sprites.look(for: 0).glow), timed: true) { _ in }
        case .pause:
            screen = PauseScreen(halfWidth: halfWidth, halfHeight: halfHeight, onRestart: {}, onSettings: {}, onTitle: {}, onResume: {})
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
            // The select lists only the stages not parked, by their place in it.
            let listed = stageList
            let select = StageSelectScreen(halfWidth: halfWidth, halfHeight: halfHeight, stages: listed.map { $0.name.uppercased() },
                                           voters: stageVoters, localVoters: localStageVoters, colours: colours, heading: heading,
                                           start: listed.firstIndex(of: series.stage) ?? 0) { [weak self] voter, index in
                self?.voteStage(listed.indices.contains(index) ? listed[index] : .wreckCenter, by: voter)
            }
            for (voter, vote) in stageVotes { select.show(vote: listed.firstIndex(of: vote) ?? 0, by: voter) }
            // Back to the title from the first pick offline, before anything's been played.
            if online == nil, series.stagesPlayed == 0 { select.back = { [weak self] in self?.enter(.title) } }
            screen = select
        case .paused:
            let pause = PauseScreen(halfWidth: halfWidth, halfHeight: halfHeight,
                                    onRestart: { [weak self] in self?.restartMatch() },
                                    onSettings: { [weak self] in self?.flowState?.openSettings() },
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
    /// A score digit's size in points, before the HUD's text scale.
    private static let scoreDigit = CGSize(width: 10, height: 20)
    /// Half the scoreboard plate's width, for the FLO meters either side of it.
    private var scorePlateHalfWidth: CGFloat = 60
    private func addHUDPlate(width: CGFloat, height: CGFloat) {
        let panels = UITuning.shared.scale(.hud, .panels)
        // A wider or narrower plate moves the meters out or in with it.
        let halfWidth = width * panels / 2
        if halfWidth != scorePlateHalfWidth {
            scorePlateHalfWidth = halfWidth
            if !floMeters.isEmpty { layoutFloMeters() }
        }
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
        threePointArcs.isHidden = (gameMode != .fortySeven && previewing != .hud) || match.stage.features.look == .wetshot
        for arc in threePointArcSides { arc.node.lineWidth = ThreePointTuning.lineWidth }
        if gameMode == .fortySeven {
            // 47: each side's points either side of the middle, in its colour, no circles, no drinks.
            for label in drinkLabels { label.text = "" }
            circles.removeAllChildren()
            circlesOverCam.removeAllChildren()
            // Each side's points in CardCourt's seven-segment digits, lit in its colour.
            let text = UITuning.shared.scale(.hud, .text)
            for (index, score) in fortySevenScores.enumerated() {
                let digits = SegmentDigits.texture(score, lit: sprites.look(for: index).glow,
                                                   digitSize: CGSize(width: GameScene.scoreDigit.width * text, height: GameScene.scoreDigit.height * text))
                let number = SKSpriteNode(texture: digits.texture, size: digits.size)
                // Its digits' near edge 12 off the middle, the glow's room past it.
                number.anchorPoint = CGPoint(x: index == 0 ? (digits.size.width - digits.pad) / digits.size.width : digits.pad / digits.size.width, y: 0.5)
                number.position = CGPoint(x: index == 0 ? -12 : 12, y: 0)
                circles.addChild(number)
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
    /// Both sides as last picked on the customize screen.
    func applySavedColours() {
        let sides = PlayerCustomization.sides
        applyColours(sides.map(\.energy), looks: sides.map(\.look))
    }

    /// The customize screen's player, in a side's look with its hooded head.
    func customizePortrait(player: Int) -> SpriteLibrary.Portrait? {
        // The second side is shown facing left.
        sprites.portrait("player_customize", player: sprites.bodyPlayer(player, facingLeft: player == 1), headDrawnFor: GameScene.hoodDrawnFor)
    }

    /// A side's hooded head alone, cut to what's drawn, for the customize screen's hood box.
    func customizeHood(player: Int) -> CGImage? {
        CustomizeArt.trimmed(sprites.hoodHead(skin: sprites.look(for: player).dressing.skinTone, player: player).drawn.cgImage())
    }

    /// Both sides' colours onto everything drawn in them, in `looks` where given.
    func applyColours(_ colours: [EnergyColour], looks: [Look]? = nil) {
        for (index, colour) in colours.enumerated() { sprites.setLook(looks.map { $0[index] } ?? colour.look, for: index) }
        sideColours = colours
        headStreamsCache = [:]
        for (index, flashes) in zip(stunBodies.indices, zip(stunBodies, stunHeads)) {
            let dark = SKColor(rgb: sprites.look(for: index).energyTone(luminance: 0.15))
            flashes.0.color = dark
            flashes.1.color = dark
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
        for frameEvents in frames {
            show(frameEvents.events)
            // FLO's orbs once a gain, a frame run again after a rollback bringing none more.
            for case .floGained(let player, let amount, let at) in frameEvents.events
                where floGainsShown.insert(FloGain(frame: frameEvents.frame, player: player)).inserted {
                spawnFloOrbs(for: player, amount: amount, at: at)
            }
            // Kept a while, and only from this match's run: a new one counts its frames from 0 again.
            floGainsShown = floGainsShown.filter { (0..<GameScene.floGainsKeptFrames).contains(frameEvents.frame - $0.frame) }
        }
    }
    private struct FloGain: Hashable {
        var frame: Int
        var player: Int
    }
    private var floGainsShown: Set<FloGain> = []
    private static let floGainsKeptFrames = 600

    // MARK: Sound

    /// The sounds for a frame's events, shown once like the effects.
    private func playSounds(_ events: [MatchEvent]) {
        func body(_ index: Int) -> Vec2 { match.players.indices.contains(index) ? match.players[index].position : match.ball.position }
        for event in events {
            switch event {
            case .jumped(let index), .doubleJumped(let index), .wallJumped(let index, _), .steppedBack(let index): play(.jump, at: body(index))
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
        // The dribble's bounce, under a loose ball's, and its word out of the floor under the ball.
        if GameScene.dribbleBounceFrames(of: frame.animation).contains(frame.frame) {
            play(.ballBounce, at: feet, volume: GameScene.dribbleVolume)
            if match.players.indices.contains(index), let offset = BallLandmarks.offset(frame) {
                let player = match.players[index]
                let ahead = Double(offset.x) / SpriteLibrary.pixelsPerUnit * player.spec.scale * player.facing.sign
                // Off a ledge it bounces on the floor below, where the ball's drawn reaching down to.
                let contact = player.overhangBall(in: match.stage).map { Vec2(x: $0.x, y: $0.y - BallRules.radius) }
                    ?? Vec2(x: feet.x + ahead, y: feet.y)
                soundWords.removeAll { $0.parent == nil }
                say(.dribble, at: contact, away: player.facing.sign, rise: 20)
            }
        }
    }

    /// The dribble's bounce at this share of a loose ball's, on the frames it meets the floor.
    private static let dribbleVolume: Float = 0.5
    private static var bounceFramesCache: [Animation: Set<Int>] = [:]
    private static func dribbleBounceFrames(of animation: Animation) -> Set<Int> {
        if let cached = bounceFramesCache[animation] { return cached }
        let frames = animation.dribbleBounceFrames()
        bounceFramesCache[animation] = frames
        return frames
    }

    /// The events of frames both sides' inputs have confirmed: the point.
    private func confirm(_ frames: [FrameEvents]) {
        for frameEvents in frames {
            for case .scored(let scorer, let hoop, let entry, let points, let floater) in frameEvents.events {
                rimFlash[hoop] = 8
                let dunk = dunkScoring
                // A three is a three before any doubling.
                let shotPoints = gameMode == .fortySeven && match.stage.features.doublePoints ? points / 2 : points
                strike(hoop: hoop, by: scorer, entry: entry)
                if gameMode == .fortySeven {
                    showBanner(shotPoints >= 3 ? "THREE!!" : "BUCKET!!", size: 48)
                    fortySevenScored(by: scorer, points: points, at: frameEvents.frame)
                } else {
                    showBanner("BUCKET!!", size: 48)
                    pointScored(by: scorer, at: frameEvents.frame)
                }
                if gameMode == .fortySeven, match.stage.features.doublePoints { showDoubleMark(at: hoop) }
                exclaimBasket(at: hoop, dunk: dunk, three: shotPoints >= 3)
                announce(dunk: dunk, three: gameMode == .fortySeven && shotPoints >= 3, floater: floater, winning: pendingFlow == .won)
            }
        }
    }

    private func show(_ events: [MatchEvent]) {
        playSounds(events)
        exclaim(events)
        for event in events {
            switch event {
            case .zBurst(let player, let at):
                let burst = EnergyEffect.burst.node(sprites, player: player, at: SpriteLibrary.point(at))
                // At its sheet's own size: stretched to the push's reach it scaled by a third, unevenly.
                glowers.addChild(burst)
            case .galeBurst(let at):
                // The burst's sheet once at its own size, not squeezed as the gale is.
                let frames = (0..<ElementsArt.burstFrames).map { sprites.texture("tornado_burst", $0) }
                let burst = SKSpriteNode(texture: frames[0])
                burst.size = CGSize(width: ElementsArt.burstSide, height: ElementsArt.burstSide)
                burst.position = SpriteLibrary.point(at)
                burst.zPosition = -1
                burst.run(.sequence([.animate(with: frames, timePerFrame: 1 / Double(TornadoRules.burstSheetFramesPerSecond)), .removeFromParent()]))
                glowers.addChild(burst)
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
                    spark.xScale *= 0.75 * bodyScale(index)
                    spark.yScale *= 0.75 * bodyScale(index)
                    glowers.addChild(spark)
                }
                if player.power == .frostTea { spawnSnowflakes(at: SpriteLibrary.point(player.position), count: 3, spread: 10) }
            case .dashed(let index), .slid(let index):
                let player = match.players[index]
                if player.power == .blazingBoba {
                    spawn(.fireDash, at: player.position, flipped: player.facing == .left, scale: bodyScale(index))
                } else {
                    spawn(.smoke, at: player.position, flipped: player.facing == .left, player: index, scale: bodyScale(index))
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
                    let spark = Effect.catchSpark.node(sprites, at: SpriteLibrary.point(player.position + offset), flipped: player.facing == .left, player: index)
                    glowers.addChild(spark)
                    riders.append((spark, index, offset))
                }
            case .popped(let victim, let popper):
                // A spark off the ball as it leaves the hands, in the colour of whoever knocked it.
                spawnHitSpark(player: popper, at: match.players[victim].heldBallPoint)
            case .swatted(let index, hit: true):
                spawnHitSpark(player: index, at: match.ball.position)
            case .slashClanked(let index):
                // The blade against a backboard shakes it.
                let player = match.players[index]
                shakeBackboard(at: player.chest + Vec2(x: player.facing.sign * GameScene.bladeReach, y: 0))
            case .wallJumped(let index, let wall):
                let player = match.players[index]
                // Off a backboard, it shakes.
                shakeBackboard(at: Vec2(x: player.position.x + wall.sign * (player.spec.bodyWidth / 2 + 1), y: player.chest.y))
                // The sheet's spark flies left, away from a wall on the right.
                // Blazing Boba's is the fire skid sheet; everyone else's the fire wall spark as
                // a silhouette in their energy. Both painted the other way round from the old spark.
                let at = SpriteLibrary.point(player.position + Vec2(x: wall.sign * 4, y: 5))
                if player.power == .blazingBoba {
                    spawn(.fireSkid, at: player.position + Vec2(x: wall.sign * 4, y: 5), flipped: wall == .right, scale: bodyScale(index))
                } else {
                    let frames = (0..<Effect.fireWallSpark.frameCount).map { sprites.silhouetteTexture(Effect.fireWallSpark.name, $0, player: index) }
                    let spark = SKSpriteNode(texture: frames[0])
                    spark.anchorPoint = Effect.fireWallSpark.anchor
                    spark.position = at
                    spark.xScale = (wall == .right ? -1 : 1) * Effect.fireWallSpark.scale * bodyScale(index)
                    spark.yScale = Effect.fireWallSpark.scale * bodyScale(index)
                    spark.zPosition = 30
                    spark.run(.sequence([.animate(with: frames, timePerFrame: 1 / Effect.fireWallSpark.fps), .removeFromParent()]))
                    glowers.addChild(spark)
                }
                if player.power == .frostTea { spawnSnowflakes(at: SpriteLibrary.point(player.position + Vec2(x: 0, y: 5)), count: 4, spread: 10) }
            case .caught(let index):
                let player = match.players[index]
                spawn(.catchSpark, at: player.position + Vec2(x: player.facing.sign * 2, y: 0), flipped: player.facing == .left, player: index)
            case .rimBounced(let hoop, let speed, let ball):
                if hoop < rimSpin.count { rimSpin[hoop] += CGFloat(speed) * RimLook.kickPerSpeed }
                if ball, hoop < rimJitter.count { rimJitter[hoop] = RimLook.jitterFrames }
            case .ballBounced(let position, let speed) where speed > GameScene.bounceSoundFloor:
                if let hoop = backboard(at: position), hoop < boardJitter.count { boardJitter[hoop] = RimLook.jitterFrames }
            case .doubleJumped(let index):
                let player = match.players[index]
                spawnJumpRings(at: SpriteLibrary.point(player.position), colour: SKColor(rgb: sprites.look(for: index).glow), scale: bodyScale(index))
            case .warped(let flasher, let from, let to), .flashed(let flasher, let from, let to):
                // The flash sheet at both ends, in the energy colour, at its own size.
                // Drawn over rather than added, or the white saturates past the tone.
                for end in [from, to] {
                    let point = SpriteLibrary.point(end + Vec2(x: 0, y: BallRules.chestHeight))
                    let flash = EnergyEffect.flashSpark3.node(sprites, player: flasher, at: point)
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
            case .lavaSplashed(let at, let isBall):
                splashLava(at: at, ball: isBall)
            case .icicleShattered(let at):
                shatterIcicle(at: at)
            case .lightningFlashed:
                flashLightning()
            case .lightningStruck(let at):
                strikeLightning(at: at)
            case .tornadoBurned(let at):
                splashLava(at: at, ball: false, splash: false)
            case .stageFireballBurst(let at):
                play(.fireHit, at: at)
                glowers.addChild(Effect.fireExplosion.node(sprites, at: SpriteLibrary.point(at), flipped: false))
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
    /// A rim's turn as drawn, in radians: its dip, down at the front, whichever side its backboard is.
    /// The backboard at a point, if there is one there, shaken as a ball off it shakes it.
    private func shakeBackboard(at point: Vec2) {
        if let hoop = backboard(at: point), hoop < boardJitter.count { boardJitter[hoop] = RimLook.jitterFrames }
    }

    /// A shake's offset with this many frames left: a pixel one way, then the other, none at the end.
    private static func shake(_ framesLeft: Int) -> CGFloat {
        framesLeft == 0 ? 0 : (framesLeft % 4 < 2 ? 1 : -1)
    }

    /// The hoop whose backboard a ball bounced against here: on its backboard side, from the
    /// board's face out past its back, from under its bottom up the board's height.
    private func backboard(at position: Vec2) -> Int? {
        match.stage.hoops.indices.first { index in
            let hoop = match.stage.hoops[index]
            let out = (position.x - hoop.position.x) * hoop.backboard.sign
            let up = position.y - hoop.position.y
            return out >= Stage.backboardFace - BallRules.radius - 1 && out <= Stage.backboardFace + Stage.backboardDepth + BallRules.radius + 1
                && up >= Stage.backboardBottom - BallRules.radius - 1 && up <= RimLook.boardHeight
        }
    }

    private func rimTurn(_ index: Int) -> CGFloat {
        guard index < rimDip.count, index < match.stage.hoops.count else { return 0 }
        return rimDip[index] * .pi / 180 * CGFloat(match.stage.hoops[index].backboard.sign)
    }

    /// Where a rim turns: its art's back edge, on the backboard, in the scene.
    private func rimPivot(_ index: Int) -> CGPoint {
        let look = match.stage.features.look
        let hoop = match.stage.hoops[index]
        let art = GameScene.hoopArtPoint(for: hoop, on: look)
        let pivot = HoopTuning.pivot(for: look)
        let size = rimNodes.indices.contains(index) ? rimNodes[index].size : CGSize(width: 48, height: 48)
        return CGPoint(x: art.x + (pivot.x - 0.5) * abs(size.width) * CGFloat(hoop.backboard.sign), y: art.y + (pivot.y - 0.5) * abs(size.height))
    }

    private func rotated(_ point: CGPoint, about centre: CGPoint, by angle: CGFloat) -> CGPoint {
        let dx = point.x - centre.x, dy = point.y - centre.y
        return CGPoint(x: centre.x + dx * cos(angle) - dy * sin(angle), y: centre.y + dx * sin(angle) + dy * cos(angle))
    }

    /// A body's drawn size against a plain one's: Titan Tea's, grown into after its port-in.
    /// Its sparks, rings and cubes are drawn at it too.
    private func bodyScale(_ index: Int) -> CGFloat {
        guard match.players.indices.contains(index), titanGrowth.indices.contains(index) else { return 1 }
        return 1 + (CGFloat(match.players[index].spec.scale) - 1) * titanGrowth[index]
    }

    private func spawnJumpRings(at point: CGPoint, colour: SKColor, scale: CGFloat = 1) {
        for ring in 0..<GameScene.jumpRingCount {
            let size = CGSize(width: GameScene.jumpRingSize.width * scale, height: GameScene.jumpRingSize.height * scale)
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
    /// the same tone and the floor and walls go white, fading back. `score_strike` erupts off
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

        let crown = EnergyEffect.scoreStrike.node(sprites, player: scorer, at: rim)
        crown.zPosition = 46
        glowers.addChild(crown)
    }

    private func line(from a: CGPoint, to b: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    /// The body where it is, in its colour's bright version, held a moment then fading behind
    /// it: the stepback's trail (and the jump shot's, the throw's, the slash's), as Zeus Juice's bolt leaves one.
    private static let afterimageAlpha: CGFloat = 0.9
    private var slashAfterimages: [Int: Int] = [:]
    private static let afterimageHold = 0.1
    private static let afterimageFade = 0.3
    private func spawnAfterimage(of body: SKSpriteNode, player index: Int, colour: SKColor? = nil) {
        guard let texture = body.texture else { return }
        let ghost = SKSpriteNode(texture: texture)
        ghost.size = CGSize(width: abs(body.size.width), height: abs(body.size.height))
        ghost.anchorPoint = body.anchorPoint
        ghost.position = body.position
        ghost.xScale = body.xScale
        ghost.zRotation = body.zRotation
        ghost.color = colour ?? SKColor(rgb: sprites.look(for: index).bright)
        ghost.colorBlendFactor = 1
        ghost.alpha = GameScene.afterimageAlpha
        ghost.zPosition = -1
        bodies.addChild(ghost)
        ghost.run(.sequence([.wait(forDuration: GameScene.afterimageHold), .fadeOut(withDuration: GameScene.afterimageFade), .removeFromParent()]))
    }

    private func spawn(_ effect: Effect, at position: Vec2, flipped: Bool, player: Int? = nil, scale: CGFloat = 1) {
        let node = effect.node(sprites, at: SpriteLibrary.point(position), flipped: flipped, player: player)
        node.xScale *= scale
        node.yScale *= scale
        glowers.addChild(node)
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
        /// Spiralling round the body this far out while a change is on, rather than rising.
        var helixRadius: CGFloat?
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
        /// Rising round a line straight up while its body changes: the line's x, how far out, how far round.
        var helix: (centreX: CGFloat, radius: CGFloat, angle: Double, rise: CGFloat)?
    }

    private var headParticles: [HeadParticle] = []

    /// The cube particles as the Metal layer draws them: where each is, turned, at its
    /// dissolve's size, in its colour and fade.
    var cubeInstances: [CubeInstance] {
        headParticles.compactMap { particle in
            guard let cube = particle.cube else { return nil }
            let node = particle.node
            let size = (particle.legCube ? ParticleLook.legCubeSize : ParticleLook.cubeSize) * Float(node.xScale) * Float(bodyScale(particle.owner))
            let model = simd_float4x4.translation(SIMD3<Float>(Float(node.position.x), Float(node.position.y), 0))
                * simd_float4x4(cube.orientation) * simd_float4x4.scale(SIMD3<Float>(repeating: size))
            var colour = cube.colour
            colour.w = Float(node.alpha)
            return CubeInstance(model: model, color: colour, flags: SIMD4<Float>(particle.behind ? 1 : 0, 0, 0, 0))
        } + (NetTuning.cylinder ? nets.enumerated().flatMap { index, net in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            net.colour.getRed(&r, green: &g, blue: &b, alpha: &a)
            // Hung from the rim as it's turned, and turned with it.
            let turn = index < rimDip.count ? rimTurn(index) : 0
            let top = index < rimDip.count ? rotated(net.hangPoint, about: rimPivot(index), by: turn) : net.hangPoint
            return CylinderNet.instances(top: top, turn: turn, mirrored: net.mirrored, sways: net.rowSways, spreads: net.rowSpreads, flare: net.dunkFlare, swish: net.swishWeight,
                                         colour: SIMD4<Float>(Float(r), Float(g), Float(b), 1))
        } : [])
    }

    /// The rims' art, for the net behind them to keep out of.
    var rimSnapshots: [BodySnapshot] {
        rimNodes.filter { !$0.isHidden }.compactMap { rim in
            rim.texture.map { BodySnapshot(texture: $0, position: rim.position, anchor: rim.anchorPoint, xScale: rim.xScale, size: rim.size, zRotation: rim.zRotation) }
        }
    }
    /// A leg's cubes, in the leg's own colour, the back leg's behind the players; each leg's
    /// credit apart from the head's.
    private static let legCreditKey = 1000
    /// From the head's middle up to its crown, where its particles leave, in art pixels at a plain body's size.
    static let crownLift: CGFloat = 4
    /// In the colour of the part as the body is drawn (`drawnAs`, turned round or not).
    private func legStream(_ index: Int, part: BodyPart, energyColour: Bool = false, drawnAs: Int? = nil) -> HeadStream {
        let look = sprites.look(for: drawnAs ?? index)
        return HeadStream(frames: [sprites.flatSquare(size: 4, alpha: 1)], size: ParticleLook.energySize,
                          tint: SKColor(rgb: energyColour ? look.glow : (look.colours[part] ?? look.glow)), rate: Double(ParticleLook.legCubeRate),
                          zoneTinted: true, cubes: true, legs: true, behind: part.isBack)
    }

    /// The change into the energy form, as drawn: lifted off the ground, all white on the
    /// sheet's fifth frame and the energy form from its sixth; cubes spiralling up round the
    /// body until then, and the head's and legs' cubes rising in a helix.
    private static let transformLift: CGFloat = 7
    private static let transformWhiteFrame = 4
    private static let transformEnergyFrame = 5
    private static let transformCreditKey = 2000
    private static let vortexCreditKey = 3000
    private static let transformSpiralRate = 30.0
    /// Into or out of FloState, how many frames the cubes swirl round the body.
    private static let floSwirlFrames = 30
    private var wasInFloState: [Int: Bool] = [:]
    private var lastChangeBurstDue: [Int: Bool] = [:]
    /// The change's frame its burst starts on: its third (0-based 2).
    private static let transformBurstFrame = 2
    private var floSwirlFrames: [Int: Int] = [:]
    /// Rising round the body in a helix: while it changes, up to the energy form, and while it swirls.
    private func spiralling(_ index: Int) -> Bool {
        guard match.players.indices.contains(index) else { return false }
        let player = match.players[index]
        return (player.state == .transforming && player.animationFrame.frame < GameScene.transformEnergyFrame) || floSwirlFrames[index, default: 0] > 0
            || hoverVortex(index)
    }
    /// Super Smoothie hovering still: cubes off the hanging foot in a vortex, widening round
    /// the body as they rise.
    private func hoverVortex(_ index: Int) -> Bool {
        guard match.players.indices.contains(index) else { return false }
        let player = match.players[index]
        return player.power == .superSmoothie && player.state == .flying && player.velocity.length < GameScene.hoverStill
    }
    private static let hoverStill = 0.2
    private static let vortexRate = 30.0
    /// The vortex's width at the foot and the top, and halfway up, where it's widest.
    private static let vortexStartRadius: CGFloat = 2
    private static let vortexWidestRadius: CGFloat = 18
    private static let transformSpiralRadius: CGFloat = 10
    private static let transformHelixRadius: CGFloat = 3
    private static let helixTurnsPerSecond = 2.0
    /// The Elements' wind on the nets: the push at their bottom, and how fast it gusts.
    private static let netWind: CGFloat = 0.4
    private static let netGustRate = 1.3
    /// Every other stage's breeze: the push at the nets' bottom, either way.
    private static let netBreeze: CGFloat = 0.1
    private static let spiralRise: CGFloat = 50

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
                // In the zone a head's particles come out in the zone's colours, and in FloState.
                let inFloState = match.players.indices.contains(index) && match.players[index].inFloState
                let zoneTint = (ZoneTuning.inTheZone || inFloState) && stream.zoneTinted && trailing == nil ? ZoneTuning.colours.randomElement().map { SKColor(rgb: $0) } : nil
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
                let life = frames.count > 1 ? Double(frames.count) / 24
                    : (cube != nil ? cubeTrail(index) / speed : 0.6) + Double.random(in: -0.05...0.05)
                // While its body changes, it rises in a helix rather than straight.
                var helix: (centreX: CGFloat, radius: CGFloat, angle: Double, rise: CGFloat)?
                if trailing == nil, spiralling(index) {
                    let radius = stream.helixRadius ?? GameScene.transformHelixRadius
                    helix = (point.x, radius, Double.random(in: 0..<(2 * .pi)), stream.helixRadius == nil ? CGFloat(speed) : GameScene.spiralRise)
                }
                headParticles.append(HeadParticle(node: node, owner: index, velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                                                  age: 0, life: life, frames: frames,
                                                  startFrame: Int.random(in: 0..<frames.count), drifts: trailing == nil, cube: cube, legCube: stream.legs,
                                                  behind: stream.behind, helix: helix))
            }
        }
        headCredit[creditKey] = credit
    }

    /// How far a player's cube trails run: the slider's base, and a point more for each 10 FLO
    /// they have, to 14 at full.
    private func cubeTrail(_ index: Int) -> Double {
        let flo = match.players.indices.contains(index) ? match.players[index].flo : 0
        // In FloState, always the longest.
        if match.players.indices.contains(index), match.players[index].inFloState { return ParticleLook.cubeTrailMost }
        return min(Double(ParticleLook.cubeTrail) + Double(flo / 10), ParticleLook.cubeTrailMost)
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
            if var helix = particle.helix {
                if spiralling(particle.owner) {
                    // Swirling, it goes round the body wherever the body goes; in the hover's
                    // vortex, widening as it rises.
                    let vortex = hoverVortex(particle.owner)
                    if floSwirlFrames[particle.owner, default: 0] > 0 || vortex {
                        helix.centreX = SpriteLibrary.point(match.players[particle.owner].position).x
                    }
                    // The vortex bellies out: narrow at the foot, widest halfway up, narrowing to the top.
                    if vortex {
                        let share = min(particle.age / max(particle.life, 0.001), 1)
                        helix.radius = GameScene.vortexStartRadius + (GameScene.vortexWidestRadius - GameScene.vortexStartRadius) * CGFloat(sin(share * .pi))
                    }
                    helix.angle += 2 * .pi * GameScene.helixTurnsPerSecond * step
                    particle.node.position = CGPoint(x: helix.centreX + CGFloat(cos(helix.angle)) * helix.radius,
                                                     y: particle.node.position.y + helix.rise * CGFloat(step))
                    particle.helix = helix
                } else {
                    // The change done, it rises on as the rest do.
                    particle.helix = nil
                    particle.velocity = CGVector(dx: 0, dy: helix.rise)
                }
            } else if particle.drifts {
                // Flowing toward the ball along x: a steady push, easing off as the body and the
                // ball come level. With the ball in hand, one swinging wind instead.
                var flow = 0.0
                if match.stage.features.look == .elements {
                    // The Elements' wind blows it all leftward.
                    flow = -Double(ParticleLook.flowSpeed)
                } else if match.players.indices.contains(particle.owner), match.players[particle.owner].hasBall {
                    flow = sin(Double(match.frame) / 60 * 2 * .pi * ParticleLook.swayPerSecond + Double(particle.owner) * 2) * Double(ParticleLook.flowSpeed)
                } else if match.players.indices.contains(particle.owner) {
                    let gap = Double(SpriteLibrary.point(match.ball.position).x - SpriteLibrary.point(match.players[particle.owner].position).x)
                    flow = min(max(gap / Double(ParticleLook.flowEaseDistance), -1), 1) * Double(ParticleLook.flowSpeed)
                }
                particle.velocity.dx += flow * step
                particle.velocity.dy += 10 * step
            }
            if particle.helix == nil {
                particle.node.position = CGPoint(x: particle.node.position.x + particle.velocity.dx * step,
                                                 y: particle.node.position.y + particle.velocity.dy * step)
            }
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

    /// Where the camera wants to be on a scrolling stage: the local player, led by where they're
    /// heading, kept inside the stage's ends.
    private func cameraTargetX() -> CGFloat {
        guard match.players.indices.contains(localIndex) else { return cameraBase.x }
        let player = match.players[localIndex]
        // The lead eased, so a speed that keeps flipping, as against a slide slope, doesn't shake it.
        let lead = CGFloat(player.velocity.x) * GameScene.cameraLeadFrames * CGFloat(SpriteLibrary.pixelsPerUnit)
        cameraLead += (lead - cameraLead) * GameScene.cameraLeadEase
        let wanted = SpriteLibrary.point(player.position).x + cameraLead
        let halfView = size.width * cameraNode.xScale / 2
        let width = CGFloat(match.stage.columns) * GameScene.pixelsPerTile
        return min(max(wanted, halfView), max(width - halfView, halfView))
    }
    private static let cameraEase: CGFloat = 0.08
    private static let cameraLeadFrames: CGFloat = 20
    private static let cameraLeadEase: CGFloat = 0.05
    private var cameraLead: CGFloat = 0

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
        // Whatever rides the body turns with it: the ball in hand, its glow, the energy, the
        // charge, the hooded head and its flashes and strings, the stun's and lockout's copies.
        for rider in [handBalls[index], handHalos[index], energyNodes[index], chargeNodes[index], hoodNodes[index], hoodFlashes[index],
                      lockoutHoods[index], lockoutClothes[index], stunBodies[index], stunHeads[index], eyesNodes[index]] where !rider.isHidden {
            rider.position = turned(rider.position + CGPoint(x: 0, y: bob))
            rider.zRotation += angle
        }
        hoodStrings[index].move { turned($0 + CGPoint(x: 0, y: bob)) }
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
    /// The whole stage on screen at once, for the map maker.
    private var wholeStageView = false
    #if !os(tvOS)
    /// The map maker, while it's open, and where the pointer last was in it.
    private var mapEditor: MapEditor?
    private var lastEditorPoint = CGPoint.zero

    private func openMapEditor() {
        let look = match.stage.features.look
        let mapStage: MapStage
        switch look {
        case .elements: mapStage = .elements
        case .wetshot: mapStage = .wetshot
        case .flight: mapStage = .flight
        default: return
        }
        guard mapEditor == nil, online == nil else { return }
        let rebuilt: () -> Stage = {
            switch mapStage {
            case .elements: .elements
            case .wetshot: .wetshot
            case .flight: .flight
            }
        }
        wholeStageView = true
        layout(displayScale: displayScale)
        let scale = hudScale * cameraNode.xScale
        let editor = MapEditor(
            stage: mapStage, map: StageMap.current[mapStage], halfWidth: size.width / 2 / hudScale, halfHeight: size.height / 2 / hudScale, unitsPerHud: scale,
            world: { [weak self] point in
                guard let self else { return .zero }
                return CGPoint(x: self.cameraNode.position.x + point.x * scale, y: self.cameraNode.position.y + point.y * scale)
            },
            hudFromWorld: { [weak self] point in
                guard let self else { return .zero }
                return CGPoint(x: (point.x - self.cameraNode.position.x) / scale, y: (point.y - self.cameraNode.position.y) / scale)
            },
            onTiles: { [weak self] cells in
                guard let self else { return }
                let map = StageMap.current[mapStage]
                for cell in cells {
                    for layer in StageMap.layers {
                        let placed = map.tiles.first { $0.cell == cell && $0.layer == layer }
                        self.elementsArt?.set(placed, at: cell, layer: layer)
                        self.flightArt?.set(placed, at: cell, layer: layer)
                    }
                }
                self.refreshStaticFlats()
                self.session.mutate { match in
                    match.stage = rebuilt()
                    match.refreshExtras()
                }
            },
            onMarkers: { [weak self] in self?.session.mutate { $0.stage = rebuilt(); $0.refreshExtras() } },
            onTornados: { [weak self] in
                self?.elementsArt?.setTornados(StageMap.current[.elements].tornados)
                self?.session.mutate { $0.stage = rebuilt(); $0.refreshExtras() }
            },
            onProps: { [weak self] in
                // The Hoopfish carries the rim: the stage again, for where it now is.
                self?.wetshotArt?.setProps(StageMap.current[.wetshot].props)
                self?.wetshotArt?.setPile(StageMap.current[.wetshot].pile)
                self?.refreshStaticFlats()
                self?.session.mutate { $0.stage = rebuilt(); $0.refreshExtras() }
            },
            onWalls: { [weak self] in self?.session.mutate { $0.stage = rebuilt(); $0.refreshExtras() } },
            onClose: { [weak self] in self?.closeMapEditor(restart: true) })
        hud.addChild(editor)
        mapEditor = editor
    }

    /// The hoop support builder, while it's open.
    private var supportBuilder: SupportBuilder?

    private func openSupportBuilder() {
        guard supportBuilder == nil, online == nil, match.stage.features.look == .court,
              let right = match.stage.hoops.first(where: { $0.backboard == .right }) else { return }
        let scale = hudScale * cameraNode.xScale
        let artPoint = { [weak self] in
            GameScene.hoopArtPoint(for: self?.match.stage.hoops.first { $0.backboard == .right } ?? right, on: .court)
        }
        let builder = SupportBuilder(
            top: controls?.slidersBottom ?? size.height / 2 / hudScale - 40, artPixelsPerHud: scale,
            rimDrop: Stage.courtRimDrop, rimDepth: Stage.courtRimDepth, blockShift: Stage.courtBlockShift,
            fromHud: { [weak self] point in
                guard let self else { return .zero }
                return CGPoint(x: self.cameraNode.position.x + point.x * scale, y: self.cameraNode.position.y + point.y * scale) - artPoint()
            },
            toHud: { [weak self] art in
                guard let self else { return .zero }
                let world = art + artPoint()
                return CGPoint(x: (world.x - self.cameraNode.position.x) / scale, y: (world.y - self.cameraNode.position.y) / scale)
            },
            onChange: { [weak self] pieces in self?.refreshSupports(pieces) },
            onMoveRims: { [weak self] drop, depth in
                if let drop { Stage.courtRimDrop = drop }
                if let depth { Stage.courtRimDepth = depth }
                self?.moveCourtRims()
            },
            onMoveBlocks: { [weak self] toWall, up in
                if let toWall { Stage.courtBlockShift.toWall = toWall }
                if let up { Stage.courtBlockShift.up = up }
                self?.moveCourtBlocks()
            },
            onClose: { [weak self] in self?.closeSupportBuilder() })
        hud.addChild(builder)
        supportBuilder = builder
    }

    private func closeSupportBuilder() {
        supportBuilder?.removeFromParent()
        supportBuilder = nil
    }

    private func closeMapEditor(restart: Bool = false) {
        guard mapEditor != nil else { return }
        mapEditor?.removeFromParent()
        mapEditor = nil
        wholeStageView = false
        cameraBase = .zero
        layout(displayScale: displayScale)
        // Back to play from where everyone starts, on the map as it now is.
        if restart { reset() }
    }
    #else
    private func closeMapEditor(restart: Bool = false) {}
    private func closeSupportBuilder() {}
    #endif

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

    /// Each car as its wheels and its body over them, by the sim's id; frames of the dip
    /// after a landing.
    private var carNodes: [Int: (body: SKSpriteNode, wheels: SKSpriteNode?)] = [:]
    private var carDip: [Int: Int] = [:]
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

    /// The art drawn from vectors made now, before play, and sent to the GPU: the sound words,
    /// the board, the helmets in both colours, and on the highway every vehicle and the
    /// helicopter in its rims' colours. Each is drawn once and kept, not on its first appearance.
    private func warmDrawnArt() {
        var made: [SKTexture] = Onomatopoeia.warmed()
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
                // Each part lined round, the line just under its own part.
                for (part, node) in [("body", body), ("wheels", wheels)] {
                    guard let node, let line = HighwayArt.outline("vehicle_\(art)_\(part)", art: art, size: size) else { continue }
                    let outline = SKSpriteNode(texture: line)
                    outline.size = CGSize(width: line.size().width, height: line.size().height)
                    outline.anchorPoint = CGPoint(x: 0.5, y: 1 / line.size().height)
                    outline.zPosition = -0.05
                    node.addChild(outline)
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
            nodes.body.color = .black
            nodes.body.colorBlendFactor = car.level == 1 ? GameScene.farLaneShade : 0
        }
        for (id, nodes) in carNodes where !seen.contains(id) {
            nodes.body.removeFromParent()
            nodes.wheels?.removeFromParent()
            carNodes[id] = nil
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
        // Under the backboard, the net and the rim it carries.
        node.zPosition = 4.5
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
    /// own frame, laid out on a grid sheared to the crossbar's lean: its bottom where the
    /// first board's 4 rows had it, and as many rows up from there as reach the uprights' tops.
    private func buildBackboards() {
        backboards.removeAllChildren()
        let frameCount = EffectSheets.frames[EnergyEffect.flashSpark2.name] ?? 1
        for hoop in match.stage.hoops {
            let owner = 1 - hoop.owner
            let frames = sprites.effectFrames(EnergyEffect.flashSpark2, player: owner)
            let back = CGFloat(hoop.backboard.sign)
            let rim = SpriteLibrary.point(hoop.position)
            let shear = tan(GoalpostTuning.crossbarAngle * .pi / 180) * -back
            let step = BackboardTuning.spacing * BackboardTuning.size * 2
            // The uprights' tops where the cluster stands: the crossbar there, and the prongs over it.
            let postX = hoop.backboard == .left ? Stage.fieldPostInset : match.stage.width - Stage.fieldPostInset
            let post = SpriteLibrary.point(Vec2(x: postX, y: GoalpostTuning.postRimHeight))
            let x = rim.x + back * BackboardTuning.x
            let top = post.y - GoalpostTuning.crossbarBelowRim + (x - post.x) * shear + GoalpostTuning.prongHeight
            let bottom = rim.y + BackboardTuning.y - CGFloat(BackboardTuning.rows - 1) * step / 2
            let rows = max(Int((top - bottom) / step) + 1, 1)
            let centre = CGPoint(x: x, y: bottom + CGFloat(rows - 1) * step / 2)
            let cluster = flashCluster(frames: frames, frameCount: frameCount, columns: BackboardTuning.columns, rows: rows,
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
    /// A grey energy frame toned as `Look.sparkTone` does: black to the colour over the
    /// dark half, the colour itself over the light half, never lighter; the colour each
    /// node's own `a_glow`.
    private lazy var energyToneShader: SKShader = {
        let shader = SKShader(source: """
        void main() {
            vec4 texel = texture2D(u_texture, v_tex_coord);
            float level = texel.a > 0.0 ? texel.r / texel.a : 0.0;
            vec3 toned = level <= 0.5 ? a_glow * (level * 2.0) : a_glow;
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
                // Drawn in the ice look.
                let ice = SpriteLibrary.icePlayer
                let node = SKSpriteNode(texture: sprites.texture(frame, player: ice))
                node.size = node.texture!.size()
                if let outline = sprites.outlineTexture(frame, player: ice) {
                    // Its line too, in the ice look's.
                    let line = SKSpriteNode(texture: outline)
                    line.size = node.size
                    line.anchorPoint = sprites.anchor(for: frame.animation)
                    line.color = SKColor(rgb: Look.ice.outline)
                    line.colorBlendFactor = 1
                    line.zPosition = 0.1
                    node.addChild(line)
                }
                node.anchorPoint = sprites.anchor(for: frame.animation)
                node.xScale = CGFloat(owner.facing.sign)
                node.alpha = 0.8
                node.position = SpriteLibrary.point(Vec2(x: clone.box.center.x, y: clone.box.min.y))
                node.zPosition = 6
                // Its hooded head in the ice look, placed as the player's is, moved from the idle
                // frame it's drawn for by how far the head is from there; the body's space is already flipped.
                if let now = sprites.landmark(.head, in: frame, player: clone.owner),
                   let drawnFor = sprites.landmark(.head, in: GameScene.hoodDrawnFor, player: clone.owner) {
                    let texture = sprites.hoodHead(skin: sprites.look(for: clone.owner).dressing.skinTone, player: ice).drawn
                    let hood = SKSpriteNode(texture: texture)
                    hood.size = texture.size()
                    hood.anchorPoint = sprites.anchor(for: GameScene.hoodDrawnFor.animation)
                    hood.position = now - drawnFor
                    hood.zPosition = 1
                    node.addChild(hood)
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
        let galeFrame = Int(CACurrentMediaTime() / ElementsArt.tornadoFrameSeconds)
        for gale in match.gales {
            seen.insert(gale.id)
            let node = galeNodes[gale.id] ?? {
                let made = SKSpriteNode(texture: sprites.texture("tornado", 0))
                made.size = CGSize(width: ElementsArt.tornadoSide * GameScene.galeScale.width, height: ElementsArt.tornadoSide * GameScene.galeScale.height)
                made.zPosition = -1
                glowers.addChild(made)
                galeNodes[gale.id] = made
                return made
            }()
            node.texture = sprites.texture("tornado", (galeFrame + gale.id) % ElementsArt.tornadoFrames)
            node.position = SpriteLibrary.point(gale.box.center)
        }
        for (id, node) in galeNodes where !seen.contains(id) {
            node.removeFromParent()
            galeNodes[id] = nil
        }

        // Z Tea's beams: the tail at the hand, the middle stretched along, the head at the end,
        // in the firer's energy colour, over a soft halo in their glow colour.
        seen = []
        for beam in match.beams {
            seen.insert(beam.id)
            let holder = beamNodes[beam.id] ?? {
                let made = SKNode()
                made.zPosition = 8
                // The halo's ends are a soft glow's halves, its middle the glow's centre column stretched.
                let glow = sprites.softGlow(diameter: 32)
                for rect in [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 1.0 / 32, height: 1),
                             CGRect(x: 0.5, y: 0, width: 0.5, height: 1)] {
                    let halo = SKSpriteNode(texture: SKTexture(rect: rect, in: glow))
                    halo.anchorPoint = CGPoint(x: 0, y: 0.5)
                    halo.color = SKColor(rgb: sprites.look(for: beam.owner).glow)
                    halo.colorBlendFactor = 1
                    halo.alpha = GameScene.beamGlow
                    halo.blendMode = .add
                    halo.zPosition = -0.1
                    made.addChild(halo)
                }
                for piece in 0..<3 {
                    let sprite = SKSpriteNode(texture: sprites.effectTexture(EnergyEffect.beam.name, piece, player: beam.owner))
                    sprite.anchorPoint = CGPoint(x: 0, y: 0.5)
                    made.addChild(sprite)
                }
                glowers.addChild(made)
                beamNodes[beam.id] = made
                return made
            }()
            let length = CGFloat(beam.reach) * SpriteLibrary.pixelsPerUnit
            let side = GameScene.beamPieceSide
            if let nodes = holder.children as? [SKSpriteNode], nodes.count == 6 {
                let halos = nodes[0..<3], pieces = nodes[3..<6]
                let haloSide = side * GameScene.beamGlowWidth
                let haloStart = -(haloSide - side) / 2
                let haloMiddle = max(CGFloat(length) - side, 0)
                let spans: [(x: CGFloat, width: CGFloat)] = [(haloStart, haloSide / 2), (haloStart + haloSide / 2, haloMiddle),
                                                             (haloStart + haloSide / 2 + haloMiddle, haloSide / 2)]
                for (halo, (x, width)) in zip(halos, spans) {
                    halo.size = CGSize(width: width, height: haloSide)
                    halo.position = CGPoint(x: x, y: 0)
                }
                let piece = Array(pieces)
                piece[0].size = CGSize(width: side, height: side)
                piece[0].position = .zero
                piece[1].size = CGSize(width: max(length - side * 2, 0), height: side)
                piece[1].position = CGPoint(x: side, y: 0)
                piece[2].size = CGSize(width: side, height: side)
                piece[2].position = CGPoint(x: length - side, y: 0)
            }
            holder.position = SpriteLibrary.point(beam.origin)
            holder.zRotation = CGFloat(Trig.atan2(beam.direction.y, beam.direction.x))
        }
        for (id, node) in beamNodes where !seen.contains(id) {
            node.removeFromParent()
            beamNodes[id] = nil
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
                let node = SKSpriteNode(texture: sprites.basketballFireFrames[0])
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
        // Hit-stop holds the world's look with the match: every effect's action, the orbs, the
        // cubes, the strings and the water's life, not only the bodies.
        let held = match.hitStop > 0
        world.speed = held ? 0 : 1
        strokeFloMeters()
        stepFloSparkles()
        if !held { stepFloOrbs() }
        updateFloMeters()
        drawFloBundles()
        for index in floFlash.indices where floFlash[index] > 0 { floFlash[index] -= 1 }
        if !held { stepHeadParticles() }
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
            // Frozen, the body is drawn in the ice look.
            // Changing, the energy form from the sheet's sixth frame on.
            let changing = player.state == .transforming
            let energyForm = player.inFloState || (changing && frame.frame >= GameScene.transformEnergyFrame)
            // Facing left, turned round where the sleeves and boots need swapping.
            let drawnAs = player.frozen > 0 ? SpriteLibrary.icePlayer
                : (energyForm ? SpriteLibrary.transformedPlayer(index) : sprites.bodyPlayer(index, facingLeft: player.facing == .left))
            node.texture = sprites.texture(frame, player: drawnAs, ballAsEnergy: wholeSheet)
            // Titan Tea's size, grown into after its port-in.
            if titanGrowDelay[index] > 0 {
                titanGrowDelay[index] -= 1
            } else if titanGrowth[index] < 1 {
                titanGrowth[index] = min(titanGrowth[index] + 1 / CGFloat(GameScene.titanGrowFrames), 1)
            }
            let drawScale = bodyScale(index)
            let growing = player.spec.scale != 1 && titanGrowth[index] < 1
            node.size = node.texture!.size().scaled(by: drawScale)
            node.anchorPoint = sprites.anchor(for: frame.animation)
            // A flight holding still hovers round a small circle, eased in and out, counter-clockwise;
            // held in a tornado, a smaller one.
            let stillFlight = player.state == .flying && player.velocity.length < 0.2
            let inTornado = player.state == .suspended
            hover[index] += ((stillFlight || inTornado ? 1 : 0) - hover[index]) * 0.1
            let lap = Double(match.frame) / 60 / GameScene.hoverSeconds * 2 * .pi
            let radius = (inTornado ? ElementsArt.hoverRadius : GameScene.hoverRadius) * hover[index]
            let drift = CGPoint(x: (cos(lap) * Double(radius)).rounded(), y: (sin(lap) * Double(radius)).rounded())
            node.position = SpriteLibrary.point(player.position) + drift
            // Held a few pixels up off the ground the whole change.
            if changing { node.position.y += GameScene.transformLift }
            if player.state == .dunking {
                // Each frame of the dunk sits where its art was placed on the rim.
                // Titan Tea's whole dunk moved again by its own offset.
                let titan = player.power == .titanTea ? DunkArt.titanOffset : .zero
                let nudge = DunkArt.offsets(for: match.stage.features.look)[Animation.dunkEntry(at: player.stateTimer).index] + titan
                node.position = node.position + CGPoint(x: nudge.x * CGFloat(player.facing.sign), y: nudge.y) * drawScale
            }
            node.xScale = CGFloat(player.facing.sign)
            // Firing Z Tea's beam, its arms over the body, turned with the aim about the shoulder.
            let arms = blastArms(index, on: node)
            arms.isHidden = !player.firingBeam
            if !arms.isHidden {
                arms.texture = sprites.texture(AnimationFrame(.blastArms, 0), player: drawnAs)
                arms.size = arms.texture!.size().scaled(by: drawScale)
                // On the firing loop's even frames the body's shifted: the arms with it.
                let shift = frame.frame % 2 == 0 ? GameScene.blastEvenFrameShift : .zero
                arms.position = CGPoint(x: (GameScene.blastShoulder.width + shift.x) * drawScale, y: (GameScene.blastShoulder.height + shift.y) * drawScale)
                arms.zRotation = CGFloat(player.beamAim)
            }
            // In the throw stance's parry frames, and growing, white.
            let tint: SKColor = .white
            // And all white, glowing, on the change's fifth frame.
            let flashWhite = changing && frame.frame == GameScene.transformWhiteFrame
            let tintShare: CGFloat = growing || flashWhite ? 1 : (player.throwParrying ? 0.85 : 0)
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
            // Hanging on a rim the body turns with it, about the rim's back.
            if player.state == .dunking, player.dunkHoop < rimDip.count {
                let turn = rimTurn(player.dunkHoop)
                node.position = rotated(node.position, about: rimPivot(player.dunkHoop), by: turn)
                node.zRotation += turn
            }

            // Hit by the blade, the body and head flicker a dark shade of their energy, every
            // other pair of frames; locked out after a 47 basket, black, every other four.
            let stunned = player.hitStun > 0 && (player.hitStun / 2) % 2 == 0
            let lockedOut = player.hitStun == 0 && player.pickupLockout > 0 && (player.pickupLockout / 4) % 2 == 0
            // Taking a FLO orb, the whole body flashes its energy's own colour.
            let absorbing = floFlash.indices.contains(index) && floFlash[index] > 0
            let flashColour = absorbing ? SKColor(rgb: sprites.look(for: index).glow)
                : lockedOut ? SKColor(rgb: PixelPalette.outline) : SKColor(rgb: sprites.look(for: index).energyTone(luminance: 0.15))
            for (flash, source) in [(stunBodies[index], node), (stunHeads[index], headNodes[index])] {
                flash.isHidden = !(stunned || lockedOut || absorbing) || source.isHidden
                guard stunned || lockedOut || absorbing else { continue }
                flash.color = flashColour
                flash.texture = source.texture
                flash.size = source.size
                flash.anchorPoint = source.anchorPoint
                flash.position = source.position
                flash.xScale = source.xScale
                flash.yScale = source.yScale
                flash.zRotation = source.zRotation
            }

            // Locked out of FloState, the clothes flash palette 39, every other four frames: the dark
            // ones and the energy's, the hood (below) among them; unglowing meanwhile.
            let lockedOutOfFloState = player.floStateLockout > 0 && !player.inFloState
            let lockoutOn = lockedOutOfFloState && (player.floStateLockout / 4) % 2 == 0
            let clothesFlash = lockoutClothes[index]
            let clothesTexture = lockoutOn ? sprites.clothesTexture(frame, player: drawnAs, ballAsEnergy: wholeSheet) : nil
            clothesFlash.isHidden = clothesTexture == nil || node.isHidden
            if let clothesTexture {
                clothesFlash.texture = clothesTexture
                clothesFlash.size = node.size
                clothesFlash.anchorPoint = node.anchorPoint
                clothesFlash.position = node.position
                clothesFlash.xScale = node.xScale
                clothesFlash.yScale = node.yScale
                clothesFlash.zRotation = node.zRotation
            }
            if lockoutOn { greyedOut.insert(index) } else { greyedOut.remove(index) }
            // The whole lockout, small sizzles off the arms and the head, faint.
            if lockedOutOfFloState, !held, Double.random(in: 0..<1) < GameScene.lockoutSizzlesPerSecond * GameScene.stepSeconds,
               let part = [BodyPart.head, .frontArm, .backArm].randomElement(),
               let landmark = sprites.landmark(part, in: frame, player: index) {
                // On the body itself, so they go where it goes.
                sizzle(at: landmark * drawScale, on: node)
            }

            // Prone in the snipe, the cursor where it's aimed.
            snipeCursors[index].isHidden = player.state != .gunSnipe
            if player.state == .gunSnipe { snipeCursors[index].position = SpriteLibrary.point(player.snipeCursor) }

            // The line round the body, in the look's outline or cycling through the zone's.
            let outlineNode = outlineNodes[index]
            // In FloState, half as thick, in the zone's colours.
            let floStateLine = player.inFloState && player.frozen == 0
            if let outline = floStateLine ? sprites.thinOutlineTexture(frame, player: drawnAs, ballAsEnergy: wholeSheet)
                : sprites.outlineTexture(frame, player: drawnAs, ballAsEnergy: wholeSheet) {
                outlineNode.isHidden = false
                outlineNode.texture = outline
                outlineNode.size = node.size
                outlineNode.anchorPoint = node.anchorPoint
                // White as the body is, growing or parrying; ice, frozen; else the look's or the zone's.
                // The zone's colours cycle round it in the zone and in FloState.
                let cycling = ZoneTuning.inTheZone || floStateLine
                let lineColour = cycling ? ZoneTuning.outline(at: CACurrentMediaTime()) : SKColor(rgb: sprites.look(for: index).outline)
                // In the parry frames the line goes the bright version of the body's colour.
                outlineNode.color = growing ? .white
                    : player.throwParrying ? SKColor(rgb: sprites.look(for: index).bright)
                    : (player.frozen > 0 ? SKColor(rgb: Look.ice.outline) : lineColour)
            } else {
                outlineNode.isHidden = true
            }

            // The frame's energy rides exactly where the body is drawn.
            let energyNode = energyNodes[index]
            if let energy = sprites.energyTexture(frame, player: drawnAs, ballAsEnergy: wholeSheet) {
                energyNode.isHidden = false
                energyNode.texture = energy
                // In the zone the energy (the slash's blade among it) runs the zone's colours.
                setGlow(energyNode, ZoneTuning.inTheZone ? ZoneTuning.outline(at: CACurrentMediaTime()) : SKColor(rgb: sprites.look(for: drawnAs).glow))
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

            // The hood, toned in the energy as the energy is, so it glows the same, a little
            // lighter: up over the human's head, down behind the energy form's. Drawn for the
            // idle's third frame, moved each frame by how far the head is from it there.
            let hood = hoodNodes[index]
            // It follows the head, the human's and FloState's alike.
            let partNow = sprites.landmark(.head, in: frame, player: index)
            let partDrawnFor = sprites.landmark(.head, in: GameScene.hoodDrawnFor, player: index)
            if !node.isHidden, let partNow, let partDrawnFor {
                hood.isHidden = false
                // Toned ahead of time through the energy's ramp, opaque, rather than by a shader:
                // up, the whole hooded head in the skin it's drawn for, its hood alone toned.
                // In FloState the same hooded head, its hood in the energy form's colour; frozen,
                // all of it in the ice look's.
                let skin = sprites.look(for: index).dressing.skinTone
                let frozen = player.frozen > 0
                let hoodHead = frozen ? sprites.hoodHead(skin: skin, player: SpriteLibrary.icePlayer)
                    : sprites.hoodHead(skin: skin, player: index, energy: energyForm)
                if energyForm, !frozen { energyHoods.insert(index) } else { energyHoods.remove(index) }
                hood.texture = hoodHead.drawn
                hoodMasks[index] = (hoodHead.hood, hoodHead.face)
                hood.zPosition = GameScene.hoodUpZ
                // Sized unflipped, then flipped: a sprite's size is taken against its scale.
                hood.xScale = 1
                hood.size = hood.texture!.size().scaled(by: drawScale)
                hood.anchorPoint = sprites.anchor(for: GameScene.hoodDrawnFor.animation)
                let moved = (partNow - partDrawnFor) * drawScale
                hood.position = node.position + leaned(CGPoint(x: moved.x * CGFloat(player.facing.sign), y: moved.y))
                hood.xScale = node.xScale
                hood.zRotation = node.zRotation
                // Super Smoothie flying down, the hooded head tips forward; flying up or forward, back;
                // eased, about the head's middle, and let down a little to sit on the neck turned.
                let ahead = player.velocity.x * player.facing.sign
                let diving = player.velocity.y < -FlightSheet.still && -player.velocity.y > ahead
                let rising = player.velocity.y > FlightSheet.still || ahead > FlightSheet.still
                // Z Tea's beam aimed up, the head tips back with it, down, forward: as far as
                // flying's tip at the aim's limit.
                let aiming = player.state == .beamCharging || player.state == .beamFiring
                let wantedTip: CGFloat = aiming ? CGFloat(player.beamAim / ZRules.aimRange) * GameScene.flightHeadTip
                    : player.state != .flying ? 0
                    : (diving ? -GameScene.flightHeadTip : (rising ? GameScene.flightHeadTip : 0))
                headTip[index, default: 0] += (wantedTip - headTip[index, default: 0]) * GameScene.headTipEase
                if abs(headTip[index, default: 0]) > 0.001, let head = sprites.landmark(.head, in: GameScene.hoodDrawnFor, player: index) {
                    let anim = GameScene.hoodDrawnFor.animation
                    let middle = CGPoint(x: anim.pixelSize / 2 + head.x, y: anim.pixelSize - anim.feetFromBottom - head.y)
                    let tip = headTip[index, default: 0]
                    turn(hood, about: middle, by: tip * CGFloat(player.facing.sign), scale: drawScale)
                    hood.position.y -= GameScene.flightHeadDrop * abs(tip) / GameScene.flightHeadTip * drawScale
                }
            } else {
                hood.isHidden = true
                hoodMasks[index] = nil
            }
            // Greyed out of FloState, the hood's own grey over it.
            let hoodGrey = lockoutHoods[index]
            hoodGrey.isHidden = hood.isHidden || !lockoutOn || hoodMasks[index] == nil
            if !hoodGrey.isHidden, let mask = hoodMasks[index]?.hood {
                hoodGrey.texture = mask
                hoodGrey.xScale = 1
                hoodGrey.size = mask.size().scaled(by: drawScale)
                hoodGrey.anchorPoint = hood.anchorPoint
                hoodGrey.position = hood.position
                hoodGrey.xScale = hood.xScale
                hoodGrey.zRotation = hood.zRotation
            }
            // Its strings, off the hood, over the body: behind it, the hood down's were lost under
            // the torso. Toned as the hood's white and its palette 37 are.
            if hood.isHidden || player.frozen > 0 {
                hoodStrings[index].hide()
            } else if !held {
                let look = sprites.look(for: index)
                // FloState's float, one each way; Super Smoothie flying, both stream behind; else they hang.
                let style = energyForm ? HoodStrings.floState
                    : (player.power == .superSmoothie && player.state == .flying ? HoodStrings.streaming : HoodStrings.hanging)
                // In the hood's colours: in FloState the energy form's, as its hood is.
                let grey = SKColor(rgb: GameScene.lockoutGrey)
                let plain = energyForm ? (look.body ?? look.glow) : look.energyTone(luminance: SpriteLibrary.hoodLevel)
                let accent = energyForm ? Look.scaled(look.body ?? look.glow, GameScene.stringAccentLuminance)
                    : look.energyTone(luminance: GameScene.stringAccentLuminance * SpriteLibrary.hoodLevel)
                hoodStrings[index].step(anchors: HoodStrings.anchors(on: hood, scale: drawScale), style: style,
                                        facing: CGFloat(player.facing.sign), scale: drawScale, time: CACurrentMediaTime(),
                                        plain: lockoutOn ? grey : SKColor(rgb: plain),
                                        accent: lockoutOn ? grey : SKColor(rgb: accent),
                                        z: energyForm ? GameScene.floatingStringZ : GameScene.hoodUpZ + 0.0005)
            }
            // The hood flashes with the body, part of its silhouette: over the body's flash when
            // it's up, over the hood itself when it's down behind.
            let hoodFlash = hoodFlashes[index]
            hoodFlash.isHidden = hood.isHidden || !(stunned || lockedOut || absorbing)
            if !hoodFlash.isHidden {
                hoodFlash.color = flashColour
                hoodFlash.texture = hood.texture
                hoodFlash.xScale = 1
                hoodFlash.size = hood.texture!.size().scaled(by: drawScale)
                hoodFlash.anchorPoint = hood.anchorPoint
                hoodFlash.position = hood.position
                hoodFlash.xScale = hood.xScale
                hoodFlash.zRotation = hood.zRotation
                hoodFlash.zPosition = GameScene.hoodFlashZ
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
            halo.color = player.hasFireball ? GameScene.fireballColour : teamColour
            if player.holding, let landmark = sprites.landmark(.ball, in: frame, player: index) {
                let inHand = landmark * drawScale
                let ballX = player.position.x + Double(inHand.x) * player.facing.sign / SpriteLibrary.pixelsPerUnit
                let dribbling = Animation.dribbles.contains(frame.animation)
                let drop = player.grounded && dribbling ? match.stage.drop(fromX: ballX, y: player.position.y) * SpriteLibrary.pixelsPerUnit : 0
                let phase = min(max(inHand.y / (CGFloat(BallRules.dribbleHandHeight) * drawScale), 0), 1)
                let y = inHand.y - CGFloat(drop) * (1 - phase)
                let at = node.position + leaned(CGPoint(x: inHand.x * CGFloat(player.facing.sign), y: y.rounded()))
                // A frozen ball takes no glow: it washes it out.
                halo.isHidden = player.frozen > 0
                halo.position = at
                handBall.isHidden = false
                handBall.position = at
                let look = player.frozen > 0 ? sprites.basketballIceFrames : (player.hasFireball ? sprites.basketballFireFrames : sprites.basketballFrames)
                handBall.texture = look[dribbling ? Int(CACurrentMediaTime() / GameScene.dribbleFrameSeconds) % SpriteLibrary.basketballFrameCount : 0]
            } else {
                halo.isHidden = true
                handBall.isHidden = true
            }

            // A held throw charges: the swirl round the ball in hand, up to the loop's end,
            // then round the loop for as long as the throw is held. Let go into the throw,
            // the rest of the sheet plays out where the ball was.
            let charge = chargeNodes[index]
            // Z Tea's beam charges at the hand the throw's way; once it fires the swirl plays out.
            let beaming = player.power == .zTea && player.state == .beamCharging
            let chargingNow = (player.state == .throwStance && !handBall.isHidden) || beaming
            if chargingNow {
                // A sprite's size is set in its parent's units, so it's divided by whatever
                // scale the node has on: back to 1 first, or the scale below does nothing.
                charge.setScale(1)
                switch player.power {
                case .blazingBoba where !beaming:
                    // Fire round the ball, the sheet looped, as painted.
                    let frame = player.stateTimer * Int(Effect.fireCharge.fps) / 60 % Effect.fireCharge.frameCount
                    charge.texture = sprites.texture(Effect.fireCharge.name, frame)
                    charge.size = charge.texture!.size()
                    charge.anchorPoint = Effect.fireCharge.anchor
                    charge.setScale(Effect.fireCharge.scale)
                case .zeusJuice where !beaming:
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
                charge.position = beaming ? chargeHands(frame, player: index, body: node.position, drawScale: drawScale, leaned: leaned)
                    ?? SpriteLibrary.point(player.beamOrigin) : handBall.position
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
                   player.state == .throwing || player.state == .dunking || player.state == .beamFiring {
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
            // A head drawn apart, unless the hooded head stands in for it.
            if hood.isHidden, let landmark = sprites.landmark(.head, in: frame, player: index),
               let headTexture = sprites.headTexture(frame, player: drawnAs),
               let anchor = sprites.headAnchor(frame, player: drawnAs) {
                let head = landmark * drawScale
                let target = node.position + leaned(CGPoint(x: head.x * CGFloat(player.facing.sign), y: head.y))
                if headShown[index] == .zero { headShown[index] = target }
                // The energy form's rides its body exactly; the lag and the bob, which read as
                // detached, are kept for any other head drawn apart (`GameScene.headsRide`).
                let rides = GameScene.headsRide && energyForm
                let lag = rides ? 1 : headVariant.lag
                headShown[index] = CGPoint(x: headShown[index].x + (target.x - headShown[index].x) * lag,
                                           y: headShown[index].y + (target.y - headShown[index].y) * lag)
                var offset = headShown[index] - target
                if headVariant.reversedAcross { offset.x = -offset.x }
                let bob = rides ? 0 : (sin(Double(match.frame) / 60 * 2 * .pi * 1.2) * 1).rounded()
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
                if !lockedOutOfFloState { emitHeadParticles(index, power: player.power, at: CGPoint(x: shown.x, y: shown.y + GameScene.crownLift * drawScale)) }
            } else {
                headNode.isHidden = true
                headEspers[index].particleBirthRate = 0
                headEsperMixes[index].particleBirthRate = 0
                // A human's head is on the body: its particles still rise off it.
                // None while locked out of FloState.
                if !sprites.look(for: drawnAs).headApart || !hood.isHidden, !lockedOutOfFloState, let landmark = sprites.landmark(.head, in: frame, player: drawnAs) {
                    let head = landmark * drawScale
                    let at = node.position + leaned(CGPoint(x: head.x * CGFloat(player.facing.sign), y: head.y))
                    emitHeadParticles(index, power: player.power, at: CGPoint(x: at.x, y: at.y + GameScene.crownLift * drawScale))
                }
            }
            // A human's legs, in the energy's colours, give off smaller cubes of their own; in
            // the energy form, the hands too.
            if HumanLook.enabled, ParticleLook.cubes, !lockedOutOfFloState {
                // A human's off whatever of the limbs is energy, as drawn (`Dressing.cubeSources`): a
                // boot's or a sleeve's top, a shoe; the energy form's off its legs and hands.
                let limbs: [(part: BodyPart, fromTop: Bool)] = energyForm ? [(.frontLeg, false), (.backLeg, false), (.frontHand, false), (.backHand, false)]
                    : sprites.look(for: drawnAs).dressing.cubeSources
                for (slot, limb) in limbs.enumerated() {
                    guard let landmark = limb.fromTop ? sprites.top(limb.part, in: frame) : sprites.landmark(limb.part, in: frame, player: drawnAs) else { continue }
                    let leg = landmark * drawScale
                    let at = node.position + leaned(CGPoint(x: leg.x * CGFloat(player.facing.sign), y: leg.y))
                    emitHeadParticles(index, power: player.power, at: at, creditKey: GameScene.legCreditKey + index * 4 + slot,
                                      streams: [legStream(index, part: limb.part, energyColour: energyForm, drawnAs: drawnAs)])
                }
            }
            // Into FloState, on the change's third frame, or out of it: a burst in the energy's
            // colour, and cubes swirling round a while (going in, the change's own spiral as well).
            let changeBurstDue = changing && frame.frame >= GameScene.transformBurstFrame
            let goingIn = changeBurstDue && lastChangeBurstDue[index] != true
            let goingOut = wasInFloState[index] == true && !player.inFloState
            if goingIn || goingOut {
                glowers.addChild(EnergyEffect.burst.node(sprites, player: index, at: SpriteLibrary.point(player.chest)))
                floSwirlFrames[index] = GameScene.floSwirlFrames
            }
            wasInFloState[index] = player.inFloState
            lastChangeBurstDue[index] = changeBurstDue
            if floSwirlFrames[index, default: 0] > 0 { floSwirlFrames[index, default: 0] -= 1 }
            // Changing, up to the white frame cubes spiral up round the whole body; and swirling.
            if (changing && frame.frame <= GameScene.transformWhiteFrame || floSwirlFrames[index, default: 0] > 0), ParticleLook.cubes {
                var spiral = legStream(index, part: .frontLeg, energyColour: true)
                spiral.rate = GameScene.transformSpiralRate
                spiral.helixRadius = GameScene.transformSpiralRadius
                // At the head's cube size, bigger than the legs'.
                spiral.legs = false
                emitHeadParticles(index, power: player.power, at: SpriteLibrary.point(player.position) + CGPoint(x: 0, y: GameScene.transformLift),
                                  creditKey: GameScene.transformCreditKey + index, streams: [spiral])
            }
            // Super Smoothie hovering still: a vortex of cubes off the foot that hangs lowest.
            if hoverVortex(index), ParticleLook.cubes, !lockedOutOfFloState {
                let feet = [BodyPart.frontFoot, .backFoot].compactMap { sprites.landmark($0, in: frame, player: index) }
                if let foot = feet.min(by: { $0.y < $1.y }) {
                    var vortex = legStream(index, part: .frontFoot, energyColour: true)
                    vortex.rate = GameScene.vortexRate
                    vortex.helixRadius = GameScene.vortexStartRadius
                    vortex.legs = false
                    let spot = foot * drawScale
                    emitHeadParticles(index, power: player.power, at: node.position + leaned(CGPoint(x: spot.x * CGFloat(player.facing.sign), y: spot.y)),
                                      creditKey: GameScene.vortexCreditKey + index, streams: [vortex])
                }
            }
            // The change's eyes over the body, in the energy's colour.
            let eyes = eyesNodes[index]
            eyes.isHidden = !changing || EffectSheets.frames["transform_eyes"] == nil
            if !eyes.isHidden {
                eyes.texture = sprites.texture("transform_eyes", frame.frame)
                eyes.size = node.size
                eyes.anchorPoint = node.anchorPoint
                eyes.position = node.position
                eyes.xScale = node.xScale
                eyes.zRotation = node.zRotation
                eyes.color = SKColor(rgb: sprites.look(for: index).glow)
            }

            placeSurf(index, player: player, body: node, head: headNode)
            if match.stage.features.shadows {
                // The body and head cast down from the feet, flipped and sheared with the turf.
                let feet = SpriteLibrary.point(player.position).y
                let drop = CGFloat(match.stage.drop(fromX: player.position.x, y: player.position.y) * SpriteLibrary.pixelsPerUnit)
                castShadow(shadowBodies[index], of: node, anchorY: feet, facing: node.xScale, ground: feet - drop, rise: drop)
                castShadow(shadowHeads[index], of: headNode, anchorY: feet, facing: headNode.xScale, ground: feet - drop, rise: drop)
            }
            // The stepback, a jump out of the shooting stance, the throw and the slash leave the trail.
            let trailing = player.state == .stepback || player.state == .throwing || (player.state == .shootStance && !player.grounded)
            if trailing, match.frame % 2 == 0 { spawnAfterimage(of: node, player: index) }
            // The slash's trail is the body and its blade; in FloState each one the next of the zone's colours.
            if player.state == .slashing, match.frame % 2 == 0 {
                slashAfterimages[index, default: 0] += 1
                let rainbow = player.inFloState ? ZoneTuning.colours[slashAfterimages[index, default: 0] % ZoneTuning.colours.count] : nil
                spawnAfterimage(of: node, player: index, colour: rainbow.map { SKColor(rgb: $0) })
                if !energyNodes[index].isHidden { spawnAfterimage(of: energyNodes[index], player: index, colour: rainbow.map { SKColor(rgb: $0) }) }
            }
            if player.power == .frostTea, player.state == .slide, match.frame % 3 == 0 {
                spawnSnowflakes(at: SpriteLibrary.point(player.position + Vec2(x: -player.facing.sign * 4, y: 2)), count: 2, spread: 6)
            }
            // Blazing Boba's skid: the fire sheet as the run stops.
            if player.power == .blazingBoba, player.state == .idle, lastStates[index] == .run || lastStates[index] == .dash {
                // The sheet skids the other way from the run sheets.
                spawn(.fireSkid, at: player.position, flipped: player.facing == .right, scale: bodyScale(index))
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
        placeStageFireball()
        blowWind()
        if !held { stepWater() }
        stepFootfalls()
        splashRain()
        sizzleRain()
        riseLightningDots()
        placeIcicles()
        fallRain()
        elementsArt?.placeTornados(match.tornadoBoxes, fire: TornadoRules.isFire(at: match.frame), time: CACurrentMediaTime(),
                                   burstFrame: TornadoRules.burstFrame(at: match.frame),
                                   hoverLap: Double(match.frame) / 60 / GameScene.hoverSeconds * 2 * .pi)
        section("webs")

        let ball = match.ball
        ballNode.isHidden = ball.holder != nil
        ballNode.position = SpriteLibrary.point(ball.position)
        // On the Hoopfish's antenna it nods with it.
        if match.hoopfish?.carrying == .ball, ball.holder == nil { ballNode.position = hoopfishNod(0).turn(ballNode.position) }
        // Frozen it goes ice; burning it goes fire.
        let colour = ball.frozen > 0 ? GameScene.ice : (ball.burning ? GameScene.fireballColour : ballColour)
        // A frozen ball takes no glow: it washes it out.
        ballHalo.isHidden = ball.frozen > 0
        // Hung on the Hoopfish's antenna its glow swells from its usual strength to most of it and
        // back, bigger and lighter, so it reads over the bright water.
        let onAntenna = match.hoopfish?.carrying == .ball && ball.holder == nil
        let swell = CGFloat(0.5 - 0.5 * cos(CACurrentMediaTime() / GameScene.antennaBallGlowSeconds * 2 * .pi))
        if onAntenna {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let lighten = GameScene.antennaBallLighten
            ballHalo.color = SKColor(red: red + (1 - red) * lighten, green: green + (1 - green) * lighten, blue: blue + (1 - blue) * lighten, alpha: 1)
        } else {
            ballHalo.color = colour
        }
        ballHalo.alpha = onAntenna ? GameScene.ballGlow + (GameScene.antennaBallGlow - GameScene.ballGlow) * swell : GameScene.ballGlow
        ballHalo.setScale(onAntenna ? GameScene.antennaBallHaloScale : 1)
        spinBall(ball)
        // The camera on a scrolling stage: level, gliding after the local player and leading them.
        if !wholeStageView, [StageLook.footballField, .elements].contains(match.stage.features.look) { cameraBase.x += (cameraTargetX() - cameraBase.x) * GameScene.cameraEase }
        placeBallCamFrame()
        circlesOverCam.isHidden = !ballCamEnabled
        // 47's lines breathe, slowly, between gone and a quarter.
        drawSwimmingThreeLine()
        if !threePointArcs.isHidden {
            let breath = CGFloat(0.5 - 0.5 * cos(CACurrentMediaTime() / ThreePointTuning.breathSeconds * 2 * .pi))
            for arc in threePointArcSides { arc.node.alpha = ThreePointTuning.breathMax * breath }
        }
        // Quake-Up Coffee's shake: the camera a pixel or two off, a few frames; none with it set off.
        if shake > 0, !GameSettings.screenShake { shake = 0 }
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
                if [StageLook.wetshot, .elements, .flight].contains(match.stage.features.look) {
                    // Closing in, the view stays inside the stage's sides.
                    let halfSeen = size.width * cameraNode.xScale / 2, stageWidth = SpriteLibrary.point(Vec2(x: match.stage.width, y: 0)).x
                    cameraNode.position.x = min(max(cameraNode.position.x, halfSeen), max(stageWidth - halfSeen, halfSeen))
                }
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
        // Not on Wetshot Wake, where the ball off screen is only ever on the Hoopfish's antenna.
        let offSide: CGFloat? = match.stage.features.look == .wetshot ? nil
            : (ballAt.x > cameraNode.position.x + halfView ? 1 : (ballAt.x < cameraNode.position.x - halfView ? -1 : nil))
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
                chevron.position = SpriteLibrary.point(targetHoop.position) + CGPoint(x: 0, y: ChevronTuning.basketLift - CGFloat(index) * 5)
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
                // The rim's spring: toward its rest, or held down while someone dunks on it.
                // The rim gives only for the dunk's last two frames.
                let dunkedOn = match.players.contains { $0.state == .dunking && $0.dunkHoop == index && Animation.dunkEntry(at: $0.stateTimer).index >= Animation.dunkSequence.count - 2 }
                rimSpin[index] += ((dunkedOn ? RimLook.dunkDip : 0) - rimDip[index]) * RimLook.stiffness - rimSpin[index] * RimLook.damping
                // The slam shakes the backboard too, the rim riding it.
                if dunkedOn { boardJitter[index] = RimLook.jitterFrames }
                rimDip[index] += rimSpin[index]
                let artPoint = GameScene.hoopArtPoint(for: match.stage.hoops[index], on: match.stage.features.look)
                let pivot = HoopTuning.pivot(for: match.stage.features.look)
                rimNodes[index].xScale = match.stage.hoops[index].backboard == .left ? -1 : 1
                rimNodes[index].anchorPoint = pivot
                // A shake: a whole art pixel either way, every other frame, while it lasts.
                if rimJitter[index] > 0 { rimJitter[index] -= 1 }
                if boardJitter[index] > 0 { boardJitter[index] -= 1 }
                let boardShake = CGPoint(x: GameScene.shake(boardJitter[index]), y: 0)
                let rimShake = CGPoint(x: GameScene.shake(rimJitter[index]), y: 0) + boardShake
                rimNodes[index].position = rimPivot(index) + rimShake
                rimNodes[index].zRotation = rimTurn(index)
                // Wetshot Wake's rim nods with the Hoopfish's antenna, about where it meets the body.
                let nod = hoopfishNod(index)
                rimNodes[index].position = nod.turn(rimNodes[index].position)
                rimNodes[index].zRotation += nod.angle
                backboardNodes[index].position = artPoint + boardShake
                backboardNodes[index].xScale = rimNodes[index].xScale
                // Laid out round the right hoop, mirrored at the left.
                if index < supportNodes.count {
                    supportNodes[index].position = artPoint
                    supportNodes[index].xScale = match.stage.hoops[index].backboard == .left ? -1 : 1
                }
                // The Hoopfish's spin has the rim in it: its own art and net out of sight meanwhile.
                let spinning = index == 0 && (match.hoopfish?.spin ?? 0) > 0
                rimNodes[index].isHidden = spinning
                // The front lip over the ball, wherever and however the rim is.
                if index < rimFronts.count, rimFronts[index].texture != nil {
                    let front = rimFronts[index], rim = rimNodes[index]
                    front.isHidden = rim.isHidden
                    front.size = rim.size
                    front.anchorPoint = rim.anchorPoint
                    front.position = rim.position
                    front.xScale = rim.xScale
                    front.zRotation = rim.zRotation
                    front.color = rim.color
                    front.colorBlendFactor = rim.colorBlendFactor
                }
                if index < nets.count { nets[index].hidden = spinning }
                if index < nets.count {
                    // The Elements' wind blows the nets leftward, in gusts; elsewhere a light breeze sways them.
                    let time = CACurrentMediaTime() * GameScene.netGustRate
                    let gust = 0.7 + 0.3 * sin(time)
                    nets[index].wind = match.stage.features.look == .elements ? -GameScene.netWind * CGFloat(gust)
                        : GameScene.netBreeze * CGFloat(sin(time + Double(index)))
                    nets[index].step(rim: nod.turn(GameScene.netPoint(for: match.stage.hoops[index], on: match.stage.features.look)), ball: ballNode.isHidden ? nil : ballNode.position,
                                     ballRadius: CGFloat(BallRules.radius) * SpriteLibrary.pixelsPerUnit + 1,
                                     bodies: match.players.map { SpriteLibrary.point($0.chest) })
                    // Someone hanging on this rim: its net flares out at the bottom, easing in and back.
                    // The rim gives only for the dunk's last two frames.
                let dunkedOn = match.players.contains { $0.state == .dunking && $0.dunkHoop == index && Animation.dunkEntry(at: $0.stateTimer).index >= Animation.dunkSequence.count - 2 }
                    let step = 1 / CGFloat(NetTuning.dunkFlareFrames)
                    nets[index].dunkFlare = dunkedOn ? min(nets[index].dunkFlare + step, 1) : max(nets[index].dunkFlare - step, 0)
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
        drawWalls()
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
        fpsLabel.isHidden = !GameScene.diagnosingPerformance
        if GameScene.diagnosingPerformance { fpsLabel.text = "\(framesPerSecond) fps  worst \(worstFrameMilliseconds) ms\n\(frameReadout)" }
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
    /// The walls overlay, redrawn only when the stage's solids change.
    private func drawWalls() {
        guard showWalls else {
            if drawnWalls != nil { wallsLayer.removeAllChildren(); drawnWalls = nil }
            return
        }
        let stage = match.stage
        if let drawn = drawnWalls, drawn.tiles == stage.tiles, drawn.boxes == stage.extras, drawn.outOfReach == stage.outOfReach { return }
        drawnWalls = (stage.tiles, stage.extras, stage.outOfReach)
        wallsLayer.removeAllChildren()
        func fill(_ rect: CGRect, _ colour: SKColor) {
            let node = SKShapeNode(rect: rect)
            node.fillColor = colour.withAlphaComponent(0.3)
            node.strokeColor = colour.withAlphaComponent(0.8)
            node.lineWidth = 1
            wallsLayer.addChild(node)
        }
        func rect(_ box: Box) -> CGRect {
            let low = SpriteLibrary.point(box.min), high = SpriteLibrary.point(box.max)
            return CGRect(x: low.x, y: low.y, width: high.x - low.x, height: high.y - low.y)
        }
        let side = GameScene.pixelsPerTile
        for row in 0..<stage.rows {
            for column in 0..<stage.columns {
                switch stage.tile(column: column, row: row) {
                case .solid: fill(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side), .red)
                case .oneWay: fill(CGRect(x: CGFloat(column) * side, y: CGFloat(row + 1) * side - 2, width: side, height: 2), .yellow)
                case .empty: break
                }
            }
        }
        for box in stage.extras { fill(rect(box), .cyan) }
        for box in stage.outOfReach { fill(rect(box), .magenta) }
    }

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
        #if !os(tvOS)
        if let editor = mapEditor {
            editor.began(at: hudPoint(point, viewSize: viewSize))
            return
        }
        if let builder = supportBuilder {
            builder.began(at: hudPoint(point, viewSize: viewSize))
            return
        }
        #endif
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
        #if !os(tvOS)
        if let editor = mapEditor {
            editor.moved(to: hudPoint(point, viewSize: viewSize))
            return
        }
        if let builder = supportBuilder {
            builder.moved(to: hudPoint(point, viewSize: viewSize))
            return
        }
        #endif
        controls?.moved(touch, to: hudPoint(point, viewSize: viewSize))
    }

    func touchEnded(_ touch: UITouch, at point: CGPoint? = nil, viewSize: CGSize = .zero) {
        #if !os(tvOS)
        if let editor = mapEditor {
            editor.ended(at: point.map { hudPoint($0, viewSize: viewSize) } ?? lastEditorPoint)
            return
        }
        if let builder = supportBuilder {
            builder.ended(at: point.map { hudPoint($0, viewSize: viewSize) } ?? .zero)
            return
        }
        #endif
        controls?.ended(touch)
    }
}
