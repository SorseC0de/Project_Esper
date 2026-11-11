import Foundation

/// A body's movement numbers. Units per frame at 60, as Melee counts them.
public struct FighterSpec: Equatable {
    public var name: String

    public var walkMaxSpeed: Double
    public var walkAcceleration: Double
    /// Stick length that counts as a smash input when it arrives fast.
    public var dashThreshold: Double
    public var dashInitialVelocity: Double
    /// Frames the initial dash lasts before it becomes a run or a stop.
    public var dashFrames: Int
    public var runSpeed: Double
    /// Speed lost per frame on the ground with no stick.
    public var traction: Double
    /// Frames to turn around out of a run.
    public var pivotFrames: Int

    public var jumpSquatFrames: Int
    public var fullHopVelocity: Double
    public var shortHopVelocity: Double
    public var doubleJumpVelocity: Double
    public var jumps: Int
    public var gravity: Double
    public var fallSpeed: Double
    public var fastFallSpeed: Double
    public var airAccelerationBase: Double
    public var airAccelerationAdditional: Double
    public var airFriction: Double
    public var landingLagFrames: Int

    public var wallJumpHorizontal: Double
    public var wallJumpVertical: Double
    /// Speed of the slide down the wall while clinging. The cling lasts as long as the
    /// stick is held into the wall.
    public var wallSlideSpeed: Double
    /// Frames after a wall jump before a cling can start again.
    public var wallLandCooldownFrames: Int
    /// Frames after leaving the ground before a cling can start, so a jump beside a wall
    /// isn't caught by it on the way up.
    public var wallLandGroundLockoutFrames = 8
    /// A wall jump comes only out of the cling: the wall land state. Frames after one in
    /// which the stick doesn't steer, so the arc leaves the wall.
    public var wallJumpControlLockFrames = 12
    /// Frames after walking off an edge in which a jump press is still a ground jump.
    public var coyoteFrames = 3
    /// Frames of holding down in a run before it brakes to walking speed.
    public var runBrakeHoldFrames = 4
    /// Frames into a walk with the ball in which the stick still turns the body, before it
    /// faces the opponent. Without the ball a walk faces the stick.
    public var walkFaceLockoutFrames = 3
    /// Speed of a crouch walk.
    public var crouchWalkSpeed = 0.8
    /// Sideways speed lost per frame in an airborne shoot stance, and in a throw stance,
    /// which keeps most of its run so a jump can carry it to the rim for the dunk.
    public var stanceAirBrake = 0.01
    public var throwStanceAirBrake = 0.03
    /// Speed lost per frame on the ground through a snatch or a slash, so a run or a dash
    /// carries into them.
    public var attackBrake = 0.15
    /// A shot leaves at this speed, and runs its arc this many times faster than an
    /// ordinary ball; Cannon Cola raises the pace, never the speed, so the arc is the same.
    public var shotSpeed = 4.5
    public var shotPace = 1.0
    /// A slide lasts this many frames and bleeds only this much a frame, so it carries
    /// the burst it started with; Slide Cider adds frames.
    public var slideFrames = 20
    /// Slide Cider's level: one, the slide knocks harder and catches the ball; two, it stuns too.
    public var slideCiderLevel = 0
    /// Guarderade: a bigger shield, and at level two a second before landing. Shelter Seltzer:
    /// the shield lingers where it's raised, and at level two every snatch raises one.
    public var guarderadeLevel = 0
    public var shelterSeltzerLevel = 0
    /// Floback Fresca: FLO when hit or snatched, and at level two when throwing the ball.
    public var flobackFrescaLevel = 0
    /// Quake-Up Coffee's level: one, a fast fall's landing quakes the floor it's on and falls
    /// faster; two, the quake shakes every floor.
    public var quakeLevel = 0
    public var slideFriction = 0.02
    /// A third jump's speed, when there is one: Jumper Juice's second drink.
    public var thirdJumpVelocity = 0.0
    /// Share of gravity felt falling, not fast falling: Feather Float's float.
    public var fallGravityShare = 1.0
    /// Share of any knock the body takes: Titan Tea's weight.
    public var knockbackShare = 1.0
    /// Frames a knocked body coasts on it before the stick steers it again.
    public var knockCoastFrames = 12
    /// The body's size against the ordinary one, its reaches and the heights its hands
    /// hold and let go of the ball at with it: Titan Tea's 2.
    public var scale = 1.0
    public var canCrouch = true
    /// Through an action, the state's clock holds one frame in this many, so the action
    /// runs that much slower; 0 for never. Titan Tea's 10.
    public var actionHoldInterval = 0

