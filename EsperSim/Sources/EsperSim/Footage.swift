import Foundation

/// Footage: scripted scenes for trailer capture, each a match set up a certain way and both sides
/// driven frame by frame, or left to the computer (`nil` for that side). The app records each
/// scene and logs its events; `Tools/highlights.py` cuts the clips.
public struct FootageScene {
    public var name: String
    public var stage: StageChoice
    public var mode: GameMode
    /// Each side's energy colour, by `EnergyColour`'s raw value; the app resolves them.
    public var colours: [String]
    /// Each side's drink awake from the start at level two (Rounds), or picked ahead for 47 and
    /// Breaker Ball, where it wakes in FloState (or at once in Breaker Ball).
    public var drinks: [Greateraid?]
    /// The drinks awake from the start in 47 too, as the POWER picker has them: no FloState.
    public var drinksAwake = false
    /// Anozira's weather held: 0 clear, 1 the full storm; nil as the match has it.
    public var rain: Double?
    public var countdown: Int
    public var maxFrames: Int
    /// Both sides the computer's, the game played to its end.
    public var cpuMatch = false
    /// Rounds: the first side's drink pick after it's scored on, its cursor's moves one beat apart, then the drink.
    public var pickMoves: [Int] = []
    /// The computer's seeds for each side, wherever the scene leaves a side to it.
    public var seeds: [UInt32] = [1, 10]
    /// The stage's preview played first, its big panel kept as a still (`preview_` scenes).
    public var showsPreview = false
    public var setup: (inout Match) -> Void
    /// Applied to the match before every frame: what the scene holds in place.
    public var eachFrame: ((inout Match) -> Void)?
    public var step: (inout FootageDirector, Match) -> [PlayerInput?]
    public var done: (FootageDirector, Match) -> Bool

    public init(name: String, stage: StageChoice, mode: GameMode = .rounds, colours: [String] = ["yellow", "teal"],
                drinks: [Greateraid?] = [nil, nil], rain: Double? = nil, countdown: Int = 0, maxFrames: Int = 1200,
                setup: @escaping (inout Match) -> Void = { _ in },
                eachFrame: ((inout Match) -> Void)? = nil,
                step: @escaping (inout FootageDirector, Match) -> [PlayerInput?] = { _, _ in [nil, nil] },
                done: @escaping (FootageDirector, Match) -> Bool = { _, _ in false }) {
        self.name = name
        self.stage = stage
        self.mode = mode
        self.colours = colours
        self.drinks = drinks
        self.rain = rain
        self.countdown = countdown
        self.maxFrames = maxFrames
        self.setup = setup
        self.eachFrame = eachFrame
        self.step = step
        self.done = done
    }

    /// The match as the scene starts it, before the app's own round setup is layered on.
    public func makeMatch(seed: UInt32 = 7) -> Match {
        var match = Match(stage: stage.stage, specs: [.starting, .starting], countdown: countdown, seed: seed, mode: mode)
        prepare(&match)
        return match
    }

    /// The scene's drinks, Anozira's FLO and its own setup onto a match made for its stage and mode.
    public func prepare(_ match: inout Match) {
        for (index, drink) in drinks.enumerated() where match.players.indices.contains(index) {
            if mode.picksDrinkAhead, !drinksAwake {
                match.players[index].floStateDrink = drink
            } else if let drink {
                match.wake(drink, on: index)
            }
        }
        match.wakeBreakerDrinks()
        if !cpuMatch, match.stage.features.look == .anozira, mode != .breakerBall {
            // The hoop truck in and home from the start, as the stage preview has it: the ball's handed
            // over, so the ball truck's release that calls it in never comes.
            match.anoziraStart = match.frame
            match.hoopTruckArrives = match.frame - AnoziraRules.truckEnterFrames - 1
        }
        if !cpuMatch, match.stage.features.roadSlides {
            // Anozira's road slides whoever has no FLO: the scripted sides run on it instead.
            for index in match.players.indices { match.players[index].flo = FloRules.full - 1 }
        }
        setup(&match)
    }
}

/// A scene's running state: which phase it's in, how long it's been there, and notes the
/// script keeps between frames.
public struct FootageDirector {
    public var phase = 0
    /// Frames in this phase.
    public var phaseFrames = 0
    public var frames = 0
    public var notes: [String: Double] = [:]
    /// Set by a script once its scene has shown what it's for; the app stops a moment later.
    public var finished = false

    public init() {}

    public mutating func advance() {
        phase += 1
        phaseFrames = 0
    }

    /// On to the next phase once this one has run `frames`.
    public mutating func advance(after frames: Int) {
        if phaseFrames >= frames { advance() }
    }

    public mutating func go(to phase: Int) {
        self.phase = phase
        phaseFrames = 0
    }

    public mutating func tick() {
        frames += 1
        phaseFrames += 1
    }
}

extension Match {
    /// A drink awake on a body at level two, as Breaker Ball wakes its picks: its power in hand and
    /// its body changes on.
    public mutating func wake(_ drink: Greateraid, on index: Int) {
        guard players.indices.contains(index) else { return }
        players[index].spec = Drinks.levelTwo(drink).spec(from: players[index].spec)
        if let power = drink.power {
            players[index].power = power
            players[index].powerLevel = 2
        }
    }

    /// A body set down standing here, still.
    public mutating func place(_ index: Int, at x: Double, y: Double, facing: Facing) {
        guard players.indices.contains(index) else { return }
        players[index].position = Vec2(x: x, y: y)
        players[index].velocity = .zero
        players[index].facing = facing
    }

    /// The rim this player scores on, where it is now; nil while it's off the stage.
    public func scoringRim(for index: Int) -> Vec2? {
        guard let rim = stage.hoops.first(where: { !$0.rimless && ($0.shared || $0.owner == index) })?.position,
              rim.x > -100, rim.y < 1000 else { return nil }
        return rim
    }

    /// The ball out of play, held off the stage.
    public mutating func parkBall() {
        if let holder = ball.holder {
            players[holder].hasBall = false
            ball.holder = nil
        }
        ball.respawn(at: Vec2(x: -1000, y: 300))
        ball.frozen = 2
    }

    /// Anozira: the hoop truck's roof, its one-way tops at the stage's right, as one span; nil till it's in.
    public var anoziraTruckRoof: Box? {
        let tops = stage.oneWayBoxes.filter { $0.min.x >= 300 }
        guard let first = tops.first else { return nil }
        return tops.dropFirst().reduce(first) { Box(min: Vec2(x: min($0.min.x, $1.min.x), y: min($0.min.y, $1.min.y)), max: Vec2(x: max($0.max.x, $1.max.x), y: max($0.max.y, $1.max.y))) }
    }

    /// Anozira: a pothole on the road within `ahead` units in front of `index`'s feet, the way they face.
    public func potholeAhead(of index: Int, within ahead: Double) -> Bool {
        let player = players[index]
        return potholes.contains { ($0 - player.position.x) * player.facing.sign > -8 && ($0 - player.position.x) * player.facing.sign < ahead }
    }
}

/// Input makers for the scripts.
public enum FootageInput {
    public static func stick(_ x: Double, _ y: Double = 0, jump: Bool = false, shoot: Bool = false, throwBall: Bool = false, shield: Bool = false, aim: Vec2 = .zero) -> PlayerInput {
        PlayerInput(stick: Vec2(x: x, y: y), aim: aim, jump: jump, shoot: shoot, throwBall: throwBall, shield: shield)
    }

    /// The stick toward `x`, full on; nothing within `slack` of it.
    public static func toward(_ player: Player, x: Double, slack: Double = 3) -> PlayerInput {
        let away = x - player.position.x
        return abs(away) <= slack ? .idle : stick(away > 0 ? 1 : -1)
    }

    /// Facing `x` from where the body stands, without moving far: a nudge on the stick that way.
    public static func facing(_ player: Player, x: Double) -> PlayerInput {
        if (x > player.position.x) == (player.facing == .right) { return .idle }
        return stick(x > player.position.x ? 0.6 : -0.6)
    }

    /// A shot's flick angle that drops the ball onto `rim` from `from` at `speed`, under the
    /// ball's gravity: the lower arc (or the higher with `high`), or nil if the rim is out of range.
    /// The ball steps its speed down before it moves, so it flies half a frame's gravity lower
    /// than the textbook arc: the aim is lifted by that, and by `margin` over the rim.
    public static func shotAngle(from: Vec2, to rim: Vec2, speed: Double, high: Bool = false, margin: Double = 1, gravity: Double = BallRules.gravity) -> Double? {
        let across = abs(rim.x - from.x)
        guard across > 0 else { return nil }
        let speedSquared = speed * speed
        var up = rim.y + margin - from.y
        var angle: Double?
        for _ in 0..<3 {
            let root = speedSquared * speedSquared - gravity * (gravity * across * across + 2 * up * speedSquared)
            guard root >= 0 else { return nil }
            let found = atan((speedSquared + (high ? 1 : -1) * root.squareRoot()) / (gravity * across))
            let frames = across / (speed * cos(found))
            up = rim.y + margin - from.y + gravity / 2 * frames
            angle = found
        }
        return angle.map { min(max($0, BallRules.shotAngleMin), BallRules.shotAngleMax) }
    }

    /// How many frames the ball takes to `rim` along that arc.
    public static func flightFrames(from: Vec2, to rim: Vec2, speed: Double, angle: Double) -> Double {
        abs(rim.x - from.x) / (speed * cos(angle))
    }

    /// The flick for that angle, the way the body faces.
    public static func flick(_ angle: Double, facing: Facing) -> Vec2 {
        Vec2(x: cos(angle) * facing.sign, y: sin(angle))
    }

    /// Where the ball will leave from if the shoot button's let go now: the release comes
    /// `BallRules.shotReleaseFrames` on, the body falling meanwhile.
    public static func predictedReleasePoint(_ player: Player) -> Vec2 {
        let frames = Double(BallRules.shotReleaseFrames)
        let rise = player.grounded ? 0 : player.velocity.y * frames - 0.5 * player.spec.gravity * frames * frames
        return player.shotReleasePoint + Vec2(x: 0, y: rise)
    }

    /// The flick onto `rim` from where the shot will leave, or a steep one if it's out of range;
    /// a rim on the move (`moving`, units a frame) is led by the ball's flight.
    public static func flickAt(_ rim: Vec2, by player: Player, moving: Vec2 = .zero, margin: Double = 1) -> Vec2 {
        let from = predictedReleasePoint(player)
        var target = rim
        var angle: Double?
        for _ in 0..<3 {
            guard let found = shotAngle(from: from, to: target, speed: player.spec.shotSpeed, margin: margin) else { break }
            angle = found
            let frames = flightFrames(from: from, to: target, speed: player.spec.shotSpeed, angle: found) + Double(BallRules.shotReleaseFrames)
            target = rim + moving * frames
        }
        let toward: Facing = rim.x >= from.x ? .right : .left
        return angle.map { flick($0, facing: toward) } ?? flick(0.8, facing: toward)
    }
}

/// The scenes themselves.
public enum FootageScenes {
    public static let colours = ["yellow", "teal", "red", "green", "blue", "purple", "orange", "pink"]

    /// The computer's seeds where the plain pair didn't let a scene show what it's for, found by the probe.
    static let provenSeeds: [String: [UInt32]] = [
        "jumpshot_wreckCenter_60": [2, 17],
        "jumpshot_wreckCenter_100": [2, 17],
        "jumpshot_wreckCenter_140": [2, 17],
        "jumpshot_kAndA_100": [3, 24],
        "jumpshot_kAndA_140": [2, 17],
        "jumpshot_anozira_90": [3, 40],
        "jumpshot_anozira_100": [2, 27],
        "jumpshot_anozira_115": [6, 45],
        "jumpshot_hoopfishHideaway_60": [4, 53],
        "jumpshot_hoopfishHideaway_90": [4, 53],
        "floater_glass_anozira": [2, 27],
        "flostate_phantomFrappe_wreckCenter": [2, 27],
    ]

    /// Every scripted scene, in the order they're shot.
    /// Each previewed stage's preview played, for its big panel's still; the match after barely runs.
    public static var previewStills: [FootageScene] {
        [StageChoice.wreckCenter, .longballStadium, .theElements, .hoopfishHideaway, .flightB411, .kAndA, .anozira].map { stage in
            var scene = FootageScene(name: "preview_\(stage)", stage: stage, maxFrames: 30, step: { _, _ in [.idle, .idle] })
            scene.showsPreview = true
            return scene
        }
    }

    public static var scripted: [FootageScene] {
        var scenes: [FootageScene] = []
        scenes += jumpshots
        scenes += dunks
        scenes += floaters
        scenes += [beamBreak, blasts, elementsSwing, smoothieDefence]
        scenes += clashes
        scenes += floStateMontage
        scenes += [roundsFlight, fortySevenKAndA]
        scenes += [tauntThreeWreckCenter]
        scenes += [webSwingLongball, webSwingElements, flashDunkWreckCenter, flashThrowKAndA]
        for index in scenes.indices { if let seeds = provenSeeds[scenes[index].name] { scenes[index].seeds = seeds } }
        return scenes
    }

    /// Computer against computer, a game each: 47 and Breaker Ball across the stages.
    public static var cpuMatches: [FootageScene] {
        var scenes: [FootageScene] = []
        let pairs: [(StageChoice, GameMode, [Greateraid?], [String])] = [
            (.wreckCenter, .fortySeven, [.zTea, .webWater], ["yellow", "teal"]),
            (.anozira, .fortySeven, [.superSmoothie, .flashFizz], ["red", "blue"]),
            (.kAndA, .fortySeven, [.voltaCola, .galeAle], ["green", "purple"]),
            (.hoopfishHideaway, .fortySeven, [.blazingBoba, .frostTea], ["orange", "teal"]),
            (.flightB411, .fortySeven, [.titanTea, .pulsepistol], ["yellow", "pink"]),
            (.theElements, .breakerBall, [.zTea, .platformShake], ["yellow", "teal"]),
            (.longballStadium, .breakerBall, [.webWater, .surfSoda], ["blue", "orange"]),
            (.wreckCenter, .breakerBall, [.phantomFrappe, .galeAle], ["purple", "green"]),
        ]
        for (stage, mode, drinks, colours) in pairs {
            var scene = FootageScene(name: "cpu_\(mode == .fortySeven ? "47" : "breaker")_\(stage)", stage: stage, mode: mode,
                                     colours: colours, drinks: drinks, countdown: 180, maxFrames: 60 * 60 * 6)
            scene.cpuMatch = true
            scenes.append(scene)
        }
        return scenes
    }

    // MARK: Shots

    /// Whether a stage's preset arc can be trusted to drop on its rim: not under the Elements'
    /// ceiling, and not on Longball, which doesn't aim.
    static func presetShoots(_ stage: StageChoice) -> Bool {
        stage != .theElements && stage != .longballStadium && stage != .hoopfishHideaway
    }

