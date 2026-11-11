import Foundation

/// Breaker Ball's play (`BreakerRules`, `BreakerPosture.swift`). Its target's the other's body, their
/// barrier: out to a throwing distance off them, then a throw planned by playing it out, a hop (and
/// the double jump if it needs it) up to their height, the stance held there charging, and the throw
/// let go into them, a Breaker Ball summoned for it if its hands are empty, charged or quick. Their
/// throws and shots coming at it it snatches out of the air, shields or hops over, some of the time;
/// close, it slashes, backs off or stands to throw, and it rushes in when their throw's charging;
/// close to one holding, it snatches theirs. Their barrier shattered, their rim's out over them: a ball in hand
/// (summoned and kept), and the rim shot at as any rim on the move (`offence`).
extension Opponent {
    /// A throw played out ahead and kept to: the input each frame, and where the feet should be
    /// before it; off course, it's dropped.
    struct BreakerThrow: Equatable {
        var inputs: [PlayerInput]
        var feet: [Vec2]
        var step = 0
    }

    /// Throwing from this far off the barrier across, the middle its aim; nearer than the least it backs off.
    static let breakerThrowBand: ClosedRange<Double> = 45...120
    static let breakerThrowDistance = 75.0
    /// The other this near across, the throw's let go as soon as it can be; further, charged in full.
    static let breakerHurryDistance = 70.0
    /// The ball's line has to pass this share of the barrier's reach from its middle: a little margin for its drift.
    static let breakerAimShare = 0.8
    /// A throw's plan played this far ahead at most.
    static let breakerPlanFrames = 110
    /// A body's rise or fall is led this many frames at most; its run across this many.
    static let breakerLeadFrames = 8
    static let breakerBodyLeadFrames = 40
    /// At the band this long with no throw found: the shot at the barrier for a while instead.
    static let breakerStuckFrames = 120
    static let breakerShootFrames = 90

    /// The other's rim out over them, it's seen this many frames after the hit stop: a person's reaction to the shatter.
    static let breakerReactionFrames: ClosedRange<Int> = 15...30

    static func breaker(_ match: Match) -> Bool { match.mode == .breakerBall }

    /// Breaker Ball: `defender`'s barrier shattered, their rim out over them.
    static func breakerRimOpen(_ match: Match, defender: Int) -> Bool {
        guard breaker(match), let rim = defendedRim(match, by: defender) else { return false }
        return !match.stage.hoops[rim].rimless
    }

    /// The rim a player defends in Breaker Ball, by its place.
    static func defendedRim(_ match: Match, by player: Int) -> Int? {
        match.stage.hoops.indices.first { match.defender(of: match.stage.hoops[$0]) == player }
    }

    /// Whether its own rim rides along behind it: Breaker Ball's, unparked, off Flight B411.
    static func rimFollows(_ match: Match, defender player: Int) -> Bool {
        guard breaker(match), !match.stage.features.tilts, let rim = defendedRim(match, by: player) else { return false }
        return !match.stage.hoops[rim].parked
    }

    /// A Breaker rim ahead: where it is, led by its motion a few frames, as a rim on the move.
    func breakerRimPath(_ match: Match, hoop index: Int) -> [Vec2]? {
        guard Opponent.breaker(match), match.stage.hoops.indices.contains(index) else { return nil }
        let hoop = match.stage.hoops[index]
        return (0..<Opponent.lookAheadFrames).map { hoop.position + hoop.velocity * Double(min($0, Opponent.breakerLeadFrames)) }
    }

    /// The throw under way, its next frame; nil when there's none or it's gone off course.
    mutating func continueBreakerThrow(_ match: Match, me: Player) -> PlayerInput? {
        guard var planned = breakerThrow else { return nil }
        // The hit-stop holds the body: nothing's played, the button kept as it was.
        if match.hitStop > 0 { return pressed }
        guard planned.step < planned.inputs.count, me.hitStun == 0, me.frozen == 0,
              me.position.distance(to: planned.feet[planned.step]) <= 1 else {
            breakerThrow = nil
            return nil
        }
        let input = planned.inputs[planned.step]
        planned.step += 1
        breakerThrow = planned.step < planned.inputs.count ? planned : nil
        return input
    }

