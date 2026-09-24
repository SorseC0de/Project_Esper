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
    public var flames: [Flame] = []
    public var fireballs: [Fireball] = []
    /// The next id for anything the powers leave, so the screen can follow each one.
    public var nextId = 1
    public var scores: [Int]
    public var frame = 0
    /// The count before play: frames in which nobody moves or acts, at the start and after
    /// every point, and how long that is.
    public var countdown: Int
    public let countdownLength: Int
    /// A point waiting to restart, after a dunk: frames left with the dunker on the rim,
    /// and whose hands the ball then goes to.
    public var restartIn = 0
    public var restartBallTo = 0
    /// What happened on the last `advance`.
    public var events: [MatchEvent] = []

    public init(stage: Stage = .court, specs: [FighterSpec] = [.baseline, .baseline], countdown: Int = 0) {
        self.stage = stage
        players = specs.indices.map { index in
            Player(spec: specs[index], index: index, position: stage.playerSpawns[index], facing: stage.playerFacings[index])
        }
        ball = Ball(position: stage.ballSpawn)
        scores = Array(repeating: 0, count: specs.count)
        countdownLength = countdown
        self.countdown = countdown
    }

    public mutating func advance(inputs given: [PlayerInput]) {
        frame += 1
        events = []
        if restartIn > 0 {
            restartIn -= 1
            if restartIn == 0 { restart(ballTo: restartBallTo) }
        }
        let inputs = countdown > 0 ? [] : given
        if countdown > 0 { countdown -= 1 }

        // Platforms count down and go; the stage carries the ones standing.
        platforms = platforms.compactMap { platform in
            platform.framesLeft > 1 ? Platform(owner: platform.owner, box: platform.box, framesLeft: platform.framesLeft - 1) : nil
        }
        stage.extras = platforms.map(\.box)

        for index in players.indices {
            let input = index < inputs.count ? inputs[index] : .idle
            let opponentX = players.indices.first { $0 != index }.map { players[$0].position.x }
            guard let action = players[index].step(input: input, stage: stage, opponentX: opponentX,
                                                   ballHolder: ball.holder, ballOwner: ball.isLive ? ball.owner : nil,
                                                   events: &events) else { continue }
            perform(action, by: index)
        }
        resolveParries()
        for index in players.indices {
            resolveHits(by: index)
        }
        stepBolts()
        stepClones()
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
        } else if ball.isLive, ball.tether == nil {
            if let hoop = ball.step(stage: stage, events: &events) {
                let owner = stage.hoops[hoop].owner
                scores[owner] += 1
                events.append(.scored(player: owner, hoop: hoop, entry: ball.velocity))
                if let other = players.indices.first(where: { $0 != owner }) {
                    if players.contains(where: { $0.state == .dunking }) {
                        // A dunk: the dunker hangs on the rim a beat, the ball dead, then the restart.
                        restartIn = BallRules.dunkHangFrames
                        restartBallTo = other
                        ball.respawnTimer = BallRules.dunkHangFrames + 5
                    } else {
                        restart(ballTo: other)
                    }
                }
                return
            }
            strikeWithThrow()
            tryCatch()
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
            ball.position = players[holder].chest + Vec2(x: 0, y: 3)
            ball.velocity = .zero
        }
    }

    /// After a point: everyone back to their spawn as they began, the ball in `holder`'s
    /// hands, any slab gone, and the count again.
    public mutating func restart(ballTo holder: Int) {
        for index in players.indices {
            let was = players[index]
            players[index] = Player(spec: was.spec, index: index, position: stage.playerSpawns[index], facing: stage.playerFacings[index])
            players[index].power = was.power
            players[index].powerLevel = was.powerLevel
        }
        platforms = []
        stage.extras = []
        bolts = []
        clones = []
        flames = []
        fireballs = []
        ball.respawn(at: stage.ballSpawn)
        players[holder].hasBall = true
        ball.holder = holder
        ball.position = players[holder].chest + Vec2(x: 0, y: 3)
        countdown = countdownLength
    }

    private mutating func perform(_ action: PlayerAction, by index: Int) {
        let player = players[index]
        switch action {
        case .releaseShot(let velocity):
            // Cannon Cola's pace: the same arc run through that many times faster.
            ball.release(from: player.position + Vec2(x: 0, y: BallRules.shotReleaseHeight),
                         velocity: velocity * player.spec.shotPace, by: index, straight: false, pace: player.spec.shotPace)
            ball.shotInFlight = true
            ball.burning = player.power == .blazingBoba
        case .releaseThrow(let velocity):
            let hand = Vec2(x: player.position.x + player.facing.sign * 6, y: player.position.y + BallRules.throwReleaseHeight)
            if velocity.y > 0, velocity.x == 0 {
                ball.releaseFloater(from: Vec2(x: player.position.x, y: player.position.y + BallRules.shotReleaseHeight),
                                    sideways: player.throwStanceEntrySpeed * BallRules.floaterMomentumShare, by: index)
            } else {
                ball.release(from: hand, velocity: velocity, by: index, straight: true)
                ball.strikes = true
            }
            ball.burning = player.power == .blazingBoba
        case .releaseFireball(let velocity, let straight):
            let hand = Vec2(x: player.position.x + player.facing.sign * 6, y: player.position.y + BallRules.throwReleaseHeight)
            fireballs.append(Fireball(id: stamp(), owner: index, position: hand, velocity: velocity, framesLeft: BlazeRules.fireballFrames, straight: straight))
        case .quake:
            quake(by: index)
        case .fireBolt(let direction):
            bolts.append(Bolt(id: stamp(), owner: index, position: player.chest + direction * 6, velocity: direction * ZeusRules.boltSpeed,
                              framesLeft: ZeusRules.boltFrames))
            events.append(.boltFired(player: index))
        case .strikeBolt(let x, let bottom):
            strike(x: x, bottom: bottom, by: index)
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
        case .dunk(let hoop):
            ball.release(from: stage.hoops[hoop].position + Vec2(x: 0, y: 2), velocity: Vec2(x: 0, y: -2), by: index, straight: false)
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
            make(box, by: index)
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
                let ends = [from + Vec2(x: 0, y: BallRules.chestHeight), to + Vec2(x: 0, y: BallRules.chestHeight)]
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
            let feet = Vec2(x: ball.position.x, y: ball.position.y - BallRules.chestHeight)
            players[index].warp(to: feet, in: stage)
            events.append(.warped(player: index, from: from, to: players[index].position))
            hand(ballTo: index)
        }
    }

    private mutating func stamp() -> Int {
        defer { nextId += 1 }
        return nextId
    }

    /// A slab or a wall, solid for a second, and the maker disarmed and on the cooldown.
    private mutating func make(_ box: Box, by index: Int) {
        platforms.append(Platform(owner: index, box: box, framesLeft: ShakeRules.platformFrames))
        players[index].platformArmed = false
        players[index].platformCooldown = ShakeRules.cooldownFrames
        stage.extras = platforms.map(\.box)
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
        if let leg = player.slideHitbox, let other, players[other].hasBall, players[other].grounded, players[other].body.overlaps(leg) {
            players[index].slideHit = true
            pop(from: other, by: index)
        }
        if let blade = player.slashHitbox {
            if let other, players[other].body.overlaps(blade), players[other].frozen == 0 {
                // The body, ball or no ball: stripped and knocked along the swing.
                players[index].slashHit = true
                strip(other, by: index, knock: Vec2(x: SlashRules.knock.x * player.facing.sign, y: SlashRules.knock.y))
            } else if ball.isLive, ball.box.overlaps(blade) {
                // Down and away at about the spike angle, jittered a little by the frame.
                players[index].slashHit = true
                let noise = Double((frame &* 1103515245 &+ 12345) & 0xFFFF) / 65535 * 2 - 1
                let angle = SlashRules.spikeAngle + SlashRules.spikeJitter * noise
                ball.swat(along: Vec2(x: Trig.cos(angle) * player.facing.sign, y: Trig.sin(angle)), by: index)
                events.append(.swatted(player: index, hit: true))
            }
        }
        if let reach = player.snatchHitbox {
            let held = ball.holder.flatMap { $0 == index ? nil : $0 }
            // A held ball is where the holder's sheet draws it this frame, so the hand can
            // take it off the dribble; failing a landmark, the chest.
            let at = held.map { holder -> Vec2 in
                let body = players[holder]
                if let offset = BallLandmarks.offset(body.animationFrame) {
                    return body.position + Vec2(x: offset.x / 1.6 * body.facing.sign, y: offset.y / 1.6)
                }
                return body.chest + Vec2(x: 0, y: 3)
            } ?? ball.position
            let facingIt = (at.x - player.position.x) * player.facing.sign >= -1
            // A burning ball is the thrower's alone.
            let allowed = !ball.burning || ball.lastTouched == index || held != nil
            if player.power == .frostTea, let other, players[other].frozen == 0, players[other].body.overlaps(reach),
               (players[other].body.center.x - player.position.x) * player.facing.sign >= -1 {
                // Frost Tea: the body it reaches is frozen where it stands, and stripped.
                strip(other, by: index, knock: nil)
                freeze(other)
            } else if facingIt, allowed, player.snatchReaches(ballAt: at) || (held.map { players[$0].body.overlaps(reach) } ?? false),
                      held != nil || ball.isLive {
                if let held {
                    players[held].loseBall()
                    players[held].hitStun = BallRules.hitStunFrames
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

    /// A snatch's reach meeting a live blade: the slasher is the one stripped and knocked
    /// back, and the blade is spent. Before the blades are resolved, so it wins.
    private mutating func resolveParries() {
        for index in players.indices {
            guard let reach = players[index].snatchHitbox, let other = players.indices.first(where: { $0 != index }),
                  let blade = players[other].slashHitbox, blade.overlaps(reach) else { continue }
            players[other].slashHit = true
            let away = players[other].position.x >= players[index].position.x ? 1.0 : -1.0
            strip(other, by: index, knock: Vec2(x: SnatchRules.parryKnock.x * away, y: SnatchRules.parryKnock.y))
            events.append(.parried(player: other, by: index))
        }
    }

    /// The ball knocked out of `victim`'s hands: it pops straight up, nobody's, and the
    /// victim is stunned, so the popper has first go at it.
    private mutating func pop(from victim: Int, by popper: Int) {
        let from = players[victim].chest + Vec2(x: 0, y: 3)
        players[victim].loseBall()
        players[victim].hitStun = BallRules.hitStunFrames
        ball.pop(from: from)
        events.append(.popped(player: victim, by: popper))
    }

    /// The strip: the victim stunned, any ball they hold popped free, and knocked away if
    /// `knock` is given. Without stunning, only the ball pops and the knock lands.
    private mutating func strip(_ victim: Int, by striker: Int, knock: Vec2?, stun: Bool = true) {
        if !stun {
            // A push, not a hit: no stun and no spark, the ball let go of if held.
            let held = players[victim].hasBall
            if held {
                let from = players[victim].chest + Vec2(x: 0, y: 3)
                players[victim].loseBall()
                ball.pop(from: from)
            }
            events.append(.pushed(player: victim, by: striker, ball: held))
        } else if players[victim].hasBall {
            pop(from: victim, by: striker)
        } else {
            events.append(.struck(player: victim, by: striker))
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
    /// at level two whatever stands on any.
    private mutating func quake(by index: Int) {
        let me = players[index]
        events.append(.quaked(player: index))
        let whole = me.powerLevel >= 2
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

    /// Zeus Juice's strike: a column from the top of the screen down to `bottom` at `x`,
    /// stripping the other body in it and popping a loose ball in it up.
    private mutating func strike(x: Double, bottom: Double, by index: Int) {
        let top = Double(stage.rows + Stage.skyRows) * Stage.tileSize
        let column = Box(min: Vec2(x: x - ZeusRules.strikeHalfWidth, y: bottom), max: Vec2(x: x + ZeusRules.strikeHalfWidth, y: top))
        events.append(.boltStruck(player: index, x: x, bottom: bottom))
        if let other = players.indices.first(where: { $0 != index }), players[other].frozen == 0, players[other].body.overlaps(column) {
            strip(other, by: index, knock: Vec2(x: 0, y: 1))
        } else if ball.isLive, ball.frozen == 0, ball.box.overlaps(column) {
            ball.pop(from: ball.position)
        }
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

    /// Zeus Juice's bolts fly straight until they meet a wall, a body or the ball.
    private mutating func stepBolts() {
        var kept: [Bolt] = []
        for var bolt in bolts {
            bolt.position += bolt.velocity
            bolt.framesLeft -= 1
            let box = Box(center: bolt.position, width: 4, height: 4)
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
                let gravity = BallRules.gravity * BlazeRules.fireballGravityShare
                fireball.velocity.y = max(fireball.velocity.y - gravity, -BallRules.fallSpeed * BlazeRules.fireballGravityShare)
            }
            fireball.position += fireball.velocity
            fireball.framesLeft -= 1
            let box = Box(center: fireball.position, width: BallRules.radius * 2, height: BallRules.radius * 2)
            let other = players.indices.first { $0 != fireball.owner }
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
        let victim = players[other]
        guard victim.frozen == 0, victim.snatchHitbox == nil, victim.body.overlaps(ball.box) else { return }
        let back = ball.velocity.x >= 0 ? -1.0 : 1.0
        strip(other, by: thrower, knock: Vec2(x: SlashRules.knock.x * -back, y: SlashRules.knock.y))
        ball.velocity = Vec2(x: max(abs(ball.velocity.x), 2) * BallRules.bounce * back, y: 2)
        ball.straight = false
        ball.strikes = false
        ball.returning = true
        ball.lastTouched = thrower
        ball.owned = true
    }

    private mutating func tryCatch() {
        let speed = ball.velocity.length
        let candidates = players.indices
            .filter { !ball.burning || ball.lastTouched == $0 }
            .filter { players[$0].canCatch(ballAt: ball.position, speed: ball.returning && ball.lastTouched == $0 ? 0 : speed, shotInFlight: ball.shotInFlight) }
            .sorted { players[$0].chest.distance(to: ball.position) < players[$1].chest.distance(to: ball.position) }
        guard let catcher = candidates.first else { return }
        hand(ballTo: catcher)
    }

    /// The arc a shot would take from where the player stands, for the aiming guide.
    public func shotPreview(for index: Int, points: Int = 30, every stride: Int = 3) -> [Vec2] {
        let player = players[index]
        var position = player.position + Vec2(x: 0, y: BallRules.shotReleaseHeight)
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
