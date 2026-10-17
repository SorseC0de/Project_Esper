/// Shielding: its own button, with no ball, out of anything neutral: forward with the stick
/// still or forward, back turning the body round first, up and down tilted 45 degrees that way.
/// It runs the snatch's timing in its own pose. Raised
/// at the hand's full stretch, it hangs where it was raised, apart from the body, for the art's
/// length. A loose ball off it reflects; met in its first frames, the perfect shield, the ball's
/// stopped and popped up a little to be caught. A blade on it parries the swinger. A snatch, a
/// thrown ball (not a floater) or another player's shield where it is breaks it. Raised on another
/// body, it pushes it away, as the change into FloState's burst does, without a hit. It's solid to
/// the other's body, so they can't dunk through it. Up or down, its raiser hops the floater's half hop.
public enum ShieldAim: Equatable, CaseIterable {
    case forward, up, down
}

public struct Shield: Equatable {
    public let owner: Int
    public let centre: Vec2
    /// The way its face points: the owner's facing, tilted 45 degrees up or down for those.
    public let normal: Vec2
    /// Its turn from upright, radians, anticlockwise: the tilt, mirrored for facing left.
    public let tilt: Double
    public var aim: ShieldAim = .forward
    public var age = 0
    /// The ball's flight it last turned: each shield turns a flight once, off it or popped up,
    /// and that flight passes it after, so it can't bounce the ball between itself and the
    /// ground or a body over and over; the next shot or throw it turns again.
    public var turnedFlight: Int?

    /// Its reach: a circle round its middle (`ShieldRules.diameter`).
    public var radius: Double { ShieldRules.diameter / 2 }

    /// Whether a circle here this big touches it.
    public func touches(_ point: Vec2, radius other: Double) -> Bool {
        (point - centre).length <= radius + other
    }

    /// Whether it meets a box: the box's nearest point to its middle within its reach.
    public func overlaps(_ box: Box) -> Bool {
        box.distance(to: centre) <= radius
    }

    public func overlaps(_ other: Shield) -> Bool {
        (other.centre - centre).length <= radius + other.radius
    }

    /// Its box round its reach, for the stage's solids.
    public var bounds: Box { Box(center: centre, width: ShieldRules.diameter, height: ShieldRules.diameter) }
}

public enum ShieldRules {
    /// The stick past this along one way picks the shield over the snatch.
    public static let stickThreshold = 0.5
    /// Its reach, a circle this wide in units, round its middle.
    public static let diameter = 24.0
    /// shield.png's 18 frames (48 by 64) at 15 a second, in sim frames: its whole life, its 11th to
    /// 14th looped this many times more on the way (the LOOPS slider; none to start).
    public static let sheetFrames = 18
    public static let sheetFramesPerSecond = 15
    public static let loopFrames = 10..<14
    nonisolated(unsafe) public static var extraLoops = 0
    public static var simFramesPerSheetFrame: Int { 60 / sheetFramesPerSecond }
    public static var lifeFrames: Int { (sheetFrames + loopFrames.count * extraLoops) * simFramesPerSheetFrame }
    /// The sheet's frame showing at this age: up to the loop's end, round the loop, then on out.
    public static func sheetFrame(atAge age: Int) -> Int {
        let played = age / simFramesPerSheetFrame
        let looped = loopFrames.count * extraLoops
        if played < loopFrames.upperBound { return played }
        if played < loopFrames.upperBound + looped { return loopFrames.lowerBound + (played - loopFrames.upperBound) % loopFrames.count }
        return min(played - looped, sheetFrames - 1)
    }
    /// The ball off an up shield goes out at least this far from straight up, the raiser's way.
    public static let upOutwardDegrees = 5.0
    /// Met in this many frames of its raising, the ball's stopped and popped up this fast.
    public static let perfectFrames = 6
    public static let perfectPop = 3.0
    /// Its tilt for up and down.
    public static let tiltDegrees = 45.0
    /// A body it's raised on is pushed away this fast, and a unit up, unhit.
    public static let bodyPush = 3.0
    /// Breaking another's shield with a snatch or a throw earns this much FLO.
    public static let breakFlo = 10
    /// Its middle from the hand at full stretch, for each aim, in art pixels (whole, as the
    /// sliders have them): x the way the body faces, y up. In units by `handOffset`.
    nonisolated(unsafe) public static var handOffsetPixels: [ShieldAim: Vec2] = [.forward: Vec2(x: 8, y: 0), .up: Vec2(x: 0, y: 14), .down: Vec2(x: 0, y: -14)]
    public static let pixelsPerUnit = 1.6
    public static func handOffset(_ aim: ShieldAim) -> Vec2 { (handOffsetPixels[aim] ?? .zero) * (1 / pixelsPerUnit) }

    /// The shield this stick raises: its aim, and whether the body turns round first (back).
    public static func aim(stick: Vec2, facing: Facing) -> (aim: ShieldAim, turns: Bool) {
        let x = abs(stick.x), y = abs(stick.y)
        if y > x, y >= stickThreshold { return (stick.y > 0 ? .up : .down, false) }
        return (.forward, x >= stickThreshold && stick.x * facing.sign < 0)
    }
}

