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
    /// Coming out of its goalpost's prongs' middle (`gate`, the line it comes through) toward the
    /// field until clear of the goalpost, then up or down to `bottom`, then across; at the other
    /// goalpost back to the prongs' height and in through theirs (`gate` then theirs). Solid only
    /// while it travels.
    public var phase: HelmetPhase = .travelling
    public var gate: Double = 0
    public var bottom: Double = 0
}

public enum HelmetPhase: Equatable { case emerging, settling, travelling, returning, entering }

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
    /// Standstill traffic, and the rim carried by a helicopter.
    public var traffic = false
    /// Bodies and scenery cast shadows on the floor, and a ball cam hangs over the player;
    /// only the view reads these, and which scenery to draw.
    public var shadows = false
    public var ballCam = false
    public var look = StageLook.court
    /// A body can land on the stage's walls, and so wall jump; off, only on what moves or is
    /// made (helmets, slabs), never the tiles. The board rides them either way.
    public var tileWallsHold = true
    /// The height of lava along the bottom: feet under it burn, and go back to where they started.
    public var lavaSurface: Double?
    /// Under water: gravity halved, for bodies and the ball; the ground's speeds halved but not
    /// the air's; the bodies' sheets played at half their rate.
    public var underwater = false
    /// In 47, a basket's points doubled; a round is a round either way.
    public var doublePoints = false
    /// Every body this many times its size, as Titan Tea grows one: on a stage drawn bigger than
    /// the bodies' own art, Flight B411's.
    public var bodyScale = 1.0
    /// The stage pitches now and then, leaning gravity (`Stage.tilt`), with a cart rolling it: Flight B411's.
    public var tilts = false
    /// Every body this share of its speeds, on the ground, in the air and in flight: half on Flight B411.
    public var speedShare = 1.0
    /// Whether its rims can be dunked on at all: not the plane's.
    public var dunks = true
    /// Whether 47 has threes at all, and draws their line: not on the plane, too small for them.
    public var threes = true
    /// 47's three-point radius on this stage, rather than one measured to its one-ways: K&A's,
    /// whose one-ways are its cars.
    public var threeRadius: Double?
    /// Seen whole: the camera fitted to the stage, not by whole screen pixels, as the plane and K&A are.
    public var seenWhole = false
    /// The ball truck brings the ball in at the start of the match and of each Rounds round (`BallTruck.swift`).
    public var ballTruck = false
    /// The floor's a road: whoever's on it slides left with it (`Player`'s forced slide), Anozira's.
    public var roadSlides = false
    /// A dunk lands but scores nothing: the ball bounces off the rim, the dunker hanging on (Anozira's moving rim).
    public var dunksBounce = false
    /// Whether a body can land on the stage's walls and jump off them: not the plane's.
    public var wallJumps = true
    /// Whether a rim's top turns back a ball not scoring and a body coming down on it: not the
    /// plane's, whose rims hang in their cases with no net.
    public var rimBounce = true
    /// Whether a shot's preset arc aims itself at the rim: not on Longball.
    public var autoAims = true
    /// The Tutorial (`Stage.tutorial`), debug only for now: the Wreck Center's court from its own
    /// map, one rim, a door at each end and a belt along the floor; the training dummy the other side.
    public var tutorial = false
    public init(helmets: Bool = false, portals: Bool = false, startsHeld: Bool = false, traffic: Bool = false,
                shadows: Bool = false, ballCam: Bool = false, look: StageLook = .court, tileWallsHold: Bool = true) {
        self.helmets = helmets
        self.portals = portals
        self.startsHeld = startsHeld
        self.traffic = traffic
        self.shadows = shadows
        self.ballCam = ballCam
        self.look = look
        self.tileWallsHold = tileWallsHold
    }
}

/// The scenery a stage is drawn with.
public enum StageLook: Equatable {
    case court, footballField, highway, elements, hoopfishHideaway, flightB411, kAndA, anozira
}