    /// Body box: full width and height, feet at the position.
    public var bodyWidth: Double
    public var bodyHeight: Double

    /// Melee Mario, from the SSBWiki attribute table. Walk acceleration, dash length, the
    /// pivot and the wall numbers are not on the table and are chosen to sit with the rest.
    public static let meleeMario = FighterSpec(
        name: "Mario",
        walkMaxSpeed: 1.1,
        walkAcceleration: 0.1,
        dashThreshold: 0.8,
        dashInitialVelocity: 1.5,
        dashFrames: 12,
        runSpeed: 1.5,
        traction: 0.06,
        pivotFrames: 15,
        jumpSquatFrames: 4,
        fullHopVelocity: 2.3,
        shortHopVelocity: 1.4,
        doubleJumpVelocity: 2.2,
        jumps: 2,
        gravity: 0.095,
        fallSpeed: 1.7,
        fastFallSpeed: 2.3,
        airAccelerationBase: 0.02,
        airAccelerationAdditional: 0.025,
        airFriction: 0.016,
        landingLagFrames: 4,
        wallJumpHorizontal: 1.5,
        wallJumpVertical: 2.0,
        wallSlideSpeed: 0.3,
        wallLandCooldownFrames: 6,
        bodyWidth: 10,
        bodyHeight: 17.5
    )

    /// Melee Captain Falcon, same table. Jump velocities come from the listed heights: full
    /// hop 38.5, short hop 14.9, double jump 28.6. The wall jump is his run speed out and
    /// most of a full hop up, as Mario's was.
    public static let meleeFalcon = FighterSpec(
        name: "Falcon",
        walkMaxSpeed: 0.85,
        walkAcceleration: 0.1,
        dashThreshold: 0.8,
        dashInitialVelocity: 2.0,
        dashFrames: 15,
        runSpeed: 2.3,
        traction: 0.08,
        pivotFrames: 15,
        jumpSquatFrames: 4,
        fullHopVelocity: 3.1,
        shortHopVelocity: 1.9,
        doubleJumpVelocity: 2.66,
        jumps: 2,
        gravity: 0.13,
        fallSpeed: 2.9,
        fastFallSpeed: 3.5,
        airAccelerationBase: 0.02,
        airAccelerationAdditional: 0.04,
        airFriction: 0.01,
        landingLagFrames: 4,
        wallJumpHorizontal: 2.3,
        wallJumpVertical: 2.7,
        wallSlideSpeed: 0.5,
        wallLandCooldownFrames: 6,
        bodyWidth: 10,
        bodyHeight: 17.5
    )

    /// Melee Fox. Full hop 31.3, short hop 10.7, double jump 40.2; 3-frame jumpsquat.
    public static let meleeFox = FighterSpec(
        name: "Fox",
        walkMaxSpeed: 1.6,
        walkAcceleration: 0.1,
        dashThreshold: 0.8,
        dashInitialVelocity: 1.9,
        dashFrames: 11,
        runSpeed: 2.2,
        traction: 0.08,
        pivotFrames: 15,
        jumpSquatFrames: 3,
        fullHopVelocity: 3.68,
        shortHopVelocity: 2.1,
        doubleJumpVelocity: 4.19,
        jumps: 2,
        gravity: 0.23,
        fallSpeed: 2.8,
        fastFallSpeed: 3.4,
        airAccelerationBase: 0.02,
        airAccelerationAdditional: 0.06,
        airFriction: 0.02,
        landingLagFrames: 4,
        wallJumpHorizontal: 2.2,
        wallJumpVertical: 3.2,
        wallSlideSpeed: 0.5,
        wallLandCooldownFrames: 6,
        bodyWidth: 10,
        bodyHeight: 17.5
    )

    /// Melee Sheik. Full hop 34.1, short hop 20.2, double jump 38; 3-frame jumpsquat.
    public static let meleeSheik = FighterSpec(
        name: "Sheik",
        walkMaxSpeed: 1.2,
        walkAcceleration: 0.1,
        dashThreshold: 0.8,
        dashInitialVelocity: 1.7,
        dashFrames: 12,
        runSpeed: 1.8,
        traction: 0.08,
        pivotFrames: 15,
        jumpSquatFrames: 3,
        fullHopVelocity: 2.91,
        shortHopVelocity: 2.23,
        doubleJumpVelocity: 3.08,
        jumps: 2,
        gravity: 0.13,
        fallSpeed: 2.13,
        fastFallSpeed: 3.0,
        airAccelerationBase: 0.02,
        airAccelerationAdditional: 0.04,
        airFriction: 0.04,
        landingLagFrames: 4,
        wallJumpHorizontal: 1.8,
        wallJumpVertical: 2.5,
        wallSlideSpeed: 0.5,
        wallLandCooldownFrames: 6,
        bodyWidth: 10,
        bodyHeight: 17.5
    )
}

