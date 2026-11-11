/// The computer's rock-paper-scissors: snatch beats shield, slash beats snatch, shield beats slash.
/// It plays it as a person does, not off the frame the other's move starts. Each move is seen a
/// reaction time after it starts, and answered then, some of the time; a point-blank slash is
/// live before that, so it lands. Spam, the same move twice in a short while, is read for its
/// rhythm, and the counter goes in when the next is due, a few frames early or late, sometimes
/// not at all.
extension Opponent {
    /// The other's moves it reads.
    enum Read: Hashable { case slash, snatch, shield }
    /// Its answers: the shield, the Spin Move (with the ball), the slash, the snatch, the ball thrown at them.
    enum Counter: Equatable { case shield, spin, slash, snatch, throwAt }

    struct CounterPlan: Equatable {
        var move: Counter
        /// The frame it goes in.
        var at: Int
        /// The frames of its input given so far: the spin's and the throw's take two.
        var step = 0
    }

    struct Reaction: Equatable {
        var read: Read
        var started: Int
        var seenAfter: Int
    }

    /// A person's reaction: what the other starts is seen this many frames later.
    static let reactionFrames: ClosedRange<Int> = 12...20
    /// Seen, a move's answered this often; of the rest, it backs off if it's in reach.
    static let answerChance: UInt32 = 40
    /// Spam: this many starts of one move inside this many frames.
    static let spamCount = 2
    static let spamWindow = 90
    /// Spam read, the counter goes for the next one this often, this many frames early or late at most.
    static let punishChance: UInt32 = 70
    static let rhythmSlop = 6
    /// A counter's plan is dropped this many frames after it was due, not gone in.
    static let counterGrace = 10
    /// How near the other has to be, across and up, for a counter to be worth it.
    static let counterReach = 44.0
    static let backOffFrames = 12

    /// The move the other is in, if one it reads.
    static func read(_ player: Player) -> Read? {
        switch player.state {
        case .slashing: .slash
        case .snatching: .snatch
        case .flipJump: .shield
        default: nil
        }
    }

    /// The other's slashes, snatches and shields as they start: kept for spam, and on the second
    /// in a short while, the counter planned for when the next is due.
    mutating func noteStarts(_ match: Match, me: Player, human: Player) {
        for read in starts.keys { starts[read]?.removeAll { match.frame - $0 > Opponent.spamWindow } }
        guard let read = Opponent.read(human), human.stateTimer == 0 else { return }
        starts[read, default: []].append(match.frame)
        let seen = starts[read] ?? []
        guard seen.count >= Opponent.spamCount, counterPlan == nil, chance(Opponent.punishChance) else { return }
        let rhythm = seen[seen.count - 1] - seen[seen.count - 2]
        let due = match.frame + rhythm
        let slop = Int(roll(UInt32(Opponent.rhythmSlop * 2 + 1))) - Opponent.rhythmSlop
        // Each counter timed to meet the next as it goes live: the shield up as the blade comes
        // out, the spin under way, the slash on the snatcher, the snatch on a shield that's up.
        let move = Opponent.answer(to: read, holding: me.hasBall)
        counterPlan = CounterPlan(move: move, at: due + Opponent.lead(move) + slop)
    }