    /// Where the first side stands to shoot from `distance` in front of the rim: on Anozira the
    /// car's roof (the rim comes to it on the hoop truck), on the Hideaway a spot the fish swims past.
    static func shootingSpot(_ match: Match, distance: Double) -> (x: Double, y: Double, facing: Facing) {
        if match.stage.features.roadSlides {
            // Off the car's far end: the run up the road to the spot comes first.
            return (match.anoziraCar.x + 70, 30, .right)
        }
        if match.hoopfish != nil { return (120, 10, .right) }
        let rim = match.scoringRim(for: 0) ?? match.stage.hoops.first?.position ?? Vec2(x: match.stage.width / 2, y: 100)
        let side: Facing = rim.x > match.stage.width / 2 ? .right : .left
        let x = min(max(rim.x - side.sign * distance, 20), match.stage.width - 20)
        return (x, floorY(match.stage, x: x), side)
    }

    /// A jump shot from `distance` units in front of the rim, by the first side, with the ball
    /// handed over and the other side parked out of the way; the flick aimed where the preset can't be.
    public static func jumpshot(on stage: StageChoice, distance: Double, colour: String, name: String) -> FootageScene {
        FootageScene(name: name, stage: stage, mode: .fortySeven, colours: [colour, "teal"], maxFrames: 2400, setup: { match in
            let spot = shootingSpot(match, distance: distance)
            match.place(0, at: spot.x, y: spot.y, facing: spot.facing)
            parkOther(&match, awayFrom: spot.x)
            match.takeBall(for: 0)
        }, step: { director, match in
            let me = match.players[0]
            guard let rim = match.scoringRim(for: 0) else { return [.idle, nil] }
            let across = (rim.x - me.position.x) * me.facing.sign
            let rimMoving = match.stage.hoops.first { !$0.rimless && ($0.shared || $0.owner == 0) }?.velocity ?? .zero
            switch director.phase {
            case 0:
                // Facing the rim, and with it in range: a swimming one waited for, crossing toward the shooter.
                let ready = across >= BallRules.autoAimMinimum && across <= BallRules.autoAimRange && (match.hoopfish == nil || rimMoving.x * me.facing.sign <= 0)
                if match.stage.features.roadSlides {
                    // Anozira: the run up the road to the spot, potholes hopped; the road's run gives no
                    // stance, so it's the jump first and the stance in the air.
                    guard director.phaseFrames >= 30 else { return [.idle, nil] }
                    if across <= distance, me.grounded { director.go(to: 10); return [FootageInput.stick(0, jump: true), nil] }
                    return [FootageInput.stick(1, jump: me.grounded && match.potholeAhead(of: 0, within: 40)), nil]
                }
                if director.phaseFrames >= 30, ready, me.grounded, me.state != .catching { director.advance() }
                return [FootageInput.facing(me, x: rim.x), nil]
            case 1:
                // The stance held on the ground a moment, so the windup's over by the top of the jump.
                if me.state == .shootStance, me.stateTimer >= 12 { director.advance() }
                return [FootageInput.stick(0, shoot: true), nil]
            case 2:
                director.advance()
                return [FootageInput.stick(0, jump: true, shoot: true), nil]
            case 3:
                // Let go near the top; the ball leaves five frames on, at the top.
                // The Elements: aimed well over the rim, or the arc out from under the overhang comes in too flat to drop.
                let aim: Vec2 = presetShoots(stage) ? .zero : FootageInput.flickAt(rim, by: me, moving: rimMoving, margin: stage == .theElements ? 6 : 1)
                if me.velocity.y <= 1.2, me.stateTimer >= BallRules.shotWindupFrames, !me.grounded { director.advance() }
                return [FootageInput.stick(0, shoot: true, aim: aim), nil]
            case 10:
                // Anozira: the jump held through the squat, then the stance in the air.
                director.advance(after: 5)
                return [FootageInput.stick(0, jump: true), nil]
            case 11:
                if me.state == .shootStance, me.stateTimer >= BallRules.shotWindupFrames { director.go(to: 4) }
                if director.phaseFrames > 60 { director.finished = true }
                return [FootageInput.stick(0, shoot: true), nil]
            default:
                if director.phaseFrames > 150 { director.finished = true }
                return [.idle, nil]
            }
        }, done: { director, _ in director.finished })
    }

    public static var jumpshots: [FootageScene] {
        var scenes: [FootageScene] = []
        let plans: [(StageChoice, [Double])] = [
            (.wreckCenter, [60, 100, 140]), (.kAndA, [60, 100, 140]), (.anozira, [90, 100, 115]),
            (.hoopfishHideaway, [60, 90]), (.theElements, [96, 105]),
        ]
        for (stageIndex, plan) in plans.enumerated() {
            for (rangeIndex, distance) in plan.1.enumerated() {
                scenes.append(jumpshot(on: plan.0, distance: distance, colour: colours[(stageIndex + rangeIndex) % colours.count],
                                       name: "jumpshot_\(plan.0)_\(Int(distance))"))
            }
        }
        // 130 is past the arc's reach from a wall jump's height.
        scenes.append(longballHelmetShot(fromRim: 120, runFrom: 625, colour: "blue"))
        scenes.append(longballHelmetShot(fromRim: 110, runFrom: 625, colour: "green"))
        scenes.append(longballHelmetShot(fromRim: 90, runFrom: 625, colour: "orange"))
        return scenes
    }

    /// Longball: in from off the screen with the ball, up a helmet coming the other way, the wall jump
    /// off it, the double jump, and the shot on the way. `runFrom` is how far short of the jump the run starts.
    public static func longballHelmetShot(fromRim: Double, runFrom: Double, colour: String) -> FootageScene {
        FootageScene(name: "jumpshot_longball_helmet_\(Int(fromRim))", stage: .longballStadium, mode: .fortySeven, colours: [colour, "yellow"], maxFrames: 3000, setup: { match in
            guard let rim = match.scoringRim(for: 0) else { return }
            let x = max(rim.x - fromRim - runFrom, 30)
            match.place(0, at: x, y: 10, facing: .right)
            parkOther(&match, awayFrom: x)
            match.takeBall(for: 0)
        }, step: { director, match in
            let me = match.players[0]
            guard let rim = match.scoringRim(for: 0) else { return [.idle, nil] }
            let spot = rim.x - fromRim
            func helmetAhead(_ reach: ClosedRange<Double>) -> Bool {
                match.helmets.contains { $0.phase == .travelling && $0.speed < 0 && reach.contains($0.box.min.x - me.position.x) && (15...55).contains($0.box.min.y) }
            }
            switch director.phase {
            case 0:
                director.advance(after: 20)
                return [.idle, nil]
            case 1:
                // The run in; a helmet met on the way taken at a run, one not yet come waited for at the spot.
                if me.position.x >= spot - 70, me.grounded, helmetAhead(30...70) { director.go(to: 2) }
                else if me.position.x >= spot { director.go(to: 10) }
                return [FootageInput.stick(1), nil]
            case 10:
                if helmetAhead(25...55) { director.go(to: 2) }
                return [FootageInput.facing(me, x: rim.x), nil]
            case 2:
                director.advance(after: 6)
                return [FootageInput.stick(1, jump: true), nil]
            case 3:
                // Up toward it, held toward it: the wall land.
                if me.state == .wallLand { director.advance() }
                if director.phaseFrames > 50 { director.go(to: 10) }
                return [FootageInput.stick(1), nil]
            case 4:
                director.advance()
                return [FootageInput.stick(0, jump: true), nil]
            case 5:
                // Off the wall; at the top of that, the double jump.
                if me.state == .air, me.velocity.y <= 0.3, me.stateTimer >= 3 { director.advance(); return [FootageInput.stick(0, jump: true), nil] }
                if director.phaseFrames > 40 { director.go(to: 10) }
                return [.idle, nil]
            case 6:
                // The stance on the way up, let go once the windup's done, flicked at the rim.
                if me.state == .shootStance, me.stateTimer >= BallRules.shotWindupFrames { director.advance() }
                if director.phaseFrames > 60 { director.finished = true }
                return [FootageInput.stick(0, shoot: true, aim: FootageInput.flickAt(rim, by: me)), nil]
            default:
                if director.phaseFrames > 150 { director.finished = true }
                return [.idle, nil]
            }
        }, done: { director, _ in director.finished })
    }

    /// A dunk: the ball in hand, a run at the rim, the jump and the double jump up beside it, and
    /// the throw button held there.
    public static func dunk(on stage: StageChoice, colour: String) -> FootageScene {
        FootageScene(name: "dunk_\(stage)", stage: stage, mode: .fortySeven, colours: [colour, "teal"], maxFrames: 600, setup: { match in
            guard let rim = match.scoringRim(for: 0) else { return }
            let side: Facing = rim.x > match.stage.width / 2 ? .right : .left
            let x = rim.x - side.sign * 90
            match.place(0, at: x, y: floorY(match.stage, x: x), facing: side)
            parkOther(&match, awayFrom: x)
            match.takeBall(for: 0)
        }, step: { director, match in
            let me = match.players[0]
            guard let rim = match.scoringRim(for: 0) else { return [.idle, nil] }
            return dunkSteps(&director, me: me, rim: rim)
        }, done: { director, _ in director.finished })
    }

    /// The dunk's run, jump, double jump and throw at `rim`, from the director's phase 0.
    static func dunkSteps(_ director: inout FootageDirector, me: Player, rim: Vec2) -> [PlayerInput?] {
        let way = rim.x > me.position.x ? 1.0 : -1.0
        // Under the rim's near side, where the hands reach it.
        let under = rim.x - way * 12
        let steer = abs(under - me.position.x) > 4 ? (under > me.position.x ? 1.0 : -1.0) : 0
        switch director.phase {
        case 0:
            director.advance(after: 20)
            return [.idle, nil]
        case 1:
            if abs(rim.x - me.position.x) <= 46 { director.advance() }
            return [FootageInput.stick(way), nil]
        case 2:
            // Jump held through the squat: the full hop.
            director.advance(after: 6)
            return [FootageInput.stick(way, jump: true), nil]
        case 3:
            if me.velocity.y <= 0.3, !me.grounded { director.advance(); return [FootageInput.stick(steer, jump: true), nil] }
            return [FootageInput.stick(steer), nil]
        case 4:
            if me.state == .dunking { director.advance() }
            if director.phaseFrames > 50 { director.finished = true }
            return [FootageInput.stick(steer, throwBall: true), nil]
        default:
            if director.phaseFrames > 120 { director.finished = true }
            return [.idle, nil]
        }
    }

    public static var dunks: [FootageScene] {
        [dunk(on: .wreckCenter, colour: "red"), dunk(on: .theElements, colour: "purple")]
    }

    /// Anozira: the ball carried along the road from the car toward the hoop truck's rim, potholes
    /// hopped on the way, and the dunk, or the floater off the glass, from the road under it.
    public static func anoziraTruck(dunking: Bool, colour: String) -> FootageScene {
        FootageScene(name: dunking ? "dunk_anozira" : "floater_glass_anozira", stage: .anozira, mode: .fortySeven, colours: [colour, "teal"], maxFrames: 2400, setup: { match in
            match.place(0, at: match.anoziraCar.x + 70, y: 30, facing: .right)
            parkOther(&match, awayFrom: 0)
            match.place(1, at: match.anoziraCar.x + 10, y: 30, facing: .right)
            match.takeBall(for: 0)
        }, step: { director, match in
            let me = match.players[0]
            switch director.phase {
            case 0:
                // The truck in with its rim, then down off the car and along the road.
                if match.scoringRim(for: 0) != nil, director.phaseFrames > 30 { director.advance() }
                return [.idle, nil]
            case 1:
                guard let rim = match.scoringRim(for: 0) else { return [.idle, nil] }
                // Running right, potholes hopped, to the spot: the dunk's run-up, or a step off the glass.
                let spot = dunking ? rim.x - 60 : rim.x - 12
                if abs(me.position.x - spot) <= 8, me.grounded {
                    director.go(to: dunking ? 11 : 2)
                    return [FootageInput.stick(dunking ? 1 : 0, jump: !dunking), nil]
                }
                // Past it, the stick let go to come down; landed past it, back.
                if me.position.x > spot { return [FootageInput.stick(me.grounded ? -1 : 0), nil] }
                let hop = me.grounded && match.potholeAhead(of: 0, within: 40)
                return [FootageInput.stick(1, jump: hop), nil]
            case 2:
                // Off the road with a hop, then the floater: up and Guard, held till it goes.
                director.advance(after: 5)
                return [FootageInput.stick(0, jump: true), nil]
            case 3:
                if me.state == .throwing { director.advance() }
                if director.phaseFrames > 40 { director.finished = true }
                return [FootageInput.stick(0, 1, throwBall: true), nil]
            case 4:
                if director.phaseFrames > 150 { director.finished = true }
                return [.idle, nil]
            default:
                guard let rim = match.scoringRim(for: 0) else { return [.idle, nil] }
                var dunk = director
                dunk.phase -= 10
                let inputs = dunkSteps(&dunk, me: me, rim: rim)
                dunk.phase += 10
                director = dunk
                return inputs
            }
        }, done: { director, _ in director.finished })
    }

    /// A floater: the throw stance with up, let go `distance` in front of the rim, off a run from
    /// `runUp` further back, or standing where it starts; up against the backboard it goes off the glass.
    public static func floater(on stage: StageChoice, distance: Double, runUp: Double = 0, jumpFirst: Bool = false, colour: String, name: String) -> FootageScene {
        FootageScene(name: name, stage: stage, mode: .fortySeven, colours: [colour, "teal"], maxFrames: 600, setup: { match in
            guard let rim = match.scoringRim(for: 0) else { return }
            let side: Facing = rim.x > match.stage.width / 2 ? .right : .left
            let x = rim.x - side.sign * (distance + runUp)
            match.place(0, at: x, y: floorY(match.stage, x: x), facing: side)
            parkOther(&match, awayFrom: x)
            match.takeBall(for: 0)
        }, step: { director, match in
            let me = match.players[0]
            guard let rim = match.scoringRim(for: 0) else { return [.idle, nil] }
            let way = rim.x > me.position.x ? 1.0 : -1.0
            switch director.phase {
            case 0:
                if director.phaseFrames >= 30, abs(rim.x - me.position.x) <= distance { director.advance(); if jumpFirst { director.go(to: 10) } }
                return [director.phaseFrames >= 30 && runUp > 0 ? FootageInput.stick(way) : FootageInput.facing(me, x: rim.x), nil]
            case 1:
                if me.state == .throwing || me.state == .shooting { director.advance() }
                if director.phaseFrames > 40 { director.finished = true }
                return [FootageInput.stick(0, 1, throwBall: true), nil]
            case 10:
                // A rim too high for the layup's hop: the full hop first, the layup at the top of it.
                director.advance(after: 6)
                return [FootageInput.stick(0, jump: true), nil]
            case 11:
                if me.velocity.y <= 0.3, !me.grounded { director.go(to: 1) }
                if director.phaseFrames > 40 { director.finished = true }
                return [.idle, nil]
            default:
                if director.phaseFrames > 150 { director.finished = true }
                return [.idle, nil]
            }
        }, done: { director, _ in director.finished })
    }

