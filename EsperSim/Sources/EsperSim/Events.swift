import Foundation

/// Something that happened this frame that the screen might want to show. Cleared every
/// frame; nothing in the sim reads them back.
public enum MatchEvent: Equatable {
    case jumped(player: Int)
    case doubleJumped(player: Int)
    case wallJumped(player: Int, wall: Facing)
    case dashed(player: Int)
    case landed(player: Int)
    case caught(player: Int)
    case shot(player: Int)
    case thrown(player: Int)
    case dunked(player: Int)
    case swatted(player: Int, hit: Bool)
    /// `entry` is the ball's velocity as it went through.
    case scored(player: Int, hoop: Int, entry: Vec2)
    case ballBounced(position: Vec2)
    case ballRespawned
    case helmetSpawned(at: Vec2, owner: Int)
    /// Gone at the far wall.
    case helmetRemoved(at: Vec2, owner: Int)
    case helmetsCollided(at: Vec2, owner: Int)
    case portalOpened(at: Vec2)
    case portalClosed(at: Vec2)
    case portalWarped(from: Vec2, to: Vec2)
    case carHit(id: Int)
    case carWrecked(id: Int, at: Vec2)
    case carArrived(id: Int)
    case helicopterArrived(hoop: Int)
    case surfLanded(player: Int)
    /// Something the other threw or fired stopped on Surf Soda's board.
    case boardBlocked(player: Int, at: Vec2)
    case webSwung(player: Int)
    case webLine(player: Int, hit: Bool)
    case flew(player: Int)
    case warped(player: Int, from: Vec2, to: Vec2)
    /// Flash Fizz's flash without the ball: the tear left at `to` pulls a loose ball in.
    case flashed(player: Int, from: Vec2, to: Vec2)
    case platformMade(player: Int)
    case slid(player: Int)
    case slashed(player: Int)
    /// The snatch's hand is at full stretch.
    case snatchReached(player: Int)
    /// The ball knocked out of `player`'s hands by `by`.
    case popped(player: Int, by: Int)
    case ledgeGrabbed(player: Int)
    /// A body struck without the ball: stunned, and knocked if `knocked`.
    case struck(player: Int, by: Int)
    /// A snatch met a live blade: the slasher is the one stripped.
    case parried(player: Int, by: Int)
    case quaked(player: Int)
    case boltFired(player: Int)
    case boltLanded(at: Vec2)
    /// A strike from the top of the screen down to `bottom`, at `x`.
    case boltStruck(player: Int, x: Double, bottom: Double)
    case frozen(player: Int)
    case ballFrozen
    case cloneMade(player: Int, at: Vec2)
    case cloneShattered(at: Vec2)
    case flameLeft(player: Int, at: Vec2)
    case fireballMade(player: Int)
    case fireballBurst(at: Vec2)
    case pulsed(player: Int, pull: Bool)
    /// Pushed or pulled by a pulse, not stunned: `ball` when the ball left the hands with it.
    case pushed(player: Int, by: Int, ball: Bool)
}

/// What a player's step asks the match to do with the ball.
public enum PlayerAction: Equatable {
    case releaseShot(velocity: Vec2)
    case releaseThrow(velocity: Vec2)
    case dunk(hoop: Int)
    case webLine(direction: Vec2)
    case warpToBall
    case flash(direction: Vec2)
    case makePlatform
    case makeWall
    case quake
    case fireBolt(direction: Vec2)
    case strikeBolt(x: Double, bottom: Double)
    case leaveClone
    case leaveFlame
    case releaseFireball(velocity: Vec2, straight: Bool)
    case pulse(pull: Bool)
}
