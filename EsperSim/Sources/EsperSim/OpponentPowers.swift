import Foundation

/// The biomorph in hand, used as a person would: Z Tea's blasts and beam, Pulsepistol Punch's
/// pulses, Volta Cola's bolts, Gale Ale's tornados, Blazing Boba's fireballs, Platform Protein
/// Shake's platforms and walls, Flash Fizz's warp, Web Water's line and Super Smoothie's flight.
/// What a power does on its own (Frost Tea, Titan Tea, the double jumps) needs nothing of it.
extension Opponent {
    /// A power's move that takes more than a frame of input.
    enum PowerMove: Equatable {
        /// Z Tea's blasts, pressed again while the pose lasts, this many more.
        case blastRun(left: Int)
        /// Web Water's line: aimed while the throw button's held, let go to fire.
        case webLine
        /// Blazing Boba's fireball, summoned, then thrown at the other: frames since the summon.
        case fireball(frames: Int)
        /// Super Smoothie's flight, jump held, steered at the ball or the rim: frames flown.
        case flight(frames: Int)
    }

    /// Between one look at a power and the next, after it's used or passed up.
    static let powerRestFrames: ClosedRange<Int> = 30...90
    /// A chance worth taking is taken this often.
    static let powerUseChance: UInt32 = 60
    /// The beam's charge is a second stood still, so it's taken less.
    static let beamChance: UInt32 = 35
    /// How level a straight shot's target has to be, up or down from the chest.
    static let levelBand = 20.0
    static let pulseBand = 10.0
    static let galeBand = 14.0
    /// Z Tea's run: follow-up blasts at level one and level two, at most.
    static let blastRunLevelOne = 2
    static let blastRunLevelTwo = 4
    /// The fireball's summon pose played out before the throw, and the throw's hold.
    static let fireballThrowAfter = BlazeRules.summonPoseFrames + 2
    static let fireballHoldFrames = 8
    static let fireballGiveUp = 120
    /// Super Smoothie: a ball or rim this far over the body is worth flying for; a flight gives up after this long.
    static let flightRise = 50.0
    static let flightGiveUp = 180
    /// Platform Protein Shake: the goal this far over the feet, falling, is worth a platform under them.
    static let platformRise = 30.0
    /// Flash Fizz: a loose ball this far off is worth the warp.
    static let warpDistance = 90.0

    /// One frame of the biomorph's use, when there's one worth making; true when the input's its.
    mutating func usePower(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        if powerRest > 0 { powerRest -= 1 }
        if me.hitStun > 0 || me.frozen > 0 {
            powerMove = nil
            return false
        }
        if let move = powerMove { return continuePowerMove(move, match, me: me, human: human, into: &input) }
        if me.state == .beamCharging || me.state == .beamFiring {
            aimBeam(me: me, at: human.chest, into: &input)
            return true
        }
        guard powerRest == 0, Opponent.powerReadyStates.contains(me.state) else { return false }
        switch me.power {
        case .zTea: return zTea(match, me: me, human: human, into: &input)
        case .pulsepistol: return pulse(match, me: me, human: human, into: &input)
        case .voltaCola: return bolt(match, me: me, human: human, into: &input)
        case .galeAle: return gale(match, me: me, human: human, into: &input)
        case .blazingBoba: return fireball(match, me: me, human: human, into: &input)
        case .platformShake: return platform(match, me: me, human: human, into: &input)
        case .flashFizz: return warp(match, me: me, into: &input)
        case .webWater: return webLine(match, me: me, human: human, into: &input)
        case .superSmoothie: return flight(match, me: me, into: &input)
        case .phantomFrappe: return solidify(match, me: me, into: &input)
        default: return false
        }
    }

    /// Phantom Frappe, should a Spin Move have turned it phantom: back solid with the taunt once the
    /// ball's in hand on the ground, to be able to score.
    private func solidify(_ match: Match, me: Player, into input: inout PlayerInput) -> Bool {
        guard me.phantomMode, me.hasBall, me.grounded else { return false }
        input.taunt = match.frame % 2 == 0
        return true
    }

