import Foundation

/// The football field's moving pieces: helmets that sweep the field while someone has the
/// ball, and the portal that carries a shot or throw downfield. Both live in the match, so
/// rollback copies them, and every choice they make comes off the match's dice.
public struct Helmet: Equatable {
    public var id: Int
    public var box: Box
    /// Units a frame, signed: the way it travels.
    public var speed: Double
    /// The defender whose colour it wears.
    public var owner: Int
    /// Which of the three helmet drawings.
    public var variant: Int
}

public struct Portal: Equatable {
    public var id: Int
    public var centre: Vec2
    public var framesLeft: Int
}

/// What a stage has beyond its tiles. The court has none of it.
public struct StageFeatures: Equatable {
    public var helmets = false
    public var portals = false
    /// The ball starts in a player's hands, by the coin flip, rather than loose at centre.
    public var startsHeld = false
    /// Bodies and scenery cast shadows on the floor, and a ball cam hangs over the player;
    /// only the view reads these.
    public var shadows = false
    public var ballCam = false
    public init(helmets: Bool = false, portals: Bool = false, startsHeld: Bool = false, shadows: Bool = false, ballCam: Bool = false) {
        self.helmets = helmets
        self.portals = portals
        self.startsHeld = startsHeld
        self.shadows = shadows
        self.ballCam = ballCam
    }
}

/// The field's numbers. Helmets are five tiles square, spawn every five seconds of
/// possession, halved to two and a half, from the defender's end at one of four heights, four
/// tiles square, and cross to the
/// other end. The portal is a vertical loop above double-jump height, one at a time, five
/// seconds each, the next as soon as it goes; a shot or throw through it comes out ten
/// yards toward the shooter's rim with a lift.
public enum FieldRules {
    public static let helmetSize = 40.0
    public static let helmetSpawnFrames = 150
    public static let helmetSpeed = 2.0
    /// The lowest pushes a standing body and clears a crouched or sliding one.
    public static let helmetHeights: [Double] = [20, 50, 70, 90]
    public static let helmetVariants = 3
    public static let portalFrames = 300
    public static let portalHeight = 90.0
    public static let portalHalfWidth = 5.0
    public static let portalHalfHeight = 15.0
    /// Kept this far from either end, clear of the goalposts.
    public static let portalMargin = 200.0
    /// A hundred yards is the field between the walls.
    public static func yard(in stage: Stage) -> Double { (stage.width - 2 * Stage.tileSize) / 100 }
    public static let warpYards = 10.0
    public static let warpLift = Vec2(x: 2, y: 3.5)
    /// The backboard's box: its centre behind and above the rim, and its size, in units;
    /// the drawing's 10 and 24 art pixels.
    public static let backboardOffset = Vec2(x: 6.25, y: 15)
    public static let backboardSize = Vec2(x: 4, y: 20)
}

extension Match {
    /// Helmets and the portal, a frame on, before anyone moves.
    mutating func stepField() {
        if stage.features.helmets { stepHelmets() }
        if stage.features.portals { stepPortal() }
    }

    private mutating func stepHelmets() {
        // The spawn clock runs only while someone has the ball.
        if let holder = ball.holder, let defender = players.indices.first(where: { $0 != holder }) {
            helmetClock += 1
            if helmetClock >= FieldRules.helmetSpawnFrames {
                helmetClock = 0
                spawnHelmet(against: holder, wearing: defender)
            }
        }
        var kept: [Helmet] = []
        for var helmet in helmets {
            // Who stands on it rides it; who is in its way is pushed ahead of it, unless
            // that would put them in a wall, and then it passes through them.
            let riders = players.indices.filter { stands(players[$0], on: helmet.box) }
            helmet.box = helmet.box.offset(by: Vec2(x: helmet.speed, y: 0))
            for index in riders { carry(index, by: helmet.speed) }
            for index in players.indices where !riders.contains(index) && players[index].body.overlaps(helmet.box) {
                push(index, ahead: helmet)
            }
            if ball.holder == nil, ball.isLive, ball.frozen == 0, ball.box.overlaps(helmet.box) {
                pushBall(ahead: helmet)
            }
            // Gone at the far wall.
            let far = helmet.speed > 0 ? helmet.box.max.x >= stage.width - Stage.tileSize : helmet.box.min.x <= Stage.tileSize
            if far {
                events.append(.helmetRemoved(at: helmet.box.center, owner: helmet.owner))
            } else {
                kept.append(helmet)
            }
        }
        // Two going opposite ways that meet take each other out.
        var gone = Set<Int>()
        for first in kept.indices {
            for second in kept.indices where second > first && kept[first].speed.sign != kept[second].speed.sign {
                if kept[first].box.overlaps(kept[second].box) {
                    gone.insert(first)
                    gone.insert(second)
                    events.append(.helmetsCollided(at: kept[first].box.center, owner: kept[first].owner))
                    events.append(.helmetsCollided(at: kept[second].box.center, owner: kept[second].owner))
                }
            }
        }
        helmets = kept.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
        stage.extras = platforms.map(\.box) + helmets.map(\.box)
    }

