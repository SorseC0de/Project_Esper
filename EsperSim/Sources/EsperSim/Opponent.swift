import Foundation

/// The computer's player. It reads the whole match each frame and gives one frame of
/// input, the way a pad would, so it sits outside the sim like a controller does; with
/// its own little random stream it is deterministic, so it could live inside the sim
/// later. Powerless for now: it runs, walks, jumps, slides, slashes and snatches.
///
/// With the ball it doesn't just go and score. When the other is near and hasn't
/// committed it waits, shuffles, or pump fakes, and the moment they commit to a slash or
/// a snatch it darts past, over them if they're in the way, then shoots from range, the
/// way Silksong's magma flies wait for the swing. Without the ball and the other holding
/// it, it guards the rim they score on rather than chasing them: it walks to a spot
/// between them and the rim and stands there, and only swings when they come into
/// reach, and not every time, since a swing is a window for them. With the ball loose
/// it goes for it, sliding when it's a race, and holds the catch stance when it's coming.
public struct Opponent: Equatable {
    public let index: Int
    private var random: UInt32
    private var plan = Plan.none
    private var planFrames = 0
    private var shuffleDirection = 1.0
    private var fakeHold = 0
    private var stanceFrames = 0
    private var rest = 0
    private var stepFrames = 0

    /// What it's up to.
    public enum Plan: Equatable {
        case none
        /// With the ball: standing, walking back and forth, a pump fake, the dash past,
        /// backing off, and going to score.
        case hold, shuffle, fake, dart, retreat, score
    }

    public init(index: Int, seed: UInt32 = 7) {
        self.index = index
        random = seed
    }

    /// The plan it's on, for the corner readout.
    public var current: Plan { plan }

    /// One frame of input for the match as it stands.
    public mutating func decide(_ match: Match) -> PlayerInput {
        guard match.players.indices.contains(index), let human = match.players.first(where: { $0.index != index }) else { return .idle }
        let me = match.players[index]
        if match.countdown > 0 {
            plan = .none
            planFrames = 0
            stanceFrames = 0
            rest = 0
            return .idle
        }
        var input = PlayerInput.idle
        if me.hasBall {
            offence(match, me: me, human: human, into: &input)
        } else if human.hasBall {
            defence(match, me: me, human: human, into: &input)
        } else {
            neutral(match, me: me, human: human, into: &input)
        }
        return input
    }

    // MARK: Chance

    private mutating func roll(_ sides: UInt32) -> UInt32 {
        random = random &* 1664525 &+ 1013904223
        return (random >> 16) % sides
    }

    private mutating func chance(_ percent: UInt32) -> Bool {
        roll(100) < percent
    }

    private func hoop(scoredOnBy player: Int, in match: Match) -> Hoop {
        match.stage.hoops.first { $0.owner == player } ?? match.stage.hoops[0]
    }

    private static let committedStates: [PlayerState] = [.slashing, .rolling, .snatching, .slide, .catching, .land, .jumpSquat, .walling]

    /// Whether a body's swing or reach is still live: a slash before its blade is spent, a
    /// snatch with the hand still out, a slide.
    private static func dangerous(_ player: Player) -> Bool {
        switch player.state {
        case .slashing: player.stateTimer < SlashRules.liveFrames.upperBound
        case .snatching: player.stateTimer < SnatchRules.activeFrames.upperBound
        case .slide: true
        default: false
        }
    }

    /// Whether a body is committed and spent: in the recovery of a swing or a reach, the
    /// roll, a landing, a catch. The moment to go past it.
    private static func open(_ player: Player) -> Bool {
        switch player.state {
        case .slashing: player.stateTimer >= SlashRules.liveFrames.upperBound
        case .snatching: player.stateTimer >= SnatchRules.activeFrames.upperBound
        case .rolling, .land, .catching, .walling: true
        default: false
        }
    }

    // MARK: With the ball