    /// The counter, planned or reacted: true while it's giving one, or backing out of the way.
    mutating func counter(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        let gap = human.position.x - me.position.x
        let near = abs(gap) < Opponent.counterReach && abs(human.position.y - me.position.y) < 24
        // Seen a reaction time after it starts: answered some of the time, else backed off from.
        if let read = Opponent.read(human), near {
            let started = match.frame - human.stateTimer
            if reactingTo?.started != started || reactingTo?.read != read {
                reactingTo = Reaction(read: read, started: started,
                                      seenAfter: Opponent.reactionFrames.lowerBound + Int(roll(UInt32(Opponent.reactionFrames.count))))
            }
            if let reaction = reactingTo, human.stateTimer == reaction.seenAfter, counterPlan == nil {
                if chance(Opponent.answerChance) {
                    counterPlan = CounterPlan(move: Opponent.answer(to: read, holding: me.hasBall), at: match.frame)
                } else if read == .slash, Opponent.bladeReaches(human, me) {
                    backingOff = Opponent.backOffFrames
                }
            }
        }
        if backingOff > 0 {
            backingOff -= 1
            input.stick = Vec2(x: gap > 0 ? -1 : 1, y: 0)
            return true
        }
        guard var plan = counterPlan else { return false }
        if match.frame > plan.at + Opponent.counterGrace, plan.step == 0 {
            counterPlan = nil
            return false
        }
        guard match.frame >= plan.at else { return false }
        let free: [PlayerState] = [.idle, .walk, .dash, .run, .pivot, .air, .crouch, .land]
        // Not free, too far, or no longer the right answer: waited on, then let go at its grace.
        let ready = plan.step > 0 || (free.contains(me.state) && me.hitStun == 0 && !me.parryLocked && near)
        guard ready else { return false }
        let toward: Facing = gap > 0 ? .right : .left
        switch plan.move {
        case .shield:
            guard !me.holding else { counterPlan = nil; return false }
            input.shield = !pressed.shield
            shieldWhy = "counter"
            counterPlan = nil
        case .slash, .snatch:
            guard !me.holding else { counterPlan = nil; return false }
            // Round to face them first, a frame.
            if me.facing != toward {
                input.stick = Vec2(x: toward.sign * 0.5, y: 0)
                return true
            }
            if plan.move == .slash { tapShoot(&input) } else { tapThrow(&input) }
            counterPlan = nil
        case .spin:
            guard me.hasBall else { counterPlan = nil; return false }
            if plan.step == 0 {
                // The stance on a fresh press, then the aim's flick down with it held.
                if pressed.throwBall { return true }
                input.throwBall = true
                plan.step = 1
                counterPlan = plan
            } else {
                input.throwBall = true
                input.aim = Vec2(x: 0, y: -1)
                counterPlan = nil
            }
        case .throwAt:
            guard me.hasBall else { counterPlan = nil; return false }
            if plan.step == 0 {
                if pressed.throwBall { return true }
                input.throwBall = true
                input.stick = Vec2(x: toward.sign, y: 0)
                plan.step = 1
                counterPlan = plan
            } else {
                // Let go at once: the quick throw goes as the windup ends, at them.
                input.stick = Vec2(x: toward.sign, y: 0)
                counterPlan = nil
            }
        }
        return true
    }

    /// Frames after the next one's due that the counter goes in: the shield up ahead of the blade
    /// (it lasts, so early costs little), the spin under way before it, the slash on the snatcher,
    /// the snatch on a shield that's up.
    static func lead(_ move: Counter) -> Int {
        switch move {
        case .shield: -2
        case .spin: -1
        case .slash: 2
        case .snatch: 4
        case .throwAt: 2
        }
    }

    /// The answer to a move: shield beats slash, slash beats snatch, snatch beats shield; with
    /// the ball, the spin through a slash or a snatch, and the ball thrown at a shield.
    static func answer(to read: Read, holding ball: Bool) -> Counter {
        switch (read, ball) {
        case (.slash, false): .shield
        case (.snatch, false): .slash
        case (.shield, false): .snatch
        case (.slash, true), (.snatch, true): .spin
        case (.shield, true): .throwAt
        }
    }

    /// A loose ball's chase, decided once a flight: whether it slides in a race for it, snatches
    /// it in reach, and spikes it (the slash, or the shield's face) when the other's on it too.
    struct Race: Equatable {
        var flight: Int
        var slide: Bool
        var snatch: Bool
        var spike: Counter?
        mutating func spiked() { spike = nil }
    }
    static let raceSlideChance: UInt32 = 25
    static let raceSnatchChance: UInt32 = 70
    static let raceSpikeChance: UInt32 = 50
    /// Of its spikes, this many in a hundred are the shield's flick.
    static let spikeShieldChance: UInt32 = 40

