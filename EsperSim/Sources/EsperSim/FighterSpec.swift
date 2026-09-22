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
    /// A jump with the stick held starts at least this fast sideways.
    public var jumpHorizontalVelocity: Double
    /// A double jump with the stick held sets the sideways speed to this, which turns around.
    public var doubleJumpHorizontalVelocity: Double
    public var gravity: Double
    public var fallSpeed: Double
    public var fastFallSpeed: Double
    public var airSpeedMax: Double
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
    /// A jump press in the air with a wall this close on either side is a wall jump, cling
    /// or not.
    public var wallJumpReach = 2.0
    /// Frames after letting go of a wall in which a jump press still jumps off it.
    public var wallJumpGraceFrames = 6
    /// Frames after a wall jump in which the stick doesn't steer, so the arc leaves the wall.
    public var wallJumpControlLockFrames = 6
    /// Frames after walking off an edge in which a jump press is still a ground jump.
    public var coyoteFrames = 3
    /// Frames of holding down in a run before it brakes to walking speed.
    public var runBrakeHoldFrames = 4
    /// Frames into a walk with the ball in which the stick still turns the body, before it
    /// faces the opponent. Without the ball a walk faces the stick.
    public var walkFaceLockoutFrames = 3
    /// Speed of a crouch walk.
    public var crouchWalkSpeed = 0.8
    /// Sideways speed lost per frame in an airborne stance.
    public var stanceAirBrake = 0.01
    /// Speed lost per frame on the ground through a snatch or a slash, so a run or a dash
    /// carries into them.
    public var attackBrake = 0.15

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
        jumpHorizontalVelocity: 0.86,
        doubleJumpHorizontalVelocity: 0.86,
        gravity: 0.095,
        fallSpeed: 1.7,
        fastFallSpeed: 2.3,
        airSpeedMax: 0.86,
        airAccelerationBase: 0.02,
        airAccelerationAdditional: 0.025,
        airFriction: 0.016,
        landingLagFrames: 4,
        wallJumpHorizontal: 1.5,
        wallJumpVertical: 2.0,
        wallSlideSpeed: 0.3,
        wallLandCooldownFrames: 6,
        bodyWidth: 10,
        bodyHeight: 15
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
        jumpHorizontalVelocity: 1.12,
        doubleJumpHorizontalVelocity: 1.12,
        gravity: 0.13,
        fallSpeed: 2.9,
        fastFallSpeed: 3.5,
        airSpeedMax: 1.12,
        airAccelerationBase: 0.02,
        airAccelerationAdditional: 0.04,
        airFriction: 0.01,
        landingLagFrames: 4,
        wallJumpHorizontal: 2.3,
        wallJumpVertical: 2.7,
        wallSlideSpeed: 0.5,
        wallLandCooldownFrames: 6,
        bodyWidth: 10,
        bodyHeight: 15
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
        jumpHorizontalVelocity: 0.83,
        doubleJumpHorizontalVelocity: 0.83,
        gravity: 0.23,
        fallSpeed: 2.8,
        fastFallSpeed: 3.4,
        airSpeedMax: 0.83,
        airAccelerationBase: 0.02,
        airAccelerationAdditional: 0.06,
        airFriction: 0.02,
        landingLagFrames: 4,
        wallJumpHorizontal: 2.2,
        wallJumpVertical: 3.2,
        wallSlideSpeed: 0.5,
        wallLandCooldownFrames: 6,
        bodyWidth: 10,
        bodyHeight: 15
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
        jumpHorizontalVelocity: 0.8,
        doubleJumpHorizontalVelocity: 0.8,
        gravity: 0.13,
        fallSpeed: 2.13,
        fastFallSpeed: 3.0,
        airSpeedMax: 0.8,
        airAccelerationBase: 0.02,
        airAccelerationAdditional: 0.04,
        airFriction: 0.04,
        landingLagFrames: 4,
        wallJumpHorizontal: 1.8,
        wallJumpVertical: 2.5,
        wallSlideSpeed: 0.5,
        wallLandCooldownFrames: 6,
        bodyWidth: 10,
        bodyHeight: 15
    )
}

