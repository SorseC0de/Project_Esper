import Foundation

/// The ball. Held, it rides the holder's chest; loose, it flies, bounces and rolls.
public struct Ball: Equatable {
    public var position: Vec2
    public var velocity: Vec2 = .zero
    public var holder: Int?
    /// A thrown ball flies straight until it first hits something.
    public var straight = false
    /// Frames of floater left: drifting up with gravity off.
    public var floater = 0
    /// Let go as a floater, until it's next let go or knocked: for the view's announcer.
    public var floaterShot = false
    /// Put down through the rim by a dunk that counts, until it's next let go or knocked: a
    /// dunk's point, for its sound and the announcer. Only a dunk that lands sets it, so one that
    /// doesn't (the Hoopfish's spin, Anozira's bounce) leaves nothing behind.
    public var dunkShot = false
    /// Released by a throw and not yet caught.
    public var thrown = false
    /// A throw sideways or down is a projectile: the other body it meets is stripped and
    /// knocked as by the slash, and it comes back off them, `returning`, for the thrower
    /// to catch at any speed.
    public var strikes = false
    public var returning = false
    /// Whether the rims still steer it: a shot's or a floater's until its first bounce off
    /// anything but a backboard's glass, which it can bank off and still be drawn in. A thrown ball never steers, so scoring off a throw is the ball going
    /// through on its own.
    public var steers = false
    /// A shot still in flight, before its first bounce: the rings don't take it; only a
    /// snatch does. Bodies never deflect the ball; it goes through anyone not catching it.
    public var shotInFlight = false
    /// Let go as a shot, a floater or a dunk, and kept through its bounces: it can go down
    /// through a rim. Anything else, thrown or knocked loose, bounces off the rim's top.
    public var scoring = false
    /// Who released or swatted it last.
    public var lastTouched: Int?
    /// Counts every time it leaves a hand, is knocked or respawns: a flight's number, for what
    /// turns it once a flight (a shield).
    public var flight = 0
    /// Reeled in by a web: the player pulling it.
    public var tether: Int?
    /// Whether the ball still counts as `lastTouched`'s: from a release until its first
    /// bounce off anything.
    public var owned = false
    /// Exclusion (`ExclusionRules`): only this player's to take, by hand or snatch, and nobody's
    /// to slash, for `exclusionFrames` more frames loose.
    public var exclusiveTo: Int?
    /// Whether `player` may touch it at all, by hand or by anything they do: under Exclusion, only
    /// the one it's exclusive to; phantom, only a phantom, and solid, only the solid.
    public func isOpen(to player: Int) -> Bool {
        (exclusiveTo == nil || exclusiveTo == player) && phantom == ((phantomPlayers >> player) & 1 == 1)
    }
    /// Phantom Frappe's: let go by a phantom, passing through the walls and the rims (`PhantomFrappe.swift`).
    public var phantom = false
    /// Which players are phantom, a bit each, kept by the match.
    public var phantomPlayers = 0
    public var exclusionFrames = 0
    /// Drawn out of a tornado by a rim: no tornado takes it back till a hand or a release does.
    public var drawnFromTornado = false
    /// How many times faster than an ordinary ball a shot runs its arc, Cannon Cola's
    /// doing: the velocity is this much more and gravity this much squared, so the path is
    /// the same. It's an ordinary ball again from its first bounce.
    public var pace = 1.0

    /// Whose the ball still is, if anyone's.
    public var owner: Int? { owned ? lastTouched : nil }
    /// Frost Tea: held exactly where it is for this many frames more.
    public var frozen = 0
    /// A throw's charge (`ThrowChargeRules`), 0 to 1; at full, nobody but the thrower takes it till it bounces.
    public var throwCharge = 0.0
    public var unstoppable: Bool { thrown && owned && throwCharge >= 1 }
    /// Blazing Boba: alight from a shot or a throw until the first bounce; nobody but the
    /// thrower can catch or snatch it.
    public var burning = false
    /// The middle of the tornado holding it, if one is.
    public var tornadoCentre: Vec2?
    /// Loose and in no tornado last frame, so one can take it.
    public var outsideTornados = false
    public var resting = false
    /// Counting down to the respawn after a score, 0 when live.
    public var respawnTimer = 0
    /// Where it last left a hand, or was knocked or swatted from: 47's three-point line
    /// reads it.
    public var launchPoint: Vec2?
    var previousY: Double
    /// The rim a scoring ball came down into from above, its bottom through: the point is scored
    /// once its middle is through too, so the basket counts as the ball sits in the net, not as
    /// it touches the rim. Out of it sideways or back up, it's lost.
    var enteringHoop: Int?
    /// A made basket going down the net: drawn to the rim's middle, its sideways speed kept aside
    /// and given back once it's out of the net's bottom, or out of the rim, to bounce on with.
    var throughNet: NetDrop?
    struct NetDrop: Equatable {
        var hoop: Int
        var carriedX: Double
    }
    /// What it came into the rim with, for the net's swish: its kept sideways speed while it's in the net.
    public var entryVelocity: Vec2 { throughNet.map { Vec2(x: $0.carriedX, y: velocity.y) } ?? velocity }