    public static var floaters: [FootageScene] {
        [floater(on: .wreckCenter, distance: 18, runUp: 50, colour: "blue", name: "floater_wreckCenter"),
         floater(on: .wreckCenter, distance: 8, colour: "pink", name: "floater_glass_wreckCenter"),
         floater(on: .kAndA, distance: 18, runUp: 50, jumpFirst: true, colour: "orange", name: "floater_kAndA"),
         floater(on: .theElements, distance: 15, colour: "yellow", name: "floater_theElements"),
         floater(on: .theElements, distance: 8, colour: "green", name: "floater_glass_theElements"),
         anoziraTruck(dunking: false, colour: "red")]
    }

    // MARK: Z Tea

    /// Breaker Ball on Anozira under a clear sky, both up on the cars: the first side's beam from
    /// the left car, wiggled after the other as they run and jump about the right one, worn down to the Break.
    static var beamBreak: FootageScene {
        FootageScene(name: "beam_break_anozira", stage: .anozira, mode: .breakerBall, colours: ["yellow", "teal"], drinks: [.zTea, nil], rain: 0, maxFrames: 1800, setup: { match in
            match.place(0, at: match.anoziraCar.x + 35, y: 40, facing: .right)
            match.place(1, at: match.anoziraSecondCar.x + 35, y: 40, facing: .left)
            // Worn already, so the beam's hits finish it.
            if match.posture.count > 1 { match.posture[1] = 10 }
        }, step: { director, match in
            let me = match.players[0], them = match.players[1]
            // The other shuffles and hops about their car's roof, never off it, at no set beat: each
            // stretch its own length, way and hop.
            let roofCentre = match.anoziraSecondCar.x + 35
            let drift = them.position.x - roofCentre
            if Double(director.frames) >= director.notes["stretchUntil", default: 0] {
                let roll = AnoziraRules.mixed(director.frames, salt: 0xB3A1)
                director.notes["stretchUntil"] = Double(director.frames + 14 + Int(roll % 36))
                director.notes["stretchWay"] = [-0.7, -0.4, 0, 0.3, 0.6][Int(roll / 7 % 5)]
                director.notes["hopAt"] = roll / 41 % 3 == 0 ? Double(director.frames + Int(roll / 13 % 10)) : -100
            }
            var theirs = PlayerInput.idle
            theirs.stick = Vec2(x: drift > 12 ? -0.7 : (drift < -12 ? 0.7 : director.notes["stretchWay", default: 0]), y: 0)
            let hopAt = Int(director.notes["hopAt", default: -100])
            theirs.jump = director.frames >= hopAt && director.frames < hopAt + 6
            switch director.phase {
            case 0:
                // Hands empty first: the Breaker Ball thrown away, the throw held a moment and let go.
                director.advance(after: 20)
                return [.idle, theirs]
            case 1:
                director.advance(after: 14)
                return [FootageInput.stick(1, throwBall: true), theirs]
            case 2:
                if !me.hasBall, me.state != .throwing { director.advance(after: 30) }
                return [.idle, theirs]
            case 3:
                // Down and Strike: the charge.
                if me.state == .beamCharging { director.advance() }
                if director.phaseFrames > 30 { director.go(to: 2) }
                return [FootageInput.stick(0, -1, shoot: true), theirs]
            case 4:
                if me.state != .beamCharging, director.phaseFrames > 5 { director.advance() }
                return [.idle, theirs]
            case 5:
                // Down and Strike again: the stored charge fired.
                if me.state == .beamFiring { director.advance() }
                if director.phaseFrames > 30 { director.go(to: 3) }
                return [FootageInput.stick(0, -1, shoot: true), theirs]
            case 6:
                // Held on at their general height, slow to follow their hops, wagged a little either way
                // at no set beat.
                if me.state != .beamFiring { director.advance() }
                let height = director.notes["height", default: them.chest.y] * 0.94 + them.chest.y * 0.06
                director.notes["height"] = height
                if Double(director.frames) >= director.notes["wagUntil", default: 0] {
                    let roll = AnoziraRules.mixed(director.frames, salt: 0x5EA7)
                    director.notes["wagUntil"] = Double(director.frames + 6 + Int(roll % 16))
                    director.notes["wag"] = Double(Int(roll / 17 % 11) - 5) * Double.pi / 180
                }
                let toThem = Vec2(x: them.chest.x, y: height) - me.shotReleasePoint
                let angle = atan2(toThem.y, abs(toThem.x)) + director.notes["wag", default: 0]
                let aim = Vec2(x: cos(angle) * me.facing.sign, y: sin(angle))
                return [PlayerInput(stick: aim), theirs]
            default:
                if match.postureBroken.indices.contains(1), match.postureBroken[1] { director.notes["broken"] = 1 }
                if director.phaseFrames > 90 {
                    if director.notes["broken"] == 1 || director.frames > 1600 { director.finished = true } else { director.go(to: 3) }
                }
                return [.idle, theirs]
            }
        }, done: { director, _ in director.finished })
    }

    /// Z Tea's blasts, one after another, aimed after the other as they jump away.
    static var blasts: FootageScene {
        FootageScene(name: "blasts_wreckCenter", stage: .wreckCenter, colours: ["purple", "orange"], drinks: [.zTea, nil], maxFrames: 900, setup: { match in
            match.place(0, at: 90, y: 10, facing: .right)
            match.place(1, at: 200, y: 10, facing: .left)
        }, eachFrame: { $0.parkBall() }, step: { director, match in
            let me = match.players[0], them = match.players[1]
            let theirs: PlayerInput? = nil
            if director.frames > 60 * 11 { director.finished = true }
            if director.frames < 30 { return [.idle, theirs] }
            // Up and Strike fires one; between them the stick points the next at them.
            let toThem = them.chest - me.chest
            let angle = max(min(atan2(toThem.y, abs(toThem.x)), ZRules.aimRange), -ZRules.aimRange)
            let aim = Vec2(x: cos(angle) * (toThem.x > 0 ? 1 : -1), y: sin(angle))
            let firing = director.frames % 24 < 4
            return [firing ? FootageInput.stick(aim.x * 0.2, 1, shoot: true) : PlayerInput(stick: aim), theirs]
        }, done: { director, _ in director.finished })
    }

    // MARK: Web Water, Super Smoothie

    /// The Elements: a swing across the middle, left to right, then back right to left, the spin
    /// carrying on after.
    static var elementsSwing: FootageScene {
        FootageScene(name: "web_swing_theElements", stage: .theElements, colours: ["blue", "red"], drinks: [.webWater, nil], maxFrames: 900, setup: { match in
            match.place(0, at: 180, y: 150, facing: .right)
            match.place(1, at: 600, y: 100, facing: .left)
        }, eachFrame: { $0.parkBall() }, step: { director, match in
            let me = match.players[0]
            switch director.phase {
            case 0:
                director.advance(after: 20)
                return [.idle, nil]
            case 1:
                // The walk to the edge, the jump off it, and the swing once clear of the platform.
                if me.position.x >= 230 { director.advance() }
                return [FootageInput.stick(0.7), nil]
            case 2:
                director.advance(after: 5)
                return [FootageInput.stick(1, jump: true), nil]
            case 3:
                if me.state == .air, me.stateTimer >= 3, me.position.x >= 246 { director.advance() }
                return [FootageInput.stick(1), nil]
            case 4:
                if me.state == .webSwing { director.advance() }
                return [FootageInput.stick(1, jump: true), nil]
            case 5:
                if me.state != .webSwing { director.advance() }
                return [FootageInput.stick(1, jump: true), nil]
            case 6:
                // Down on the far side, turned round, and back the other way.
                if me.grounded, director.phaseFrames > 10 { director.advance() }
                return [FootageInput.stick(1), nil]
            case 7:
                director.advance(after: 30)
                return [.idle, nil]
            case 8:
                if me.position.x <= 440 { director.advance() }
                return [FootageInput.stick(-0.7), nil]
            case 9:
                director.advance(after: 5)
                return [FootageInput.stick(-1, jump: true), nil]
            case 10:
                if me.state == .air, me.stateTimer >= 3, me.position.x <= 424 { director.advance() }
                return [FootageInput.stick(-1), nil]
            case 11:
                if me.state == .webSwing { director.advance() }
                return [FootageInput.stick(-1, jump: true), nil]
            case 12:
                if me.state != .webSwing { director.advance() }
                return [FootageInput.stick(-1, jump: true), nil]
            default:
                // The spin out of the swing, drifting on.
                if director.phaseFrames > 120 { director.finished = true }
                return [FootageInput.stick(-1), nil]
            }
        }, done: { director, _ in director.finished })
    }

    /// Super Smoothie on defence: the other's shot comes in, the Super Jump up, a circle in the
    /// air, then after the ball and the slash that smacks it away.
    static var smoothieDefence: FootageScene {
        FootageScene(name: "smoothie_defence_wreckCenter", stage: .wreckCenter, colours: ["green", "pink"], drinks: [.superSmoothie, nil], maxFrames: 900, setup: { match in
            match.place(0, at: 100, y: 10, facing: .right)
            match.place(1, at: 190, y: 10, facing: .left)
            match.takeBall(for: 1)
        }, step: { director, match in
            let me = match.players[0], them = match.players[1]
            var theirs: PlayerInput? = director.frames < 30 ? .idle : nil
            // Their jump shot at the rim behind the first side, once the clock's run a moment; the computer's after.
            if director.frames >= 30, director.frames < 34 { theirs = FootageInput.stick(0, shoot: true) }
            if director.frames >= 34, them.state == .shootStance { theirs = FootageInput.stick(0, jump: director.frames < 38, shoot: them.velocity.y > 0.3 || them.stateTimer < BallRules.shotWindupFrames) }
            let ball = match.ball
            let loose = ball.holder == nil && them.state != .shootStance && director.frames > 40
            switch director.phase {
            case 0:
                if director.frames >= 20 { director.advance() }
                return [.idle, theirs]
            case 1:
                // Up and jump: the Super Jump into flight.
                if me.state == .flying { director.advance() }
                return [FootageInput.stick(0, 1, jump: true), theirs]
            case 2:
                // The circle: the stick round once, jump held; then after the ball.
                let turn = Double(director.phaseFrames) / 45 * 2 * Double.pi
                if director.phaseFrames >= 45, loose { director.advance() }
                return [FootageInput.stick(cos(turn), sin(turn), jump: true), theirs]
            case 3:
                // Toward where the ball's about to be; the slash as it comes within reach.
                let ahead = ball.position + ball.velocity * 6
                let toBall = ahead - me.chest
                if ball.position.distance(to: me.chest) < 16 || toBall.length < 10 { director.advance(); return [FootageInput.stick(toBall.x > 0 ? 1 : -1, 0, jump: true, shoot: true), theirs] }
                if director.phaseFrames > 120 { director.finished = true }
                let way = toBall.length > 0 ? toBall * (1 / toBall.length) : Vec2.zero
                return [FootageInput.stick(way.x, way.y, jump: true), theirs]
            default:
                // Away upward after the swat, then down.
                if director.phaseFrames > 70 { director.finished = true }
                return [director.phaseFrames < 30 ? FootageInput.stick(me.facing.sign * 0.5, 1, jump: true) : .idle, theirs]
            }
        }, done: { director, _ in director.finished })
    }

    // MARK: Modes

    /// The flick that puts a shot in from a stance being held now, found by playing the shot out on
    /// a copy of the match for each angle from `angles`, the nearest to `preferred` first, the other
    /// side standing still; nil if none goes in. Where gravity leans (Flight B411's pitch) or the
    /// rim moves, the arc can't be worked out, only tried.
    public static func searchedFlick(_ match: Match, shooter: Int, toward: Facing, preferred: Double = 0.95,
                                     angles: ClosedRange<Double> = 0.35...1.45, step: Double = 0.01,
                                     other: (Match, Int) -> PlayerInput = { _, _ in .idle }) -> Vec2? {
        let count = Int(((angles.upperBound - angles.lowerBound) / step).rounded())
        let tried = (0...count).map { angles.lowerBound + Double($0) * step }.sorted { abs($0 - preferred) < abs($1 - preferred) }
        for angle in tried {
            let aim = FootageInput.flick(angle, facing: toward)
            if shotGoesIn(match, shooter: shooter, aim: aim, other: other) { return aim }
        }
        return nil
    }

    /// Whether the stance being held now, flicked `aim` and let go once its windup's done, scores;
    /// the other side playing `other` (given the match and the frames on).
    public static func shotGoesIn(_ match: Match, shooter: Int, aim: Vec2, frames: Int = 180,
                                  other: (Match, Int) -> PlayerInput = { _, _ in .idle }) -> Bool {
        var copy = match
        for frame in 0..<frames {
            let me = copy.players[shooter]
            let holding = me.state == .shootStance && me.stateTimer < BallRules.shotWindupFrames
            var inputs = [other(copy, frame), other(copy, frame)]
            inputs[shooter] = FootageInput.stick(0, shoot: holding, aim: aim)
            copy.advance(inputs: inputs)
            for event in copy.events {
                if case let .scored(player, _, _, _, _, _) = event { return player == shooter }
            }
        }
        return false
    }

    /// Whether a layup, the throw with `stick` held from now till it's away, scores for `thrower`;
    /// with `offGlass`, only off the backboard's glass on the way in.
    public static func layupGoesIn(_ match: Match, thrower: Int, stick: Vec2, offGlass: Bool = false, frames: Int = 150) -> Bool {
        var copy = match
        var away = false
        var kissed = false
        for _ in 0..<frames {
            let me = copy.players[thrower]
            if me.state == .throwing || me.state == .shooting { away = true }
            var inputs = [PlayerInput.idle, PlayerInput.idle]
            inputs[thrower] = away ? .idle : FootageInput.stick(stick.x, stick.y, throwBall: true)
            copy.advance(inputs: inputs)
            for event in copy.events {
                if case let .ballBounced(position, _) = event, copy.stage.backboard(at: position) != nil { kissed = true }
                if case let .scored(player, _, _, _, _, _) = event { return player == thrower && (!offGlass || kissed) }
            }
        }
        return false
    }