    private mutating func offence(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) {
        let hoop = hoop(scoredOnBy: index, in: match)
        let toHoop = hoop.position.x - me.position.x
        let toward: Double = toHoop > 0 ? 1 : -1
        let gap = human.position.x - me.position.x
        let level = abs(human.position.y - me.position.y) < 30
        let near = abs(gap) < 45 && level
        let inReach = abs(gap) < 26 && level
        let dangerous = Opponent.dangerous(human)
        let open = Opponent.open(human) && abs(gap) < 60 && level
        let committed = dangerous || open
        let between = (gap > 0) == (toHoop > 0) && abs(gap) < abs(toHoop)

        // In the stance: a fake lets go with down on the ground; a shot holds through the
        // windup with the aim on the rim, then lets go, sooner if they're closing in, which
        // fires it when the windup ends anyway.
        if me.state == .shootStance {
            stanceFrames += 1
            if plan == .fake {
                if stanceFrames >= fakeHold {
                    input.stick = Vec2(x: 0, y: -1)
                    plan = .none
                    planFrames = 0
                } else {
                    input.shoot = true
                }
                return
            }
            if let aim = shotAim(match, from: me, to: hoop) {
                input.aim = aim
                input.shoot = stanceFrames <= BallRules.shotWindupFrames + 1 && !(near && abs(gap) < 20 && !committed)
            } else {
                input.stick = Vec2(x: 0, y: -1)
                plan = .none
                planFrames = 0
            }
            return
        }
        stanceFrames = 0
        if me.state == .shooting || me.state == .catching || me.state == .jumpSquat { return }

        if planFrames > 0 {
            planFrames -= 1
        } else if plan != .none {
            plan = .none
        }
        if plan == .none {
            if open {
                plan = .dart
                planFrames = 40
            } else if dangerous, inReach {
                plan = .retreat
                planFrames = 10
            } else if dangerous, near {
                plan = .hold
                planFrames = 6
            } else if !near || abs(toHoop) < 30 {
                plan = .score
                planFrames = 90
            } else {
                switch roll(10) {
                case 0...3:
                    plan = .hold
                    planFrames = 15 + Int(roll(30))
                case 4...6:
                    plan = .shuffle
                    planFrames = 40 + Int(roll(40))
                    shuffleDirection = chance(50) ? 1 : -1
                case 7...8:
                    plan = .fake
                    fakeHold = 8 + Int(roll(8))
                    planFrames = 30
                default:
                    plan = .dart
                    planFrames = 40
                }
            }
        }
        // Their swing is live while it waits: a step back out of its reach, or just wait.
        // Spent: past them, now.
        if dangerous, inReach, plan == .hold || plan == .shuffle || plan == .fake || plan == .dart {
            plan = .retreat
            planFrames = 10
        } else if dangerous, near, plan == .shuffle || plan == .fake || plan == .dart {
            plan = .hold
            planFrames = 6
        } else if open, plan == .hold || plan == .shuffle || plan == .fake || plan == .retreat {
            plan = .dart
            planFrames = 40
        }
        // They crowd it: away, or straight past.
        if abs(gap) < 16, level, !committed, plan != .dart, plan != .retreat {
            plan = chance(50) ? .dart : .retreat
            planFrames = 30
        }

        switch plan {
        case .hold:
            break
        case .shuffle:
            if planFrames % 20 == 0 { shuffleDirection = -shuffleDirection }
            input.stick = Vec2(x: 0.5 * shuffleDirection, y: 0)
        case .fake:
            input.shoot = true
        case .dart:
            // A frame with the stick centred first, so the push reads as a smash.
            if planFrames >= 39 {
                break
            }
            input.stick = Vec2(x: toward, y: 0)
            if between, abs(gap) < 28, me.grounded {
                input.jump = true
            }
        case .retreat:
            input.stick = Vec2(x: gap > 0 ? -0.5 : 0.5, y: 0)
        case .score:
            if abs(toHoop) > 80 {
                input.stick = Vec2(x: toward, y: 0)
            } else if me.grounded, shotAim(match, from: me, to: hoop) != nil {
                input.shoot = true
            } else if abs(toHoop) > 35 {
                input.stick = Vec2(x: 0.5 * toward, y: 0)
            }
        case .none:
            break
        }
    }

    /// The flick that lands a shot from here nearest the rim, in five-degree steps through
    /// the shot's range, or nil when none comes within twenty units of it.
    private func shotAim(_ match: Match, from me: Player, to hoop: Hoop) -> Vec2? {
        let sign: Double = hoop.position.x > me.position.x ? 1 : -1
        var best: (angle: Double, error: Double)?
        var angle = BallRules.shotAngleMin
        while angle <= BallRules.shotAngleMax + 0.001 {
            var position = me.position + Vec2(x: 0, y: BallRules.shotReleaseHeight)
            var velocity = Vec2(x: cos(angle) * sign, y: sin(angle)) * BallRules.shotSpeed
            var error: Double?
            for _ in 0..<200 {
                let before = position
                velocity.y = max(velocity.y - BallRules.gravity, -BallRules.fallSpeed)
                position += velocity
                if before.y >= hoop.position.y, position.y < hoop.position.y {
                    error = abs(position.x - hoop.position.x)
                    break
                }
                if match.stage.overlapsSolid(Box(center: position, width: BallRules.radius * 2, height: BallRules.radius * 2)) {
                    break
                }
            }
            if let error, error <= 20, best == nil || error < best!.error {
                best = (angle, error)
            }
            angle += degrees(5)
        }
        guard let best else { return nil }
        return Vec2(x: cos(best.angle) * sign, y: sin(best.angle))
    }