extension FighterSpec {
    /// The body a match starts on: the baseline with half a unit less run and dash speed,
    /// and so of air speed, which is the run's; the double jump kept. One Hasty Horchata brings the speeds back.
    public static let starting: FighterSpec = {
        var spec = baseline
        spec.name = "Starting"
        spec.runSpeed = baseline.runSpeed - 0.5
        spec.dashInitialVelocity = spec.runSpeed + 0.4
        return spec
    }()

    /// The body the game is tuned on: Fox with a Falco-style dash, the burst always 0.4 over
    /// the 3.2 run,
    /// more traction, air control turned up so a jump starts at air speed and turns in about
    /// five frames, and a shoot stance that brakes hard in the air.
    public static let baseline: FighterSpec = {
        var spec = meleeFox
        spec.name = "Baseline"
        spec.runSpeed = 3.2
        spec.dashInitialVelocity = spec.runSpeed + 0.4
        // Half Fox's 11 frames, rounded up: the dash covers half the ground.
        spec.dashFrames = 6
        // Its three sheet frames three sim frames each: the shortest turn they can still be seen in.
        spec.pivotFrames = 9
        // Near-instant: a full run is gone in a couple of frames.
        spec.traction = 1.5
        spec.airAccelerationAdditional = 0.24
        spec.stanceAirBrake = 0.15
        return spec
    }()
}

/// The defender, without the ball while the other has it, moves this much faster.
public enum DefenceRules {
    public static let speedShare = 1.1
}

/// Everything about the ball, the hoops and the plays on them. Units and frames.
public enum BallRules {
    /// A made basket down the net: how far under the rim the net's bottom is, in units (20 art
    /// pixels), and the share of the way to the rim's middle it's drawn a frame.
    public static let netDepth = 12.5
    public static let netCentring = 0.35
    /// After a point, frames in which no other counts.
    public static let scoreLockoutFrames = 20
    public static let gravity = 0.15
    public static let fallSpeed = 6.0
    public static let radius = 2.5
    /// Speed kept after hitting a wall, the floor, or a body.
    public static let bounce = 0.75
    /// Rolling on the floor, the speed lost a frame: this share of it, and this much more, down to
    /// a stop at zero rather than a snap.
    public static let rollingFriction = 0.03
    public static let rollingDrag = 0.01
    /// Art pixels above the feet the dribbling hand holds the ball at; below it the bounce
    /// reaches down a drop.
    public static let dribbleHandHeight = 16.0