    /// Breaker Ball's own play for this frame; false leaves it to `offence`, with a ball in hand and their rim out.
    mutating func breakerPlay(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        guard Opponent.breaker(match) else { return false }
        let free: [PlayerState] = [.idle, .walk, .run, .dash, .pivot, .crouch, .crouchWalk, .air, .land]
        if breakerRimReaction == 0, let theirs = Opponent.defendedRim(match, by: human.index), !match.stage.hoops[theirs].rimless {
            breakerStuck = 0
            if match.stage.features.dunks {
                dunkOpenRim(match, me: me, rim: match.stage.hoops[theirs].position, into: &input)
                return true
            }
            // Their barrier shattered and no dunking here: the ball in hand, summoned and kept, for the shot.
            if me.hasBall, me.state != .throwStance { return false }
            if me.state == .throwStance {
                // Guard kept down, so the cancel never lets the throw go.
                input.throwBall = true
                tapShoot(&input)
            } else if free.contains(me.state), !me.holding {
                tapThrow(&input)
            }
            return true
        }
        if answerIncoming(match, me: me, human: human, into: &input) { return true }
        // A stance not of its plan's making is called off: never a throw or a shot it didn't pick.
        if me.state == .shootStance {
            input.shoot = true
            tapThrow(&input)
            return true
        }
        if me.state == .throwStance {
            // Guard kept down, so the cancel never lets the throw go.
            input.throwBall = true
            tapShoot(&input)
            return true
        }
        if Opponent.committedStates.contains(me.state) || me.state == .jumpSquat { return true }
        let gap = human.position.x - me.position.x
        let toward: Double = gap >= 0 ? 1 : -1
        let level = abs(human.position.y - me.position.y) < 24
        // Close to one holding, facing them: the snatch that takes theirs.
        if !me.holding, human.hasBall, level, abs(gap) < Opponent.breakerStealReach, me.facing.sign == toward, me.snatchCooldown == 0,
           free.contains(me.state), chance(Opponent.breakerStealChance) {
            input.stick = Vec2(x: toward, y: 0)
            tapThrow(&input)
            return true
        }
        if upClose(match, me: me, human: human, into: &input) { return true }
        breakBarrier(match, me: me, human: human, into: &input)
        return true
    }

    /// The rim out over the stunned other: in under it, up to it if it's high, and Guard pressed in the
    /// dunk's reach, the stance (a Breaker Ball summoned into it with empty hands) dunking. Out of
    /// reach in the stance, it's called off, the ball kept, and in again.
    private mutating func dunkOpenRim(_ match: Match, me: Player, rim: Vec2, into input: inout PlayerInput) {
        let free: [PlayerState] = [.idle, .walk, .run, .dash, .pivot, .crouch, .crouchWalk, .air, .land]
        let reach = BallRules.dunkRadius * me.spec.scale - Opponent.breakerDunkMargin
        let dx = rim.x - me.position.x
        let near = me.chest.distance(to: rim) <= reach
        if me.state == .throwStance {
            input.throwBall = true
            if !near, me.chest.distance(to: rim) > reach + Opponent.breakerDunkMargin * 2 { tapShoot(&input) }
            return
        }
        if me.state == .shootStance {
            input.shoot = true
            tapThrow(&input)
            return
        }
        guard free.contains(me.state) else { return }
        if near {
            // Neutral on the stick, so empty hands summon rather than snatch.
            tapThrow(&input)
            return
        }
        if abs(dx) > 2 { input.stick = Vec2(x: dx > 0 ? 1 : -1, y: 0) }
        if me.grounded, abs(dx) < reach, rim.y - me.chest.y > reach - 4, !pressed.jump { fullHop(&input) }
    }
    static let breakerDunkMargin = 3.0

