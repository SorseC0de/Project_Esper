import Foundation

/// A power. Each one takes over parts of the controls, and less of it is available with
/// the ball in hand.
public enum Power: Equatable, Hashable {
    case none
    case webWater
    case superSmoothie
    case flashFizz
    case platformShake
    case quakeUp
    case zeusJuice
    case frostTea
    case blazingBoba
    case pulsepistol
    case surfSoda
    case titanTea

    /// Powers whose shoot button, without the ball, is something other than the slash.
    public var takesShoot: Bool {
        self == .zeusJuice || self == .pulsepistol
    }
}

/// What a web line runs to.
public enum WebTarget: Equatable {
    case point(Vec2)
    case ball
    case opponent
}

public struct WebLine: Equatable {
    public var target: WebTarget
    /// Frames left to show, for a line to nothing; a pull's line lasts as long as the pull.
    public var frames: Int
}

/// Flash Fizz's tear in space, left where a flash came out: a loose ball within reach of
/// it is pulled into the hands while it lasts.
public struct Tear: Equatable {
    public var position: Vec2
    public var framesLeft: Int
}

public enum PlayerState: Equatable, Hashable {
    case idle, walk, dash, run, pivot
    case jumpSquat, air, wallLand, land
    case shootStance, shooting
    case throwStance, throwing, dunking
    case catching, taunt
    /// Without the ball: the crouch and crouch walk, the slide, the Esper Slash and the
    /// roll that always follows it, the snatch, and hanging from and climbing a ledge.
    case crouch, crouchWalk, slide
    case slashing, rolling, snatching
    case ledgeHang, ledgeClimb
    /// Platform Protein Shake's wall, made on the snatch's reach.
    case walling
    /// A shot's or throw's stance, stepping back.
    case stepback
    /// Web Water: swinging under a web, reeling to a wall, and being reeled by the other.
    case webSwing, webPull, webbed
    /// Super Smoothie: flying. Pulsepistol Punch: the shot, standing.
    case flying, gunShoot
    /// Pulsepistol Punch at level two: prone, aiming a cursor.
    case gunSnipe
    /// Held in one of the Elements' tornados, hovering at its middle.
    case suspended
    /// Changing from the human form into the energy form, held still in the air.
    case transforming

    /// The actions Titan Tea does slower.
    public var isAction: Bool {
        switch self {
        case .shootStance, .shooting, .throwStance, .throwing, .dunking, .catching, .slide, .slashing, .rolling, .snatching,
             .walling, .gunShoot: true
        default: false
        }
    }

    public var isGroundState: Bool {
        switch self {
        case .idle, .walk, .dash, .run, .pivot, .jumpSquat, .land, .crouch, .crouchWalk, .slide, .gunSnipe: true
        default: false
        }
    }

    /// States a ball can be caught out of. The snatch takes the ball its own way.
    public var canCatch: Bool {
        switch self {
        case .idle, .walk, .dash, .run, .pivot, .jumpSquat, .air, .land, .wallLand, .webSwing, .webPull, .flying,
             .crouch, .crouchWalk, .slide, .suspended: true
        default: false
        }
    }
}

/// One fighter. Position is the feet, centred.
public struct Player: Equatable {
    public var spec: FighterSpec
    public var index: Int
    public var position: Vec2
    public var velocity: Vec2 = .zero
    public var facing: Facing
    public var state: PlayerState = .idle
    public var previousState: PlayerState = .idle
    /// The throw stance's opening frames, the parry's (`ThrowParryRules`).
    public var throwParrying: Bool { (state == .throwStance && hasBall && stateTimer < ThrowParryRules.frames) || state == .stepback }
    /// The stance a stepback came out of and goes back to, and whether this stance has had its one.
    public var stepbackFrom: PlayerState = .shootStance
    public var stepbackUsed = false
    /// Down pressed in this stance: the stepback, once the stance is held.
    public var stepbackAsked = false
    /// The stick is still down from the stepback: it aims nothing until it's let go and pressed again.
    public var stepbackAimLocked = false
    /// The run's speed as it last stood, for the pivot jump to carry.
    public var runMomentum = 0.0
    /// Frames spent in the state so far; 0 on the frame it was entered.
    public var stateTimer = 0
    /// The clock held this frame, so a check for reaching a frame doesn't fire twice.
    public private(set) var timerHeld = false
    private var actionTicks = 0
    /// The state's clock on `frame` this step, and not held on it from the last.
    public func reached(_ frame: Int) -> Bool { stateTimer == frame && !timerHeld }
    public var grounded = true
    public var wallSide: Facing?
    /// The wall beside, if the board can ride it: not a car.
    public var ridableWallSide: Facing?
    public var jumpsLeft: Int
    public var fastFalling = false
    public var hasBall = false
    /// The last flick recorded in the shooting stance.
    public var shotAim: Vec2 = .zero
    /// The stance was let go before its windup finished: it fires when the windup ends.
    public var quickShot = false
    /// The stance was taken on the ground and jumped out of.
    public var jumpShot = false
    /// The throw stance was let go before its windup finished: it throws when the windup ends.
    public var quickThrow = false
    /// The shot was released on the way up out of a jump shot: it leaves with the body's lift.
    public var shotLift = false
    /// The last cardinal recorded in the throwing stance; zero throws forward.
    public var throwDirection: Vec2 = .zero
    public var catchCooldown = 0
    /// 47: the scorer can't take the ball, by hand or snatch, until this runs out.
    public var pickupLockout = 0
    public var wallLandCooldown = 0
    /// Frames left in which the stick doesn't steer, after a wall jump.
    public var airControlLock = 0
    /// Frames left after walking off an edge in which a jump is still a ground jump.
    public var coyote = 0
    /// Frames the stick has been held down.
    public var downHeldFrames = 0
    /// Which shoot buttons took the stance; a different one pressed cancels it.
    public var stanceButtons: UInt8 = 0
    /// After a cancel, every shoot button has to come up before another shoot stance, and
    /// the throw button before another throw stance.
    public var shootReady = true
    public var throwReady = true
    /// The sideways speed when the throw stance began; the floater carries it.
    public var throwStanceEntrySpeed = 0.0

    public var power = Power.none
    /// One, or two after Bio-Boba.
    public var powerLevel = 1
    /// The swing's web, while swinging: where it's anchored, and the arc.
    public var webAnchor: Vec2?
    private var swingLength = 0.0
    private var swingStartAngle = 0.0
    private var swingAngle = 0.0
    private var swingLeastArc = 0.0
    /// Holding throw with no ball: aiming the shot along the stick, fired on release.
    public var webAiming = false
    public var webAimDirection = Vec2.zero
    /// A shot's web, for drawing.
    public var webLine: WebLine?
    public var webLineCooldown = 0
    /// Frames until the next swing can start.
    public var swingCooldown = 0
    /// Where a reel is taking this body.
    public var pullTarget: Vec2?
    /// Frames the line's pose shows.
    public var webLinePose = 0
    /// Super Smoothie: frames of flight left this airtime.
    public var flightLeft = SmoothieRules.flightFrames(level: 1)
    /// Flash Fizz: frames until the next flash; where a warp decided this step is going
    /// when it's down to the ball in hand; and the tear the last flash left.
    public var warpCooldown = 0
    /// Flashes left before the cooldown; nil is a full set for the level.
    public var flashCharges: Int?
    public var pendingWarp: Vec2?
    public var tear: Tear?
    /// Platform Protein Shake: a fast fall just began and wants a slab. A slab or a wall
    /// can be made only once the cooldown has passed and after a jump, a wall jump or a
    /// wall land since the last.
    public var wantsPlatform = false
    public var platformArmed = true
    /// Frames until the next wall; walls need no arming.
    public var wallCooldown = 0
    public var platformCooldown = 0
    /// The slide's leg and the slash's blade each hit once.
    public var slideHit = false
    /// A slide on a slope going down the way it faces: the body rides it on its own, and only a
    /// jump gets out, until flat ground or open air.
    public var forcedSlide = false
    /// In the energy form; and whether the change is there to be made (parked: never, for now).
    public var transformed = false
    public var transformReady = false
    /// Held in a tornado: where its middle is, for the body's middle to be drawn to; and
    /// frames left before a tornado can take the body again after it jumped out.
    public var tornadoCentre: Vec2?
    public var tornadoCooldown = 0
    public var slashHit = false
    /// Frames of down held on the ground, and frames left falling through one-ways after a drop.
    public var dropHoldFrames = 0
    public var dropThrough = 0
    /// Titan Tea: already touching the body it last ran into.
    public var trampling = false
    /// In the air from a knock, not a jump or a fall of its own: Titan Tea's landing
    /// doesn't quake then, or two Titans would knock each other up forever.
    public var knockedAloft = false
    /// Frames left in which no button does anything and nothing is caught, after the ball
    /// was knocked or taken out of the hands; the stick still works.
    public var hitStun = 0 {
        // Titan Tea is stripped but never stunned.
        didSet { if power == .titanTea, hitStun > 0 { hitStun = 0 } }
    }
    public var snatchCooldown = 0
    /// The corner being hung from, and frames after walking off an edge before a corner
    /// can be grabbed.
    public var ledge: Vec2?
    public var ledgeCooldown = 0
    /// The rim being dunked on, and where the body was when the dunk began, to glide from.
    public var dunkHoop = 0
    public var dunkFrom = Vec2.zero
    /// Frames of double-jump animation left.
    public var doubleJumpTimer = 0
    /// Frames a jump press stays live waiting for something to spend it.
    public var jumpBuffer = 0
    /// Frames since the stick was near centre on x, for telling a smash from a tilt.
    public var stickAwayFrames = 0
    /// Walk and run cycle position, in animation frames.
    public var animationPhase = 0.0
    public var lastInput = PlayerInput.idle
    /// Frozen by Frost Tea: held exactly as it is for this many frames more, nothing
    /// running, nothing caught, no hitbox live.
    public var frozen = 0
    /// Blazing Boba's fireball in hand, shot or thrown like the ball.
    public var hasFireball = false
    /// Something in hand, the ball or a fireball: what the stances and the sheets go by.
    public var holding: Bool { hasBall || hasFireball }
    /// Frames until the next bolt, strike or pulse.
    public var boltCooldown = 0
    public var strikeCooldown = 0
    public var pulseCooldown = 0
    /// Frames left of the running shot's pose, and whether the standing shot pulls.
    public var gunRunTimer = 0
    public var gunPull = false
    /// The snipe's cursor, frames into its shot (0 between shots), and whether that shot pulls.
    public var snipeCursor = Vec2.zero
    public var snipeFire = 0
    public var snipePull = false
    /// Surf Soda: frames into the crescent, the way it runs, whether the board is out in the
    /// air, and the body's turn about its middle.
    public var surfPath = 0
    public var surfDirection = 1.0
    public var surfing = false
    public var surfAngle = 0.0
    /// How far the crescent turns the body, a lean or a whole backflip; the wall it's
    /// riding up, if any; and frames left of a backflip off one.
    public var surfTurn = 0.0
    public var surfWall: Facing?
    public var surfFlip = 0
    /// A flip off a wall's turn a frame: on round the way the ride turned it, to upright.
    public var surfFlipRate = 0.0

    /// Whether Surf Soda's board is under the feet: running, or up on a surf jump.
    /// On the ground the board stays out while the body is still coming down off the
    /// wheelie; never on the rim.
    public var boardOut: Bool {
        guard power == .surfSoda, state != .dunking else { return false }
        return surfing || state == .air || (grounded && (state == .run || state == .dash || abs(surfAngle) > 0.02))
    }

    /// Riding the ground the body turns about the board's tail, where it meets the floor;
    /// in the air, about the body's middle.
    public var riding: Bool { grounded && !surfing }

    /// The board's tail on the floor, behind the feet.
    public var boardTail: Vec2 {
        Vec2(x: position.x - facing.sign * SurfRules.boardLength / 2, y: position.y - SurfRules.boardThickness / 2)
    }

