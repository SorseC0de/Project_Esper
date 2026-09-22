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
    /// Released by a throw and not yet caught.
    public var thrown = false
    /// Whether the rims still steer it: a shot's or a floater's until its first bounce off
    /// anything. A thrown ball never steers, so scoring off a throw is the ball going
    /// through on its own.
    public var steers = false
    /// The hoop it last rose up through; its next fall through that hoop isn't a score.
    public var roseThrough: Int?
    /// Who released or swatted it last.
    public var lastTouched: Int?
    /// Reeled in by a web: the player pulling it.
    public var tether: Int?
    /// Frames the ball still counts as `lastTouched`'s, after a release.
    public var ownedFrames = 0

    /// Whose the ball still is, if anyone's.
    public var owner: Int? { ownedFrames > 0 ? lastTouched : nil }
    public var resting = false
    /// Counting down to the respawn after a score, 0 when live.
    public var respawnTimer = 0
    private var previousY: Double

    public init(position: Vec2) {
        self.position = position
        previousY = position.y
    }

    public var box: Box { Box(center: position, width: BallRules.radius * 2, height: BallRules.radius * 2) }

    public var isLive: Bool { holder == nil && respawnTimer == 0 }

    /// Moves the loose ball one frame. Returns the hoop it fell through, if any.
    public mutating func step(stage: Stage, bodies: [Box], events: inout [MatchEvent]) -> Int? {
        previousY = position.y
        if ownedFrames > 0 { ownedFrames -= 1 }
        var scoredHoop: Int?

        for hoop in stage.hoops where steers && velocity.y < 0 && position.y > hoop.position.y {
            steer(toward: hoop)
        }

        if floater > 0 {
            floater -= 1
        } else if !straight {
            velocity.y = max(velocity.y - BallRules.gravity, -BallRules.fallSpeed)
        }

        let sweptX = stage.sweepHorizontally(box, by: velocity.x)
        position.x += sweptX.moved
        if sweptX.blocked != nil {
            bounceX(events: &events)
        }
        let sweptY = stage.sweepVertically(box, by: velocity.y)
        position.y += sweptY.moved
        if sweptY.landed || sweptY.ceiling {
            bounceY(events: &events)
        }
        for body in bodies {
            deflect(off: body, events: &events)
        }

        // Down through a rim scores, unless it rose up through that rim first.
        for (index, hoop) in stage.hoops.enumerated() where abs(position.x - hoop.position.x) <= BallRules.rimHalfWidth {
            if previousY >= hoop.position.y, position.y < hoop.position.y {
                if roseThrough == index {
                    roseThrough = nil
                } else {
                    scoredHoop = index
                }
            } else if previousY < hoop.position.y, position.y >= hoop.position.y {
                roseThrough = index
            }
        }

        let onFloor = stage.isGrounded(box)
        if onFloor, velocity.y == 0 {
            velocity.x *= BallRules.rollingFriction
            if abs(velocity.x) < BallRules.restSpeed { velocity.x = 0 }
        }
        resting = onFloor && velocity == .zero
        return scoredHoop
    }

    /// Bends a falling ball's path so it arrives over the rim: the sideways speed it would
    /// need to reach the rim's centre in the time it will take to fall to the rim's height,
    /// approached a share at a time.
    private mutating func steer(toward hoop: Hoop) {
        let across = hoop.position.x - position.x
        let above = position.y - hoop.position.y
        guard abs(across) <= BallRules.hoopReach, above <= BallRules.hoopReach else { return }
        let down = -velocity.y
        let g = BallRules.gravity
        let frames = (-down + (down * down + 2 * g * above).squareRoot()) / g
        guard frames > 0 else { return }
        let needed = across / frames
        let change = (needed - velocity.x) * BallRules.hoopSteerShare
        velocity.x += min(max(change, -BallRules.hoopSteerMax), BallRules.hoopSteerMax)
    }

    private mutating func bounceX(events: inout [MatchEvent]) {
        straight = false
        floater = 0
        steers = false
        velocity.x = abs(velocity.x) > 0.3 ? -velocity.x * BallRules.bounce : 0
        events.append(.ballBounced(position: position))
    }

    private mutating func bounceY(events: inout [MatchEvent]) {
        straight = false
        floater = 0
        steers = false
        let rebound = -velocity.y * BallRules.bounce
        velocity.y = abs(rebound) > 0.6 ? rebound : 0
        events.append(.ballBounced(position: position))
    }

    /// Pushes out of a body along the shallow axis and reflects that part of the velocity.
    private mutating func deflect(off body: Box, events: inout [MatchEvent]) {
        let mine = box
        guard mine.overlaps(body) else { return }
        let pushLeft = mine.max.x - body.min.x
        let pushRight = body.max.x - mine.min.x
        let pushDown = mine.max.y - body.min.y
        let pushUp = body.max.y - mine.min.y
        let smallest = min(pushLeft, pushRight, pushDown, pushUp)
        if smallest == pushLeft {
            position.x -= pushLeft
            if velocity.x > 0 { bounceX(events: &events) }
        } else if smallest == pushRight {
            position.x += pushRight
            if velocity.x < 0 { bounceX(events: &events) }
        } else if smallest == pushDown {
            position.y -= pushDown
            if velocity.y > 0 { bounceY(events: &events) }
        } else {
            position.y += pushUp
            if velocity.y < 0 { bounceY(events: &events) }
        }
    }

    public mutating func release(from position: Vec2, velocity: Vec2, by player: Int, straight: Bool) {
        holder = nil
        self.position = position
        previousY = position.y
        self.velocity = velocity
        self.straight = straight
        floater = 0
        thrown = straight
        steers = !straight
        roseThrough = nil
        lastTouched = player
        ownedFrames = BallRules.ownedFrames
        resting = false
    }

    /// The floater: a soft drift up that ignores gravity for a while, carrying the
    /// thrower's sideways speed, then a normal fall the rims steer.
    public mutating func releaseFloater(from position: Vec2, sideways: Double, by player: Int) {
        release(from: position, velocity: Vec2(x: sideways, y: BallRules.floaterSpeed), by: player, straight: false)
        thrown = true
        floater = BallRules.floaterFrames
    }

    /// Knocked out of a holder's hands: a short floater straight up, then a normal fall,
    /// nobody's to warp to.
    public mutating func pop(from position: Vec2) {
        holder = nil
        self.position = position
        previousY = position.y
        velocity = Vec2(x: 0, y: BallRules.floaterSpeed)
        straight = false
        floater = BallRules.popFloatFrames
        thrown = false
        steers = false
        roseThrough = nil
        tether = nil
        lastTouched = nil
        ownedFrames = 0
        resting = false
    }

    /// Swatted: sent the way the swatter faces and a little up, at its own speed or the
    /// swat speed, whichever is more.
    public mutating func swat(toward facing: Facing, by player: Int) {
        velocity = Vec2(x: facing.sign * 2, y: 1).normalized * max(velocity.length, SlashRules.swatSpeed)
        straight = false
        floater = 0
        steers = false
        lastTouched = player
    }

    public mutating func respawn(at spawn: Vec2) {
        position = spawn
        previousY = spawn.y
        velocity = .zero
        holder = nil
        straight = false
        floater = 0
        thrown = false
        steers = false
        roseThrough = nil
        tether = nil
        lastTouched = nil
        ownedFrames = 0
        resting = false
        respawnTimer = 0
    }
}