    /// Rounds on Flight B411: the plane leans, an empty bin and then a hoopcase out of another, the
    /// second side's shot through it over the first side's guarding, and the first, scored on, on
    /// the drink pick: the cursor along the bottles and back, and one drunk.
    public static var roundsFlight: FootageScene {
        var scene = FootageScene(name: "mode_rounds_flightB411", stage: .flightB411, mode: .rounds, colours: ["orange", "blue"], maxFrames: 1500, setup: { match in
            match.place(0, at: 40, y: 20, facing: .right)
            match.place(1, at: 150, y: 20, facing: .left)
            match.takeBall(for: 1)
            // The level spell after the count done: the pitch and the bins from the first frame.
            match.flightRoundStart = match.frame - match.countdownLength - FlightB411Rules.startLevelFrames
            match.tiltFrom = 0
            match.tiltTarget = flightLean * FlightB411Rules.tiltMax
            match.tiltClock = 1
            // The ball's bin open and empty a moment, so the next is the hoop's.
            match.ballBin = nil
            for index in match.bins.indices { match.bins[index] = Bin() }
            match.bins[FlightB411Rules.centreBin].open = true
            match.bins[FlightB411Rules.centreBin].framesLeft = flightEmptyBinFrames
            match.lastBin = FlightB411Rules.centreBin
            match.emptyRun = FlightB411Rules.emptyRunMost
        }, step: { director, match in
            let me = match.players[1]
            let rim = match.bins.firstIndex(where: \.hoopLive).map { FlightB411Rules.rimSpot(in: $0) }
            switch director.phase {
            case 0:
                // Holding on to it while the plane leans and the case comes out.
                if rim != nil, me.grounded { director.advance() }
                return [nil, .idle]
            case 1:
                guard let rim else { director.go(to: 0); return [nil, .idle] }
                // To a spot a shot's length from under the rim, on the side it's on, facing it.
                let side = me.position.x > rim.x ? 1.0 : -1.0
                let spot = min(max(rim.x + side * flightShotDistance, 12), FlightB411Rules.width - 12)
                if abs(me.position.x - spot) <= 4, me.grounded { director.advance(); return [nil, FootageInput.facing(me, x: rim.x)] }
                if director.phaseFrames > 120 { director.advance() }
                return [nil, FootageInput.toward(me, x: spot)]
            case 2:
                guard let rim else { director.go(to: 0); return [nil, .idle] }
                // The stance; once it's up, the flick that goes in, found on a copy of the match.
                if me.state == .shootStance, director.notes["aimX"] == nil {
                    let toward: Facing = rim.x > me.position.x ? .right : .left
                    if let aim = searchedFlick(match, shooter: 1, toward: toward) {
                        director.notes["aimX"] = aim.x
                        director.notes["aimY"] = aim.y
                    } else {
                        director.notes["aimX"] = 0
                        director.notes["aimY"] = 0
                    }
                }
                let aim = Vec2(x: director.notes["aimX"] ?? 0, y: director.notes["aimY"] ?? 0)
                if me.state == .shooting { director.advance() }
                let holding = me.state != .shootStance || me.stateTimer < BallRules.shotWindupFrames
                return [nil, FootageInput.stick(0, shoot: holding, aim: aim)]
            default:
                return [nil, nil]
            }
        })
        scene.pickMoves = [1, 1, -1]
        return scene
    }

    /// 47 on K&A: footsies, both sides the computer's, till the first side's air slash knocks the
    /// ball out of the second's hands; then played out: the catch, a three over the second side's
    /// run to contest it, the second snatching it under the net, the run the other way, the Spin
    /// Move through the first side's slash, the layup off the glass out of the spin, still in the
    /// air; the computer's again after, so it plays on to the cut.
    public static var fortySevenKAndA: FootageScene {
        var scene = FootageScene(name: "mode_47_kAndA", stage: .kAndA, mode: .fortySeven, colours: ["orange", "teal"], maxFrames: 1500, setup: { match in
            let y = floorY(match.stage, x: 190)
            match.place(0, at: 225, y: y, facing: .left)
            match.place(1, at: 150, y: y, facing: .right)
            match.takeBall(for: 1)
        }, step: { director, match in
            let first = match.players[0], second = match.players[1]
            let gap = first.position.x - second.position.x
            let scoredNow = match.events.contains { if case .scored = $0 { return true } else { return false } }
            if scoredNow { director.notes["scored"] = Double(director.frames) }
            switch director.phase {
            case 0:
                // Footsies, both sides the computer's, till the first side's air slash pops the ball loose.
                let stripped = match.events.contains { if case .popped(1, 0) = $0 { return true } else { return false } }
                if stripped, !first.grounded { director.go(to: 2) }
                return [nil, nil]
            case 2:
                // The ball comes down to the slasher, caught; the second side after it too, too late.
                if first.hasBall, first.grounded { director.advance() }
                if director.phaseFrames > 120 { director.go(to: 20) }
                let firstInput = first.hasBall || first.state == .slashing || first.state == .rolling ? PlayerInput.idle : FootageInput.toward(first, x: match.ball.position.x, slack: 2)
                return [firstInput, second.grounded ? FootageInput.toward(second, x: match.ball.position.x, slack: 2) : nil]
            case 3:
                // Out toward the rim at a run, a frame's let go first so it's a dash, to well outside
                // the line; the stance. The dribble faces the other side; the stance turns with the stick.
                if first.state == .catching { director.notes["caughtAt"] = Double(director.phaseFrames) }
                if Double(director.phaseFrames) - (director.notes["caughtAt"] ?? 0) <= 2 { return [.idle, chaseToContest(&director, second, first)] }
                if first.position.x >= fortySevenShotX, first.grounded {
                    if first.state == .shootStance, first.facing == .right { director.advance() }
                    return [FootageInput.stick(0.6, shoot: true), chaseToContest(&director, second, first)]
                }
                return [FootageInput.stick(1), chaseToContest(&director, second, first)]
            case 4:
                if first.stateTimer >= 12 { director.advance(); return [FootageInput.stick(0.6, jump: true, shoot: true), chaseToContest(&director, second, first)] }
                return [FootageInput.stick(0.6, shoot: true), chaseToContest(&director, second, first)]
            case 5:
                // Let go near the top, flicked where it goes in over the contest.
                if first.velocity.y <= 1.2, first.stateTimer >= BallRules.shotWindupFrames, !first.grounded {
                    director.advance()
                    let start = director
                    var copyDirector = start
                    let aim = searchedFlick(match, shooter: 0, toward: .right, preferred: 0.8) { copy, frame in
                        if frame == 0 { copyDirector = start }
                        return chaseToContest(&copyDirector, copy.players[1], copy.players[0])
                    } ?? .zero
                    director.notes["aimX"] = aim.x
                    director.notes["aimY"] = aim.y
                    return [FootageInput.stick(0, aim: aim), chaseToContest(&director, second, first)]
                }
                return [FootageInput.stick(0.6, shoot: true), chaseToContest(&director, second, first)]
            case 6:
                // The contest, then under the net for the ball as it drops through; the shooter,
                // down, back the other way.
                if director.notes["scored"] != nil { director.advance() }
                if director.phaseFrames > 150 { director.go(to: 20) }
                let firstInput = first.grounded && first.state != .shooting ? FootageInput.toward(first, x: fortySevenCutOff) : PlayerInput.idle
                return [firstInput, chaseToContest(&director, second, first)]
            case 7:
                // The snatch as the ball comes within reach.
                let ball = match.ball.position
                let near = abs(ball.x - second.position.x) < fortySevenSnatchReach && ball.y < second.position.y + 30
                if second.hasBall { director.advance() }
                if director.phaseFrames > 120 { director.go(to: 20) }
                return [FootageInput.toward(first, x: fortySevenCutOff), near && second.state != .snatching ? FootageInput.stick(0, throwBall: true) : FootageInput.toward(second, x: ball.x, slack: 2)]
            case 8:
                // The run the other way, a frame's let go first so it's a dash; the first side out to
                // cut it off, facing it. Into a jump at the rim.
                let firstInput = abs(first.position.x - fortySevenCutOff) > 3 ? FootageInput.toward(first, x: fortySevenCutOff) : FootageInput.facing(first, x: second.position.x)
                if second.state == .catching { director.notes["caughtAt"] = Double(director.phaseFrames) }
                if Double(director.phaseFrames) - (director.notes["caughtAt"] ?? 0) <= 2 { return [firstInput, .idle] }
                if abs(gap) <= fortySevenDriveJumpGap, second.grounded { director.advance(); return [firstInput, FootageInput.stick(-1, jump: true)] }
                return [firstInput, FootageInput.stick(-1)]
            case 9:
                // Up at it, the first side's jump and slash; the second's Spin Move, its down throw, as they close.
                let firstInput = first.grounded && abs(gap) <= fortySevenCutJumpGap ? FootageInput.stick(0.4, jump: true)
                    : first.grounded ? FootageInput.facing(first, x: second.position.x) : .idle
                if abs(gap) <= fortySevenSpinGap, !second.grounded { director.advance(); return [firstInput, FootageInput.stick(0, -1, throwBall: true)] }
                if second.grounded, director.phaseFrames > 6 { director.go(to: 20) }
                return [firstInput, FootageInput.stick(-1, jump: true)]
            case 10:
                // Let go with down still held: the spin, steered on toward the rim.
                // Held with down as it goes in the air, the spin at once; the slash swung into it, passing through.
                if second.state == .spinning { director.advance() }
                if director.phaseFrames > 10 { director.go(to: 20) }
                let swing = director.phaseFrames == 0 && !first.grounded
                return [swing ? FootageInput.stick(0.4, shoot: true) : .idle, FootageInput.stick(0, -1, throwBall: true)]
            case 11:
                // Out of the spin, still in the air: the layup the moment one would go in, off the glass.
                if second.state != .spinning {
                    if second.grounded { director.go(to: 20); return [.idle, .idle] }
                    // The one that comes down clear of the first side, not on top of them.
                    for across in [0.5, 0.25, 0.75, 0, -0.5] {
                        let stick = Vec2(x: across, y: 1)
                        guard layupGoesIn(match, thrower: 1, stick: stick, offGlass: true),
                              let landing = layupLanding(match, thrower: 1, stick: stick),
                              abs(landing - first.position.x) >= fortySevenLandingClear else { continue }
                        director.notes["layupX"] = across
                        director.notes["landing"] = landing
                        director.advance()
                        return [.idle, FootageInput.stick(across, 1, throwBall: true)]
                    }
                    return [.idle, FootageInput.stick(-1)]
                }
                // Through the spin, carried on, then braked so it comes out just short of the rim.
                let rimX = match.scoringRim(for: 1)?.x ?? 35
                return [.idle, FootageInput.stick(abs(second.position.x - rimX) > fortySevenSpinBrakeFrom ? -1 : 0)]
            case 12:
                // The layup held till it's away; the first side, down, back toward the play, short of
                // where the layup comes down.
                let across = director.notes["layupX"] ?? 0
                // Let go the frame it's away, as the copies tried it.
                if second.state == .throwing || second.state == .shooting {
                    director.notes["awayAt"] = Double(director.frames)
                    director.advance()
                    return [backToThePlay(&director, first, second), .idle]
                }
                if director.phaseFrames > 40 { director.go(to: 20) }
                return [backToThePlay(&director, first, second), FootageInput.stick(across, 1, throwBall: true)]
            case 13:
                if (director.notes["scored"] ?? 0) >= (director.notes["awayAt"] ?? .infinity) || director.phaseFrames > 120 { director.go(to: 20) }
                return [backToThePlay(&director, first, second), .idle]
            default:
                // Both the computer's again, the game carrying on to the cut.
                if director.phaseFrames > fortySevenPlayOnFrames { director.finished = true }
                return [nil, nil]
            }
        }, done: { director, _ in director.finished })
        scene.seeds = fortySevenSeeds
        return scene
    }

    /// The seeds the footsies run on, the computer's, proved headlessly to end in the air slash's strip.
    static let fortySevenSeeds: [UInt32] = [15, 5]
    static let fortySevenLandingClear = 30.0
    static let fortySevenPlayOnFrames = 90
    static let fortySevenContestJumpGap = 40.0
    static let fortySevenContestLean = 0.4
    static let fortySevenUnderRim = 326.0
    static let fortySevenShotX = 240.0
    static let fortySevenSnatchReach = 16.0
    static let fortySevenCutOff = 80.0
    static let fortySevenDriveJumpGap = 75.0
    static let fortySevenCutJumpGap = 50.0
    static let fortySevenCutSlashGap = 30.0
    static let fortySevenSpinGap = 34.0
    static let fortySevenSpinBrakeFrom = 46.0

    /// Running at the shooter flat out, one way, and up at them once they're rising to shoot;
    /// committed, carried on through the jump, then under the net for the ball once down.
    static func chaseToContest(_ director: inout FootageDirector, _ me: Player, _ shooter: Player) -> PlayerInput {
        if let way = director.notes["contestWay"] {
            if me.grounded, director.notes["contestUp"] != nil {
                // Down: let go till the landing's over, so the run under the net starts as a dash;
                // there, stopped, not pacing about the spot.
                if director.notes["contestDown"] == nil {
                    if me.state != .land { director.notes["contestDown"] = 1 }
                    return .idle
                }
                let toRim = fortySevenUnderRim - me.position.x
                if director.notes["underRim"] != nil || abs(toRim) <= 4 { director.notes["underRim"] = 1; return .idle }
                return FootageInput.stick(toRim > 0 ? 1 : -1)
            }
            if !me.grounded { director.notes["contestUp"] = 1 }
            return FootageInput.stick(way)
        }
        let way = shooter.position.x > me.position.x ? 1.0 : -1.0
        let gap = abs(shooter.position.x - me.position.x)
        // Walking in while they gather the catch; once they're off, a frame's let go so the chase is a dash.
        guard let chaseWay = director.notes["chaseWay"] else {
            if shooter.state == .catching { return FootageInput.stick(way * 0.5) }
            director.notes["chaseWay"] = way
            return .idle
        }
        if gap <= fortySevenContestJumpGap {
            // Up with them as they rise, leaning in, close as they are; till then pulled up beside them.
            if !shooter.grounded, me.grounded {
                director.notes["contestWay"] = way * fortySevenContestLean
                return FootageInput.stick(director.notes["contestWay"] ?? way, jump: true)
            }
            if shooter.state == .shootStance || chaseWay != way { return FootageInput.facing(me, x: shooter.position.x) }
        }
        return FootageInput.stick(chaseWay)
    }