    /// The board: its middle and its turn, under the feet, turning with the body.
    public var board: (centre: Vec2, angle: Double) {
        if riding {
            let half = facing.sign * SurfRules.boardLength / 2
            return (boardTail + Vec2(x: Trig.cos(surfAngle) * half, y: Trig.sin(surfAngle) * half), surfAngle)
        }
        let middle = Vec2(x: position.x, y: position.y + spec.bodyHeight / 2)
        let down = spec.bodyHeight / 2 + SurfRules.boardThickness / 2
        return (middle + Vec2(x: Trig.sin(surfAngle) * down, y: -Trig.cos(surfAngle) * down), surfAngle)
    }

    /// Whether a round thing of this radius at `point` touches the board.
    public func boardBlocks(_ point: Vec2, radius: Double) -> Bool {
        guard boardOut else { return false }
        let (centre, angle) = board
        let offset = point - centre
        let along = offset.x * Trig.cos(angle) + offset.y * Trig.sin(angle)
        let across = -offset.x * Trig.sin(angle) + offset.y * Trig.cos(angle)
        return abs(along) <= SurfRules.boardLength / 2 + radius && abs(across) <= SurfRules.boardThickness / 2 + radius
    }

    /// Frames left of the throw's pose after a bolt; its way is set on the release.
    public var boltPose = 0
    /// Frames left of the throw's hold frame after a fireball summon; only for show.
    public var summonPose = 0
    /// Smash's rising aerial: shoot or throw pressed with or during the jump squat comes
    /// out of it as the slash or the snatch on the jump's first frame, with its ascent.
    public enum Aerial: Equatable { case slash, snatch }
    public var pendingAerial: Aerial?
    /// Frames of running at full speed or sliding, for the flames left every few.
    private var flameTimer = 0
    /// Something a piece of the step asked the match to do, if nothing else took the turn.
    private var wanted: PlayerAction?

    public init(spec: FighterSpec, index: Int, position: Vec2, facing: Facing) {
        self.spec = spec
        self.index = index
        self.position = position
        self.facing = facing
        jumpsLeft = spec.jumps
    }

    /// Defending, the body moves this much faster than the one with the ball; the match
    /// sets it each frame from who holds the ball.
    public var speedShare = 1.0
    /// Under water (`StageFeatures.underwater`), set from the stage each step: gravity, the fall
    /// speeds, the jumps, the ground's and the air's speeds and every pick-up and brake at half,
    /// and the clock, every state's timing and its sheet with it, at half its rate.
    public var underwater = false
    var waterTicks = 0
    var waterShare: Double { underwater ? 0.5 : 1 }
    /// Under water a jump rises at half its push but to twice its height: the pull on the way up
    /// an eighth, on the way down a half.
    var gravity: Double { spec.gravity * (underwater ? (velocity.y > 0 ? 1.0 / 8 : 0.5) : 1) }
    var fallSpeed: Double { spec.fallSpeed * waterShare }
    /// The jumps' push, and off a wall, at half under water.
    var fullHopVelocity: Double { spec.fullHopVelocity * waterShare }
    var shortHopVelocity: Double { spec.shortHopVelocity * waterShare }
    var doubleJumpVelocity: Double { spec.doubleJumpVelocity * waterShare }
    var thirdJumpVelocity: Double { spec.thirdJumpVelocity * waterShare }
    var wallJumpHorizontal: Double { spec.wallJumpHorizontal * waterShare }
    var wallJumpVertical: Double { spec.wallJumpVertical * waterShare }
    /// Every change of speed a frame, picking up and braking, at half under water.
    var traction: Double { spec.traction * waterShare }
    var walkAcceleration: Double { spec.walkAcceleration * waterShare }
    var attackBrake: Double { spec.attackBrake * waterShare }
    var airFriction: Double { spec.airFriction * waterShare }
    var slideFriction: Double { spec.slideFriction * waterShare }
    var stanceAirBrake: Double { spec.stanceAirBrake * waterShare }
    var throwStanceAirBrake: Double { spec.throwStanceAirBrake * waterShare }
    var fastFallSpeed: Double { spec.fastFallSpeed * waterShare }
    var runSpeed: Double { spec.runSpeed * speedShare * waterShare }
    var walkMaxSpeed: Double { spec.walkMaxSpeed * speedShare * waterShare }
    var dashInitialVelocity: Double { runSpeed + (spec.dashInitialVelocity - spec.runSpeed) }
    /// The air moves as the ground does: the run's speed, which the jumps set off at too, and
    /// the ground's traction to brake when the stick lets go. Moves that don't steer coast
    /// on the spec's light air friction instead, so their momentum carries.
    var airSpeedMax: Double { spec.runSpeed * speedShare * waterShare }
    var airBrake: Double { traction }

    /// Crouched or sliding, the body is half as tall, so it fits under what a standing
    /// body can't.
    public var body: Box {
        let low = state == .crouch || state == .crouchWalk || state == .slide || state == .gunSnipe
        return Box(min: Vec2(x: position.x - spec.bodyWidth / 2, y: position.y),
                   max: Vec2(x: position.x + spec.bodyWidth / 2, y: position.y + spec.bodyHeight * (low ? 0.5 : 1)))
    }

    /// The body standing where it is, for whether there's room to get up.
    private var standingBody: Box {
        Box(min: Vec2(x: position.x - spec.bodyWidth / 2, y: position.y),
            max: Vec2(x: position.x + spec.bodyWidth / 2, y: position.y + spec.bodyHeight))
    }

    private func roomToStand(in stage: Stage) -> Bool { !stage.overlapsSolid(standingBody) }
    public var standingHeightTop: Double { standingBody.max.y }

    public var chest: Vec2 { Vec2(x: position.x, y: position.y + BallRules.chestHeight * spec.scale) }
    /// Where a held ball sits: a little over the chest.
    public var heldBallPoint: Vec2 { chest + Vec2(x: 0, y: 3 * spec.scale) }

    /// The centre of the second catch ring, the spark's, out in front.
    public var handCatchPoint: Vec2 {
        Vec2(x: position.x + BallRules.handCatchCentre.x * spec.scale * facing.sign, y: position.y + BallRules.handCatchCentre.y * spec.scale)
    }

    /// The centre of the slash's blade: the body's, a little in front.
    public var bladeCentre: Vec2 {
        Vec2(x: body.center.x + SlashRules.forward * spec.scale * facing.sign, y: body.center.y)
    }

    public var inStance: Bool { state == .shootStance || state == .throwStance }

    /// The first step in a state, after `enter` on the step before.
    private var stanceTimerJustEntered: Bool { reached(1) }

    public mutating func enter(_ next: PlayerState) {
        previousState = state
        state = next
        stateTimer = 0
        if next != .slide { forcedSlide = false }
        if next != .suspended { tornadoCentre = nil }
        // A fresh stance has its stepback; coming back out of one doesn't.
        if next == .shootStance || next == .throwStance, previousState != .stepback {
            stepbackUsed = false
            stepbackAsked = false
            stepbackAimLocked = false
        }
        // Onto the rim the body goes upright and the board drops away.
        if next == .dunking {
            surfing = false
            surfWall = nil
            surfFlip = 0
            surfAngle = 0
        }
        // The crescent is only the air's; anything else ends it and sets the body upright.
        if next != .air, next != .land {
            surfPath = 0
            if surfing, next.isGroundState || [.wallLand, .ledgeHang, .webbed, .webPull].contains(next) {
                surfing = false
                surfAngle = surfAngle - (surfAngle / (2 * Double.pi)).rounded() * 2 * Double.pi
                surfWall = nil
                surfFlip = 0
            }
        }
    }

    /// The run cycle's advance this frame: 24 frames a second at full run speed, scaling
    /// with how fast the body actually moves, up to 26 in the dash and never under 10.
    private var runCycleStep: Double {
        Player.steady(min(max(abs(velocity.x) / runSpeed * 24, 10), 26)) / 60
    }

    /// The rates a sheet may play at, sixty split evenly: nothing in between.
    static let steadyRates: [Double] = [7.5, 10, 12, 15, 20, 24, 30]
    /// The nearest of them to `fps`.
    static func steady(_ fps: Double) -> Double {
        steadyRates.min { abs($0 - fps) < abs($1 - fps) } ?? fps
    }

    /// Whether the stick is pushed the way the body faces.
    /// Up out of a slide: into the run with the stick still held forward, as out of a dash.
    private func standUp(from input: PlayerInput) -> PlayerState {
        abs(input.stick.x) >= 0.5 && stickForward(input) ? .run : .idle
    }

    private func stickForward(_ input: PlayerInput) -> Bool {
        input.stick.x != 0 && (input.stick.x > 0) == (facing == .right)
    }

    private func stickFacing(_ input: PlayerInput) -> Facing? {
        input.stick.x == 0 ? nil : (input.stick.x > 0 ? .right : .left)
    }

    // MARK: Step