    /// The states a power's press is made from.
    static let powerReadyStates: Set<PlayerState> = [.idle, .walk, .run, .dash, .crouch, .crouchWalk, .air]

    // MARK: Aiming

    /// What a shot is worth aiming at: the other with the ball, winding up, or beside it loose.
    private func powerTarget(_ match: Match, human: Player) -> Vec2? {
        // Breaker Ball: their barrier while it stands.
        if Opponent.breaker(match), let theirs = Opponent.defendedRim(match, by: human.index), match.stage.hoops[theirs].barrierStanding {
            return match.stage.hoops[theirs].position
        }
        if human.hasBall || human.state == .shootStance || human.state == .throwStance { return human.chest }
        if match.ball.isLive, match.ball.position.distance(to: human.chest) < 60 { return human.chest }
        return nil
    }

    /// The target out in front at the chest's height, within reach across.
    private func level(_ me: Player, _ target: Vec2, reach: ClosedRange<Double>, band: Double) -> Bool {
        reach.contains(abs(target.x - me.position.x)) && abs(target.y - me.chest.y) <= band
    }

    private func sign(from me: Player, to target: Vec2) -> Double { target.x >= me.position.x ? 1 : -1 }

    /// Turned to the target first: on the ground a half push of the stick, a walk, not a dash; in the
    /// air the body can't turn, so it's no shot. True while it's turning or can't.
    private func turnToward(_ me: Player, _ target: Vec2, into input: inout PlayerInput) -> Bool {
        let way = sign(from: me, to: target)
        guard me.facing.sign != way else { return false }
        if me.grounded { input.stick = Vec2(x: way * 0.5, y: 0) }
        return true
    }

    /// A chance seen: taken some of the time, and either way not looked at again for a while.
    private mutating func takes(_ percent: UInt32 = Opponent.powerUseChance) -> Bool {
        powerRest = Opponent.powerRestFrames.lowerBound + Int(roll(UInt32(Opponent.powerRestFrames.count)))
        return chance(percent)
    }

    /// The stick toward a point, kept off the full down that would crouch or fast fall.
    private func stick(from origin: Vec2, to target: Vec2) -> Vec2 {
        let toward = (target - origin).normalized
        return Vec2(x: toward.x, y: min(max(toward.y, -0.6), 0.6))
    }

    // MARK: Z Tea

    private mutating func zTea(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        guard !me.holding else { return false }
        // A stored beam (level two) let go the moment they're in front.
        if me.beamStored, level(me, human.chest, reach: 40...400, band: Opponent.levelBand * 2) {
            if turnToward(me, human.chest, into: &input) { return true }
            guard takes() else { return false }
            input.stick = Vec2(x: 0, y: -1)
            tapShoot(&input)
            return true
        }
        guard let target = powerTarget(match, human: human) else { return false }
        if me.grounded, !me.beamStored, level(me, target, reach: 120...400, band: Opponent.levelBand * 2), human.state != .air {
            if turnToward(me, target, into: &input) { return true }
            if takes(Opponent.beamChance) {
                input.stick = Vec2(x: 0, y: -1)
                tapShoot(&input)
                return true
            }
        }
        guard me.blastCooldown == 0, me.blastStep == nil, level(me, target, reach: 24...260, band: Opponent.levelBand) else { return false }
        if turnToward(me, target, into: &input) { return true }
        guard takes() else { return false }
        input.stick = Vec2(x: sign(from: me, to: target) * 0.4, y: 0.9)
        tapShoot(&input)
        let most = me.powerLevel >= 2 ? Opponent.blastRunLevelTwo : Opponent.blastRunLevelOne
        powerMove = .blastRun(left: Int(roll(UInt32(most + 1))))
        return true
    }

    /// The beam's charge and its firing aimed at the other: the stick across to face them, up or down for the angle.
    private func aimBeam(me: Player, at target: Vec2, into input: inout PlayerInput) {
        input.stick = stick(from: me.beamOrigin, to: target)
    }

    // MARK: Pulsepistol Punch