    /// Back toward the play, down from the slash, stopping short of where the layup comes down
    /// and of the layup itself on the way, never pushing through it.
    static func backToThePlay(_ director: inout FootageDirector, _ me: Player, _ layup: Player) -> PlayerInput {
        guard me.grounded, me.state != .slashing, me.state != .rolling, let landing = director.notes["landing"] else { return .idle }
        if director.notes["backAtPlay"] != nil { return FootageInput.facing(me, x: layup.position.x) }
        let side = me.position.x > landing ? 1.0 : -1.0
        let nearest = side > 0 ? max(landing, layup.position.x) : min(landing, layup.position.x)
        let stop = nearest + fortySevenLandingClear * side
        if (me.position.x - stop) * side <= 0 { director.notes["backAtPlay"] = 1; return FootageInput.facing(me, x: layup.position.x) }
        return FootageInput.stick(-side)
    }

    /// Where `thrower` comes down after the layup with `stick` held till it's away.
    public static func layupLanding(_ match: Match, thrower: Int, stick: Vec2, frames: Int = 150) -> Double? {
        var copy = match
        var away = false
        for _ in 0..<frames {
            let me = copy.players[thrower]
            if me.state == .throwing || me.state == .shooting { away = true }
            if away, me.grounded { return me.position.x }
            var inputs = [PlayerInput.idle, PlayerInput.idle]
            inputs[thrower] = away ? .idle : FootageInput.stick(stick.x, stick.y, throwBall: true)
            copy.advance(inputs: inputs)
        }
        return nil
    }

    /// Flight B411's lean for the Rounds scene, a share of the most; under the slide's.
    static let flightLean = 0.5
    static let flightEmptyBinFrames = 100
    static let flightShotDistance = 45.0

    // MARK: Clips

    /// Wreck Center, teal against orange, the first look at a game. Teal walks the ball back and
    /// forth once, taunts twice, walks in and double jumps into a three, orange working at it the
    /// while with short hopped aerial slashes and snatches from just out of reach, falling back
    /// between, and a shieldflip as the shot goes that misses it. Orange takes the ball the length
    /// of the court for a dunk over teal's whiffed slashes; teal's slash lands as orange comes down,
    /// and teal takes the ball the other way. Orange runs teal down and its slash pops the ball,
    /// caught; teal snatches it back, jumps, spins and lays a floater in off the glass. Then both
    /// the computer's.
    public static var tauntThreeWreckCenter: FootageScene {
        var scene = FootageScene(name: "clip_tauntThree_wreckCenter", stage: .wreckCenter, mode: .fortySeven, colours: ["teal", "orange"], maxFrames: 2400, setup: { match in
            let y = floorY(match.stage, x: tauntThreeTealStart)
            match.place(0, at: tauntThreeTealStart, y: y, facing: .right)
            match.place(1, at: tauntThreeOrangeStart, y: y, facing: .left)
            match.takeBall(for: 0)
        }, step: { director, match in
            let teal = match.players[0], orange = match.players[1]
            guard let tealRim = match.scoringRim(for: 0), let orangeRim = match.scoringRim(for: 1) else { return [nil, nil] }
            func happened(_ test: (MatchEvent) -> Bool) -> Bool { match.events.contains(where: test) }
            let busy: Set<PlayerState> = [.land, .jumpSquat, .slashing, .rolling, .snatching, .catching, .throwStance, .throwing, .dunking,
                                          .shootStance, .shooting, .flipJump, .tumbling, .spinning]
            let free = { (player: Player) in player.grounded && !busy.contains(player.state) && player.hitStun == 0 }
            let toBall = { (player: Player) -> PlayerInput in FootageInput.toward(player, x: match.ball.position.x, slack: 1) }
            switch director.phase {
            case 0:
                // The walk, slow, toward orange first so the body never turns from them; turned at the
                // far end without a let go, so it stays a walk facing them.
                var leg = Int(director.notes["tLeg"] ?? 0)
                let way = leg == 0 ? 1.0 : -1.0
                if (way > 0 && teal.position.x >= tauntThreeWalkEnds.upperBound) || (way < 0 && teal.position.x <= tauntThreeWalkEnds.lowerBound) {
                    leg += 1
                    director.notes["tLeg"] = Double(leg)
                }
                if leg >= 2 { director.advance(); return [.idle, tauntThreeHarass(&director, orange, teal)] }
                return [FootageInput.stick((leg == 0 ? 1.0 : -1.0) * tauntThreeWalkStick), tauntThreeHarass(&director, orange, teal)]
            case 1:
                // Stopped dead first, then two taunts back to back, each played out.
                let orangeInput = tauntThreeHarass(&director, orange, teal)
                if director.notes["tTaunts"] == nil {
                    guard teal.state == .idle, abs(teal.velocity.x) < 0.01 else { return [.idle, orangeInput] }
                    director.notes["tTaunts"] = 0
                }
                let taunts = Int(director.notes["tTaunts"] ?? 0)
                if teal.state == .taunt { director.notes["tTaunting"] = 1; return [.idle, orangeInput] }
                if director.notes["tTaunting"] != nil {
                    director.notes["tTaunting"] = nil
                    director.notes["tTaunts"] = Double(taunts + 1)
                    if taunts + 1 >= 2 { director.advance() }
                    return [.idle, orangeInput]
                }
                return [PlayerInput(taunt: !teal.lastInput.taunt), orangeInput]
            case 2:
                // The walk in; orange settles in front, waiting on it. Then the jump, held for the full hop.
                let orangeInput = tauntThreeContest(&director, orange, teal)
                if teal.position.x >= tauntThreeJumpAt { director.advance(); return [FootageInput.stick(0, jump: true), orangeInput] }
                return [FootageInput.stick(tauntThreeWalkInStick), orangeInput]
            case 3:
                // Up; near the top, jump let go a frame and pressed again: the double jump.
                let orangeInput = tauntThreeContest(&director, orange, teal)
                if teal.grounded { return [FootageInput.stick(0, jump: true), orangeInput] }
                if teal.velocity.y <= tauntThreeDoubleJumpAt {
                    if director.notes["jumpLetGo"] == nil { director.notes["jumpLetGo"] = 1; return [.idle, orangeInput] }
                    director.advance()
                    return [FootageInput.stick(0, jump: true), orangeInput]
                }
                return [FootageInput.stick(0, jump: true), orangeInput]
            case 4:
                // Into the stance on the double jump's way up.
                let orangeInput = tauntThreeContest(&director, orange, teal)
                if teal.state == .shootStance { director.advance() }
                return [FootageInput.stick(0, shoot: true), orangeInput]
            case 5:
                // Let go near the top, flicked where it goes in past orange's shieldflip, raised a frame after.
                let orangeInput = tauntThreeContest(&director, orange, teal)
                if teal.velocity.y <= tauntThreeReleaseAt, teal.stateTimer >= BallRules.shotWindupFrames {
                    director.advance()
                    let aim = searchedFlick(match, shooter: 0, toward: .right, preferred: 0.8) { copy, _ in
                        PlayerInput(shield: copy.events.contains { if case .shot(0) = $0 { return true } else { return false } })
                    } ?? .zero
                    director.notes["aimX"] = aim.x
                    director.notes["aimY"] = aim.y
                    return [FootageInput.stick(0, aim: aim), orangeInput]
                }
                return [FootageInput.stick(0, shoot: true), orangeInput]
            case 6:
                // The shieldflip, a frame after the shot's away; then both wait on it.
                let shield = happened { if case .shot(0) = $0 { return true } else { return false } }
                if happened({ if case .scored(0, _, _, _, _, _) = $0 { return true } else { return false } }) { director.advance() }
                if director.phaseFrames > 200 { director.finished = true }
                return [teal.grounded ? FootageInput.facing(teal, x: orange.position.x) : .idle, shield ? PlayerInput(shield: true) : .idle]
            case 7:
                // Orange for the ball and down the court with it to the dunk; teal after them, slashing
                // a beat too far off.
                if happened({ if case .dunked(1) = $0 { return true } else { return false } }) { director.advance() }
                if director.phaseFrames > 600 { director.finished = true }
                let orangeInput: PlayerInput
                if orange.hasBall {
                    orangeInput = tauntThreeDunk(&director, orange, rim: orangeRim)
                } else {
                    orangeInput = tauntThreeIntercept(&director, match, orange)
                }
                return [tauntThreeWhiff(&director, teal, orange), orangeInput]
            case 8:
                // Orange down off the rim; teal's slash as it lands, which hits.
                if happened({
                    if case .struck(1, 0) = $0 { return true }
                    if case .popped(1, 0) = $0 { return true }
                    return false
                }) { director.advance() }
                if director.phaseFrames > 300 { director.finished = true }
                guard free(teal) else { return [.idle, .idle] }
                let spot = orange.position.x + tauntThreeLandingSlashGap * (teal.position.x > orange.position.x ? 1 : -1)
                let down = orange.grounded && [.idle, .walk, .land].contains(orange.state)
                if down, director.notes["tLandingSlash"] == nil, abs(orange.position.x - teal.position.x) <= tauntThreeLandingSlashGap + 4 {
                    director.notes["tLandingSlash"] = 1
                    return [FootageInput.stick(orange.position.x > teal.position.x ? 0.3 : -0.3, shoot: true), .idle]
                }
                return [tauntThreeStep(teal, to: spot, facing: orange.position.x), .idle]
            case 9:
                // Teal for the ball, and away up the court with it, slowing past the middle.
                if happened({ if case .popped(0, 1) = $0 { return true } else { return false } }) { director.advance() }
                if director.phaseFrames > 600 { director.finished = true }
                let tealInput: PlayerInput
                if !teal.hasBall {
                    tealInput = free(teal) ? toBall(teal) : .idle
                } else {
                    // The stick let go a frame out of the catch, so slammed again it's a dash.
                    let running = [.dash, .run].contains(teal.state)
                    // Past the middle, braked out of the run, then on at a walk.
                    if teal.position.x < tauntThreeSlowFrom, !running, teal.lastInput.stick.x >= 0.8 { tealInput = .idle }
                    else if teal.position.x >= tauntThreeSlowFrom, running || teal.state == .pivot { tealInput = .idle }
                    else { tealInput = FootageInput.stick(teal.position.x < tauntThreeSlowFrom ? 1 : tauntThreeSlowStick) }
                }
                // Orange after them, once teal's clear, and the slash once close.
                if teal.hasBall, director.notes["tCarryAt"] == nil { director.notes["tCarryAt"] = Double(director.frames) }
                let clear = director.notes["tCarryAt"].map { director.frames - Int($0) >= tauntThreeChaseDelay } ?? false
                var orangeInput = free(orange) && !clear ? FootageInput.facing(orange, x: teal.position.x) : PlayerInput.idle
                if free(orange), teal.hasBall, clear {
                    let gap = teal.position.x - orange.position.x
                    orangeInput = abs(gap) <= tauntThreeChaseSlashGap ? FootageInput.stick(gap > 0 ? 0.3 : -0.3, shoot: true) : FootageInput.stick(gap > 0 ? 1 : -1)
                }
                return [tealInput, orangeInput]
            case 10:
                // Orange for the loose ball; teal, once up, close in and snatch it back.
                if teal.hasBall { director.advance() }
                if director.phaseFrames > 400 { director.finished = true }
                let orangeInput: PlayerInput = orange.hasBall ? (free(orange) ? FootageInput.facing(orange, x: teal.position.x) : .idle)
                    : (orange.grounded && !busy.contains(orange.state) ? toBall(orange) : .idle)
                guard free(teal), orange.hasBall else { return [.idle, orangeInput] }
                let gap = orange.position.x - teal.position.x
                if abs(gap) <= tauntThreeSnatchGap {
                    if (gap > 0) != (teal.facing == .right) { return [FootageInput.facing(teal, x: orange.position.x), orangeInput] }
                    return [FootageInput.stick(0, throwBall: true), orangeInput]
                }
                return [FootageInput.stick(gap > 0 ? 1 : -1), orangeInput]
            case 11:
                // To the floater's spot near the rim, the jump off the run.
                if director.phaseFrames > 300 { director.finished = true }
                guard teal.grounded, !busy.contains(teal.state) else { return [.idle, .idle] }
                let spot = tealRim.x - tauntThreeFloaterJumpGap
                if teal.position.x < spot { return [FootageInput.stick(1), .idle] }
                director.advance()
                return [FootageInput.stick(1, jump: true), .idle]
            case 12:
                // Up, the full hop; near its top, down on the aim and the stick let go: the Spin Move,
                // which brakes the run's carry away, so what follows goes straight up.
                if teal.state == .spinning { director.advance(); return [.idle, .idle] }
                if teal.grounded { return [FootageInput.stick(0, jump: true), .idle] }
                if director.notes["tSpinAsked"] != nil || teal.velocity.y <= tauntThreeSpinAt {
                    director.notes["tSpinAsked"] = 1
                    return [PlayerInput(aim: Vec2(x: 0, y: -1), throwBall: true), .idle]
                }
                return [FootageInput.stick(0, jump: true), .idle]
            case 13:
                // Out of the spin, the double jump, straight up beside the glass.
                if teal.state == .spinning { return [.idle, .idle] }
                director.advance()
                return [FootageInput.stick(tauntThreeRiseDrift, jump: true), .idle]
            case 14:
                // The throw held on the way up; at the glass, up with it still held: the floater, off
                // the glass and in, the first frame it goes in so.
                if teal.state == .throwing { director.advance(); return [.idle, .idle] }
                if teal.grounded, director.phaseFrames > 4 { director.finished = true }
                if teal.state != .throwStance { return [FootageInput.stick(tauntThreeRiseDrift, jump: true, throwBall: !teal.lastInput.throwBall), .idle] }
                let banks = layupGoesIn(match, thrower: 0, stick: Vec2(x: 0, y: 1), offGlass: true)
                return [banks ? FootageInput.stick(0, 1, throwBall: true) : FootageInput.stick(tauntThreeRiseDrift, throwBall: true), .idle]
            case 15:
                if happened({ if case .scored(0, _, _, _, _, _) = $0 { return true } else { return false } }) { director.advance() }
                if director.phaseFrames > 200 { director.finished = true }
                return [.idle, .idle]
            default:
                // Both the computer's a beat, then done.
                if director.phaseFrames > tauntThreeTailFrames { director.finished = true }
                return [nil, nil]
            }
        }, done: { director, _ in director.finished })
        scene.seeds = fortySevenSeeds
        return scene
    }

