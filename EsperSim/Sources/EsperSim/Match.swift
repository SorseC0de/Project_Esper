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
    public var scores: [Int]
    public var frame = 0
    /// What happened on the last `advance`.
    public var events: [MatchEvent] = []

    public init(stage: Stage = .court, specs: [FighterSpec] = [.baseline, .baseline]) {
        self.stage = stage
        players = specs.indices.map { index in
            Player(spec: specs[index], index: index, position: stage.playerSpawns[index], facing: stage.playerFacings[index])
        }
        ball = Ball(position: stage.ballSpawn)
        scores = Array(repeating: 0, count: specs.count)
    }

    public mutating func advance(inputs: [PlayerInput]) {
        frame += 1
        events = []

        // Platforms count down and go; the stage carries the ones standing.
        platforms = platforms.compactMap { platform in
            platform.framesLeft > 1 ? Platform(owner: platform.owner, box: platform.box, framesLeft: platform.framesLeft - 1) : nil
        }
        for index in players.indices {
            players[index].hasPlatform = platforms.contains { $0.owner == index }
        }
        stage.extras = platforms.map(\.box)

        for index in players.indices {
            let input = index < inputs.count ? inputs[index] : .idle
            let opponentX = players.indices.first { $0 != index }.map { players[$0].position.x }
            let ballOwner = ball.isLive ? ball.owner : nil
            guard let action = players[index].step(input: input, stage: stage, opponentX: opponentX, ballOwner: ballOwner, events: &events) else { continue }
            perform(action, by: index)
        }

        for index in players.indices where players[index].webLine?.target == .opponent {
            let other = players.indices.first { $0 != index }
            if let other, players[other].state != .webbed { players[index].webLine = nil }
        }
        reelBall()

        if ball.isLive, ball.tether == nil {
            let bodies = players.filter { $0.catchCooldown == 0 }.map(\.body)
            if let hoop = ball.step(stage: stage, bodies: bodies, events: &events) {
                let owner = stage.hoops[hoop].owner
                scores[owner] += 1
                ball.respawnTimer = BallRules.respawnFrames
                events.append(.scored(player: owner, hoop: hoop))
            }
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

    private mutating func perform(_ action: PlayerAction, by index: Int) {
        let player = players[index]
        switch action {
        case .releaseShot(let velocity):
            ball.release(from: player.position + Vec2(x: 0, y: BallRules.shotReleaseHeight),
                         velocity: velocity, by: index, straight: false)
        case .releaseThrow(let velocity):
            let hand = Vec2(x: player.position.x + player.facing.sign * 6, y: player.position.y + BallRules.throwReleaseHeight)
            if velocity.y > 0, velocity.x == 0 {
                ball.releaseFloater(from: Vec2(x: player.position.x, y: player.position.y + BallRules.shotReleaseHeight),
                                    sideways: player.throwStanceEntrySpeed * BallRules.floaterMomentumShare, by: index)
            } else {
                ball.release(from: hand, velocity: velocity, by: index, straight: true)
            }
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
            platforms.append(Platform(owner: index, box: box, framesLeft: ShakeRules.platformFrames))
            players[index].hasPlatform = true
            stage.extras = platforms.map(\.box)
            events.append(.platformMade(player: index))
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
            players[index].catchBall()
            ball.holder = index
            ball.straight = false
            ball.thrown = false
            ball.tether = nil
            ball.resting = false
            events.append(.warped(player: index, from: from, to: players[index].position))
            events.append(.caught(player: index))
        case .swat:
            if ball.isLive, player.canSwat(ballAt: ball.position) {
                ball.velocity = -ball.velocity
                ball.straight = false
                ball.lastTouched = index
                events.append(.swatted(player: index, hit: true))
            } else {
                events.append(.swatted(player: index, hit: false))
            }
        }
    }

    /// Web Water's line: the first thing along it wins. A loose ball is reeled in; the other
    /// with the ball loses it to the reel; the other without it is reeled to a spot in front;
    /// a wall reels the shooter to it. The line bends toward a ball or body within the assist
    /// angle of the aim first.
    private mutating func webLine(from index: Int, direction aimed: Vec2) {
        let shooter = players[index]
        let origin = shooter.chest
        let opponent = players.indices.first { $0 != index }
        var direction = aimed
        var bestTurn = WebRules.assistAngle
        var candidates: [Vec2] = []
        if ball.isLive { candidates.append(ball.position) }
        if let opponent { candidates.append(players[opponent].chest) }
        for candidate in candidates {
            let toward = candidate - origin
            guard toward.length <= WebRules.lineRange, toward.length > 1 else { continue }
            let turn = abs(atan2(toward.x * aimed.y - toward.y * aimed.x, toward.x * aimed.x + toward.y * aimed.y))
            if turn < bestTurn {
                bestTurn = turn
                direction = toward.normalized
            }
        }
        var hit = false
        var travelled = 0.0
        while travelled <= WebRules.lineRange {
            let point = origin + direction * travelled
            if stage.overlapsSolid(Box(center: point, width: 1, height: 1)) {
                let landing = origin + direction * max(travelled - 4, 0)
                players[index].startPull(to: landing, byOther: false)
                players[index].webLine = WebLine(target: .point(point), frames: WebRules.pullMaxFrames)
                hit = true
                break
            }
            if ball.isLive, ball.position.distance(to: point) <= BallRules.radius + WebRules.snapRadius {
                ball.tether = index
                ball.thrown = false
                players[index].webLine = WebLine(target: .ball, frames: WebRules.pullMaxFrames)
                hit = true
                break
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
                    let drop = Vec2(x: shooter.position.x + shooter.facing.sign * WebRules.dropDistance, y: shooter.position.y)
                    players[opponent].startPull(to: drop, byOther: true)
                    players[index].webLine = WebLine(target: .opponent, frames: WebRules.pullMaxFrames)
                }
                hit = true
                break
            }
            travelled += 2
        }
        if !hit {
            players[index].webLine = WebLine(target: .point(origin + direction * WebRules.lineRange), frames: WebRules.missFrames)
        }
        events.append(.webLine(player: index, hit: hit))
    }

    /// A tethered ball comes straight to its puller and is caught on arrival, whatever its
    /// speed or the puller's facing.
    private mutating func reelBall() {
        guard let puller = ball.tether, ball.holder == nil else { return }
        let target = players[puller].chest
        let gap = target - ball.position
        if gap.length <= BallRules.catchRadius, !players[puller].hasBall {
            players[puller].catchBall()
            ball.holder = puller
            ball.straight = false
            ball.thrown = false
            ball.tether = nil
            ball.resting = false
            players[puller].webLine = nil
            events.append(.caught(player: puller))
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
    private mutating func tryCatch() {
        let speed = ball.velocity.length
        let candidates = players.indices
            .filter { players[$0].canCatch(ballAt: ball.position, speed: speed) }
            .sorted { players[$0].chest.distance(to: ball.position) < players[$1].chest.distance(to: ball.position) }
        guard let catcher = candidates.first else { return }
        players[catcher].catchBall()
        ball.holder = catcher
        ball.straight = false
        ball.thrown = false
        ball.resting = false
        events.append(.caught(player: catcher))
    }

    /// The arc a shot would take from where the player stands, for the aiming guide.
    public func shotPreview(for index: Int, points: Int = 30, every stride: Int = 3) -> [Vec2] {
        let player = players[index]
        var position = player.position + Vec2(x: 0, y: BallRules.shotReleaseHeight)
        var velocity = player.shotVelocity
        var path: [Vec2] = []
        for step in 0..<(points * stride) {
            velocity.y = max(velocity.y - BallRules.gravity, -BallRules.fallSpeed)
            position += velocity
            if stage.overlapsSolid(Box(center: position, width: BallRules.radius * 2, height: BallRules.radius * 2)) { break }
            if step % stride == 0 { path.append(position) }
        }
        return path
    }
}
