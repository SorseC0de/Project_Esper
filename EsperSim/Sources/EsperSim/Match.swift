import Foundation

/// A slab a player made. Solid to everyone until it dissipates.
public struct Platform: Equatable {
    public var owner: Int
    public var box: Box
    public var framesLeft: Int
}

/// The whole game, one value. `advance` is the only way it changes.
public struct Match: Equatable {
    public var stage: Stage
    public var players: [Player]
    public var ball: Ball
    public var platforms: [Platform] = []
    /// What the powers leave in the world.
    public var bolts: [Bolt] = []
    public var clones: [IceClone] = []
    /// Gale Ale's tornados.
    public var gales: [Gale] = []
    /// Z Tea's beams while they fire.
    public var beams: [Beam] = []
    public var flames: [Flame] = []
    public var fireballs: [Fireball] = []
    /// The next id for anything the powers leave, so the screen can follow each one.
    public var nextId = 1
    /// The football field's helmets and portal, the clock to the next helmet, and the
    /// dice they roll on; a warp can't repeat for a few frames.
    public var helmets: [Helmet] = []
    public var portal: Portal?
    public var helmetClock = 0
    public var portalCooldown = 0
    public var fieldDice: Dice
    /// Highway Traffic's cars and helicopter, and which rim the last one carried.
    public var cars: [Car] = []
    public var helicopter: Helicopter?
    /// Wetshot Wake's Hoopfish, swimming across with the ball or the rim on its antenna.
    public var hoopfish: Hoopfish?
    public var lastHelicopterHoop: Int?
    public var scores: [Int]
    /// Rounds reset on a point; 47 plays on through its baskets.
    public var mode = GameMode.rounds
    public var frame = 0
    /// The count before play: frames in which nobody moves or acts, at the start and after
    /// every point, and how long that is.
    public var countdown: Int
    public let countdownLength: Int
    /// A point waiting to restart, after a dunk: frames left with the dunker on the rim,
    /// and whose hands the ball then goes to, nobody's for a decider, in neutral.
    public var restartIn = 0
    public var restartBallTo: Int? = 0
    /// Frames left in which no point counts, after one has.
    public var scoreLockout = 0
    /// Frames left of hit-stop: while it runs the match is held, nothing moves or counts down.
    public var hitStop = 0
    /// What happened on the last `advance`.
    public var events: [MatchEvent] = []
    /// The winning bucket's been made: no inputs and no catches from here, set by the
    /// series when it confirms the point.
    public var finished = false

    /// `seed` drives the field's dice and, on a stage that starts held, the coin flip for
    /// who has the ball; both sides of a network match pass the same one.
    public init(stage: Stage = .court, specs: [FighterSpec] = [.baseline, .baseline], countdown: Int = 0, seed: UInt32 = 1,
                mode: GameMode = .rounds) {
        self.stage = stage
        self.mode = mode
        players = specs.indices.map { index in
            Player(spec: specs[index], index: index, position: stage.playerSpawns[index], facing: stage.playerFacings[index])
        }
        ball = Ball(position: stage.ballSpawn)
        scores = Array(repeating: 0, count: specs.count)
        countdownLength = countdown
        self.countdown = countdown
        fieldDice = Dice(seed: seed)
        if let fish = stage.hoopfishStart {
            hoopfish = Hoopfish.starting(at: fish, on: stage, countdown: countdown)
            placeHoopfishLoad()
        }
        if stage.features.traffic {
            fillTraffic()
            for index in players.indices { players[index].position = spawnPoint(index) }
        }
        if stage.features.startsHeld, !players.isEmpty {
            let holder = fieldDice.roll(players.count)
            players[holder].hasBall = true
            ball.holder = holder
            ball.position = players[holder].heldBallPoint
        }
    }

    mutating func stampId() -> Int {
        defer { nextId += 1 }
        return nextId
    }

    public mutating func advance(inputs given: [PlayerInput]) {
        frame += 1
        events = []
        if scoreLockout > 0 { scoreLockout -= 1 }
        if hitStop > 0 {
            hitStop -= 1
            return
        }
        if restartIn > 0 {
            restartIn -= 1
            if restartIn == 0 { restart(ballTo: restartBallTo) }
        }
        // Once the match is won nobody moves: no inputs, the computer's among them.
        let inputs = countdown > 0 || finished ? [] : given
        if countdown > 0 { countdown -= 1 }

        // Platforms count down and go; the stage carries the ones standing.
        platforms = platforms.compactMap { platform in
            platform.framesLeft > 1 ? Platform(owner: platform.owner, box: platform.box, framesLeft: platform.framesLeft - 1) : nil
        }
        refreshExtras()
        if portalCooldown > 0 { portalCooldown -= 1 }
        stepField()
        stepTornados()
        stepHoopfish()
        stepStageFireball()
        stepLightning()
        stepIcicles()

        for index in players.indices {
            let input = index < inputs.count ? inputs[index] : .idle
            players[index].speedShare = (ball.holder != nil && ball.holder != index ? DefenceRules.speedShare : 1)
                * (players[index].power == .surfSoda ? SurfRules.speedShare : 1)
            let opponentX = players.indices.first { $0 != index }.map { players[$0].position.x }
            guard let action = players[index].step(input: input, stage: stage, opponentX: opponentX,
                                                   ballHolder: ball.holder, ballOwner: ball.isLive ? ball.owner : nil,
                                                   events: &events) else { continue }
            perform(action, by: index)
        }
        burnInLava()
        burnDribbles()
        resolveParries()
        for index in players.indices {
            resolveHits(by: index)
        }
        stepBolts()
        stepClones()
        stepGales()
        stepBeams()
        stepFlames()
        stepFireballs()

        for index in players.indices where players[index].webLine?.target == .opponent {
            let other = players.indices.first { $0 != index }
            if let other, players[other].state != .webbed { players[index].webLine = nil }
        }
        snagWithLingeringLines()
        reelBall()

        if ball.frozen > 0 {
            // Frost Tea: the ball hangs where it is, but a hand can still take it.
            ball.frozen -= 1
            if ball.isLive { tryCatch() }
        } else if hoopfish?.carrying == .ball, ball.isLive {
            // On the Hoopfish's antenna, where a hand can take it off.
            tryCatch()
            if ball.holder != nil { hoopfish?.carrying = .nothing }
        } else if ball.isLive, ball.tether == nil {
            // The ball sees the stage's ball-only solids as well.
            var ballStage = stage
            ballStage.extras += stage.ballBlockers + stage.ceilingSlopes.map(\.box)
            if let hoop = ball.step(stage: ballStage, events: &events), scoreLockout == 0 {
                // A few frames after a point no other counts: a rim on the move can take the
                // same ball through twice.
                scoreLockout = BallRules.scoreLockoutFrames
                // A shared rim's point goes to whoever put the ball through.
                let owner = stage.hoops[hoop].shared ? (ball.lastTouched ?? stage.hoops[hoop].owner) : stage.hoops[hoop].owner
                if mode == .fortySeven {
                    // 47: the points by where the ball left a hand, and play on, the scorer
                    // kept off the ball a while.
                    let points = FortySevenRules.points(from: ball.launchPoint, through: stage.hoops[hoop], on: stage) * pointValue
                    scores[owner] += points
                    events.append(.scored(player: owner, hoop: hoop, entry: ball.velocity, points: points, floater: ball.floaterShot))
                    players[owner].gainFlo(FloRules.madeShot, at: stage.hoops[hoop].position, events: &events)
                    holdHitStop(HitStopRules.shotFrames)
                    players[owner].pickupLockout = FortySevenRules.scorerLockoutFrames
                    ball.launchPoint = nil
                    // Through the net it's nobody's shot any more: anyone but the scorer can take it.
                    ball.shotInFlight = false
                    ball.owned = false
                } else {
                    scores[owner] += 1
                    // Level after a point, the next is the stage's decider: it starts from the ball in
                    // neutral rather than in the hands of whoever was just scored on.
                    let tiedDecider = scores[0] == scores[1]
                    events.append(.scored(player: owner, hoop: hoop, entry: ball.velocity, points: 1, floater: ball.floaterShot))
                    players[owner].gainFlo(FloRules.madeShot, at: stage.hoops[hoop].position, events: &events)
                    holdHitStop(HitStopRules.shotFrames)
                    if let other = players.indices.first(where: { $0 != owner }) {
                        if players.contains(where: { $0.state == .dunking }) {
                            // A dunk: the dunker hangs on the rim a beat, the ball dead, then the restart.
                            restartIn = BallRules.dunkHangFrames
                            restartBallTo = tiedDecider ? nil : other
                            ball.respawnTimer = BallRules.dunkHangFrames + 5
                        } else {
                            // The point restarts once the hit-stop's held the ball in the net.
                            restartIn = 1
                            restartBallTo = tiedDecider ? nil : other
                        }
                    }
                    return
                }
            }
            strikeWithThrow()
            tryCatch()
            keepBallInWorld()
        } else if ball.respawnTimer > 0 {
            ball.velocity.y = max(ball.velocity.y - BallRules.gravity, -BallRules.fallSpeed)
            ball.position += ball.velocity
            ball.respawnTimer -= 1
            if ball.respawnTimer == 0 {
                ball.respawn(at: stage.ballSpawn)
                events.append(.ballRespawned)
            }
        }

        if let holder = ball.holder {
            ball.position = players[holder].heldBallPoint
            ball.velocity = .zero
        }
    }

