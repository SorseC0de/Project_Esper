import Foundation

/// The ball. Held, it rides the holder's chest; loose, it flies, bounces and rolls.
public struct Ball: Equatable {
    public var position: Vec2
    public var velocity: Vec2 = .zero
    public var holder: Int?
    /// A thrown ball flies straight until it first hits something.
    public var straight = false
    /// Released by a throw and not yet caught: the rims don't pull it, so scoring off a
    /// throw is the ball going through on its own.
    public var thrown = false
    /// Who released or swatted it last.
    public var lastTouched: Int?
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
        var scoredHoop: Int?

        for hoop in stage.hoops where !thrown && velocity.y < 0 && position.y > hoop.position.y {
            steer(toward: hoop)
        }

        if !straight {
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

        for (index, hoop) in stage.hoops.enumerated()
        where previousY >= hoop.position.y && position.y < hoop.position.y && abs(position.x - hoop.position.x) <= BallRules.rimHalfWidth {
            scoredHoop = index
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
        velocity.x = abs(velocity.x) > 0.3 ? -velocity.x * BallRules.bounce : 0
        events.append(.ballBounced(position: position))
    }

    private mutating func bounceY(events: inout [MatchEvent]) {
        straight = false
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
        thrown = straight
        lastTouched = player
        resting = false
    }

    public mutating func respawn(at spawn: Vec2) {
        position = spawn
        previousY = spawn.y
        velocity = .zero
        holder = nil
        straight = false
        thrown = false
        lastTouched = nil
        resting = false
        respawnTimer = 0
    }
}