extension StageFeatures {
    /// Drawn with scenery in place of tiles, the floor an invisible strip through the ground.
    public var scenic: Bool { look != .court }
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
    /// The goalposts as drawn, in art pixels: the base's 64-pixel frame on the floor's bottom, GOALPOST
    /// HEIGHT stems of 16 over it, the 16-pixel bend on them, and the crossbar's 48-pixel frame centred
    /// on the bend's, its foot 16 under the bend's; the hoop's frame shares that foot, the rim 14 up it,
    /// raised HOOP LIFT tiles off it. FORK HEIGHT forks of 16 stand on each end of the crossbar.
    nonisolated(unsafe) public static var goalpostStems = 8
    nonisolated(unsafe) public static var goalpostForks = 8
    nonisolated(unsafe) public static var hoopLiftTiles = 0
    public static let goalpostFootPixels = 0
    public static var crossbarFootPixels: Int { goalpostFootPixels + 64 + 16 * goalpostStems - 16 }
    public static var rimOverCrossbarFootPixels: Int { 14 + 16 * hoopLiftTiles }
    /// The goalpost's picture's far side, 24 pixels in front of its rim, and its width.
    public static let goalpostFrontOfRimPixels = 24
    public static let goalpostWidthPixels = 80
    /// The middle between the prongs, in units: behind the rim across, and up from the floor's
    /// foot (the forks' middle, the far ones 48 over the crossbar's foot, the near ones 16).
    public static var prongsBehindRim: Double { Double(goalpostWidthPixels / 2 - goalpostFrontOfRimPixels) / 1.6 }
    public static var prongsHeight: Double { Double(crossbarFootPixels + 32 + 8 * goalpostForks) / 1.6 }
    public static var goalpostFrontOfRim: Double { Double(goalpostFrontOfRimPixels) / 1.6 }
    /// A rim's goalpost's prongs' middle, and its front toward the field, across, in units.
    public static func prongsGate(of hoop: Hoop) -> Double { hoop.position.x + hoop.backboard.sign * prongsBehindRim }
    public static func goalpostFront(of hoop: Hoop) -> Double { hoop.position.x - hoop.backboard.sign * goalpostFrontOfRim }
    /// The energy fence's top, in units: the uprights' tops over the backboard, where the drawn
    /// fence stops. The far cap's top is 56 over the crossbar's foot and the near one's 32, 66 pixels
    /// apart; the backboard stands 30 in from the far one, so 45 plus the forks. The ball's blocker
    /// runs from the backboard's bottom up to here.
    public static var fenceTop: Double { Double(crossbarFootPixels + 16 * goalpostForks + 45) / 1.6 }
}

extension Match {
    /// Helmets and the portal, a frame on, before anyone moves.
    mutating func stepField() {
        if stage.features.helmets { stepHelmets() }
        if stage.features.portals { stepPortal() }
        if stage.features.traffic { stepHighway() }
    }