    mutating func raceFor(_ ball: Ball) -> Race {
        if let race, race.flight == ball.flight { return race }
        if ball.shotInFlight, let shooter = ball.lastTouched, shooter != index {
            // The other's shot: something's always tried on it, the shield, the slash or the snatch.
            let tool = roll(3)
            let made = Race(flight: ball.flight, slide: false, snatch: tool == 2, spike: tool == 0 ? .shield : tool == 1 ? .slash : nil)
            race = made
            shieldIntent = ShieldIntent(key: -ball.flight - 1, will: tool == 0, slop: -2 + Int(roll(6)))
            return made
        }
        let spike: Counter? = chance(Opponent.raceSpikeChance) ? (chance(Opponent.spikeShieldChance) ? .shield : .slash) : nil
        let made = Race(flight: ball.flight, slide: chance(Opponent.raceSlideChance), snatch: chance(Opponent.raceSnatchChance), spike: spike)
        race = made
        return made
    }

    /// The shield's going up for this (a shot's flight, a stance, an approach), or not, and when.
    struct ShieldIntent: Equatable {
        var key: Int
        var will: Bool
        /// Frames early (under 0) or late it goes up.
        var slop: Int
    }
    /// A shot it's in the way of is blocked this often, the shield up as the ball's this many frames
    /// off, give or take a few; a stance close by is contested with it this often, an approach met
    /// with it this often, inside this far.
    static let blockChance: UInt32 = 45
    static let blockLead = 3
    static let blockLookahead = 14
    static let contestChance: UInt32 = 25
    static let approachChance: UInt32 = 25
    static let approachReach = 30.0
    static let stanceContestReach = 36.0

    private mutating func intend(_ key: Int, _ percent: UInt32, slop: ClosedRange<Int>) -> ShieldIntent {
        if let shieldIntent, shieldIntent.key == key { return shieldIntent }
        let made = ShieldIntent(key: key, will: chance(percent), slop: slop.lowerBound + Int(roll(UInt32(slop.count))))
        shieldIntent = made
        return made
    }

    private static let freeToShield: [PlayerState] = [.idle, .walk, .dash, .run, .pivot, .air, .crouch, .land]

    /// The other's shot on its way, coming through the shield's reach: the shield raised to meet it,
    /// decided once a shot, some of the time, a few frames early or late.
    mutating func blockShot(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        let ball = match.ball
        guard ball.shotInFlight, ball.lastTouched == human.index, !me.holding, me.hitStun == 0, !me.parryLocked,
              Opponent.freeToShield.contains(me.state) else { return false }
        let middle = me.body.center
        guard let meets = (1...Opponent.blockLookahead).first(where: {
            ballPosition(ball, after: $0).distance(to: middle) <= (me.spec.guarderadeLevel >= 1 ? ShieldRules.guarderadeReach : ShieldRules.reach) + BallRules.radius
        }) else { return false }
        let intent = intend(-ball.flight - 1, Opponent.blockChance, slop: -2...3)
        guard intent.will, meets <= Opponent.blockLead + intent.slop else { return false }
        input.shield = !pressed.shield
        shieldWhy = "block shot"
        shieldIntent?.will = false
        return true
    }

    /// The shield as a tool: up in the face of a shot stance close by, after it's seen, or of the
    /// other coming straight at it at a dash or a run, once they're in close. Raised on them it
    /// shoves them out and knocks the ball loose. Each decided once, some of the time.
    mutating func contestWithShield(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        guard !me.holding, me.hitStun == 0, !me.parryLocked, me.grounded, Opponent.freeToShield.contains(me.state),
              match.shields.allSatisfy({ $0.owner != index }) else { return false }
        let gap = human.position.x - me.position.x
        guard abs(human.position.y - me.position.y) < 24 else { return false }
        let started = match.frame - human.stateTimer
        if human.state == .shootStance, abs(gap) < Opponent.stanceContestReach {
            let intent = intend(started, Opponent.contestChance, slop: Opponent.reactionFrames)
            guard intent.will, human.stateTimer >= intent.slop else { return false }
        } else if [.dash, .run].contains(human.state), human.velocity.x * -gap > 0, abs(gap) < Opponent.approachReach {
            let intent = intend(started, Opponent.approachChance, slop: 0...4)
            guard intent.will, human.stateTimer >= intent.slop else { return false }
        } else {
            return false
        }
        input.shield = !pressed.shield
        shieldWhy = "contest \(human.state)"
        shieldIntent?.will = false
        return true
    }

