/// Shielding: the snatch with the stick held up, down, forward or back, and no ball. Back turns
/// the body round at once and raises it forward; up and down tilt it 45 degrees that way. Raised
/// at the hand's full stretch, it hangs where it was raised, apart from the body, for the art's
/// length. A loose ball off it reflects; met in its first frames, the perfect shield, the ball's
/// stopped and popped up a little to be caught. A blade on it parries the swinger. A snatch, a
/// thrown ball or another shield where it is breaks it. Raised on another body, it pushes it
/// away, as the change into FloState's burst does, without a hit.
public enum ShieldAim: Equatable {
    case forward, up, down
}

public struct Shield: Equatable {
    public let owner: Int
    public let centre: Vec2
    /// The way its face points: the owner's facing, tilted 45 degrees up or down for those.
    public let normal: Vec2
    /// Its turn from upright, radians, anticlockwise: the tilt, mirrored for facing left.
    public let tilt: Double
    public var age = 0

    /// Its box's own axes: across it, and up it.
    var across: Vec2 { Vec2(x: Trig.cos(tilt), y: Trig.sin(tilt)) }
    var up: Vec2 { Vec2(x: -Trig.sin(tilt), y: Trig.cos(tilt)) }

    /// Whether a circle here this big touches it.
    public func touches(_ point: Vec2, radius: Double) -> Bool {
        let offset = point - centre
        return abs(offset.dot(across)) <= ShieldRules.size.x / 2 + radius && abs(offset.dot(up)) <= ShieldRules.size.y / 2 + radius
    }

    /// Its four corners, for drawing its box and for meeting other boxes.
    public var corners: [Vec2] {
        let a = across * (ShieldRules.size.x / 2), b = up * (ShieldRules.size.y / 2)
        return [centre - a - b, centre + a - b, centre + a + b, centre - a + b]
    }

    /// Whether it meets a box: no line along either's axes parts them.
    public func overlaps(_ box: Box) -> Bool {
        let boxCorners = [box.min, Vec2(x: box.max.x, y: box.min.y), box.max, Vec2(x: box.min.x, y: box.max.y)]
        return Shield.parted(corners, boxCorners, along: [Vec2(x: 1, y: 0), Vec2(x: 0, y: 1), across, up]) == false
    }

    public func overlaps(_ other: Shield) -> Bool {
        Shield.parted(corners, other.corners, along: [across, up, other.across, other.up]) == false
    }

    private static func parted(_ first: [Vec2], _ second: [Vec2], along axes: [Vec2]) -> Bool {
        axes.contains { axis in
            let a = first.map { $0.dot(axis) }, b = second.map { $0.dot(axis) }
            return a.max()! < b.min()! || b.max()! < a.min()!
        }
    }
}

public enum ShieldRules {
    /// The stick past this along one way picks the shield over the snatch.
    public static let stickThreshold = 0.5
    /// Its box, in units: shield.png drawn at half its size.
    public static let size = Vec2(x: 12, y: 16)
    /// shield.png's 24 frames at 15 a second, in sim frames: its whole life.
    public static let sheetFrames = 24
    public static let sheetFramesPerSecond = 15
    public static var lifeFrames: Int { sheetFrames * 60 / sheetFramesPerSecond }
    /// Met in this many frames of its raising, the ball's stopped and popped up this fast.
    public static let perfectFrames = 6
    public static let perfectPop = 3.0
    /// Its tilt for up and down.
    public static let tiltDegrees = 45.0
    /// A body it's raised on is pushed away this fast, and a unit up, unhit.
    public static let bodyPush = 3.0
    /// Breaking another's shield with a snatch or a throw earns this much FLO.
    public static let breakFlo = 10
    /// A down-shield on the ground or a body hops its raiser this share of the double jump's height.
    public static let hopHeightShare = 0.5
    /// Its middle from the hand at full stretch, in units: along its face's way, and across it
    /// (up, for one raised forward). On the debug sliders.
    nonisolated(unsafe) public static var handOffset = Vec2(x: 0, y: 0)

    /// What a snatch press with this stick raises, if a shield: its aim, and whether the body turns round first.
    public static func aim(stick: Vec2, facing: Facing) -> (aim: ShieldAim, turns: Bool)? {
        let x = abs(stick.x), y = abs(stick.y)
        if x >= y, x >= stickThreshold { return (.forward, stick.x * facing.sign < 0) }
        if y > x, y >= stickThreshold { return (stick.y > 0 ? .up : .down, false) }
        return nil
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
        // Across its face, the way that's up for one raised forward, whichever way it faces.
        let aside = Vec2(x: -normal.y * side, y: normal.x * side)
        let centre = player.handCatchPoint + normal * ShieldRules.handOffset.x + aside * ShieldRules.handOffset.y
        let shield = Shield(owner: index, centre: centre, normal: normal, tilt: radians * side)
        events.append(.shieldRaised(player: index, at: centre))
        // Two in one place break each other.
        if let met = shields.firstIndex(where: { $0.overlaps(shield) }) {
            let other = shields.remove(at: met)
            events.append(.shieldBroken(player: other.owner, at: other.centre))
            events.append(.shieldBroken(player: index, at: centre))
            return
        }
        shields.append(shield)
        // Down onto the ground or a body: a hop off it, a jump to spare.
        let corners = shield.corners
        let bounds = Box(min: Vec2(x: corners.map(\.x).min()!, y: corners.map(\.y).min()!), max: Vec2(x: corners.map(\.x).max()!, y: corners.map(\.y).max()!))
        if aim == .down, stage.overlapsSolid(bounds) || players.indices.contains(where: { $0 != index && shield.overlaps(players[$0].body) }) {
            players[index].shieldHop()
            events.append(.doubleJumped(player: index))
        }
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

    /// The loose ball meeting a shield face on: a thrown one breaks it; otherwise it reflects,
    /// or met in the shield's first frames it's stopped and popped up.
    mutating func shieldTheBall() {
        guard !shields.isEmpty, ball.isLive, ball.holder == nil, ball.tether == nil, ball.frozen == 0 else { return }
        guard let number = shields.firstIndex(where: { $0.touches(ball.position, radius: BallRules.radius) && ball.velocity.dot($0.normal) < 0 }) else { return }
        let shield = shields[number]
        if ball.thrown {
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
    }
}