    private mutating func pulse(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        guard !me.holding, me.pulseCooldown == 0 else { return false }
        let ball = match.ball
        let pullBall = ball.isLive && ball.position.distance(to: me.chest) > 60 && level(me, ball.position, reach: 60...300, band: Opponent.pulseBand)
        guard pullBall || human.hasBall && level(me, human.chest, reach: 20...300, band: Opponent.pulseBand) else { return false }
        let target = pullBall ? ball.position : human.chest
        if turnToward(me, target, into: &input) { return true }
        guard takes() else { return false }
        // The loose ball pulled in; the one in their hands pulled to it, or pushed off them.
        let pull = pullBall || chance(60)
        input.stick = Vec2(x: 0, y: pull ? 1 : -1)
        tapShoot(&input)
        return true
    }

    // MARK: Volta Cola

    private mutating func bolt(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        guard !me.holding, me.boltCooldown == 0, let target = powerTarget(match, human: human),
              level(me, target, reach: 50...300, band: Opponent.levelBand * 1.5) else { return false }
        if turnToward(me, target, into: &input) { return true }
        guard takes() else { return false }
        tapShoot(&input)
        return true
    }

    // MARK: Gale Ale

    /// Level two's moving tornado, at the other with the ball: it strips them and carries it off.
    private mutating func gale(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        guard me.powerLevel >= 2, !me.holding, me.blastCooldown == 0, human.hasBall,
              level(me, human.chest, reach: 30...250, band: Opponent.galeBand) else { return false }
        if turnToward(me, human.chest, into: &input) { return true }
        guard takes() else { return false }
        input.stick = Vec2(x: 0, y: 1)
        tapShoot(&input)
        return true
    }

    // MARK: Blazing Boba

    private mutating func fireball(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        guard me.powerLevel >= 2, !me.holding, human.hasBall else { return false }
        let across = abs(human.position.x - me.position.x)
        guard (50...250).contains(across), takes() else { return false }
        input.stick = Vec2(x: 0, y: 1)
        tapShoot(&input)
        powerMove = .fireball(frames: 0)
        return true
    }

    // MARK: Platform Protein Shake

    private mutating func platform(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        // Level two's wall, stood up in front of a shot or a throw being wound up close by.
        if me.powerLevel >= 2, me.grounded, !me.holding, me.platformCooldown == 0,
           human.state == .shootStance || human.state == .throwStance,
           level(me, human.chest, reach: 30...90, band: Opponent.levelBand) {
            if turnToward(me, human.chest, into: &input) { return true }
            guard takes() else { return false }
            input.stick = Vec2(x: 0, y: 1)
            tapShoot(&input)
            return true
        }
        // Falling short of where it's going: the fast fall that lays a platform under the feet.
        guard me.state == .air, me.velocity.y <= 0, !me.fastFalling, me.platformCooldown == 0 else { return false }
        let goal = me.hasBall ? hoop(scoredOnBy: index, in: match).position : match.ball.position
        guard goal.y - me.position.y > Opponent.platformRise, takes() else { return false }
        input.stick = Vec2(x: 0, y: -1)
        return true
    }

    // MARK: Flash Fizz

    /// The warp to a loose ball far off: its own after a throw or a shot, any at level two.
    private mutating func warp(_ match: Match, me: Player, into input: inout PlayerInput) -> Bool {
        let ball = match.ball
        guard !me.holding, me.warpCooldown == 0, ball.isLive, me.powerLevel >= 2 || ball.owner == index,
              ball.position.distance(to: me.chest) > Opponent.warpDistance, takes() else { return false }
        input.stick = Vec2(x: 0, y: 1)
        tapShoot(&input)
        return true
    }

    // MARK: Web Water

    /// Level two's line, at the loose ball in reach or the ball in the other's hands.
    private mutating func webLine(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        guard me.powerLevel >= 2, !me.holding, me.webLineCooldown == 0, !pressed.throwBall,
              let target = webTarget(match, me: me, human: human), takes() else { return false }
        input.stick = (target - me.chest).normalized
        input.throwBall = true
        powerMove = .webLine
        return true
    }

