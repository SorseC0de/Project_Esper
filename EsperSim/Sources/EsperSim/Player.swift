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
    /// Web Water: swinging under a web, reeling to a wall, and being reeled by the other.
    case webSwing, webPull, webbed
    /// Super Smoothie: flying. Pulsepistol Punch: the shot, standing.
    case flying, gunShoot

    public var isGroundState: Bool {
        switch self {
        case .idle, .walk, .dash, .run, .pivot, .jumpSquat, .land, .crouch, .crouchWalk, .slide: true
        default: false
        }
    }

    /// States a ball can be caught out of. The snatch takes the ball its own way.
    public var canCatch: Bool {
        switch self {
        case .idle, .walk, .dash, .run, .pivot, .jumpSquat, .air, .land, .wallLand, .webSwing, .webPull, .flying,
             .crouch, .crouchWalk, .slide: true
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
    /// Frames spent in the state so far; 0 on the frame it was entered.
    public var stateTimer = 0
    public var grounded = true
    public var wallSide: Facing?
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
    public var slashHit = false
    /// Frames left in which no button does anything and nothing is caught, after the ball
    /// was knocked or taken out of the hands; the stick still works.
    public var hitStun = 0
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
    var runSpeed: Double { spec.runSpeed * speedShare }
    var walkMaxSpeed: Double { spec.walkMaxSpeed * speedShare }
    var dashInitialVelocity: Double { runSpeed + (spec.dashInitialVelocity - spec.runSpeed) }
    var airSpeedMax: Double { spec.airSpeedMax * speedShare }

    /// Crouched or sliding, the body is half as tall, so it fits under what a standing
    /// body can't.
    public var body: Box {
        let low = state == .crouch || state == .crouchWalk || state == .slide
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

    public var chest: Vec2 { Vec2(x: position.x, y: position.y + BallRules.chestHeight) }

    /// The centre of the second catch ring, the spark's, out in front.
    public var handCatchPoint: Vec2 {
        Vec2(x: position.x + BallRules.handCatchCentre.x * facing.sign, y: position.y + BallRules.handCatchCentre.y)
    }

    /// The centre of the slash's blade: the body's, a little in front.
    public var bladeCentre: Vec2 {
        Vec2(x: body.center.x + SlashRules.forward * facing.sign, y: body.center.y)
    }

    public var inStance: Bool { state == .shootStance || state == .throwStance }

    /// The first step in a state, after `enter` on the step before.
    private var stanceTimerJustEntered: Bool { stateTimer == 1 }

    public mutating func enter(_ next: PlayerState) {
        previousState = state
        state = next
        stateTimer = 0
    }

    /// The run cycle's advance this frame: 24 frames a second at full run speed, scaling
    /// with how fast the body actually moves, up to 26 in the dash and never under 10.
    private var runCycleStep: Double {
        min(max(abs(velocity.x) / runSpeed * 24, 10), 26) / 60
    }

    /// Whether the stick is pushed the way the body faces.
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
    public mutating func step(input given: PlayerInput, stage: Stage, opponentX: Double? = nil,
                              ballHolder: Int? = nil, ballOwner: Int? = nil, events: inout [MatchEvent]) -> PlayerAction? {
        var input = given
        if frozen > 0 {
            // Held exactly as it is: no timers, no moves, nothing.
            frozen -= 1
            lastInput = input
            return nil
        }
        stateTimer += 1
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
        if coyote > 0 { coyote -= 1 }
        if input.shootButtons == 0 { shootReady = true }
        if !input.throwBall { throwReady = true }
        if snatchCooldown > 0 { snatchCooldown -= 1 }
        if ledgeCooldown > 0 { ledgeCooldown -= 1 }
        if hitStun > 0 {
            hitStun -= 1
            input.jump = false
            input.shootButtons = 0
            input.throwBall = false
            input.taunt = false
            jumpBuffer = 0
        }
        if doubleJumpTimer > 0 { doubleJumpTimer -= 1 }
        stickAwayFrames = abs(input.stick.x) < 0.3 ? 0 : stickAwayFrames + 1
        downHeldFrames = input.stick.y < -0.65 ? downHeldFrames + 1 : 0

        if input.jump && !lastInput.jump { jumpBuffer = 5 } else if jumpBuffer > 0 { jumpBuffer -= 1 }
        let jumpPressed = jumpBuffer > 0
        var shootPressed = input.shoot && !lastInput.shoot
        let throwPressed = input.throwBall && !lastInput.throwBall
        let tauntPressed = input.taunt && !lastInput.taunt
        let smash = abs(input.stick.x) >= spec.dashThreshold && stickAwayFrames <= 3
        let onDefence = ballHolder != nil && ballHolder != index
        var action: PlayerAction?
        let free = state == .idle || state == .walk || state == .run || state == .dash || state == .air || state == .land || state == .wallLand
            || state == .flying || state == .crouch || state == .crouchWalk
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

        switch state {
        case .idle:
            velocity.x = approach(velocity.x, 0, spec.traction)
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
                        let target = walkMaxSpeed * input.stick.x
                        velocity.x = approach(velocity.x, target, spec.walkAcceleration)
                        // The cycle runs 15 frames a second at full walk and never under 10, so the ball can't hang on a tween.
                        animationPhase += max(abs(velocity.x) / walkMaxSpeed * 0.25, 10.0 / 60)
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
                    animationPhase += runCycleStep
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
                    velocity.x = approach(velocity.x, 0, spec.traction)
                    animationPhase += runCycleStep
                    if abs(velocity.x) <= walkMaxSpeed {
                        enter(stickFacing(input) == nil ? .idle : .walk)
                    }
                } else if let direction = stickFacing(input) {
                    if direction != facing {
                        enter(.pivot)
                    } else {
                        velocity.x = runSpeed * facing.sign
                        animationPhase += runCycleStep
                    }
                } else {
                    enter(.idle)
                }
            }

        case .pivot:
            velocity.x = approach(velocity.x, 0, spec.traction * 2)
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
            if stateTimer >= spec.jumpSquatFrames {
                velocity.y = input.jump ? spec.fullHopVelocity : spec.shortHopVelocity
                let cap = max(abs(velocity.x), airSpeedMax)
                velocity.x = min(max(velocity.x + input.stick.x * spec.jumpHorizontalVelocity, -cap), cap)
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

        case .air:
            // The body turns with the stick in the air, at once.
            if airControlLock == 0, let direction = stickFacing(input) { facing = direction }
            airDrift(airControlLock > 0 ? .idle : input)
            fall(input)
            if jumpPressed, coyote > 0 {
                // Just off an edge: the jump the ground would have given.
                jumpBuffer = 0
                coyote = 0
                velocity.y = input.jump ? spec.fullHopVelocity : spec.shortHopVelocity
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
            } else if wallSide == nil || (stickFacing(input) != facing && !webAiming) {
                // Aiming a web line holds the cling whatever the stick does.
                enter(.air)
            }

        case .land:
            velocity.x = approach(velocity.x, 0, spec.traction)
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
            stanceMovement(input, airBrake: spec.stanceAirBrake)
            if input.aim.length >= BallRules.flickThreshold {
                shotAim = input.aim
                if shotAim.x != 0 { facing = shotAim.x > 0 ? .right : .left }
            } else if let direction = stickFacing(input) {
                // The stick turns the body throughout, so touch can turn as the pad does.
                facing = direction
            }
            if grounded, jumpPressed {
                jumpBuffer = 0
                velocity.y = spec.fullHopVelocity
                jumpsLeft = 0
                grounded = false
                jumpShot = true
                events.append(.jumped(player: index))
            }
            if grounded, downHeldFrames == 1 {
                // Down on the ground: the cancel.
                cancelShot()
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
                velocity.x = approach(velocity.x, 0, spec.traction)
            } else if stateTimer > BallRules.shotReleaseFrames {
                // Hanging after the release, in the pose.
                velocity.x = approach(velocity.x, 0, spec.stanceAirBrake)
                velocity.y = 0
            } else {
                airDrift(.idle)
                fall(.idle)
            }
            if stateTimer == BallRules.shotReleaseFrames {
                let lift = shotLift ? max(velocity.y, 0) : 0
                if hasFireball {
                    hasFireball = false
                    action = .releaseFireball(velocity: shotVelocity + Vec2(x: 0, y: lift), straight: false)
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
            stanceMovement(input, airBrake: spec.throwStanceAirBrake)
            let aim = input.aim.length >= BallRules.flickThreshold ? input.aim : input.stick
            if aim.length >= 0.5 {
                throwDirection = abs(aim.x) >= abs(aim.y) ? Vec2(x: aim.x > 0 ? 1 : -1, y: 0) : Vec2(x: 0, y: aim.y > 0 ? 1 : -1)
                if throwDirection.x != 0 { facing = throwDirection.x > 0 ? .right : .left }
            }
            if stanceTimerJustEntered, hasBall, power == .zeusJuice, powerLevel >= 2, strikeCooldown == 0 {
                // Zeus Juice: the charge calls a strike down onto the ball in hand.
                strikeCooldown = ZeusRules.strikeCooldownFrames
                // Onto the ball where the stance's sheet draws it, a little behind the chest.
                let ball = BallLandmarks.offset(animationFrame).map { position + Vec2(x: $0.x / 1.6 * facing.sign, y: $0.y / 1.6) }
                    ?? Vec2(x: chest.x - facing.sign * 5, y: chest.y + 3)
                wanted = .strikeBolt(x: ball.x, bottom: ball.y)
            }
            if hasBall, let hoop = stage.hoops.indices.first(where: { stage.hoops[$0].position.distance(to: chest) <= BallRules.dunkRadius }) {
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
                velocity.x = approach(velocity.x, 0, spec.traction)
            } else {
                airDrift(.idle)
                fall(.idle)
            }
            if stateTimer == BallRules.throwReleaseFrames {
                let direction = throwDirection == .zero ? Vec2(x: facing.sign, y: 0) : throwDirection
                if hasFireball {
                    hasFireball = false
                    action = .releaseFireball(velocity: direction * BallRules.throwSpeed, straight: true)
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
            let place = rim.position + Vec2(x: BallRules.dunkOffset.x * rim.backboard.sign, y: BallRules.dunkOffset.y)
            let slam = BallRules.dunkFrames / 2
            let share = min(Double(stateTimer) / Double(slam), 1)
            position = dunkFrom + (place - dunkFrom) * share
            if stateTimer == BallRules.dunkFrames / 2 {
                hasBall = false
                catchCooldown = BallRules.catchCooldownFrames
                events.append(.dunked(player: index))
                action = .dunk(hoop: dunkHoop)
            } else if stateTimer >= BallRules.dunkFrames + BallRules.dunkHangFrames {
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
                velocity.x = approach(velocity.x, spec.crouchWalkSpeed * input.stick.x, spec.walkAcceleration)
                animationPhase += max(abs(velocity.x) / spec.crouchWalkSpeed * 0.25, 10.0 / 60)
            } else {
                velocity.x = approach(velocity.x, 0, spec.traction)
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
            } else if (input.stick.x != 0) != (state == .crouchWalk) {
                enter(input.stick.x != 0 ? .crouchWalk : .crouch)
            }

        case .slide:
            // The leg out front, the body low, the burst carried nearly whole; then up into
            // the skid, or a crouch if down is still held. On Frost Tea it's ice: no
            // friction and no end, until jump, throw, shoot, the stick, or down let go
            // cancel it.
            if power == .frostTea {
                if jumpPressed {
                    enter(.jumpSquat)
                } else if throwPressed, snatchCooldown == 0 {
                    startSnatch()
                } else if shootPressed, slashAllowed {
                    startSlash(events: &events)
                } else if !crouchAsked(input) || (input.stick.x != 0 && !stickForward(input)) {
                    enter(roomToStand(in: stage) ? .idle : .crouch)
                }
            } else {
                velocity.x = approach(velocity.x, 0, spec.slideFriction)
                if stateTimer >= spec.slideFrames {
                    enter(crouchAsked(input) || !roomToStand(in: stage) ? .crouch : .idle)
                }
            }

        case .slashing:
            // On the ground the swing carries the run it came from, bleeding it off; in the
            // air gravity is cut, so the body hangs through it, and the roll follows.
            if grounded {
                velocity.x = approach(velocity.x, 0, spec.attackBrake)
            } else {
                velocity.x = approach(velocity.x, 0, spec.airFriction)
                velocity.y = max(velocity.y - spec.gravity * SlashRules.gravityShare, -spec.fallSpeed)
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
                velocity.x = approach(velocity.x, 0, spec.attackBrake)
            } else {
                airDrift(input)
                fall(.idle)
            }
            if stateTimer == SnatchRules.sparkFrame {
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

        case .walling:
            // The snatch's reach, and the wall appears at the hand's full stretch.
            if grounded {
                velocity.x = approach(velocity.x, 0, spec.attackBrake)
            } else {
                airDrift(input)
                fall(.idle)
            }
            if stateTimer == ShakeRules.wallAppearFrame {
                action = .makeWall
            }
            if stateTimer >= ShakeRules.wallFrames {
                enter(grounded ? .idle : .air)
            }

        case .ledgeHang:
            velocity = .zero
            if stateTimer >= LedgeRules.hangFrames {
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
                velocity.y = min(velocity.y, spec.fullHopVelocity)
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

        case .gunShoot:
            // Pulsepistol Punch's shot, standing: braked, the pulse on its frame.
            if grounded {
                velocity.x = approach(velocity.x, 0, spec.traction)
            } else {
                airDrift(.idle)
                fall(.idle)
            }
            if stateTimer == PulseRules.fireFrame {
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

        if action == nil, wantsPlatform {
            action = .makePlatform
        }
        wantsPlatform = false
        move(in: stage)
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
        velocity = push
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
    private func crouchAsked(_ input: PlayerInput) -> Bool {
        !holding && input.stick.y < -0.65
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
    private mutating func grabLedgeIfThere(in stage: Stage, events: inout [MatchEvent]) {
        guard state == .air, !hasBall, velocity.y <= 0, ledgeCooldown == 0 else { return }
        let hand = position.y + LedgeRules.hangDepth
        for side in [facing, facing.flipped] {
            guard let corner = stage.ledge(beside: body, side: side, reach: LedgeRules.grabReach,
                                           top: (hand - LedgeRules.grabSlack)...(hand + LedgeRules.grabSlack)) else { continue }
            let hang = Vec2(x: corner.x - side.sign * spec.bodyWidth / 2, y: corner.y - LedgeRules.hangDepth)
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
        return [Vec2(x: corner.x - facing.sign * half, y: corner.y - LedgeRules.hangDepth),
                Vec2(x: corner.x, y: corner.y - LedgeRules.hangDepth / 2),
                Vec2(x: corner.x + facing.sign * (half + 1), y: corner.y)]
    }

    // MARK: Hitboxes

    /// The extended leg while sliding, until it has hit.
    public var slideHitbox: Box? {
        guard state == .slide, !slideHit, frozen == 0 else { return nil }
        let front = position.x + facing.sign * spec.bodyWidth / 2
        let tip = front + facing.sign * SlideRules.legReach
        return Box(min: Vec2(x: min(front, tip), y: position.y), max: Vec2(x: max(front, tip), y: position.y + SlideRules.legHeight))
    }

    /// The blade: a square round the body over the slash's live frames, until it has hit.
    public var slashHitbox: Box? {
        guard state == .slashing, !slashHit, frozen == 0, SlashRules.liveFrames.contains(stateTimer) else { return nil }
        return Box(center: bladeCentre, width: SlashRules.reach * 2, height: SlashRules.reach * 2)
    }

    /// Whether the snatch's hand takes a ball centred here: the ball on the body and the
    /// reach in front, or on the hand's catch ring.
    public func snatchReaches(ballAt at: Vec2) -> Bool {
        guard let reach = snatchHitbox else { return false }
        let ball = Box(center: at, width: BallRules.radius * 2, height: BallRules.radius * 2)
        return ball.overlaps(reach) || at.distance(to: handCatchPoint) <= BallRules.handCatchRadius + BallRules.radius
    }

    /// The whole body and the hand's reach in front, while the snatch's hand is out.
    public var snatchHitbox: Box? {
        guard state == .snatching, frozen == 0, SnatchRules.activeFrames.contains(stateTimer) else { return nil }
        let box = body
        return facing == .right
            ? Box(min: box.min, max: Vec2(x: box.max.x + SnatchRules.reach, y: box.max.y))
            : Box(min: Vec2(x: box.min.x - SnatchRules.reach, y: box.min.y), max: box.max)
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
        let ballX = position.x + offset.x / 1.6 * facing.sign
        let drop = stage.drop(fromX: ballX, y: position.y)
        guard drop > Stage.tileSize else { return nil }
        return Vec2(x: ballX, y: position.y - drop + BallRules.radius)
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
        velocity = Vec2(x: spec.wallJumpHorizontal * -wall.sign, y: spec.wallJumpVertical)
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

    private mutating func doubleJump(_ input: PlayerInput, events: inout [MatchEvent]) {
        jumpBuffer = 0
        platformArmed = true
        // Jumper Juice's third jump is the last one left of three, lower.
        velocity.y = spec.jumps >= 3 && jumpsLeft == 1 ? spec.thirdJumpVelocity : spec.doubleJumpVelocity
        if power == .frostTea, powerLevel >= 2 { wanted = .leaveClone }
        if input.stick.x != 0 {
            velocity.x = input.stick.x * spec.doubleJumpHorizontalVelocity
        }
        jumpsLeft -= 1
        fastFalling = false
        doubleJumpTimer = 30
        if let direction = stickFacing(input) { facing = direction }
        events.append(.doubleJumped(player: index))
    }

    /// Air control. Above the air speed cap the body only slows toward it. A stick against
    /// the way it's going turns it at once, as Silksong does, rather than braking through.
    private mutating func airDrift(_ input: PlayerInput) {
        let x = input.stick.x
        if x == 0 {
            velocity.x = approach(velocity.x, 0, spec.airFriction)
            return
        }
        let target = airSpeedMax * (x > 0 ? 1 : -1)
        let sameWay = velocity.x == 0 || (velocity.x > 0) == (x > 0)
        if !sameWay {
            velocity.x = airSpeedMax * x
        } else if abs(velocity.x) > airSpeedMax {
            velocity.x = approach(velocity.x, target, spec.airFriction)
        } else {
            velocity.x = approach(velocity.x, target, spec.airAccelerationBase + spec.airAccelerationAdditional * abs(x))
        }
    }

    /// Gravity, and the fast fall. Holding the throw button with the ball never fast falls:
    /// down is the throw's aim.
    private mutating func fall(_ input: PlayerInput) {
        let aimingThrow = hasBall && input.throwBall
        // Quake-Up Coffee drops faster than anyone.
        let fastFall = spec.fastFallSpeed * (power == .quakeUp ? QuakeRules.fastFallMultiplier : 1)
        if !fastFalling, !aimingThrow, velocity.y <= 0, input.stick.y < -0.65 {
            fastFalling = true
            velocity.y = -fastFall
            if power == .platformShake, platformArmed, platformCooldown == 0 { wantsPlatform = true }
        }
        let floor = fastFalling ? -fastFall : -spec.fallSpeed
        velocity.y = max(velocity.y - spec.gravity, floor)
    }

    /// A stance comes to a stop on the ground and drifts down slowly in the air, its
    /// sideways speed bleeding off at `airBrake`.
    private mutating func stanceMovement(_ input: PlayerInput, airBrake: Double) {
        if grounded {
            velocity.x = approach(velocity.x, 0, spec.traction)
        } else {
            velocity.x = approach(velocity.x, 0, airBrake)
            if velocity.y <= 0 {
                velocity.y = -BallRules.stanceFallSpeed
            } else {
                velocity.y -= spec.gravity
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

    private mutating func move(in stage: Stage) {
        let sweptX = stage.sweepHorizontally(body, by: velocity.x)
        position.x += sweptX.moved
        if sweptX.blocked != nil {
            velocity.x = 0
            position.x = position.x.rounded(toPlaces: 6)
        }
        let sweptY = stage.sweepVertically(body, by: velocity.y)
        position.y += sweptY.moved
        if sweptY.landed || sweptY.ceiling {
            velocity.y = 0
            position.y = position.y.rounded(toPlaces: 6)
        }
        wallSide = stage.wall(beside: body)
        grounded = velocity.y <= 0 && stage.isGrounded(body)
    }

    /// Landing and walking off ledges, after the move.
    private mutating func settle(_ input: PlayerInput, events: inout [MatchEvent]) {
        if grounded {
            if fastFalling, power == .quakeUp, state == .air || state == .rolling {
                // Quake-Up Coffee: a fast fall's landing shakes the floor.
                wanted = .quake
            }
            jumpsLeft = spec.jumps
            fastFalling = false
            flightLeft = SmoothieRules.flightFrames(level: powerLevel)
            swingCooldown = 0
            switch state {
            case .air, .wallLand, .rolling:
                events.append(.landed(player: index))
                enter(.land)
            case .webSwing:
                webAnchor = nil
                events.append(.landed(player: index))
                enter(.land)
            case .flying:
                events.append(.landed(player: index))
                enter(.land)
            default:
                break
            }
        } else if state.isGroundState, state != .jumpSquat {
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
        guard !holding, catchCooldown == 0, hitStun == 0, frozen == 0, state.canCatch else { return false }
        guard speed <= BallRules.catchSpeedThreshold, !shotInFlight else { return false }
        if ballPosition.distance(to: handCatchPoint) <= BallRules.handCatchRadius { return true }
        let offset = ballPosition - chest
        guard offset.length <= BallRules.catchRadius else { return false }
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