    /// After a point: everyone back to their spawn as they began, the ball in `holder`'s
    /// hands, or loose where it starts with no holder (in neutral), any slab gone, and the count again.
    public mutating func restart(ballTo holder: Int?) {
        for index in players.indices {
            let was = players[index]
            players[index] = Player(spec: was.spec, index: index, position: spawnPoint(index), facing: stage.playerFacings[index])
            players[index].power = was.power
            players[index].powerLevel = was.powerLevel
            players[index].flo = was.flo
        }
        platforms = []
        refreshExtras()
        bolts = []
        clones = []
        flames = []
        fireballs = []
        helmets = []
        helmetClock = 0
        ball.respawn(at: stage.ballSpawn)
        if let holder {
            players[holder].hasBall = true
            ball.holder = holder
            ball.position = players[holder].heldBallPoint
        } else if hoopfish != nil {
            // In neutral on Wetshot Wake is back on the Hoopfish's antenna.
            hoopfish?.carrying = .ball
            placeHoopfishLoad()
        }
        countdown = countdownLength
    }

    private mutating func perform(_ action: PlayerAction, by index: Int) {
        let player = players[index]
        switch action {
        case .releaseShot(let velocity):
            // Cannon Cola's pace: the same arc run through that many times faster.
            ball.release(from: player.position + Vec2(x: 0, y: BallRules.shotReleaseHeight * player.spec.scale),
                         velocity: velocity * player.spec.shotPace, by: index, straight: false, pace: player.spec.shotPace)
            ball.shotInFlight = true
            ball.scoring = true
            ball.burning = player.power == .blazingBoba
        case .releaseThrow(let velocity):
            // The hand, pushed out of any wall the body is pressed against.
            let reach = Vec2(x: player.position.x + player.facing.sign * 6 * player.spec.scale, y: player.position.y + BallRules.throwReleaseHeight * player.spec.scale)
            let hand = reach + stage.pushOut(Box(center: reach, width: BallRules.radius * 2, height: BallRules.radius * 2), reach: 12)
            if velocity.y > 0, velocity.x == 0 {
                ball.releaseFloater(from: Vec2(x: player.position.x, y: player.position.y + BallRules.shotReleaseHeight * player.spec.scale),
                                    sideways: player.throwStanceEntrySpeed * BallRules.floaterMomentumShare, by: index)
            } else {
                ball.release(from: hand, velocity: velocity, by: index, straight: true)
                ball.strikes = true
            }
            ball.burning = player.power == .blazingBoba
        case .releaseFireball(let velocity, let straight, let ballArc):
            let hand = Vec2(x: player.position.x + player.facing.sign * 6 * player.spec.scale, y: player.position.y + BallRules.throwReleaseHeight * player.spec.scale)
            if ballArc {
                // A quick shot's fireball takes the quick shot's preset arc, light as it is.
                fireballs.append(Fireball(id: stamp(), owner: index, position: player.position + Vec2(x: 0, y: BallRules.shotReleaseHeight * player.spec.scale),
                                          velocity: velocity, framesLeft: BlazeRules.fireballFrames, straight: false, ballArc: true))
            } else {
                fireballs.append(Fireball(id: stamp(), owner: index, position: hand, velocity: velocity * BlazeRules.fireballSpeedShare,
                                          framesLeft: BlazeRules.fireballFrames, straight: straight))
            }
            events.append(.fireballThrown(player: index))
        case .quake:
            quake(by: index)
        case .fireBolt(let direction):
            bolts.append(Bolt(id: stamp(), owner: index, position: player.chest + direction * 6, velocity: direction * ZeusRules.boltSpeed,
                              framesLeft: ZeusRules.boltFrames))
            events.append(.boltFired(player: index))
        case .strikeBolt(let x, let bottom):
            strike(x: x, bottom: bottom, by: index)
        case .fireBeam:
            beams.append(Beam(id: stamp(), owner: index, origin: player.beamOrigin, direction: player.beamDirection, framesLeft: ZRules.fireFrames))
            events.append(.beamFired(player: index, from: player.beamOrigin, direction: player.beamDirection))
        case .zBurst:
            let centre = player.body.center
            for other in players.indices where other != index && players[other].body.distance(to: centre) <= ZRules.burstRadius {
                let away = players[other].body.center - centre
                let direction = away.length > 0.01 ? away * (1 / away.length) : Vec2(x: player.facing.sign, y: 0)
                strip(other, by: index, knock: direction * ZRules.burstBodyPush + Vec2(x: 0, y: 1), stun: false)
            }
            if ball.isLive, ball.position.distance(to: centre) <= ZRules.burstRadius + BallRules.radius {
                let away = ball.position - centre
                let direction = away.length > 0.01 ? away * (1 / away.length) : Vec2(x: player.facing.sign, y: 0)
                ball.tornadoCentre = nil
                ball.release(from: ball.position, velocity: direction * ZRules.burstBallPush, by: index, straight: false)
            }
            events.append(.zBurst(player: index, at: centre))
        case .makeGale:
            // Under the feet it jumped from, the jumper let rise clear before it can hold them.
            let size = GaleRules.size
            let box = Box(center: player.position - Vec2(x: 0, y: size.y / 2), width: size.x, height: size.y)
            gales.append(Gale(id: stamp(), owner: index, box: box, velocity: .zero, framesLeft: GaleRules.stillFrames, snatching: false))
            players[index].tornadoCooldown = TornadoRules.jumpOutCooldownFrames
            events.append(.galeMade(at: box.center, snatching: false))
        case .sendGale(let hand, let heading):
            let size = GaleRules.size
            let box = Box(center: hand, width: size.x, height: size.y)
            gales.append(Gale(id: stamp(), owner: index, box: box, velocity: Vec2(x: heading.sign * GaleRules.snatchSpeed, y: 0),
                              framesLeft: GaleRules.snatchFrames, snatching: true))
            events.append(.galeMade(at: box.center, snatching: true))
        case .leaveClone:
            clones.append(IceClone(id: stamp(), owner: index, box: player.body, framesLeft: FrostRules.cloneFrames))
            events.append(.cloneMade(player: index, at: player.position))
        case .leaveFlame:
            let box = Box(min: Vec2(x: player.position.x - BlazeRules.flameWidth / 2, y: player.position.y),
                          max: Vec2(x: player.position.x + BlazeRules.flameWidth / 2, y: player.position.y + BlazeRules.flameHeight))
            flames.append(Flame(id: stamp(), owner: index, box: box, framesLeft: BlazeRules.flameFrames))
            events.append(.flameLeft(player: index, at: player.position))
        case .pulse(let pull):
            pulse(by: index, pull: pull)
        case .snipe(let at, let pull):
            snipe(by: index, at: at, pull: pull)
        case .dunk(let hoop) where hoopfish != nil:
            // No dunking the Hoopfish: at the slam it spins, rim and all, and the ball drops
            // out through where the rim was, no point, the dunker let go.
            hoopfish?.spin = HoopfishRules.spinFrames
            placeHoopfishLoad()
            ball.release(from: player.heldBallPoint, velocity: Vec2(x: 0, y: -1), by: index, straight: false)
            ball.steers = false
            players[index].grounded = false
            players[index].enter(.air)
            events.append(.hoopfishSpun)
        case .dunk(let hoop):
            // Its bottom just over the rim, so it comes down through it.
            ball.release(from: stage.hoops[hoop].position + Vec2(x: 0, y: BallRules.radius + 2), velocity: Vec2(x: 0, y: -2), by: index, straight: false)
            ball.scoring = true
        case .webLine(let direction):
            webLine(from: index, direction: direction)
        case .makePlatform:
            // A slab under the feet as they are after this frame's fall, rounded down so the
            // body stands on it rather than in it; centred, a tile thick, for a second.
            let top = player.position.y.rounded(.down)
            let box = Box(min: Vec2(x: player.position.x - ShakeRules.platformWidth / 2, y: top - ShakeRules.platformThickness),
                          max: Vec2(x: player.position.x + ShakeRules.platformWidth / 2, y: top))
            make(box, by: index)
        case .makeWall:
            // A wall just in front of the body, from the feet up, rounded down to sit on
            // whatever the feet are on.
            let bottom = player.position.y.rounded(.down)
            let near = player.position.x + player.facing.sign * (player.spec.bodyWidth / 2 + 2)
            let far = near + player.facing.sign * ShakeRules.wallWidth
            let box = Box(min: Vec2(x: min(near, far), y: bottom), max: Vec2(x: max(near, far), y: bottom + ShakeRules.wallHeight))
            make(box, by: index, wall: true)
        case .flash(let direction):
            // Five tiles along the stick, or in place, nudged clear of solids. The flashes
            // are tears: the ball is pulled into the hands from where it came out for a
            // while after, and the other holding the ball with their body within reach of
            // either end loses it.
            let from = player.position
            players[index].warp(to: from + direction * FizzRules.flashDistance, in: stage)
            let to = players[index].position
            events.append(.flashed(player: index, from: from, to: to))
            players[index].tear = Tear(position: players[index].chest, framesLeft: FizzRules.tearFrames)
            if let other = players.indices.first(where: { $0 != index }), players[other].hasBall {
                let body = players[other].body
                let chestHeight = BallRules.chestHeight * player.spec.scale
                let ends = [from + Vec2(x: 0, y: chestHeight), to + Vec2(x: 0, y: chestHeight)]
                if ends.contains(where: { body.distance(to: $0) <= FizzRules.tearRadius }) {
                    pop(from: other, by: index)
                }
            }
        case .warpToBall:
            let from = player.position
            if let overhang = player.pendingWarp {
                // Down to the dribbled ball, keeping it.
                players[index].pendingWarp = nil
                let feet = Vec2(x: overhang.x, y: overhang.y - BallRules.radius)
                players[index].warp(to: feet, in: stage)
                events.append(.warped(player: index, from: from, to: players[index].position))
                return
            }
            guard ball.isLive else { return }
            let feet = Vec2(x: ball.position.x, y: ball.position.y - BallRules.chestHeight * player.spec.scale)
            players[index].warp(to: feet, in: stage)
            events.append(.warped(player: index, from: from, to: players[index].position))
            hand(ballTo: index)
        }
    }

