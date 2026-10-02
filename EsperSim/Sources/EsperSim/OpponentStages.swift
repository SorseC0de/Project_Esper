import Foundation

/// Off the Wreck Center: the stage read for its surfaces and the jumps between them, the ball
/// and a moving rim followed ahead by stepping copies of them, shots tried out by the ball's own
/// flight, and the lava kept clear of.
extension Opponent {
    /// The link it's on, from which surface, and by when it should have made it.
    struct Journey: Equatable {
        var from: Int
        var link: Terrain.Link
        var deadline: Int
        /// Once it's at the takeoff the move is played through, whatever else changes.
        var started = false
        var startedAt = 0
        var startY = 0.0
        var leftGround = false
    }

    /// A link given up on after failing, until a frame.
    struct GivenUp: Equatable {
        var from: Int
        var to: Int
        var until: Int
    }

    /// A place to shoot from at a still rim, found by trying shots from there.
    struct ShotSpot: Equatable {
        var feet: Vec2
        var jumpShot: Bool
    }

    /// The search for a still rim's shot spots: the places left to try, and those that worked.
    struct SpotSearch: Equatable {
        var hoop: Int
        var candidates: [Vec2]
        var tried = 0
        var found: [ShotSpot] = []
        var done: Bool { tried >= candidates.count }
    }

    /// Whether this stage is played by its reading: everywhere but the court the computer was
    /// first taught on.
    static func readsStage(_ match: Match) -> Bool { match.stage.features.look != .court }

    /// The rim, ball and frames a link may take a tornado for: one that's up, not fire, and
    /// staying up a while.
    private static let tornadoTrustFrames = 45
    /// A move that hasn't left the ground this long after it began was interrupted: dropped.
    static let takeoffFrames = 10
    /// A link taken this long past what its walk and jump should need is given up on a while.
    private static let journeySpareFrames = 150
    private static let givenUpFrames = 600
    /// Frames ahead the ball and a moving rim are followed.
    static let lookAheadFrames = 240

    // MARK: The reading

    mutating func readStage(_ match: Match, me: Player) {
        let signature = Terrain.signature(of: match.stage, for: me)
        if terrain?.signature != signature {
            terrain = Terrain(stage: match.stage, player: me)
            journey = nil
            givenUp = []
            spotSearch = nil
        }
        givenUp.removeAll { $0.until <= match.frame }
        terrain?.prepare(budget: Opponent.readingBudget)
    }

    /// Frames of a body stepped each frame finding the stage's links, until they're all found.
    static let readingBudget = 1500

    private func usable(_ from: Int, _ link: Terrain.Link, _ match: Match) -> Bool {
        if givenUp.contains(where: { $0.from == from && $0.to == link.to }) { return false }
        guard let terrain else { return true }
        // Out of a tornado only from where the move was tried: up, not sinking or rising.
        if terrain.surfaces[from].tornado != nil, TornadoRules.sunkShare(at: match.frame) != 0 { return false }
        guard terrain.surfaces[link.to].tornado != nil else { return true }
        return stride(from: 0, through: Opponent.tornadoTrustFrames, by: 15).allSatisfy { ahead in
            TornadoRules.holds(at: match.frame + ahead) && !TornadoRules.isFire(at: match.frame + ahead)
        }
    }

    /// Which tornado holds it, by the middle it's drawn to.
    private func tornado(holding me: Player, in match: Match) -> Int? {
        guard me.state == .suspended, let centre = me.tornadoCentre else { return nil }
        return match.stage.tornados.indices.min { abs(match.stage.tornados[$0].center.x - centre.x) < abs(match.stage.tornados[$1].center.x - centre.x) }
    }

    /// The surface it stands on, or the tornado holding it.
    func surface(of me: Player, in match: Match) -> Int? {
        guard let terrain else { return nil }
        if let held = tornado(holding: me, in: match) { return terrain.surface(under: me.position, suspendedIn: held) }
        return me.grounded ? terrain.surface(under: me.position) : nil
    }

    // MARK: Getting about

