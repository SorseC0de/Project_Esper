import Foundation

/// Breaker Ball. Each rim floats over and behind the player defending it, a little late, inside a
/// barrier of hexes, tied to their far hand by a chain; every snatch parks it where it is, or near
/// enough, takes it back. Shots, throws, slashes and powers wear the other's barrier down, smaller as
/// it goes, every hit giving its defender FLO; at nothing it shatters and the rim is open. A basket on
/// your own rim mends your barrier (your own ball passes through it); a shattered one stands again
/// only once it's whole. One basket on the other's wins. No shot is aimed for you.
public enum BreakerRules {
    public static let full = 100.0
    /// The rim's rest off its defender's middle, units: behind the way they face, and up. On the BREAKER sliders.
    public static var restBehind = 24 / 1.6
    public static var restAbove = 30.0
    /// The share of the way to its rest the rim goes each frame.
    public static var followShare = 0.08
    /// Kept this far inside the stage's sides and top, units.
    public static let wallMargin = 15.0
    /// The barrier's sphere round the rim's middle, units (28 art pixels); Flight B411's hoopcases' smaller (20).
    public static let radius = 28 / 1.6
    public static let hoopcaseRadius = 20 / 1.6
    /// Mended by each basket its defender puts through their own rim.
    public static let ownBasketHeal = 10.0
    /// Shrunk to this share of its size at nothing, in step with what's left.
    public static let emptySizeShare = 0.5
    /// A parked rim's taken back by a snatch this near its middle, units (48 art pixels).
    public static let unparkReach = 48 / 1.6
    /// A ball on a floating backboard's top rolls off it at least this fast: nothing's left up there out of reach.
    public static let boardRollOff = 1.0
    /// Furthest a rim parked in a wall is moved to stand clear of it, in units.
    public static let parkClearReach = 64 / 1.6
    /// FLO its defender gains for each point of damage the barrier takes.
    public static let floPerDamage = 0.5
    /// False: attacks touch the barriers and the loose ball alone, never a body.
    public static let attacksHitPlayers = true
    /// The other body put back out of a barrier, and sent off it at least this fast.
    public static let pushSpeed = 2.0

    /// Breaker Balls: a throw's by its charge, uncharged to full; a shot's the full throw's, slower and harder to land;
    /// one snatched out of the air takes this off its thrower.
    public static let ballThrowDamageLeast = 5.0
    public static let ballThrowDamageMost = 10.0
    public static let ballShotDamage = 10.0
    public static let catchDamage = 10.0
    /// Baskets to win.
    public static let winningScore = 3
    /// A stunned body's rim over the top of their head, units: the BREAKER HOOP ABOVE slider.
    public static var hoopAboveHead = 32 / 1.6
    /// The barrier round a body, units (24 art pixels): the BREAKER BARRIER slider.
    public static var postureRadius = 24 / 1.6
    /// Hits land on the barrier's circle rather than the body's box; false puts the box back.
    public static let roundHurtbox = true
    /// A shatter's stun, frames: five seconds.
    public static let stunFrames = 300
    /// Frames the game holds on whoever's scored on.
    public static let scoredOnFreezeFrames = 30
    /// A Breaker Ball still flying after this long bursts.
    public static let flightFramesMost = 600

    public static let shotDamage = 1.0
    /// A throw's by its charge (`ThrowChargeRules`), uncharged to full.
    public static let throwDamageLeast = 3.0
    public static let throwDamageMost = 6.0
    /// A full throw's: closing in is worth it.
    public static let slashDamage = ballThrowDamageMost
    public static let boltDamage = 1.5
    public static let strikeDamage = 4.0
    public static let blastDamage = 1.5
    public static let beamDamagePerFrame = 0.125
    public static let fireballDamage = 7.5
    public static let flameDamagePerFrame = 0.05
    /// Gale Ale's tornados and the Elements' a frame they're on a barrier; a fire one twice.
    public static let tornadoDamagePerFrame = 0.125
    public static let fireTornadoDamagePerFrame = 0.25
    public static let snipeDamage = 3.0
    public static let pulseDamage = 1.5
    /// The ball circling a body changing into FloState, each pass at most every `orbitHitFrames`.
    public static let orbitDamage = 3.0
    public static let orbitHitFrames = 12
    /// The Elements: an icicle, its fireball (Blazing Boba's own), and a frame of a barrier dipping into the lava.
    public static let icicleDamage = 5.0
    public static let lavaDamagePerFrame = 0.2
    /// A body burned while its barrier's shattered comes back with this much of it.
    public static let lavaRespawnPosture = 1.0
    /// The Elements' lightning, and a Longball helmet breaking on one.
    public static let lightningDamage = 10.0
    public static let helmetDamage = 15.0
    /// Anozira: sliding on the road wears your own barrier down a frame; a pothole under your car
    /// a little, sliding or running into one more.
    public static let roadSlideDamagePerFrame = 0.1
    public static let potholeRidingDamage = 1.0
    public static let potholeSlidingDamage = 6.0
}