    // MARK: The other with the ball

    private mutating func defence(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) {
        let hoop = hoop(scoredOnBy: human.index, in: match)
        let side: Double = human.position.x >= hoop.position.x ? 1 : -1
        let spot = hoop.position.x + side * 25
        let toSpot = spot - me.position.x
        let gap = human.position.x - me.position.x
        let level = abs(human.position.y - me.position.y) < 20
        if rest > 0 { rest -= 1 }
        if Opponent.committedStates.contains(me.state) { return }

        // In reach: mostly the slash, sometimes the snatch when they're right here; not
        // every time, and a rest after, since a swing is a window for them.
        if abs(gap) <= 22, level, rest == 0 {
            let winding = human.state == .shootStance
            let rushing = abs(human.velocity.x) > 2 && (human.velocity.x > 0) == (gap < 0)
            if winding || rushing || chance(3) {
                if abs(gap) <= 12, chance(40) {
                    input.throwBall = true
                } else {
                    input.shoot = true
                }
                rest = 45
                return
            }
        }
        // Between them and the rim, facing them: walk there, run if it's far, and a step
        // at them now and then.
        if abs(toSpot) > 6 {
            let speed = abs(toSpot) > 50 ? 1.0 : 0.5
            input.stick = Vec2(x: toSpot > 0 ? speed : -speed, y: 0)
        } else if me.facing != (gap > 0 ? .right : .left) {
            input.stick = Vec2(x: gap > 0 ? 0.5 : -0.5, y: 0)
        } else if stepFrames > 0 {
            stepFrames -= 1
            input.stick = Vec2(x: gap > 0 ? 0.5 : -0.5, y: 0)
        } else if chance(1) {
            stepFrames = 12
        }
    }

    // MARK: Nobody's ball

    private mutating func neutral(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) {
        let ball = match.ball
        if Opponent.committedStates.contains(me.state) { return }
        guard ball.isLive else { return }
        let target = landing(of: ball, in: match.stage)
        let toBall = target - me.position.x
        let coming = ball.velocity.length > 3 && ball.position.distance(to: me.chest) < 40
        if coming {
            input.shoot = true
        }
        if abs(toBall) > 30 {
            input.stick = Vec2(x: toBall > 0 ? 1 : -1, y: 0)
        } else if abs(toBall) > 5 {
            input.stick = Vec2(x: toBall > 0 ? 0.5 : -0.5, y: 0)
        }
        // A race for it: the slide.
        if me.state == .run, abs(toBall) < 40, abs(human.position.x - target) < abs(toBall) + 15, chance(15) {
            input.stick = Vec2(x: input.stick.x * 0.7, y: -0.8)
        }
        // Over its head and dropping: up for it.
        if ball.position.y > me.position.y + 18, abs(ball.position.x - me.position.x) < 14, me.grounded, ball.velocity.y < 1 {
            input.jump = true
        }
    }

    /// Where the loose ball comes down: its x when it next reaches the floor, off the walls
    /// if it gets there, or where it lies.
    private func landing(of ball: Ball, in stage: Stage) -> Double {
        if ball.resting { return ball.position.x }
        var position = ball.position
        var velocity = ball.velocity
        let floor = Stage.tileSize + BallRules.radius
        for _ in 0..<180 {
            velocity.y = max(velocity.y - BallRules.gravity, -BallRules.fallSpeed)
            position += velocity
            if position.x < Stage.tileSize + BallRules.radius || position.x > stage.width - Stage.tileSize - BallRules.radius {
                velocity.x = -velocity.x * BallRules.bounce
                position.x = min(max(position.x, Stage.tileSize + BallRules.radius), stage.width - Stage.tileSize - BallRules.radius)
            }
            if position.y <= floor, velocity.y < 0 { return position.x }
        }
        return position.x
    }
}