    /// `opponentX` is where the other body stands; a walk with the ball faces it.
    /// `ballHolder` is who has the ball in hand, and `ballOwner` whose the loose ball still
    /// is, for Flash Fizz's warp to it.
    public mutating func step(input given: PlayerInput, stage sharedStage: Stage, opponentX: Double? = nil,
                              ballHolder: Int? = nil, ballOwner: Int? = nil, events: inout [MatchEvent]) -> PlayerAction? {
        var input = given
        underwater = sharedStage.features.underwater
        // Surf Soda rides the lava as ground.
        var stage = sharedStage
        if power == .surfSoda, let lava = stage.features.lavaSurface {
            stage.extras.append(Box(min: Vec2(x: 0, y: lava - Stage.tileSize * 4), max: Vec2(x: stage.width, y: lava)))
        }
        if frozen > 0 {
            // Held exactly as it is: no timers, no moves, nothing.
            frozen -= 1
            lastInput = input
            return nil
        }
        // Titan Tea's actions run slower: one frame in `actionHoldInterval` the clock holds.
        if spec.actionHoldInterval > 0, state.isAction {
            actionTicks += 1
            timerHeld = actionTicks % spec.actionHoldInterval == 0
        } else {
            timerHeld = false
        }
        // Under water the clock holds every other frame: the whole of every state, and its sheet, at half speed.
        if underwater {
            waterTicks += 1
            if waterTicks % 2 == 0 { timerHeld = true }
        }
        if !timerHeld { stateTimer += 1 }
        if boltCooldown > 0 { boltCooldown -= 1 }
        if strikeCooldown > 0 { strikeCooldown -= 1 }
        if pulseCooldown > 0 { pulseCooldown -= 1 }
        if gunRunTimer > 0 { gunRunTimer -= 1 }
        if summonPose > 0 { summonPose -= 1 }
        if boltPose > 0 {
            boltPose -= 1
            if ZeusRules.boltPoseFrames - boltPose == ZeusRules.boltReleaseFrame, wanted == nil {
                // The way the body faces now, and the stick's tilt now, on the release.
                let tilt = min(max(input.stick.y, -1), 1) * ZeusRules.boltTilt
                wanted = .fireBolt(direction: Vec2(x: Trig.cos(tilt) * facing.sign, y: Trig.sin(tilt)))
            }
        }
        if catchCooldown > 0 { catchCooldown -= 1 }
        if pickupLockout > 0 { pickupLockout -= 1 }
        if wallLandCooldown > 0 { wallLandCooldown -= 1 }
        if webLineCooldown > 0 { webLineCooldown -= 1 }
        if swingCooldown > 0 { swingCooldown -= 1 }
        if warpCooldown > 0 {
            warpCooldown -= 1
            if warpCooldown == 0 { flashCharges = nil }
        }
        if let open = tear { tear = open.framesLeft > 1 ? Tear(position: open.position, framesLeft: open.framesLeft - 1) : nil }
        if platformCooldown > 0 { platformCooldown -= 1 }
        if wallCooldown > 0 { wallCooldown -= 1 }
        if webLinePose > 0 { webLinePose -= 1 }
        if let line = webLine, case .point = line.target, state != .webPull {
            webLine = line.frames > 1 ? WebLine(target: line.target, frames: line.frames - 1) : nil
        }
        if airControlLock > 0 { airControlLock -= 1 }
        if tornadoCooldown > 0 { tornadoCooldown -= 1 }
        if coyote > 0 { coyote -= 1 }
        if input.shootButtons == 0 { shootReady = true }
        if !input.throwBall { throwReady = true }
        if snatchCooldown > 0 { snatchCooldown -= 1 }
        if ledgeCooldown > 0 { ledgeCooldown -= 1 }
        if hitStun > 0 {
            // Stunned: no button answers; with the lock on, the stick doesn't either. It ends a snipe.
            if state == .gunSnipe { enter(.idle) }
            hitStun -= 1
            if StunRules.locksMovement {
                input.stick = .zero
                input.aim = .zero
            }
            input.jump = false
            input.shootButtons = 0
            input.throwBall = false
            input.taunt = false
            jumpBuffer = 0
        }
        if doubleJumpTimer > 0 { doubleJumpTimer -= 1 }
        // Down held on a one-way drops through it.
        if dropThrough > 0 { dropThrough -= 1 }
        dropHoldFrames = grounded && input.stick.y < -0.65 ? dropHoldFrames + 1 : 0
        if dropHoldFrames >= DropRules.holdFrames, state.isGroundState, stage.standsOnlyOnOneWays(body) {
            dropHoldFrames = 0
            dropThrough = DropRules.passFrames
            grounded = false
            velocity.y = 0
            enter(.air)
        }
        stickAwayFrames = abs(input.stick.x) < 0.3 ? 0 : stickAwayFrames + 1
        downHeldFrames = input.stick.y < -0.65 ? downHeldFrames + 1 : 0

        if input.jump && !lastInput.jump { jumpBuffer = 5 } else if jumpBuffer > 0 { jumpBuffer -= 1 }
        let jumpPressed = jumpBuffer > 0
        var shootPressed = input.shoot && !lastInput.shoot
        var throwPressed = input.throwBall && !lastInput.throwBall
        let tauntPressed = input.taunt && !lastInput.taunt
        let smash = abs(input.stick.x) >= spec.dashThreshold && stickAwayFrames <= 3
        let onDefence = ballHolder != nil && ballHolder != index
        var action: PlayerAction?
        let free = state == .idle || state == .walk || state == .run || state == .dash || state == .air || state == .land || state == .wallLand
            || state == .flying || state == .suspended || state == .crouch || state == .crouchWalk
        if free {
            action = webLineIfAsked(input, throwPressed: throwPressed)
        }
        if action == nil, free || ((state == .shooting || state == .throwing) && !hasBall) {
            action = flashIfAsked(input, shootPressed: shootPressed, ballOwner: ballOwner, stage: stage)
        }
        // A warp or a flash on a shoot press takes the button; nothing else reads it this frame.
        if action == .warpToBall {
            shootPressed = false
            input.shootButtons = 0
        } else if case .flash(_)? = action {
            // And the stick: the flash is the move this frame.
            shootPressed = false
            input.shootButtons = 0
            input.stick = .zero
        }
        // Zeus Juice's bolt throw on the ground is committed as the slash is: the stick
        // doesn't walk, and the run it came from bleeds off at the slash's brake.
        let throwingBolt = boltPose > 0 && grounded && state.isGroundState
        let boltCarry = velocity.x
        if throwingBolt { input.stick.x = 0 }

        // Throw and shoot together, out of anything free, or a stance, a slash or a snatch the
        // first of them just started: the change into the energy form, or, in it, straight back out.
        let changeFrom = [.idle, .walk, .dash, .run, .pivot, .jumpSquat, .land, .crouch, .crouchWalk, .air].contains(state)
            || ([.shootStance, .throwStance, .slashing, .snatching].contains(state) && stateTimer <= TransformRules.pressWindowFrames)
        // Blazing Boba's fireball keeps the two together for now, where it's asked for.
        if input.shoot, input.throwBall, shootPressed || throwPressed, changeFrom, hitStun == 0,
           !fireballAsked(input, shootPressed: shootPressed, throwPressed: throwPressed) {
            shootPressed = false
            throwPressed = false
            input.shootButtons = 0
            input.throwBall = false
            if transformed {
                transformed = false
                if ![.idle, .walk, .dash, .run, .pivot, .jumpSquat, .land, .crouch, .crouchWalk, .air].contains(state) { enter(grounded ? .idle : .air) }
            } else if transformReady {
                velocity = .zero
                enter(.transforming)
            }
        }

        // A slide slope: nobody stands on it. Held uphill, the body walks against it and is
        // carried back down, as up a down escalator; otherwise it turns downhill into the forced slide.
        var slideSlopeResisted: Facing?
        var surfingDownSlide: Facing?
        let onSlideSlope = grounded && velocity.y <= 0 && [.idle, .walk, .dash, .run, .pivot, .land, .crouch, .crouchWalk, .slide].contains(state)
            ? stage.slideSlopeDownhill(under: body, reach: SlopeRules.step) : nil
        if power == .surfSoda, let downhill = onSlideSlope {
            // Surf Soda surfs a slide slope: down it on the board unless the stick takes it up.
            if stickFacing(input) != downhill.flipped { surfingDownSlide = downhill }
        } else if let downhill = onSlideSlope {
            if stickFacing(input) == downhill.flipped, !jumpPressed {
                if state != .walk { enter(.walk) }
                slideSlopeResisted = downhill
            } else if state != .slide {
                facing = downhill
                enter(.slide)
                forcedSlide = true
            } else {
                facing = downhill
            }
        }

        switch state {
        case .idle:
            velocity.x = approach(velocity.x, 0, traction)
            if !groundActions(input, jumpPressed: jumpPressed, shootPressed: shootPressed, throwPressed: throwPressed,
                              tauntPressed: tauntPressed, onDefence: onDefence, events: &events) {
                if crouchAsked(input) {
                    enter(.crouch)
                } else if let direction = stickFacing(input) {
                    if smash {
                        facing = direction
                        startDash(events: &events)
                    } else {
                        enter(.walk)
                    }
                }
            }

        case .walk:
            // A walk with the ball faces the opponent whichever way it goes, so it can back off
            // or dribble between the legs while staring them down, after a few frames in which
            // the stick can still turn the body. Only a dash turns it after that. Without the
            // ball the stick turns the body throughout.
            if !hasBall || stateTimer <= spec.walkFaceLockoutFrames, let direction = stickFacing(input) {
                facing = direction
            } else if hasBall, let opponentX, opponentX != position.x {
                facing = opponentX > position.x ? .right : .left
            }
            if !groundActions(input, jumpPressed: jumpPressed, shootPressed: shootPressed, throwPressed: throwPressed,
                              tauntPressed: tauntPressed, onDefence: onDefence, events: &events) {
                if crouchAsked(input) {
                    enter(.crouch)
                } else if let direction = stickFacing(input) {
                    if smash {
                        facing = direction
                        startDash(events: &events)
                    } else {
                        // Up to walking speed gently; past it, or against the stick, the ground's
                        // brake, so a walk come into at a run doesn't slide on for half a second.
                        let target = walkMaxSpeed * input.stick.x
                        let braking = abs(velocity.x) > walkMaxSpeed || velocity.x * target < 0
                        velocity.x = approach(velocity.x, target, braking ? traction : walkAcceleration)
                        // The cycle runs 15 frames a second at full walk and never under 10, so the ball
                        // can't hang on a tween, at the nearest steady rate.
                        animationPhase += (Player.steady(max(abs(velocity.x) / walkMaxSpeed * 15, 10)) / 60) * waterShare
                    }
                } else {
                    enter(.idle)
                }
            }

        case .dash:
            if !groundActions(input, jumpPressed: jumpPressed, shootPressed: shootPressed, throwPressed: throwPressed,
                              tauntPressed: tauntPressed, onDefence: onDefence, events: &events) {
                if let direction = stickFacing(input), direction != facing, smash {
                    facing = direction
                    startDash(events: &events)
                } else {
                    velocity.x = dashInitialVelocity * facing.sign
                    animationPhase += (runCycleStep) * waterShare
                    if stateTimer >= spec.dashFrames {
                        enter(abs(input.stick.x) >= 0.5 && stickForward(input) ? .run : .idle)
                    }
                }
            }

        case .run:
            if !groundActions(input, jumpPressed: jumpPressed, shootPressed: shootPressed, throwPressed: throwPressed,
                              tauntPressed: tauntPressed, onDefence: onDefence, events: &events) {
                if !hasBall, downHeldFrames >= 1 {
                    // Down at full run without the ball: the slide.
                    startSlide(events: &events)
                } else if downHeldFrames >= spec.runBrakeHoldFrames {
                    // Held down: the run brakes, and at walking speed it becomes a walk.
                    velocity.x = approach(velocity.x, 0, traction)
                    animationPhase += (runCycleStep) * waterShare
                    if abs(velocity.x) <= walkMaxSpeed {
                        enter(stickFacing(input) == nil ? .idle : .walk)
                    }
                } else if let direction = stickFacing(input) {
                    if direction != facing {
                        runMomentum = abs(velocity.x)
                        enter(.pivot)
                    } else {
                        velocity.x = runSpeed * facing.sign
                        runMomentum = runSpeed
                        animationPhase += (runCycleStep) * waterShare
                    }
                } else {
                    enter(.idle)
                }
            }

        case .pivot:
            velocity.x = approach(velocity.x, 0, traction * 2)
            if jumpPressed {
                enter(.jumpSquat)
            } else if stateTimer >= spec.pivotFrames {
                facing = facing.flipped
                enter(stickForward(input) ? .run : .idle)
            }

        case .jumpSquat:
            jumpBuffer = 0
            if !holding, shootPressed, slashAllowed { pendingAerial = .slash }
            if !holding, throwPressed, throwIsSnatch { pendingAerial = .snatch }
            if stateTimer >= spec.jumpSquatFrames, power == .surfSoda {
                // Surf Soda: off on the crescent, the board under the feet.
                jumpsLeft -= 1
                startSurfJump(events: &events)
                grounded = false
                enter(.air)
            } else if stateTimer >= spec.jumpSquatFrames {
                // The pivot jump, Mario 64's: out of a run or its pivot with the stick slammed the
                // other way, the jump turns with the run's whole speed, the new way.
                if previousState == .run || previousState == .pivot, let way = stickFacing(input), runMomentum > 0,
                   velocity.x * way.sign <= 0 {
                    facing = way
                    velocity.x = runMomentum * way.sign
                }
                velocity.y = input.jump ? fullHopVelocity : shortHopVelocity
                let cap = max(abs(velocity.x), airSpeedMax)
                velocity.x = min(max(velocity.x + input.stick.x * airSpeedMax, -cap), cap)
                jumpsLeft -= 1
                platformArmed = true
                grounded = false
                wallLandCooldown = max(wallLandCooldown, spec.wallLandGroundLockoutFrames)
                events.append(.jumped(player: index))
                enter(.air)
                if let aerial = pendingAerial {
                    // The rising aerial: out of the squat straight into the move, still rising.
                    pendingAerial = nil
                    switch aerial {
                    case .slash: startSlash(events: &events)
                    case .snatch: startSnatch()
                    }
                }
            }

        case .air where surfWall != nil:
            // Surf Soda up a wall: the board against it, up at the run speed while the stick
            // holds toward it; let go, stall, or meet the ceiling and it's a backflip off.
            let wall = surfWall!
            surfAngle += (wall.sign * Double.pi / 2 - surfAngle) * 0.3
            velocity = Vec2(x: wall.sign * 0.5, y: runSpeed)
            if stickFacing(input) != wall || ridableWallSide != wall || stateTimer > 1 && position.y <= lastWallRideY {
                leapOffWall(wall)
            }
            lastWallRideY = position.y

        case .air where surfPath > 0 || surfing:
            // Surf Soda: the crescent, fixed, the body turning back with it; past its top the
            // stick spins the body instead of drifting it, the fall floats unless the fast
            // fall cuts through, and it eases upright near the ground.
            if surfPath > 0 {
                surfPath += 1
                let step = Double.pi / 2 / Double(SurfRules.pathFrames)
                let angle = Double(surfPath) * step
                velocity = Vec2(x: surfDirection * SurfRules.reach * Trig.sin(angle) * step, y: SurfRules.rise * Trig.cos(angle) * step)
                surfAngle += surfDirection * surfTurn / Double(SurfRules.pathFrames)
                if surfPath >= SurfRules.pathFrames { surfPath = 0 }
            } else if surfFlip > 0 {
                surfFlip -= 1
                surfAngle += surfFlipRate
                floatDown(input)
            } else {
                floatDown(input)
                // Spinning it by hand is level two's: toward the way it faces is a backspin.
                if powerLevel >= 2 { surfAngle += input.stick.x * SurfRules.spinRate }
            }
            let drop = stage.drop(fromX: position.x, y: position.y)
            // Upright again near the ground, or whenever the stick isn't spinning it.
            if surfPath == 0, surfFlip == 0, drop < SurfRules.uprightHeight || stickFacing(input) == nil || powerLevel < 2 {
                // The nearest upright, not always back the way it came.
                let turns = (surfAngle / (2 * Double.pi)).rounded()
                surfAngle += (turns * 2 * Double.pi - surfAngle) * SurfRules.uprightShare
            }
            if powerLevel >= 2, surfPath == 0, let wall = ridableWallSide, stickFacing(input) == wall, wallLandCooldown == 0 {
                // Onto a wall anywhere up it, held into it: the ride, as a wall land would be.
                startWallRide(wall)
            } else if surfWall == nil, jumpPressed, jumpsLeft > 0 {
                jumpsLeft -= 1
                startSurfJump(backflip: true, events: &events)
                events.append(.doubleJumped(player: index))
            } else if holding, input.shoot, shootReady {
                enterShootStance()
            } else if holding, input.throwBall, throwReady {
                throwDirection = .zero
                quickThrow = false
                throwStanceEntrySpeed = velocity.x
                enter(.throwStance)
            } else if !holding, throwPressed, snatchCooldown == 0, throwIsSnatch {
                startSnatch()
            } else if !holding, shootPressed, slashAllowed {
                startSlash(events: &events)
            }

        case .air:
            // The body turns with the stick in the air, at once.
            if airControlLock == 0, let direction = stickFacing(input) { facing = direction }
            // Into a stance the stick aims, not steers, so the frame it starts on coasts too.
            let stancing = holding && ((input.shoot && shootReady) || (input.throwBall && throwReady))
            if airControlLock > 0 || stancing { airCoast() } else { airDrift(input) }
            fall(input)
            if jumpPressed, coyote > 0 {
                // Just off an edge: the jump the ground would have given.
                jumpBuffer = 0
                coyote = 0
                velocity.y = input.jump ? fullHopVelocity : shortHopVelocity
                jumpsLeft = spec.jumps - 1
                platformArmed = true
                fastFalling = false
                events.append(.jumped(player: index))
            } else if wallLandCooldown == 0, let wall = wallSide, stickFacing(input) == wall {
                facing = wall
                velocity = .zero
                platformArmed = true
                enter(.wallLand)
            } else if power == .superSmoothie, jumpPressed, flightLeft > 0 {
                // A fresh press in the air starts flight; holding keeps it.
                jumpBuffer = 0
                jumpsLeft = 0
                fastFalling = false
                velocity = .zero
                events.append(.flew(player: index))
                enter(.flying)
            } else if power == .webWater, jumpPressed, swingCooldown == 0 {
                startWebSwing(events: &events)
            } else if power == .flashFizz, jumpPressed, (flashCharges ?? FizzRules.flashCharges(level: powerLevel)) > 0 {
                // Flash Fizz's flash is the double jump: five tiles along the stick, or in place.
                jumpBuffer = 0
                let left = (flashCharges ?? FizzRules.flashCharges(level: powerLevel)) - 1
                flashCharges = left
                if left == 0 { warpCooldown = FizzRules.cooldownFrames }
                wanted = .flash(direction: input.stick.length > 0.3 ? input.stick.normalized : .zero)
            } else if jumpPressed, jumpsLeft > 0, power != .superSmoothie, power != .webWater, power != .flashFizz {
                doubleJump(input, events: &events)
            } else if holding, input.shoot, shootReady {
                enterShootStance()
            } else if holding, input.throwBall, throwReady {
                throwDirection = .zero
                quickThrow = false
                fastFalling = false
                throwStanceEntrySpeed = velocity.x
                enter(.throwStance)
            } else if !holding, fireballAsked(input, shootPressed: shootPressed, throwPressed: throwPressed) {
                summonFireball(events: &events)
            } else if !holding, throwPressed, snatchCooldown == 0, throwIsSnatch {
                startSnatch()
            } else if !holding, throwPressed, power == .pulsepistol, powerLevel >= 2, pulseCooldown == 0 {
                startGunShot(pull: true)
            } else if !holding, shootPressed, power == .platformShake, powerLevel >= 2, wallCooldown == 0 {
                startWall()
            } else if !holding, shootPressed, power == .zeusJuice, boltCooldown == 0 {
                fireBolt(input)
            } else if !holding, shootPressed, power == .pulsepistol, pulseCooldown == 0 {
                startGunShot(pull: false)
            } else if !holding, shootPressed, slashAllowed {
                startSlash(events: &events)
            }

        case .wallLand:
            // Silksong's rule: the slide lasts as long as the stick is held into the wall.
            // Web Water doesn't slide at all.
            velocity = Vec2(x: 0, y: power == .webWater ? 0 : -spec.wallSlideSpeed)
            if jumpPressed {
                wallJump(off: facing, events: &events)
            } else if input.stick.y <= -0.5, !webAiming {
                // Down lets go, and the wall can't be clung to again at once.
                wallLandCooldown = spec.wallLandCooldownFrames
                enter(.air)
            } else if wallSide == nil || (stickFacing(input) != facing && !webAiming) {
                // Aiming a web line holds the cling whatever the stick does.
                enter(.air)
            }

        case .land:
            velocity.x = approach(velocity.x, 0, traction)
            if stateTimer >= spec.landingLagFrames {
                enter(crouchAsked(input) ? .crouch : (stickFacing(input) == nil ? .idle : .walk))
            }

        case .shootStance:
            if stanceTimerJustEntered { stanceButtons = input.shootButtons }
            if input.shootButtons & ~stanceButtons != 0 || throwPressed {
                // A shoot button other than the one that took the stance, or the throw: the cancel.
                cancelShot()
                throwReady = !throwPressed
                break
            }
            stanceMovement(input, airBrake: stanceAirBrake)
            if downHeldFrames == 0 { stepbackAimLocked = false }
            if input.aim.length >= BallRules.flickThreshold, !stepbackAimLocked {
                shotAim = input.aim
                if shotAim.x != 0 { facing = shotAim.x > 0 ? .right : .left }
            } else if let direction = stickFacing(input) {
                // The stick turns the body throughout, so touch can turn as the pad does.
                facing = direction
            }
            if grounded, jumpPressed {
                jumpBuffer = 0
                velocity.y = fullHopVelocity
                jumpsLeft = 0
                grounded = false
                jumpShot = true
                events.append(.jumped(player: index))
            }
            // Down on the ground asks for the stepback, which comes once the stance is held.
            if grounded, downHeldFrames == 1 { stepbackAsked = true }
            if grounded, stepbackAsked, stateTimer >= BallRules.shotWindupFrames, !stepbackUsed, hasBall || hasFireball {
                startStepback(from: .shootStance, events: &events)
                break
            }
            if !input.shoot, !quickShot {
                // Letting go always follows through: now, or when the windup ends.
                if stateTimer < BallRules.shotWindupFrames {
                    quickShot = true
                } else {
                    releaseShot()
                }
            }
            if quickShot, stateTimer >= BallRules.shotWindupFrames {
                releaseShot()
            }

        case .shooting:
            if grounded {
                velocity.x = approach(velocity.x, 0, traction)
            } else if stateTimer > BallRules.shotReleaseFrames {
                // Hanging after the release, in the pose.
                velocity.x = approach(velocity.x, 0, stanceAirBrake)
                velocity.y = 0
            } else {
                airCoast()
                fall(.idle)
            }
            if reached(BallRules.shotReleaseFrames) {
                let lift = shotLift ? max(velocity.y, 0) : 0
                if hasFireball {
                    hasFireball = false
                    action = .releaseFireball(velocity: shotVelocity + Vec2(x: 0, y: lift), straight: false, ballArc: quickShot)
                } else {
                    hasBall = false
                    catchCooldown = BallRules.catchCooldownFrames
                    action = .releaseShot(velocity: shotVelocity + Vec2(x: 0, y: lift))
                }
                events.append(.shot(player: index))
            } else if stateTimer >= BallRules.shotReleaseFrames + (grounded ? BallRules.shotRecoveryFrames : BallRules.shotHangFrames) {
                fastFalling = false
                enter(grounded ? .idle : .air)
            }

        case .throwStance:
            if shootPressed {
                // The shoot button cancels the throw.
                shootReady = false
                throwReady = false
                enter(grounded ? .idle : .air)
                break
            }
            if jumpPressed, grounded || coyote > 0 || jumpsLeft > 0 {
                // Jump cancels the charge: on the ground into the jump; in the air the
                // buffered press takes the air's jump next frame.
                throwReady = false
                quickThrow = false
                if grounded {
                    pendingAerial = nil
                    enter(.jumpSquat)
                } else {
                    enter(.air)
                }
                break
            }
            if grounded, downHeldFrames == 1 { stepbackAsked = true }
            if grounded, stepbackAsked, stateTimer >= BallRules.throwWindupFrames, !stepbackUsed {
                startStepback(from: .throwStance, events: &events)
                break
            }
            stanceMovement(input, airBrake: throwStanceAirBrake)
            let aim = input.aim.length >= BallRules.flickThreshold ? input.aim : input.stick
            if downHeldFrames == 0 { stepbackAimLocked = false }
            if aim.length >= 0.5, !stepbackAimLocked {
                throwDirection = abs(aim.x) >= abs(aim.y) ? Vec2(x: aim.x > 0 ? 1 : -1, y: 0) : Vec2(x: 0, y: aim.y > 0 ? 1 : -1)
                if throwDirection.x != 0 { facing = throwDirection.x > 0 ? .right : .left }
            }
            if stanceTimerJustEntered, hasBall, power == .zeusJuice, powerLevel >= 2, strikeCooldown == 0 {
                // Zeus Juice: the charge calls a strike down onto the ball in hand.
                strikeCooldown = ZeusRules.strikeCooldownFrames
                // Onto the ball where the stance's sheet draws it, a little behind the chest.
                let ball = BallLandmarks.offset(animationFrame).map { position + Vec2(x: $0.x / 1.6 * spec.scale * facing.sign, y: $0.y / 1.6 * spec.scale) }
                    ?? Vec2(x: chest.x - facing.sign * 5, y: chest.y + 3)
                wanted = .strikeBolt(x: ball.x, bottom: ball.y)
            }
            if hasBall, stateTimer >= BallRules.dunkStanceFrames, let hoop = stage.hoops.indices.first(where: { stage.hoops[$0].position.distance(to: chest) <= BallRules.dunkRadius * spec.scale && stage.dunkable(stage.hoops[$0]) }) {
                // Onto the rim: the feet at the dunk's place on it, facing the backboard.
                // Turned to the backboard; the body glides to its place on the rim through
                // the wind-up, so it never jumps there.
                facing = stage.hoops[hoop].backboard
                velocity = .zero
                dunkHoop = hoop
                dunkFrom = position
                enter(.dunking)
            } else if !input.throwBall, !quickThrow {
                if stateTimer >= BallRules.throwWindupFrames {
                    enter(.throwing)
                } else {
                    // Let go early: the throw goes when the windup ends, where the stick pointed.
                    quickThrow = true
                }
            }
            if quickThrow, stateTimer >= BallRules.throwWindupFrames {
                enter(.throwing)
            }

        case .throwing:
            if grounded {
                velocity.x = approach(velocity.x, 0, traction)
            } else {
                airCoast()
                fall(.idle)
            }
            if reached(BallRules.throwReleaseFrames) {
                let direction = throwDirection == .zero ? Vec2(x: facing.sign, y: 0) : throwDirection
                if hasFireball {
                    hasFireball = false
                    action = .releaseFireball(velocity: direction * BallRules.throwSpeed, straight: true, ballArc: false)
                } else {
                    hasBall = false
                    catchCooldown = BallRules.catchCooldownFrames
                    action = .releaseThrow(velocity: direction * BallRules.throwSpeed)
                }
                events.append(.thrown(player: index))
            } else if stateTimer >= BallRules.throwRecoveryFrames {
                enter(grounded ? .idle : .air)
            }

        case .dunking:
            // To the rim over the wind-up, there by the slam, then hanging through the dunk
            // and the beat after, until the point restarts; the ball leaves the hand at the slam.
            velocity = .zero
            let rim = stage.hoops[dunkHoop]
            // The feet's place off the rim, at the body's size, so the hands still meet it.
            let place = rim.position + Vec2(x: BallRules.dunkOffset.x * rim.backboard.sign, y: BallRules.dunkOffset.y) * spec.scale
            let slam = BallRules.dunkFrames / 2
            let share = min(Double(stateTimer) / Double(slam), 1)
            position = dunkFrom + (place - dunkFrom) * share
            if reached(BallRules.dunkFrames / 2) {
                hasBall = false
                catchCooldown = BallRules.catchCooldownFrames
                events.append(.dunked(player: index))
                action = .dunk(hoop: dunkHoop)
            } else if stateTimer >= BallRules.dunkFrames + BallRules.dunkHangFrames
                        || stateTimer > BallRules.dunkFrames / 2 && input.stick.y <= -0.5 {
                // Hung on the rim through the beat after, or let go with down once it's slammed.
                enter(grounded ? .idle : .air)
            }

        case .catching:
            if grounded {
                velocity.x = 0
            } else {
                fall(.idle)
            }
            if stateTimer >= 15 {
                enter(grounded ? .idle : .air)
            }

        case .crouch, .crouchWalk:
            // Down with no ball. The crouch walk is slow, and the stick turns the body.
            if let direction = stickFacing(input) { facing = direction }
            if state == .crouchWalk {
                velocity.x = approach(velocity.x, spec.crouchWalkSpeed * waterShare * input.stick.x, walkAcceleration)
                animationPhase += (Player.steady(max(abs(velocity.x) / spec.crouchWalkSpeed * 15, 10)) / 60) * waterShare
            } else {
                velocity.x = approach(velocity.x, 0, traction)
            }
            if jumpPressed {
                enter(.jumpSquat)
            } else if throwPressed, snatchCooldown == 0, throwIsSnatch {
                startSnatch()
            } else if shootPressed {
                // Shoot while crouched: the slide, in neutral or on defence alike.
                startSlide(events: &events)
            } else if !crouchAsked(input), roomToStand(in: stage) {
                enter(stickFacing(input) == nil ? .idle : .walk)
            } else if state == .crouch, snipes, stateTimer >= SnipeRules.holdFrames {
                // Pulsepistol Punch at level two: down held goes prone into the snipe.
                snipeCursor = Vec2(x: position.x + facing.sign * SnipeRules.cursorStart, y: position.y + PulseRules.handHeight)
                snipeFire = 0
                enter(.gunSnipe)
            } else if (input.stick.x != 0) != (state == .crouchWalk) {
                enter(input.stick.x != 0 ? .crouchWalk : .crouch)
            }

        case .gunSnipe:
            // Prone: the stick moves the cursor, not the body; shoot repels and throw
            // attracts at it; jump gets up.
            velocity.x = approach(velocity.x, 0, traction)
            let top = Double(stage.rows + Stage.skyRows) * Stage.tileSize
            snipeCursor = Vec2(x: min(max(snipeCursor.x + input.stick.x * SnipeRules.cursorSpeed, 0), stage.width),
                               y: min(max(snipeCursor.y + input.stick.y * SnipeRules.cursorSpeed, 0), top))
            if snipeFire > 0 {
                snipeFire += 1
                if snipeFire == SnipeRules.fireFrame { wanted = .snipe(at: snipeCursor, pull: snipePull) }
                if snipeFire >= SnipeRules.shotFrames { snipeFire = 0 }
            }
            if jumpPressed {
                snipeFire = 0
                enter(.idle)
            } else if snipeFire == 0, shootPressed || throwPressed, pulseCooldown == 0 {
                snipeFire = 1
                snipePull = !shootPressed
                pulseCooldown = PulseRules.cooldownFrames
            }

        case .slide:
            // The leg out front, the body low, the burst carried nearly whole; then up into
            // the skid, or a crouch if down is still held. On Frost Tea it's ice: no
            // friction and no end, until jump, throw, shoot, the stick, or down let go
            // cancel it.
            // Down a slope the slide is forced: no friction, no timer, nothing to do but a jump,
            // until it reaches flat ground, or open air, which the fall out of a ground state ends.
            if grounded, stage.slopeDescends(under: body, facing: facing, reach: SlopeRules.step) {
                forcedSlide = true
            } else if grounded {
                forcedSlide = false
            }
            if forcedSlide {
                velocity.x = approach(velocity.x, dashInitialVelocity * facing.sign, SlopeRules.slideGain * waterShare)
                if jumpPressed { enter(.jumpSquat) }
            } else if power == .frostTea {
                if jumpPressed {
                    enter(.jumpSquat)
                } else if throwPressed, snatchCooldown == 0 {
                    startSnatch()
                } else if shootPressed, slashAllowed {
                    startSlash(events: &events)
                } else if !crouchAsked(input) || (input.stick.x != 0 && !stickForward(input)) {
                    enter(roomToStand(in: stage) ? standUp(from: input) : .crouch)
                }
            } else {
                velocity.x = approach(velocity.x, 0, slideFriction)
                if stateTimer >= spec.slideFrames {
                    enter(crouchAsked(input) || !roomToStand(in: stage) ? .crouch : standUp(from: input))
                }
            }

        case .slashing:
            // On the ground the swing carries the run it came from, bleeding it off; in the
            // air gravity is cut, so the body hangs through it, and the roll follows.
            if grounded {
                velocity.x = approach(velocity.x, 0, attackBrake)
            } else {
                velocity.x = approach(velocity.x, 0, airBrake)
                velocity.y = max(velocity.y - gravity * SlashRules.gravityShare, -fallSpeed)
            }
            if stateTimer >= SlashRules.frames {
                endSlash()
            }

        case .rolling:
            airDrift(input)
            fall(.idle)
            if stateTimer >= SlashRules.rollFrames {
                enter(.air)
            }

        case .snatching:
            if grounded {
                velocity.x = approach(velocity.x, 0, attackBrake)
            } else {
                airDrift(input)
                fall(.idle)
            }
            if reached(SnatchRules.sparkFrame) {
                events.append(.snatchReached(player: index))
                if power == .zeusJuice, powerLevel >= 2, strikeCooldown == 0 {
                    // Zeus Juice: the strike down onto the hand at full stretch.
                    strikeCooldown = ZeusRules.strikeCooldownFrames
                    wanted = .strikeBolt(x: handCatchPoint.x, bottom: handCatchPoint.y)
                }
            }
            if stateTimer >= SnatchRules.frames {
                snatchCooldown = SnatchRules.cooldownFrames
                enter(grounded ? .idle : .air)
            }

        case .stepback:
            // Straight back at an even speed, the facing kept; off an edge the stance is lost.
            if !grounded {
                enter(.air)
            } else if stateTimer >= StepbackRules.frames {
                velocity.x = 0
                let hold = stepbackFrom == .shootStance ? BallRules.shotWindupFrames : BallRules.throwWindupFrames
                enter(stepbackFrom)
                stateTimer = hold
            } else {
                velocity = Vec2(x: -facing.sign * StepbackRules.distance / Double(StepbackRules.frames), y: 0)
            }

        case .walling:
            // The snatch's reach, and the wall appears at the hand's full stretch.
            if grounded {
                velocity.x = approach(velocity.x, 0, attackBrake)
            } else {
                airDrift(input)
                fall(.idle)
            }
            if reached(ShakeRules.wallAppearFrame) {
                action = .makeWall
            }
            if stateTimer >= ShakeRules.wallFrames {
                enter(grounded ? .idle : .air)
            }

        case .ledgeHang:
            velocity = .zero
            if input.stick.y <= -0.5 {
                // Down drops off, and the ledge isn't grabbed again at once.
                ledge = nil
                ledgeCooldown = LedgeRules.walkOffCooldownFrames
                enter(.air)
            } else if stateTimer >= LedgeRules.hangFrames {
                enter(.ledgeClimb)
            }

        case .ledgeClimb:
            // Up in three steps with the sheet: hanging, astride the corner, standing on it.
            velocity = .zero
            guard let corner = ledge else { enter(.air); break }
            position = ledgePositions(at: corner)[min((stateTimer - 1) * 3 / LedgeRules.climbFrames, 2)]
            if stateTimer >= LedgeRules.climbFrames {
                ledge = nil
                enter(.idle)
            }

        case .taunt:
            // The sauce is only for show: anything cancels it, the stick walks out of it.
            velocity.x = 0
            if groundActions(input, jumpPressed: jumpPressed, shootPressed: shootPressed, throwPressed: throwPressed,
                             tauntPressed: false, onDefence: onDefence, events: &events) {
                break
            }
            if stickFacing(input) != nil, input.stick.y >= -0.65 {
                enter(.walk)
            } else if stateTimer >= 44 {
                enter(.idle)
            }

        case .webSwing:
            // A pendulum under the anchor: the least arc always, further while jump is held,
            // up to twice the least arc and never over the anchor.
            guard let anchor = webAnchor else { enter(.air); break }
            let pace = swingLeastArc / Double(WebRules.swingFrames) * facing.sign
            let easeIn = min(Double(stateTimer) / 4, 1)
            swingAngle += pace * easeIn
            let swept = (swingAngle - swingStartAngle) * facing.sign
            let target = anchor + Vec2(x: Trig.sin(swingAngle), y: -Trig.cos(swingAngle)) * swingLength
            velocity = target - position
            let full = swept >= swingLeastArc * WebRules.swingMaxArcShare || abs(swingAngle) >= WebRules.swingMaxAngle
            if full || (swept >= swingLeastArc && !input.jump) {
                // The exit keeps the arc's direction but not all its speed, so the stick can turn it.
                endSwing()
                velocity.x = min(max(velocity.x, -airSpeedMax), airSpeedMax)
                velocity.y = min(velocity.y, fullHopVelocity)
                enter(.air)
            }

        case .flying:
            // Any direction, slowly, gravity off, while jump is held and the budget lasts;
            // at level two the stick forward is the glide: fast, sinking unless up is held,
            // diving on down. The body keeps facing the way it did.
            flightLeft -= 1
            let forward = input.stick.x * facing.sign
            if powerLevel >= 2, forward > 0.3 {
                let vertical: Double
                if input.stick.y > 0.3 {
                    vertical = input.stick.y * SmoothieRules.flightSpeed(level: powerLevel, withBall: hasBall)
                } else if input.stick.y < -0.3 {
                    vertical = -SmoothieRules.diveSpeed
                } else {
                    vertical = -SmoothieRules.glideSink
                }
                velocity = Vec2(x: facing.sign * forward * SmoothieRules.glideSpeed(withBall: hasBall), y: vertical)
            } else {
                velocity = input.stick * SmoothieRules.flightSpeed(level: powerLevel, withBall: hasBall)
            }
            if holding, input.shoot, shootReady {
                enterShootStance()
            } else if holding, input.throwBall, throwReady {
                throwDirection = .zero
                quickThrow = false
                throwStanceEntrySpeed = velocity.x
                enter(.throwStance)
            } else if !holding, throwPressed, snatchCooldown == 0 {
                // Flight cancels into the snatch or the slash as the air does.
                startSnatch()
            } else if !holding, shootPressed {
                startSlash(events: &events)
            } else if !input.jump || flightLeft <= 0 {
                enter(.air)
            }

        case .transforming:
            // Held still where it started, off the ground, until the sheet's played through.
            velocity = .zero
            if stateTimer >= TransformRules.frames {
                transformed = true
                enter(grounded ? .idle : .air)
            }

        case .suspended:
            // Held in a tornado: the body's middle drawn to its middle, a share of the way a
            // frame, gravity off. Jump leaves it with a jump; the rest is as in flight.
            guard let centre = tornadoCentre else { enter(.air); break }
            let middle = Vec2(x: position.x, y: position.y + spec.bodyHeight / 2)
            velocity = (centre - middle) * TornadoRules.pullShare
            // The stick drifts it sideways, slowly, out if held long enough; let go, back to the middle.
            if abs(input.stick.x) >= 0.3 {
                velocity.x = input.stick.x * airSpeedMax * TornadoRules.driftShare
                facing = input.stick.x > 0 ? .right : .left
            }
            if jumpPressed {
                jumpBuffer = 0
                velocity = Vec2(x: velocity.x, y: fullHopVelocity)
                jumpsLeft = spec.jumps - 1
                tornadoCooldown = TornadoRules.jumpOutCooldownFrames
                events.append(.jumped(player: index))
                enter(.air)
            } else if holding, input.shoot, shootReady {
                enterShootStance()
            } else if holding, input.throwBall, throwReady {
                throwDirection = .zero
                quickThrow = false
                throwStanceEntrySpeed = velocity.x
                enter(.throwStance)
            } else if !holding, throwPressed, snatchCooldown == 0 {
                startSnatch()
            } else if !holding, shootPressed {
                startSlash(events: &events)
            }

        case .gunShoot:
            // Pulsepistol Punch's shot, standing: braked, the pulse on its frame.
            if grounded {
                velocity.x = approach(velocity.x, 0, traction)
            } else {
                airCoast()
                fall(.idle)
            }
            if reached(PulseRules.fireFrame) {
                wanted = .pulse(pull: gunPull)
            }
            if stateTimer >= PulseRules.shotFrames {
                enter(grounded ? .idle : .air)
            }

        case .webPull, .webbed:
            // Reeled straight at the target, dropped there or wherever it gets stuck.
            guard let target = pullTarget else { enter(grounded ? .idle : .air); break }
            let gap = target - position
            velocity = gap.length <= WebRules.pullSpeed ? gap : gap.normalized * WebRules.pullSpeed
            if gap.length <= 1 || stateTimer >= WebRules.pullMaxFrames {
                endPull()
            }
        }

        if throwingBolt, state.isGroundState {
            velocity.x = approach(boltCarry, 0, attackBrake)
        }
        if let downhill = surfingDownSlide, state.isGroundState, state != .jumpSquat {
            if state != .run { enter(.run) }
            facing = downhill
            velocity.x = approach(velocity.x, downhill.sign * runSpeed, SlopeRules.slideGain * waterShare)
        }
        if let downhill = slideSlopeResisted, state == .walk {
            facing = downhill.flipped
            velocity.x = downhill.sign * walkMaxSpeed * SlopeRules.slideSlopePushBack
        }
        if action == nil, wantsPlatform {
            action = .makePlatform
        }
        wantsPlatform = false
        let feetBefore = position.y
        move(in: stage)
        bounceOffRims(in: stage, feetBefore: feetBefore, events: &events)
        // Surf Soda: running into a wall with the stick held toward it takes the board up it.
        if power == .surfSoda, powerLevel >= 2, grounded, state == .run || state == .dash || state == .walk, let wall = ridableWallSide, stickFacing(input) == wall {
            startWallRide(wall)
        }
        // Surf Soda on the ground: up into the wheelie at a run, back down to upright else.
        if power == .surfSoda, grounded, !surfing, surfWall == nil {
            let target = state == .run || state == .dash ? facing.sign * SurfRules.wheelie : 0
            surfAngle += (target - surfAngle) * SurfRules.wheelieShare
            if target == 0, abs(surfAngle) < 0.02 { surfAngle = 0 }
        }
        if state == .webSwing, let anchor = webAnchor {
            let target = anchor + Vec2(x: Trig.sin(swingAngle), y: -Trig.cos(swingAngle)) * swingLength
            if position.distance(to: target) > 1 {
                endSwing()
                enter(.air)
            }
        }
        settle(input, events: &events)
        grabLedgeIfThere(in: stage, events: &events)
        // Blazing Boba: a flame every few frames of a full run or a slide.
        if power == .blazingBoba, grounded, state == .slide || (state == .run && abs(velocity.x) >= runSpeed - 0.01) {
            flameTimer += 1
            if flameTimer % BlazeRules.flameEveryFrames == 0, wanted == nil { wanted = .leaveFlame }
        } else {
            flameTimer = 0
        }
        if action == nil, let asked = wanted {
            action = asked
        }
        wanted = nil
        lastInput = input
        return action
    }

