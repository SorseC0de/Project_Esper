import Foundation

/// A Breaker Ball in flight: let go as the ball is, flying as it does, bursting on the first thing it
/// meets but a backboard's glass or a rim. Into the other's body it takes `damage` off their barrier;
/// down through a stunned body's rim it scores.
public struct BreakerFlight: Equatable {
    public var id: Int
    /// Whose it is, to hit the other with; nobody's once knocked out of a hand.
    public var owner: Int?
    /// Whose energy it's drawn in.
    public var colour: Int
    public var ball: Ball
    public var damage: Double
    public var frames = 0
    /// Taken by a Web Water line: reeled to this body's hands, theirs on arrival.
    public var tether: Int?
}

/// Breaker Ball's posture rules. Each body has a barrier, its posture, that everything passes
/// through; hits wear it down. At nothing, or whenever the body's stunned as a parry stuns, it
/// shatters and their rim appears over their head. A basket through it scores, ends the stun and
/// restores the barrier; so does the stun running out. Both play with Breaker Balls, summoned
/// with Guard and nothing in hand, and no other ball. Three baskets win.
extension Match {
    /// Breaker Ball's start: both dribbling a Breaker Ball, the ball out of play, no FLO, the rims away.
    mutating func startBreakerBall() {
        posture = players.map { _ in BreakerRules.full }
        postureBroken = players.map { _ in false }
        for index in players.indices {
            players[index].summonsBreakerBall = true
            players[index].earnsFlo = false
            players[index].hasBall = true
        }
        ball.holder = nil
        ball.position = HighwayRules.parked
        ball.velocity = .zero
        // Never counted down: the ball's never live.
        ball.respawnTimer = 1
        for hoop in stage.hoops.indices {
            stage.hoops[hoop].barrier = nil
            stage.hoops[hoop].rimless = true
        }
        placeBreakerHoops(snapped: true)
    }

    /// Breaker Ball's drinks: each picked drink awake from the start and for good, as FloState wakes
    /// it elsewhere, there being no FloState here.
    public mutating func wakeBreakerDrinks() {
        guard mode == .breakerBall else { return }
        for index in players.indices {
            guard let drink = players[index].floStateDrink else { continue }
            players[index].floStateDrink = nil
            players[index].spec = Drinks.levelTwo(drink).spec(from: players[index].spec)
            if let drunk = drink.power {
                players[index].power = drunk
                players[index].powerLevel = 2
            }
        }
    }

    /// Who `index` plays against holding a Breaker Ball, for what the step does on defence.
    func breakerHolder(facing index: Int) -> Int? {
        players.indices.first { $0 != index && players[$0].hasBall }
    }

    /// The rim `player` defends: the one the other scores on.
    func breakerHoop(defendedBy player: Int) -> Int? {
        stage.hoops.indices.first { defender(of: stage.hoops[$0]) == player }
    }

    /// Each stunned body's rim over the top of their head, its backboard behind them; every other
    /// rim away off the stage.
    mutating func placeBreakerHoops(snapped: Bool = false) {
        guard mode == .breakerBall else { return }
        let top = Double(stage.rows) * Stage.tileSize - BreakerRules.wallMargin
        for index in stage.hoops.indices {
            guard !stage.hoops[index].rimless, let defender = defender(of: stage.hoops[index]) else {
                stage.hoops[index].position = HighwayRules.parked
                stage.hoops[index].velocity = .zero
                continue
            }
            let body = players[defender]
            var rim = Vec2(x: body.position.x, y: body.standingHeightTop + BreakerRules.hoopAboveHead)
            rim.x = min(max(rim.x, BreakerRules.wallMargin), stage.width - BreakerRules.wallMargin)
            rim.y = min(rim.y, top)
            stage.hoops[index].velocity = snapped ? .zero : rim - stage.hoops[index].position
            stage.hoops[index].position = rim
            stage.hoops[index].backboard = body.facing == .right ? .left : .right
        }
        let boards = stage.hoops.filter { $0.hasBackboard && !$0.rimless }.map(Match.breakerBackboard)
        stage.ballBlockers = boards
        stage.wallJumpBoards = boards
    }

    /// `victim`'s barrier worn down by `damage`, from `striker`'s hit or the stage's (nil); at nothing
    /// they're stunned as a parry stuns, which shatters it.
    mutating func wearPosture(_ victim: Int, by damage: Double, from striker: Int?, at point: Vec2) {
        guard mode == .breakerBall, damage > 0, posture.indices.contains(victim), !postureBroken[victim] else { return }
        let left = max(posture[victim] - damage, 0)
        events.append(.barrierHit(player: victim, at: point, damage: posture[victim] - left))
        posture[victim] = left
        guard left == 0 else { return }
        stunAsParried(victim, by: striker ?? players.indices.first { $0 != victim } ?? victim)
    }