    /// Toward a point by the stage's surfaces: along the one it's on, or across the others a link
    /// at a time, each move played as it was when it was found to make it. True once it's there.
    @discardableResult
    mutating func go(to point: Vec2, match: Match, me: Player, into input: inout PlayerInput, near: Double = 4) -> Bool {
        guard let terrain, let goal = terrain.standing(nearest: point) else { return false }
        if var journey, journey.started {
            let standing = me.grounded || me.state == .suspended
            let stalled = !journey.leftGround && match.frame - journey.startedAt > Opponent.takeoffFrames
            if stalled || (standing && (journey.leftGround || surface(of: me, in: match) != journey.from || match.frame > journey.deadline)) {
                // Down, or somewhere else than it set off from: the move's over, landed where it meant to or not.
                self.journey = nil
            } else {
                if !me.grounded, me.state != .suspended, me.state != .jumpSquat { journey.leftGround = true }
                self.journey = journey
                play(journey, me: me, into: &input)
                rescueFromLava(match: match, me: me, into: &input)
                return false
            }
        }
        guard let here = surface(of: me, in: match) else {
            // In the air with no move: toward the goal, and off the lava.
            let dx = goal.x - me.position.x
            input.stick = Vec2(x: abs(dx) > 2 ? (dx > 0 ? 1 : -1) : 0, y: 0)
            rescueFromLava(match: match, me: me, into: &input)
            return false
        }
        if here == goal.surface {
            journey = nil
            if terrain.surfaces[here].tornado != nil { return true }
            return walk(to: goal.x, me: me, into: &input, near: near)
        }
        guard let link = terrain.route(from: here, to: goal.surface, usable: { usable($0, $1, match) })?.first else {
            // No way there now, a tornado down or fire: wait where it's safe, as near as this surface goes.
            journey = nil
            if terrain.surfaces[here].tornado == nil { walk(to: terrain.surfaces[here].clamp(goal.x), me: me, into: &input, near: near) }
            return false
        }
        if journey?.from != here || journey?.link != link {
            let speed = max(me.spec.runSpeed * me.waterShare, 0.5)
            journey = Journey(from: here, link: link, deadline: match.frame + Opponent.journeySpareFrames + Int(abs(link.takeoff - me.position.x) / speed))
        } else if let deadline = journey?.deadline, match.frame > deadline {
            givenUp.append(GivenUp(from: here, to: link.to, until: match.frame + Opponent.givenUpFrames))
            journey = nil
            return false
        }
        // To the takeoff, still, then the move.
        let dx = link.takeoff - me.position.x
        // In a tornado, its pull brings it to the middle the move was tried from.
        let atTakeoff = link.kind == .walkOff ? abs(dx) <= 6 : abs(dx) <= 2 && abs(me.velocity.x) < 0.3
        if !atTakeoff {
            // In a tornado its pull is what brings it to the middle; the stick only fights it.
            input.stick = abs(dx) <= 2 || me.state == .suspended ? .zero : Vec2(x: (dx > 0 ? 1 : -1) * (abs(dx) > 20 ? 1 : 0.4), y: 0)
            return false
        }
        journey?.started = true
        journey?.startedAt = match.frame
        journey?.deadline = match.frame + Opponent.journeySpareFrames * 3
        journey?.startY = me.position.y
        if let journey { play(journey, me: me, into: &input) }
        return false
    }

    /// This frame of the move under way.
    private mutating func play(_ journey: Journey, me: Player, into input: inout PlayerInput) {
        guard let terrain else { return }
        input = Terrain.input(for: journey.link, body: me, startY: journey.startY, target: terrain.surfaces[journey.link.to],
                              leftGround: journey.leftGround, jumpWasDown: pressed.jump, halfWidth: terrain.halfWidth)
        if input.jump, !journey.leftGround, me.state != .suspended { wantsFullHop = true }
    }

    /// Where the way to a point goes next from here: the takeoff of the first move off this
    /// surface, or the point itself if it's on it.
    func nextStepX(toward point: Vec2, match: Match, me: Player) -> Double {
        guard let terrain, let goal = terrain.standing(nearest: point) else { return point.x }
        // In the air, where the move under way comes down, or straight on.
        guard let here = surface(of: me, in: match) else { return journey?.started == true ? journey!.link.landing : me.position.x }
        if here == goal.surface { return point.x }
        // No way now, a tornado down: nowhere to go but here.
        guard let link = terrain.route(from: here, to: goal.surface, usable: { usable($0, $1, match) })?.first else { return me.position.x }
        return abs(link.takeoff - me.position.x) > 3 ? link.takeoff : link.landing
    }