extension FighterSpec {
    /// The body the game is tuned on: Fox with a Falco-style dash, the burst always 0.4 over
    /// the 3.2 run,
    /// more traction, air control turned up so a jump starts at air speed and turns in about
    /// five frames, and a shoot stance that brakes hard in the air.
    public static let baseline: FighterSpec = {
        var spec = meleeFox
        spec.name = "Baseline"
        spec.runSpeed = 3.2
        spec.dashInitialVelocity = spec.runSpeed + 0.4
        spec.traction = 0.35
        spec.airSpeedMax = 1.6
        spec.airAccelerationAdditional = 0.24
        spec.jumpHorizontalVelocity = 1.6
        spec.doubleJumpHorizontalVelocity = 1.6
        spec.stanceAirBrake = 0.15
        return spec
    }()
}

/// Everything about the ball, the hoops and the plays on them. Units and frames.
public enum BallRules {
    public static let gravity = 0.15
    public static let fallSpeed = 6.0
    public static let radius = 2.5
    /// Speed kept after hitting a wall, the floor, or a body.
    public static let bounce = 0.75
    /// Floor friction per frame while rolling, and the speed under which the ball rests.
    public static let rollingFriction = 0.9
    public static let restSpeed = 0.2

    /// A shot leaves from this high above the feet and arcs at this speed.
    public static let shotSpeed = 4.5
    public static let shotReleaseHeight = 25.0
    public static let shotAngleMin = degrees(25)
    public static let shotAngleMax = degrees(80)
    public static let shotAngleDefault = degrees(53)
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
    /// Frames after any release before the same player can catch it back.
    public static let catchCooldownFrames = 15
    /// In the air the stance holds the fall to this.
    public static let stanceFallSpeed = 0.5

    /// A throw goes straight at this speed, with no gravity until its first bounce.
    public static let throwSpeed = 7.0
    /// An up throw is the floater: it drifts up this fast, gravity off, for this many
    /// frames, then falls as a ball does. It keeps this share of the run it started from,
    /// enough to drift with the thrower and not enough to arc.
    public static let floaterSpeed = 1.5
    public static let floaterFrames = 30
    public static let floaterMomentumShare = 0.2
    public static let throwReleaseHeight = 12.0
    public static let throwWindupFrames = 12
    /// Frames from the release to the ball leaving the hand, then to acting again.
    public static let throwReleaseFrames = 3
    public static let throwRecoveryFrames = 15
    /// A throw stance this close to a rim becomes a dunk.
    public static let dunkRadius = 12.0
    public static let dunkFrames = 20

    /// The ball is caught within this of the chest, in front. Faster than the threshold it
    /// bounces off instead, unless the body is in the catch stance: a shoot button held
    /// with no ball.
    public static let catchRadius = 12.5
    /// The second ring, the catch spark's where the snatch puts it, on the hand at full
    /// stretch: centred this far ahead of and above the feet and as big as the spark
    /// grows, in units, from 18, 19 and 16 art pixels. A ball in it is caught whichever
    /// way the body moves.
    public static let handCatchCentre = Vec2(x: 18 / 1.6, y: 19 / 1.6)
    public static let handCatchRadius = 16 / 1.6
    public static let catchSpeedThreshold = 5.0
    public static let chestHeight = 9.0
    /// A ball knocked out of a holder's hands pops straight up: the floater's drift for
    /// this many frames, then a normal fall, nobody's.
    public static let popFloatFrames = 10

    /// A ball falling toward a rim from within this reach, sideways and above, has its
    /// sideways speed blended each frame toward what would carry it through the rim, by
    /// this share, never by more than this much speed in one frame.
    public static let hoopReach = 25.0
    public static let hoopSteerShare = 0.15
    public static let hoopSteerMax = 0.3
    public static let rimHalfWidth = 6.0
    /// Frames after a score before the ball comes back to centre.
    public static let respawnFrames = 90
    /// Frames after a shot, throw or dunk the ball still counts as the thrower's.
    public static let ownedFrames = 60
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
    /// A swing can't start again for this long after one ends: the frames a full swing
    /// takes, the least arc's frames times the max share plus the ease-in's frame and a
    /// half. It neither spends nor needs the double jump, so a swing let go early doesn't
    /// lock the next one out until landing.
    public static let swingCooldownFrames = Int((Double(swingFrames) * swingMaxArcShare + 1.5).rounded(.up))
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
}

