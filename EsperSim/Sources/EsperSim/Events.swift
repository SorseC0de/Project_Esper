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
    /// A dunk on the Hoopfish, which spins it off.
    case hoopfishSpun
    /// A Gale Ale tornado made, and one bursting where it is.
    case galeMade(at: Vec2, snatching: Bool)
    case galeBurst(at: Vec2)
    /// Z Tea's beam fired from here this way, and its burst going off.
    case beamFired(player: Int, from: Vec2, direction: Vec2)
    case zBurst(player: Int, at: Vec2)
    case swatted(player: Int, hit: Bool)
    /// `entry` is the ball's velocity as it went through; `points` what it was worth.
    /// `floater`: the ball went in as a floater, for the announcer.
    case scored(player: Int, hoop: Int, entry: Vec2, points: Int, floater: Bool)
    /// `speed`: how fast it met the surface, across it.
    case ballBounced(position: Vec2, speed: Double)
    /// A body or a ball came down on a rim's top and bounced off it; how fast it came.
    case rimBounced(hoop: Int, speed: Double)
    case ballRespawned
    case helmetSpawned(at: Vec2, owner: Int)
    /// Gone at the far wall.
    case helmetRemoved(at: Vec2, owner: Int)
    case helmetsCollided(at: Vec2, owner: Int)
    case portalOpened(at: Vec2)
    case portalClosed(at: Vec2)
    case portalWarped(from: Vec2, to: Vec2)
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
    /// The blade met a wall on its first live frame.
    case slashClanked(player: Int)
    /// The snatch's hand is at full stretch.
    case snatchReached(player: Int)
    /// FLO earned, this much, from a play there: the rim of a basket, a counter, a snatch, a
    /// pop, a taunt's ball on the floor.
    case floGained(player: Int, amount: Int, at: Vec2)
    /// The ball knocked out of `player`'s hands by `by`.
    case popped(player: Int, by: Int)
    case ledgeGrabbed(player: Int)
    /// A body struck without the ball: stunned, and knocked if `knocked`.
    case struck(player: Int, by: Int)
    /// A snatch met a live blade: the slasher is the one stripped.
    case parried(player: Int, by: Int)
    /// Someone's feet went into the lava and they went back to their start.
    case lavaBurned(player: Int)
    /// Something fell into the lava here: a body, or the ball.
    case lavaSplashed(at: Vec2, ball: Bool)
    /// Burned by a fire tornado, here.
    case tornadoBurned(at: Vec2)
    /// The Elements' sky flashed: lightning will strike `at` when the warning's out.
    case lightningFlashed(at: Vec2)
    /// The Elements' lightning struck here, on the top of rock.
    case lightningStruck(at: Vec2)
    /// An Elements icicle shattered here, its tip.
    case icicleShattered(at: Vec2)
    /// The Elements' fireball burst here.
    case stageFireballBurst(at: Vec2)
    /// A stance's stepback began.
    case steppedBack(player: Int)
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
    case fireballThrown(player: Int)
    case fireballBurst(at: Vec2)
    case pulsed(player: Int, pull: Bool)
    case sniped(player: Int, at: Vec2, pull: Bool)
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
    /// Gale Ale: a still tornado where the double jump left from; at level two the snatch's, sent off.
    case makeGale
    /// Z Tea: the beam leaves, and the burst goes off.
    case fireBeam
    case zBurst
    case sendGale(at: Vec2, heading: Facing)
    case leaveFlame
    case releaseFireball(velocity: Vec2, straight: Bool, ballArc: Bool)
    case pulse(pull: Bool)
    /// The snipe's shot at `at`: a repulsion, or with `pull` an attraction.
    case snipe(at: Vec2, pull: Bool)
}