    private mutating func stepHelmets() {
        if mode == .breakerBall {
            // Breaker Ball: the clock runs whoever has the ball, and each comes off the dice, its end and its colour.
            helmetClock += 1
            if helmetClock >= FieldRules.helmetSpawnFrames, !players.isEmpty {
                helmetClock = 0
                let holder = fieldDice.roll(players.count)
                spawnHelmet(against: holder, wearing: fieldDice.roll(players.count))
            }
        } else if let holder = ball.holder, let defender = players.indices.first(where: { $0 != holder }) {
            // The spawn clock runs only while someone has the ball.
            helmetClock += 1
            if helmetClock >= FieldRules.helmetSpawnFrames {
                helmetClock = 0
                spawnHelmet(against: holder, wearing: defender)
            }
        }
        var kept: [Helmet] = []
        for var helmet in helmets {
            guard helmet.phase == .travelling else {
                if passThrough(&helmet) {
                    kept.append(helmet)
                } else {
                    events.append(.helmetRemoved(at: Vec2(x: helmet.gate, y: FieldRules.prongsHeight), owner: helmet.owner))
                }
                continue
            }
            // Who stands on it rides it; who is in its way is pushed ahead of it, unless
            // that would put them in a wall, and then it passes through them.
            let riders = players.indices.filter { stands(players[$0], on: helmet.box) }
            helmet.box = helmet.box.offset(by: Vec2(x: helmet.speed, y: 0))
            for index in riders { carry(index, by: helmet.speed) }
            // A Titan in its way isn't pushed: it breaks on them.
            if players.indices.contains(where: { !riders.contains($0) && players[$0].power == .titanTea && players[$0].body.overlaps(helmet.box) }) {
                events.append(.helmetRemoved(at: helmet.box.center, owner: helmet.owner))
                continue
            }
            // Breaker Ball: it breaks on a barrier, wearing it down hard.
            // if mode == .breakerBall, stage.hoops.contains(where: { $0.barrierStanding && helmet.box.distance(to: $0.position) <= barrierRadius($0) }) {
            //     stageHitsBarriers(helmet.box, damage: BreakerRules.helmetDamage)
            //     events.append(.helmetRemoved(at: helmet.box.center, owner: helmet.owner))
            //     continue
            // }
            // Breaker Ball: it breaks on a body, wearing their barrier down hard.
            if mode == .breakerBall, let index = players.indices.first(where: { !riders.contains($0) && !players[$0].phantomMode && players[$0].hurt(by: helmet.box) }) {
                wearPosture(index, by: BreakerRules.helmetDamage, from: nil, at: helmet.box.center)
                events.append(.helmetRemoved(at: helmet.box.center, owner: helmet.owner))
                continue
            }
            for index in players.indices where !riders.contains(index) && players[index].body.overlaps(helmet.box) {
                push(index, ahead: helmet)
            }
            if ball.holder == nil, ball.isLive, ball.frozen == 0, ball.box.overlaps(helmet.box) {
                pushBall(ahead: helmet)
            }
            // At the other goalpost, on its way into it; gone at the far wall, should it get there.
            let forward = helmet.speed > 0 ? 1.0 : -1.0
            let lead = forward > 0 ? helmet.box.max.x : helmet.box.min.x
            if let far = stage.goalpostHoops.first(where: { $0.backboard.sign == forward }),
               (lead - FieldRules.goalpostFront(of: far)) * forward >= 0 {
                helmet.box = helmet.box.offset(by: Vec2(x: FieldRules.goalpostFront(of: far) - lead, y: 0))
                helmet.gate = FieldRules.prongsGate(of: far)
                helmet.bottom = FieldRules.prongsHeight - FieldRules.helmetSize / 2
                helmet.phase = .returning
                kept.append(helmet)
                continue
            }
            let atWall = helmet.speed > 0 ? helmet.box.max.x >= stage.width - Stage.tileSize : helmet.box.min.x <= Stage.tileSize
            if atWall {
                events.append(.helmetRemoved(at: helmet.box.center, owner: helmet.owner))
            } else {
                kept.append(helmet)
            }
        }
        // Two going opposite ways that meet take each other out.
        var gone = Set<Int>()
        for first in kept.indices where kept[first].phase == .travelling {
            for second in kept.indices where second > first && kept[second].phase == .travelling && kept[first].speed.sign != kept[second].speed.sign {
                if kept[first].box.overlaps(kept[second].box) {
                    gone.insert(first)
                    gone.insert(second)
                    events.append(.helmetsCollided(at: kept[first].box.center, owner: kept[first].owner))
                    events.append(.helmetsCollided(at: kept[second].box.center, owner: kept[second].owner))
                }
            }
        }
        helmets = kept.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
        refreshExtras()
    }