    /// A shot leaves from this high above the feet, at the body's shot speed.
    public static let shotReleaseHeight = 25.0
    public static let shotAngleMin = degrees(25)
    public static let shotAngleMax = degrees(80)
    public static let shotAngleDefault = degrees(53)
    /// The preset arc, a shot with no flick (ARC HEIGHT, ARC DISTANCE): its peak this high over
    /// the release, back down to the release's height this far ahead, in units.
    public static var presetArcHeight = 50.0
    public static var presetArcDistance = 150.0
    /// The preset arc aimed at the shooter's own rim: its peak ARC HEIGHT over the higher of the
    /// release and the rim, coming down onto the rim from wherever it's let go. Off (the ARC AIM
    /// picker's FIXED), it peaks ARC HEIGHT over the release and goes ARC DISTANCE the way the body faces.
    public static var presetAimsAtRim = true
    /// The auto-aim only within this far across of the rim (AIM RANGE), and only facing it;
    /// otherwise the fixed arc the way the body faces. Never closer than five tiles: nearer, its
    /// arc goes up high and narrow, and it's the floater's and the layup's ground.
    public static var autoAimRange = 144.0
    public static let autoAimMinimum = 5 * Stage.tileSize
    /// The preset arc's release from `from`, peaking ARC HEIGHT over the higher of it and `rim`
    /// and coming down at `rim`: up fast enough for the peak, across fast enough to be over the
    /// rim as it falls to its height.
    /// `gravityShare`: the pull the ball's under there (half under water, leaned on a pitched stage).
    public static func presetArcVelocity(from: Vec2, to rim: Vec2, gravityShare: Double = 1, height: Double = presetArcHeight) -> Vec2 {
        presetArc(from: from, to: rim, gravityShare: gravityShare, height: height).velocity
    }
    /// The same, and how many frames it takes to come down to the rim.
    public static func presetArc(from: Vec2, to rim: Vec2, gravityShare: Double = 1, height: Double = presetArcHeight) -> (velocity: Vec2, frames: Double) {
        let pull = gravity * gravityShare
        let rise = rim.y - from.y
        let peak = max(rise, 0) + max(height, 1)
        let up = (pull + (pull * pull + 8 * pull * peak).squareRoot()) / 2
        // Frames to come back down to the rim's height: y(t) = up·t − g·t(t+1)/2, the later root.
        let b = up - pull / 2
        let frames = max((b + max(b * b - 2 * pull * rise, 0).squareRoot()) / pull, 1)
        return (Vec2(x: (rim.x - from.x) / frames, y: up), frames)
    }
    /// The preset arc's release, the way the body faces: up fast enough to peak at its height,
    /// across fast enough to come back down to the release's height at its distance.
    public static func presetArcVelocity(sign: Double) -> Vec2 {
        // A frame's fall comes off before each step: the peak is n·vy − g·n(n+1)/2.
        let up = (gravity + (gravity * gravity + 8 * gravity * max(presetArcHeight, 1)).squareRoot()) / 2
        let frames = max(2 * up / gravity - 1, 1)
        return Vec2(x: presetArcDistance / frames * sign, y: up)
    }
    /// A way aimed this many frames before the throw's press still sets the throw's way.
    public static let throwAimBufferFrames = 6
    /// Aim length the flick has to reach to count.
    public static let flickThreshold = 0.5
    /// Frames from taking the stance to being able to release. Letting go always follows
    /// through: before the windup ends it fires when it does, on the preset arc unless a
    /// flick came first. Cancelling is another shoot button, the throw button, or down on
    /// the ground.
    public static let shotWindupFrames = 20
    /// Frames from the release to the ball leaving the hand, then to acting again on the
    /// ground. In the air the body hangs, gravity off, for the hang frames instead, in the
    /// pose with the leg kick.
    public static let shotReleaseFrames = 5
    public static let shotRecoveryFrames = 10
    public static let shotHangFrames = 18
    /// The floater's pose held this long after the ball leaves the hand (0.8 s), so it can be seen,
    /// and so the ball can't be had back and scored again straight away.
    public static let shotPoseHoldFrames = 48
    /// A shot's pose is held as long as its ball takes to reach the rim (to go in, or first touch
    /// anything), and this much more, so a game-winner freezes on it; within these bounds. Past
    /// the hang, a shot in the air falls in it.
    public static let shotPoseAfterFlightFrames = 6
    public static let shotPoseHoldRange = 10...120
    /// The pull on a body held in a shot's or a floater's pose in the air, a share of its gravity;
    /// landing ends the pose.
    public static let poseHoldGravityShare = 0.5
    /// Frames after any release before the same player can catch it back.
    public static let catchCooldownFrames = 15
    /// In the air the stance holds the fall to this.
    public static let stanceFallSpeed = 0.5

    /// A thrown ball hitting the other knocks them this hard, half again the slash's.
    public static let thrownHitKnock = Vec2(x: 6, y: 3)
    /// A throw goes straight at this speed, with no gravity until its first bounce.
    public static let throwSpeed = 7.0
    /// An up throw is the floater: it drifts up this fast, gravity off, for this many
    /// frames, then falls as a ball does. It keeps this share of the run it started from,
    /// enough to drift with the thrower and not enough to arc.
    public static let floaterSpeed = 1.5
    /// A ball that can't score bouncing on a rim's top: kicked out across, the way it's off the
    /// ring's middle, and at least this fast across, so it rolls off rather than sitting there.
    public static let rimKick = 0.4
    public static let rimRollOffSpeed = 0.6
    /// The up throw's floater, the layup's ball: a touch quicker up than a pop's (1.5, the up
    /// throw's too at first), so one let go off the ground from under the Wreck Center's rim clears
    /// it and drops through, the baseline; 1.54 is the least that does.
    public static let upThrowSpeed = 1.55
    public static let floaterFrames = 30
    public static let floaterMomentumShare = 0.2
    public static let throwReleaseHeight = 12.0
    public static let throwWindupFrames = 12
    public static let throwSheetFramesPerSecond = 15
    /// Frames from the release to the ball leaving the hand, then to acting again.
    public static let throwReleaseFrames = 3
    public static let throwRecoveryFrames = 15
    /// The up throw, the layup: out of the throw's hold frame into `player_layup`'s nine frames
    /// (its last two drawn twice, held twice as long) at 30 a second, the ball leaving the hand on
    /// frame 5, from where the sheet's frame before draws it, acting again once its last is done;
    /// and on its way up off a half jump, a full hop's speed times the root of a half, so it
    /// climbs half as high (on the ground, into the air).
    public static let layupFramesPerSecond = 30
    public static let layupReleaseSheetFrame = 5
    public static let layupReleaseFrames = layupReleaseSheetFrame * 60 / layupFramesPerSecond
    public static let layupRecoveryFrames = 9 * 60 / layupFramesPerSecond
    public static let layupHopShare = 0.7071067811865476
    /// A throw stance with the chest this close to a rim becomes a dunk, wider than the
    /// basket. The ball goes in at the slam, and the dunker hangs on the rim for
    /// `dunkSlamToHangFrames` and then `dunkHangFrames` before letting go.
    public static let dunkRadius = 25.0
    /// Frames in the throw stance before one by a rim becomes a dunk, so a throw let go
    /// in passing doesn't.
    public static let dunkStanceFrames = 3
    public static var dunkSlamFrame: Int { Animation.dunkSlamFrame }
    public static let dunkSlamToHangFrames = 20
    public static let dunkHangFrames = 45
    /// Frames stuck in the dunk's last frame, the rim hang, before down lets go.
    public static let dunkLetGoDelayFrames = 3
    public static var dunkLetGoFrame: Int { Animation.dunkStart(of: Animation.dunkSequence.count - 1) + dunkLetGoDelayFrames }
    /// Where the dunker's feet go on the rim, from the rim's centre, for a rim with its
    /// backboard on the right; across is mirrored for the other. 16 art pixels back and
    /// 24 down, as the user placed it on the sliders.
    public static let dunkOffset = Vec2(x: -16 / 1.6, y: -24 / 1.6)