    /// Whether shoot without the ball is the slash: not for the powers that take the
    /// button for their own thing.
    private var slashAllowed: Bool {
        !power.takesShoot && !(power == .platformShake && powerLevel >= 2)
    }

    /// Whether throw without the ball is the snatch: Web Water's line and Pulsepistol's
    /// pull take the button at level two.
    private var throwIsSnatch: Bool {
        !(power == .webWater && powerLevel >= 2) && !(power == .pulsepistol && powerLevel >= 2)
    }

    /// Blazing Boba at level two: shoot and throw together, one pressed with the other
    /// down, with nothing in hand.
    private func fireballAsked(_ input: PlayerInput, shootPressed: Bool, throwPressed: Bool) -> Bool {
        power == .blazingBoba && powerLevel >= 2 && !holding
            && ((shootPressed && input.throwBall) || (throwPressed && input.shoot))
    }

    private mutating func summonFireball(events: inout [MatchEvent]) {
        hasFireball = true
        summonPose = BlazeRules.summonPoseFrames
        // Both have to come up before either can take a stance with it.
        shootReady = false
        throwReady = false
        events.append(.fireballMade(player: index))
    }

    /// Zeus Juice's bolt: straight ahead, tilted by the stick up to the limit.
    private mutating func fireBolt(_ input: PlayerInput) {
        boltCooldown = ZeusRules.boltCooldownFrames
        // Thrown: the whole throw sheet plays, and the bolt leaves on its release frame the
        // way the body faces then.
        boltPose = ZeusRules.boltPoseFrames
    }

