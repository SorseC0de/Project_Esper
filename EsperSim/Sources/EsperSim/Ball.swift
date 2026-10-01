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
    /// Released by a throw and not yet caught.
    public var thrown = false
    /// A throw sideways or down is a projectile: the other body it meets is stripped and
    /// knocked as by the slash, and it comes back off them, `returning`, for the thrower
    /// to catch at any speed.
    public var strikes = false
    public var returning = false
    /// Whether the rims still steer it: a shot's or a floater's until its first bounce off
    /// anything. A thrown ball never steers, so scoring off a throw is the ball going
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
    /// Reeled in by a web: the player pulling it.
    public var tether: Int?
    /// Whether the ball still counts as `lastTouched`'s: from a release until its first
    /// bounce off anything.
    public var owned = false
    /// How many times faster than an ordinary ball a shot runs its arc, Cannon Cola's
    /// doing: the velocity is this much more and gravity this much squared, so the path is
    /// the same. It's an ordinary ball again from its first bounce.
    public var pace = 1.0

    /// Whose the ball still is, if anyone's.
    public var owner: Int? { owned ? lastTouched : nil }
    /// Frost Tea: held exactly where it is for this many frames more.
    public var frozen = 0
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

    public init(position: Vec2) {
        self.position = position
        previousY = position.y
    }

    /// Under water the ball falls at half the pull.
    static func gravityShare(_ stage: Stage) -> Double { stage.features.underwater ? 0.5 : 1 }

    public var box: Box { Box(center: position, width: BallRules.radius * 2, height: BallRules.radius * 2) }

    public var isLive: Bool { holder == nil && respawnTimer == 0 }

    /// Moves the loose ball one frame. Returns the hoop it fell through, if any.
    public mutating func step(stage: Stage, events: inout [MatchEvent]) -> Int? {
        previousY = position.y
        var scoredHoop: Int?

        for hoop in stage.hoops where steers && velocity.y < 0 && position.y > hoop.position.y {
            steer(toward: hoop, gravityShare: Ball.gravityShare(stage))
        }

        if let centre = tornadoCentre {
            // Held in a tornado: drawn to its middle, gravity off.
            velocity = (centre - position) * TornadoRules.pullShare
        } else if floater > 0 {
            floater -= 1
        } else if !straight {
            velocity.y = max(velocity.y - BallRules.gravity * Ball.gravityShare(stage) * pace * pace, -BallRules.fallSpeed * pace)
        }

        // The way it came in, for a slope to turn: a block's flat top under the slope may
        // already have bounced it straight.
        let incoming = velocity
        let sweptX = stage.sweepHorizontally(box, by: velocity.x)
        position.x += sweptX.moved
        if sweptX.blocked != nil {
            bounceX(events: &events)
        }
        // Slopes are left out of the fall: they turn the ball off their diagonal below,
        // rather than stopping it flat.
        var flat = stage
        flat.slopes = []
        let sweptY = flat.sweepVertically(box, by: velocity.y)
        position.y += sweptY.moved
        if sweptY.landed || sweptY.ceiling {
            bounceY(events: &events)
        }

        // Down through a rim scores, whatever it did before: a floater that rose up through
        // it from under counts once it falls back in. Going up through one never does. The
        // ball's bottom has to come down through it, so all of it was above the rim: one
        // thrown flat at the rim's height, off the backboard, drops out under it.
        for (index, hoop) in stage.hoops.enumerated() where abs(position.x - hoop.position.x) <= BallRules.rimHalfWidth {
            if previousY - BallRules.radius >= hoop.position.y, position.y - BallRules.radius < hoop.position.y {
                if scoring {
                    scoredHoop = index
                } else {
                    events.append(.rimBounced(hoop: index, speed: abs(velocity.y)))
                    position.y = hoop.position.y + BallRules.radius
                    bounceY(events: &events)
                }
            }
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
            let slowed = abs(velocity.x) * (1 - BallRules.rollingFriction) - BallRules.rollingDrag
            velocity.x = slowed > 0 ? (velocity.x < 0 ? -slowed : slowed) : 0
        }
        resting = onFloor && velocity == .zero
        return scoredHoop
    }

    /// Bends a falling ball's path so it arrives over the rim: the sideways speed it would
    /// need to reach the rim's centre in the time it will take to fall to the rim's height,
    /// approached a share at a time.
    private mutating func steer(toward hoop: Hoop, gravityShare: Double) {
        let across = hoop.position.x - position.x
        let above = position.y - hoop.position.y
        guard abs(across) <= BallRules.hoopReach, above <= BallRules.hoopReach else { return }
        let down = -velocity.y
        let g = BallRules.gravity * gravityShare * pace * pace
        let frames = (-down + (down * down + 2 * g * above).squareRoot()) / g
        guard frames > 0 else { return }
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

    private mutating func bounceX(events: inout [MatchEvent]) {
        settlePace()
        straight = false
        floater = 0
        steers = false
        shotInFlight = false
        let speed = abs(velocity.x)
        velocity.x = abs(velocity.x) > 0.3 ? -velocity.x * BallRules.bounce : 0
        events.append(.ballBounced(position: position, speed: speed))
    }

    private mutating func bounceY(events: inout [MatchEvent]) {
        settlePace()
        straight = false
        floater = 0
        steers = false
        shotInFlight = false
        let speed = abs(velocity.y)
        let rebound = -velocity.y * BallRules.bounce
        velocity.y = abs(rebound) > 0.6 ? rebound : 0
        events.append(.ballBounced(position: position, speed: speed))
    }

    public mutating func release(from position: Vec2, velocity: Vec2, by player: Int, straight: Bool, pace: Double = 1) {
        holder = nil
        self.position = position
        previousY = position.y
        self.velocity = velocity
        self.pace = pace
        self.straight = straight
        strikes = false
        returning = false
        floater = 0
        floaterShot = false
        scoring = false
        thrown = straight
        steers = !straight
        shotInFlight = false
        lastTouched = player
        launchPoint = position
        owned = true
        resting = false
    }

    /// The floater: a soft drift up that ignores gravity for a while, carrying the
    /// thrower's sideways speed, then a normal fall the rims steer.
    public mutating func releaseFloater(from position: Vec2, sideways: Double, by player: Int) {
        release(from: position, velocity: Vec2(x: sideways, y: BallRules.floaterSpeed), by: player, straight: false)
        thrown = true
        floater = BallRules.floaterFrames
        floaterShot = true
        scoring = true
    }

    /// Knocked out of a holder's hands: a short floater straight up, then a normal fall,
    /// nobody's to warp to.
    public mutating func pop(from position: Vec2) {
        holder = nil
        launchPoint = position
        self.position = position
        previousY = position.y
        velocity = Vec2(x: 0, y: BallRules.floaterSpeed)
        pace = 1
        burning = false
        strikes = false
        returning = false
        straight = false
        floater = BallRules.popFloatFrames
        floaterShot = false
        thrown = false
        steers = false
        shotInFlight = false
        scoring = false
        tether = nil
        lastTouched = nil
        owned = false
        resting = false
    }

    /// Spiked: sent along `direction`, at its own speed or the swat speed, whichever is more.
    public mutating func swat(along direction: Vec2, by player: Int) {
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
        launchPoint = nil
        position = spawn
        previousY = spawn.y
        velocity = .zero
        pace = 1
        burning = false
        floaterShot = false
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
        resting = false
        respawnTimer = 0
        tornadoCentre = nil
    }
}