    /// The ball is caught within this of the chest, in front. Faster than the threshold it
    /// goes through instead, as a shot in flight does; those take the snatch. Bodies never
    /// deflect the ball.
    public static let catchRadius = 12.5
    /// The second ring, the catch spark's where the snatch puts it, on the hand at full
    /// stretch: centred this far ahead of and above the feet and as big as the spark
    /// grows, in units, from 18, 19 and 16 art pixels. A ball in it is caught whichever
    /// way the body moves.
    public static let handCatchCentre = Vec2(x: 18 / 1.6, y: 19 / 1.6)
    public static let handCatchRadius = 16 / 1.6
    public static let catchSpeedThreshold = 5.0
    /// Knocked loose by a blade or a leg, or robbed by a snatch, the body can't press
    /// anything or catch anything for this long, though the stick still moves it: the
    /// taker's advantage for the ball. Longer than the pop's round trip, which is 32
    /// frames up and back to chest height, so the ball comes down while they're still out.
    public static let hitStunFrames = 60
    public static let chestHeight = 9.0
    /// A ball knocked out of a holder's hands pops straight up: the floater's drift for
    /// this many frames, then a normal fall, nobody's.
    public static let popFloatFrames = 10
    /// Frames a popped ball takes to come back down to the height it left from: the float,
    /// then the rise and the fall, stepped as the ball steps them.
    public static let popAloftFrames: Int = {
        var height = 0.0, rise = floaterSpeed, floating = popFloatFrames, frames = 0
        repeat {
            if floating > 0 { floating -= 1 } else { rise = max(rise - gravity, -fallSpeed) }
            height += rise
            frames += 1
        } while height > 0 && frames < 600
        return frames
    }()

    /// A ball falling toward a rim from within this reach, sideways and above, has its
    /// sideways speed blended each frame toward what would carry it through the rim, by
    /// this share, never by more than this much speed in one frame.
    public static let hoopReach = 25.0
    public static let hoopSteerShare = 0.15
    public static let hoopSteerMax = 0.3
    public static let rimHalfWidth = 6.0
    /// Frames after a score before the ball comes back to centre.
    public static let respawnFrames = 90
}

/// Web Water's numbers.
public enum WebRules {
    /// The swing's anchor sits this far ahead and this far up from the body, wherever it
    /// is, so the swing is the same at any height. The least arc runs past the mirrored
    /// angle by the overshoot, over this many frames; holding jump keeps it going up to
    /// twice that arc, never past this angle over the anchor.
    public static let swingReach = 45.0
    public static let swingHeight = 130.0
    public static let swingFrames = 16
    public static let swingOvershoot = 1.0
    public static let swingMaxArcShare = 1.6
    public static let swingMaxAngle = 1.4
    /// A swing can't start again for this long after one ends (WEB SWING GAP; was a full swing's
    /// frames, 28). It neither spends nor needs the double jump, so a swing let go early doesn't
    /// lock the next one out until landing.
    nonisolated(unsafe) public static var swingCooldownFrames = 20
    /// The line reaches this far, bends to a ball or body within this angle of the aim,
    /// snaps to one within this of its tip, reels at this speed, can't repeat for this long,
    /// and a miss shows for this many frames, live the whole time.
    public static let lineRange = 120.0
    public static let assistAngle = 0.26
    public static let snapRadius = 8.0
    public static let pullSpeed = 5.0
    public static let lineCooldownFrames = 30
    public static let missFrames = 8
    /// A pulled body is dropped this far in front of the shooter's chest, and any pull
    /// gives up after this many frames.
    public static let dropDistance = 12.0
    public static let pullMaxFrames = 40
    /// The shot's pose, let go, plays its four frames after the hold at 15 a second: the line goes
    /// out on the second (the sheet's 5th, the wall's 3rd) and pulls on the fourth (7th, 5th).
    public static let shotOutFrames = 4
    public static let shotPullFrames = 12
    public static let shotPoseFrames = 20
}