    /// Out of a stun (struck, parried, frozen, pushed off a clash) it settles a moment, as a person
    /// gets their bearings, before it attacks again: no slash or snatch for a beat, sometimes
    /// backing off meanwhile. The shield and the spin, answers to what's coming, still go; with the
    /// ball it plays on.
    mutating func settleAfterStun(me: Player, human: Player, into input: inout PlayerInput) {
        let stunned = me.hitStun > 0 || me.parryLocked || me.clashPushed || me.frozen > 0
        if wasStunned, !stunned {
            settling = Opponent.settleFrames.lowerBound + Int(roll(UInt32(Opponent.settleFrames.count)))
            settlesAway = chance(Opponent.settleAwayChance)
        }
        wasStunned = stunned
        guard settling > 0, !stunned else { return }
        settling -= 1
        guard !me.holding else { return }
        input.shoot = false
        input.throwBall = false
        if settlesAway, me.grounded, !input.shield {
            input.stick = Vec2(x: human.position.x > me.position.x ? -0.5 : 0.5, y: 0)
        }
    }
    static let settleFrames: ClosedRange<Int> = 8...27
    static let settleAwayChance: UInt32 = 40

    /// In close on the ball's holder, the swing: the snatch at the hand, the shield on them (it
    /// shoves them and knocks the ball loose, though a throw breaks it), or the slash.
    mutating func defensiveSwing(gap: Double, into input: inout PlayerInput) {
        let pick = roll(100)
        if abs(gap) <= Opponent.swingSnatchReach, pick < Opponent.swingSnatchChance {
            tapThrow(&input)
        } else if pick < Opponent.swingSnatchChance + Opponent.swingShieldChance {
            input.shield = !pressed.shield
            shieldWhy = "defensive swing"
        } else {
            tapShoot(&input)
        }
    }
    static let swingSnatchReach = 12.0
    static let swingSnatchChance: UInt32 = 35
    static let swingShieldChance: UInt32 = 30