    public init(position: Vec2) {
        self.position = position
        previousY = position.y
        enteringHoop = nil
        throughNet = nil
    }

    /// Under water the ball falls at half the pull, no faster than half the speed, and rolls to a
    /// stop at half the drag: every change of its speed at half.
    static func gravityShare(_ stage: Stage) -> Double { stage.features.underwater ? 0.5 : 1 }

    public var box: Box { Box(center: position, width: BallRules.radius * 2, height: BallRules.radius * 2) }

    public var isLive: Bool { holder == nil && respawnTimer == 0 }

    /// Moves the loose ball one frame. Returns the hoop it fell through, if any.
    public mutating func step(stage: Stage, events: inout [MatchEvent]) -> Int? {
        previousY = position.y
        var scoredHoop: Int?
        if exclusiveTo != nil {
            exclusionFrames -= 1
            if exclusionFrames <= 0 { exclusiveTo = nil }
        }

        // Only the rim it's meant for pulls it in: the one whoever last touched it scores on. An
        // own basket can still drop, but nothing draws it there; but in Breaker Ball, where an own
        // basket mends, your own rim pulls too, and the other's only once its barrier's down.
        for hoop in stage.hoops where steers && velocity.y < 0 && position.y > hoop.position.y && !hoop.rimless
            && (hoop.barrier == nil ? hoop.shared || lastTouched == nil || hoop.owner == lastTouched
                : lastTouched == nil || hoop.owner != lastTouched || !hoop.barrierStanding) {
            steer(toward: hoop, gravityShare: Ball.gravityShare(stage))
        }

        if let centre = tornadoCentre {
            // Held in a tornado: drawn to its middle, gravity off. Carried over a rim it scores
            // on, the rim draws it out and down into it, a shot again.
            velocity = (centre - position) * TornadoRules.pullShare
            if let hoop = stage.hoops.first(where: { !$0.rimless && !$0.bonus && ($0.shared || lastTouched == nil || $0.owner == lastTouched)
                && abs($0.position.x - position.x) <= BallRules.hoopReach && position.y > $0.position.y && position.y - $0.position.y <= BallRules.hoopReach }) {
                tornadoCentre = nil
                drawnFromTornado = true
                steers = true
                scoring = true
                velocity = Vec2(x: 0, y: -0.5)
                steer(toward: hoop, gravityShare: Ball.gravityShare(stage))
            }
        } else if floater > 0 {
            floater -= 1
        } else if !straight {
            // On a pitched stage gravity leans: a share of it sideways.
            velocity.y = max(velocity.y - BallRules.gravity * Ball.gravityShare(stage) * pace * pace * stage.tiltDown, -BallRules.fallSpeed * Ball.gravityShare(stage) * pace)
            velocity.x -= BallRules.gravity * Ball.gravityShare(stage) * pace * pace * stage.tiltPull
        }

        // The way it came in, for a slope to turn: a block's flat top under the slope may
        // already have bounced it straight.
        let incoming = velocity
        let sweptX = stage.sweepHorizontally(box, by: velocity.x)
        position.x += sweptX.moved
        if sweptX.blocked != nil {
            bounceX(events: &events, offGlass: stage.backboard(at: position) != nil)
        }
        // Slopes are left out of the fall: they turn the ball off their diagonal below,
        // rather than stopping it flat.
        var flat = stage
        flat.slopes = []
        let sweptY = flat.sweepVertically(box, by: velocity.y)
        position.y += sweptY.moved
        if sweptY.landed || sweptY.ceiling {
            bounceY(events: &events, offGlass: stage.backboard(at: position) != nil)
        }

        // Down through a rim scores, whatever it did before: a floater that rose up through
        // it from under counts once it falls back in. Going up through one never does. The
        // ball's bottom has to come down through it, so all of it was above the rim: one
        // thrown flat at the rim's height, off the backboard, drops out under it.
        for (index, hoop) in stage.hoops.enumerated() where abs(position.x - hoop.position.x) <= BallRules.rimHalfWidth && !hoop.rimless {
            if previousY - BallRules.radius >= hoop.position.y, position.y - BallRules.radius < hoop.position.y {
                if scoring {
                    enteringHoop = index
                    if throughNet == nil { throughNet = NetDrop(hoop: index, carriedX: velocity.x) }
                } else if stage.features.rimBounce {
                    events.append(.rimBounced(hoop: index, speed: abs(velocity.y), ball: true))
                    position.y = hoop.position.y + BallRules.radius
                    bounceY(events: &events)
                    // Off the ring rather than settling on it: kicked out the way it's off the
                    // ring's middle (dead on, away from the board), and never slower across than a roll off.
                    let off = position.x - hoop.position.x
                    let out = abs(off) > 0.01 ? (off > 0 ? 1.0 : -1.0) : -hoop.backboard.sign
                    velocity.x += out * BallRules.rimKick
                    if abs(velocity.x) < BallRules.rimRollOffSpeed { velocity.x = out * BallRules.rimRollOffSpeed }
                }
            }
        }

        // Down onto a spring's top (the jellyfish's bell): off it, as off a floor.
        for spring in stage.springs where position.x >= spring.left && position.x <= spring.right
            && previousY - BallRules.radius >= spring.y && position.y - BallRules.radius < spring.y {
            events.append(.springBounced(at: Vec2(x: position.x, y: spring.y), speed: abs(velocity.y), ball: true))
            position.y = spring.y + BallRules.radius
            bounceY(events: &events)
        }

        // In the rim it came down into: scored as its middle goes through, or lost if it leaves.
        if let entering = enteringHoop, stage.hoops.indices.contains(entering) {
            let hoop = stage.hoops[entering]
            if position.y < hoop.position.y {
                scoredHoop = entering
                enteringHoop = nil
                // Through: at the rim's middle as the point is held, the slide done.
                if throughNet != nil {
                    position.x = hoop.position.x
                    velocity.x = 0
                }
            } else if velocity.y > 0 || abs(position.x - hoop.position.x) > BallRules.rimHalfWidth + BallRules.radius {
                enteringHoop = nil
                leaveNet()
            }
        } else {
            enteringHoop = nil
        }
        // Down the net: drawn to the rim's middle, till it's out of the bottom or going back up.
        if let through = throughNet, stage.hoops.indices.contains(through.hoop) {
            let hoop = stage.hoops[through.hoop]
            if position.y < hoop.position.y - BallRules.netDepth || velocity.y > 0 {
                leaveNet()
            } else {
                position.x += (hoop.position.x - position.x) * BallRules.netCentring
                velocity.x = 0
            }
        } else {
            throughNet = nil
        }

        rollOffSlopes(stage, incoming: incoming, events: &events)

        let onFloor = stage.isGrounded(box)
        // Held up at a slope's foot, on the corner of the block under the slope above, it's
        // tipped on down the slope under its middle rather than parked there.
        if onFloor, velocity.y == 0, let slope = stage.slopes.first(where: {
            $0.box.min.x <= position.x && position.x <= $0.box.max.x && abs($0.surface(at: position.x) - (position.y - BallRules.radius)) <= BallRules.radius
        }) {
            velocity.x += slope.downhill.sign * BallRules.gravity * Ball.gravityShare(stage) * SlopeRules.diagonal
        } else if onFloor, velocity.y == 0 {
            let share = Ball.gravityShare(stage)
            // On a pitched stage it rolls downhill.
            velocity.x -= BallRules.gravity * share * stage.tiltPull
            let slowed = abs(velocity.x) * (1 - BallRules.rollingFriction * share) - BallRules.rollingDrag * share
            velocity.x = slowed > 0 ? (velocity.x < 0 ? -slowed : slowed) : 0
        }
        resting = onFloor && velocity == .zero
        return scoredHoop
    }

