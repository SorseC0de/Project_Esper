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
    case swatted(player: Int, hit: Bool)
    /// `entry` is the ball's velocity as it went through; `points` what it was worth.
    /// `floater`: the ball went in as a floater, for the announcer; `dunk`: put down by a dunk.
    case scored(player: Int, hoop: Int, entry: Vec2, points: Int, floater: Bool, dunk: Bool)
    /// `speed`: how fast it met the surface, across it.
    case ballBounced(position: Vec2, speed: Double)
    /// A body or a ball came down on a rim's top and bounced off it; how fast it came.
    case rimBounced(hoop: Int, speed: Double, ball: Bool)
    /// A body or the ball off a spring's top (the jellyfish's), where.
    case springBounced(at: Vec2, speed: Double, ball: Bool)
    case ballRespawned
    case helmetSpawned(at: Vec2, owner: Int)
    /// Gone at the far wall.
    case helmetRemoved(at: Vec2, owner: Int)
    case helmetsCollided(at: Vec2, owner: Int)
    case portalOpened(at: Vec2)
    case portalClosed(at: Vec2)
    case portalWarped(from: Vec2, to: Vec2)
    /// A player without the ball through the portal, their feet from and to.
    case portalCarried(player: Int, from: Vec2, to: Vec2)
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
    /// A slab or a wall broken, or replaced by its maker's next: its box, for the cubes it breaks into.
    case platformShattered(player: Int, box: Box)
    /// Phantom Frappe: a body into its phantom form, or back out of it.
    case phantomToggled(player: Int, phantom: Bool)
    /// Pulsepistol Punch's repulsion turning something fired back on its firer, where.
    case pulseReflected(player: Int, at: Vec2)
    /// Breaker Ball: `player`'s barrier, their posture, worn down this much, where they were hit; at 0
    /// it shatters, as it does when they're stunned, their rim appears over them, and it's restored
    /// once they're scored on or the stun ends.
    case barrierHit(player: Int, at: Vec2, damage: Double)
    case barrierShattered(player: Int, at: Vec2)
    case barrierRestored(player: Int)
    /// Breaker Ball: `player`'s rim appearing over them as their barrier shatters.
    case breakerHoopAppeared(player: Int, hoop: Int)
    /// Breaker Ball: `player` scored on, held still a moment.
    case scoredOnFreeze(player: Int)
    /// Breaker Ball's Breaker Balls: one summoned into `player`'s hands; one taken out of the air by a
    /// snatch, `from` its thrower (hit for it) if anyone's; one bursting where it met something.
    case breakerBallSummoned(player: Int)
    case breakerBallCaught(player: Int, from: Int?)
    case breakerBallBurst(at: Vec2, colour: Int)
    /// A basket through `player`'s own rim mending their barrier this much.
    case barrierHealed(player: Int, amount: Double)
    /// Breaker Ball's snatch: `player`'s rim left where it is, or taken back with a touch.
    case hoopParked(player: Int, parked: Bool)
    case slid(player: Int)
    case slashed(player: Int)
    /// The blade met a wall on its first live frame.
    case slashClanked(player: Int)
    /// Both blades met each other: a slashclash, where they met.
    case slashClashed(at: Vec2)
    /// Two snatches' reaches meeting.
    case snatchClashed(at: Vec2)
    /// The snatch's hand is at full stretch.
    case snatchReached(player: Int)
    /// FLO earned, this much, from a play there: the rim of a basket, a counter, a snatch, a
    /// pop, a taunt's ball on the floor.
    case floGained(player: Int, amount: Int, at: Vec2)
    /// The change into FloState's burst went off: the body is becoming energy.
    case transformed(player: Int)
    /// The ball knocked out of `player`'s hands by `by`.
    case popped(player: Int, by: Int)
    /// The ball spilled out of `player`'s hands onto a road (`RoadRules`).
    case roadSpilled(player: Int)
    /// A vehicle, or someone sliding on a road, went over a pothole there (Anozira's).
    case potholeBump(at: Vec2)
    /// The ball taken out of `from`'s hands by `player`'s snatch: a steal, for the announcer.
    case stolen(player: Int, from: Int)
    /// Flight B411's cart rolled into a body, where it was.
    case cartHit(player: Int, at: Vec2)
    /// Flight B411's cart sent rolling by a slash.
    case cartSlashed(player: Int)
    case ledgeGrabbed(player: Int)
    /// A body struck without the ball: stunned, and knocked if `knocked`.
    case struck(player: Int, by: Int)
    /// A snatch met a live blade: the slasher is the one stripped.
    case parried(player: Int, by: Int)
    /// `player` countered by `by`: a parry, a snatch on a shield, a throw into one, a slash on a snatch.
    case countered(player: Int, by: Int, at: Vec2)
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
    /// A fireball in flight snatched or caught, held now as if made.
    case fireballTaken(player: Int)
    case fireballThrown(player: Int)
    case fireballBurst(at: Vec2)
    case pulsed(player: Int, pull: Bool)
    case sniped(player: Int, at: Vec2, pull: Bool)
    /// Pushed or pulled by a pulse, not stunned: `ball` when the ball left the hands with it.
    case pushed(player: Int, by: Int, ball: Bool)
    /// Shielding (`Shield.swift`): one raised, one broken, the ball off one, and a perfect one.
    case shieldRaised(player: Int, at: Vec2)
    case blastFired(player: Int, hand: Int)
    case blastBurst(at: Vec2)
    /// The Spin Move, with the FLO for its phasing or without.
    case spun(player: Int, phasing: Bool)
    /// The Spin Move asked for again in the same airtime: nothing happens (its "can't" sound to come).
    case spinRefused(player: Int)
    case shieldBroken(player: Int, at: Vec2)
    case shieldReflected(player: Int, at: Vec2)
    case shieldPerfect(player: Int, at: Vec2)
    /// A thrown power stopped on `player`'s shield, not turned back.
    case powerBlocked(player: Int, at: Vec2)
    /// Two shields raised into each other, as they were when they met.
    case shieldClashed(at: Vec2, first: Shield, second: Shield)
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
    /// The change into FloState's burst: pushes away as Z Tea's does, and parries.
    case floBurst
    case sendGale(at: Vec2, heading: Facing)
    case leaveFlame
    case releaseFireball(velocity: Vec2, straight: Bool, ballArc: Bool)
    case pulse(pull: Bool)
    /// The snipe's shot at `at`: a repulsion, or with `pull` an attraction.
    case snipe(at: Vec2, pull: Bool)
    /// The snatch with the stick held a way: a shield at the hand.
    case raiseShield
    /// Z Tea's blast, off this hand (0 or 1, by turns through a run of them).
    case zBlast(direction: Vec2, hand: Int)
    /// The Spin Move under way: its foot, where it is, kicks off a body it touches.
    case spin
    /// A down throw with the Spin Move already spent this airtime: nothing, for its sound.
    case spinRefused
}
