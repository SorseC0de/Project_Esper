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
    private var jumpShot = false
    /// The jump's button held through the squat, so the hop is full.
    var wantsFullHop = false
    private var humanStill = 0
    /// How long the other charged the throw they last let go: a long charge is telegraphed.
    /// Whether it will go for the throw in the air is decided once per throw.
    private var humanThrowCharge = 0
    private var lastThrowCharge = 0
    private var throwRead: Bool?
    /// Last frame's output, to make a press an edge.
    var pressed = PlayerInput.idle
    /// The frames the other's last slashes started on, to tell spam from a one-off, and
    /// whether the throw stance it's in is a parry, to be cancelled once it's done.
    private var slashStarts: [Int] = []
    private var parrying = false
    /// Off the court: the stage as read, the link being taken, links given up on a while, the
    /// search for a still rim's shot spots, and the spot it's making for.
    var terrain: Terrain?
    /// The helmet it last stood on, so stepping off its back isn't taken for it coming.
    private var riddenHelmet: Int?
    var journey: Journey?
    var givenUp: [GivenUp] = []
    var spotSearch: SpotSearch?
    private var readSpot: ShotSpot?
    private var readSpotFrames = 0

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
            pressed = .idle
            return .idle
        }
        humanStill = abs(human.velocity.x) < 0.2 && (human.state == .idle || human.state == .crouch) ? humanStill + 1 : 0
        if human.state == .slashing, human.stateTimer == 0 { slashStarts.append(match.frame) }
        slashStarts.removeAll { match.frame - $0 > Opponent.slashSpamFrames }
        if human.state == .throwStance {
            humanThrowCharge = human.stateTimer
        } else if human.state == .throwing {
            lastThrowCharge = humanThrowCharge
        } else {
            humanThrowCharge = 0
        }
        let readsStage = Opponent.readsStage(match)
        // Every stage is read, the court too, for what its own play can't reach.
        readStage(match, me: me)
        // Its rim's shot spots, found by trying shots, on every stage.
        let scoringHoop = match.stage.hoops.firstIndex { $0.owner == index } ?? 0
        if match.hoopfish == nil, match.stage.hoops.indices.contains(scoringHoop) { searchSpots(match, me: me, hoop: scoringHoop) }
        if readsStage, leaveTornado(match, me: me, toward: me.hasBall ? hoop(scoredOnBy: index, in: match).position : match.ball.position, into: &input) {
            // Out of a tornado before it lets go.
        } else if me.state == .jumpSquat {
            // Through the squat the button stays down for a full hop, or up for a short one.
            input.jump = wantsFullHop
        } else if clearHelmet(match, me: me, heading: heading(match, me: me, human: human), into: &input) {
            // A helmet bearing down: up and onto it, whatever else it was doing.
        } else if me.hasBall {
            offence(match, me: me, human: human, into: &input)
        } else if human.hasBall {
            defence(match, me: me, human: human, into: &input)
        } else {
            neutral(match, me: me, human: human, into: &input)
        }
        if readsStage, me.state == .suspended, me.hitStun > 0 {
            // Stunned in a tornado the jump won't answer but the stick still drifts it: held still, the pull keeps it in.
            input = PlayerInput()
        } else if readsStage, me.state != .jumpSquat {
            if journey?.started != true { dodgeHazards(match, me: me, into: &input) }
            if journey?.started != true { keepTheDribbleOffTheLava(match, me: me, into: &input) }
            keepOffTheLava(match, me: me, into: &input)
        }
        pressed = input
        return input
    }

    /// Two slashes inside this many frames is spam, and the next is met with the throw
    /// stance's parry.
    private static let slashSpamFrames = 90

    // MARK: Helmets

    /// A helmet coming at it at its height, close. Low enough to go under crouched, and
    /// with nothing in hand on the floor, it crouches, or slides from a run, until it's
    /// past; otherwise a full hop and the double jump to get on top and ride it, holding
    /// still until clear of its top, then over. True while it's doing either.
    private static let helmetLeadFrames = 20.0

    /// Which way it's going about its business: to the rim it scores on with the ball, the one it
    /// guards without, the ball when it's loose.
    private func heading(_ match: Match, me: Player, human: Player) -> Double {
        let x = me.hasBall ? hoop(scoredOnBy: index, in: match).position.x
            : human.hasBall ? hoop(scoredOnBy: human.index, in: match).position.x : match.ball.position.x
        return x >= me.position.x ? 1 : -1
    }

    private mutating func clearHelmet(_ match: Match, me: Player, heading: Double, into input: inout PlayerInput) -> Bool {
        guard !Opponent.committedStates.contains(me.state) || me.state == .slide else { return false }
        let feet = me.position.y
        // Stood on its top: the body's grounded flag can lag a frame behind one that moves.
        if let standing = match.helmets.first(where: { abs($0.box.max.y - feet) < 0.5 && me.velocity.y <= 0
            && me.position.x >= $0.box.min.x && me.position.x <= $0.box.max.x }) {
            riddenHelmet = standing.id
        } else if me.grounded {
            riddenHelmet = nil
        }
        let standingTop = feet + me.spec.bodyHeight
        let crouchedTop = feet + me.spec.bodyHeight / 2
        let halfWidth = me.spec.bodyWidth / 2
        let coming = match.helmets.first { helmet in
            let ahead = (me.position.x - helmet.box.center.x) * (helmet.speed > 0 ? 1 : -1)
            let gap = ahead - helmet.box.width / 2 - halfWidth
            // At its height, or up in the air over it on the way down onto it.
            let above = !me.grounded && feet >= helmet.box.max.y - 1 && feet < helmet.box.max.y + 60
            let level = (helmet.box.min.y < standingTop + 4 && helmet.box.max.y > feet) || above
            // Close by time, not distance: the frames to meet it at the speed they're closing.
            let closing = max(abs(helmet.speed) - me.velocity.x * (helmet.speed > 0 ? 1 : -1), 1)
            // Ridden, and stepped off its back: let it go on and come down behind it.
            let leaving = above && ahead < 0 && riddenHelmet == helmet.id
            return ahead > -helmet.box.width && gap < closing * Opponent.helmetLeadFrames && level && !leaving
        }
        guard let helmet = coming else { return false }
        if me.grounded, !me.holding, helmet.box.min.y > crouchedTop + 1 {
            // Under it: down, and from a run that's the slide.
            input.stick = Vec2(x: 0, y: -1)
            return true
        }
        guard me.state != .slide else { return true }
        if (helmet.speed > 0 ? 1.0 : -1.0) != heading {
            // Coming from where it's headed: riding it would carry it back the way it came. Over it
            // and on, both jumps if it needs them: held still on the way up so it comes on slower,
            // across once the feet are over its top.
            input.stick = me.grounded || me.position.y > helmet.box.max.y + 1 ? Vec2(x: heading, y: 0) : .zero
            if me.grounded {
                fullHop(&input)
            } else if me.velocity.y < 0.5, me.jumpsLeft > 0, me.position.y < helmet.box.max.y + 2 {
                tapJump(&input)
            }
            return true
        }
        // In the air the stick lets go, and the air's brake holds it, until the feet clear the
        // top; then into it, and let go again once over it, so it sets down there.
        let over = abs(helmet.box.center.x - me.position.x) < helmet.box.width / 4
        let clear = me.position.y > helmet.box.max.y + 1
        let toward = Vec2(x: helmet.box.center.x > me.position.x ? 1 : -1, y: 0)
        input.stick = me.grounded ? toward : (clear && !over ? toward : .zero)
        if me.grounded {
            fullHop(&input)
        } else if me.velocity.y < 0.5, me.jumpsLeft > 0, me.position.y < helmet.box.max.y + 2 {
            tapJump(&input)
        }
        return true
    }

    // MARK: Chance and presses

    mutating func roll(_ sides: UInt32) -> UInt32 {
        random = random &* 1664525 &+ 1013904223
        return (random >> 16) % sides
    }

    mutating func chance(_ percent: UInt32) -> Bool {
        roll(100) < percent
    }

    /// A press is an edge: down this frame only if it was up last frame.
    func tapJump(_ input: inout PlayerInput) { input.jump = !pressed.jump }
    func tapShoot(_ input: inout PlayerInput) { input.shoot = !pressed.shoot }
    func tapThrow(_ input: inout PlayerInput) { input.throwBall = !pressed.throwBall }

    mutating func fullHop(_ input: inout PlayerInput) {
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

    private mutating func offence(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) {
        var hoop = hoop(scoredOnBy: index, in: match)
        let readsStage = Opponent.readsStage(match)
        let hoopIndex = match.stage.hoops.firstIndex { $0.owner == index } ?? 0
        let rimPath = readsStage ? hoopPath(match) : nil
        if let rimPath {
            // A rim on the move is played where it'll be in a moment, or where it comes back in.
            guard let coming = rimPath.prefix(20).last(where: { $0 != HighwayRules.parked }) ?? rimPath.first(where: { $0 != HighwayRules.parked }) else {
                // None for a while: the ball kept, away from them.
                readSpot = nil
                if !Opponent.committedStates.contains(me.state), me.state != .shootStance, me.state != .throwStance {
                    let away: Double = me.position.x >= human.position.x ? 1 : -1
                    go(to: Vec2(x: me.position.x + away * 40, y: me.position.y), match: match, me: me, into: &input)
                } else if me.state == .shootStance {
                    input.stick = Vec2(x: 0, y: -1)
                }
                return
            }
            hoop.position = coming
        }
        // The Hoopfish's rim is never dunked on: it spins the dunk away.
        let rimOut = rimPath != nil
        let inward = -hoop.backboard.sign
        let toHoop = hoop.position.x - me.position.x
        let gap = human.position.x - me.position.x
        let level = abs(human.position.y - me.position.y) < 30
        let near = abs(gap) < 50 && level
        let inReach = abs(gap) < 26 && level

        // The parry: held through its frames, then the shoot button cancels it, ball kept.
        if parrying {
            if me.state == .throwStance {
                if me.stateTimer >= ThrowParryRules.frames {
                    input.shoot = true
                    parrying = false
                } else {
                    input.throwBall = true
                }
                return
            }
            parrying = false
        }
        // Spam in reach: the next slash's start is met with the stance.
        let facingMe = (me.position.x - human.position.x) * human.facing.sign > 0
        if human.state == .slashing, human.stateTimer < SlashRules.liveFrames.lowerBound, slashStarts.count >= 2,
           abs(gap) < 34, level, facingMe, [.idle, .walk, .run, .dash, .air].contains(me.state) {
            input.throwBall = true
            parrying = true
            return
        }
        // In the air by the rim: the dunk, whatever the plan was.
        if !rimOut, !me.grounded, me.state == .air, hoop.position.distance(to: me.chest) < 60, me.chest.y > hoop.position.y - 40 {
            plan = .dunk
            planFrames = max(planFrames, 20)
        }
        let dangerous = Opponent.dangerous(human)
        let open = Opponent.open(human) && abs(gap) < 60 && level
        let committed = dangerous || open
        // Behind the block: on the backboard's side of the rim, past the block's face.
        let behind = !readsStage && (me.position.x - hoop.position.x) * hoop.backboard.sign > 5 && me.position.y < 100

        // In the stance: a fake is called off with the throw (letting go of shoot always shoots,
        // and down is the stepback); a shot holds through the windup with the aim on the rim,
        // then lets go, sooner if they're closing in; a jump shot hops out of the stance after
        // the windup and lets go on the rise with the aim solved for the lift.
        if me.state == .shootStance {
            stanceFrames += 1
            // A stance outliving its plan, a fake's run out before it was called off, is called
            // off now: never a shot it didn't pick.
            if plan != .fake, plan != .shoot {
                input.shoot = true
                tapThrow(&input)
                return
            }
            if plan == .fake {
                input.shoot = true
                if stanceFrames >= fakeHold {
                    tapThrow(&input)
                    plan = .none
                    planFrames = 0
                }
                return
            }
            if jumpShot {
                if me.grounded {
                    input.shoot = true
                    if stanceFrames > BallRules.shotWindupFrames { fullHop(&input) }
                } else {
                    guard let aim = aimShot(match, me: me, hoop: hoopIndex, path: rimPath) else {
                        // Nothing goes in from here: the stance called off, the ball kept.
                        input.shoot = true
                        tapThrow(&input)
                        return
                    }
                    input.aim = aim
                    input.shoot = me.velocity.y > Opponent.jumpShotLetGo
                }
                return
            }
            if let aim = aimShot(match, me: me, hoop: hoopIndex, path: rimPath) {
                input.aim = aim
                input.shoot = stanceFrames <= BallRules.shotWindupFrames + 1 && !(inReach && !committed)
            } else {
                // Nothing goes in from here: the stance called off, the ball kept.
                input.shoot = true
                tapThrow(&input)
                plan = .none
                planFrames = 0
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
        // A rim on the move: wherever it is, a shot that goes in from right here is taken now.
        if let rimPath, plan != .shoot, me.grounded, [.idle, .walk, .run, .dash].contains(me.state), match.frame % 3 == 0 {
            let standing = !scoringAngles(match, body: me, jumpShot: false, stanceSoFar: 0, hoop: hoopIndex, path: rimPath, stopAtFirst: true).isEmpty
            let jumping = !standing && !scoringAngles(match, body: me, jumpShot: true, stanceSoFar: 0, hoop: hoopIndex, path: rimPath, stopAtFirst: true).isEmpty
            if standing || jumping {
                readSpot = ShotSpot(feet: me.position, jumpShot: jumping)
                readSpotFrames = 90
                plan = .shoot
                planFrames = 90
                jumpShot = jumping
            }
        }
        // A spot among those its shots were found to go in from, picked afresh now and then.
        if readSpot == nil || readSpotFrames <= 0 {
            readSpot = rimPath.flatMap { spotUnderMovingRim(match, me: me, path: $0) } ?? pickReadSpot(match, me: me, human: human, hoop: hoop)
                ?? terrain?.standing(nearest: Vec2(x: hoop.position.x + inward * 50, y: hoop.position.y - 60)).map { stand in
                    ShotSpot(feet: Vec2(x: stand.x, y: terrain!.surfaces[stand.surface].height(at: stand.x)), jumpShot: true)
                }
            readSpotFrames = rimPath != nil ? 45 : 240
        } else {
            readSpotFrames -= 1
        }
        let target = readSpot?.feet ?? me.position
        let atSpot = abs(target.x - me.position.x) < 6 && abs(target.y - me.position.y) < 4 && me.grounded
        // Off the court the way there may not run straight at the spot: what's in the way is what's on the next step of it.
        let toWay = (readsStage ? nextStepX(toward: target, match: match, me: me) : target.x) - me.position.x
        let blocked = abs(toWay) >= 1 && (gap > 0) == (toWay > 0) && abs(gap) < abs(toWay) + 10 && near
        // The dash and the jump over go that way too; on the court, at the rim.
        let toRush = readsStage ? toWay : toHoop
        // Over lava a lob is the ball thrown away to chase where it can burn.
        let lobs = match.stage.features.lavaSurface == nil

        // Near enough the rim and level with its floor: the dunk, up and onto it.
        let rimClose = readsStage ? !rimOut && abs(toHoop) < 55 && dunkReach(match, rim: hoop.position)
            : abs(toHoop) < 55 && me.position.y < hoop.position.y && hoop.position.y - me.position.y < 60
        if behind, plan != .dunk {
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
            } else if atSpot, let rimPath {
                // A rim on the move: only the shot that, played out, goes in from here and now;
                // none does, and it waits for the rim to come round.
                let standing = !scoringAngles(match, body: me, jumpShot: false, stanceSoFar: 0, hoop: hoopIndex, path: rimPath, stopAtFirst: true).isEmpty
                let jumping = !standing && !scoringAngles(match, body: me, jumpShot: true, stanceSoFar: 0, hoop: hoopIndex, path: rimPath, stopAtFirst: true).isEmpty
                if standing || jumping {
                    plan = .shoot
                    planFrames = 90
                    jumpShot = jumping
                    dances = 0
                } else {
                    plan = .hold
                    planFrames = 4
                }
            } else if atSpot {
                plan = .shoot
                planFrames = 90
                jumpShot = readSpot?.jumpShot ?? true
                dances = 0
            } else if blocked, !committed {
                dances += 1
                if dances > 3 {
                    // Enough waiting: up and over, the lob, or another spot.
                    dances = 0
                    switch roll(3) {
                    case 0: plan = .over; planFrames = 45
                    case 1: plan = lobs ? .lob : .over; planFrames = 60
                    default:
                        readSpot = nil
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
                        plan = lobs ? .lob : .over
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
        // Off the court only when they're on the side it's going.
        let crowding = !readsStage || (abs(toWay) >= 1 && (gap > 0) == (toWay > 0))
        if crowding, abs(gap) < 16, level, !committed, ![.dart, .retreat, .over, .lob, .dunk].contains(plan) {
            switch roll(10) {
            case 0...3: plan = .dart
            case 4...6: plan = .retreat
            default: plan = lobs ? .lob : .over
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
            if planFrames >= 39 || abs(toRush) < 1 { break }
            input.stick = Vec2(x: toRush > 0 ? 1 : -1, y: 0)
            let between = (gap > 0) == (toRush > 0) && abs(gap) < abs(toRush)
            if between, abs(gap) < 30, me.grounded {
                fullHop(&input)
            } else if !me.grounded, me.velocity.y < 0.5, me.jumpsLeft > 0, between, abs(gap) < 20 {
                tapJump(&input)
            }
        case .retreat:
            input.stick = Vec2(x: gap > 0 ? -0.5 : 0.5, y: 0)
        case .travel:
            if readsStage {
                go(to: target, match: match, me: me, into: &input)
            } else {
                travel(to: target, me: me, human: human, into: &input)
            }
        case .shoot:
            // Pressed afresh: a stance only starts on a press.
            if !atSpot, me.grounded {
                plan = .none
            } else if me.grounded {
                tapShoot(&input)
            }
        case .lob:
            // The throw stance with up; the stance handler lets it go.
            input.stick = Vec2(x: 0, y: 1)
            input.throwBall = true
        case .over:
            // Up and over toward the rim: a full hop, the double jump at the top.
            if abs(toRush) < 1 { break }
            input.stick = Vec2(x: toRush > 0 ? 1 : -1, y: 0)
            if me.grounded {
                fullHop(&input)
            } else if me.velocity.y < 0.5, me.jumpsLeft > 0 {
                tapJump(&input)
            }
        case .climb:
            climbOut(me: me, hoop: hoop, into: &input)
        case .dunk:
            // In under the rim, a full hop when it's close, and the throw held in the air
            // so the stance carries it onto the rim. Off the court, the way to under it first.
            if readsStage, me.grounded, abs(toHoop) >= 34 {
                go(to: Vec2(x: hoop.position.x, y: hoop.position.y - 30), match: match, me: me, into: &input)
                if planFrames == 0 { plan = .none }
                break
            }
            input.stick = Vec2(x: toHoop > 0 ? 1 : -1, y: 0)
            if me.grounded, abs(toHoop) < 34 {
                fullHop(&input)
            } else if !me.grounded {
                if me.velocity.y < 0.5, me.jumpsLeft > 0, hoop.position.y - me.chest.y > 20 { tapJump(&input) }
                // Only inside the dunk's reach: a stance any further off is a throw let go.
                if hoop.position.distance(to: me.chest) < BallRules.dunkRadius * me.spec.scale { input.throwBall = true }
            }
            if planFrames == 0 { plan = .none }
        default:
            plan = .none
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
    /// Out from behind the block: under it, along the floor, back out in front of the rim;
    /// in the air, down and out the same way. The block floats, so the floor is open.
    private mutating func climbOut(me: Player, hoop: Hoop, into input: inout PlayerInput) {
        input.stick = Vec2(x: -hoop.backboard.sign, y: 0)
    }

    /// The flick for the shot from where it is: the ball's own flight tried, the rim followed
    /// where it moves, on every stage.
    private func aimShot(_ match: Match, me: Player, hoop hoopIndex: Int, path: [Vec2]?) -> Vec2? {
        aimByFlight(match, me: me, jumpShot: jumpShot, stanceSoFar: stanceFrames - 1, hoop: hoopIndex, path: path)
    }

    // MARK: The other with the ball

    private mutating func defence(_ match: Match, me: Player, human: Player, into input: inout PlayerInput) {
        var hoop = hoop(scoredOnBy: human.index, in: match)
        let readsStage = Opponent.readsStage(match)
        // A rim out of play, off with the Hoopfish: on them instead.
        if readsStage, hoop.position == HighwayRules.parked { hoop.position = human.position + Vec2(x: 0, y: 40) }
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
        // A throw charged at it for more than a few frames is telegraphed: it squares up
        // to them and stands ready, and the snatch comes as the ball does.
        let charged = human.state == .throwStance ? humanThrowCharge : (human.state == .throwing ? lastThrowCharge : 0)
        if human.state == .throwStance || human.state == .throwing, charged > 6, abs(gap) < 100, level, (gap > 0) == (human.facing == .left) {
            plan = .none
            planFrames = 0
            if me.facing != (gap > 0 ? .right : .left) { input.stick = Vec2(x: gap > 0 ? 0.5 : -0.5, y: 0) }
            return
        }
        let winding = human.state == .shootStance || (human.state == .throwStance && abs(gap) < 30)
        let humanOpen = Opponent.open(human)
        if winding || plan == .strike || (humanOpen && abs(gap) < 45) || (rest == 0 && abs(gap) < 45 && humanStill > 20 && chance(4)) {
            // The strike: in at them and the swing when the blade will reach, up first if
            // they're above. In reach, the slash, or the snatch up close.
            plan = .strike
            planFrames = 30
            // On another surface: the way there first; on the court, up a block's wall to them.
            let climbing = journey?.started == true || (human.grounded && outOfJumpingReach(human.position, me: me))
            if (readsStage && (abs(rise) >= 24 || abs(gap) > 60)) || climbing {
                go(to: human.position, match: match, me: me, into: &input)
                return
            }
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
            if readsStage {
                if go(to: human.position, match: match, me: me, into: &input, near: 32) || (abs(gap) <= 32 && level) {
                    plan = .strike
                    planFrames = 30
                }
                return
            }
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
            if readsStage {
                go(to: Vec2(x: hoverX, y: hoop.position.y - 40), match: match, me: me, into: &input, near: 8)
                return
            }
            if abs(toHover) > 8 { input.stick = Vec2(x: toHover > 0 ? 0.5 : -0.5, y: 0) }
            return
        }
        if readsStage, !go(to: Vec2(x: guardX, y: hoop.position.y - 40), match: match, me: me, into: &input, near: 6) {
            return
        } else if !readsStage, abs(toGuard) > 6 {
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
            if Opponent.readsStage(match) {
                go(to: Vec2(x: hoop.position.x - (hoop.shared ? 0 : hoop.backboard.sign * 30), y: hoop.position.y - 40), match: match, me: me, into: &input)
                return
            }
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
        // A throw coming at it: it stands its ground, facing it, and the snatch goes out so
        // the hand is live as the ball arrives. Charged more than a few frames it was
        // telegraphed and the snatch comes every time; a quick throw gets by seven in ten.
        if ball.strikes, ball.velocity.x != 0, abs(ball.position.y - me.chest.y) < 14,
           (ball.position.x < me.position.x) == (ball.velocity.x > 0) {
            if throwRead == nil { throwRead = lastThrowCharge > 6 || chance(30) }
            let toward: Facing = ball.position.x < me.position.x ? .left : .right
            if me.facing != toward, me.grounded {
                input.stick = Vec2(x: toward.sign * 0.5, y: 0)
                return
            }
            let reach = abs(ball.position.x - me.handCatchPoint.x) - BallRules.handCatchRadius - BallRules.radius
            let framesAway = reach / abs(ball.velocity.x)
            if throwRead == true, me.snatchCooldown == 0, framesAway <= Double(SnatchRules.activeFrames.lowerBound + 1) {
                tapThrow(&input)
            }
            return
        }
        throwRead = nil
        // On the court, a ball up where no jump from here reaches, the blocks' tops, is gone after
        // by the reading: up the wall beside it; a climb under way is played out.
        if Opponent.readsStage(match) || outOfJumpingReach(ball, me: me) || journey?.started == true {
            if !snatchOrSpike(ball, me: me, human: human, into: &input) { chaseReadBall(match, me: me, into: &input) }
            return
        }
        journey = nil
        let target = landing(of: ball, in: match.stage)
        let toBall = target - me.position.x
        let above = ball.position.y - me.position.y
        if snatchOrSpike(ball, me: me, human: human, into: &input) { return }
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

    /// How near the other must be to a loose ball for it to be worth spiking away from them.
    static let contestReach = 60.0

    /// Whether the ball rests on a surface higher over the feet than the jumps go.
    private func outOfJumpingReach(_ ball: Ball, me: Player) -> Bool {
        ball.velocity.length < 1 && outOfJumpingReach(ball.position, me: me)
    }

    /// Whether a point is over a surface higher over the feet than the jumps go: a block's top.
    private func outOfJumpingReach(_ point: Vec2, me: Player) -> Bool {
        guard let terrain, terrain.ready, let under = terrain.standing(nearest: point) else { return false }
        let height = terrain.surfaces[under.surface].height(at: under.x)
        return abs(under.x - point.x) < 10 && height - me.position.y > terrain.rise + 8
    }

    /// A ball in flight about to be in reach: the snatch to take it, timed for the hand, or the
    /// slash to spike it, by chance, but only out of the other's reach: an uncontested ball is
    /// let come to it, not knocked away to chase.
    private mutating func snatchOrSpike(_ ball: Ball, me: Player, human: Player, into input: inout PlayerInput) -> Bool {
        guard ball.velocity.length > 2 else { return false }
        let soon = ballPosition(ball, after: 6)
        let inHand = soon.distance(to: me.handCatchPoint) <= BallRules.handCatchRadius || soon.distance(to: me.chest) <= BallRules.catchRadius
        let inBlade = abs(soon.x - me.bladeCentre.x) <= SlashRules.reach && abs(soon.y - me.bladeCentre.y) <= SlashRules.reach
        let contested = soon.distance(to: human.chest) < min(soon.distance(to: me.chest) + 20, Opponent.contestReach)
        if inHand, me.snatchCooldown == 0, chance(70) {
            tapThrow(&input)
            return true
        } else if inBlade, contested, chance(50) {
            tapShoot(&input)
            return true
        }
        return false
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