    /// Pulsepistol Punch's shot: on the run at level two it fires in stride; otherwise the
    /// standing shot, which fires on its frame.
    private mutating func startGunShot(pull: Bool) {
        pulseCooldown = PulseRules.cooldownFrames
        if powerLevel >= 2, state == .run || state == .dash {
            gunRunTimer = PulseRules.runShotFrames
            wanted = .pulse(pull: pull)
        } else {
            gunPull = pull
            fastFalling = false
            enter(.gunShoot)
        }
    }

    /// Hit: whatever the body was doing is over and it's sent this way through the air.
    /// The ball, if held, is the match's to pop.
    public mutating func knock(_ push: Vec2) {
        webAnchor = nil
        pullTarget = nil
        ledge = nil
        wantsPlatform = false
        velocity = push * spec.knockbackShare
        // Knocked out of a tornado, it doesn't take the body straight back.
        if state == .suspended { tornadoCooldown = TornadoRules.jumpOutCooldownFrames }
        knockedAloft = true
        grounded = false
        fastFalling = false
        enter(.air)
    }

    // MARK: Pieces of the step

    /// Jumps, stances and the taunt, shared by every standing state, and without the ball
    /// the snatch and, on defence, the Esper Slash. True when one fired.
    private mutating func groundActions(_ input: PlayerInput, jumpPressed: Bool, shootPressed: Bool, throwPressed: Bool,
                                        tauntPressed: Bool, onDefence: Bool, events: inout [MatchEvent]) -> Bool {
        if jumpPressed {
            pendingAerial = nil
            if !holding, shootPressed, slashAllowed { pendingAerial = .slash }
            if !holding, throwPressed, throwIsSnatch { pendingAerial = .snatch }
            enter(.jumpSquat)
        } else if !holding, fireballAsked(input, shootPressed: shootPressed, throwPressed: throwPressed) {
            summonFireball(events: &events)
        } else if holding, input.shoot, shootReady {
            enterShootStance()
        } else if holding, input.throwBall, throwReady {
            throwDirection = .zero
            quickThrow = false
            throwStanceEntrySpeed = velocity.x
            enter(.throwStance)
        } else if hasBall, tauntPressed || (input.stick.y < -0.65 && lastInput.stick.y >= -0.65 && (state == .idle || state == .walk)) {
            // The sauce: the taunt sheet, on the button or on down with the ball standing
            // or walking, for show. A run holding down brakes instead.
            enter(.taunt)
        } else if !holding, throwPressed, snatchCooldown == 0, throwIsSnatch {
            startSnatch()
        } else if !holding, throwPressed, power == .pulsepistol, powerLevel >= 2, pulseCooldown == 0 {
            startGunShot(pull: true)
        } else if !holding, shootPressed, power == .platformShake, powerLevel >= 2, wallCooldown == 0 {
            startWall()
        } else if !holding, shootPressed, power == .zeusJuice, boltCooldown == 0 {
            fireBolt(input)
        } else if !holding, shootPressed, power == .pulsepistol, pulseCooldown == 0 {
            startGunShot(pull: false)
        } else if !holding, shootPressed, slashAllowed {
            startSlash(events: &events)
        } else {
            return false
        }
        return true
    }