    private mutating func stamp() -> Int { stampId() }

    /// A slab or a wall, solid for a second. A slab disarms its maker until the next jump
    /// and starts the slab's cooldown; a wall starts only its own cooldown.
    private mutating func make(_ box: Box, by index: Int, wall: Bool = false) {
        platforms.append(Platform(owner: index, box: box, framesLeft: ShakeRules.platformFrames))
        if wall {
            players[index].wallCooldown = ShakeRules.cooldownFrames
        } else {
            players[index].platformArmed = false
            players[index].platformCooldown = ShakeRules.cooldownFrames
        }
        refreshExtras()
        events.append(.platformMade(player: index))
    }

    /// The slide's leg and the slash's blade knock the ball out of the other's hands, the
    /// blade swats a loose ball away, the snatch takes any ball it reaches while the body
    /// faces it, loose or in the other's hands, and a flash's tear pulls a loose ball in.
    private mutating func resolveHits(by index: Int) {
        let player = players[index]
        let other = players.indices.first { $0 != index }
        if let tear = player.tear, ball.isLive, ball.position.distance(to: tear.position) <= FizzRules.tearRadius {
            players[index].tear = nil
            hand(ballTo: index)
        }
        // Titan Tea at level two: running or dashing into the other strips them, once a contact.
        if player.power == .titanTea, player.powerLevel >= 2, let other {
            let touching = player.body.overlaps(players[other].body)
            if touching, !player.trampling, player.grounded, player.state == .run || player.state == .dash, players[other].frozen == 0 {
                strip(other, by: index, knock: nil)
            }
            players[index].trampling = touching
        }
        if let leg = player.slideHitbox, let other, players[other].hasBall, players[other].grounded, players[other].body.overlaps(leg) {
            players[index].slideHit = true
            pop(from: other, by: index)
        } else if let leg = player.slideHitbox, let other, !players[other].hasBall, players[other].frozen == 0,
                  players[other].hitStun == 0, players[other].body.overlaps(leg) {
            // Without the ball the leg stuns, as every other attack does.
            players[index].slideHit = true
            strip(other, by: index, knock: nil)
        }
        if let blade = player.slashHitbox {
            // Clear of the floor the body stands on, the blade in a wall clanks, once a swing.
            if player.reached(SlashRules.liveFrames.lowerBound) {
                let clear = Box(min: Vec2(x: blade.min.x, y: max(blade.min.y, player.position.y + 1)), max: blade.max)
                if stage.overlapsSolid(clear) { events.append(.slashClanked(player: index)) }
            }
            if let other, players[other].body.overlaps(blade), players[other].frozen == 0 {
                // The body, ball or no ball: stripped and knocked along the swing.
                players[index].slashHit = true
                // The ball pops back to the slasher, away from the one who had it, coming down
                // on them where they'll be once their swing's slide is done.
                let from = players[other].chest.x
                let landing = player.position.x + player.slashSlide(over: BallRules.popAloftFrames)
                let carry = (landing - from) / Double(BallRules.popAloftFrames)
                strip(other, by: index, knock: Vec2(x: SlashRules.knock.x * player.facing.sign, y: SlashRules.knock.y),
                      carry: carry)
            } else if ball.isLive, ball.box.overlaps(blade) {
                // Down and away at about the spike angle, jittered a little by the frame.
                players[index].slashHit = true
                let noise = Double((frame &* 1103515245 &+ 12345) & 0xFFFF) / 65535 * 2 - 1
                let angle = SlashRules.spikeAngle + SlashRules.spikeJitter * noise
                ball.swat(along: Vec2(x: Trig.cos(angle) * player.facing.sign, y: Trig.sin(angle)), by: index)
                events.append(.swatted(player: index, hit: true))
            }
        }
        if player.snatchHitbox != nil {
            // A stepback's ball can't be snatched.
            let held = ball.holder.flatMap { $0 == index || players[$0].state == .stepback ? nil : $0 }
            // A held ball is where the holder's sheet draws it this frame, so the hand can
            // take it off the dribble; failing a landmark, the chest.
            let at = held.map { holder -> Vec2 in
                players[holder].ballInHand(on: stage) ?? players[holder].heldBallPoint
            } ?? ball.position
            // In front, or a holder the body itself overlaps: the body is part of the reach.
            let onTheBody = held.map { player.body.overlaps(players[$0].body) } ?? false
            let facingIt = (at.x - player.position.x) * player.facing.sign >= -1 || onTheBody
            // A burning ball is the thrower's alone.
            let allowed = (!ball.burning || ball.lastTouched == index || held != nil) && (held != nil || player.pickupLockout == 0)
            if player.power == .frostTea, let other, players[other].frozen == 0, players[other].state != .stepback,
               player.snatchReaches(box: players[other].body),
               (players[other].body.center.x - player.position.x) * player.facing.sign >= -1 || players[other].body.overlaps(player.body) {
                // Frost Tea's upgrade, on the snatch's own reach: the body it reaches is frozen
                // where it stands, and stripped.
                strip(other, by: index, knock: nil)
                freeze(other)
            } else if facingIt, allowed, player.snatchReaches(ballAt: at) || (held.map { player.snatchReaches(box: players[$0].body) } ?? false),
                      held != nil || ball.isLive {
                players[index].gainFlo(FloRules.snatch, at: at, events: &events)
                if let held {
                    players[held].loseBall()
                    players[held].hitStun = BallRules.hitStunFrames
                    holdHitStop(HitStopRules.hitFrames)
                    if player.power == .frostTea { freeze(held) }
                }
                if held == nil, player.power == .frostTea {
                    // Frost Tea's snatch freezes a loose ball rather than taking it; a
                    // hand, anyone's, can still pick the frozen ball up.
                    if ball.frozen == 0 {
                        ball.frozen = FrostRules.freezeFrames
                        events.append(.ballFrozen)
                    }
                } else {
                    hand(ballTo: index)
                }
            }
        }
    }