    /// The other's Breaker Ball across, this near: its snatch takes theirs. Tried this share of frames it could.
    static let breakerStealReach = 22.0
    static let breakerStealChance: UInt32 = 30

    /// How it meets one of the other's Breaker Balls coming at it, decided once a ball.
    enum BreakerAnswer: Equatable { case take, snatch, shield, hop }
    /// Frames before the ball meets the barrier that each answer goes in: the snatch's live frames
    /// (`SnatchRules.activeFrames`, 8 to 20) round it, the shield's perfect frames on it, the hop clear over it.
    static let breakerSnatchLead = 13.0
    static let breakerShieldLead = 4.0
    static let breakerHopLead = 16.0
    static let breakerDoubleJumpLead = 8.0
    /// Out of a hundred: empty-handed, the snatch, the shield and the hop, the rest taken; a full
    /// charge's can't be snatched, so the shield or the hop; holding, only the hop.
    static let breakerSnatchOdds: UInt32 = 35
    static let breakerShieldOdds: UInt32 = 25
    static let breakerHopOdds: UInt32 = 25
    static let breakerUnstoppableShieldOdds: UInt32 = 45
    static let breakerUnstoppableHopOdds: UInt32 = 40
    static let breakerHoldingHopOdds: UInt32 = 55

    /// The other's Breaker Ball flying at it: the frames till it meets the barrier, if it's coming.
    func incomingBreakerBall(_ match: Match, me: Player, human: Player) -> (flight: BreakerFlight, frames: Double, way: Double)? {
        let across = (me.roundHurtbox ? BreakerRules.postureRadius : me.spec.bodyWidth / 2) + BallRules.radius
        let up = (me.roundHurtbox ? BreakerRules.postureRadius : me.spec.bodyHeight / 2) + BallRules.radius
        for flight in match.breakerFlights where flight.owner == human.index && flight.damage > 0 {
            let ball = flight.ball
            guard ball.velocity.x != 0 else { continue }
            let way: Double = ball.position.x >= me.body.center.x ? 1 : -1
            let gap = me.body.center.x + way * across - ball.position.x
            guard (gap > 0) == (ball.velocity.x > 0) else { continue }
            let frames = abs(gap) / abs(ball.velocity.x)
            let fall = ball.straight || ball.floater > 0 ? 0 : 0.5 * BallRules.gravity * frames * frames
            let arriving = ball.position.y + ball.velocity.y * frames - fall
            guard frames < 40, abs(arriving - me.body.center.y) < up + 4 else { continue }
            return (flight, frames, way)
        }
        return nil
    }

    /// One of the other's Breaker Balls flying at it: snatched out of the air, shielded, hopped
    /// over, or taken, as it decided for that ball.
    private mutating func answerIncoming(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        let free: [PlayerState] = [.idle, .walk, .run, .dash, .pivot, .crouch, .crouchWalk, .air, .land]
        guard me.attackLockout == 0, me.hitStun == 0, free.contains(me.state),
              let (flight, frames, way) = incomingBreakerBall(match, me: me, human: human) else { return false }
        if breakerCatchFlight != flight.id {
            breakerCatchFlight = flight.id
            let pick = roll(100)
            if me.holding {
                breakerAnswer = pick < Opponent.breakerHoldingHopOdds ? .hop : .take
            } else if flight.ball.unstoppable {
                breakerAnswer = pick < Opponent.breakerUnstoppableShieldOdds ? .shield
                    : pick < Opponent.breakerUnstoppableShieldOdds + Opponent.breakerUnstoppableHopOdds ? .hop : .take
            } else {
                let shieldFrom = Opponent.breakerSnatchOdds, hopFrom = shieldFrom + Opponent.breakerShieldOdds
                breakerAnswer = pick < shieldFrom ? .snatch : pick < hopFrom ? .shield : pick < hopFrom + Opponent.breakerHopOdds ? .hop : .take
            }
        }
        switch breakerAnswer {
        case .take:
            return false
        case .snatch:
            guard !me.holding, me.snatchCooldown == 0 else { return false }
            if me.facing.sign != way {
                input.stick = Vec2(x: way * 0.5, y: 0)
            } else if frames <= Opponent.breakerSnatchLead {
                input.stick = Vec2(x: way, y: 0)
                tapThrow(&input)
            }
        case .shield:
            guard !me.holding else { return false }
            if frames <= Opponent.breakerShieldLead {
                input.shield = !pressed.shield
                shieldWhy = "breaker ball"
            }
        case .hop:
            if me.grounded, frames <= Opponent.breakerHopLead, !pressed.jump {
                fullHop(&input)
            } else if !me.grounded, me.jumpsLeft > 0, frames <= Opponent.breakerDoubleJumpLead {
                tapJump(&input)
            }
            input.stick = Vec2(x: -way, y: 0)
        }
        return true
    }