    /// Out of the net: its sideways speed back, to go on with.
    private mutating func leaveNet() {
        if let through = throughNet { velocity.x = through.carriedX }
        throughNet = nil
    }

    /// Bends a falling ball's path so it arrives over the rim: the sideways speed it would
    /// need to reach the rim's centre in the time it will take to fall to the rim's height,
    /// approached a share at a time. A swimming rim is led: aimed at where it will be by then,
    /// not where it is, as the computer's own aim already does.
    private mutating func steer(toward hoop: Hoop, gravityShare: Double) {
        guard abs(hoop.position.x - position.x) <= BallRules.hoopReach, position.y - hoop.position.y <= BallRules.hoopReach else { return }
        let down = -velocity.y
        let g = BallRules.gravity * gravityShare * pace * pace
        func framesToFall(to rimY: Double) -> Double {
            let above = position.y - rimY
            return (-down + (down * down + 2 * g * max(above, 0)).squareRoot()) / g
        }
        var frames = framesToFall(to: hoop.position.y)
        // Twice round: where the rim will be when the ball falls to it, and the fall to there.
        for _ in 0..<2 where hoop.velocity != .zero {
            frames = framesToFall(to: hoop.position.y + hoop.velocity.y * frames)
        }
        guard frames > 0 else { return }
        let across = hoop.position.x + hoop.velocity.x * frames - position.x
        let needed = across / frames
        let change = (needed - velocity.x) * BallRules.hoopSteerShare
        let most = BallRules.hoopSteerMax * pace
        velocity.x += min(max(change, -most), most)
    }