    /// Along the ground to `x`: running when it's far, walking when it's close.
    @discardableResult
    func walk(to x: Double, me: Player, into input: inout PlayerInput, near: Double = 4) -> Bool {
        let dx = x - me.position.x
        if abs(dx) > 40 {
            input.stick = Vec2(x: dx > 0 ? 1 : -1, y: 0)
        } else if abs(dx) > near {
            input.stick = Vec2(x: dx > 0 ? 0.5 : -0.5, y: 0)
        } else {
            return true
        }
        return false
    }

    /// Falling toward lava with nothing to land on: the jump that's left, toward the nearest ground.
    private func rescueFromLava(match: Match, me: Player, into input: inout PlayerInput) {
        guard let terrain, let lava = terrain.lava, !me.grounded, me.state != .suspended, me.velocity.y < 0,
              me.position.y < lava + 45, !terrain.ground(under: me.position.x, below: me.position.y),
              let nearest = terrain.standing(nearest: Vec2(x: me.position.x, y: me.position.y + 20)) else { return }
        let dx = nearest.x - me.position.x
        input.stick = Vec2(x: abs(dx) > 2 ? (dx > 0 ? 1 : -1) : 0, y: 0)
        if me.jumpsLeft > 0 { tapJump(&input) }
    }

    /// Held in a tornado that lets go within this many frames, it's time to be out of it.
    static let tornadoLeaveFrames = 60

    /// Held in a tornado about to burst, sink or go fire: out of it now, onto solid ground, the
    /// way toward where it's headed if there's a choice. True while it's doing that.
    mutating func leaveTornado(_ match: Match, me: Player, toward goal: Vec2, into input: inout PlayerInput) -> Bool {
        guard let terrain, me.state == .suspended, let here = surface(of: me, in: match),
              !(0...Opponent.tornadoLeaveFrames).allSatisfy({ TornadoRules.holds(at: match.frame + $0) && !TornadoRules.isFire(at: match.frame + $0) })
        else { return false }
        let ways = terrain.links(from: here).filter { terrain.surfaces[$0.to].tornado == nil }
        guard let way = ways.min(by: { abs(terrain.surfaces[$0.to].clamp(goal.x) - goal.x) + $0.cost < abs(terrain.surfaces[$1.to].clamp(goal.x) - goal.x) + $1.cost })
        else { return false }
        if abs(me.position.x - way.takeoff) > 2 {
            // Let the pull bring it to the middle the jump was tried from.
            journey = nil
            input = PlayerInput()
            return true
        }
        journey = Journey(from: here, link: way, deadline: match.frame + Opponent.journeySpareFrames * 3, started: true, startedAt: match.frame, startY: me.position.y)
        play(journey!, me: me, into: &input)
        return true
    }

    /// A strike or an icicle this close is stepped out from under.
    static let hazardLeadFrames = 45