/// Super Smoothie's numbers: slow flight in any direction, gravity off, for a budget per
/// airtime, twice as fast without the ball, on a cape of energy. Level two is faster, with
/// the ball as fast as level one without, lasts longer, and the stick forward is the
/// glide: this fast, sinking this much a frame unless up is held, diving this fast on down.
public enum SmoothieRules {
    /// How far up the stick must be for jump to launch: half way, so a diagonal up counts.
    public static let launchStickUp = 0.5
    public static func flightSpeed(level: Int, withBall: Bool) -> Double {
        level >= 2 ? (withBall ? 2.0 : 3.0) : (withBall ? 1.0 : 2.0)
    }

    public static func flightFrames(level: Int) -> Int {
        level >= 2 ? 180 : 120
    }

    public static func glideSpeed(withBall: Bool) -> Double { withBall ? 2.5 : 3.5 }
    public static let glideSink = 0.8
    public static let diveSpeed = 3.0
    /// Level two, from the ground with up held: the launch, straight up this fast into flight,
    /// as high as a full jump and a double jump together.
    public static let launchSpeed = 6.0
}

/// Flash Fizz's numbers. Without the ball, shoot is the warp to the ball while it's still
/// yours, the owned frames after you let it go, arriving holding it; otherwise the
/// flash: this far along the stick, further at level two, or in place, this often. At
/// level two the flashes are tears: the ball within this reach of where it came out is
/// pulled into the hands for this long after, and the other holding the ball within
/// reach of where it left or came out loses it. With the ball, shoot is the warp down
/// to an overhung dribble.
public enum FizzRules {
    public static let cooldownFrames = 60
    /// Five tiles at either level; level two gets two flashes a cooldown.
    public static let flashDistance = 80.0
    public static func flashCharges(level: Int) -> Int { level >= 2 ? 2 : 1 }
    public static let tearFrames = 12
    public static let tearRadius = 15.0
}

/// Platform Protein Shake's numbers: a fast fall makes a slab under the feet this wide and
/// this thick, standing till it's broken or the next, slab or wall, replaces it. Without the ball, shoot makes a wall in front this thick
/// and this tall on the snatch's reach, over this many frames, appearing on this one.
/// Either can be made only this long after the last of either; a slab only after a jump, a
/// wall jump or a wall land since it too, so holding down through a fall makes one, not a
/// stream, and jump, slab, jump, slab still works.
public enum ShakeRules {
    public static let platformWidth = 30.0
    public static let platformThickness = 10.0
    public static let cooldownFrames = 75
    public static let wallWidth = 10.0
    public static let wallHeight = 30.0
    public static let wallFrames = 24
    public static let wallAppearFrame = 8
}

/// The slide's numbers: down at full run without the ball, or shoot while crouched. It
/// starts at the dash burst and carries it for the body's slide frames, bleeding only
/// its slide friction, then stands up into the run's skid. The extended leg reaches this
/// far past the body's front edge and this high off the floor, and knocks the ball out
/// of a grounded holder it meets.
public enum SlideRules {
    public static let legReach = 10.0
    public static let legHeight = 6.0
    /// A loose ball the slide meets is kicked on ahead, this far up from level, at the swat's speed.
    public static let kickAngle = degrees(30)
    /// Slide Cider: the leg's knock on a body it meets, the way the slide goes and up.
    public static let ciderKnock = Vec2(x: 4, y: 2)
}