    static let tauntThreeTealStart = 118.0
    static let tauntThreeOrangeStart = 200.0
    /// Teal's walk at half the full walk's pace, and where it turns; the walk in, and the jump once past there.
    static let tauntThreeWalkStick = 0.5
    static let tauntThreeWalkEnds = 106.0...132.0
    static let tauntThreeWalkInStick = 0.6
    static let tauntThreeJumpAt = 140.0
    static let tauntThreeDoubleJumpAt = 0.5
    static let tauntThreeReleaseAt = 0.5
    /// Orange working at teal: in to this far off, the hopped swing, back out to that, a pause.
    static let tauntThreeHarassNear = 40.0
    static let tauntThreeHarassFar = 62.0
    static let tauntThreeHarassPause = 6
    static let tauntThreeContestGap = 40.0
    /// Teal's slashes behind orange's drive, this far off, out of reach; at most this many.
    static let tauntThreeWhiffGap = 27.0...34.0
    static let tauntThreeWhiffs = 2
    static let tauntThreeWhiffRest = 30
    static let tauntThreeWhiffUnderHeight = 45.0
    static let tauntThreeLandingSlashGap = 16.0
    /// Teal's run up the court, slowed past here; orange's slash once this close.
    static let tauntThreeSlowFrom = 150.0
    static let tauntThreeSlowStick = 0.5
    static let tauntThreeChaseSlashGap = 18.0
    static let tauntThreeChaseDelay = 45
    static let tauntThreeSnatchGap = 14.0
    /// The floater: the jump from this far off the rim, the Spin Move as the rise slows to this, and
    /// the stick toward the rim on the double jump's way up.
    static let tauntThreeFloaterJumpGap = 35.0
    static let tauntThreeSpinAt = 0.5
    static let tauntThreeRiseDrift = 0.6
    static let tauntThreeTailFrames = 90

    /// To `x` without overshooting: run, walked the last of the way, stopped there facing `facing`.
    static func tauntThreeStep(_ me: Player, to x: Double, facing: Double) -> PlayerInput {
        let away = x - me.position.x
        if abs(away) > 3 { return FootageInput.stick(abs(away) > 14 ? (away > 0 ? 1 : -1) : (away > 0 ? 0.7 : -0.7)) }
        if [.dash, .run, .pivot].contains(me.state) { return .idle }
        return FootageInput.facing(me, x: facing)
    }

    /// Orange at teal while teal plays with the ball: in to a step short of reach, a short hop and an
    /// aerial at its top, slash and snatch in turn; back out on short hops, still facing teal; a pause.
    static func tauntThreeHarass(_ director: inout FootageDirector, _ me: Player, _ teal: Player) -> PlayerInput {
        let busy: Set<PlayerState> = [.land, .jumpSquat, .slashing, .rolling, .snatching]
        let moving: Set<PlayerState> = [.dash, .run, .pivot]
        let near = teal.position.x + tauntThreeHarassNear, far = teal.position.x + tauntThreeHarassFar
        switch Int(director.notes["oStep"] ?? 0) {
        case 0:
            guard me.grounded, !busy.contains(me.state) else { return .idle }
            let away = near - me.position.x
            if abs(away) > 2 { return FootageInput.stick(abs(away) > 14 ? (away > 0 ? 1 : -1) : (away > 0 ? 0.7 : -0.7)) }
            if moving.contains(me.state) { return .idle }
            if (teal.position.x > me.position.x) != (me.facing == .right) { return FootageInput.facing(me, x: teal.position.x) }
            director.notes["oStep"] = 1
            director.notes["oSwung"] = nil
            return FootageInput.stick(0, jump: true)
        case 1:
            if me.grounded {
                if director.notes["oSwung"] != nil, !busy.contains(me.state) {
                    director.notes["oSwings"] = (director.notes["oSwings"] ?? 0) + 1
                    director.notes["oStep"] = 2
                    director.notes["oHopping"] = nil
                }
                return .idle
            }
            if director.notes["oSwung"] == nil, me.velocity.y <= 0.3 {
                director.notes["oSwung"] = 1
                return Int(director.notes["oSwings"] ?? 0) % 2 == 0 ? FootageInput.stick(0, shoot: true) : FootageInput.stick(0, throwBall: true)
            }
            return .idle
        case 2:
            let back = me.position.x > teal.position.x ? 1.0 : -1.0
            if !me.grounded { return FootageInput.stick(back) }
            guard !busy.contains(me.state) else { return .idle }
            if director.notes["oHopping"] != nil, abs(me.position.x - teal.position.x) >= abs(far - teal.position.x) - 8 {
                director.notes["oStep"] = 3
                director.notes["oPausedAt"] = Double(director.frames)
                return .idle
            }
            director.notes["oHopping"] = 1
            return FootageInput.stick(0, jump: true)
        default:
            if director.frames - Int(director.notes["oPausedAt"] ?? 0) >= tauntThreeHarassPause { director.notes["oStep"] = 0 }
            return me.grounded && !busy.contains(me.state) ? FootageInput.facing(me, x: teal.position.x) : .idle
        }
    }

    /// Orange as teal goes up for the shot: any swing played out, then to its spot in front, facing teal.
    static func tauntThreeContest(_ director: inout FootageDirector, _ me: Player, _ teal: Player) -> PlayerInput {
        if !me.grounded || [.land, .jumpSquat, .slashing, .rolling, .snatching].contains(me.state) { return .idle }
        let spot = teal.position.x + tauntThreeContestGap
        let away = spot - me.position.x
        if director.notes["oSet"] == nil {
            if abs(away) > 2 { return FootageInput.stick(abs(away) > 14 ? (away > 0 ? 1 : -1) : (away > 0 ? 0.7 : -0.7)) }
            if [.dash, .run, .pivot].contains(me.state) { return .idle }
            director.notes["oSet"] = 1
        }
        return FootageInput.facing(me, x: teal.position.x)
    }

    /// Orange's drive with the ball: at a run to the rim, the full hop, the double jump at its top
    /// steered under the rim's near side, and the throw held into the dunk.
    static func tauntThreeDunk(_ director: inout FootageDirector, _ me: Player, rim: Vec2) -> PlayerInput {
        let way = rim.x > me.position.x ? 1.0 : -1.0
        let under = rim.x - way * 12
        let steer = abs(under - me.position.x) > 4 ? (under > me.position.x ? 1.0 : -1.0) : 0
        switch Int(director.notes["oDunk"] ?? 0) {
        case 0:
            if me.state == .catching { return .idle }
            if abs(rim.x - me.position.x) <= 46, me.grounded {
                director.notes["oDunk"] = 1
                director.notes["oDunkAt"] = Double(director.frames)
                return FootageInput.stick(way, jump: true)
            }
            return FootageInput.stick(way)
        case 1:
            if director.frames - Int(director.notes["oDunkAt"] ?? 0) < 6 { return FootageInput.stick(way, jump: true) }
            if me.velocity.y <= 0.3, !me.grounded { director.notes["oDunk"] = 2; return FootageInput.stick(steer, jump: true) }
            return FootageInput.stick(steer)
        default:
            return FootageInput.stick(steer, throwBall: true)
        }
    }

    /// Orange for the ball off the rim: under it, and the jump the first frame a full hop held
    /// toward it catches it in the air.
    static func tauntThreeIntercept(_ director: inout FootageDirector, _ match: Match, _ me: Player) -> PlayerInput {
        let ball = match.ball.position.x
        let way = ball > me.position.x ? 1.0 : -1.0
        if director.notes["oLeapt"] != nil { return me.grounded && me.state != .jumpSquat ? FootageInput.toward(me, x: ball, slack: 1) : FootageInput.stick(way * 0.5, jump: true) }
        guard me.grounded, ![.land, .jumpSquat, .flipJump, .tumbling, .slashing, .rolling, .snatching].contains(me.state) else { return .idle }
        var copy = match
        for frame in 0..<tauntThreeInterceptFrames {
            let leaper = copy.players[1]
            copy.advance(inputs: [.idle, FootageInput.stick((copy.ball.position.x > leaper.position.x ? 1.0 : -1.0) * 0.5, jump: true)])
            if copy.ball.holder == 1 {
                _ = frame
                director.notes["oLeapt"] = 1
                return FootageInput.stick(way * 0.5, jump: true)
            }
        }
        return FootageInput.toward(me, x: ball, slack: 4)
    }
    static let tauntThreeInterceptFrames = 50

    /// Teal after orange's drive: a run behind, and a slash or two from a step out of reach.
    static func tauntThreeWhiff(_ director: inout FootageDirector, _ me: Player, _ orange: Player) -> PlayerInput {
        guard me.grounded, ![.land, .jumpSquat, .slashing, .rolling, .snatching].contains(me.state), me.hitStun == 0 else { return .idle }
        guard orange.hasBall else { return FootageInput.facing(me, x: orange.position.x) }
        let gap = orange.position.x - me.position.x
        // Only at a drive going away, so the swing's carry never reaches it.
        let drivingAway = orange.velocity.x * gap > 0 && abs(orange.velocity.x) >= 1
        let swings = Int(director.notes["tWhiffs"] ?? 0)
        let last = director.notes["tWhiffAt"].map { director.frames - Int($0) } ?? 999
        // Or under it as it goes up, the blade well below its feet.
        let underneath = !orange.grounded && orange.position.y >= tauntThreeWhiffUnderHeight && abs(gap) <= tauntThreeWhiffGap.upperBound
        if swings < tauntThreeWhiffs, last >= tauntThreeWhiffRest, (drivingAway && tauntThreeWhiffGap.contains(abs(gap))) || underneath {
            director.notes["tWhiffs"] = Double(swings + 1)
            director.notes["tWhiffAt"] = Double(director.frames)
            return FootageInput.stick(gap > 0 ? 0.3 : -0.3, shoot: true)
        }
        if abs(gap) < tauntThreeWhiffGap.lowerBound { return FootageInput.facing(me, x: orange.position.x) }
        return FootageInput.stick(gap > 0 ? 1 : -1)
    }

    /// Longball, red on Web Water with the ball, toward the right end: two full swings,
    /// the first over a helmet coming the other way, and out of the second the spin, floating right
    /// as the camera brings the rim into view. The other side parked at the far end.
    public static var webSwingLongball: FootageScene { webSwingLongball(runFrom: webLongballRunFrom, jumpFrom: webLongballJumpFrom) }

    public static func webSwingLongball(runFrom: Double, jumpFrom: Double) -> FootageScene {
        var scene = FootageScene(name: "clip_webSwing_longball", stage: .longballStadium, mode: .fortySeven, colours: ["red", "blue"],
                                 drinks: [.webWater, nil], maxFrames: 1200, setup: { match in
            match.place(0, at: webLongballStart, y: 10, facing: .right)
            match.place(1, at: 60, y: 10, facing: .right)
            match.takeBall(for: 0)
        }, step: { director, match in
            let me = match.players[0]
            let swung = match.events.contains { if case .webSwung(0) = $0 { return true } else { return false } }
            if swung { director.notes["swings"] = (director.notes["swings"] ?? 0) + 1 }
            let swings = Int(director.notes["swings"] ?? 0)
            // The first helmet out, coming this way: the one the first swing goes over.
            let helmet = match.helmets.first { $0.phase == .travelling && $0.speed < 0 }
            let gap = helmet.map { $0.box.min.x - me.position.x }
            switch director.phase {
            case 0:
                // Standing with it, facing the rim, till the helmet's that far off; a frame's let go, then the run.
                if let gap, gap <= runFrom { director.advance() }
                return [.idle, .idle]
            case 1:
                if let gap, gap <= jumpFrom { director.advance(); return [FootageInput.stick(1, jump: true), .idle] }
                return [FootageInput.stick(1), .idle]
            case 2:
                // Up; near the top, jump let go a frame and pressed again: the swing, held through.
                if me.grounded { return [FootageInput.stick(1, jump: true), .idle] }
                if me.velocity.y <= webLongballSwingAt {
                    if director.notes["letGo"] == nil { director.notes["letGo"] = 1; return [FootageInput.stick(1), .idle] }
                    director.notes["letGo"] = nil
                    director.advance()
                    return [FootageInput.stick(1, jump: true), .idle]
                }
                return [FootageInput.stick(1, jump: true), .idle]
            case 3:
                if me.state != .webSwing, swings >= 1, director.phaseFrames > 2 { director.advance() }
                return [FootageInput.stick(1, jump: true), .idle]
            case 4:
                // Out of the first, let go; the second as soon as it can start, held through.
                if director.phaseFrames >= WebRules.swingCooldownFrames + 1 { director.advance(); return [FootageInput.stick(1, jump: true), .idle] }
                return [FootageInput.stick(1), .idle]
            case 5:
                if me.state != .webSwing, swings >= 2, director.phaseFrames > 2 { director.advance() }
                return [FootageInput.stick(1, jump: true), .idle]
            default:
                // The spin, floating right; done a while after it's down.
                if me.grounded { director.notes["down"] = director.notes["down"] ?? Double(director.frames) }
                if let down = director.notes["down"], director.frames - Int(down) >= webLongballTailFrames { director.finished = true }
                return [me.grounded ? .idle : FootageInput.stick(1), .idle]
            }
        }, done: { director, _ in director.finished })
        scene.drinksAwake = true
        scene.seeds = fortySevenSeeds
        return scene
    }

    static let webLongballStart = 1620.0
    /// How far ahead the helmet is when the run starts, and when the jump comes.
    static let webLongballRunFrom = 380.0
    static let webLongballJumpFrom = 340.0
    static let webLongballSwingAt = 0.5
    /// Frames kept after it's down: few, the third helmet's on its way to it.
    static let webLongballTailFrames = 10

    /// The Elements, red on Web Water with the ball: off the right platform, a swing high across
    /// to the left one; then off its edge, down where the tornados rise while they're gone, and
    /// a wide swing back under the middle platform, up out of the gap onto the right platform.
    /// The other side stood on the right ledge.
    public static var webSwingElements: FootageScene {
        var scene = FootageScene(name: "clip_webSwing_theElements", stage: .theElements, mode: .fortySeven, colours: ["red", "blue"],
                                 drinks: [.webWater, nil], maxFrames: 1200, setup: { match in
            match.place(0, at: webElementsStart, y: 150, facing: .left)
            match.place(1, at: 610, y: 100, facing: .left)
            match.takeBall(for: 0)
        }, step: { director, match in
            let me = match.players[0]
            switch director.phase {
            case 0:
                if match.frame >= webElementsGoAt { director.advance() }
                return [.idle, .idle]
            case 1:
                // The walk toward the edge, the jump short of it (a dribble over the drop is lost to
                // the lava), and the swing once clear of the platform.
                if me.position.x <= webElementsHighJumpAt { director.advance() }
                return [FootageInput.stick(-0.7), .idle]
            case 2:
                director.advance(after: 5)
                return [FootageInput.stick(-1, jump: true), .idle]
            case 3:
                if me.state == .air, me.stateTimer >= 3, me.position.x <= webElementsHighSwingAt { director.advance() }
                return [FootageInput.stick(-1), .idle]
            case 4:
                if me.state == .webSwing { director.advance() }
                return [FootageInput.stick(-1, jump: true), .idle]
            case 5:
                if me.state != .webSwing { director.advance() }
                return [FootageInput.stick(-1, jump: true), .idle]
            case 6:
                if me.grounded, director.phaseFrames > 10 { director.advance() }
                return [me.grounded ? .idle : FootageInput.stick(-1), .idle]
            case 7:
                // Turned round and walked to the edge.
                if me.position.x >= webElementsLowHopFrom { director.advance() }
                return [FootageInput.stick(0.5), .idle]
            case 8:
                // Stopped, then the hop off as the tornados go under.
                guard me.state == .idle, abs(me.velocity.x) < 0.01 else { return [.idle, .idle] }
                if match.frame % TornadoRules.cycleFrames >= webElementsLowHopCycleFrame { director.advance(); return [FootageInput.stick(0.3, jump: true), .idle] }
                return [.idle, .idle]
            case 9:
                // Down the gap, and the swing low through where they rise, held to its widest.
                if !me.grounded, me.velocity.y < 0, me.position.y <= webElementsLowSwingAt { director.advance(); return [FootageInput.stick(1, jump: true), .idle] }
                return [FootageInput.stick(me.grounded ? 0.3 : min(max((webElementsLowSwingX - me.position.x) / 8, -1), 1)), .idle]
            case 10:
                if me.state != .webSwing, director.phaseFrames > 2 { director.advance() }
                return [FootageInput.stick(1, jump: true), .idle]
            case 11:
                // The spin up out of the gap, kept off the wall till it's over the platform, then onto it.
                if me.grounded { director.advance() }
                return [FootageInput.stick(me.position.y > webElementsOverPlatform ? 1 : 0, jump: true), .idle]
            default:
                if director.phaseFrames > 40 { director.finished = true }
                return [.idle, .idle]
            }
        }, done: { director, _ in director.finished })
        scene.drinksAwake = true
        scene.seeds = fortySevenSeeds
        return scene
    }