    // MARK: Up close

    /// What it does with the other near: in for the slash, back out of its reach, or stood its
    /// ground to throw from there.
    enum BreakerCloseCall: Equatable { case slash, retreat, stand }
    /// The other this near across counts as up close; backing off, it goes this far.
    static let breakerCloseRange = 52.0
    static let breakerRetreatTo = 85.0
    /// Out of a hundred, the other close and doing nothing in particular: the slash, backing off, the rest standing.
    static let breakerSlashOdds: UInt32 = 40
    static let breakerRetreatOdds: UInt32 = 45
    /// Their throw or shot charging, or their swing spent, close: in for the slash this often, else away.
    static let breakerPunishOdds: UInt32 = 75
    /// Holding, close: stood its ground for a quick throw this often, else away.
    static let breakerStandOdds: UInt32 = 50
    /// Frames a rush in for the slash lasts at most. A throw found is given up for one this often;
    /// their throw charging or their swing spent within `breakerRushRange`, one starts this share of frames.
    static let breakerRushFrames = 150
    static let breakerRushInsteadChance: UInt32 = 30
    static let breakerRushRange = 90.0
    static let breakerRushOnOpeningChance: UInt32 = 8
    /// The next throw let go as soon as it hits, rather than charged, this often.
    static let breakerQuickChance: UInt32 = 35

    /// Whether its slash, started now, would reach the other's barrier (or body, with the box hurtbox).
    static func breakerBladeReaches(_ me: Player, _ other: Player) -> Bool {
        let blade = Box(center: Vec2(x: me.body.center.x + SlashRules.forward * me.spec.scale * (other.body.center.x >= me.body.center.x ? 1 : -1),
                                     y: me.body.center.y),
                        width: SlashRules.reach * 2 * me.spec.scale, height: SlashRules.reach * 2 * me.spec.scale)
        return other.hurt(by: blade.offset(by: Vec2(x: me.velocity.x * 4, y: 0)))
    }