    /// Every body `box` touches worn down by `damage` this frame: `owner`'s attack spares its owner, the stage's (nil) nobody.
    mutating func wearPostureTouching(_ box: Box, from owner: Int?, by damage: Double) {
        guard mode == .breakerBall else { return }
        for index in players.indices where index != owner && players[index].hurt(by: box) {
            if let owner, !reachable(index, by: owner) { continue }
            wearPosture(index, by: damage, from: owner, at: players[index].chest)
        }
    }

    /// The Elements' lava eating at every barrier that dips into it.
    mutating func lavaWearsPosture() {
        guard mode == .breakerBall, let lava = stage.features.lavaSurface else { return }
        for index in players.indices where !players[index].phantomMode && players[index].body.center.y - BreakerRules.postureRadius < lava {
            wearPosture(index, by: BreakerRules.lavaDamagePerFrame, from: nil, at: Vec2(x: players[index].position.x, y: lava))
        }
    }

    /// `index`'s barrier shattered, stunned as they are: their rim out over their head.
    mutating func shatterPosture(_ index: Int) {
        guard mode == .breakerBall, postureBroken.indices.contains(index), !postureBroken[index] else { return }
        posture[index] = 0
        postureBroken[index] = true
        events.append(.barrierShattered(player: index, at: players[index].body.center))
        holdHitStop(HitStopRules.shatterFrames)
        guard let hoop = breakerHoop(defendedBy: index) else { return }
        stage.hoops[hoop].rimless = false
        placeBreakerHoops(snapped: true)
        events.append(.breakerHoopAppeared(player: index, hoop: hoop))
    }

    /// `index`'s barrier whole again and their rim gone.
    mutating func restorePosture(_ index: Int) {
        guard mode == .breakerBall, postureBroken.indices.contains(index), postureBroken[index] else { return }
        posture[index] = BreakerRules.full
        postureBroken[index] = false
        if let hoop = breakerHoop(defendedBy: index) {
            stage.hoops[hoop].rimless = true
            // A dunker still hanging on it lets go where they are, not carried off with it.
            for player in players.indices { players[player].letGoOfRim(hoop) }
        }
        placeBreakerHoops(snapped: true)
        events.append(.barrierRestored(player: index))
    }

    /// A shattered barrier restored once its body's stun is over.
    mutating func restoreUnstunnedPostures() {
        guard mode == .breakerBall else { return }
        for index in players.indices where postureBroken.indices.contains(index) && postureBroken[index]
            && players[index].attackLockout == 0 && players[index].hitStun == 0 {
            restorePosture(index)
        }
    }

    /// `index`'s Breaker Ball let go as the ball would be by `action`, a flight of its own: true if it was.
    mutating func launchBreakerBall(_ action: PlayerAction, by index: Int) -> Bool {
        let player = players[index]
        var flying = Ball(position: player.heldBallPoint)
        let damage: Double
        switch action {
        case .releaseShot(let velocity):
            let aimed = velocity * player.spec.shotPace + stage.shotLead(by: index)
            flying.release(from: shotRelease(of: player), velocity: tutorialSnappedShot(aimed, for: index) ?? aimed, by: index,
                           straight: false, pace: player.spec.shotPace)
            flying.shotInFlight = true
            flying.scoring = true
            players[index].shotPoseFrames = shotPoseFrames(for: flying)
            damage = BreakerRules.ballShotDamage
        case .releaseThrow(let velocity):
            let reach = Vec2(x: player.position.x + player.facing.sign * 6 * player.spec.scale, y: player.position.y + BallRules.throwReleaseHeight * player.spec.scale)
            let hand = reach + stage.pushOut(Box(center: reach, width: BallRules.radius * 2, height: BallRules.radius * 2), reach: 12)
            if velocity.y > 0, velocity.x == 0 {
                flying.releaseFloater(from: player.layupReleasePoint, sideways: player.throwStanceEntrySpeed * BallRules.floaterMomentumShare, by: index)
            } else {
                flying.release(from: hand, velocity: velocity, by: index, straight: true)
                flying.throwCharge = player.throwCharge
                flying.strikes = true
            }
            damage = BreakerRules.ballThrowDamageLeast + (BreakerRules.ballThrowDamageMost - BreakerRules.ballThrowDamageLeast) * player.throwCharge
        case .dunk(let hoop):
            flying.release(from: stage.hoops[hoop].position + Vec2(x: 0, y: BallRules.radius + 2), velocity: Vec2(x: 0, y: -2), by: index, straight: false)
            flying.scoring = true
            flying.dunkShot = true
            damage = 0
        default:
            return false
        }
        breakerFlights.append(BreakerFlight(id: stampId(), owner: index, colour: index, ball: flying, damage: damage))
        return true
    }

