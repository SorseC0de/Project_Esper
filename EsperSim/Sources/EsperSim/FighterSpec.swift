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
    public var airSpeedMax: Double
    public var airAccelerationBase: Double
    public var airAccelerationAdditional: Double
    public var airFriction: Double
    public var landingLagFrames: Int

    public var wallJumpHorizontal: Double
    public var wallJumpVertical: Double
    /// Speed of the slide down the wall while clinging.
    public var wallSlideSpeed: Double
    /// Frames the cling lasts before dropping off.
    public var wallLandFrames: Int
    /// Frames after leaving a wall before another cling can start.
    public var wallLandCooldownFrames: Int

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
        airSpeedMax: 0.86,
        airAccelerationBase: 0.02,
        airAccelerationAdditional: 0.025,
        airFriction: 0.016,
        landingLagFrames: 4,
        wallJumpHorizontal: 1.5,
        wallJumpVertical: 2.0,
        wallSlideSpeed: 0.3,
        wallLandFrames: 12,
        wallLandCooldownFrames: 30,
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
        wallLandFrames: 12,
        wallLandCooldownFrames: 30,
        bodyWidth: 10,
        bodyHeight: 15
    )
}

/// Everything about the ball, the hoops and the plays on them. Units and frames.
public enum BallRules {
    public static let gravity = 0.09
    public static let fallSpeed = 5.0
    public static let radius = 2.5
    /// Speed kept after hitting a wall, the floor, or a body.
    public static let bounce = 0.75
    /// Floor friction per frame while rolling, and the speed under which the ball rests.
    public static let rollingFriction = 0.9
    public static let restSpeed = 0.2

    /// A shot leaves from this high above the feet and arcs at this speed.
    public static let shotSpeed = 2.5
    public static let shotReleaseHeight = 25.0
    public static let shotAngleMin = degrees(25)
    public static let shotAngleMax = degrees(80)
    public static let shotAngleDefault = degrees(53)
    /// Aim length the flick has to reach to count.
    public static let flickThreshold = 0.5
    /// Frames from taking the stance to being able to release.
    public static let shotWindupFrames = 20
    /// Frames from the release to the ball leaving the hand, then to acting again.
    public static let shotReleaseFrames = 5
    public static let shotRecoveryFrames = 10
    /// Frames after any release before the same player can catch it back.
    public static let catchCooldownFrames = 15
    /// In the air the stance holds the fall to this.
    public static let stanceFallSpeed = 0.5

    /// A throw goes straight at this speed, with no gravity until its first bounce.
    public static let throwSpeed = 5.0
    public static let throwReleaseHeight = 12.0
    public static let throwWindupFrames = 25
    public static let throwRecoveryFrames = 15
    /// A throw stance this close to a rim becomes a dunk.
    public static let dunkRadius = 12.0
    public static let dunkFrames = 20

    /// The ball is caught within this of the chest, in front.
    public static let catchRadius = 12.5
    public static let chestHeight = 9.0
    /// The swat reaches this far and can't repeat for this long.
    public static let swatRadius = 20.0
    public static let swatCooldownFrames = 80
    public static let swatFrames = 30

    /// The rim pulls the ball in from this far, at strength over distance squared, and
    /// swallows it within the absorb radius.
    public static let hoopPullRadius = 25.0
    public static let hoopPullStrength = 20.0
    public static let hoopAbsorbRadius = 12.0
    public static let rimHalfWidth = 6.0
    /// Frames after a score before the ball comes back to centre.
    public static let respawnFrames = 90
}