extension Stage {
    /// Breaker Ball's barrier round each rim on this stage, units.
    public var barrierRadius: Double { features.tilts ? BreakerRules.hoopcaseRadius : BreakerRules.radius }

    /// The stage as Breaker Ball plays it: the backboard columns and walls that stood where the rims
    /// began taken out, two rims where it had one, no Hoopfish, nothing aimed, every barrier whole.
    func forBreakerBall() -> Stage {
        var stage = self
        stage.homeHoops = hoops
        stage.fixedExtras.removeAll { box in
            hoops.contains { hoop in
                let side = hoop.backboard.sign
                return box.distance(to: Vec2(x: hoop.position.x + side * (Stage.backboardFace + 1), y: hoop.position.y + Stage.backboardBottom + 1)) == 0
            }
        }
        stage.extras = stage.fixedExtras
        stage.ballBlockers = []
        stage.hoopfishStart = nil
        stage.features.autoAims = false
        stage.features.doublePoints = false
        stage.features.dunksBounce = false
        stage.features.ballTruck = false
        // One rim for both, or a bonus ring beside it: a rim each instead.
        let playable = stage.hoops.filter { !$0.bonus }
        if playable.count != 2 || playable.contains(where: \.shared) {
            let rim = playable.first?.position ?? stage.ballSpawn
            stage.hoops = [Hoop(position: rim, owner: 1, backboard: .left), Hoop(position: rim, owner: 0, backboard: .right)]
        } else {
            stage.hoops = playable
        }
        if stage.features.look == .anozira {
            // A car each, the first on its hood, the second on its trunk, facing each other.
            stage.playerSpawns = [AnoziraRules.car(at: 0, running: nil) + AnoziraRules.carSpawns[1],
                                  AnoziraRules.secondCar(at: 0, running: nil) + AnoziraRules.carSpawns[0]]
            stage.playerFacings = [.right, .left]
        }
        for index in stage.hoops.indices {
            stage.hoops[index].shared = false
            stage.hoops[index].barrier = BreakerRules.full
        }
        return stage
    }
}

extension Match {
    /// A barrier's sphere now: smaller the more it's lost.
    public func barrierRadius(_ hoop: Hoop) -> Double {
        stage.barrierRadius * (BreakerRules.emptySizeShare + (1 - BreakerRules.emptySizeShare) * (hoop.barrier ?? BreakerRules.full) / BreakerRules.full)
    }

    /// Breaker Ball's attacks pass through bodies.
    var bodiesSpared: Bool { mode == .breakerBall && !BreakerRules.attacksHitPlayers }

    /// Whether `striker`'s attack can touch `victim`'s body: not a phantom apart, nor in Breaker Ball, nor a shattered barrier,
    /// nor in a hit's grace (`HitGraceRules`).
    func attacksPass(_ victim: Int, _ striker: Int) -> Bool {
        phantomApart(victim, striker) || bodiesSpared || barrierDown(victim) || players[victim].hitGrace > 0
    }

    /// A Breaker Ball body whose barrier is shattered: attacks pass through it.
    func barrierDown(_ index: Int) -> Bool {
        mode == .breakerBall && postureBroken.indices.contains(index) && postureBroken[index]
    }

    /// The player defending a rim: the one who doesn't score on it.
    func defender(of hoop: Hoop) -> Int? {
        players.indices.first { $0 != hoop.owner }
    }