    /// From the end the defender guards, the rim the holder scores on, toward the other: out of
    /// that goalpost's prongs' middle, wholly behind it to start.
    private mutating func spawnHelmet(against holder: Int, wearing defender: Int) {
        let target = stage.goalpostHoops.first { $0.owner == holder } ?? stage.goalpostHoops[0]
        let back = target.backboard.sign
        let bottom = FieldRules.helmetHeights[fieldDice.roll(FieldRules.helmetHeights.count)]
        let size = FieldRules.helmetSize
        let gate = FieldRules.prongsGate(of: target)
        let x = back > 0 ? gate : gate - size
        let y = FieldRules.prongsHeight - size / 2
        let box = Box(min: Vec2(x: x, y: y), max: Vec2(x: x + size, y: y + size))
        helmets.append(Helmet(id: stampId(), box: box, speed: -back * FieldRules.helmetSpeed, owner: defender,
                              variant: fieldDice.roll(FieldRules.helmetVariants), phase: .emerging, gate: gate, bottom: bottom))
        events.append(.helmetSpawned(at: Vec2(x: gate, y: FieldRules.prongsHeight), owner: defender))
    }

    /// A frame of a helmet's way out of a goalpost or into one, at its speed: out toward the field
    /// until its back clears the goalpost's front, then to its height; at the other end to the
    /// prongs' height, then in until its back is through. False once it's gone in.
    private func passThrough(_ helmet: inout Helmet) -> Bool {
        let pace = abs(helmet.speed)
        let forward = helmet.speed > 0 ? 1.0 : -1.0
        let back = forward > 0 ? helmet.box.min.x : helmet.box.max.x
        func slide(to x: Double) -> Bool {
            let step = min(pace, max((x - back) * forward, 0))
            helmet.box = helmet.box.offset(by: Vec2(x: forward * step, y: 0))
            return step < pace
        }
        func rise() -> Bool {
            let rise = helmet.bottom - helmet.box.min.y
            helmet.box = helmet.box.offset(by: Vec2(x: 0, y: max(-pace, min(pace, rise))))
            return abs(rise) <= pace
        }
        switch helmet.phase {
        case .emerging:
            if slide(to: helmet.gate + forward * (FieldRules.prongsBehindRim + FieldRules.goalpostFrontOfRim)) { helmet.phase = .settling }
        case .settling:
            if rise() { helmet.phase = .travelling }
        case .returning:
            if rise() { helmet.phase = .entering }
        case .entering:
            if slide(to: helmet.gate) { return false }
        case .travelling:
            break
        }
        return true
    }

    func stands(_ player: Player, on box: Box) -> Bool {
        player.grounded && abs(player.position.y - box.max.y) < 0.01
            && player.body.max.x > box.min.x && player.body.min.x < box.max.x
    }

    /// Moved along with a helmet it stands on, stopping at a wall.
    mutating func carry(_ index: Int, by dx: Double) {
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
        guard let open = portal else { return }
        let loop = Box(center: open.centre, width: FieldRules.portalHalfWidth * 2, height: FieldRules.portalHalfHeight * 2)
        // A player without the ball through it, likewise ten yards toward their rim, going on as they were.
        for index in players.indices where !players[index].hasBall && players[index].body.overlaps(loop) {
            let target = stage.hoops.first { $0.owner == index } ?? stage.hoops[0]
            let sign: Double = target.position.x > players[index].position.x ? 1 : -1
            let from = players[index].position
            let half = players[index].spec.bodyWidth / 2
            let low = Stage.tileSize + half, high = stage.width - Stage.tileSize - half
            let velocity = players[index].velocity
            players[index].warp(to: Vec2(x: min(max(from.x + sign * FieldRules.warpYards * FieldRules.yard(in: stage), low), high), y: from.y), in: stage)
            players[index].velocity = velocity
            events.append(.portalCarried(player: index, from: from, to: players[index].position))
        }
        // A shot or a throw, still its thrower's, through the loop: ten yards toward their rim.
        guard ball.isLive, ball.holder == nil, let shooter = ball.owner else { return }
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
            || ball.position.y > Double(stage.rows + stage.skyRows) * Stage.tileSize
            || (ball.resting && stage.outOfReach.contains { $0.min.x <= ball.position.x && ball.position.x <= $0.max.x
                && $0.min.y <= ball.position.y && ball.position.y <= $0.max.y })
        if outside {
            ball.respawn(at: stage.ballSpawn)
            events.append(.ballRespawned)
        }
    }
}