    /// From the end the defender guards, the rim the holder scores on, toward the other.
    private mutating func spawnHelmet(against holder: Int, wearing defender: Int) {
        let target = stage.hoops.first { $0.owner == holder } ?? stage.hoops[0]
        let fromRight = target.position.x > stage.width / 2
        let bottom = FieldRules.helmetHeights[fieldDice.roll(FieldRules.helmetHeights.count)]
        let size = FieldRules.helmetSize
        // Just clear of its own wall, so it isn't gone the frame it comes.
        let x = fromRight ? stage.width - Stage.tileSize - size - 1 : Stage.tileSize + 1
        let box = Box(min: Vec2(x: x, y: bottom), max: Vec2(x: x + size, y: bottom + size))
        helmets.append(Helmet(id: stampId(), box: box, speed: FieldRules.helmetSpeed * (fromRight ? -1 : 1),
                              owner: defender, variant: fieldDice.roll(FieldRules.helmetVariants)))
        events.append(.helmetSpawned(at: box.center, owner: defender))
    }

    private func stands(_ player: Player, on box: Box) -> Bool {
        player.grounded && abs(player.position.y - box.max.y) < 0.01
            && player.body.max.x > box.min.x && player.body.min.x < box.max.x
    }

    /// Moved along with a helmet it stands on, stopping at a wall.
    private mutating func carry(_ index: Int, by dx: Double) {
        let swept = stage.sweepHorizontally(players[index].body, by: dx)
        players[index].position.x += swept.moved
    }

    private func onlyTiles() -> Stage {
        var tiles = stage
        tiles.extras = platforms.map(\.box)
        return tiles
    }

    /// Ahead of the helmet's leading face, unless a wall is there.
    private mutating func push(_ index: Int, ahead helmet: Helmet) {
        let half = players[index].spec.bodyWidth / 2
        let x = helmet.speed > 0 ? helmet.box.max.x + half : helmet.box.min.x - half
        var moved = players[index]
        moved.position.x = x
        guard !onlyTiles().overlapsSolid(moved.body) else { return }
        players[index].position.x = x
        if (players[index].velocity.x > 0) != (helmet.speed > 0) || abs(players[index].velocity.x) < abs(helmet.speed) {
            players[index].velocity.x = helmet.speed
        }
    }

    private mutating func pushBall(ahead helmet: Helmet) {
        let x = helmet.speed > 0 ? helmet.box.max.x + BallRules.radius : helmet.box.min.x - BallRules.radius
        let moved = Box(center: Vec2(x: x, y: ball.position.y), width: BallRules.radius * 2, height: BallRules.radius * 2)
        guard !onlyTiles().overlapsSolid(moved) else { return }
        ball.position.x = x
        if (ball.velocity.x > 0) != (helmet.speed > 0) || abs(ball.velocity.x) < abs(helmet.speed) {
            ball.velocity.x = helmet.speed
        }
        // Pushed, it's an ordinary ball: it falls.
        ball.straight = false
        ball.floater = 0
        ball.resting = false
    }

    private mutating func stepPortal() {
        if var open = portal {
            open.framesLeft -= 1
            portal = open.framesLeft > 0 ? open : nil
            if portal == nil { events.append(.portalClosed(at: open.centre)) }
        }
        if portal == nil {
            let span = Int(stage.width - 2 * FieldRules.portalMargin)
            let x = FieldRules.portalMargin + Double(fieldDice.roll(max(span, 1)))
            portal = Portal(id: stampId(), centre: Vec2(x: x, y: FieldRules.portalHeight), framesLeft: FieldRules.portalFrames)
            events.append(.portalOpened(at: portal!.centre))
        }
        // A shot or a throw, still its thrower's, through the loop: ten yards toward their rim.
        guard let open = portal, ball.isLive, ball.holder == nil, let shooter = ball.owner else { return }
        let loop = Box(center: open.centre, width: FieldRules.portalHalfWidth * 2, height: FieldRules.portalHalfHeight * 2)
        guard ball.box.overlaps(loop), portalCooldown == 0 else { return }
        let target = stage.hoops.first { $0.owner == shooter } ?? stage.hoops[0]
        let sign: Double = target.position.x > ball.position.x ? 1 : -1
        let from = ball.position
        let reach = FieldRules.warpYards * FieldRules.yard(in: stage)
        let low = Stage.tileSize + BallRules.radius, high = stage.width - Stage.tileSize - BallRules.radius
        ball.position.x = min(max(ball.position.x + sign * reach, low), high)
        ball.previousY = ball.position.y
        ball.velocity = Vec2(x: FieldRules.warpLift.x * sign, y: FieldRules.warpLift.y)
        ball.straight = false
        portalCooldown = 20
        events.append(.portalWarped(from: from, to: ball.position))
    }

    /// Anything that has left the world comes back at centre.
    mutating func keepBallInWorld() {
        guard ball.holder == nil, ball.isLive else { return }
        let outside = ball.position.y < -Stage.tileSize || ball.position.x < 0 || ball.position.x > stage.width
            || ball.position.y > Double(stage.rows + Stage.skyRows) * Stage.tileSize
        if outside {
            ball.respawn(at: stage.ballSpawn)
            events.append(.ballRespawned)
        }
    }
}