    // Breaker Ball's old following rims: off for the posture rules (`BreakerPosture.swift` places them now).
    // /// Each rim on toward its rest behind and over its defender, its backboard on the far side; a parked one stays put.
    // mutating func placeBreakerHoops(snapped: Bool = false) {
    //     guard mode == .breakerBall, !stage.features.tilts else { return }
    //     let top = Double(stage.rows) * Stage.tileSize - BreakerRules.wallMargin
    //     for index in stage.hoops.indices where !stage.hoops[index].parked {
    //         guard let defender = defender(of: stage.hoops[index]) else { continue }
    //         let body = players[defender]
    //         let rest = body.body.center + Vec2(x: -body.facing.sign * BreakerRules.restBehind, y: BreakerRules.restAbove)
    //         let was = stage.hoops[index].position
    //         var next = snapped ? rest : was + (rest - was) * BreakerRules.followShare
    //         next.x = min(max(next.x, BreakerRules.wallMargin), stage.width - BreakerRules.wallMargin)
    //         next.y = min(next.y, top)
    //         stage.hoops[index].position = next
    //         stage.hoops[index].velocity = snapped ? .zero : next - was
    //         stage.hoops[index].backboard = next.x < body.position.x ? .left : .right
    //     }
    //     for index in stage.hoops.indices where stage.hoops[index].parked { stage.hoops[index].velocity = .zero }
    //     placeBreakerBoards()
    // }

    /// The backboards where the rims now are: solid to the ball, walls to jump off for the bodies.
    mutating func placeBreakerBoards() {
        let boards = stage.hoops.filter(\.hasBackboard).map(Match.breakerBackboard)
        stage.ballBlockers = boards
        stage.wallJumpBoards = boards
    }

    /// A rim's backboard: from its face behind the rim back its depth, from its bottom up the glass.
    static func breakerBackboard(_ hoop: Hoop) -> Box {
        let sign = hoop.backboard.sign
        let face = hoop.position.x + sign * Stage.backboardFace, back = face + sign * Stage.backboardDepth
        return Box(min: Vec2(x: Swift.min(face, back), y: hoop.position.y + Stage.backboardBottom),
                   max: Vec2(x: Swift.max(face, back), y: hoop.position.y + Stage.backboardTop))
    }

    /// The snatch, begun: the snatcher's rim parked where it is, or with a touch on its barrier, taken back.
    mutating func snatchParks(_ index: Int) {
        guard mode == .breakerBall, !stage.features.tilts, let hoop = stage.hoops.indices.first(where: { defender(of: stage.hoops[$0]) == index }) else { return }
        if !stage.hoops[hoop].parked {
            stage.hoops[hoop].parked = true
            stage.hoops[hoop].position = clearOfWalls(stage.hoops[hoop])
            events.append(.hoopParked(player: index, parked: true))
        } else if players[index].body.distance(to: stage.hoops[hoop].position) <= BreakerRules.unparkReach {
            stage.hoops[hoop].parked = false
            events.append(.hoopParked(player: index, parked: false))
        }
    }

    /// Where `hoop` stands nearest with its rim, net and backboard out of every wall and inside the stage;
    /// where it is if that's clear already or nowhere within reach is.
    func clearOfWalls(_ hoop: Hoop) -> Vec2 {
        let sign = hoop.backboard.sign
        let front = -sign * BallRules.rimHalfWidth, back = sign * (Stage.backboardFace + Stage.backboardDepth)
        func footprint(_ at: Vec2) -> Box {
            Box(min: Vec2(x: at.x + Swift.min(front, back), y: at.y - BallRules.netDepth),
                max: Vec2(x: at.x + Swift.max(front, back), y: at.y + Stage.backboardTop))
        }
        func clear(_ at: Vec2) -> Bool {
            let box = footprint(at)
            return box.min.x >= 0 && box.max.x <= stage.width && box.min.y >= 0 && box.max.y <= Double(stage.rows) * Stage.tileSize
                && !stage.overlapsSolid(box)
        }
        if clear(hoop.position) { return hoop.position }
        let reach = Int(BreakerRules.parkClearReach.rounded())
        var best: Vec2?
        for across in -reach...reach {
            for up in -reach...reach {
                let offset = Vec2(x: Double(across), y: Double(up))
                guard offset.length <= Double(reach), offset.length < (best?.length ?? .infinity), clear(hoop.position + offset) else { continue }
                best = offset
            }
        }
        return best.map { hoop.position + $0 } ?? hoop.position
    }