    /// The Wreck Center's belts carry a loose ball to their end, where it drops into the rim below
    /// and scores. Riding toward the rim it guards, the ball's not chased up there: it waits under
    /// the drop and goes up to meet it as it falls, the shield or the slash, decided once a drop,
    /// and a frame or two early or late as a person is.
    mutating func guardTheBeltDrop(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        let ball = match.ball
        func onBelt(_ belt: Conveyor) -> Bool {
            abs(ball.position.y - BallRules.radius - belt.box.max.y) < 0.5
                && ball.position.x + BallRules.radius > belt.box.min.x && ball.position.x - BallRules.radius < belt.box.max.x
        }
        let rim = hoop(scoredOnBy: human.index, in: match).position
        // Riding a belt, or just off its end and falling into the rim.
        let riding = ball.velocity.y == 0 ? match.stage.conveyors.first(where: { $0.running && onBelt($0) }) : nil
        let falling = beltPick != nil && ball.velocity.y < 0 && ball.position.y > rim.y - 10 && abs(ball.position.x - rim.x) < 30
        guard ball.isLive, ball.holder == nil, !me.holding, ball.lastTouched != index, riding != nil || falling else {
            beltPick = nil
            beltClimb = nil
            return false
        }
        if falling { beltClimb = nil }
        var due = 0.0, dropX = ball.position.x
        // Met at the top of its highest jump, where the shield's reach round its middle and the
        // blade's from its chest come up over the rim; the ball falling into that.
        let lift = me.fullHopVelocity, gravity = max(me.gravity, 0.01), second = me.spec.doubleJumpVelocity
        let twice = me.jumpsLeft > 1
        let topFeet = me.position.y + lift * lift / (2 * gravity) + (twice ? second * second / (2 * gravity) : 0)
        let meetY = min(topFeet + BallRules.chestHeight * me.spec.scale + Opponent.beltMeetOverChest, rim.y + Opponent.beltMeetOverRim)
        if let belt = riding {
            // Its end: along the belts joined to it the same way.
            var end = belt.way > 0 ? belt.box.max.x : belt.box.min.x
            while let next = match.stage.conveyors.first(where: { $0.way == belt.way && abs($0.box.max.y - belt.box.max.y) < 0.5
                && abs((belt.way > 0 ? $0.box.min.x : $0.box.max.x) - end) < 0.5 }) {
                end = belt.way > 0 ? next.box.max.x : next.box.min.x
            }
            guard abs(end - rim.x) < Opponent.beltRimReach, rim.y < belt.box.max.y else {
                beltPick = nil
                return false
            }
            dropX = end + belt.way * BallRules.radius
            let toEnd = max((end - ball.position.x) * belt.way + BallRules.radius, 0) / WreckCenterRules.beltSpeed
            if climbToTheBelt(match, me: me, top: belt.box.max.y, face: end, way: belt.way, ballX: ball.position.x, toEnd: toEnd, into: &input) { return true }
            let fall = max(belt.box.max.y + BallRules.radius - meetY, 0)
            due = toEnd + (2 * fall / BallRules.gravity).squareRoot()
        }
        if beltPick == nil {
            beltPick = roll(100)
            beltSlop = Int(roll(5)) - 2
        }
        let pick = beltPick ?? 0
        if !me.grounded {
            // Up: under it, the second jump at the top if the first won't get the hands there, and
            // in reach, the answer.
            let toDrop = (falling ? ball.position.x : dropX) - me.position.x
            if abs(toDrop) > 2 { input.stick = Vec2(x: toDrop > 0 ? 1 : -1, y: 0) }
            // Each answer pressed its own startup early, where the ball will be by then in its reach:
            // the shield's round the body's middle, the blade's and the hand's out front.
            let snatching = pick < Opponent.beltSnatchChance
            let shielding = !snatching && pick < Opponent.beltSnatchChance + Opponent.beltShieldChance
            let startup = snatching ? SnatchRules.activeFrames.lowerBound : (shielding ? 1 : SlashRules.liveFrames.lowerBound)
            let reach = shielding ? (me.spec.guarderadeLevel >= 1 ? ShieldRules.guarderadeReach : ShieldRules.reach) + BallRules.radius
                : (snatching ? Opponent.beltHandReach : SlashRules.reach + BallRules.radius)
            let centre = shielding ? me.body.center : me.chest
            if ballPosition(ball, after: startup).distance(to: centre) <= reach {
                if snatching { tapThrow(&input) } else if shielding { input.shield = !pressed.shield; shieldWhy = "belt drop" } else { tapShoot(&input) }
                return true
            }
            if me.jumpsLeft > 0, me.velocity.y < Opponent.doubleJumpBelow, meetY > me.position.y + Opponent.handsOverFeet + 4 { tapJump(&input) }
            return true
        }
        // Under the drop, then up so the top of the jump comes as it falls by.
        let toDrop = dropX - me.position.x
        if abs(toDrop) > 3 { input.stick = Vec2(x: toDrop > 0 ? 1 : -1, y: 0) }
        let rise = lift / gravity + (twice ? second / gravity : 0)
        let lead = Double(me.spec.jumpSquatFrames) + rise + Double(beltSlop)
        if abs(toDrop) <= 8, due <= lead { fullHop(&input) }
        return true
    }
    /// The ball riding a belt to its rim, with time to beat it there: up onto the middle platform,
    /// off it at the wall under the belt (the block's face and the backboard's under it) with both
    /// jumps, off the wall at every cling till over the lip, and up there in the ball's way, where
    /// it's caught. `face`: the wall's, the belt's end; `way`: the belt's, toward it from the wall.
    mutating func climbToTheBelt(_ match: Match, me: Player, top: Double, face: Double, way: Double, ballX: Double,
                                 toEnd: Double, into input: inout PlayerInput) -> Bool {
        let side = -way
        // Up on it: in the ball's way.
        if me.grounded, abs(me.position.y - top) < 1, (me.position.x - face) * side > 0 {
            beltClimb = nil
            let toBall = ballX - me.position.x
            if abs(toBall) > 4 { input.stick = Vec2(x: toBall > 0 ? 1 : -1, y: 0) }
            return true
        }
        guard let platform = match.stage.dropPlatforms.first else { return false }
        let platformTop = platform.top
        let firstColumn = match.stage.dropPlatforms.map { $0.columns.lowerBound }.min() ?? 0
        let lastColumn = match.stage.dropPlatforms.map { $0.columns.upperBound }.max() ?? 0
        let platformSpan = Double(firstColumn) * Stage.tileSize...Double(lastColumn + 1) * Stage.tileSize
        let onPlatform = me.grounded && abs(me.position.y - platformTop) < 1 && platformSpan.contains(me.position.x)
        // Back down on the floor partway: the climb's over, or begun again if there's still time.
        if me.grounded, me.position.y < platformTop - 1, beltClimb != nil, beltClimb != .mounting { beltClimb = nil }
        if case .climbing(let frames)? = beltClimb {
            beltClimb = .climbing(frames: frames + 1)
            input.stick = Vec2(x: side, y: 0)
            if frames == 0 { fullHop(&input) }
            if frames == Opponent.climbSecondJump || (me.state == .wallLand && me.stateTimer >= Opponent.climbCling) { tapJump(&input) }
            return true
        }
        let middle = (platformSpan.lowerBound + platformSpan.upperBound) / 2
        let mount = onPlatform ? 0 : abs(middle - me.position.x) / max(me.spec.runSpeed, 0.1) + Opponent.climbMountFrames
        if onPlatform {
            guard mount + Opponent.climbFrames <= toEnd else { return false }
            beltClimb = .climbing(frames: 0)
            input.stick = Vec2(x: side, y: 0)
            fullHop(&input)
            return true
        }
        guard beltClimb == .mounting || (me.grounded && me.position.y < platformTop && mount + Opponent.climbFrames <= toEnd) else { return false }
        // Onto the platform: under its middle, up through it, the second jump just high enough to clear it.
        beltClimb = .mounting
        let toMiddle = middle - me.position.x
        if abs(toMiddle) > 3 { input.stick = Vec2(x: toMiddle > 0 ? 1 : -1, y: 0) }
        if me.grounded {
            if abs(toMiddle) <= 12 { fullHop(&input) }
        } else if me.jumpsLeft > 0, me.position.y < platformTop, me.position.y >= platformTop - Opponent.mountSecondJumpUnder {
            tapJump(&input)
        }
        return true
    }
    /// The climb's timings, off the sim from anywhere on the platform: the second jump this many
    /// frames after the first, off the wall this many into a cling; the frames up from the
    /// platform at worst, and onto it from under its middle, the second jump this far under its top.
    static let climbSecondJump = 22
    static let climbCling = 2
    static let climbFrames = 130.0
    static let climbMountFrames = 40.0
    static let mountSecondJumpUnder = 22.0