/// The Esper Slash's numbers: shoot without the ball, in neutral or on defence. On the
/// ground it carries what run it had and is over when the swing is; in the air the body
/// rises at least this fast and gravity is cut to this share, so it hangs through the
/// swing, and the roll follows over this many frames. Both play at this many sheet
/// frames a second. The blade is a square round the body, 56 art pixels a side, its centre
/// this far in front of the body's, live over these sheet frames. A body it meets, ball
/// or no ball, is stripped and knocked this far along the swing. It knocks the ball out of a holder's hands, or spikes a loose one down
/// and away at about this angle below the horizontal, jittered by up to this much, at no
/// less than this speed.
public enum SlashRules {
    public static let sheetFramesPerSecond = 15
    public static let sheetFrames = 6
    public static var frames: Int { simFrames(sheetFrames, at: sheetFramesPerSecond) }
    public static var rollFrames: Int { frames }
    public static let lift = 0.5
    public static let gravityShare = 0.7
    /// Half the blade's box across: 52 art pixels across, 56 at first.
    public static let reach = 52 / 1.6 / 2
    public static let forward = 4 / 1.6
    public static let liveSheetFrames = 1..<6
    public static var liveFrames: Range<Int> { simFrames(liveSheetFrames, at: sheetFramesPerSecond) }
    public static let spikeAngle = degrees(-45)
    public static let spikeJitter = degrees(10)
    public static let swatSpeed = 6.0
    /// Knocked along the swing, harder while it's tried in place of the stun's lockout.
    public static let knock = Vec2(x: 4, y: 2)
}

/// Whether a stun also locks the stick. Parked off while a harder knockback is tried
/// instead; the lock stays, one switch away.
public enum StunRules {
    public static let locksMovement = false
    /// Off: a hit body jumps as it moves, so movement is all free or all locked, never half.
    public static let locksJump = false
}

/// Hits taken close together: each one within `windowFrames` of the last makes the next grace
/// longer, `stepFrames` a hit past the first, in which attacks pass through, so a chain can't trap.
public enum HitGraceRules {
    public static var windowFrames = 120
    public static var stepFrames = 30
    public static func graceFrames(chainedHits: Int) -> Int { max(chainedHits - 1, 0) * stepFrames }
}

/// A parry's reward: the parrier back in neutral at once, free to do anything, while the one
/// parried is locked out of every input, reeling, through the stun (`BallRules.hitStunFrames`)
/// and this long more, so the parry can be made something of: two seconds in all, every counter's.
public enum ParryRules {
    public static let attackLockoutAfterStunFrames = 60
}

/// The stepback: down on the ground in a shot's or throw's stance once it's held, once a
/// stance, sliding straight back 48 art pixels over this many frames on the throw sheet's
/// third frame, facing kept, countering a blade and not to be snatched the whole way, then
/// back in the stance at its hold.
public enum StepbackRules {
    public static let distance = 48 / 1.6
    public static let frames = 12
    public static let sheetFrame = 2
}

/// The rim's top, a thin platform that can't be stood on: a body coming down on it is sent
/// back up at this speed, a ball that isn't scoring bounces off it; nothing climbs it or
/// drops through it.
public enum RimRules {
    public static let bodyBounce = 3.5
    /// With jump held as the body meets the rim.
    public static let jumpBounce = 4.5
    /// Under water a bounce off a rim rises half as high: the push at the square root of a half.
    public static let underwaterBounceShare = 0.5.squareRoot()
}

/// Hit-stop: the whole match held this many frames after a hit lands or a counter, the longest;
/// none for a basket.
public enum HitStopRules {
    public static let hitFrames = 8
    /// A counter's: the rock-paper-scissors won, a parry among them; under a clash's.
    public static let counterFrames = 28
    /// Every clash's, slash, snatch or shield, held long.
    public static let clashFrames = 40
    /// A Breaker Ball barrier shattering.
    public static let shatterFrames = 30
}

/// A clash over: both bodies pushed hard down and away from where they met, nothing answering
/// till they've landed and slid to a stop, braking this much a frame along the ground.
public enum ClashRules {
    public static let knock = Vec2(x: 6, y: -4)
    public static let slideBrake = 0.3
}

/// FloState's slash, on the ground or in the air: one attack, a step through forward the FloState snatch's
/// distance while its sheet's nine frames play through, both its swings, at 30 a second. The
/// blade's box is live from its first frame to its last and hits once a swing: twice in all, the
/// second swing from its sheet's fifth frame.
public enum FloSlashRules {
    public static let sheetFramesPerSecond = 30
    public static let sheetFrames = 9
    public static var frames: Int { simFrames(sheetFrames, at: sheetFramesPerSecond) }
    public static let secondSwingSheetFrame = 4
    public static var secondSwingFrame: Int { simFrames(secondSwingSheetFrame, at: sheetFramesPerSecond) }
    public static var travel: Double { SnatchRules.floStateTravel }
    /// Over its last frame till the plain slash would be over: no sooner ready again.
    public static var lastingFrames: Int { max(frames, SlashRules.frames) }
}