    /// Under a slope's surface, the ball is set back on it and bounces off the diagonal:
    /// the push into it turned back, a share kept, the run along it kept whole, so gravity
    /// rolls it down.
    private mutating func rollOffSlopes(_ stage: Stage, incoming: Vec2, events: inout [MatchEvent]) {
        for slope in stage.slopes where slope.box.min.x <= position.x && position.x <= slope.box.max.x {
            let surface = slope.surface(at: position.x)
            guard position.y - BallRules.radius < surface - Stage.edge, position.y > slope.box.min.y - BallRules.radius else { continue }
            // A one-way slope turns only a ball that was at its base or above: come down onto it, or rolled on from its foot.
            if slope.oneWay, previousY - BallRules.radius < slope.box.min.y - Stage.edge { continue }
            position.y = surface + BallRules.radius
            let normal = slope.rising ? Vec2(x: -SlopeRules.diagonal, y: SlopeRules.diagonal) : Vec2(x: SlopeRules.diagonal, y: SlopeRules.diagonal)
            // Resting on it, gravity alone still pushes in: that push is what rolls it down.
            let arriving = Vec2(x: incoming.x, y: min(incoming.y, -BallRules.gravity))
            let into = arriving.x * normal.x + arriving.y * normal.y
            if into < 0 {
                velocity = arriving - normal * (into * (1 + BallRules.bounce))
                settlePace()
                straight = false
            }
        }
    }

    /// The first bounce ends a paced shot: an ordinary ball's speed from here.
    private mutating func settlePace() {
        burning = false
        owned = false
        strikes = false
        returning = false
        guard pace != 1 else { return }
        velocity = velocity / pace
        pace = 1
    }

    /// Taken and held by a tornado or a gale: its shot or throw over, as a bounce ends one, so
    /// anyone may catch it.
    mutating func endFlight() {
        settlePace()
        straight = false
        floater = 0
        steers = false
        shotInFlight = false
    }

    /// A bounce ends a shot's flight and the rims' pull on it; off a backboard's glass (`offGlass`)
    /// the pull stays, so a shot kissed off the glass can still be drawn in.
    private mutating func bounceX(events: inout [MatchEvent], offGlass: Bool = false) {
        settlePace()
        straight = false
        floater = 0
        if !offGlass { steers = false }
        shotInFlight = false
        let speed = abs(velocity.x)
        velocity.x = abs(velocity.x) > 0.3 ? -velocity.x * BallRules.bounce : 0
        events.append(.ballBounced(position: position, speed: speed))
    }