    /// On the ground, out from under what's about to come down: the lightning's line once it's
    /// close to striking, an icicle falling toward it or about to drop over it. Out the nearer
    /// side, or the way it was going if that's out too; and not into one it isn't under.
    func dodgeHazards(_ match: Match, me: Player, into input: inout PlayerInput) {
        guard me.grounded, let terrain else { return }
        let reach = terrain.halfWidth + 2
        var lines: [ClosedRange<Double>] = []
        if let warning = match.lightningWarning, warning.framesLeft <= Opponent.hazardLeadFrames, me.position.y >= warning.target.y - 1 {
            lines.append((warning.target.x - LightningRules.halfWidth - reach)...(warning.target.x + LightningRules.halfWidth + reach))
        }
        let head = me.position.y + me.spec.bodyHeight
        for (index, icicle) in match.icicles.enumerated() where match.stage.icicleSockets.indices.contains(index) {
            let socket = match.stage.icicleSockets[index]
            let tip = icicle.falling ?? socket
            guard tip.y > me.position.y else { continue }
            // Frames till it's down to head height, falling as the ball falls.
            var height = tip.y - head, speed = icicle.fallSpeed, frames = icicle.falling == nil ? max(icicle.dropAt - match.frame, 0) : 0
            guard icicle.falling != nil || icicle.formedAt != nil else { continue }
            while height > 0, frames <= Opponent.hazardLeadFrames {
                speed = min(speed + BallRules.gravity, BallRules.fallSpeed)
                height -= speed
                frames += 1
            }
            if frames <= Opponent.hazardLeadFrames { lines.append((tip.x - IcicleRules.width / 2 - reach)...(tip.x + IcicleRules.width / 2 + reach)) }
        }
        guard !lines.isEmpty else { return }
        let x = me.position.x
        if let under = lines.first(where: { $0.contains(x) }) {
            let wanted: Double = input.stick.x == 0 ? (x - under.lowerBound < under.upperBound - x ? -1 : 1) : (input.stick.x > 0 ? 1 : -1)
            input.stick = Vec2(x: wanted, y: 0)
            input.jump = false
        } else if input.stick.x != 0, lines.contains(where: { $0.contains(x + (input.stick.x > 0 ? 6 : -6)) }) {
            input.stick.x = 0
        }
    }

    /// Where a body ends up playing an input out.
    enum Fate: Equatable { case ground, tornado, lava, unknown }

    /// Whatever it decided, it isn't to end in the lava: the input played out with a copy of the
    /// body, and if that burns, the safe one nearest it instead, a jump or the stick another way.
    mutating func keepOffTheLava(_ match: Match, me: Player, into input: inout PlayerInput) {
        guard let terrain, terrain.lava != nil else { return }
        let follow: (Player, Bool, Bool) -> PlayerInput
        if let journey, journey.started {
            let target = terrain.surfaces[journey.link.to]
            follow = { body, left, jumpWasDown in
                Terrain.input(for: journey.link, body: body, startY: journey.startY, target: target, leftGround: left || journey.leftGround,
                              jumpWasDown: jumpWasDown, halfWidth: terrain.halfWidth)
            }
        } else {
            let stick = input.stick
            let holdJump = input.jump
            follow = { body, _, _ in PlayerInput(stick: stick, jump: holdJump && body.state == .jumpSquat) }
        }
        if fate(of: input, then: follow, me: me, match: match) != .lava { return }
        var best: (input: PlayerInput, score: Double)?
        for stickX in [input.stick.x == 0 ? 0 : (input.stick.x > 0 ? 1 : -1), -1, 0, 1] as [Double] {
            for jump in [false, true] where !jump || (me.jumpsLeft > 0 && !pressed.jump) {
                let option = PlayerInput(stick: Vec2(x: stickX, y: 0), aim: input.aim, jump: jump)
                let holdJump = option.jump
                let outcome = fate(of: option, then: { body, _, _ in PlayerInput(stick: Vec2(x: stickX, y: 0), jump: holdJump && body.state == .jumpSquat) },
                                   me: me, match: match)
                guard outcome != .lava else { continue }
                // Keep as close to what it wanted as it can: its way, and no jump if none's needed.
                let score = abs(stickX - input.stick.x) + (jump ? 0.5 : 0) + (outcome == .unknown ? 1 : 0)
                if best == nil || score < best!.score { best = (option, score) }
            }
        }
        if let best {
            input = best.input
            if input.jump, me.grounded { wantsFullHop = true }
        }
    }