/// The snatch's numbers: throw without the ball, in neutral or on defence. Over this many
/// frames; the hand is out over these, and the whole body plus this much of reach in
/// front, or the hand's catch ring, takes any ball it touches while the body faces it,
/// loose or in the other's hands. The spark shows on this sheet frame. It can repeat
/// as soon as it's over, as the slash can. Meeting a live blade, it's the parry: the
/// slasher is the one stripped and knocked back.
public enum SnatchRules {
    public static let sheetFramesPerSecond = 15
    public static let sheetFrames = 10
    /// The third sheet frame, the hand at full stretch, holds twice as long as the rest.
    public static let heldSheetFrame = 2
    public static let heldTimes = 2
    /// The sim frame a sheet frame starts on, with the held one's extra length in.
    public static func simStart(ofSheetFrame frame: Int) -> Int {
        let each = simFrames(1, at: sheetFramesPerSecond)
        return frame * each + (frame > heldSheetFrame ? each * (heldTimes - 1) : 0)
    }
    /// The sheet frame showing on a sim frame.
    public static func sheetFrame(at simFrame: Int) -> Int {
        let each = simFrames(1, at: sheetFramesPerSecond)
        let heldEnd = simStart(ofSheetFrame: heldSheetFrame + 1)
        if simFrame < simStart(ofSheetFrame: heldSheetFrame) { return simFrame / each }
        if simFrame < heldEnd { return heldSheetFrame }
        return heldSheetFrame + 1 + (simFrame - heldEnd) / each
    }
    /// The last two sheet frames are left off, for the held frame's extra length.
    public static let playedSheetFrames = sheetFrames - 2
    public static var frames: Int { simStart(ofSheetFrame: playedSheetFrames) }
    public static let activeSheetFrames = 2..<4
    public static var activeFrames: Range<Int> { simStart(ofSheetFrame: activeSheetFrames.lowerBound)..<simStart(ofSheetFrame: activeSheetFrames.upperBound) }
    public static let sparkSheetFrame = 2
    public static var sparkFrame: Int { simStart(ofSheetFrame: sparkSheetFrame) }
    public static let cooldownFrames = 0
    public static let parryKnock = Vec2(x: 3, y: 1.5)
    /// FloState's snatch on the ground steps through the other: 96 art pixels forward over the
    /// snatch, two of the sheets' 48-pixel boxes, taking the ball off whatever it passes.
    public static let floStateTravel = 60.0
}

/// The ledge's numbers: falling past a corner with no ball, the hand catches it when the
/// corner is within this reach of the body's side and within this much either way of
/// hand height, which is this far above the feet, 28 art pixels as the sheet draws it.
/// The hang lasts this long and the climb this long, and for this long after walking off
/// an edge the corner just left can't be grabbed again.
/// Down held this many frames standing on a one-way drops through it, and one-ways are
/// passed through for this many after, time to fall clear of the platform's top.
public enum DropRules {
    public static let holdFrames = 10
    public static let passFrames = 12
}

public enum LedgeRules {
    public static let hangDepth = 17.5
    public static let grabReach = 10.0
    public static let grabSlack = 10.0
    public static let hangFrames = 10
    public static let climbFrames = 15
    public static let walkOffCooldownFrames = 20
}

/// Sim frames, at sixty a second, for this many sheet frames at the sheet's rate.
func simFrames(_ sheetFrames: Int, at sheetFramesPerSecond: Int) -> Int {
    sheetFrames * 60 / sheetFramesPerSecond
}

/// The sim frames a range of sheet frames covers, at the sheet's rate.
func simFrames(_ sheetFrames: Range<Int>, at sheetFramesPerSecond: Int) -> Range<Int> {
    simFrames(sheetFrames.lowerBound, at: sheetFramesPerSecond)..<simFrames(sheetFrames.upperBound, at: sheetFramesPerSecond)
}

/// A throw's charge: the stance held past its windup, full after `fullFrames` in it (where the charge's
/// swirl starts its loop). The speed runs from `leastSpeed` to `mostSpeed` (`BallRules.throwSpeed`,
/// as throws were, at three quarters), still well over a floater's; at full, none but the thrower takes it
/// till it bounces. Not the floater's.
public enum ThrowChargeRules {
    public static let fullFrames = 70
    public static let leastSpeed = 4.0
    public static let mostSpeed = 8.0

    /// The charge, 0 to 1, for a stance held this long.
    public static func charge(heldFrames: Int) -> Double {
        min(max(Double(heldFrames - BallRules.throwWindupFrames) / Double(fullFrames - BallRules.throwWindupFrames), 0), 1)
    }
    public static func speed(_ charge: Double) -> Double { leastSpeed + (mostSpeed - leastSpeed) * charge }
}