    private mutating func upClose(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        let gap = human.body.center.x - me.body.center.x
        let toward: Double = gap >= 0 ? 1 : -1
        let rise = human.position.y - me.position.y
        if breakerRush > 0 { breakerRush -= 1 }
        let range = breakerCloseCall == .retreat ? Opponent.breakerRetreatTo : Opponent.breakerCloseRange
        let near = abs(gap) < range && abs(rise) < 30
        guard near || breakerRush > 0 else {
            breakerCloseCall = nil
            return false
        }
        if breakerCloseCall == nil {
            let opening = Opponent.open(human) || human.state == .throwStance || human.state == .shootStance
            if breakerRush > 0, !me.holding {
                breakerCloseCall = .slash
            } else if me.holding {
                breakerCloseCall = chance(Opponent.breakerStandOdds) ? .stand : .retreat
            } else if opening {
                breakerCloseCall = chance(Opponent.breakerPunishOdds) ? .slash : .retreat
            } else {
                let pick = roll(100)
                breakerCloseCall = pick < Opponent.breakerSlashOdds ? .slash
                    : pick < Opponent.breakerSlashOdds + Opponent.breakerRetreatOdds ? .retreat : .stand
            }
        }
        switch breakerCloseCall {
        case .slash:
            guard !me.holding else {
                breakerCloseCall = .retreat
                return true
            }
            if Opponent.breakerBladeReaches(me, human), abs(rise) < 20 {
                if me.facing.sign != toward {
                    input.stick = Vec2(x: toward * 0.5, y: 0)
                } else {
                    tapShoot(&input)
                    breakerCloseCall = nil
                    breakerRush = 0
                }
                return true
            }
            input.stick = Vec2(x: toward, y: 0)
            if rise > 10, me.grounded, abs(gap) < 50, !pressed.jump { fullHop(&input) }
            return true
        case .retreat:
            let margin = Stage.tileSize + me.spec.bodyWidth + 10
            let cornered = toward > 0 ? me.position.x < margin : me.position.x > match.stage.width - margin
            if cornered {
                // Backed up to the wall: over them instead.
                if me.grounded, !pressed.jump { fullHop(&input) }
                input.stick = Vec2(x: toward, y: 0)
            } else {
                input.stick = Vec2(x: -toward, y: 0)
            }
            return true
        case .stand, nil:
            return false
        }
    }

    // MARK: Wearing the barrier down