    /// The input this frame, then `follow` each frame after, played with a copy of the body on
    /// the stage, the tornados holding and bursting as they will: where it comes down. On the
    /// ground it's only played a short way, in the air until it lands.
    func fate(of first: PlayerInput, then follow: (Player, Bool, Bool) -> PlayerInput, me: Player, match: Match) -> Fate {
        guard let lava = terrain?.lava else { return .unknown }
        var body = me
        var events: [MatchEvent] = []
        var leftGround = !me.grounded && me.state != .suspended
        var jumpWasDown = pressed.jump
        for frame in 0..<150 {
            // On the ground and still there a little way on: nothing it does now drops it.
            if frame == 24, me.grounded, body.grounded || body.state == .suspended { return .ground }
            let input = frame == 0 ? first : follow(body, leftGround, jumpWasDown)
            jumpWasDown = input.jump
            _ = body.step(input: input, stage: match.stage, events: &events)
            if body.position.y < lava { return .lava }
            let at = match.frame + frame + 1
            let fire = TornadoRules.isFire(at: at)
            let boxes = TornadoRules.holds(at: at) ? Opponent.tornadoBoxes(match.stage, at: at) : []
            let inside = boxes.first { $0.overlaps(body.body) }
            if inside != nil, fire { return .lava }
            if body.state == .suspended {
                if inside == nil {
                    body.enter(.air)
                } else if TornadoRules.sunkShare(at: at) == 0, (0...Opponent.tornadoLeaveFrames + 15).allSatisfy({ TornadoRules.holds(at: at + $0) && !TornadoRules.isFire(at: at + $0) }) {
                    // Held, and held a while yet: time to get out when it's due.
                    return .tornado
                }
            } else if body.state == .air, body.tornadoCooldown == 0, let inside {
                body.enter(.suspended)
                body.tornadoCentre = inside.center
                // Held: safe as long as it's up, not rising out of the lava, and holds a while yet.
                if TornadoRules.sunkShare(at: at) == 0, (0...Opponent.tornadoLeaveFrames + 30).allSatisfy({ TornadoRules.holds(at: at + $0) && !TornadoRules.isFire(at: at + $0) }) { return .tornado }
            }
            if !body.grounded, body.state != .suspended, body.state != .jumpSquat { leftGround = true }
            if leftGround, body.grounded { return .ground }
        }
        // Still up after all that, sliding down a wall or drifting: is there ground under it?
        return terrain?.ground(under: body.position.x, below: body.position.y) == true ? .unknown : .lava
    }

    /// The stage's tornados where they are on a frame: up, or sunk into the lava or rising.
    static func tornadoBoxes(_ stage: Stage, at frame: Int) -> [Box] {
        let share = TornadoRules.sunkShare(at: frame)
        return stage.tornados.map { box in
            let drop = (TornadoRules.sunkBottom - box.min.y) * share
            return Box(min: Vec2(x: box.min.x, y: box.min.y + drop), max: Vec2(x: box.max.x, y: box.max.y + drop))
        }
    }

    // MARK: Following things ahead

    /// The loose ball's way from here, a frame at a time: on the Hooperfish's antenna where the
    /// fish swims it, held in a tornado where it is, otherwise as the stage moves it; ending if
    /// it's caught, burnt or comes to rest.
    func ballPath(_ match: Match, frames: Int = Opponent.lookAheadFrames) -> [Vec2] {
        if match.hooperfish?.carrying == .ball, match.ball.holder == nil, var fish = match.hooperfish {
            return (0..<frames).map { _ in
                fish.step(on: match.stage)
                return fish.ballPoint
            }
        }
        var ball = match.ball
        guard ball.isLive else { return [] }
        if ball.tornadoCentre != nil || ball.frozen > 0 { return Array(repeating: ball.position, count: frames) }
        var stage = match.stage
        stage.extras += stage.ballBlockers + stage.ceilingSlopes.map(\.box)
        var events: [MatchEvent] = []
        var path: [Vec2] = []
        for _ in 0..<frames {
            _ = ball.step(stage: stage, events: &events)
            if let lava = stage.features.lavaSurface, ball.position.y < lava { break }
            path.append(ball.position)
            if ball.resting { break }
        }
        return path
    }

    /// Where a rim that moves will be, a frame at a time: Wetshot Wake's on the Hooperfish,
    /// parked off the stage while it isn't carrying it.
    func hoopPath(_ match: Match, frames: Int = Opponent.lookAheadFrames) -> [Vec2]? {
        guard var fish = match.hooperfish else { return nil }
        return (0..<frames).map { _ in
            fish.step(on: match.stage)
            return fish.carrying == .hoop && !fish.away ? fish.antenna : HighwayRules.parked
        }
    }

    // MARK: Shots