/// Super Soda's numbers: slow flight in any direction, gravity off, this long per airtime.
/// Twice as fast without the ball.
public enum SodaRules {
    public static let flightSpeed = 1.0
    public static let flightSpeedWithoutBall = 2.0
    public static let flightFrames = 120
}

/// Flash Fizz's numbers. Without the ball, shoot is the flash: this far along the stick,
/// or in place, this often. The tear it leaves at the exit lasts this long and pulls a
/// loose ball within this reach into the hands. With the ball, shoot is the warp down to
/// an overhung dribble.
public enum FizzRules {
    public static let cooldownFrames = 60
    public static let flashDistance = 30.0
    public static let tearFrames = 12
    public static let tearRadius = 12.0
}

/// Platform Protein Shake's numbers: a fast fall makes a slab under the feet this wide,
/// this thick, for this long. Without the ball, shoot makes a wall in front this thick
/// and this tall on the snatch's reach, over this many frames, appearing on this one.
/// Either can be made again only this long after the last, and only after a jump, a
/// wall jump or a wall land since it, so holding down through a fall makes one, not a
/// stream, and jump, slab, jump, slab still works.
public enum ShakeRules {
    public static let platformWidth = 30.0
    public static let platformThickness = 10.0
    public static let platformFrames = 60
    public static let cooldownFrames = 75
    public static let wallWidth = 10.0
    public static let wallHeight = 30.0
    public static let wallFrames = 24
    public static let wallAppearFrame = 8
}

/// The slide's numbers: down at full run without the ball, or shoot while crouched. It
/// starts at the dash burst and bleeds this much a frame for this long. The extended leg
/// reaches this far past the body's front edge and this high off the floor, and knocks
/// the ball out of a grounded holder it meets.
public enum SlideRules {
    public static let frames = 20
    public static let friction = 0.15
    public static let legReach = 10.0
    public static let legHeight = 6.0
}

/// The Esper Slash's numbers: shoot on defence, with the other holding the ball. On the
/// ground it carries what run it had and is over when the swing is; in the air the body rises at
/// least this fast and gravity is cut to this share, so it hangs through the swing, and
/// the roll follows over this many frames. Both play at this many sheet frames a second.
/// The blade is where the sheet draws the crescent, frame by frame: raised behind and
/// above on sheet frame 1, overhead on 2, swung down in front on 3, in units from the
/// feet facing right. It knocks the ball out of a holder's hands, body or ball, or swats
/// a loose one away at no less than this speed.
public enum SlashRules {
    public static let frames = 18
    public static let rollFrames = 18
    public static let sheetFramesPerSecond = 20
    public static let lift = 1.0
    public static let gravityShare = 0.2
    public static let blades: [Int: Box] = [
        1: Box(min: Vec2(x: -14, y: 8), max: Vec2(x: 0, y: 21)),
        2: Box(min: Vec2(x: -13, y: 16), max: Vec2(x: 8, y: 21)),
        3: Box(min: Vec2(x: 1, y: 0), max: Vec2(x: 18, y: 25)),
    ]
    /// The sim frames on which some blade is live.
    public static let liveFrames = 3..<12
    public static let swatSpeed = 6.0
}

/// The snatch's numbers: throw without the ball, in neutral or on defence. Over this many
/// frames; the hand is out over these, and the whole body plus this much of reach in
/// front takes any ball it overlaps while the body faces it, loose or in the other's
/// hands. The spark shows on this frame. Then it can't repeat for this long.
public enum SnatchRules {
    public static let frames = 40
    public static let activeFrames = 4..<16
    public static let sparkFrame = 8
    public static let reach = 10.0
    public static let cooldownFrames = 30
}

/// The ledge's numbers: falling past a corner with no ball, the hand catches it when the
/// corner is within this reach of the body's side and within this much either way of
/// hand height, which is this far above the feet, 28 art pixels as the sheet draws it.
/// The hang lasts this long and the climb this long, and for this long after walking off
/// an edge the corner just left can't be grabbed again.
public enum LedgeRules {
    public static let hangDepth = 17.5
    public static let grabReach = 10.0
    public static let grabSlack = 10.0
    public static let hangFrames = 10
    public static let climbFrames = 15
    public static let walkOffCooldownFrames = 20
}
