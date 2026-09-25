import Foundation

/// The things the newer powers leave in the world, each a value the match carries and
/// steps: Zeus Juice's bolts, Frost Tea's ice clones, Blazing Boba's flames and
/// fireballs. A "strip" is the shared outcome of most hits: the victim is stunned and any
/// ball they hold pops free; some strips knock the body away too.
public struct Bolt: Equatable {
    public var id: Int
    public var owner: Int
    public var position: Vec2
    public var velocity: Vec2
    public var framesLeft: Int
}

public struct IceClone: Equatable {
    public var id: Int
    public var owner: Int
    public var box: Box
    public var framesLeft: Int
}

public struct Flame: Equatable {
    public var id: Int
    public var owner: Int
    public var box: Box
    public var framesLeft: Int
}

public struct Fireball: Equatable {
    public var id: Int
    public var owner: Int
    public var position: Vec2
    public var velocity: Vec2
    public var framesLeft: Int
    /// Thrown, it flies dead straight, as a thrown ball does; shot, it arcs, floatier
    /// than the ball.
    public var straight: Bool
}

/// Surf Soda: the jumps are a fixed crescent, a quarter circle this high and this far
/// forward over these frames; from its top the stick spins the body at this rate a frame
/// instead of drifting it, and within this height of the ground it eases upright, this
/// share a frame. Under the feet a board this long and thick, turning with the body,
/// stops the other's bolts and fireballs and turns back their thrown ball. First guesses,
/// for tuning.
public enum SurfRules {
    public static let rise = 40.0
    public static let reach = 30.0
    public static let pathFrames = 30
    public static let spinRate = 0.25
    public static let uprightHeight = 30.0
    public static let uprightShare = 0.15
    public static let boardLength = 20.0
    public static let boardThickness = 3.0
    /// A tenth faster on the board, on top of the defender's tenth.
    public static let speedShare = 1.1
    /// Past the crescent's top it floats down: this share of gravity, falling no faster than
    /// this share of the fall speed, unless the fast fall cuts through.
    public static let gravityShare = 0.5
    public static let fallShare = 0.6
    /// The first jump leans back this far over its crescent; the double jump is a whole
    /// backflip over it.
    public static let jumpLean = Double.pi / 4
    /// Into a wall on the board: up it at the run speed while the stick holds toward it;
    /// off it with this push, in a backflip over this many frames.
    public static let wallLeap = Vec2(x: 2.5, y: 2.5)
    public static let flipFrames = 30
}

/// Slopes: a body's feet ride one up or down this far a frame at most, a block's height;
/// the diagonal's normal is this share of each axis.
public enum SlopeRules {
    public static let step = 5.5
    public static let diagonal = 0.7071067811865476
}

/// Quake-Up Coffee: a fast fall's landing shakes the floor. At level one whatever is
/// grounded on the same floor is hit, the ball hopping up by this much and the other
/// stripped; at level two the whole screen is the floor.
public enum QuakeRules {
    /// The fast fall is this much faster than anyone else's.
    public static let fastFallMultiplier = 1.6
    public static let ballHop = 3.0
    public static let knock = Vec2(x: 0, y: 2)
    /// Bodies within this of each other's height stand on the same floor.
    public static let sameFloorSlack = 1.0
}

/// Zeus Juice: shoot without the ball throws a bolt straight ahead at this speed, tilted
/// by the stick up to this far, for this long, this often. A body it meets is stripped and
/// knocked on; the ball it meets pops back toward the thrower. Level two's throw calls a
/// strike down from the top of the screen, this wide, at the ball in hand or at the
/// snatch's hand.
public enum ZeusRules {
    public static let boltSpeed = 6.0
    public static let boltTilt = degrees(30)
    public static let boltFrames = 60
    public static let boltCooldownFrames = 24
    /// The whole throw sheet, eight frames at 15 a second, and the bolt leaves on its
    /// release frame, the fifth.
    public static let boltPoseFrames = 32
    public static let boltReleaseFrame = 16
    /// A bolt knocks a body as the slash does.
    public static var boltKnock: Vec2 { SlashRules.knock }
    public static let ballPop = Vec2(x: 2, y: 2)
    public static let strikeHalfWidth = 2.5
    public static let strikeCooldownFrames = 40
}

/// Frost Tea: the snatch freezes what it reaches for this long, a body or the loose ball,
/// held exactly where it is. The slide has no friction and runs until it's cancelled. At
/// level two a double jump or a slide leaves an ice clone, the body's box, that freezes
/// whatever touches it and shatters after this long.
public enum FrostRules {
    public static let freezeFrames = 60
    public static let cloneFrames = 60
}

/// Blazing Boba: a run at full speed or a slide leaves a flame every few frames, this big
/// at the feet, for this long; the other side touching one is stripped. A shot or a throw
/// sets the ball alight until its first bounce, and nobody but the thrower can catch or
/// snatch it. Level two: shoot and throw together with nothing in hand makes a fireball
/// in hand, shot or thrown like the ball but under this share of its gravity, that
/// bursts on whatever it meets, stripping and knocking everything within this reach.
public enum BlazeRules {
    public static let flameEveryFrames = 4
    public static let flameWidth = 6.0
    public static let flameHeight = 4.0
    public static let flameFrames = 45
    public static let flameKnock = Vec2(x: 0, y: 2)
    public static let fireballGravityShare = 0.5
    /// Frames the throw's hold frame shows after a summon, while the fire gathers.
    public static let summonPoseFrames = 30
    public static let fireballFrames = 150
    /// A fireball leaves at this many times the ball's speed, shot or thrown.
    public static let fireballSpeedShare = 1.5
    public static let burstReach = 15.0
    public static let burstKnock = Vec2(x: 3, y: 2.5)
}

/// Pulsepistol Punch: shoot without the ball fires a pulse the width of the screen the way
/// the body faces, this tall at the hand, that knocks the ball and the other body away
/// without stunning and without a spark, a held ball popping free. Level two runs while shooting, and throw
/// is the pull, the same pulse bringing everything toward the body.
public enum PulseRules {
    public static let halfHeight = 5.0
    public static let handHeight = 11.0
    public static let ballPush = Vec2(x: 5, y: 1)
    public static let bodyPush = Vec2(x: 3, y: 1.5)
    /// The gun sheet's ten frames at 15 a second, the pulse on its third sheet frame; on
    /// the run, the running sheet's eight frames at the same rate.
    public static let shotFrames = 40
    public static let fireFrame = 8
    public static let runShotFrames = 32
    public static let cooldownFrames = 20
}