    /// The flick whose shot goes in, tried by playing the shot out: a copy of the body through
    /// the rest of the stance, off the jump if it's a jump shot, to the frame the ball leaves the
    /// hand, then the ball's own flight, the rim followed where it moves. The middle of the angles
    /// that score, or nil if none does.
    func aimByFlight(_ match: Match, me: Player, jumpShot: Bool, stanceSoFar: Int, hoop index: Int, path: [Vec2]?) -> Vec2? {
        let angles = scoringAngles(match, body: me, jumpShot: jumpShot, stanceSoFar: stanceSoFar, hoop: index, path: path, stopAtFirst: false)
        guard !angles.isEmpty else { return nil }
        let angle = angles[angles.count / 2]
        return Vec2(x: Trig.cos(angle) * aimSide(match, from: me.position, hoop: index, path: path), y: Trig.sin(angle))
    }

    private func aimSide(_ match: Match, from feet: Vec2, hoop index: Int, path: [Vec2]?) -> Double {
        let target = path?.first(where: { $0 != HighwayRules.parked }) ?? match.stage.hoops[index].position
        return target.x > feet.x ? 1 : -1
    }

    /// The shot angles, five degrees apart through the shot's range, that go in.
    func scoringAngles(_ match: Match, body: Player, jumpShot: Bool, stanceSoFar: Int, hoop index: Int, path: [Vec2]?, stopAtFirst: Bool) -> [Double] {
        var stage = match.stage
        stage.extras += stage.ballBlockers + stage.ceilingSlopes.map(\.box)
        guard (path?.contains { $0 != HighwayRules.parked } ?? true), stage.hoops[index].position != HighwayRules.parked || path != nil else { return [] }
        let sign = aimSide(match, from: body.position, hoop: index, path: path)
        var angles: [Double] = []
        var angle = BallRules.shotAngleMin
        while angle <= BallRules.shotAngleMax + 0.001 {
            let aim = Vec2(x: Trig.cos(angle) * sign, y: Trig.sin(angle))
            if let (release, velocity, frames) = shotRelease(body, stage: match.stage, aim: aim, jumpShot: jumpShot, stanceSoFar: stanceSoFar) {
                var ball = Ball(position: release)
                ball.release(from: release, velocity: velocity, by: body.index, straight: false, pace: body.spec.shotPace)
                ball.shotInFlight = true
                ball.scoring = true
                var events: [MatchEvent] = []
                for frame in 0..<200 {
                    if let path { stage.hoops[index].position = path[min(frame + frames, path.count - 1)] }
                    if let scored = ball.step(stage: stage, events: &events) {
                        if scored == index { angles.append(angle) }
                        break
                    }
                    // Done once it's come down well under the rim; still rising to it from below, not yet.
                    if ball.resting || (ball.velocity.y < 0 && ball.position.y < stage.hoops[index].position.y - 60) { break }
                }
                if stopAtFirst, !angles.isEmpty { return angles }
            }
            angle += degrees(5)
        }
        return angles
    }

    /// The shot as this body lets it go with this aim, played the way the computer plays it: the
    /// stance taken if it isn't in one, held through the windup, then let go; or for a jump shot,
    /// up out of the stance after the windup and let go once the rise slows. Where the ball
    /// leaves the hand, how fast, and how many frames from now.
    func shotRelease(_ start: Player, stage: Stage, aim: Vec2, jumpShot: Bool, stanceSoFar: Int) -> (Vec2, Vec2, Int)? {
        var body = start
        var stance = stanceSoFar
        var events: [MatchEvent] = []
        // Under water every state runs at half speed, the windup with them.
        for frame in 0..<200 {
            var input = PlayerInput(aim: aim)
            if body.state == .shootStance {
                stance += 1
                if jumpShot {
                    if body.grounded {
                        input.shoot = true
                        input.jump = stance > BallRules.shotWindupFrames
                    } else {
                        input.shoot = body.velocity.y > Opponent.jumpShotLetGo
                    }
                } else {
                    input.shoot = stance <= BallRules.shotWindupFrames + 1
                }
            } else if body.state != .shooting {
                input.shoot = frame % 2 == 0
            }
            if case .releaseShot(let velocity) = body.step(input: input, stage: stage, events: &events) {
                return (body.position + Vec2(x: 0, y: BallRules.shotReleaseHeight * body.spec.scale), velocity * body.spec.shotPace, frame + 1)
            }
        }
        return nil
    }