    static let webElementsStart = 490.0
    /// Play starts here: timed so the walk back to the left platform's edge meets the tornados going under.
    static let webElementsGoAt = 354
    static let webElementsHighJumpAt = 455.0
    static let webElementsHighSwingAt = 424.0
    static let webElementsLowHopFrom = 225.0
    /// The hop off this far into the tornados' cycle: the swing's under them once they've burst.
    static let webElementsLowHopCycleFrame = 193
    static let webElementsLowSwingX = 266.0
    static let webElementsLowSwingAt = 102.0
    static let webElementsOverPlatform = 151.0

    /// Wreck Center, yellow on Flash Fizz with the ball, purple on the attack: purple
    /// runs in and slashes, and each time yellow jumps and flashes clear, past it or away; then,
    /// the flashes back, a drive at the rim, a floater off a jump, the warp up to the ball at its top, and the dunk.
    public static var flashDunkWreckCenter: FootageScene {
        var scene = FootageScene(name: "clip_flashDunk_wreckCenter", stage: .wreckCenter, mode: .fortySeven, colours: ["yellow", "purple"],
                                 drinks: [.flashFizz, nil], maxFrames: 1500, setup: { match in
            match.place(0, at: flashDunkYellowStart, y: 10, facing: .right)
            match.place(1, at: flashDunkPurpleStart, y: 10, facing: .left)
            match.takeBall(for: 0)
        }, step: { director, match in
            let me = match.players[0], them = match.players[1]
            guard let rim = match.scoringRim(for: 0) else { return [.idle, .idle] }
            let attacking = director.phase < 6
            let purple = attacking ? flashAttacker(&director, them, target: me) : flashContester(&director, them, target: me, spot: rim.x - flashContestGap)
            let away = me.position.x > them.position.x ? 1.0 : -1.0
            switch director.phase {
            case 0, 3:
                // Dribbling, facing purple, till it's running in close: up off the floor before the slash.
                let closing = [.dash, .run].contains(them.state) || them.state == .slashing
                if closing, abs(them.position.x - me.position.x) <= flashDunkDodgeGap, me.grounded, ![.land, .jumpSquat].contains(me.state) {
                    director.advance()
                    return [FootageInput.stick(0, jump: true), purple]
                }
                return [director.phase == 0 ? FootageInput.stick(0.3) : .idle, purple]
            case 1, 4:
                // Up, jump let go; as the slash comes, or a few frames up, jump again along the stick:
                // the flash, the first past purple toward the rim, the second back the other way.
                if me.grounded || (them.state != .slashing && director.phaseFrames < flashDunkFlashFrames) { return [.idle, purple] }
                director.advance()
                let way = director.phase == 2 ? -away : away
                return [FootageInput.stick(way * 0.9, 0.45, jump: true), purple]
            case 2, 5:
                if me.grounded, director.phaseFrames > 4 { director.advance() }
                return [.idle, purple]
            case 6:
                // The flashes back: the drive to the rim's near side.
                let spot = rim.x - flashDunkFloaterGap * (rim.x > me.position.x ? 1 : -1)
                if (me.warpCooldown == 0 && abs(me.position.x - spot) <= 4) && me.grounded { director.advance(); return [FootageInput.stick(0, jump: true), purple] }
                if abs(me.position.x - spot) <= 4 { return [FootageInput.facing(me, x: rim.x), purple] }
                return [FootageInput.stick(spot > me.position.x ? 1 : -1), purple]
            case 7:
                // Up, the full hop, and the floater from the top of it, held till it's away.
                if me.state == .throwing || me.state == .shooting { director.advance(); return [.idle, purple] }
                if director.phaseFrames > 60 { director.finished = true }
                if me.grounded || me.velocity.y > 0.3 { return [FootageInput.stick(0, jump: true), purple] }
                return [FootageInput.stick(0, 1, throwBall: true), purple]
            case 8:
                // At its top, the warp up to it: up and Strike, the ball in hand at once.
                if match.ball.velocity.y <= flashDunkWarpAt, !me.hasBall {
                    director.advance()
                    return [FootageInput.stick(0, 1, shoot: true), purple]
                }
                if director.phaseFrames > 60 { director.finished = true }
                return [.idle, purple]
            case 9:
                // Holding it high by the rim: the throw held, the dunk.
                if me.state == .dunking { director.advance() }
                if director.phaseFrames > 60 { director.finished = true }
                return [FootageInput.stick(0, throwBall: me.hasBall), purple]
            default:
                if director.phaseFrames > flashDunkTailFrames { director.finished = true }
                return [.idle, purple]
            }
        }, done: { director, _ in director.finished })
        scene.drinksAwake = true
        scene.seeds = fortySevenSeeds
        return scene
    }

    static let flashDunkYellowStart = 90.0
    static let flashDunkPurpleStart = 190.0
    /// Purple's slash this close sets off the dodge; the floater from this far off the rim; the warp
    /// up as the ball's rise slows to this.
    static let flashDunkDodgeGap = 44.0
    static let flashDunkFlashFrames = 8
    static let flashDunkFloaterGap = 18.0
    static let flashDunkWarpAt = 0.5
    static let flashDunkTailFrames = 90

    /// Purple on the attack: run in, and the slash once close, a beat between swings.
    static func flashAttacker(_ director: inout FootageDirector, _ me: Player, target: Player) -> PlayerInput {
        guard me.grounded, ![.slashing, .land, .jumpSquat].contains(me.state) else { return .idle }
        let gap = target.position.x - me.position.x
        let last = director.notes["pSlashAt"].map { director.frames - Int($0) } ?? 999
        if abs(gap) <= flashAttackReach, last >= flashAttackRest {
            director.notes["pSlashAt"] = Double(director.frames)
            return FootageInput.stick(gap > 0 ? 0.3 : -0.3, shoot: true)
        }
        if abs(gap) <= flashAttackReach { return FootageInput.facing(me, x: target.position.x) }
        return FootageInput.stick(gap > 0 ? 1 : -1)
    }
    static let flashAttackReach = 30.0
    static let flashAttackRest = 40

    /// Purple as yellow goes up for the dunk: to its spot short of the rim, walked the last of the way so
    /// no dash carries it past, then short hops in place facing yellow, an air snatch at the top of each.
    static func flashContester(_ director: inout FootageDirector, _ me: Player, target: Player, spot: Double) -> PlayerInput {
        let moving: Set<PlayerState> = [.dash, .run, .pivot]
        if !me.grounded {
            if director.notes["pHopSnatched"] == nil, me.velocity.y <= flashContestSnatchAt {
                director.notes["pHopSnatched"] = 1
                return FootageInput.stick(0, throwBall: true)
            }
            return .idle
        }
        if director.notes["pAtSpot"] == nil {
            let away = spot - me.position.x
            if abs(away) > 2 { return FootageInput.stick(abs(away) > flashContestWalkFrom ? (away > 0 ? 1 : -1) : (away > 0 ? 0.7 : -0.7)) }
            if moving.contains(me.state) { return .idle }
            director.notes["pAtSpot"] = 1
            director.notes["pLanded"] = Double(director.frames)
        }
        if [.land, .jumpSquat, .snatching].contains(me.state) || moving.contains(me.state) { return .idle }
        if director.notes["pHopSnatched"] != nil {
            director.notes["pHopSnatched"] = nil
            director.notes["pLanded"] = Double(director.frames)
        }
        let facingTarget = (target.position.x > me.position.x) == (me.facing == .right)
        if facingTarget, director.frames - Int(director.notes["pLanded"] ?? 0) >= flashContestRestFrames {
            // The short hop: jump tapped, let go inside the squat.
            return FootageInput.stick(0, jump: true)
        }
        return FootageInput.facing(me, x: target.position.x)
    }
    static let flashContestGap = 40.0
    static let flashContestWalkFrom = 14.0
    static let flashContestSnatchAt = 0.3
    static let flashContestRestFrames = 10

    /// K&A, yellow in FloState on Flash Fizz against purple: neutral, both the computer's, till yellow
    /// has the ball with purple between it and the rim; then the ball thrown off purple, the warp to
    /// it on its bounce, a jump and the flash up, and a jumper that goes in; the computer's again after.
    public static var flashThrowKAndA: FootageScene {
        var scene = FootageScene(name: "clip_flashThrow_kAndA", stage: .kAndA, mode: .fortySeven, colours: ["yellow", "purple"],
                                 drinks: [.flashFizz, nil], maxFrames: 2400, setup: { match in
            let y = floorY(match.stage, x: 150)
            match.place(0, at: 150, y: y, facing: .right)
            match.place(1, at: 250, y: y, facing: .left)
            match.takeBall(for: 0)
            match.players[0].flo = FloRules.full
            match.players[0].floStateLockout = 0
        }, step: { director, match in
            let me = match.players[0], them = match.players[1]
            guard let rim = match.scoringRim(for: 0) else { return [nil, nil] }
            if director.notes["changed"] == nil {
                if me.inFloState, me.state != .transforming { director.notes["changed"] = 1; return [.idle, .idle] }
                if me.state == .transforming || director.frames < 20 { return [.idle, .idle] }
                return [PlayerInput(shoot: true, throwBall: true), .idle]
            }
            let free: Set<PlayerState> = [.idle, .walk, .run, .dash]
            switch director.phase {
            case 0:
                // Neutral, both the computer's, till yellow's on the ball, grounded, with purple ahead toward the rim.
                let gap = them.position.x - me.position.x
                let ready = director.phaseFrames >= flashThrowNeutralFrames && me.hasBall && me.grounded && them.grounded
                    && free.contains(me.state) && free.contains(them.state) && flashThrowGap.contains(gap) && flashThrowSpots.contains(me.position.x)
                    // The warp and both flashes to hand: none spent in the neutral just gone.
                    && me.warpCooldown == 0 && (me.flashCharges ?? FizzRules.flashCharges(level: me.powerLevel)) == FizzRules.flashCharges(level: me.powerLevel)
                if ready { director.notes["scriptAt"] = Double(director.frames); director.advance(); return [FootageInput.stick(1, throwBall: true), .idle] }
                if director.phaseFrames > flashThrowNeutralMost { director.finished = true }
                return [nil, nil]
            case 1:
                // The throw at purple: held through its windup, aimed at them, let go.
                if me.state == .throwing { director.advance(); return [.idle, .idle] }
                if director.phaseFrames > 40 { director.go(to: 20) }
                let way = them.position.x > me.position.x ? 1.0 : -1.0
                let wound = me.state == .throwStance && me.stateTimer >= BallRules.throwWindupFrames
                return [FootageInput.stick(way, throwBall: !wound), .idle]
            case 2:
                // It strips purple and comes back off them: on the rebound, once free of the throw and
                // while it's still well off, up and Strike, the warp to it.
                // Tapped till it takes: a press in the hit's stop is lost.
                let warped = match.events.contains { if case .warped(0, _, _) = $0 { return true } else { return false } }
                if warped { director.advance(); return [.idle, .idle] }
                if match.ball.returning, match.ball.isLive, match.ball.position.distance(to: me.chest) >= flashThrowWarpReach {
                    return [FootageInput.stick(0, 1, shoot: !me.lastInput.shoot), .idle]
                }
                if director.phaseFrames > 90 { director.go(to: 20) }
                return [.idle, .idle]
            case 3:
                // In hand where it was: up off the floor if it's there, then the flash straight up.
                guard me.hasBall, me.state != .catching else {
                    if director.phaseFrames > 40 { director.go(to: 20) }
                    return [.idle, .idle]
                }
                if me.grounded { return [FootageInput.stick(0, jump: !me.lastInput.jump), .idle] }
                if me.lastInput.jump { return [.idle, .idle] }
                director.advance()
                return [FootageInput.stick(0, 1, jump: true), .idle]
            case 4:
                director.advance()
                return [FootageInput.stick(0, shoot: true), .idle]
            case 5:
                // The stance up there, let go near the top, flicked where it goes in.
                if me.state == .shootStance, me.stateTimer >= BallRules.shotWindupFrames, me.velocity.y <= 1.2 {
                    let aim = searchedFlick(match, shooter: 0, toward: rim.x > me.position.x ? .right : .left, preferred: 0.85) ?? .zero
                    director.notes["aimX"] = aim.x
                    director.notes["aimY"] = aim.y
                    director.advance()
                    return [FootageInput.stick(0, aim: aim), .idle]
                }
                if me.grounded, director.phaseFrames > 10 { director.go(to: 20) }
                return [FootageInput.stick(0, shoot: true), .idle]
            case 6:
                let scored = match.events.contains { if case .scored(0, _, _, _, _, _) = $0 { return true } else { return false } }
                if scored { director.notes["scored"] = Double(director.frames) }
                if director.notes["scored"] != nil, me.grounded { director.go(to: 20) }
                if director.phaseFrames > 180 { director.go(to: 20) }
                return [.idle, .idle]
            default:
                // Neutral again, both the computer's, to the cut.
                if director.phaseFrames > flashThrowAfterFrames { director.finished = true }
                return [nil, nil]
            }
        }, done: { director, _ in director.finished })
        scene.seeds = flashThrowSeeds
        return scene
    }