    private func webTarget(_ match: Match, me: Player, human: Player) -> Vec2? {
        let reach = 30.0...(WebRules.lineRange - 8)
        if match.ball.isLive, reach.contains(match.ball.position.distance(to: me.chest)) { return match.ball.position }
        if human.hasBall, reach.contains(human.chest.distance(to: me.chest)) { return human.chest }
        return nil
    }

    // MARK: Super Smoothie

    /// Flight at a loose ball high over it, or with the ball up to the rim for the dunk; at level
    /// two, off the floor with the Super Jump.
    private mutating func flight(_ match: Match, me: Player, into input: inout PlayerInput) -> Bool {
        guard me.flightLeft > 0, !pressed.jump, flightGoal(match, me: me) != nil else { return false }
        let superJump = me.grounded && me.powerLevel >= 2
        guard me.state == .air || superJump, takes() else { return false }
        if superJump { input.stick = Vec2(x: 0, y: 1) }
        input.jump = true
        powerMove = .flight(frames: 0)
        return true
    }

    /// Where a flight goes: the loose ball well over the body, or with it beside the rim it scores on.
    private func flightGoal(_ match: Match, me: Player) -> Vec2? {
        if me.hasBall {
            let rim = hoop(scoredOnBy: index, in: match).position
            guard rim.y - me.chest.y > Opponent.flightRise else { return nil }
            return rim
        }
        guard match.ball.isLive, match.ball.position.y - me.chest.y > Opponent.flightRise,
              abs(match.ball.position.x - me.position.x) < 200 else { return nil }
        return match.ball.position
    }

    // MARK: Moves under way

    private mutating func continuePowerMove(_ move: PowerMove, _ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        switch move {
        case .blastRun(let left):
            guard left > 0, me.blastStep != nil else {
                powerMove = nil
                return me.blastStep != nil
            }
            // Turned and aimed at them, the next pressed once the last is off.
            input.stick = stick(from: me.chest, to: human.chest)
            if abs(input.stick.x) < 0.3 { input.stick.x = sign(from: me, to: human.chest) * 0.3 }
            if !me.blastQueued, !pressed.shoot {
                input.shoot = true
                powerMove = .blastRun(left: left - 1)
            }
            return true
        case .webLine:
            // Let go, still aimed: the line fires.
            if let target = webTarget(match, me: me, human: human) { input.stick = (target - me.chest).normalized }
            powerMove = nil
            return true
        case .fireball(let frames):
            guard frames < Opponent.fireballGiveUp, frames == 0 || me.hasFireball else {
                powerMove = nil
                return false
            }
            powerMove = .fireball(frames: frames + 1)
            // Buttons up while it gathers, then the throw at them, held a moment and let go.
            let throwFrame = frames - Opponent.fireballThrowAfter
            if throwFrame >= 0 {
                input.stick = Vec2(x: sign(from: me, to: human.chest), y: 0)
                input.throwBall = throwFrame < Opponent.fireballHoldFrames
                if throwFrame >= Opponent.fireballHoldFrames { powerMove = nil }
            }
            return true
        case .flight(let frames):
            guard frames < Opponent.flightGiveUp, frames < 2 || me.state == .flying, let goal = flyingGoal(match, me: me) else {
                powerMove = nil
                return false
            }
            powerMove = .flight(frames: frames + 1)
            input.jump = true
            input.stick = (goal - me.chest).normalized
            if me.hasBall {
                let rim = hoop(scoredOnBy: index, in: match).position
                // In the dunk's reach: the throw held, the stance carrying it onto the rim.
                if rim.distance(to: me.chest) < BallRules.dunkRadius * me.spec.scale {
                    input.throwBall = true
                    input.jump = false
                    powerMove = nil
                }
            } else if match.ball.position.distance(to: me.chest) < 12 || !match.ball.isLive {
                powerMove = nil
            }
            return true
        }
    }

    /// A flight under way keeps after its goal once it's level with it: the ball loose, or the rim with the ball.
    private func flyingGoal(_ match: Match, me: Player) -> Vec2? {
        if me.hasBall { return hoop(scoredOnBy: index, in: match).position }
        return match.ball.isLive ? match.ball.position : nil
    }
}