    /// Where it meets a belt's drop, over the rim; how near the rim a belt's end must be to drop
    /// into it; the snatch's reach from the chest; and the answers' shares.
    static let beltMeetOverRim = 14.0
    static let beltMeetOverChest = 8.0
    static let beltRimReach = 40.0
    static let beltHandReach = 24.0
    /// The snatch's hand is out front at the chest, under a drop's reach: none.
    static let beltSnatchChance: UInt32 = 0
    static let beltShieldChance: UInt32 = 70

    /// The other's shot on its way: gone after from the ground, as a person goes after every one.
    /// The earliest point along its flight it can get under and up to in time is run to, and the
    /// jump goes as the ball's due there; in the air the shield, the slash or the snatch picked for
    /// this shot goes in as it comes in reach. Out of reach everywhere, it runs in under its rim for the miss.
    mutating func goaltend(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        let ball = match.ball
        guard ball.shotInFlight, ball.lastTouched == human.index, ball.holder == nil, !me.holding else { return false }
        var race = raceFor(ball)
        if !me.grounded {
            // Up after it: under where it's going, the double jump while it's still above; close,
            // the shield, slash or snatch picked for this shot goes, reaching or not, an attempt.
            let soon = ballPosition(ball, after: Opponent.airLead)
            if ball.position.distance(to: me.chest) < Opponent.attemptReach, race.spike != nil || race.snatch {
                switch race.spike {
                case .shield?: input.shield = !pressed.shield; shieldWhy = "goaltend"
                case .slash?: tapShoot(&input)
                default: tapThrow(&input)
                }
                race.spiked()
                race.snatch = false
                self.race = race
                return true
            }
            let toSoon = soon.x - me.position.x
            if abs(toSoon) > 3 { input.stick = Vec2(x: toSoon > 0 ? 1 : -1, y: 0) }
            // The double jump near the top of this one, if what's left of its rise won't get the hands to it.
            let riseLeft = max(me.velocity.y, 0) * max(me.velocity.y, 0) / (2 * max(me.gravity, 0.01))
            if me.jumpsLeft > 0, me.velocity.y < Opponent.doubleJumpBelow, soon.y > me.position.y + Opponent.handsOverFeet + riseLeft, abs(toSoon) < 40 {
                tapJump(&input)
            }
            return true
        }
        let speed = max(me.runSpeed, 0.1)
        let lift = me.fullHopVelocity, gravity = max(me.gravity, 0.01)
        // The hands get this far over the feet at a full hop's top; the double jump about as high again.
        let reachOverFeet = Opponent.handsOverFeet
        let hopHeight = lift * lift / (2 * gravity)
        let topReach = reachOverFeet + hopHeight * (me.jumpsLeft > 1 ? 2 : 1)
        var target: (point: Vec2, frames: Int)?
        // Failing one it gets to, the lowest it can get under in time: an attempt all the same.
        var lowest: (point: Vec2, frames: Int)?
        let rim = hoop(scoredOnBy: human.index, in: match).position
        for frames in 1...Opponent.goaltendLookahead {
            let point = ballPosition(ball, after: frames)
            // At the rim it's in: nothing to be had past there.
            if point.distance(to: rim) < Opponent.rimArrival { break }
            let height = point.y - me.position.y
            let run = abs(point.x - me.position.x) / speed
            if run + Double(me.spec.jumpSquatFrames) <= Double(frames), lowest == nil || point.y < lowest!.point.y { lowest = (point, frames) }
            guard height <= topReach else { continue }
            // Up to it: the squat and the rise to its height, on one jump or two.
            let rise = Double(me.spec.jumpSquatFrames) + (height > reachOverFeet ? Opponent.riseFrames(to: min(height - reachOverFeet, hopHeight), lift: lift, gravity: gravity) : 0)
            if run + rise <= Double(frames) {
                target = (point, frames)
                break
            }
        }
        guard let target = target ?? lowest else {
            // Nothing to be had in the air: in under the rim for the miss; off the court by the
            // stage's own ways there.
            if Opponent.readsStage(match) {
                go(to: Vec2(x: rim.x, y: rim.y - 40), match: match, me: me, into: &input, near: 12)
            } else {
                let toRim = rim.x - me.position.x
                if abs(toRim) > 12 { input.stick = Vec2(x: toRim > 0 ? 1 : -1, y: 0) }
            }
            return true
        }
        let toPoint = target.point.x - me.position.x
        if Opponent.readsStage(match) {
            // Off the court: under it by the stage's surfaces, never off a ledge into what's below.
            if let stand = terrain?.standing(nearest: Vec2(x: target.point.x, y: me.position.y)) {
                go(to: Vec2(x: stand.x, y: terrain!.surfaces[stand.surface].height(at: stand.x)), match: match, me: me, into: &input)
            }
        } else if abs(toPoint) > 4 {
            input.stick = Vec2(x: toPoint > 0 ? 1 : -1, y: 0)
        }
        let height = target.point.y - me.position.y
        let rise = height > reachOverFeet ? Opponent.riseFrames(to: min(height - reachOverFeet, hopHeight), lift: lift, gravity: gravity) : 0
        if height > reachOverFeet, Double(target.frames) <= Double(me.spec.jumpSquatFrames) + rise + 1, abs(toPoint) < 30 {
            fullHop(&input)
        }
        return true
    }
    /// How far over the feet the hands reach for a ball, how far ahead along a shot it looks.
    static let handsOverFeet = 20.0
    /// The ball this near the chest in the air, the shot's attempt goes in.
    static let attemptReach = 45.0
    /// In the air it steers for where the ball will be this many frames on.
    static let airLead = 6
    /// The double jump goes once the first's rising slower than this.
    static let doubleJumpBelow = 1.5
    static let goaltendLookahead = 90
    /// A shot this near its rim is in, or about to be.
    static let rimArrival = 15.0
    /// Frames from leaving the ground to this height on a jump of this lift.
    static func riseFrames(to height: Double, lift: Double, gravity: Double) -> Double {
        let under = max(lift * lift - 2 * gravity * height, 0)
        return (lift - under.squareRoot()) / gravity
    }