    /// Neutral at least this long first, and at most this long waiting for the throw's moment: purple
    /// this far ahead, yellow on this stretch, the jumper's range from the right rim.
    static let flashThrowNeutralFrames = 150
    static let flashThrowNeutralMost = 900
    static let flashThrowGap = 80.0...130.0
    /// The rebound warped to only while it's this far off at least, so the warp shows.
    static let flashThrowWarpReach = 30.0
    static let flashThrowSpots = 120.0...230.0
    static let flashThrowAfterFrames = 150
    static let flashThrowSeeds: [UInt32] = [4, 43]

    // MARK: Clashes

    public enum ClashKind: String { case slash, shield, snatch }

    /// A clash out of play: both sides the computer's for `leadIn` frames, then once both are on their
    /// feet, at each other till they're face to face `gap` apart (for `airborne`, up out of a jump on
    /// the way), and the same move from both at once; the computer's again after. They start `apart`
    /// either side of the stage's middle (on Anozira, of the car).
    public static func clash(_ kind: ClashKind, on stage: StageChoice, gap: Double, airborne: Bool, apart: Double = 90, leadIn: Int = 150,
                             feints: Bool = false, colours: [String], rain: Double? = nil, name: String) -> FootageScene {
        FootageScene(name: name, stage: stage, colours: colours, rain: rain, maxFrames: leadIn + 600, setup: { match in
            if match.stage.features.roadSlides {
                // About the middle of the car's roof, its one flat stretch.
                let car = match.anoziraCar.x
                match.place(0, at: car + 35 - apart, y: 40, facing: .right)
                match.place(1, at: car + 35 + apart, y: 40, facing: .left)
            } else {
                let middle = match.stage.width / 2
                let y = floorY(match.stage, x: middle)
                match.place(0, at: middle - apart, y: y, facing: .right)
                match.place(1, at: middle + apart, y: y, facing: .left)
            }
        }, eachFrame: { $0.parkBall() }, step: { director, match in
            let first = match.players[0], second = match.players[1]
            let across = abs(second.position.x - first.position.x)
            let way = second.position.x > first.position.x ? 1.0 : -1.0
            let neutral: Set<PlayerState> = [.idle, .walk, .run, .crouch]
            let facingEachOther = first.facing.sign == way && second.facing.sign == -way
            func press(_ toward: Double) -> PlayerInput {
                switch kind {
                case .slash: FootageInput.stick(toward * 0.3, shoot: true)
                case .shield: FootageInput.stick(toward * 0.3, shield: true)
                case .snatch: FootageInput.stick(toward * 0.3, throwBall: true)
                }
            }
            let bothNeutral = neutral.contains(first.state) && neutral.contains(second.state) && first.grounded && second.grounded
            switch director.phase {
            case 0:
                // Where the computer can't keep its feet near the other (Anozira's road, the Hideaway's
                // water), the lead-up's played out instead: hops, feints and crouches at each other.
                if feints {
                    let beat = clashFeints.firstIndex { $0.until > director.frames } ?? clashFeints.count
                    guard beat < clashFeints.count else { director.advance(); return [.idle, .idle] }
                    let (_, mine, theirs) = clashFeints[beat]
                    func toward(_ input: PlayerInput, _ sign: Double) -> PlayerInput {
                        var turned = input
                        turned.stick.x *= sign
                        return turned
                    }
                    return [toward(mine, way), toward(theirs, -way)]
                }
                // Play, then once both are on their feet together, at each other.
                if director.frames >= leadIn, bothNeutral || director.frames >= leadIn + 240 { director.advance() }
                return [nil, nil]
            case 1:
                // Squared up and closing in; anyone still busy, waited for.
                guard bothNeutral else { return [.idle, .idle] }
                // On top of each other (in a corner, say): the one nearer the middle walks out first.
                if across < gap * 0.6 {
                    let middle = match.stage.width / 2
                    let firstOut = abs(first.position.x - middle) < abs(second.position.x - middle)
                    let out = FootageInput.stick(middle > (firstOut ? first : second).position.x ? 0.5 : -0.5)
                    return firstOut ? [out, .idle] : [.idle, out]
                }
                if across <= gap + (airborne ? 36 : 0), facingEachOther { director.go(to: airborne ? 2 : 4) }
                // Walked in the last of it, so nobody dashes past.
                let pace = across <= gap + (airborne ? 36 : 0) + 60 ? 0.5 : 1
                return [FootageInput.stick(way * pace), FootageInput.stick(-way * pace)]
            case 2:
                director.advance()
                return [FootageInput.stick(way, jump: true), FootageInput.stick(-way, jump: true)]
            case 3:
                // Both off the ground first, so the press isn't lost in the jump's squat.
                if across <= gap, !first.grounded, !second.grounded, first.state == .air, second.state == .air { director.advance() }
                if director.phaseFrames > 40 { director.go(to: 1) }
                return [FootageInput.stick(way), FootageInput.stick(-way)]
            case 4:
                director.advance()
                return [press(way), press(-way)]
            default:
                if director.phaseFrames > 120 { director.finished = true }
                return [nil, nil]
            }
        }, done: { director, _ in director.finished })
    }

    /// The played-out lead-up to a clash, beat by beat: the frame each beat lasts until, and each
    /// side's input, its stick's across toward the other. No crouch: on a car's top it drops through.
    static let clashFeints: [(until: Int, PlayerInput, PlayerInput)] = [
        (20, .idle, .idle),
        (26, FootageInput.stick(0, jump: true), .idle),
        (46, .idle, .idle),
        (52, FootageInput.stick(0.4), .idle),
        (60, .idle, FootageInput.stick(0, jump: true)),
        (80, .idle, .idle),
        (86, .idle, FootageInput.stick(0.4)),
        (96, .idle, .idle),
        (104, FootageInput.stick(0.4), .idle),
        (116, .idle, .idle),
    ]

    public static var clashes: [FootageScene] {
        [clash(.slash, on: .wreckCenter, gap: 44, airborne: false, colours: ["yellow", "teal"], name: "slashclash_wreckCenter"),
         clash(.slash, on: .theElements, gap: 44, airborne: true, apart: 44, colours: ["red", "blue"], name: "slashclash_air_theElements"),
         clash(.shield, on: .kAndA, gap: 30, airborne: false, colours: ["green", "purple"], name: "shieldclash_kAndA"),
         clash(.shield, on: .anozira, gap: 30, airborne: true, apart: 12, feints: true, colours: ["orange", "blue"], rain: 1, name: "shieldclash_air_anozira_rain"),
         clash(.shield, on: .theElements, gap: 30, airborne: false, apart: 44, colours: ["pink", "yellow"], name: "shieldclash_theElements"),
         clash(.snatch, on: .wreckCenter, gap: 36, airborne: false, colours: ["pink", "green"], name: "snatchclash_wreckCenter"),
         clash(.snatch, on: .anozira, gap: 36, airborne: false, apart: 12, feints: true, colours: ["yellow", "red"], rain: 1, name: "snatchclash_anozira_rain"),
         clash(.slash, on: .anozira, gap: 44, airborne: false, apart: 12, feints: true, colours: ["green", "pink"], rain: 1, name: "slashclash_anozira_rain"),
         clash(.slash, on: .hoopfishHideaway, gap: 30, airborne: false, apart: 36, feints: true, colours: ["purple", "yellow"], name: "slashclash_hoopfishHideaway")]
    }

    // MARK: FloState

    /// The change into FloState, then the drink's power shown off in it.
    public static func floState(_ drink: Greateraid, on stage: StageChoice, colour: String) -> FootageScene {
        let withBall = drink == .phantomFrappe
        return FootageScene(name: "flostate_\(drink)_\(stage)", stage: stage, mode: .fortySeven, colours: [colour, "teal"], drinks: [drink, nil], maxFrames: 900, setup: { match in
            let middle = match.stage.width / 2
            let x = middle - 40
            match.place(0, at: x, y: floorY(match.stage, x: x), facing: .right)
            parkOther(&match, awayFrom: x)
            match.players[0].flo = FloRules.full
            match.players[0].floStateLockout = 0
            if withBall { match.takeBall(for: 0) }
        }, eachFrame: withBall ? nil : { $0.parkBall() }, step: { director, match in
            let me = match.players[0]
            switch director.phase {
            case 0:
                director.advance(after: 30)
                return [.idle, nil]
            case 1:
                // Strike and Guard together: the change.
                if me.state == .transforming { director.advance() }
                return [PlayerInput(shoot: true, throwBall: true), nil]
            case 2:
                if me.inFloState, me.state != .transforming { director.advance() }
                return [.idle, nil]
            case 3:
                director.advance(after: 30)
                return [.idle, nil]
            default:
                if director.phaseFrames > 240 { director.finished = true }
                return [floStateShowing(drink, me: me, them: match.players[1], frame: director.phaseFrames), nil]
            }
        }, done: { director, _ in director.finished })
    }

    /// A few seconds of a power in FloState, by frame.
    static func floStateShowing(_ drink: Greateraid, me: Player, them: Player, frame: Int) -> PlayerInput {
        switch drink {
        case .zTea:
            // Two blasts up and across, then the beam charged and fired.
            if frame < 60 { return frame % 24 < 4 ? FootageInput.stick(0, 1, shoot: true) : .idle }
            if frame < 110 { return me.state == .beamCharging ? .idle : (frame % 8 < 4 ? FootageInput.stick(0, -1, shoot: true) : .idle) }
            if frame < 130 { return me.state == .beamFiring ? .idle : (frame % 8 < 4 ? FootageInput.stick(0, -1, shoot: true) : .idle) }
            return FootageInput.stick(0.5, sin(Double(frame) / 10) * 0.6)
        case .webWater:
            if frame < 10 { return FootageInput.stick(1, jump: true) }
            if frame < 20 { return FootageInput.stick(1) }
            return FootageInput.stick(1, jump: frame < 90)
        case .superSmoothie:
            let turn = Double(frame) / 60 * 2 * Double.pi
            return frame < 10 ? FootageInput.stick(0, 1, jump: true) : FootageInput.stick(cos(turn), sin(turn), jump: true)
        case .flashFizz:
            if frame % 70 < 8 { return FootageInput.stick(1, jump: true) }
            if frame % 70 < 30 { return FootageInput.stick(1, jump: true) }
            return FootageInput.stick(frame % 140 < 70 ? 1 : -1)
        case .platformShake:
            if frame % 90 < 10 { return FootageInput.stick(0, jump: true) }
            if frame % 90 < 40 { return FootageInput.stick(0, -1) }
            return .idle
        case .voltaCola:
            // Bolts at them, turned their way and tilted to their height, moving between throws to
            // keep a throw's distance; up close, the snatch's strike down on them.
            let toThem = them.chest - me.chest
            let way = toThem.x >= 0 ? 1.0 : -1.0
            if abs(toThem.x) < 28, abs(toThem.y) < 30, me.strikeCooldown == 0 { return FootageInput.stick(way * 0.4, throwBall: true) }
            if frame % 40 < 4 {
                let tilt = min(max(atan2(toThem.y, abs(toThem.x)) / VoltaRules.boltTilt, -1), 1)
                return FootageInput.stick(way, tilt, shoot: true)
            }
            if abs(toThem.x) > 120 { return FootageInput.stick(way) }
            if abs(toThem.x) < 60 { return FootageInput.stick(-way, jump: frame % 40 == 10) }
            return FootageInput.stick(way * 0.4)
        case .blazingBoba, .galeAle, .pulsepistol:
            // Turned their way between shots.
            let way = them.position.x >= me.position.x ? 1.0 : -1.0
            return frame % 50 < 4 ? FootageInput.stick(0, 1, shoot: true) : FootageInput.stick(frame % 50 < 12 ? way * 0.6 : 0, frame % 50 < 30 ? 1 : 0)
        case .frostTea:
            if frame % 80 < 30 { return FootageInput.stick(1) }
            if frame % 80 < 50 { return FootageInput.stick(1, -1) }
            return .idle
        case .surfSoda:
            return frame % 60 < 6 ? FootageInput.stick(1, jump: true) : FootageInput.stick(1)
        case .titanTea:
            // Hops at them: every landing of its own quakes the floor.
            let way = them.position.x >= me.position.x ? 1.0 : -1.0
            if frame % 50 < 8 { return FootageInput.stick(way * 0.5, jump: true) }
            return FootageInput.stick(abs(them.position.x - me.position.x) > 40 ? way * 0.6 : 0)
        case .phantomFrappe:
            // The ball in hand: a jump, and down with Guard in the air for the Spin Move's phase.
            if frame % 80 < 6 { return FootageInput.stick(0, jump: true) }
            if frame % 80 < 12 { return .idle }
            if frame % 80 < 24 { return FootageInput.stick(0, -1, throwBall: true) }
            return .idle
        default:
            return frame % 60 < 30 ? FootageInput.stick(1) : FootageInput.stick(-1)
        }
    }

    public static var floStateMontage: [FootageScene] {
        let drinks: [Greateraid] = [.zTea, .webWater, .superSmoothie, .flashFizz, .platformShake, .voltaCola, .frostTea, .blazingBoba, .pulsepistol, .surfSoda, .titanTea, .galeAle, .phantomFrappe]
        let stages: [StageChoice] = [.wreckCenter, .kAndA, .hoopfishHideaway, .theElements]
        return drinks.enumerated().map { index, drink in
            // Titan Tea on dry land, where its landings quake; Surf Soda in the Hideaway's water instead.
            let stage: StageChoice = drink == .titanTea ? .kAndA : (drink == .surfSoda ? .hoopfishHideaway : stages[index % stages.count])
            return floState(drink, on: stage, colour: colours[index % colours.count])
        }
    }

    // MARK: Helpers

    /// The floor under `x`: the top of the highest solid tile with open air above it, the ceiling
    /// and the stage's roofs passed over.
    static func floorY(_ stage: Stage, x: Double) -> Double {
        let column = Int(x / Stage.tileSize)
        for row in stride(from: stage.rows - 5, through: 0, by: -1) where stage.tile(column: column, row: row) == .solid {
            let open = (1...3).allSatisfy { stage.tile(column: column, row: row + $0) == .empty }
            if open { return Double(row + 1) * Stage.tileSize }
        }
        return stage.playerSpawns.first?.y ?? 10
    }

    /// The other side stood well away from `x`, on the far side of the stage; on Anozira, on the car's far end.
    static func parkOther(_ match: inout Match, awayFrom x: Double) {
        guard match.players.count > 1 else { return }
        if match.stage.features.roadSlides {
            // On the road before the hoop truck, guarding its rim.
            match.place(1, at: match.anoziraTruck.standing.x - 30, y: 30, facing: .left)
            return
        }
        let farX = x < match.stage.width / 2 ? match.stage.width - 60 : 60
        match.place(1, at: farX, y: floorY(match.stage, x: farX), facing: farX > x ? .left : .right)
    }
}
