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
    /// Sideways speed lost per frame in an airborne stance.
    public var stanceAirBrake = 0.01

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
    public static let catchSpeedThreshold = 5.0
    public static let chestHeight = 9.0
    /// The swat reaches this far and can't repeat for this long.
    public static let swatRadius = 20.0
    public static let swatCooldownFrames = 80
    public static let swatFrames = 30

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
    public static let ownedFrames = 45
}

/// Web Water's numbers.
public enum WebRules {
    /// The swing's anchor sits this far ahead at the top of the court. The least arc runs
    /// past the mirrored angle by the overshoot, over this many frames; holding jump keeps
    /// it going up to twice that arc, never past this angle over the anchor.
    public static let swingReach = 35.0
    public static let swingFrames = 16
    public static let swingOvershoot = 1.15
    public static let swingMaxArcShare = 2.0
    public static let swingMaxAngle = 1.4
    /// The line reaches this far, bends to a ball or body within this angle of the aim,
    /// snaps to one within this of its tip, reels at this speed, can't repeat for this long,
    /// and a miss shows for this many frames.
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
public enum SodaRules {
    public static let flightSpeed = 1.0
    public static let flightFrames = 120
}

/// Flash Fizz's numbers: the warp to a ball that's still yours, this often.
public enum FizzRules {
    public static let cooldownFrames = 60
}