    /// The stage wearing `player`'s own barrier down: the road, a pothole.
    mutating func damageOwnBarrier(of player: Int, by damage: Double, at point: Vec2) {
        // guard mode == .breakerBall, let hoop = stage.hoops.indices.first(where: { defender(of: stage.hoops[$0]) == player }) else { return }
        // damageBarrier(hoop, by: damage, at: point)
        wearPosture(player, by: damage, from: nil, at: point)
    }

    /// The other body inside a standing barrier put back out of it, and sent off it; against a wall,
    /// a following barrier's moved off it instead, so nothing's pinned there.
    mutating func pushFromBarriers() {
        guard mode == .breakerBall else { return }
        // Always sideways, so nothing rests on top of one.
        for index in stage.hoops.indices where stage.hoops[index].barrierStanding {
            let hoop = stage.hoops[index]
            guard players.indices.contains(hoop.owner), !players[hoop.owner].phantomMode else { continue }
            let radius = barrierRadius(hoop)
            let body = players[hoop.owner].body
            guard body.distance(to: hoop.position) < radius else { continue }
            let up = Swift.max(body.min.y - hoop.position.y, 0, hoop.position.y - body.max.y)
            let clear = (Swift.max(radius * radius - up * up, 0)).squareRoot()
            let way: Double = body.center.x >= hoop.position.x ? 1 : -1
            let edge = way > 0 ? body.min.x : body.max.x
            let need = (hoop.position.x + way * clear) - edge
            let moved = stage.sweepHorizontally(body, by: need).moved
            players[hoop.owner].position.x += moved
            let blocked = need - moved
            if abs(blocked) > 0.01 {
                // A parked one stays; the body's left free to walk out of it.
                if !hoop.parked {
                    stage.hoops[index].position.x -= blocked
                    placeBreakerBoards()
                }
                continue
            }
            if players[hoop.owner].velocity.x * way < BreakerRules.pushSpeed { players[hoop.owner].velocity.x = way * BreakerRules.pushSpeed }
        }
    }

    /// The standing barrier `attacker` scores past whose sphere `reaches` meets, given its middle and
    /// radius. A phantom's attacks pass through it.
    func barrier(metBy attacker: Int, where reaches: (Vec2, Double) -> Bool) -> Int? {
        guard mode == .breakerBall, players.indices.contains(attacker), !players[attacker].phantomMode else { return nil }
        return stage.hoops.indices.first {
            stage.hoops[$0].owner == attacker && stage.hoops[$0].barrierStanding && reaches(stage.hoops[$0].position, barrierRadius(stage.hoops[$0]))
        }
    }

    /// A standing barrier `owner` scores past, met by `box`, worn down by `damage`: true when one was.
    @discardableResult
    mutating func barrierTakes(_ box: Box, from owner: Int, damage: Double) -> Bool {
        guard let hoop = barrier(metBy: owner, where: { centre, radius in box.distance(to: centre) <= radius }) else { return false }
        damageBarrier(hoop, by: damage, at: box.center)
        return true
    }

    /// Every standing barrier `box` meets worn down by the stage's own `damage`, whoever's it is.
    mutating func stageHitsBarriers(_ box: Box, damage: Double) {
        guard mode == .breakerBall else { return }
        for hoop in stage.hoops.indices where stage.hoops[hoop].barrierStanding && box.distance(to: stage.hoops[hoop].position) <= barrierRadius(stage.hoops[hoop]) {
            damageBarrier(hoop, by: damage, at: box.center)
        }
    }

    /// `hoop`'s barrier worn down, its defender's FLO up; at nothing, shattered till it's mended whole.
    mutating func damageBarrier(_ hoop: Int, by damage: Double, at point: Vec2) {
        guard stage.hoops[hoop].barrierStanding, let current = stage.hoops[hoop].barrier, let defender = defender(of: stage.hoops[hoop]) else { return }
        let left = max(current - damage, 0)
        stage.hoops[hoop].barrier = left
        events.append(.barrierHit(player: defender, at: point, damage: current - left))
        if breakerFloOwed.indices.contains(defender) {
            breakerFloOwed[defender] += (current - left) * BreakerRules.floPerDamage
            let owed = Int(breakerFloOwed[defender])
            if owed > 0 {
                breakerFloOwed[defender] -= Double(owed)
                earnFlo(owed, by: defender, at: point)
            }
        }
        if left == 0 {
            stage.hoops[hoop].barrierBroken = true
            events.append(.barrierShattered(player: defender, at: stage.hoops[hoop].position))
            holdHitStop(HitStopRules.shatterFrames)
        }
    }