    /// A jump shot is let go once the rise slows to this.
    static let jumpShotLetGo = 2.4

    /// The places to try for a still rim's shots: on the surfaces in front of it, 25 to 140
    /// across from it and not far above or below it, the ones a middling distance away first.
    func spotCandidates(_ match: Match, hoop index: Int) -> [Vec2] {
        guard let terrain else { return [] }
        let hoop = match.stage.hoops[index]
        var candidates: [Vec2] = []
        for surface in terrain.surfaces where surface.tornado == nil {
            var x = surface.left
            while x <= surface.right {
                let across = (x - hoop.position.x) * (hoop.shared ? 0 : hoop.backboard.sign)
                let distance = abs(x - hoop.position.x)
                let y = surface.height(at: x)
                if across <= 0, distance >= 25, distance <= 140, y <= hoop.position.y + 10, y >= hoop.position.y - 140 {
                    candidates.append(Vec2(x: x, y: y))
                }
                x += 10
            }
        }
        return candidates.sorted { abs(abs($0.x - hoop.position.x) - 60) < abs(abs($1.x - hoop.position.x) - 60) }
    }

    /// One more place tried for the rim's shot spots: a shot off the floor there, else a jump shot.
    mutating func searchSpots(_ match: Match, me: Player, hoop index: Int) {
        if spotSearch?.hoop != index { spotSearch = SpotSearch(hoop: index, candidates: spotCandidates(match, hoop: index)) }
        guard var search = spotSearch, !search.done else { return }
        let feet = search.candidates[search.tried]
        search.tried += 1
        var body = Player(spec: me.spec, index: me.index, position: feet, facing: match.stage.hoops[index].position.x > feet.x ? .right : .left)
        body.hasBall = true
        if !scoringAngles(match, body: body, jumpShot: false, stanceSoFar: 0, hoop: index, path: nil, stopAtFirst: true).isEmpty {
            search.found.append(ShotSpot(feet: feet, jumpShot: false))
        } else if !scoringAngles(match, body: body, jumpShot: true, stanceSoFar: 0, hoop: index, path: nil, stopAtFirst: true).isEmpty {
            search.found.append(ShotSpot(feet: feet, jumpShot: true))
        }
        spotSearch = search
    }

    /// A spot for this attack among those found: one it can get to, the way not past them and
    /// them not on it, nearer better, by chance among the best few. Nil while none is found.
    mutating func pickReadSpot(_ match: Match, me: Player, human: Player, hoop: Hoop) -> ShotSpot? {
        guard let terrain, let search = spotSearch, !search.found.isEmpty, let here = surface(of: me, in: match) ?? terrain.standing(nearest: me.position)?.surface else { return nil }
        var scored: [(spot: ShotSpot, score: Double)] = []
        for spot in search.found {
            guard let goal = terrain.standing(nearest: spot.feet),
                  let way = terrain.route(from: here, to: goal.surface, usable: { usable($0, $1, match) }) else { continue }
            var score = way.reduce(0) { $0 + $1.cost } + abs(spot.feet.x - me.position.x) * 0.5
            let between = (human.position.x - me.position.x) * (spot.feet.x - human.position.x) > 0
            if between, abs(human.position.y - spot.feet.y) < 30 { score += 80 }
            if spot.feet.distance(to: human.position) < 30 { score += 120 }
            if spot.jumpShot { score += 20 }
            scored.append((spot, score))
        }
        guard !scored.isEmpty else { return nil }
        scored.sort { $0.score < $1.score }
        return scored[Int(roll(UInt32(min(3, scored.count))))].spot
    }

