import Foundation

/// The computer's player. It reads the whole match each frame and gives one frame of
/// input, the way a pad would, so it sits outside the sim like a controller does; with
/// its own little random stream it is deterministic, so it could live inside the sim
/// later. Powerless for now: it runs, walks, jumps, slides, slashes, snatches, throws
/// and catches.
///
/// With the ball it works toward one of its shot spots, two on the floor in front of
/// its rim and one up on the ledge, and shoots from there, standing or off a jump. When
/// the other is in the way and hasn't committed it stands, shuffles, pump fakes, lobs
/// the ball up and over to run under, or goes over them with a double jump; while their
/// swing is live it steps out of reach and waits, and the moment it's spent it darts
/// past, the way Silksong's magma flies wait for the swing. It never waits for long.
/// Without the ball and the other holding it, it guards the rim they score on and
/// strikes when they wind up a shot, come into reach, or stand about: a dash in and the
/// slash, the snatch up close. With the ball loose it goes to where the ball comes
/// down, over its head with both jumps if it has to, and times a snatch or a slash for
/// a ball in flight. It leaves its own shot alone while it's in the air.
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
    /// Dances in a row without getting anywhere, so it doesn't wait forever.
    private var dances = 0
    private var spot: Spot?
    private var jumpShot = false
    /// The jump's button held through the squat, so the hop is full.
    private var wantsFullHop = false
    private var humanStill = 0
    /// Last frame's output, to make a press an edge.
    private var pressed = PlayerInput.idle

    /// What it's up to.
    public enum Plan: Equatable {
        case none
        /// With the ball: standing, walking back and forth, a pump fake, the dash past,
        /// backing off, going to the spot, shooting from it, the lob up and over, over
        /// them on two jumps, and climbing out from behind the block.
        case hold, shuffle, fake, dart, retreat, travel, shoot, lob, over, climb
        /// Without it: the guard spot, walking up to press, the dash in and swing, and
        /// hanging back a little off the rim.
        case guardSpot, pressure, strike, hover
        /// With it near the rim: up and onto it.
        case dunk
    }

    /// Where it likes to shoot from: two distances on the floor in front of the rim, and
    /// the end of the ledge nearest it.
    public enum Spot: Equatable { case nearFloor, farFloor, ledge }

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
        var input = PlayerInput.idle
        if match.countdown > 0 {
            plan = .none
            planFrames = 0
            stanceFrames = 0
            rest = 0
            dances = 0
            spot = nil
            pressed = .idle
            return .idle
        }
        humanStill = abs(human.velocity.x) < 0.2 && (human.state == .idle || human.state == .crouch) ? humanStill + 1 : 0
        if me.state == .jumpSquat {
            // Through the squat the button stays down for a full hop, or up for a short one.
            input.jump = wantsFullHop
        } else if me.hasBall {
            offence(match, me: me, human: human, into: &input)
        } else if human.hasBall {
            defence(match, me: me, human: human, into: &input)
        } else {
            neutral(match, me: me, human: human, into: &input)
        }
        pressed = input
        return input
    }

    // MARK: Chance and presses

    private mutating func roll(_ sides: UInt32) -> UInt32 {
        random = random &* 1664525 &+ 1013904223
        return (random >> 16) % sides
    }

    private mutating func chance(_ percent: UInt32) -> Bool {
        roll(100) < percent
    }

    /// A press is an edge: down this frame only if it was up last frame.
    private func tapJump(_ input: inout PlayerInput) { input.jump = !pressed.jump }
    private func tapShoot(_ input: inout PlayerInput) { input.shoot = !pressed.shoot }
    private func tapThrow(_ input: inout PlayerInput) { input.throwBall = !pressed.throwBall }

    private mutating func fullHop(_ input: inout PlayerInput) {
        wantsFullHop = true
        input.jump = true
    }

    private func hoop(scoredOnBy player: Int, in match: Match) -> Hoop {
        match.stage.hoops.first { $0.owner == player } ?? match.stage.hoops[0]
    }

    /// The states a body can't act out of.
    private static let committedStates: [PlayerState] = [.slashing, .rolling, .snatching, .slide, .catching, .land, .walling, .shooting, .throwing, .ledgeHang, .ledgeClimb]

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
    /// roll, a landing, a catch. The moment to go past it, or at it.
    private static func open(_ player: Player) -> Bool {
        switch player.state {
        case .slashing: player.stateTimer >= SlashRules.liveFrames.upperBound
        case .snatching: player.stateTimer >= SnatchRules.activeFrames.upperBound
        case .rolling, .land, .catching, .walling, .shooting, .throwing: true
        default: false
        }
    }

    // MARK: With the ball

    /// Where a spot is for this rim: the inside is the court's side of it.
    private func place(of spot: Spot, for hoop: Hoop, in stage: Stage) -> Vec2 {
        let inward = -hoop.backboard.sign
        switch spot {
        case .nearFloor: return Vec2(x: hoop.position.x + inward * 45, y: Stage.tileSize)
        case .farFloor: return Vec2(x: hoop.position.x + inward * 70, y: Stage.tileSize)
        case .ledge:
            // The court's one-way ledge: its end nearest the rim, a little in from the edge.
            let ledgeRow = 3
            var columns: [Int] = []
            for column in 0..<stage.columns where stage.tile(column: column, row: ledgeRow) == .oneWay { columns.append(column) }
            guard let low = columns.min(), let high = columns.max() else { return Vec2(x: hoop.position.x + inward * 70, y: Stage.tileSize) }
            let x = inward > 0 ? Double(low) * Stage.tileSize + 8 : Double(high + 1) * Stage.tileSize - 8
            return Vec2(x: x, y: Double(ledgeRow + 1) * Stage.tileSize)
        }
    }

    private mutating func offence(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) {
        let hoop = hoop(scoredOnBy: index, in: match)
        let inward = -hoop.backboard.sign
        let toHoop = hoop.position.x - me.position.x
        let gap = human.position.x - me.position.x
        let level = abs(human.position.y - me.position.y) < 30
        let near = abs(gap) < 50 && level
        let inReach = abs(gap) < 26 && level
        let dangerous = Opponent.dangerous(human)
        let open = Opponent.open(human) && abs(gap) < 60 && level
        let committed = dangerous || open
        // Behind the block: on the backboard's side of the rim, past the block's face.
        let behind = (me.position.x - hoop.position.x) * hoop.backboard.sign > 5 && me.position.y < 90

        // In the stance: a fake lets go with down on the ground; a shot holds through the
        // windup with the aim on the rim, then lets go, sooner if they're closing in; a
        // jump shot hops out of the stance after the windup and lets go on the rise with
        // the aim solved for the lift.
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
            if jumpShot {
                if me.grounded {
                    input.shoot = true
                    if stanceFrames > BallRules.shotWindupFrames { fullHop(&input) }
                } else {
                    let aim = shotAim(match, from: me.position, lift: max(me.velocity.y, 0), to: hoop) ?? shotAim(match, from: me.position, lift: 0, to: hoop)
                    input.aim = aim ?? Vec2(x: Trig.cos(BallRules.shotAngleDefault) * inward, y: Trig.sin(BallRules.shotAngleDefault))
                    input.shoot = me.velocity.y > 2.4
                }
                return
            }
            if let aim = shotAim(match, from: me.position, lift: 0, to: hoop) {
                input.aim = aim
                input.shoot = stanceFrames <= BallRules.shotWindupFrames + 1 && !(inReach && !committed)
            } else {
                input.stick = Vec2(x: 0, y: -1)
                plan = .none
                planFrames = 0
                spot = nil
            }
            return
        }
        stanceFrames = 0
        if me.state == .throwStance {
            // The lob: up, and let go once the windup has passed.
            input.stick = Vec2(x: 0, y: 1)
            input.throwBall = me.stateTimer < BallRules.throwWindupFrames + 1
            return
        }
        if Opponent.committedStates.contains(me.state) { return }

        if planFrames > 0 {
            planFrames -= 1
        } else if plan != .none {
            plan = .none
        }
        if spot == nil || (spot == .ledge && human.position.y > 35) {
            spot = pickSpot(match, me: me, human: human, hoop: hoop)
        }
        guard let spot else { return }
        let target = place(of: spot, for: hoop, in: match.stage)
        let atSpot = abs(target.x - me.position.x) < 6 && abs(target.y - me.position.y) < 4 && me.grounded
        let blocked = (gap > 0) == (target.x - me.position.x > 0) && abs(gap) < abs(target.x - me.position.x) + 10 && near

        // Near enough the rim and level with its floor: the dunk, up and onto it.
        let rimClose = abs(toHoop) < 55 && me.position.y < hoop.position.y && hoop.position.y - me.position.y < 60
        if behind {
            plan = .climb
            planFrames = 1
        } else if plan == .none, rimClose, !(dangerous && inReach), chance(70) {
            plan = .dunk
            planFrames = 60
        } else if plan == .none {
            if open {
                plan = .dart
                planFrames = 40
                dances = 0
            } else if dangerous, inReach {
                plan = .retreat
                planFrames = 10
            } else if dangerous, near {
                plan = .hold
                planFrames = 6
            } else if atSpot {
                plan = .shoot
                planFrames = 90
                jumpShot = spot != .ledge && chance(50)
                dances = 0
            } else if blocked, !committed {
                dances += 1
                if dances > 3 {
                    // Enough waiting: up and over, the lob, or another spot.
                    dances = 0
                    switch roll(3) {
                    case 0: plan = .over; planFrames = 45
                    case 1: plan = .lob; planFrames = 60
                    default:
                        self.spot = spot == .ledge ? .farFloor : .ledge
                        plan = .travel; planFrames = 30
                    }
                } else {
                    switch roll(12) {
                    case 0...2:
                        plan = .hold
                        planFrames = 15 + Int(roll(25))
                    case 3...5:
                        plan = .shuffle
                        planFrames = 40 + Int(roll(30))
                        shuffleDirection = chance(50) ? 1 : -1
                    case 6...7:
                        plan = .fake
                        fakeHold = 8 + Int(roll(8))
                        planFrames = 30
                    case 8:
                        plan = .lob
                        planFrames = 60
                    case 9:
                        plan = .over
                        planFrames = 45
                    default:
                        plan = .dart
                        planFrames = 40
                    }
                }
            } else {
                plan = .travel
                planFrames = 20
            }
        }
        // Their swing is live while it waits: a step back out of its reach, or just wait.
        // Spent: past them, now.
        if dangerous, inReach, [.hold, .shuffle, .fake, .dart, .travel].contains(plan) {
            plan = .retreat
            planFrames = 10
        } else if dangerous, near, [.shuffle, .fake, .travel].contains(plan) {
            plan = .hold
            planFrames = 6
        } else if open, [.hold, .shuffle, .fake, .retreat, .travel].contains(plan) {
            plan = .dart
            planFrames = 40
        }
        // They crowd it: away, straight past, or the floater up and over them.
        if abs(gap) < 16, level, !committed, ![.dart, .retreat, .over, .lob, .dunk].contains(plan) {
            switch roll(10) {
            case 0...3: plan = .dart
            case 4...6: plan = .retreat
            default: plan = .lob
            }
            planFrames = 30
        }

        switch plan {
        case .hold:
            break
        case .shuffle:
            if planFrames % 20 == 0 { shuffleDirection = -shuffleDirection }
            input.stick = Vec2(x: 0.5 * shuffleDirection, y: 0)
            if planFrames == 10, me.grounded, chance(30) { fullHop(&input) }
        case .fake:
            input.shoot = true
        case .dart:
            // A frame with the stick centred first, so the push reads as a smash.
            if planFrames >= 39 { break }
            input.stick = Vec2(x: toHoop > 0 ? 1 : -1, y: 0)
            let between = (gap > 0) == (toHoop > 0) && abs(gap) < abs(toHoop)
            if between, abs(gap) < 30, me.grounded {
                fullHop(&input)
            } else if !me.grounded, me.velocity.y < 0.5, me.jumpsLeft > 0, between, abs(gap) < 20 {
                tapJump(&input)
            }
        case .retreat:
            input.stick = Vec2(x: gap > 0 ? -0.5 : 0.5, y: 0)
        case .travel:
            travel(to: target, me: me, human: human, into: &input)
        case .shoot:
            if !atSpot, me.grounded {
                plan = .none
            } else if me.grounded {
                input.shoot = true
            }
        case .lob:
            // The throw stance with up; the stance handler lets it go.
            input.stick = Vec2(x: 0, y: 1)
            input.throwBall = true
        case .over:
            // Up and over toward the rim: a full hop, the double jump at the top.
            input.stick = Vec2(x: toHoop > 0 ? 1 : -1, y: 0)
            if me.grounded {
                fullHop(&input)
            } else if me.velocity.y < 0.5, me.jumpsLeft > 0 {
                tapJump(&input)
            }
        case .climb:
            climbOut(me: me, hoop: hoop, into: &input)
        case .dunk:
            // In under the rim, a full hop when it's close, and the throw held in the air
            // so the stance carries it onto the rim.
            input.stick = Vec2(x: toHoop > 0 ? 1 : -1, y: 0)
            if me.grounded, abs(toHoop) < 34 {
                fullHop(&input)
            } else if !me.grounded {
                if me.velocity.y < 0.5, me.jumpsLeft > 0, hoop.position.y - me.chest.y > 20 { tapJump(&input) }
                if hoop.position.distance(to: me.chest) < 45 { input.throwBall = true }
            }
            if planFrames == 0 { plan = .none }
        default:
            plan = .none
        }
    }

    /// A spot for this attack: the ledge when the way along the floor is blocked or by
    /// chance, the far floor spot most of the rest of the time, the near one otherwise.
    private mutating func pickSpot(_ match: Match, me: Player, human: Player, hoop: Hoop) -> Spot {
        let gap = human.position.x - me.position.x
        let toHoop = hoop.position.x - me.position.x
        let humanBetween = (gap > 0) == (toHoop > 0) && abs(gap) < abs(toHoop)
        if human.position.y < 35, humanBetween, chance(50) { return .ledge }
        switch roll(10) {
        case 0...2: return .ledge
        case 3...6: return .farFloor
        default: return .nearFloor
        }
    }

    /// Along the floor to under the target, then up onto it if it's the ledge: a full hop
    /// and the double jump at the top when it's still short.
    private mutating func travel(to target: Vec2, me: Player, human: Player, into input: inout PlayerInput) {
        let dx = target.x - me.position.x
        let dy = target.y - me.position.y
        if dy > 5 {
            if abs(dx) > 8, me.grounded {
                input.stick = Vec2(x: dx > 0 ? (abs(dx) > 40 ? 1 : 0.5) : (abs(dx) > 40 ? -1 : -0.5), y: 0)
            } else if me.grounded {
                fullHop(&input)
            } else {
                input.stick = Vec2(x: dx > 0 ? 0.5 : -0.5, y: 0)
                if me.velocity.y < 0.5, me.jumpsLeft > 0, me.position.y < target.y - 5 { tapJump(&input) }
            }
            return
        }
        if abs(dx) > 40 {
            input.stick = Vec2(x: dx > 0 ? 1 : -1, y: 0)
        } else if abs(dx) > 4 {
            input.stick = Vec2(x: dx > 0 ? 0.5 : -0.5, y: 0)
        }
    }

    /// Out from behind the block: to the wall, a full hop, the wall jump off it, the
    /// double jump inward over the block.
    private mutating func climbOut(me: Player, hoop: Hoop, into input: inout PlayerInput) {
        let wallward = hoop.backboard.sign
        if me.grounded {
            input.stick = Vec2(x: wallward, y: 0)
            fullHop(&input)
        } else if me.state == .wallLand {
            input.stick = Vec2(x: wallward, y: 0)
            tapJump(&input)
        } else if me.wallSide != nil, me.wallLandCooldown == 0 {
            // Into the wall for the cling; the jump comes out of that.
            input.stick = Vec2(x: wallward, y: 0)
        } else if me.velocity.y < 0.5, me.jumpsLeft > 0 {
            input.stick = Vec2(x: -wallward, y: 0)
            tapJump(&input)
        } else {
            input.stick = Vec2(x: me.position.y > 85 ? -wallward : wallward, y: 0)
        }
    }

    /// The flick that lands a shot from here nearest the rim, with `lift` added to its
    /// rise, in five-degree steps through the shot's range, or nil when none comes within
    /// twenty units of it.
    private func shotAim(_ match: Match, from feet: Vec2, lift: Double, to hoop: Hoop) -> Vec2? {
        let sign: Double = hoop.position.x > feet.x ? 1 : -1
        var best: (angle: Double, error: Double)?
        var angle = BallRules.shotAngleMin
        while angle <= BallRules.shotAngleMax + 0.001 {
            var position = feet + Vec2(x: 0, y: BallRules.shotReleaseHeight)
            var velocity = Vec2(x: Trig.cos(angle) * sign, y: Trig.sin(angle)) * match.players[index].spec.shotSpeed + Vec2(x: 0, y: lift)
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
        return Vec2(x: Trig.cos(best.angle) * sign, y: Trig.sin(best.angle))
    }

    // MARK: The other with the ball

    private mutating func defence(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) {
        let hoop = hoop(scoredOnBy: human.index, in: match)
        let side: Double = human.position.x >= hoop.position.x ? 1 : -1
        let guardX = hoop.position.x + side * 25
        let toGuard = guardX - me.position.x
        let gap = human.position.x - me.position.x
        let rise = human.position.y - me.position.y
        let level = abs(rise) < 20
        if rest > 0 { rest -= 1 }
        if Opponent.committedStates.contains(me.state) { return }
        if planFrames > 0 { planFrames -= 1 } else if plan != .none { plan = .none }

        // Their swing just started within reach: the hand out to parry it, mostly.
        if human.state == .slashing, human.stateTimer < SlashRules.liveFrames.lowerBound, abs(gap) <= 30, level, me.snatchCooldown == 0 {
            if chance(70) {
                tapThrow(&input)
                rest = 30
                return
            }
            input.stick = Vec2(x: gap > 0 ? -1 : 1, y: 0)
            return
        }
        let winding = human.state == .shootStance || (human.state == .throwStance && abs(gap) < 30)
        let humanOpen = Opponent.open(human)
        if winding || plan == .strike || (humanOpen && abs(gap) < 45) || (rest == 0 && abs(gap) < 45 && humanStill > 20 && chance(4)) {
            // The strike: in at them and the swing when the blade will reach, up first if
            // they're above. In reach, the slash, or the snatch up close.
            plan = .strike
            planFrames = 30
            if abs(gap) <= 24, rise < 24, rise > -20 {
                if rise > 8, me.grounded {
                    fullHop(&input)
                    input.stick = Vec2(x: gap > 0 ? 1 : -1, y: 0)
                    return
                }
                if abs(gap) <= 12, chance(40) { tapThrow(&input) } else { tapShoot(&input) }
                rest = 40
                plan = .none
                planFrames = 0
                return
            }
            input.stick = Vec2(x: gap > 0 ? 1 : -1, y: 0)
            if rise > 14, me.grounded, abs(gap) < 40 { fullHop(&input) }
            return
        }
        if rest == 0, abs(gap) <= 22, level, chance(3) {
            if abs(gap) <= 12, chance(40) { tapThrow(&input) } else { tapShoot(&input) }
            rest = 40
            return
        }
        // Standing about far from the rim, they're asking for it: walk up to them.
        if plan == .none, humanStill > 60, abs(gap) > 30, abs(human.position.x - hoop.position.x) > 60 {
            plan = .pressure
            planFrames = 120
        }
        if plan == .pressure {
            if abs(gap) > 32 {
                input.stick = Vec2(x: gap > 0 ? (abs(gap) > 70 ? 1 : 0.5) : (abs(gap) > 70 ? -1 : -0.5), y: 0)
            } else {
                plan = .strike
                planFrames = 30
            }
            return
        }
        // Mostly between them and the rim; now and then up to them, or hanging back a
        // way off the rim, so it isn't always in the same place.
        if plan == .none {
            switch roll(10) {
            case 0...5: plan = .guardSpot
            case 6...7: plan = .pressure
            default: plan = .hover
            }
            planFrames = 60 + Int(roll(90))
        }
        if plan == .hover {
            let hoverX = hoop.position.x + side * (55 + Double(roll(2)) * 10)
            let toHover = hoverX - me.position.x
            if abs(toHover) > 8 { input.stick = Vec2(x: toHover > 0 ? 0.5 : -0.5, y: 0) }
            return
        }
        if abs(toGuard) > 6 {
            let speed = abs(toGuard) > 50 ? 1.0 : 0.5
            input.stick = Vec2(x: toGuard > 0 ? speed : -speed, y: 0)
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
        plan = .none
        if Opponent.committedStates.contains(me.state) { return }
        guard ball.isLive else { return }
        // Its own shot, still on its way: let it go in, and wait under the rim for a miss.
        if ball.shotInFlight, ball.lastTouched == index {
            let hoop = hoop(scoredOnBy: index, in: match)
            let spot = hoop.position.x - hoop.backboard.sign * 30
            let toSpot = spot - me.position.x
            if abs(toSpot) > 6 { input.stick = Vec2(x: toSpot > 0 ? 0.5 : -0.5, y: 0) }
            return
        }
        if human.state == .slashing, human.stateTimer < SlashRules.liveFrames.lowerBound,
           abs(human.position.x - me.position.x) <= 30, abs(human.position.y - me.position.y) < 20, me.snatchCooldown == 0, chance(70) {
            tapThrow(&input)
            return
        }
        let target = landing(of: ball, in: match.stage)
        let toBall = target - me.position.x
        let above = ball.position.y - me.position.y
        // A ball in flight about to be in reach: the snatch to take it, timed for the hand,
        // or the slash to spike it, by chance.
        if ball.velocity.length > 2 {
            let soon = ballPosition(ball, after: 6)
            let inHand = soon.distance(to: me.handCatchPoint) <= BallRules.handCatchRadius || soon.distance(to: me.chest) <= BallRules.catchRadius
            let inBlade = abs(soon.x - me.bladeCentre.x) <= SlashRules.reach && abs(soon.y - me.bladeCentre.y) <= SlashRules.reach
            if inHand, me.snatchCooldown == 0, chance(70) {
                tapThrow(&input)
                return
            } else if inBlade, chance(50) {
                tapShoot(&input)
                return
            }
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
        // Over its head and staying there: up for it, both jumps if it's high.
        if above > 15, abs(ball.position.x - me.position.x) < 14, ball.velocity.y < 1 {
            if me.grounded {
                fullHop(&input)
            } else if me.velocity.y < 0.5, me.jumpsLeft > 0, above > 10 {
                tapJump(&input)
            }
        }
    }

    /// Where the ball will be this many frames on, falling as it does.
    private func ballPosition(_ ball: Ball, after frames: Int) -> Vec2 {
        var position = ball.position
        var velocity = ball.velocity
        for _ in 0..<frames {
            if ball.floater == 0 { velocity.y = max(velocity.y - BallRules.gravity, -BallRules.fallSpeed) }
            position += velocity
        }
        return position
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