    /// What a person does stuck: pushing into something and going nowhere a moment, a hop toward
    /// the way; still stuck after that, the way given up and a step back the other way a while.
    /// Stood still on defence too long with nothing happening, it goes at them.
    mutating func unstick(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) {
        let moved = lastPosition.map { $0.distance(to: me.position) > 0.05 } ?? true
        lastPosition = me.position
        if backingAway > 0 {
            backingAway -= 1
            input.stick = Vec2(x: human.position.x > me.position.x ? -1 : 1, y: 0)
            return
        }
        let free = me.grounded && me.hitStun == 0 && !me.parryLocked && match.hitStop == 0 && match.countdown == 0
        if free, input.stick.x != 0, !moved {
            pushedStill += 1
        } else if moved {
            pushedStill = 0
            if me.grounded { unstickTries = 0 }
        }
        if pushedStill >= Opponent.stuckFrames {
            pushedStill = 0
            unstickTries += 1
            if unstickTries > Opponent.unstickHops {
                // Nowhere this way: let it go, and back off.
                unstickTries = 0
                journey = nil
                plan = .none
                planFrames = 0
                backingAway = Opponent.backAwayFrames
            } else {
                fullHop(&input)
            }
        }
        // Stood idle a while, no way found to the ball or to them: a try all the same, a hop toward
        // it and the double jump at the top, as a person would.
        let target = match.ball.holder == nil ? match.ball.position : human.position
        let idle = free && !moved && input.stick == .zero && !input.jump && !input.shoot && !input.throwBall && !me.holding
        idleFrames = idle ? idleFrames + 1 : 0
        if idleFrames >= Opponent.idleTryFrames {
            idleFrames = 0
            reachFrames = Opponent.reachTryFrames
        }
        if reachFrames > 0 {
            reachFrames -= 1
            let toTarget = target.x - me.position.x
            if abs(toTarget) > 4 { input.stick = Vec2(x: toTarget > 0 ? 1 : -1, y: 0) }
            if me.grounded {
                fullHop(&input)
            } else if me.velocity.y < 0.5, me.jumpsLeft > 0, target.y > me.position.y + Opponent.handsOverFeet {
                tapJump(&input)
            }
        }
    }
    static let stuckFrames = 40
    static let unstickHops = 2
    static let backAwayFrames = 60
    static let idleTryFrames = 90
    static let reachTryFrames = 40
}