    private mutating func breakBarrier(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) {
        let centre = human.body.center
        let gap = human.position.x - me.position.x
        let level = abs(human.position.y - me.position.y) < 30
        // Their swing live and close: out of its way first.
        if Opponent.dangerous(human), abs(gap) < 34, level {
            input.stick = Vec2(x: gap > 0 ? -1 : 1, y: 0)
            return
        }
        let across = abs(centre.x - me.position.x)
        let free: [PlayerState] = [.idle, .walk, .run, .dash, .pivot, .crouch, .crouchWalk]
        // Their throw charging or their swing spent, near enough: in at them for the slash.
        if !me.holding, breakerRush == 0, across < Opponent.breakerRushRange, level,
           Opponent.open(human) || human.state == .throwStance || human.state == .shootStance, chance(Opponent.breakerRushOnOpeningChance) {
            breakerRush = Opponent.breakerRushFrames
            breakerCloseCall = nil
            return
        }
        // Stood its ground up close: thrown from there.
        let band = breakerCloseCall == .stand ? Opponent.breakerStandBand : Opponent.breakerThrowBand
        if me.grounded, free.contains(me.state), band.contains(across) {
            breakerStuck += 1
            if breakerStuck > Opponent.breakerStuckFrames {
                // No throw found from here a while: in closer, where one's likelier.
                breakerStuck = 0
                breakerShooting = Opponent.breakerShootFrames
            }
            if !pressed.jump, !pressed.throwBall {
                let attempt = Opponent.breakerTries[breakerTry % Opponent.breakerTries.count]
                breakerTry = (breakerTry + 1) % Opponent.breakerTries.count
                if let planned = planBreakerThrow(match, me: me, human: human, attempt: attempt, quick: breakerQuick) {
                    breakerStuck = 0
                    if !me.holding, breakerCloseCall != .stand, chance(Opponent.breakerRushInsteadChance) {
                        // In for the slash instead, now and then.
                        breakerRush = Opponent.breakerRushFrames
                        return
                    }
                    breakerThrow = planned
                    breakerQuick = chance(Opponent.breakerQuickChance)
                    if let first = continueBreakerThrow(match, me: me) { input = first }
                    return
                }
            }
        }
        // To the throwing distance on its side of them, or the other side if that's off the stage;
        // right up to them, onto their level, while no throw's been found from further.
        if breakerShooting > 0 { breakerShooting -= 1 }
        let closing = breakerShooting > 0
        let distance = closing ? Opponent.breakerCloseDistance : Opponent.breakerThrowDistance
        var side: Double = me.position.x >= centre.x ? 1 : -1
        var spot = centre.x + side * distance
        let margin = Stage.tileSize + me.spec.bodyWidth
        if spot < margin || spot > match.stage.width - margin {
            side = -side
            spot = centre.x + side * distance
        }
        if !closing, me.grounded, band.contains(across), breakerCloseCall == .stand || (me.position.x - centre.x) * side > 0 {
            // In the band already: facing the barrier, the stick off.
            if me.facing.sign != (centre.x >= me.position.x ? 1 : -1) { input.stick = Vec2(x: centre.x >= me.position.x ? 0.5 : -0.5, y: 0) }
            return
        }
        if !me.grounded {
            // In the air: drifting down toward the spot, never left bouncing on a rim.
            let dx = spot - me.position.x
            if abs(dx) > 2 { input.stick = Vec2(x: dx > 0 ? 1 : -1, y: 0) }
            return
        }
        // The ground under the spot, near the barrier's height, not a point in the air.
        let ground = terrain?.standing(nearest: Vec2(x: spot, y: centre.y - 30)).map { Vec2(x: $0.x, y: terrain!.surfaces[$0.surface].height(at: $0.x)) }
        let target = ground ?? Vec2(x: spot, y: me.position.y)
        if Opponent.readsStage(match) {
            go(to: target, match: match, me: me, into: &input)
        } else {
            let dx = spot - me.position.x
            if Opponent.overshooting(dx, me: me) { return }
            input.stick = Vec2(x: dx > 0 ? (abs(dx) > 40 ? 1 : 0.5) : (abs(dx) > 40 ? -1 : -0.5), y: 0)
            // Closing on them stood higher: up to their level.
            if closing, abs(centre.x - me.position.x) < Opponent.breakerThrowBand.lowerBound, human.position.y - me.position.y > 8, !pressed.jump {
                fullHop(&input)
            }
        }
    }
    /// Closing in when no throw's found from the band: this far across off them.
    static let breakerCloseDistance = 20.0
    /// Stood its ground up close, a throw's tried from this near.
    static let breakerStandBand: ClosedRange<Double> = 20...120

    /// The ways a throw is tried, one a frame in turn: hop 0 standing, 1 a full hop, 2 the hop and the
    /// double jump, 3 a short hop; `pressAfter` frames into the air (after the double jump, for 2) the
    /// stance is pressed.
    static let breakerTries: [(hop: Int, pressAfter: Int)] = [(0, 0), (3, 1), (3, 6), (1, 1), (1, 8), (1, 16), (2, 1), (2, 8)]
    /// A release only tried when the hand's this near the body's middle in height, past its reach:
    /// the body's drift over the release's frames.
    static let breakerHeightSlack = 6.0
    /// The best few releases of a way played on to the ball leaving the hand, a frame; the rest wait for the next.
    static let breakerReleasesTried = 3