    /// A Breaker Ball knocked out of a hand: up and loose, nobody's, bursting where it comes down.
    mutating func loseBreakerBall(from point: Vec2, colour: Int, carry: Double = 0) {
        var loose = Ball(position: point)
        loose.pop(from: point)
        loose.velocity.x = carry
        breakerFlights.append(BreakerFlight(id: stampId(), owner: nil, colour: colour, ball: loose, damage: 0))
    }

    /// The Breaker Balls a frame on: each flying as the ball flies; into a stunned body's rim, the
    /// basket; into the other's body, a hit; into anything else but glass or a rim, a burst.
    mutating func stepBreakerFlights() {
        guard mode == .breakerBall, !breakerFlights.isEmpty else { return }
        var flightStage = stage
        flightStage.extras += stage.ballBlockers + stage.ceilingSlopes.map(\.box)
        var kept: [BreakerFlight] = []
        let flying = breakerFlights.count
        for var flight in breakerFlights {
            // On a web line: straight to the puller's hands, through everything, theirs as it arrives.
            if let puller = flight.tether {
                // Caught on the line, held there till it pulls.
                if let line = players[puller].webLine, line.pullIn > 0 {
                    kept.append(flight)
                    continue
                }
                let gap = players[puller].chest - flight.ball.position
                if gap.length <= BallRules.catchRadius || players[puller].hasBall {
                    if !players[puller].hasBall {
                        players[puller].hasBall = true
                        events.append(.breakerBallCaught(player: puller, from: nil))
                    } else {
                        events.append(.breakerBallBurst(at: flight.ball.position, colour: flight.colour))
                    }
                    players[puller].webLine = nil
                } else {
                    flight.ball.velocity = gap.normalized * WebRules.pullSpeed
                    flight.ball.position += flight.ball.velocity
                    kept.append(flight)
                }
                continue
            }
            flight.frames += 1
            // Thrown, as it was before the bounce clears it, and where it was headed: off a slab it's
            // turned back before it's looked for there.
            let thrown = flight.ball.strikes
            let headed = flight.ball.position + flight.ball.velocity
            var touches: [MatchEvent] = []
            let scored = flight.ball.step(stage: flightStage, events: &touches)
            let at = flight.ball.position
            let box = flight.ball.box
            if let hoop = scored, let shooter = flight.owner, stage.hoops.indices.contains(hoop), !stage.hoops[hoop].rimless,
               stage.hoops[hoop].owner == shooter, scoreLockout == 0 {
                breakerScored(hoop, by: shooter, with: flight)
                continue
            }
            if let owner = flight.owner, let met = shieldMeets(at, radius: BallRules.radius, firedBy: owner) {
                if met.perfect {
                    // Off a perfect shield it's the shielder's, coming back.
                    flight.owner = met.owner
                    flight.colour = met.owner
                    flight.ball.lastTouched = met.owner
                    flight.ball.velocity = -flight.ball.velocity
                    kept.append(flight)
                } else {
                    events.append(.breakerBallBurst(at: at, colour: flight.colour))
                }
                continue
            }
            if let owner = flight.owner, flight.damage > 0, let other = players.indices.first(where: { $0 != owner }) {
                if players[other].boardBlocks(at, radius: BallRules.radius) {
                    events.append(.boardBlocked(player: other, at: at))
                    events.append(.breakerBallBurst(at: at, colour: flight.colour))
                    continue
                }
                if players[other].frozen == 0, !attacksPass(other, owner), reachable(other, by: owner), players[other].hurt(by: box) {
                    // Into a live snatch's side of the barrier: caught, however fast it came past the hand.
                    if !flight.ball.unstoppable, breakerSnatchLive(other, toward: at) {
                        catchBreakerBall(flight, by: other)
                        continue
                    }
                    let way: Double = flight.ball.velocity.x != 0 ? (flight.ball.velocity.x > 0 ? 1 : -1) : (players[other].position.x >= at.x ? 1 : -1)
                    // The hit's own spark is its burst.
                    strip(other, by: owner, knock: Vec2(x: BallRules.thrownHitKnock.x * way, y: BallRules.thrownHitKnock.y), flo: 0, posture: flight.damage)
                    continue
                }
            }
            let touched = touches.contains { event in
                switch event {
                case .ballBounced, .springBounced: return true
                default: return false
                }
            }
            let offGlass = touched && flightStage.backboard(at: at) != nil
            let outside = at.y < -Stage.tileSize || at.x < 0 || at.x > stage.width || at.y > Double(stage.rows + stage.skyRows) * Stage.tileSize
            let inLava = stage.features.lavaSurface.map { at.y < $0 } ?? false
            if (touched && !offGlass) || outside || inLava || flight.frames >= BreakerRules.flightFramesMost {
                events.append(.breakerBallBurst(at: at, colour: flight.colour))
                if thrown {
                    for point in [at, headed] {
                        shatterPlatforms(touching: Box(center: point, width: BallRules.radius * 2 + 2, height: BallRules.radius * 2 + 2), by: flight.owner)
                    }
                }
                continue
            }
            kept.append(flight)
        }
        // Balls knocked out of hands by these hits, loose from this frame.
        breakerFlights = kept + breakerFlights.dropFirst(flying)
    }