    /// A snatch's reach, or a throw stance in its opening frames, meeting a live blade: the
    /// slasher is the one stripped and knocked back, and the blade is spent. Before the
    /// blades are resolved, so it wins.
    private mutating func resolveParries() {
        for index in players.indices {
            guard let other = players.indices.first(where: { $0 != index }), let blade = players[other].slashHitbox else { continue }
            let reaches = players[index].snatchHitbox != nil ? players[index].snatchReaches(box: blade)
                : players[index].throwParrying && blade.overlaps(players[index].body)
            guard reaches else { continue }
            players[other].slashHit = true
            let away = players[other].position.x >= players[index].position.x ? 1.0 : -1.0
            strip(other, by: index, knock: Vec2(x: SnatchRules.parryKnock.x * away, y: SnatchRules.parryKnock.y))
            events.append(.parried(player: other, by: index))
            players[index].gainFlo(FloRules.counter, at: players[other].chest, events: &events)
            holdHitStop(HitStopRules.counterFrames)
        }
    }

    /// The ball knocked out of `victim`'s hands: it pops straight up, nobody's, and the
    /// victim is stunned, so the popper has first go at it.
    /// `carry`: sideways speed for the ball: a slash sends it back toward the slasher.
    private mutating func pop(from victim: Int, by popper: Int, carry: Double = 0) {
        let from = players[victim].heldBallPoint
        players[victim].loseBall()
        players[victim].hitStun = BallRules.hitStunFrames
        ball.pop(from: from)
        ball.velocity.x = carry
        events.append(.popped(player: victim, by: popper))
        players[popper].gainFlo(FloRules.pop, at: from, events: &events)
        holdHitStop(HitStopRules.hitFrames)
    }

    /// The lava: whoever's feet are under its surface goes back to where they started, the
    /// ball they held back to its own start; a loose ball in it goes back too. For now.
    private mutating func burnInLava() {
        guard let surface = stage.features.lavaSurface else { return }
        for index in players.indices where players[index].position.y < surface {
            events.append(.lavaSplashed(at: Vec2(x: players[index].position.x, y: surface), ball: false))
            burn(index)
        }
        if ball.holder == nil, ball.isLive, ball.position.y < surface {
            events.append(.lavaSplashed(at: Vec2(x: ball.position.x, y: surface), ball: true))
            ball.respawn(at: stage.ballSpawn)
        }
    }

    /// On a lava stage, a dribble bouncing down off a ledge into the lava loses the ball to it,
    /// back to where it starts, as a loose ball falling in does.
    private mutating func burnDribbles() {
        guard let lava = stage.features.lavaSurface, let holder = ball.holder else { return }
        let player = players[holder]
        let frame = player.animationFrame
        guard player.grounded, Animation.dribbles.contains(frame.animation), frame.animation.dribbleBounceFrames().contains(frame.frame),
              let offset = BallLandmarks.offset(frame) else { return }
        let ballX = player.position.x + offset.x / 1.6 * player.spec.scale * player.facing.sign
        guard player.position.y - stage.drop(fromX: ballX, y: player.position.y) < lava else { return }
        players[holder].loseBall()
        ball.holder = nil
        events.append(.lavaSplashed(at: Vec2(x: ballX, y: lava), ball: true))
        ball.respawn(at: stage.ballSpawn)
    }

    /// The Hoopfish a frame on, and its load with it: the rim where its antenna is, or parked
    /// when it isn't carrying it; the ball held there until a hand takes it.
    private mutating func stepHoopfish() {
        guard var fish = hoopfish else { return }
        fish.step(on: stage)
        hoopfish = fish
        placeHoopfishLoad()
        // A rim swimming into the stage's first or last column, or gone, lets go of whoever's hanging on it.
        if !stage.dunkable(stage.hoops[0]) {
            for index in players.indices where players[index].state == .dunking && players[index].dunkHoop == 0 {
                players[index].enter(players[index].grounded ? .idle : .air)
            }
        }
    }

    private mutating func placeHoopfishLoad() {
        guard let fish = hoopfish, !stage.hoops.isEmpty else { return }
        // Spinning, the rim spins with it, out of play.
        stage.hoops[0].position = fish.carrying == .hoop && !fish.away && fish.spin == 0 ? fish.antenna : HighwayRules.parked
        stage.hoops[0].backboard = fish.facesRight ? .left : .right
        if fish.carrying == .ball, ball.holder == nil {
            ball.position = fish.ballPoint
            ball.velocity = .zero
        }
    }

    /// What a 47 basket's points are multiplied by on this stage.
    var pointValue: Int { stage.features.doublePoints ? 2 : 1 }

    /// Where a player starts: the stage's spot, lifted onto whatever stands there, such as a car.
    func spawnPoint(_ index: Int) -> Vec2 {
        var at = stage.playerSpawns[index]
        let spec = players[index].spec
        for _ in 0..<8 {
            let body = Box(min: Vec2(x: at.x - spec.bodyWidth / 2, y: at.y), max: Vec2(x: at.x + spec.bodyWidth / 2, y: at.y + spec.bodyHeight))
            guard let top = stage.extras.filter({ $0.overlaps(body) }).map(\.max.y).max() else { break }
            at.y = top
        }
        return at
    }

    /// Burned, by the lava or a fire tornado: back to the start, the ball it held back to its own.
    private mutating func burn(_ index: Int) {
        let was = players[index]
        players[index] = Player(spec: was.spec, index: index, position: spawnPoint(index), facing: stage.playerFacings[index])
        players[index].power = was.power
        players[index].powerLevel = was.powerLevel
        players[index].flo = was.flo
        events.append(.lavaBurned(player: index))
        if ball.holder == index {
            ball.holder = nil
            ball.respawn(at: stage.ballSpawn)
        }
    }

    /// Where the stage's tornados are this frame: up, or on the way down into the lava or back.
    public var tornadoBoxes: [Box] {
        let share = TornadoRules.sunkShare(at: frame)
        return stage.tornados.map { box in
            let drop = (TornadoRules.sunkBottom - box.min.y) * share
            return Box(min: Vec2(x: box.min.x, y: box.min.y + drop), max: Vec2(x: box.max.x, y: box.max.y + drop))
        }
    }

    /// A regular tornado that's up or rising takes whoever comes into it out of the air, and
    /// the loose ball, and holds them; bursting, it lets them go. A fire one burns whoever it touches.
    private mutating func stepTornados() {
        // The Elements' tornados while they hold, then Gale Ale's still ones, which never burn.
        let stageBoxes = !stage.tornados.isEmpty && TornadoRules.holds(at: frame) ? tornadoBoxes : []
        let fire = !stage.tornados.isEmpty && TornadoRules.isFire(at: frame)
        let boxes = stageBoxes + gales.filter { !$0.snatching }.map(\.box)
        guard !boxes.isEmpty || players.contains(where: { $0.state == .suspended }) || ball.tornadoCentre != nil else { return }
        func burns(_ box: Int) -> Bool { fire && box < stageBoxes.count }
        // The ball is taken coming in from outside, not let go of inside one, as a shot from a
        // body held there is.
        let ballFree = ball.isLive && ball.tether == nil && ball.frozen == 0
        let ballBox = ballFree ? boxes.firstIndex(where: { $0.overlaps(ball.box) }) : nil
        let ballIn = ballBox.map { boxes[$0].center }
        ball.tornadoCentre = ballBox.map(burns) == true || (ball.tornadoCentre == nil && !ball.outsideTornados) ? nil : ballIn
        ball.outsideTornados = ballFree && ballIn == nil
        for index in players.indices {
            let body = players[index].body
            guard let hit = boxes.firstIndex(where: { $0.overlaps(body) }) else {
                if players[index].state == .suspended { players[index].enter(.air) }
                continue
            }
            // Blazing Boba is at home in a fire one.
            if burns(hit), players[index].power != .blazingBoba {
                events.append(.tornadoBurned(at: players[index].body.center))
                burn(index)
            } else if players[index].state == .suspended {
                players[index].tornadoCentre = boxes[hit].center
            } else if players[index].state == .air, players[index].tornadoCooldown == 0 {
                players[index].enter(.suspended)
                players[index].fastFalling = false
                players[index].jumpsLeft = players[index].spec.jumps
                players[index].tornadoCentre = boxes[hit].center
            }
        }
    }