extension Match {
    /// The shield `index` raises, at their hand at full stretch.
    mutating func raiseShield(by index: Int) {
        let player = players[index]
        guard let aim = player.shieldAim else { return }
        let side = player.facing.sign
        let degrees = aim == .up ? ShieldRules.tiltDegrees : aim == .down ? -ShieldRules.tiltDegrees : 0
        let radians = degrees * .pi / 180
        let normal = Vec2(x: Trig.cos(radians) * side, y: Trig.sin(radians))
        let offset = ShieldRules.handOffset(aim)
        let centre = player.handCatchPoint + Vec2(x: offset.x * side, y: offset.y)
        let shield = Shield(owner: index, centre: centre, normal: normal, tilt: radians * side, aim: aim)
        events.append(.shieldRaised(player: index, at: centre))
        // Two in one place break each other: two of one player's don't.
        if let met = shields.firstIndex(where: { $0.owner != index && $0.overlaps(shield) }) {
            let other = shields.remove(at: met)
            events.append(.shieldBroken(player: other.owner, at: other.centre))
            events.append(.shieldBroken(player: index, at: centre))
            return
        }
        shields.append(shield)
        // Up or down: the floater's half hop, a jump to spare.
        if aim != .forward { players[index].shieldHop() }
        // Raised on another body, it pushes it away, unhit.
        for other in players.indices where other != index && shield.overlaps(players[other].body) {
            let away = players[other].body.center - centre
            let direction = away.length > 0.01 ? away * (1 / away.length) : normal
            strip(other, by: index, knock: direction * ShieldRules.bodyPush + Vec2(x: 0, y: 1), stun: false)
        }
    }

    /// The shields age and go; a blade on one parries its swinger, a snatch on one breaks it.
    mutating func stepShields() {
        guard !shields.isEmpty else { return }
        for index in shields.indices { shields[index].age += 1 }
        shields.removeAll { $0.age >= ShieldRules.lifeFrames }
        var broken: [(number: Int, by: Int)] = []
        for (number, shield) in shields.enumerated() {
            for other in players.indices where other != shield.owner {
                if let blade = players[other].slashHitbox, shield.overlaps(blade) {
                    players[other].slashHit = true
                    parry(other, by: shield.owner)
                } else if let reach = players[other].snatchHitbox, shield.overlaps(reach) || shield.touches(players[other].handCatchPoint, radius: BallRules.handCatchRadius) {
                    broken.append((number, other))
                }
            }
        }
        for (number, by) in broken.reversed() where shields.indices.contains(number) {
            let shield = shields.remove(at: number)
            events.append(.shieldBroken(player: shield.owner, at: shield.centre))
            earnFlo(ShieldRules.breakFlo, by: by, at: shield.centre)
        }
    }

    /// The loose ball meeting a shield face on: a thrown one breaks it, but a floater; otherwise it reflects,
    /// or met in the shield's first frames it's stopped and popped up.
    /// Along the ball's whole path this frame, from `from`, so a fast one can't jump past it.
    mutating func shieldTheBall(from start: Vec2) {
        guard !shields.isEmpty, ball.isLive, ball.holder == nil, ball.tether == nil, ball.frozen == 0 else { return }
        let path = ball.position - start
        /// Where along the path it comes nearest a shield's middle.
        func nearest(_ shield: Shield) -> Vec2 {
            let length = path.dot(path)
            guard length > 1e-9 else { return ball.position }
            let share = Swift.min(Swift.max((shield.centre - start).dot(path) / length, 0), 1)
            return start + path * share
        }
        guard let number = shields.firstIndex(where: { shield in
            shield.turnedFlight != ball.flight && shield.touches(nearest(shield), radius: BallRules.radius) && ball.velocity.dot(shield.normal) < 0
        }) else { return }
        shields[number].turnedFlight = ball.flight
        let shield = shields[number]
        // Met where its path first touched: put back there to turn.
        ball.position = nearest(shield)
        if ball.thrown, !ball.floaterShot {
            shields.remove(at: number)
            events.append(.shieldBroken(player: shield.owner, at: shield.centre))
            if let thrower = ball.lastTouched, thrower != shield.owner { earnFlo(ShieldRules.breakFlo, by: thrower, at: shield.centre) }
        } else if shield.age < ShieldRules.perfectFrames {
            ball.popOffShield(up: ShieldRules.perfectPop)
            events.append(.shieldPerfect(player: shield.owner, at: ball.position))
        } else {
            ball.reflect(off: shield.normal)
            events.append(.shieldReflected(player: shield.owner, at: ball.position))
        }
        // An up shield sends it out its raiser's way, never straight up and back through a rim under it.
        if shield.aim == .up {
            let side = shield.normal.x < 0 ? -1.0 : 1.0
            let speed = ball.velocity.length
            let least = Trig.sin(degrees(ShieldRules.upOutwardDegrees))
            if speed > 1e-6, ball.velocity.x * side < speed * least {
                ball.velocity = Vec2(x: side * speed * least, y: (ball.velocity.y < 0 ? -1 : 1) * speed * Trig.cos(degrees(ShieldRules.upOutwardDegrees)))
            }
        }
    }
}