    /// The throw into the other's body, found by playing it out one way (`breakerTries`): the stance
    /// pressed on the way (a Breaker Ball summoned by it with empty hands), and let go on a frame its
    /// charge allows, the ball's straight line tried against the body where it'll be, led by its
    /// motion a few frames. Hurried, the least charged that hits; otherwise the most.
    func planBreakerThrow(_ match: Match, me: Player, human: Player, attempt: (hop: Int, pressAfter: Int), quick: Bool = false) -> BreakerThrow? {
        let reach = human.spec.bodyHeight / 2 + BallRules.radius
        let way: Double = human.position.x >= me.position.x ? 1 : -1
        let aim = Vec2(x: way, y: 0)
        let hurried = quick || abs(human.position.x - me.position.x) < Opponent.breakerHurryDistance
        // Across, their run led the whole way; up and down, only a few frames, a jump's arc turning.
        func lead(_ frame: Int) -> Vec2 {
            Vec2(x: human.velocity.x * Double(min(frame, Opponent.breakerBodyLeadFrames)),
                 y: human.grounded ? 0 : human.velocity.y * Double(min(frame, Opponent.breakerLeadFrames)))
        }
        func centre(at frame: Int) -> Vec2 { human.body.center + lead(frame) }
        func targetBody(at frame: Int) -> Box { human.body.offset(by: lead(frame)) }
        let releaseFrames = me.underwater ? 16 : 8

        // Played out to the stance's end, keeping each frame it could be let go on.
        var body = me
        var inputs: [PlayerInput] = []
        var feet: [Vec2] = []
        var events: [MatchEvent] = []
        var lastJump = pressed.jump, lastThrow = pressed.throwBall
        var airFrames = 0, sinceDouble = -1
        var releases: [(played: Int, body: Player, held: Int)] = []
        for frame in 0..<Opponent.breakerPlanFrames {
            var input = PlayerInput(aim: aim)
            if attempt.hop >= 1, frame == 0 || (body.state == .jumpSquat && attempt.hop != 3) { input.jump = true }
            if !body.grounded, body.state == .air { airFrames += 1 }
            if attempt.hop == 2, sinceDouble < 0, body.state == .air, airFrames > 2, body.velocity.y < 0.5, body.jumpsLeft > 0 {
                input.jump = !lastJump
                if input.jump { sinceDouble = 0 }
            } else if sinceDouble >= 0 {
                sinceDouble += 1
            }
            let pressNow: Bool
            switch attempt.hop {
            case 0: pressNow = true
            case 1, 3: pressNow = !body.grounded && airFrames >= attempt.pressAfter
            default: pressNow = sinceDouble >= attempt.pressAfter
            }
            if body.state == .throwStance {
                input.throwBall = true
            } else if pressNow, body.state != .jumpSquat, !input.jump {
                input.throwBall = !lastThrow
            }
            feet.append(body.position)
            inputs.append(input)
            _ = body.step(input: input, stage: match.stage, events: &events)
            lastJump = input.jump
            lastThrow = input.throwBall
            // Off its plan (a wall, a ceiling, landed out of the stance): no throw this way.
            if attempt.hop > 0, frame > 4, body.grounded, body.state != .throwStance { break }
            if body.state != .throwStance, frame > 20, releases.isEmpty == false { break }
            guard body.state == .throwStance else { continue }
            let handHeight = body.position.y + BallRules.throwReleaseHeight * body.spec.scale
            let heightOff = handHeight - centre(at: frame + releaseFrames).y
            let heightReach = reach * Opponent.breakerAimShare + Opponent.breakerHeightSlack
            // Under the barrier and not rising: nothing later reaches it.
            if heightOff < -heightReach, body.velocity.y <= 0 { break }
            guard body.stateTimer >= BallRules.throwWindupFrames, frame % 2 == 0 else { continue }
            // Nowhere near the barrier's height: not worth letting go here.
            guard abs(heightOff) < heightReach else { continue }
            // Charge past full buys nothing: held no longer than that counts.
            releases.append((inputs.count, body, min(body.stateTimer, ThrowChargeRules.fullFrames)))
        }
        guard !releases.isEmpty else { return nil }

        var stage = match.stage
        stage.extras += stage.ballBlockers + stage.ceilingSlopes.map(\.box)
        // Whether the throw let go from `hand` at `velocity` on frame `frame` meets the body before a wall.
        func meets(hand: Vec2, velocity: Vec2, frame: Int) -> Bool {
            guard velocity.x != 0, targetBody(at: frame).distance(to: hand) > BallRules.radius else { return false }
            let open = abs(stage.sweepHorizontally(Box(center: hand, width: BallRules.radius * 2, height: BallRules.radius * 2), by: velocity.x * 60).moved)
            for flown in 1...60 {
                let at = hand + velocity * Double(flown)
                if abs(at.x - hand.x) > open { return false }
                if targetBody(at: frame + flown).distance(to: at) <= BallRules.radius * (1 - Opponent.breakerAimShare) { return true }
            }
            return false
        }
        // The best first: the least held when hurried, else the most, the earliest of each.
        let ordered = releases.enumerated().sorted { first, second in
            first.element.held != second.element.held ? (hurried ? first.element.held < second.element.held : first.element.held > second.element.held)
                : first.offset < second.offset
        }.map(\.element)
        for release in ordered.prefix(Opponent.breakerReleasesTried) {
            var trial = release.body
            var tail: [PlayerInput] = [], tailFeet: [Vec2] = []
            var trialEvents: [MatchEvent] = []
            // Let go: played on to the ball leaving the hand; under water at half speed.
            for after in 0..<releaseFrames {
                let letGo = PlayerInput(aim: aim)
                tailFeet.append(trial.position)
                tail.append(letGo)
                guard case .releaseThrow(let velocity) = trial.step(input: letGo, stage: match.stage, events: &trialEvents) else { continue }
                let hand = Vec2(x: trial.position.x + trial.facing.sign * 6 * trial.spec.scale, y: trial.position.y + BallRules.throwReleaseHeight * trial.spec.scale)
                if velocity.y == 0, (velocity.x > 0) == (way > 0), meets(hand: hand, velocity: velocity, frame: release.played + after) {
                    return BreakerThrow(inputs: Array(inputs[0..<release.played]) + tail, feet: Array(feet[0..<release.played]) + tailFeet)
                }
                break
            }
        }
        return nil
    }