    /// Z Tea's beams a frame on: whoever and whatever is along one met once, stripped and sent
    /// along it; gone when the firing ends.
    private mutating func stepBeams() {
        guard !beams.isEmpty else { return }
        var kept: [Beam] = []
        for var beam in beams {
            beam.framesLeft -= 1
            guard beam.framesLeft > 0, players.indices.contains(beam.owner), players[beam.owner].firingBeam else { continue }
            // Turned as the firer turns it.
            beam.origin = players[beam.owner].beamOrigin
            beam.direction = players[beam.owner].beamDirection
            func along(_ box: Box) -> Bool {
                let reach = Box(min: box.min - Vec2(x: ZRules.halfThickness, y: ZRules.halfThickness),
                                max: box.max + Vec2(x: ZRules.halfThickness, y: ZRules.halfThickness))
                var travelled = 0.0
                while travelled <= ZRules.length {
                    if reach.contains(beam.origin + beam.direction * travelled) { return true }
                    travelled += 4
                }
                return false
            }
            if !beam.hitPlayer, let victim = players.indices.first(where: { $0 != beam.owner && along(players[$0].body) }) {
                beam.hitPlayer = true
                let held = players[victim].hasBall
                strip(victim, by: beam.owner, knock: beam.direction * ZRules.bodyKnock + Vec2(x: 0, y: ZRules.bodyLift))
                if held, ball.holder == nil {
                    beam.hitBall = true
                    ball.release(from: ball.position, velocity: beam.direction * ZRules.ballSpeed, by: beam.owner, straight: false)
                }
            }
            if !beam.hitBall, ball.isLive, along(ball.box) {
                beam.hitBall = true
                ball.tornadoCentre = nil
                ball.release(from: ball.position, velocity: beam.direction * ZRules.ballSpeed, by: beam.owner, straight: false)
            }
            kept.append(beam)
        }
        beams = kept
    }

    /// Gale Ale's tornados a frame on: the still ones running down; the snatch's on its way,
    /// stripping whoever it meets once and taking the ball, theirs or loose, until it meets
    /// anything solid, or its time's up, and bursts, letting the ball go where it is.
    private mutating func stepGales() {
        guard !gales.isEmpty else { return }
        var solid = stage
        solid.extras += stage.ballBlockers + stage.ceilingSlopes.map(\.box)
        var kept: [Gale] = []
        for var gale in gales {
            gale.framesLeft -= 1
            var bursts = gale.framesLeft <= 0
            if gale.snatching, !bursts {
                gale.box = Box(center: gale.box.center + gale.velocity, width: gale.box.width, height: gale.box.height)
                let outside = gale.box.min.x < 0 || gale.box.max.x > stage.width
                if outside || solid.overlapsSolid(gale.box) {
                    bursts = true
                } else {
                    if !gale.struck, let victim = players.indices.first(where: { $0 != gale.owner && players[$0].body.overlaps(gale.box) }) {
                        gale.struck = true
                        let held = players[victim].hasBall
                        strip(victim, by: gale.owner, knock: nil)
                        if held, ball.holder == nil { gale.carrying = true }
                    }
                    if !gale.carrying, ball.isLive, ball.tether == nil, ball.box.overlaps(gale.box), !gales.contains(where: { $0.carrying }) {
                        gale.carrying = true
                    }
                    if gale.carrying, ball.isLive {
                        ball.position = gale.box.center
                        ball.velocity = .zero
                        ball.tornadoCentre = gale.box.center
                        ball.outsideTornados = false
                        ball.lastTouched = gale.owner
                    } else {
                        gale.carrying = false
                    }
                }
            }
            if bursts {
                if gale.carrying, ball.isLive { ball.tornadoCentre = nil }
                events.append(.galeBurst(at: gale.box.center))
            } else {
                kept.append(gale)
            }
        }
        gales = kept
    }

    /// The pass the Elements' fireball last burst on, so it's gone for the rest of that pass.
    public var stageFireballBurstPass: Int?

    /// The Elements' fireball this frame, if one is out: where it is, and which way it's going.
    public var stageFireball: (position: Vec2, heading: Facing)? { stageFireball(at: frame) }

    /// Where the Elements' fireball is on `frame`, burst or not.
    public func stageFireball(at frame: Int) -> (position: Vec2, heading: Facing)? {
        guard stage.tornados.count > 0 else { return nil }
        let pass = frame / StageFireballRules.everyFrames
        let time = frame % StageFireballRules.everyFrames
        guard time < StageFireballRules.travelFrames, stageFireballBurstPass != pass else { return nil }
        let heading: Facing = pass % 2 == 0 ? .right : .left
        let centres = stage.tornados.map(\.center).sorted { $0.x < $1.x }
        let reach = StageFireballRules.reachPastTornados * Stage.tileSize
        var points = [Vec2(x: stage.tornados.map(\.min.x).min()! - reach, y: StageFireballRules.underLava)] + centres
            + [Vec2(x: stage.tornados.map(\.max.x).max()! + reach, y: StageFireballRules.underLava)]
        if heading == .left { points.reverse() }
        return (Match.alongCurve(points, share: Double(time) / Double(StageFireballRules.travelFrames)), heading)
    }

