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
}

/// Quake-Up Coffee: a fast fall's landing shakes the floor. At level one whatever is
/// grounded on the same floor is hit, the ball hopping up by this much and the other
/// stripped; at level two the whole screen is the floor.
public enum QuakeRules {
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
    public static let boltKnock = Vec2(x: 3, y: 1.5)
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
/// snatch it. Level two: shoot held this long with nothing in hand makes a fireball in
/// hand, shot or thrown like the ball, that bursts on whatever it meets, stripping and
/// knocking everything within this reach.
public enum BlazeRules {
    public static let flameEveryFrames = 4
    public static let flameWidth = 6.0
    public static let flameHeight = 4.0
    public static let flameFrames = 45
    public static let flameKnock = Vec2(x: 0, y: 2)
    public static let fireballHoldFrames = 15
    public static let fireballFrames = 120
    public static let burstReach = 15.0
    public static let burstKnock = Vec2(x: 3, y: 2.5)
}

/// Pulsepistol Punch: shoot without the ball fires a pulse the width of the screen the way
/// the body faces, this tall at the hand, that knocks the ball and the other body away
/// without stunning, a held ball popping free. Level two runs while shooting, and throw
/// is the pull, the same pulse bringing everything toward the body.
public enum PulseRules {
    public static let halfHeight = 2.5
    public static let handHeight = 11.0
    public static let ballPush = Vec2(x: 5, y: 1)
    public static let bodyPush = Vec2(x: 3, y: 1.5)
    public static let shotFrames = 10
    public static let fireFrame = 3
    public static let cooldownFrames = 20
}

/// Super Smoothie: the glide. Falling with jump held after the jumps are spent, the body
/// levels off and glides; the stick pitches it up or down between these angles, a climb
/// bleeding speed and a dive gaining it, and it ends when jump is let go, the speed
/// falls under the stall, or something is hit. Level two climbs steeper and runs faster.
public enum GlideRules {
    public static let startSpeed = 2.0
    public static let stallSpeed = 0.7
    public static func maxSpeed(level: Int) -> Double { level >= 2 ? 5.0 : 4.0 }
    public static func pitchUpMax(level: Int) -> Double { level >= 2 ? degrees(60) : degrees(40) }
    public static let pitchDownMax = degrees(-60)
    public static let pitchRate = 0.035
    public static let gravityShare = 0.06
    public static let drag = 0.004
}