    /// For a rim on the move: somewhere under where it'll be in a second and a half, to its side
    /// of it this player's on, a jump shot's distance off.
    func spotUnderMovingRim(_ match: Match, me: Player, path: [Vec2]) -> ShotSpot? {
        guard let terrain else { return nil }
        let ahead = path.prefix(90).last { $0 != HighwayRules.parked } ?? path.first { $0 != HighwayRules.parked }
        guard let rim = ahead else { return nil }
        let side: Double = me.position.x >= rim.x ? 1 : -1
        guard let stand = terrain.standing(nearest: Vec2(x: rim.x + side * 45, y: rim.y - 60)) else { return nil }
        return ShotSpot(feet: Vec2(x: stand.x, y: terrain.surfaces[stand.surface].height(at: stand.x)), jumpShot: true)
    }

    /// Whether a rim is in reach of the dunk from the surface under it: its height over that
    /// ground within the jump's rise, and the stage letting it be dunked there.
    func dunkReach(_ match: Match, rim: Vec2) -> Bool {
        guard let terrain, rim != HighwayRules.parked, match.stage.dunkable(Hoop(position: rim, owner: 0, backboard: .right)),
              let stand = terrain.standing(nearest: Vec2(x: rim.x, y: rim.y - 30)), terrain.surfaces[stand.surface].tornado == nil else { return false }
        let ground = terrain.surfaces[stand.surface].height(at: stand.x)
        return abs(stand.x - rim.x) < 20 && rim.y > ground && rim.y - ground < terrain.rise + BallRules.chestHeight
    }

    // MARK: A loose ball

    /// Where to meet the loose ball: the first point along its way it can be stood under in
    /// time, walking there and jumping up to it; or where it ends up.
    func meeting(_ match: Match, me: Player) -> (stand: Vec2, ball: Vec2, rise: Int, frames: Int)? {
        guard let terrain else { return nil }
        let path = ballPath(match)
        let speed = max(me.spec.runSpeed * me.waterShare, 0.5)
        let here = surface(of: me, in: match)
        for (index, point) in path.enumerated() where index % 2 == 1 {
            guard let stand = terrain.standing(nearest: point) else { continue }
            let surface = terrain.surfaces[stand.surface]
            let ground = surface.tornado != nil ? surface.heights[0] : surface.height(at: stand.x)
            let needed = point.y - ground - BallRules.chestHeight * me.spec.scale - 4
            guard needed <= terrain.rise else { continue }
            let rise = needed > 4 ? (terrain.framesToRise(needed) ?? Int.max / 2) : 0
            let walk = Int(abs(stand.x - me.position.x) / speed) + (here == stand.surface ? 0 : 60)
            if walk + rise <= index + 1 + 4 {
                return (Vec2(x: stand.x, y: ground), point, rise, index + 1)
            }
        }
        guard let last = path.last, let stand = terrain.standing(nearest: last) else { return nil }
        let surface = terrain.surfaces[stand.surface]
        let ground = surface.tornado != nil ? surface.heights[0] : surface.height(at: stand.x)
        return (Vec2(x: stand.x, y: ground), last, 0, path.count)
    }

    /// Off the court with nobody holding the ball: to where it can be met, up for it in time.
    mutating func chaseReadBall(_ match: Match, me: Player, into input: inout PlayerInput) {
        let ball = match.ball
        if ball.respawnTimer > 0 || !ball.isLive {
            go(to: match.stage.ballSpawn, match: match, me: me, into: &input)
            return
        }
        guard let meet = meeting(match, me: me) else { return }
        if !me.grounded, me.state != .suspended {
            // Up at it: under it, and the second jump while it's still above.
            let dx = meet.ball.x - me.position.x
            if journey == nil || abs(dx) < 30 {
                input.stick = Vec2(x: abs(dx) > 3 ? (dx > 0 ? 1 : -1) : 0, y: 0)
                if meet.ball.y - me.chest.y > 10, me.jumpsLeft > 0, me.velocity.y < 0.5 { tapJump(&input) }
                rescueFromLava(match: match, me: me, into: &input)
            } else {
                go(to: meet.stand, match: match, me: me, into: &input)
            }
            return
        }
        let there = go(to: meet.stand, match: match, me: me, into: &input, near: 5)
        if there || abs(meet.stand.x - me.position.x) < 8, meet.rise > 0, meet.frames - meet.rise <= 2, me.grounded {
            fullHop(&input)
            input.stick = .zero
        }
    }
}