    /// Down on the stick with nothing in hand.
    /// Pulsepistol Punch at level two, with nothing in hand: a held crouch goes into the snipe.
    private var snipes: Bool { power == .pulsepistol && powerLevel >= 2 && !holding }

    private func crouchAsked(_ input: PlayerInput) -> Bool {
        spec.canCrouch && !holding && input.stick.y < -0.65
    }

    /// The slide: the dash burst the way the body faces, the leg out. Frost Tea at level
    /// two leaves an ice clone where it began.
    private mutating func startSlide(events: inout [MatchEvent]) {
        slideHit = false
        velocity.x = dashInitialVelocity * facing.sign
        events.append(.slid(player: index))
        if power == .frostTea, powerLevel >= 2 { wanted = .leaveClone }
        enter(.slide)
    }

    /// The Esper Slash. In the air the body rises at least the lift, so it floats.
    private mutating func startSlash(events: inout [MatchEvent]) {
        slashHit = false
        fastFalling = false
        if !grounded { velocity.y = max(velocity.y, SlashRules.lift) }
        events.append(.slashed(player: index))
        enter(.slashing)
    }

    /// After the swing: on the ground it's over; in the air, the roll.
    private mutating func endSlash() {
        enter(grounded ? .idle : .rolling)
    }

    private mutating func startSnatch() {
        fastFalling = false
        enter(.snatching)
    }

    /// Platform Protein Shake's wall, on the snatch's reach.
    private mutating func startWall() {
        fastFalling = false
        enter(.walling)
    }

    /// Falling past a corner within a hand's reach with no ball: the hang, on either side,
    /// the body turned to face it. Not into anything solid, and not for a while after
    /// walking off an edge, so leaving a ledge doesn't grab it back.
    /// The ledge's numbers at the body's size.
    private var ledgeHangDepth: Double { LedgeRules.hangDepth * spec.scale }
    private var ledgeGrabReach: Double { LedgeRules.grabReach * spec.scale }
    private var ledgeGrabSlack: Double { LedgeRules.grabSlack * spec.scale }

    private mutating func grabLedgeIfThere(in stage: Stage, events: inout [MatchEvent]) {
        guard state == .air, !hasBall, velocity.y <= 0, ledgeCooldown == 0 else { return }
        let hand = position.y + ledgeHangDepth
        for side in [facing, facing.flipped] {
            guard let corner = stage.ledge(beside: body, side: side, reach: ledgeGrabReach,
                                           top: (hand - ledgeGrabSlack)...(hand + ledgeGrabSlack)) else { continue }
            let hang = Vec2(x: corner.x - side.sign * spec.bodyWidth / 2, y: corner.y - ledgeHangDepth)
            let hung = Box(min: Vec2(x: hang.x - spec.bodyWidth / 2, y: hang.y), max: Vec2(x: hang.x + spec.bodyWidth / 2, y: hang.y + spec.bodyHeight))
            guard !stage.overlapsSolid(hung) else { continue }
            facing = side
            position = hang
            velocity = .zero
            fastFalling = false
            ledge = corner
            events.append(.ledgeGrabbed(player: index))
            enter(.ledgeHang)
            return
        }
    }