    private mutating func bounceY(events: inout [MatchEvent], offGlass: Bool = false) {
        settlePace()
        straight = false
        floater = 0
        if !offGlass { steers = false }
        shotInFlight = false
        let speed = abs(velocity.y)
        let rebound = -velocity.y * BallRules.bounce
        velocity.y = abs(rebound) > 0.6 ? rebound : 0
        events.append(.ballBounced(position: position, speed: speed))
    }

    public mutating func release(from position: Vec2, velocity: Vec2, by player: Int, straight: Bool, pace: Double = 1) {
        flight &+= 1
        holder = nil
        self.position = position
        previousY = position.y
        enteringHoop = nil
        throughNet = nil
        self.velocity = velocity
        self.pace = pace
        self.straight = straight
        strikes = false
        returning = false
        floater = 0
        floaterShot = false
        dunkShot = false
        scoring = false
        thrown = straight
        throwCharge = 0
        steers = !straight
        shotInFlight = false
        lastTouched = player
        launchPoint = position
        owned = true
        exclusiveTo = nil
        drawnFromTornado = false
        resting = false
    }

    /// The floater: a soft drift up that ignores gravity for a while, carrying the
    /// thrower's sideways speed, then a normal fall the rims steer.
    public mutating func releaseFloater(from position: Vec2, sideways: Double, by player: Int) {
        release(from: position, velocity: Vec2(x: sideways, y: BallRules.upThrowSpeed), by: player, straight: false)
        thrown = true
        floater = BallRules.floaterFrames
        floaterShot = true
        scoring = true
    }

    /// Knocked out of a holder's hands: a short floater straight up, then a normal fall,
    /// nobody's to warp to.
    /// Off a shield's face, its way across that face turned back, as off a wall but losing
    /// nothing; nobody's shot any more.
    public mutating func reflect(off normal: Vec2) {
        leaveShieldAsLoose()
        velocity = velocity - normal * (2 * velocity.dot(normal))
    }

    /// Off a shield: sent along its face, as fast as it came or the flick's speed, whichever is more.
    public mutating func flick(along direction: Vec2, speed: Double) {
        let going = max(velocity.length, speed)
        leaveShieldAsLoose()
        velocity = direction.normalized * going
    }

    /// The perfect shield: stopped dead and popped straight up this fast, to be caught.
    public mutating func popOffShield(up speed: Double) {
        leaveShieldAsLoose()
        velocity = Vec2(x: 0, y: speed)
    }

    private mutating func leaveShieldAsLoose() {
        settlePace()
        straight = false
        floater = 0
        steers = false
        shotInFlight = false
        resting = false
    }

    public mutating func pop(from position: Vec2) {
        flight &+= 1
        holder = nil
        launchPoint = position
        self.position = position
        previousY = position.y
        enteringHoop = nil
        throughNet = nil
        velocity = Vec2(x: 0, y: BallRules.floaterSpeed)
        pace = 1
        burning = false
        strikes = false
        returning = false
        straight = false
        floater = BallRules.popFloatFrames
        floaterShot = false
        dunkShot = false
        thrown = false
        steers = false
        shotInFlight = false
        scoring = false
        tether = nil
        lastTouched = nil
        owned = false
        exclusiveTo = nil
        drawnFromTornado = false
        resting = false
    }

    /// Spiked: sent along `direction`, at its own speed or the swat speed, whichever is more.
    public mutating func swat(along direction: Vec2, by player: Int) {
        flight &+= 1
        settlePace()
        velocity = direction.normalized * max(velocity.length, SlashRules.swatSpeed)
        straight = false
        floater = 0
        steers = false
        shotInFlight = false
        scoring = false
        lastTouched = player
        launchPoint = position
    }

    public mutating func respawn(at spawn: Vec2) {
        flight &+= 1
        phantom = false
        launchPoint = nil
        position = spawn
        previousY = spawn.y
        enteringHoop = nil
        throughNet = nil
        velocity = .zero
        pace = 1
        burning = false
        floaterShot = false
        dunkShot = false
        strikes = false
        returning = false
        frozen = 0
        holder = nil
        straight = false
        floater = 0
        thrown = false
        steers = false
        shotInFlight = false
        scoring = false
        tether = nil
        lastTouched = nil
        owned = false
        exclusiveTo = nil
        drawnFromTornado = false
        resting = false
        respawnTimer = 0
        tornadoCentre = nil
    }
}