    /// A basket through your own rim: your barrier mended; a shattered one stands again once it's whole.
    mutating func mendBarrier(_ hoop: Int) {
        guard let current = stage.hoops[hoop].barrier, let defender = defender(of: stage.hoops[hoop]) else { return }
        let mended = min(current + BreakerRules.ownBasketHeal, BreakerRules.full)
        stage.hoops[hoop].barrier = mended
        events.append(.barrierHealed(player: defender, amount: mended - current))
        if mended == BreakerRules.full, stage.hoops[hoop].barrierBroken {
            stage.hoops[hoop].barrierBroken = false
            events.append(.barrierRestored(player: defender))
        }
    }

    /// The Elements' lava eating at every barrier that dips into it.
    mutating func lavaEatsBarriers() {
        guard mode == .breakerBall, let lava = stage.features.lavaSurface else { return }
        for hoop in stage.hoops.indices where stage.hoops[hoop].barrierStanding && stage.hoops[hoop].position.y - barrierRadius(stage.hoops[hoop]) < lava {
            damageBarrier(hoop, by: BreakerRules.lavaDamagePerFrame, at: Vec2(x: stage.hoops[hoop].position.x, y: lava))
        }
    }

    /// Nothing rests on a floating backboard's top: the ball's sent off toward its nearer edge.
    mutating func rollOffBackboards() {
        guard mode == .breakerBall, ball.isLive, ball.holder == nil else { return }
        let bottom = ball.position.y - BallRules.radius
        guard let board = stage.ballBlockers.first(where: { abs(bottom - $0.max.y) < 0.5 && ball.velocity.y <= 0
            && ball.position.x + BallRules.radius > $0.min.x && ball.position.x - BallRules.radius < $0.max.x }) else { return }
        let way: Double = ball.position.x < board.center.x ? -1 : 1
        if ball.velocity.x * way < BreakerRules.boardRollOff { ball.velocity.x = way * BreakerRules.boardRollOff }
        ball.resting = false
    }

    /// A standing barrier turns the ball away, as 47's locked rim does; the other's shot or throw
    /// wears it down first, once a flight.
    mutating func barriersTurnTheBall(from start: Vec2) {
        guard mode == .breakerBall, ball.isLive, ball.holder == nil, ball.tether == nil, ball.frozen == 0, !ball.phantom else { return }
        for (number, hoop) in stage.hoops.enumerated() where hoop.barrierStanding && defender(of: hoop) != ball.lastTouched {
            let reach = barrierRadius(hoop) + BallRules.radius
            let centre = hoop.position
            guard start.distance(to: centre) >= reach else { continue }
            let path = ball.position - start
            let steps = Swift.max(Int(path.length.rounded(.up)), 1)
            guard let step = (1...steps).first(where: { (start + path * (Double($0) / Double(steps))).distance(to: centre) < reach }) else { continue }
            let at = start + path * (Double(step - 1) / Double(steps))
            let normal = (at - centre).normalized
            ball.position = at
            guard ball.velocity.dot(normal) < 0 else { return }
            if ball.owner == hoop.owner, breakerChippedFlight != ball.flight, ball.thrown || ball.scoring {
                breakerChippedFlight = ball.flight
                let thrown = BreakerRules.throwDamageLeast + (BreakerRules.throwDamageMost - BreakerRules.throwDamageLeast) * ball.throwCharge
                damageBarrier(number, by: ball.thrown ? thrown : BreakerRules.shotDamage, at: centre + normal * barrierRadius(hoop))
            }
            ball.reflect(off: normal)
            return
        }
    }

    /// A standing barrier the beam's firer scores past stops it where it meets it, worn down every frame it does.
    mutating func barrierStopsTheBeam(_ beam: Beam) -> Double {
        guard mode == .breakerBall else { return beam.reach }
        var travelled = 0.0
        while travelled <= beam.reach {
            let at = beam.origin + beam.direction * travelled
            if let hoop = barrier(metBy: beam.owner, where: { centre, radius in at.distance(to: centre) <= radius + ZRules.halfThickness }) {
                damageBarrier(hoop, by: BreakerRules.beamDamagePerFrame, at: at)
                return travelled
            }
            travelled += 2
        }
        return beam.reach
    }
}