    /// Where the feet go through a climb of `corner`, facing it: hanging beside it, astride
    /// it, and standing a unit in from its edge.
    private func ledgePositions(at corner: Vec2) -> [Vec2] {
        let half = spec.bodyWidth / 2
        return [Vec2(x: corner.x - facing.sign * half, y: corner.y - ledgeHangDepth),
                Vec2(x: corner.x, y: corner.y - ledgeHangDepth / 2),
                Vec2(x: corner.x + facing.sign * (half + 1), y: corner.y)]
    }

    // MARK: Hitboxes

    /// The extended leg while sliding, until it has hit.
    public var slideHitbox: Box? {
        guard state == .slide, !slideHit, frozen == 0 else { return nil }
        let front = position.x + facing.sign * spec.bodyWidth / 2
        let tip = front + facing.sign * SlideRules.legReach * spec.scale
        return Box(min: Vec2(x: min(front, tip), y: position.y), max: Vec2(x: max(front, tip), y: position.y + SlideRules.legHeight * spec.scale))
    }

    /// The blade: a square round the body over the slash's live frames, until it has hit.
    public var slashHitbox: Box? {
        guard state == .slashing, !slashHit, frozen == 0, SlashRules.liveFrames.contains(stateTimer) else { return nil }
        return Box(center: bladeCentre, width: SlashRules.reach * 2 * spec.scale, height: SlashRules.reach * 2 * spec.scale)
    }

    /// Whether the snatch's reach touches a box: the snatcher's body, or the hand's catch ring.
    /// Every snatch's, whatever the drink; an upgrade only adds what it does on a touch.
    public func snatchReaches(box: Box) -> Bool {
        guard let body = snatchHitbox else { return false }
        return box.overlaps(body) || box.distance(to: handCatchPoint) <= BallRules.handCatchRadius * spec.scale
    }

    /// Whether the snatch's reach takes a ball centred here.
    public func snatchReaches(ballAt at: Vec2) -> Bool {
        snatchReaches(box: Box(center: at, width: BallRules.radius * 2, height: BallRules.radius * 2))
    }

    /// The body, the part of the snatch's reach that isn't the hand's ring, while the hand is out.
    public var snatchHitbox: Box? {
        guard state == .snatching, frozen == 0, SnatchRules.activeFrames.contains(stateTimer) else { return nil }
        return body
    }

    /// Web Water's line, on the throw button with no ball: held, it aims along the stick;
    /// let go, it fires that way, or forward if the stick never moved.
    private mutating func webLineIfAsked(_ input: PlayerInput, throwPressed: Bool) -> PlayerAction? {
        guard power == .webWater, powerLevel >= 2, !holding else { webAiming = false; return nil }
        if throwPressed, webLineCooldown == 0, !webAiming {
            webAiming = true
            webAimDirection = Vec2(x: facing.sign, y: 0)
        }
        guard webAiming else { return nil }
        let aim = input.aim.length >= BallRules.flickThreshold ? input.aim : input.stick
        if aim != .zero {
            webAimDirection = aim.normalized
            // On a wall the body keeps facing the wall; elsewhere it turns to the aim.
            if aim.x != 0, state != .wallLand { facing = aim.x > 0 ? .right : .left }
        }
        guard !input.throwBall else { return nil }
        webAiming = false
        webLineCooldown = WebRules.lineCooldownFrames
        webLinePose = 8
        return .webLine(direction: webAimDirection)
    }

    /// Flash Fizz on a shoot button: the warp to the ball. With the ball, only when it's
    /// dribbling over a drop of more than a tile, which counts as not having it: the warp
    /// down to it. Without the ball and the loose ball still yours, the warp to it,
    /// arriving holding it. Otherwise the button is the slash; the flash is on jump.
    private mutating func flashIfAsked(_ input: PlayerInput, shootPressed: Bool, ballOwner: Int?, stage: Stage) -> PlayerAction? {
        guard power == .flashFizz, shootPressed, warpCooldown == 0 else { return nil }
        if hasBall {
            guard let overhang = overhangBall(in: stage) else { return nil }
            warpCooldown = FizzRules.cooldownFrames
            pendingWarp = overhang
            return .warpToBall
        }
        guard ballOwner == index else { return nil }
        warpCooldown = FizzRules.cooldownFrames
        pendingWarp = nil
        return .warpToBall
    }

    /// Where the dribbled ball is when it's hanging past a ledge by more than a tile: down
    /// on the floor under it. Nil when it isn't.
    public func overhangBall(in stage: Stage) -> Vec2? {
        guard hasBall, grounded, state.isGroundState, let offset = BallLandmarks.offset(animationFrame) else { return nil }
        let ballX = position.x + offset.x / 1.6 * spec.scale * facing.sign
        let drop = stage.drop(fromX: ballX, y: position.y)
        guard drop > Stage.tileSize else { return nil }
        return Vec2(x: ballX, y: position.y - drop + BallRules.radius)
    }

    private mutating func startStepback(from stance: PlayerState, events: inout [MatchEvent]) {
        stepbackUsed = true
        stepbackAsked = false
        stepbackAimLocked = true
        shotAim = .zero
        throwDirection = .zero
        stepbackFrom = stance
        enter(.stepback)
        velocity = Vec2(x: -facing.sign * StepbackRules.distance / Double(StepbackRules.frames), y: 0)
        events.append(.steppedBack(player: index))
    }

    private mutating func enterShootStance() {
        shotAim = .zero
        quickShot = false
        jumpShot = false
        shotLift = false
        stanceButtons = 0
        enter(.shootStance)
    }

    /// The stance dropped, ball kept, and no new stance until every shoot button is up.
    private mutating func cancelShot() {
        shootReady = false
        enter(grounded ? .idle : .air)
    }

    /// Off to the shot. Released on the way up out of a jump shot, it gets the preset arc if
    /// nothing was flicked, and the body's lift.
    private mutating func releaseShot() {
        shotLift = jumpShot && velocity.y > 0
        if shotAim == .zero { shotAim = presetAim }
        enter(.shooting)
    }

    /// Web Water's swing: a web to a point ahead and above, the same wherever the body is,
    /// air movement halted.
    private mutating func startWebSwing(events: inout [MatchEvent]) {
        jumpBuffer = 0
        fastFalling = false
        let anchor = position + Vec2(x: WebRules.swingReach * facing.sign, y: WebRules.swingHeight)
        let offset = position - anchor
        swingLength = offset.length
        swingStartAngle = Trig.atan2(offset.x, -offset.y)
        swingAngle = swingStartAngle
        // Signed so the arc runs forward whichever way the body faces.
        swingLeastArc = abs(swingStartAngle) * (1 + WebRules.swingOvershoot)
        webAnchor = anchor
        velocity = .zero
        events.append(.webSwung(player: index))
        enter(.webSwing)
    }

    /// The web let go, however the swing ended, and the next swing a full swing's frames
    /// away.
    private mutating func endSwing() {
        webAnchor = nil
        swingCooldown = WebRules.swingCooldownFrames
    }

    /// Reeled to `target`, by a wall of one's own or by the other's web.
    public mutating func startPull(to target: Vec2, byOther: Bool) {
        pullTarget = target
        velocity = .zero
        fastFalling = false
        if state == .webSwing { endSwing() }
        enter(byOther ? .webbed : .webPull)
    }

    private mutating func endPull() {
        pullTarget = nil
        if state == .webPull { webLine = nil }
        velocity = .zero
        enter(grounded ? .idle : .air)
    }

    /// Flash Fizz: put down at the ball, nudged clear of anything solid, still, in the air
    /// or on the floor as it lands.
    public mutating func warp(to feet: Vec2, in stage: Stage) {
        position = feet
        position += stage.pushOut(body, reach: FizzRules.flashDistance + Stage.tileSize)
        velocity = .zero
        fastFalling = false
        webAnchor = nil
        pullTarget = nil
        enter(.air)
    }

    /// The ball taken off this body by a web.
    public mutating func loseBall() {
        hasBall = false
        catchCooldown = BallRules.catchCooldownFrames
        if inStance || state == .shooting || state == .throwing || state == .dunking {
            enter(grounded ? .idle : .air)
        }
    }

    /// The preset arc, forward at the default angle.
    private var presetAim: Vec2 {
        Vec2(x: Trig.cos(BallRules.shotAngleDefault) * facing.sign, y: Trig.sin(BallRules.shotAngleDefault))
    }

    private mutating func startDash(events: inout [MatchEvent]) {
        velocity.x = dashInitialVelocity * facing.sign
        events.append(.dashed(player: index))
        enter(.dash)
    }

    /// Off the wall, with the double jump back and the stick locked out for a moment so the
    /// arc actually leaves.
    private mutating func wallJump(off wall: Facing, events: inout [MatchEvent]) {
        jumpBuffer = 0
        jumpsLeft = max(jumpsLeft, spec.jumps - 1)
        platformArmed = true
        velocity = Vec2(x: wallJumpHorizontal * -wall.sign, y: wallJumpVertical)
        facing = wall.flipped
        fastFalling = false
        wallLandCooldown = spec.wallLandCooldownFrames
        airControlLock = spec.wallJumpControlLockFrames
        events.append(.wallJumped(player: index, wall: wall))
        enter(.air)
    }

    /// A wall within `reach` of either side of the body.
    private func wall(within reach: Double, in stage: Stage) -> Facing? {
        let wide = Box(min: Vec2(x: body.min.x - reach, y: body.min.y), max: Vec2(x: body.max.x + reach, y: body.max.y))
        return stage.wall(beside: wide)
    }

    /// Past the crescent: gravity cut and the fall slowed, unless down on the stick fast
    /// falls through it.
    private mutating func floatDown(_ input: PlayerInput) {
        if !fastFalling, velocity.y <= 0, input.stick.y < -0.65 {
            fastFalling = true
            velocity.y = -fastFallSpeed
        }
        if fastFalling {
            velocity.y = max(velocity.y - gravity, -fastFallSpeed)
        } else {
            velocity.y = max(velocity.y - gravity * SurfRules.gravityShare, -fallSpeed * SurfRules.fallShare)
        }
    }

    /// Where the wall ride was last frame, to tell when it's stopped climbing.
    private var lastWallRideY = 0.0

    /// Up the wall ahead on the board.
    private mutating func startWallRide(_ wall: Facing) {
        surfWall = wall
        facing = wall
        surfing = true
        surfPath = 0
        fastFalling = false
        grounded = false
        lastWallRideY = position.y - 1
        enter(.air)
    }

    /// Off the wall in a backflip, away from it; the same wall can't be ridden again for a
    /// moment, so the leap gets clear of it.
    private mutating func leapOffWall(_ wall: Facing) {
        surfWall = nil
        wallLandCooldown = spec.wallLandCooldownFrames
        velocity = Vec2(x: -wall.sign * SurfRules.wallLeap.x, y: SurfRules.wallLeap.y)
        facing = wall.flipped
        surfDirection = -wall.sign
        // On round the way the ride turned it, to the next upright.
        let target = (surfAngle / (2 * Double.pi)).rounded(wall.sign > 0 ? .up : .down) * 2 * Double.pi
        let rest = abs(target - surfAngle) < 0.5 ? target + wall.sign * 2 * Double.pi : target
        surfFlip = SurfRules.flipFrames
        surfFlipRate = (rest - surfAngle) / Double(SurfRules.flipFrames)
    }

    /// Surf Soda's jump: the crescent from here, forward the way the body faces, leaning
    /// back with it; `backflip` makes it a whole turn back, as the double jump is.
    private mutating func startSurfJump(backflip: Bool = false, events: inout [MatchEvent]) {
        jumpBuffer = 0
        surfPath = 1
        surfing = true
        surfFlip = 0
        surfDirection = facing.sign
        surfTurn = backflip ? 2 * Double.pi : SurfRules.jumpLean
        fastFalling = false
        platformArmed = true
        let step = Double.pi / 2 / Double(SurfRules.pathFrames)
        velocity = Vec2(x: 0, y: SurfRules.rise * step)
        events.append(.jumped(player: index))
    }