    /// A point `share` of the way along a smooth curve through `points`, each stretch between
    /// two of them taking time by its length (Catmull-Rom, the ends doubled).
    static func alongCurve(_ points: [Vec2], share: Double) -> Vec2 {
        let lengths = zip(points, points.dropFirst()).map { $0.distance(to: $1) }
        var left = min(max(share, 0), 1) * lengths.reduce(0, +)
        var stretch = 0
        while stretch < lengths.count - 1, left > lengths[stretch] {
            left -= lengths[stretch]
            stretch += 1
        }
        let t = lengths[stretch] > 0 ? min(left / lengths[stretch], 1) : 0
        let p0 = points[max(stretch - 1, 0)], p1 = points[stretch], p2 = points[stretch + 1], p3 = points[min(stretch + 2, points.count - 1)]
        let t2 = t * t, t3 = t2 * t
        let a = p1 * 2, b = (p2 - p0) * t, c = (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2, d = (p1 * 3 - p0 - p2 * 3 + p3) * t3
        return (a + b + c + d) * 0.5
    }

    /// The Elements' fireball: whoever it touches is stripped and it bursts, Blazing Boba only burst on.
    private mutating func stepStageFireball() {
        guard let fireball = stageFireball else { return }
        let box = Box(center: fireball.position, width: StageFireballRules.radius * 2, height: StageFireballRules.radius * 2)
        guard let victim = players.indices.first(where: { players[$0].body.overlaps(box) && players[$0].frozen == 0 }) else { return }
        stageFireballBurstPass = frame / StageFireballRules.everyFrames
        events.append(.stageFireballBurst(at: fireball.position))
        guard players[victim].power != .blazingBoba else { return }
        let other = players.indices.first { $0 != victim } ?? victim
        strip(victim, by: other, knock: Vec2(x: BlazeRules.burstKnock.x * fireball.heading.sign, y: BlazeRules.burstKnock.y))
        // Carried by the knock a while, the stick not braking it.
        players[victim].airControlLock = StageFireballRules.knockCoastFrames
    }

    /// One icicle socket: when its icicle started growing and when it drops, while it's in the
    /// socket; where the falling one's tip is and how fast it's falling, once it's dropped.
    public struct Icicle: Equatable {
        public var formedAt: Int?
        public var dropAt = 0
        public var falling: Vec2?
        public var fallSpeed = 0.0
    }
    public var icicles: [Icicle] = []

    /// Grown, held, dropped, fallen: shattering on the ground, the lava or a body.
    private mutating func stepIcicles() {
        let sockets = stage.icicleSockets
        if icicles.count != sockets.count { icicles = Array(repeating: Icicle(), count: sockets.count) }
        guard !sockets.isEmpty else { return }
        if frame % IcicleRules.everyFrames == 0 {
            let pick = ElementsRules.pick(frame / IcicleRules.everyFrames + 1_000_000)
            let index = Int(pick % UInt64(sockets.count))
            if icicles[index].formedAt == nil, icicles[index].falling == nil {
                let hold = IcicleRules.holdFrames
                icicles[index].formedAt = frame
                icicles[index].dropAt = frame + IcicleRules.formFrames + hold.lowerBound + Int((pick >> 32) % UInt64(hold.count))
            }
        }
        for index in icicles.indices {
            if icicles[index].formedAt != nil, frame >= icicles[index].dropAt {
                icicles[index].formedAt = nil
                icicles[index].falling = sockets[index]
                icicles[index].fallSpeed = 0
            }
            guard var tip = icicles[index].falling else { continue }
            icicles[index].fallSpeed = min(icicles[index].fallSpeed + BallRules.gravity, BallRules.fallSpeed)
            let box = Box(min: Vec2(x: tip.x - IcicleRules.width / 2, y: tip.y), max: Vec2(x: tip.x + IcicleRules.width / 2, y: tip.y + IcicleRules.length))
            let swept = stage.sweepVertically(box, by: -icicles[index].fallSpeed, oneWays: false)
            tip.y += swept.moved
            let now = Box(min: Vec2(x: tip.x - IcicleRules.width / 2, y: tip.y), max: Vec2(x: tip.x + IcicleRules.width / 2, y: tip.y + IcicleRules.length))
            if let victim = players.indices.first(where: { players[$0].body.overlaps(now) }) {
                if players[victim].power != .frostTea {
                    strip(victim, by: players.indices.first { $0 != victim } ?? victim, knock: nil)
                    freeze(victim)
                }
            } else if !swept.landed, stage.features.lavaSurface.map({ tip.y > $0 }) ?? true {
                icicles[index].falling = tip
                continue
            }
            icicles[index].falling = nil
            events.append(.icicleShattered(at: tip))
        }
    }

    /// Where the Elements' lightning will strike on `frame`'s flash, and frames left till it
    /// does, while the warning's out.
    public var lightningWarning: (target: Vec2, framesLeft: Int)? {
        guard !stage.lightningSpots.isEmpty else { return nil }
        let time = frame % LightningRules.everyFrames
        guard time < LightningRules.warningFrames else { return nil }
        return (lightningTarget(flash: frame / LightningRules.everyFrames), LightningRules.warningFrames - time)
    }

    /// Each flash's spot, picked by its count: the same on every phone.
    private func lightningTarget(flash: Int) -> Vec2 {
        stage.lightningSpots[Int(ElementsRules.pick(flash) % UInt64(stage.lightningSpots.count))]
    }

    /// The flash, then the strike: whoever the bolt's line touches, up from its spot, is
    /// stripped, but Zeus Juice.
    private mutating func stepLightning() {
        guard !stage.lightningSpots.isEmpty else { return }
        let time = frame % LightningRules.everyFrames
        let target = lightningTarget(flash: frame / LightningRules.everyFrames)
        if time == 0 { events.append(.lightningFlashed(at: target)) }
        guard time == LightningRules.warningFrames else { return }
        events.append(.lightningStruck(at: target))
        let line = Box(min: Vec2(x: target.x - LightningRules.halfWidth, y: target.y),
                       max: Vec2(x: target.x + LightningRules.halfWidth, y: Double(stage.rows) * Stage.tileSize))
        for victim in players.indices where players[victim].power != .zeusJuice && players[victim].frozen == 0 && players[victim].body.overlaps(line) {
            strip(victim, by: players.indices.first { $0 != victim } ?? victim, knock: nil)
        }
    }

    /// Hit-stop to at least this many frames.
    private mutating func holdHitStop(_ frames: Int) {
        hitStop = max(hitStop, frames)
    }

    /// The strip: the victim stunned, any ball they hold popped free, and knocked away if
    /// `knock` is given. Without stunning, only the ball pops and the knock lands.
    private mutating func strip(_ victim: Int, by striker: Int, knock: Vec2?, stun: Bool = true, carry: Double = 0) {
        if !stun {
            // A push, not a hit: no stun and no spark, the ball let go of if held.
            let held = players[victim].hasBall
            if held {
                let from = players[victim].heldBallPoint
                players[victim].loseBall()
                ball.pop(from: from)
            }
            events.append(.pushed(player: victim, by: striker, ball: held))
        } else if players[victim].hasBall {
            pop(from: victim, by: striker, carry: carry)
        } else {
            events.append(.struck(player: victim, by: striker))
            holdHitStop(HitStopRules.hitFrames)
        }
        if stun { players[victim].hitStun = BallRules.hitStunFrames }
        if let knock { players[victim].knock(knock) }
    }

    private mutating func freeze(_ index: Int) {
        guard players[index].frozen == 0 else { return }
        players[index].frozen = FrostRules.freezeFrames
        events.append(.frozen(player: index))
    }

    // MARK: The powers' pieces

    /// Quake-Up Coffee: the floor shaken. At level one whatever stands on the same floor;
    /// at level two whatever stands on any. Titan Tea's landings shake the same floor only.
    private mutating func quake(by index: Int) {
        let me = players[index]
        events.append(.quaked(player: index))
        let whole = me.power == .quakeUp && me.powerLevel >= 2
        if ball.isLive, ball.frozen == 0, stage.isGrounded(ball.box),
           whole || abs(ball.position.y - BallRules.radius - me.position.y) <= QuakeRules.sameFloorSlack {
            ball.velocity.y = QuakeRules.ballHop
            ball.steers = false
            ball.resting = false
        }
        if let other = players.indices.first(where: { $0 != index }), players[other].grounded, players[other].frozen == 0,
           whole || abs(players[other].position.y - me.position.y) <= QuakeRules.sameFloorSlack {
            strip(other, by: index, knock: QuakeRules.knock)
        }
    }

    /// Zeus Juice's strike: down from the top of the screen at `x` toward `bottom`, and it
    /// stops on the first thing it meets: a solid, the other body, stripped, or the loose
    /// ball, popped up.
    private mutating func strike(x: Double, bottom: Double, by index: Int) {
        let other = players.indices.first { $0 != index }
        var y = Double(stage.rows + Stage.skyRows) * Stage.tileSize - 1
        while y > bottom {
            let bit = Box(min: Vec2(x: x - ZeusRules.strikeHalfWidth, y: y - 2), max: Vec2(x: x + ZeusRules.strikeHalfWidth, y: y))
            if let other, players[other].frozen == 0, players[other].body.overlaps(bit) {
                events.append(.boltStruck(player: index, x: x, bottom: players[other].body.max.y))
                strip(other, by: index, knock: Vec2(x: 0, y: 1))
                return
            }
            if ball.isLive, ball.frozen == 0, ball.box.overlaps(bit) {
                events.append(.boltStruck(player: index, x: x, bottom: ball.box.max.y))
                ball.pop(from: ball.position)
                return
            }
            if let car = car(touching: bit) {
                events.append(.boltStruck(player: index, x: x, bottom: cars[car].box.max.y))
                return
            }
            if stage.overlapsSolid(bit) {
                events.append(.boltStruck(player: index, x: x, bottom: y))
                return
            }
            y -= 2
        }
        events.append(.boltStruck(player: index, x: x, bottom: bottom))
    }

    /// Pulsepistol Punch's pulse: a pillar the width of the screen the way the body
    /// faces, at the hand, that pushes the ball and the other body away, or pulls them in.
    private mutating func pulse(by index: Int, pull: Bool) {
        let me = players[index]
        let sign = me.facing.sign
        let y = me.position.y + PulseRules.handHeight
        let edge = sign > 0 ? Double(stage.columns) * Stage.tileSize : 0
        let pillar = Box(min: Vec2(x: min(me.position.x, edge), y: y - PulseRules.halfHeight),
                         max: Vec2(x: max(me.position.x, edge), y: y + PulseRules.halfHeight))
        let way = pull ? -sign : sign
        events.append(.pulsed(player: index, pull: pull))
        if let other = players.indices.first(where: { $0 != index }), players[other].frozen == 0, players[other].body.overlaps(pillar) {
            strip(other, by: index, knock: Vec2(x: PulseRules.bodyPush.x * way, y: PulseRules.bodyPush.y), stun: false)
            if !players[other].hasBall, ball.isLive == false, ball.holder == nil {
                // The ball just popped: it goes the pulse's way too.
                ball.velocity = Vec2(x: PulseRules.ballPush.x * way, y: PulseRules.ballPush.y)
            }
        }
        if ball.isLive, ball.frozen == 0, ball.box.overlaps(pillar) {
            ball.velocity = Vec2(x: PulseRules.ballPush.x * way, y: PulseRules.ballPush.y)
            ball.straight = false
            ball.floater = 0
            ball.steers = false
            ball.shotInFlight = false
            ball.resting = false
            ball.lastTouched = index
        }
    }

    /// Pulsepistol Punch's snipe: whatever is within reach of the cursor is sent the shot's
    /// way, from the shooter's hand to the cursor, or with `pull` back toward the shooter;
    /// a held ball pops free, no stun.
    private mutating func snipe(by index: Int, at: Vec2, pull: Bool) {
        let hand = players[index].position + Vec2(x: 0, y: PulseRules.handHeight)
        let line = at - hand
        let direction = line.length > 0.001 ? line.normalized : Vec2(x: players[index].facing.sign, y: 0)
        let way = pull ? direction * -1 : direction
        events.append(.sniped(player: index, at: at, pull: pull))
        if let other = players.indices.first(where: { $0 != index }), players[other].frozen == 0,
           players[other].body.distance(to: at) <= SnipeRules.reach {
            strip(other, by: index, knock: way * SnipeRules.bodyPush + Vec2(x: 0, y: SnipeRules.bodyLift), stun: false)
            if !players[other].hasBall, ball.isLive == false, ball.holder == nil { ball.velocity = way * SnipeRules.ballPush }
        }
        if ball.isLive, ball.frozen == 0, ball.position.distance(to: at) <= SnipeRules.reach + BallRules.radius {
            ball.velocity = way * SnipeRules.ballPush
            ball.straight = false
            ball.floater = 0
            ball.steers = false
            ball.shotInFlight = false
            ball.resting = false
            ball.lastTouched = index
        }
    }

    /// Zeus Juice's bolts fly straight until they meet a wall, a body or the ball.
    private mutating func stepBolts() {
        var kept: [Bolt] = []
        for var bolt in bolts {
            bolt.position += bolt.velocity
            bolt.framesLeft -= 1
            let box = Box(center: bolt.position, width: 4, height: 4)
            if let other = players.indices.first(where: { $0 != bolt.owner }), players[other].boardBlocks(bolt.position, radius: 2) {
                events.append(.boardBlocked(player: other, at: bolt.position))
                events.append(.boltLanded(at: bolt.position))
                continue
            }
            if car(touching: box) != nil {
                events.append(.boltLanded(at: bolt.position))
                continue
            }
            if bolt.framesLeft <= 0 || stage.overlapsSolid(box) {
                events.append(.boltLanded(at: bolt.position))
                continue
            }
            if let other = players.indices.first(where: { $0 != bolt.owner }), players[other].frozen == 0, players[other].body.overlaps(box) {
                let sign = bolt.velocity.x >= 0 ? 1.0 : -1.0
                strip(other, by: bolt.owner, knock: Vec2(x: ZeusRules.boltKnock.x * sign, y: ZeusRules.boltKnock.y))
                events.append(.boltLanded(at: bolt.position))
                continue
            }
            if ball.isLive, ball.frozen == 0, ball.box.overlaps(box) {
                // Back toward the thrower, a little.
                let sign = bolt.velocity.x >= 0 ? 1.0 : -1.0
                ball.pop(from: ball.position)
                ball.velocity = Vec2(x: -ZeusRules.ballPop.x * sign, y: ZeusRules.ballPop.y)
                ball.lastTouched = bolt.owner
                events.append(.boltLanded(at: bolt.position))
                continue
            }
            kept.append(bolt)
        }
        bolts = kept
    }

    /// Frost Tea's clones freeze the other body or the ball on touch and shatter, or
    /// shatter on their own when their frames run out.
    private mutating func stepClones() {
        var kept: [IceClone] = []
        for var clone in clones {
            clone.framesLeft -= 1
            var shattered = clone.framesLeft <= 0
            if let other = players.indices.first(where: { $0 != clone.owner }), players[other].frozen == 0, players[other].body.overlaps(clone.box) {
                freeze(other)
                shattered = true
            } else if ball.isLive, ball.frozen == 0, ball.box.overlaps(clone.box) {
                ball.frozen = FrostRules.freezeFrames
                events.append(.ballFrozen)
                shattered = true
            }
            if shattered {
                events.append(.cloneShattered(at: clone.box.center))
            } else {
                kept.append(clone)
            }
        }
        clones = kept
    }

    /// Blazing Boba's flames strip the other body that steps in one, once each.
    private mutating func stepFlames() {
        var kept: [Flame] = []
        for var flame in flames {
            flame.framesLeft -= 1
            guard flame.framesLeft > 0 else { continue }
            if car(touching: flame.box) != nil {
                continue
            }
            if let other = players.indices.first(where: { $0 != flame.owner }), players[other].frozen == 0,
               players[other].hitStun == 0, players[other].body.overlaps(flame.box) {
                strip(other, by: flame.owner, knock: BlazeRules.flameKnock)
                continue
            }
            kept.append(flame)
        }
        flames = kept
    }

    /// Blazing Boba's fireballs fly like a thrown ball and burst on the first thing they
    /// meet, stripping and knocking whatever's within reach.
    private mutating func stepFireballs() {
        var kept: [Fireball] = []
        for var fireball in fireballs {
            if !fireball.straight {
                let share = fireball.ballArc ? 1 : BlazeRules.fireballGravityShare
                fireball.velocity.y = max(fireball.velocity.y - BallRules.gravity * share, -BallRules.fallSpeed * share)
            }
            fireball.position += fireball.velocity
            fireball.framesLeft -= 1
            let box = Box(center: fireball.position, width: BallRules.radius * 2, height: BallRules.radius * 2)
            let other = players.indices.first { $0 != fireball.owner }
            // The other's board catches it before their body does.
            let onBoard = other.map { players[$0].boardBlocks(fireball.position, radius: BallRules.radius) } ?? false
            if onBoard, let other {
                events.append(.boardBlocked(player: other, at: fireball.position))
                events.append(.fireballBurst(at: fireball.position))
                continue
            }
            let hitBody = other.map { players[$0].frozen == 0 && players[$0].body.overlaps(box) } ?? false
            if fireball.framesLeft <= 0 || stage.overlapsSolid(box) || hitBody {
                events.append(.fireballBurst(at: fireball.position))
                if let other, players[other].body.distance(to: fireball.position) <= BlazeRules.burstReach, players[other].frozen == 0 {
                    let sign = players[other].position.x >= fireball.position.x ? 1.0 : -1.0
                    strip(other, by: fireball.owner, knock: Vec2(x: BlazeRules.burstKnock.x * sign, y: BlazeRules.burstKnock.y))
                }
                if ball.isLive, ball.frozen == 0, ball.position.distance(to: fireball.position) <= BlazeRules.burstReach {
                    let sign = ball.position.x >= fireball.position.x ? 1.0 : -1.0
                    ball.pop(from: ball.position)
                    ball.velocity = Vec2(x: BlazeRules.burstKnock.x * sign, y: BlazeRules.burstKnock.y)
                }
                continue
            }
            kept.append(fireball)
        }
        fireballs = kept
    }

    /// The ball into a player's hands, whatever it was doing.
    private mutating func hand(ballTo catcher: Int) {
        players[catcher].catchBall()
        ball.holder = catcher
        ball.straight = false
        ball.thrown = false
        ball.tether = nil
        ball.floater = 0
        ball.frozen = 0
        ball.resting = false
        events.append(.caught(player: catcher))
    }

    /// Web Water's line: the first thing along it wins. The line bends toward a ball or
    /// body within the assist angle of the aim first, and a miss leaves it showing, live,
    /// for a few frames.
    private mutating func webLine(from index: Int, direction aimed: Vec2) {
        let origin = players[index].chest
        let opponent = players.indices.first { $0 != index }
        var direction = aimed
        var bestTurn = WebRules.assistAngle
        var candidates: [Vec2] = []
        if ball.isLive { candidates.append(ball.position) }
        if let opponent { candidates.append(players[opponent].chest) }
        for candidate in candidates {
            let toward = candidate - origin
            guard toward.length <= WebRules.lineRange, toward.length > 1 else { continue }
            let turn = abs(Trig.atan2(toward.x * aimed.y - toward.y * aimed.x, toward.x * aimed.x + toward.y * aimed.y))
            if turn < bestTurn {
                bestTurn = turn
                direction = toward.normalized
            }
        }
        let hit = snag(by: index, from: origin, direction: direction, range: WebRules.lineRange, throughSolids: false)
        if !hit {
            players[index].webLine = WebLine(target: .point(origin + direction * WebRules.lineRange), frames: WebRules.missFrames)
        }
        events.append(.webLine(player: index, hit: hit))
    }

    /// Walks a line out from `origin` and takes the first thing on it. A wall reels the
    /// shooter to it, unless the line is one that already ended and is only lingering; a
    /// loose ball is tethered; the other holding the ball loses it to the tether; the other
    /// without it is reeled to a spot in front of the shooter. True when something was taken.
    private mutating func snag(by index: Int, from origin: Vec2, direction: Vec2, range: Double, throughSolids: Bool) -> Bool {
        let opponent = players.indices.first { $0 != index }
        var travelled = 0.0
        while travelled <= range {
            let point = origin + direction * travelled
            if !throughSolids, stage.overlapsSolid(Box(center: point, width: 1, height: 1)) {
                let landing = origin + direction * max(travelled - 4, 0)
                players[index].startPull(to: landing, byOther: false)
                players[index].webLine = WebLine(target: .point(point), frames: WebRules.pullMaxFrames)
                return true
            }
            if ball.isLive, ball.position.distance(to: point) <= BallRules.radius + WebRules.snapRadius {
                ball.tether = index
                ball.thrown = false
                ball.pace = 1
                players[index].webLine = WebLine(target: .ball, frames: WebRules.pullMaxFrames)
                return true
            }
            if let opponent, players[opponent].body.overlaps(Box(center: point, width: WebRules.snapRadius * 2, height: WebRules.snapRadius * 2)) {
                if players[opponent].hasBall {
                    players[opponent].loseBall()
                    ball.holder = nil
                    ball.position = players[opponent].chest
                    ball.velocity = .zero
                    ball.tether = index
                    players[index].webLine = WebLine(target: .ball, frames: WebRules.pullMaxFrames)
                } else {
                    let shooter = players[index]
                    let drop = Vec2(x: shooter.position.x + shooter.facing.sign * WebRules.dropDistance, y: shooter.position.y)
                    players[opponent].startPull(to: drop, byOther: true)
                    players[index].webLine = WebLine(target: .opponent, frames: WebRules.pullMaxFrames)
                }
                return true
            }
            travelled += 2
        }
        return false
    }

    /// A line that hit nothing stays live for as long as it shows: the ball or the other
    /// body crossing it in those frames is taken as if the line had just been fired.
    private mutating func snagWithLingeringLines() {
        for index in players.indices {
            guard let line = players[index].webLine, case .point(let end) = line.target, players[index].state != .webPull else { continue }
            let origin = players[index].chest
            let toward = end - origin
            guard toward.length > 1 else { continue }
            _ = snag(by: index, from: origin, direction: toward.normalized, range: toward.length, throughSolids: true)
        }
    }

    /// A tethered ball comes straight to its puller and is caught on arrival, whatever its
    /// speed or the puller's facing.
    private mutating func reelBall() {
        guard let puller = ball.tether, ball.holder == nil else { return }
        let target = players[puller].chest
        let gap = target - ball.position
        if gap.length <= BallRules.catchRadius, !players[puller].hasBall {
            hand(ballTo: puller)
            players[puller].webLine = nil
        } else if players[puller].hasBall {
            ball.tether = nil
            players[puller].webLine = nil
        } else {
            ball.velocity = gap.normalized * WebRules.pullSpeed
            ball.position += ball.velocity
        }
    }

    /// The other side's web let go of whoever it had, if the puller's line is gone.
    private mutating func releasePulls() {
        for index in players.indices where players[index].state == .webbed {
            let puller = players.indices.first { $0 != index }
            if let puller, players[puller].webLine == nil { players[index].pullTarget = nil }
        }
    }

    /// The nearest player who can reach the loose ball takes it.
    /// A thrown ball, sideways or down, that meets the other body: they're stripped and
    /// knocked as by the slash, and it bounces back toward the thrower, theirs to catch.
    /// A snatch with the hand out takes it instead, before this.
    private mutating func strikeWithThrow() {
        guard ball.strikes, ball.isLive, let thrower = ball.lastTouched,
              let other = players.indices.first(where: { $0 != thrower }) else { return }
        if players[other].boardBlocks(ball.position, radius: BallRules.radius) {
            // Off Surf Soda's board: turned back, and it strikes no more.
            ball.velocity.x = -ball.velocity.x * BallRules.bounce
            ball.strikes = false
            ball.straight = false
            events.append(.boardBlocked(player: other, at: ball.position))
            return
        }
        let victim = players[other]
        guard victim.frozen == 0, victim.snatchHitbox == nil, victim.body.overlaps(ball.box) else { return }
        let back = ball.velocity.x >= 0 ? -1.0 : 1.0
        strip(other, by: thrower, knock: Vec2(x: SlashRules.knock.x * -back, y: SlashRules.knock.y))
        // Straight back at the thrower's chest, so it arrives wherever they were; it's
        // theirs to catch until it first hits something.
        let speed = max(abs(ball.velocity.x), 2) * BallRules.bounce
        let toward = players[thrower].chest - ball.position
        ball.velocity = toward.length > 1 ? toward.normalized * speed : Vec2(x: speed * back, y: 0)
        ball.straight = true
        ball.strikes = false
        ball.returning = true
        ball.lastTouched = thrower
        ball.owned = true
    }

    private mutating func tryCatch() {
        // Won: nobody catches.
        guard !finished else { return }
        // A throw coming back off the other is the thrower's at any speed, facing or not,
        // in any state but a stun or a freeze.
        if ball.returning, let thrower = ball.lastTouched, !players[thrower].holding, players[thrower].hitStun == 0,
           players[thrower].frozen == 0, players[thrower].chest.distance(to: ball.position) <= BallRules.catchRadius + BallRules.radius {
            hand(ballTo: thrower)
            return
        }
        let speed = ball.velocity.length
        let candidates = players.indices
            .filter { !ball.burning || ball.lastTouched == $0 }
            .filter { players[$0].canCatch(ballAt: ball.position, speed: ball.lastTouched == $0 ? 0 : speed, shotInFlight: ball.shotInFlight && ball.lastTouched != $0) }
            .sorted { players[$0].chest.distance(to: ball.position) < players[$1].chest.distance(to: ball.position) }
        guard let catcher = candidates.first else { return }
        hand(ballTo: catcher)
    }

    /// The arc a shot would take from where the player stands, for the aiming guide.
    public func shotPreview(for index: Int, points: Int = 30, every stride: Int = 3) -> [Vec2] {
        let player = players[index]
        var position = player.position + Vec2(x: 0, y: BallRules.shotReleaseHeight * player.spec.scale)
        var velocity = player.shotVelocity
        // A fireball falls under a share of the ball's gravity.
        let share = player.hasFireball ? BlazeRules.fireballGravityShare : 1
        var path: [Vec2] = []
        for step in 0..<(points * stride) {
            velocity.y = max(velocity.y - BallRules.gravity * share, -BallRules.fallSpeed * share)
            position += velocity
            if stage.overlapsSolid(Box(center: position, width: BallRules.radius * 2, height: BallRules.radius * 2)) { break }
            if step % stride == 0 { path.append(position) }
        }
        return path
    }
}