    /// A Breaker Ball down through the stunned body's rim: the basket, their stun over, held still a
    /// moment, then their barrier restored. The screen ends the match at the third.
    mutating func breakerScored(_ hoop: Int, by scorer: Int, with flight: BreakerFlight) {
        scoreLockout = BallRules.scoreLockoutFrames
        scores[scorer] += 1
        events.append(.scored(player: scorer, hoop: hoop, entry: flight.ball.entryVelocity, points: 1, floater: flight.ball.floaterShot, dunk: flight.ball.dunkShot))
        // The rim gone at once, so nothing scores through it again; it holds its place through the freeze, parked after.
        stage.hoops[hoop].rimless = true
        for player in players.indices { players[player].letGoOfRim(hoop) }
        guard let scoredOn = defender(of: stage.hoops[hoop]) else { return }
        // The stun over as the freeze ends, held hurt through it: the barrier's restored then (`restoreUnstunnedPostures`).
        players[scoredOn].hitStun = min(players[scoredOn].hitStun, 1)
        players[scoredOn].attackLockout = 1
        events.append(.scoredOnFreeze(player: scoredOn))
        holdHitStop(BreakerRules.scoredOnFreezeFrames)
    }

    /// `index`'s snatch live, its hand toward `point`.
    func breakerSnatchLive(_ index: Int, toward point: Vec2) -> Bool {
        let player = players[index]
        guard player.snatchHitbox != nil || player.snatchSteppingThrough, !player.snatchSpent, !player.holding else { return false }
        return (point.x - player.position.x) * player.facing.sign >= -1
    }

    /// A Breaker Ball snatched out of the air by `index`: theirs, and its thrower hit for it.
    mutating func catchBreakerBall(_ flight: BreakerFlight, by index: Int) {
        players[index].snatchSpent = true
        players[index].hasBall = true
        events.append(.breakerBallCaught(player: index, from: flight.owner))
        guard let thrower = flight.owner else { return }
        let way: Double = players[thrower].position.x >= players[index].position.x ? 1 : -1
        strip(thrower, by: index, knock: Vec2(x: BallRules.thrownHitKnock.x * way, y: BallRules.thrownHitKnock.y), flo: 0,
              posture: BreakerRules.catchDamage)
    }

    /// Breaker Ball's snatch: any Breaker Ball not the snatcher's own out of the air, its thrower hit
    /// for it as a catch puts a dodgeball thrower out; or the other's out of their hands. Either's
    /// the snatcher's from then, in their energy.
    mutating func snatchBreakerBalls(by index: Int) {
        let player = players[index]
        guard mode == .breakerBall, player.snatchHitbox != nil || player.snatchSteppingThrough, !player.snatchSpent, !player.holding else { return }
        let stepping = player.snatchSteppingThrough
        func reaches(_ box: Box) -> Bool { player.snatchReaches(box: box) || (stepping && box.overlaps(player.body)) }
        func faces(_ point: Vec2, onBody: Bool) -> Bool { (point.x - player.position.x) * player.facing.sign >= -1 || onBody }
        // A full charge's, as a full charge's ball is, nobody's but its thrower's.
        if let number = breakerFlights.indices.first(where: { number in
            let flight = breakerFlights[number]
            return flight.owner != index && !flight.ball.unstoppable && faces(flight.ball.position, onBody: stepping && flight.ball.box.overlaps(player.body))
                && reaches(flight.ball.box)
        }) {
            catchBreakerBall(breakerFlights.remove(at: number), by: index)
            return
        }
        guard let other = players.indices.first(where: { $0 != index }), players[other].hasBall, players[other].state != .stepback,
              reachable(other, by: index) else { return }
        let held = players[other].ballInHand(on: stage) ?? players[other].heldBallPoint
        let onBody = player.body.overlaps(players[other].body)
        guard faces(held, onBody: onBody),
              reaches(Box(center: held, width: BallRules.radius * 2, height: BallRules.radius * 2)) || reaches(players[other].body) else { return }
        players[index].snatchSpent = true
        players[other].snatchSpent = true
        players[other].loseBall()
        players[other].hitStun = BallRules.hitStunFrames
        players[index].hasBall = true
        events.append(.stolen(player: index, from: other))
        holdHitStop(HitStopRules.hitFrames)
    }
}