    private mutating func doubleJump(_ input: PlayerInput, events: inout [MatchEvent]) {
        jumpBuffer = 0
        platformArmed = true
        // Jumper Juice's third jump is the last one left of three, lower.
        velocity.y = spec.jumps >= 3 && jumpsLeft == 1 ? thirdJumpVelocity : doubleJumpVelocity
        if power == .frostTea, powerLevel >= 2 { wanted = .leaveClone }
        if input.stick.x != 0 {
            velocity.x = input.stick.x * airSpeedMax
        }
        jumpsLeft -= 1
        fastFalling = false
        doubleJumpTimer = 30
        if let direction = stickFacing(input) { facing = direction }
        events.append(.doubleJumped(player: index))
    }

    /// Air control. Above the air speed cap the body only slows toward it. A stick against
    /// the way it's going turns it at once, as Silksong does, rather than braking through.
    /// Not steering: the momentum carries, the light air friction on it.
    private mutating func airCoast() {
        velocity.x = approach(velocity.x, 0, airFriction)
    }

    private mutating func airDrift(_ input: PlayerInput) {
        let x = input.stick.x
        if x == 0 {
            velocity.x = approach(velocity.x, 0, airBrake)
            return
        }
        let target = airSpeedMax * (x > 0 ? 1 : -1)
        let sameWay = velocity.x == 0 || (velocity.x > 0) == (x > 0)
        if !sameWay {
            velocity.x = airSpeedMax * x
        } else if abs(velocity.x) > airSpeedMax {
            velocity.x = approach(velocity.x, target, airBrake)
        } else {
            velocity.x = approach(velocity.x, target, (spec.airAccelerationBase + spec.airAccelerationAdditional * abs(x)) * waterShare)
        }
    }

    /// Gravity, and the fast fall. Holding the throw button with the ball never fast falls:
    /// down is the throw's aim.
    private mutating func fall(_ input: PlayerInput) {
        let aimingThrow = hasBall && input.throwBall
        // Quake-Up Coffee drops faster than anyone.
        let fastFall = fastFallSpeed * (power == .quakeUp ? QuakeRules.fastFallMultiplier : 1)
        if !fastFalling, !aimingThrow, velocity.y <= 0, input.stick.y < -0.65 {
            fastFalling = true
            velocity.y = -fastFall
            if power == .platformShake, platformArmed, platformCooldown == 0 { wantsPlatform = true }
        }
        let floor = fastFalling ? -fastFall : -fallSpeed
        // Feather Fresca floats down; a fast fall doesn't.
        let gravity = velocity.y <= 0 && !fastFalling ? gravity * spec.fallGravityShare : gravity
        velocity.y = max(velocity.y - gravity, floor)
    }

    /// A stance comes to a stop on the ground and drifts down slowly in the air, its
    /// sideways speed bleeding off at `airBrake`.
    private mutating func stanceMovement(_ input: PlayerInput, airBrake: Double) {
        if grounded {
            velocity.x = approach(velocity.x, 0, traction)
        } else {
            velocity.x = approach(velocity.x, 0, airBrake)
            if velocity.y <= 0 {
                velocity.y = -BallRules.stanceFallSpeed
            } else {
                velocity.y -= gravity
            }
        }
    }

    /// The recorded flick as a launch: its angle from the horizontal, clamped to the shot's
    /// range, sent the way the body faces.
    public var shotVelocity: Vec2 {
        let forward = shotAim.x * facing.sign
        var angle = Trig.atan2(shotAim.y, abs(forward))
        angle = min(max(angle, BallRules.shotAngleMin), BallRules.shotAngleMax)
        return Vec2(x: Trig.cos(angle) * facing.sign, y: Trig.sin(angle)) * spec.shotSpeed
    }

    /// Coming down onto a rim's top from above: straight back up, never standing on it. Not
    /// while dunking, which hangs on it.
    private mutating func bounceOffRims(in stage: Stage, feetBefore: Double, events: inout [MatchEvent]) {
        guard state != .dunking, feetBefore > position.y else { return }
        for (index, hoop) in stage.hoops.enumerated()
        where feetBefore >= hoop.position.y && position.y < hoop.position.y
            && body.max.x > hoop.position.x - BallRules.rimHalfWidth && body.min.x < hoop.position.x + BallRules.rimHalfWidth {
            events.append(.rimBounced(hoop: index, speed: feetBefore - position.y))
            position.y = hoop.position.y
            velocity.y = RimRules.bodyBounce
            grounded = false
            if state.isGroundState || state == .land { enter(.air) }
            return
        }
    }

    private mutating func move(in stage: Stage) {
        // On a slope the pace is the same along the surface as on the flat: a step across is
        // shorter by the diagonal, up or down, or it would be a run's speed times root two.
        var step = velocity.x
        var lift = 0.0
        var onSlope = false
        if grounded, velocity.y <= 0, step != 0 {
            let here = stage.slopeSurface(under: body, reach: 0.01) != nil
            let there = stage.slopeSurface(under: body.offset(by: Vec2(x: step * SlopeRules.diagonal, y: 0)), reach: SlopeRules.step) != nil
            if here || there {
                onSlope = true
                step *= SlopeRules.diagonal
                // Climbing, the box is tried lifted to the ground under its leading edge, a slope's
                // surface or the top of a block, so the hill's own blocks, which its uphill corner
                // is over, don't catch it. The edge is half a body and a step ahead, so a
                // diagonal's surface there is that much higher.
                let leading = step > 0 ? body.max.x + step : body.min.x + step
                let reach = SlopeRules.step + body.width / 2 + abs(step)
                let edge = Box(min: Vec2(x: leading - 0.001, y: position.y), max: Vec2(x: leading + 0.001, y: position.y + 1))
                let ahead = [stage.slopeHeight(atX: leading, near: position.y, reach: reach),
                             stage.blockTop(under: edge, near: position.y, reach: SlopeRules.step)].compactMap { $0 }.max()
                if let ahead, ahead > position.y { lift = ahead - position.y }
            }
        }
        let sweptX = stage.sweepHorizontally(body.offset(by: Vec2(x: 0, y: lift)), by: step)
        position.x += sweptX.moved
        if sweptX.blocked != nil {
            velocity.x = 0
            position.x = position.x.rounded(toPlaces: 6)
        }
        // On the ground and not jumping, the feet ride a slope up or down, a block's height
        // at most; standing still on one, the body stays put. Off the slope's end, where the
        // middle has left it, the feet go to the top of the block stepped onto or down from.
        if grounded, velocity.y <= 0 {
            if let surface = stage.slopeSurface(under: body, reach: SlopeRules.step) {
                position.y = surface
                velocity.y = 0
            } else if onSlope, let top = stage.blockTop(under: body, near: position.y, reach: SlopeRules.step) {
                position.y = top
                velocity.y = 0
            }
        }
        let sweptY = stage.sweepVertically(body, by: velocity.y, oneWays: dropThrough == 0)
        position.y += sweptY.moved
        if sweptY.landed || sweptY.ceiling {
            velocity.y = 0
            position.y = position.y.rounded(toPlaces: 6)
        }
        wallSide = stage.wall(beside: body)
        ridableWallSide = stage.wall(beside: body, riding: true)
        grounded = velocity.y <= 0 && stage.isGrounded(body, oneWays: dropThrough == 0)
    }

    /// Landing and walking off ledges, after the move.
    private mutating func settle(_ input: PlayerInput, events: inout [MatchEvent]) {
        if grounded {
            if fastFalling, power == .quakeUp, state == .air || state == .rolling {
                // Quake-Up Coffee: a fast fall's landing shakes the floor.
                wanted = .quake
            } else if power == .titanTea, !knockedAloft, [.air, .rolling, .wallLand, .webSwing, .flying].contains(state) {
                // Titan Tea: every landing of its own does.
                wanted = .quake
            }
            knockedAloft = false
            jumpsLeft = spec.jumps
            fastFalling = false
            flightLeft = SmoothieRules.flightFrames(level: powerLevel)
            swingCooldown = 0
            switch state {
            case .air, .wallLand, .rolling:
                if surfing {
                    // Down off the board, upright, in a burst of bubbles.
                    surfing = false
                    surfPath = 0
                    surfAngle = surfAngle - (surfAngle / (2 * Double.pi)).rounded() * 2 * Double.pi
                    surfWall = nil
                    surfFlip = 0
                    events.append(.surfLanded(player: index))
                }
                events.append(.landed(player: index))
                enter(.land)
            case .webSwing:
                webAnchor = nil
                events.append(.landed(player: index))
                enter(.land)
            case .flying, .suspended:
                events.append(.landed(player: index))
                enter(.land)
            default:
                break
            }
        } else if state.isGroundState, state != .jumpSquat {
            // Surf Soda off an edge: the board comes too, and the float with it.
            if power == .surfSoda {
                surfing = true
                surfPath = 0
            }
            wallLandCooldown = max(wallLandCooldown, spec.wallLandGroundLockoutFrames)
            coyote = spec.coyoteFrames
            ledgeCooldown = LedgeRules.walkOffCooldownFrames
            enter(.air)
        }
    }

    /// The match hands the ball over. Catching stops the body on the ground; caught
    /// mid-swing, the swing carries on with it.
    public mutating func catchBall() {
        hasBall = true
        if state == .snatching { snatchCooldown = SnatchRules.cooldownFrames }
        if state == .webSwing { return }
        if grounded { velocity = .zero }
        enter(.catching)
    }

    /// Whether the ball at `ballPosition` is in reach: in the ring round the chest and
    /// either in front or in the way of where the body is moving, or in the second ring
    /// out in front, the spark's. A ball arriving from behind while standing still bounces
    /// off, and so does one over the speed threshold, and a shot in flight goes through:
    /// those take the snatch.
    public func canCatch(ballAt ballPosition: Vec2, speed: Double = 0, shotInFlight: Bool = false) -> Bool {
        guard !holding, catchCooldown == 0, pickupLockout == 0, hitStun == 0, frozen == 0, state.canCatch else { return false }
        guard speed <= BallRules.catchSpeedThreshold, !shotInFlight else { return false }
        if ballPosition.distance(to: handCatchPoint) <= BallRules.handCatchRadius * spec.scale { return true }
        let offset = ballPosition - chest
        guard offset.length <= BallRules.catchRadius * spec.scale else { return false }
        let ahead = offset.x * facing.sign >= -1
        let movingInto = velocity.lengthSquared > 0.01 && offset.x * velocity.x + offset.y * velocity.y > 0
        return ahead || movingInto
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let scale = Trig.powerOfTen(places)
        return (self * scale).rounded() / scale
    }
}

extension Player {
    /// Where the sheet draws the ball in hand this frame, from its landmark: on a dribble
    /// over a drop, the bounce reaches the floor below, the more the lower the hand has it.
    public func ballInHand(on stage: Stage) -> Vec2? {
        guard let offset = BallLandmarks.offset(animationFrame) else { return nil }
        let x = position.x + offset.x / 1.6 * spec.scale * facing.sign
        let dribbling = [Animation.dribbleIdle, .dribbleWalk, .dribbleRun].contains(animationFrame.animation)
        let drop = grounded && dribbling ? stage.drop(fromX: x, y: position.y) : 0
        let phase = min(max(offset.y / BallRules.dribbleHandHeight, 0), 1)
        return Vec2(x: x, y: position.y + offset.y / 1.6 * spec.scale - drop * (1 - phase))
    }
}

extension Player {
    /// How far a slasher on the ground slides over the next `frames`: bleeding at the
    /// swing's brake while it lasts, then stopped by the ground's traction, stepped as the
    /// body steps them. A slash's pop is aimed where this puts them.
    public func slashSlide(over frames: Int) -> Double {
        guard grounded, state == .slashing else { return 0 }
        let swingLeft = max(SlashRules.frames - stateTimer, 0)
        var speed = velocity.x, travelled = 0.0
        for frame in 0..<frames {
            speed = approach(speed, 0, frame < swingLeft ? attackBrake : traction)
            travelled += speed
        }
        return travelled
    }
}