    // Breaker Ball's old play without the ball, at barriers round rims and parked rims: off for the posture rules.
    // // MARK: Without the ball
    //
    // /// Their barrier in its blade's reach: the swing; under it and near, a hop up to it now and then.
    // private mutating func swingAtBarrier(_ match: Match, me: Player, human: Player, hoop index: Int, into input: inout PlayerInput) -> Bool {
    //     let hoop = match.stage.hoops[index]
    //     let free: [PlayerState] = [.idle, .walk, .run, .dash, .pivot, .air]
    //     guard free.contains(me.state), !me.holding else { return false }
    //     let toward: Double = hoop.position.x >= me.position.x ? 1 : -1
    //     let radius = match.barrierRadius(hoop)
    //     if me.facing.sign == toward, me.bladeCentre.distance(to: hoop.position) <= radius + SlashRules.reach * 0.6 {
    //         tapShoot(&input)
    //         return true
    //     }
    //     let above = hoop.position.y - me.chest.y
    //     if me.grounded, abs(hoop.position.x - me.position.x) < radius + 10, above > 8, above < 60, chance(Opponent.barrierHopChance) {
    //         fullHop(&input)
    //         input.stick = Vec2(x: toward * 0.5, y: 0)
    //         return true
    //     }
    //     return false
    // }
    // static let barrierHopChance: UInt32 = 6
    //
    // /// Its own rim parked and close, nothing pressing: the snatch that takes it back.
    // private mutating func takeBackParkedRim(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
    //     guard !match.stage.features.tilts, let own = Opponent.defendedRim(match, by: index), match.stage.hoops[own].parked,
    //           me.snatchCooldown == 0, [.idle, .walk, .run, .dash, .pivot].contains(me.state),
    //           me.body.distance(to: match.stage.hoops[own].position) <= BreakerRules.unparkReach - 4 else { return false }
    //     // A loose ball close to either of them is the ball's first.
    //     if match.ball.holder == nil, match.ball.isLive, min(match.ball.position.distance(to: me.chest), match.ball.position.distance(to: human.chest)) < 80 { return false }
    //     tapThrow(&input)
    //     return true
    // }
}
