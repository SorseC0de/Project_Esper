/// Shielding: on defence, the up-snatch (or the touch pad's shortcut), out of anything neutral.
/// The body flipjumps back, a preset arc gravity doesn't touch, then tumbles till it lands. The
/// shield goes round the body, travelling with it, out the way it faced: from straight below to
/// straight above, its face turning from 60 degrees down through straight out to 60 up (the plate
/// 30 off flat at either end). Another's body inside its reach is shoved out. Its reach is a circle round the body's middle (SHIELD REACH). A
/// loose ball coming in is flicked off along the shield's face as it is then; met in its first
/// frames, the perfect shield, the ball's stopped and popped up a little to be caught. A blade in
/// it parries the swinger. A snatch or a thrown ball (not a floater) breaks it and stuns the
/// shielder: snatch beats shield, shield beats slash, slash beats snatch. Thrown powers stop on
/// it, or perfectly met turn back the way they came, the shielder's. Another player's shield
/// where it's raised is a shieldclash. Raised on another body, it pushes it away, without a hit.
/// It's solid to the other's body, so they can't dunk through it, and shoves one inside it out.
public struct Shield: Equatable {
    public let owner: Int
    /// Its middle, and its reach's: the raiser's body's, wherever it's got to.
    public var pivot: Vec2
    /// The way the raiser faced, 1 or -1: the shield's on that side.
    public let side: Double
    public var age = 0
    /// The ball's flight it last turned: each shield turns a flight once, off it or popped up,
    /// and that flight passes it after, so it can't bounce the ball between itself and the
    /// ground or a body over and over; the next shot or throw it turns again.
    public var turnedFlight: Int?
    /// The beams it has met, each turned back or stopped once.
    public var metBeams: [Int] = []
    /// Its reach, and its picture's size against the plain one's: Guarderade's bigger.
    public var reach = ShieldRules.reach
    public var pictureScale = 1.0
    /// Shelter Seltzer's snatch's guard: frames it lingers on once the arc's time is done, left
    /// at the hand, still a shield.
    public var lingerFrames = 0
    /// Shelter Seltzer's shieldflip: as this one leaves, a planted one is left where it ended.
    public var leavesPlanted = false
    /// That planted one: already whole, at the arc's end and its last angle, still, for
    /// `ShieldRules.shelterLingerFrames`, then it plays out. No perfect window of its own.
    public var planted = false
    /// Shelter Seltzer's raised by a snatch: a guard only, neither solid to the other's body nor
    /// shoving it, nor pushing it as it goes up, so the snatch can still reach them; raised where
    /// the hand was as the snatch went out, and left there, its picture on that spot.
    public var guardOnly = false

    public init(owner: Int, pivot: Vec2, side: Double) {
        self.owner = owner
        self.pivot = pivot
        self.side = side
    }

    /// Its whole life: the arc, then any linger; a planted one's, its linger alone.
    public var lifeFrames: Int { planted ? ShieldRules.shelterLingerFrames : ShieldRules.flipFrames + lingerFrames }
    /// Whether it's lingering: the arc done, left where it ended.
    public var lingering: Bool { planted || age >= ShieldRules.flipFrames }
    /// The shieldflip's own shield, round the shielder's body through the flip: not one left behind.
    public var isShieldflips: Bool { !planted && !guardOnly && !lingering }
    /// Whether it's still in its first frames, where a ball's stopped and popped up.
    public var inPerfectWindow: Bool { !planted && age < ShieldRules.perfectFrames }
    /// The age its place and face are read at: held at the arc's end while it lingers, and
    /// there all along when it's planted.
    private var arcAge: Int { planted ? ShieldRules.flipFrames - 1 : min(age, ShieldRules.flipFrames - 1) }

    /// The planted shield a Shelter Seltzer shieldflip leaves where it ended.
    public var plantedCopy: Shield {
        var copy = Shield(owner: owner, pivot: pivot, side: side)
        copy.reach = reach
        copy.pictureScale = pictureScale
        copy.planted = true
        return copy
    }

    /// Its sheet's frame now. Lingering, the whole shield's frames loop (`ShieldRules.loopFrames`)
    /// till its last few, then the sheet plays out to its end.
    public var sheetFrame: Int {
        let plain = ShieldRules.sheetFrame(atAge: age)
        guard lingerFrames > 0 || planted else { return plain }
        let endFrames = ShieldRules.sheetFrames - ShieldRules.loopFrames.upperBound
        let endSimFrames = Int((Double(endFrames) * 60 / ShieldRules.sheetFramesPerSecond).rounded(.up))
        if age >= lifeFrames - endSimFrames {
            let into = Int(Double(age - (lifeFrames - endSimFrames)) * ShieldRules.sheetFramesPerSecond / 60)
            return min(ShieldRules.loopFrames.upperBound + into, ShieldRules.sheetFrames - 1)
        }
        // Planted, it's whole from its first frame: the loop from the start.
        if planted {
            let into = Int(Double(age) * ShieldRules.sheetFramesPerSecond / 60)
            return ShieldRules.loopFrames.lowerBound + into % ShieldRules.loopFrames.count
        }
        guard plain >= ShieldRules.loopFrames.lowerBound else { return plain }
        let loopStartAge = Int((Double(ShieldRules.loopFrames.lowerBound) * 60 / ShieldRules.sheetFramesPerSecond).rounded(.up))
        let into = Int(Double(age - loopStartAge) * ShieldRules.sheetFramesPerSecond / 60)
        return ShieldRules.loopFrames.lowerBound + into % ShieldRules.loopFrames.count
    }

    /// How far round it's gone at an age, 0 to 1 over the flip.
    public static func share(atAge age: Int) -> Double {
        min(max(Double(age) / Double(max(ShieldRules.flipFrames - 1, 1)), 0), 1)
    }
    /// Where it is round the body, radians up from straight out: straight below to straight above.
    public static func place(atAge age: Int) -> Double { degrees(-90 + 180 * share(atAge: age)) }
    /// The way its face points, radians up from straight out.
    public static func faceAngle(atAge age: Int) -> Double {
        degrees(ShieldRules.endFaceDegrees * (2 * share(atAge: age) - 1))
    }
    public var centre: Vec2 {
        guard !guardOnly else { return pivot }
        let place = Shield.place(atAge: arcAge)
        return pivot + Vec2(x: Trig.cos(place) * side, y: Trig.sin(place)) * ShieldRules.arcRadius
    }
    /// The way its face points: the way the ball off it goes.
    public var normal: Vec2 {
        // A snatch's guard stands upright, facing straight out, the whole time.
        let angle = guardOnly ? 0 : Shield.faceAngle(atAge: arcAge)
        return Vec2(x: Trig.cos(angle) * side, y: Trig.sin(angle))
    }
    /// Its turn from upright, radians, anticlockwise, mirrored for facing left.
    public var tilt: Double { guardOnly ? 0 : Shield.faceAngle(atAge: arcAge) * side }

    /// Whether a circle here this big touches its reach.
    public func touches(_ point: Vec2, radius other: Double) -> Bool {
        (point - pivot).length <= reach + other
    }

    /// Whether it meets a box.
    public func overlaps(_ box: Box) -> Bool {
        box.distance(to: pivot) <= reach
    }

    public func overlaps(_ other: Shield) -> Bool {
        (other.pivot - pivot).length <= reach + other.reach
    }

    /// Its reach's box, for the stage's solids.
    public var walls: [Box] {
        [Box(center: pivot, width: 2 * reach, height: 2 * reach)]
    }
}

/// Exclusion: a ball only one player can take, by hand, snatch or slash, for a while loose; off
/// a perfect shield, or sniped by Pulsepistol Punch. It glows and trails white meanwhile.
public enum ExclusionRules {
    /// A second.
    public static let frames = 60
}

public enum ShieldRules {
    /// The stick past this, up more than across, makes the snatch the shield on defence.
    public static let stickThreshold = 0.5
    /// The flipjump's frames, the shield's whole arc over them, player_dbl_jump played backward
    /// across them (FLIP FRAMES).
    nonisolated(unsafe) public static var flipFrames = 36
    /// The flipjump's preset arc, in units: this far back, peaking this high over where it
    /// started, back down to that height at its end (FLIP BACK, FLIP HEIGHT).
    nonisolated(unsafe) public static var flipBack = 50.0
    nonisolated(unsafe) public static var flipHeight = 40.0
    /// Where the flip's arc has the body after a share of it, from where it started: back the
    /// way the body faces away from, up and down again.
    public static func flipOffset(share: Double, side: Double) -> Vec2 {
        Vec2(x: -side * flipBack * share, y: flipHeight * 4 * share * (1 - share))
    }
    /// Its picture this far from the body's middle (SHIELD DISTANCE), its face turned at most
    /// this far from straight out, at the start and the end.
    nonisolated(unsafe) public static var arcRadius = 16.0
    public static let endFaceDegrees = 60.0
    /// Its reach, a circle round the body's middle this wide across in radius (SHIELD REACH), and
    /// how fast a ball's flicked off it (SHIELD FLICK).
    nonisolated(unsafe) public static var reach = 20.0
    nonisolated(unsafe) public static var flickSpeed = 8.0
    /// shield.png's 18 frames, at this many a second (SHIELD FPS), its last held to the flip's end.
    /// Its seventh to sixteenth frames are the whole shield, the eleventh to sixteenth looping.
    public static let sheetFrames = 18
    public static let loopFrames = 10..<16
    /// Guarderade: the shield's reach, and its picture half again as big.
    public static let guarderadeReach = 24.0
    public static let guarderadePictureScale = 1.5
    /// Shelter Seltzer: frames the shield lingers where its arc ended.
    public static let shelterLingerFrames = 60
    nonisolated(unsafe) public static var sheetFramesPerSecond = 36.0
    public static var lifeFrames: Int { flipFrames }
    /// The sheet's frame showing at this age.
    public static func sheetFrame(atAge age: Int) -> Int {
        min(Int(Double(age) * sheetFramesPerSecond / 60), sheetFrames - 1)
    }
    /// Met in this many frames of its raising, the ball's stopped and popped up this fast.
    public static let perfectFrames = 6
    public static let perfectPop = 3.0
    /// Another's body inside its reach is shoved out this far a frame at most.
    public static let shoveSpeed = 4.0
    /// A beam turned back off a perfect shield fires this long.
    public static let turnedBeamFrames = 30

    /// Whether the stick asks for the shield with the snatch: up or down, at least as much as across.
    public static func asked(stick: Vec2) -> Bool {
        abs(stick.y) >= stickThreshold && abs(stick.y) >= abs(stick.x)
    }
}

extension Match {
    /// The shield `index` raises, about their body's middle, the way they face.
    mutating func raiseShield(by index: Int) {
        let player = players[index]
        var shield = Shield(owner: index, pivot: player.body.center, side: player.facing.sign)
        if player.spec.guarderadeLevel >= 1 {
            shield.reach = ShieldRules.guarderadeReach
            shield.pictureScale = ShieldRules.guarderadePictureScale
        }
        if player.state == .snatching {
            shield.guardOnly = true
            shield.pivot = player.handCatchPoint
            if player.spec.shelterSeltzerLevel >= 1 { shield.lingerFrames = ShieldRules.shelterLingerFrames }
        } else if player.spec.shelterSeltzerLevel >= 1 {
            shield.leavesPlanted = true
        }
        let centre = shield.centre
        events.append(.shieldRaised(player: index, at: centre))
        // Two in one place, a shieldclash: both break, a long hit stop, then both pushed apart.
        // Two of one player's don't.
        if let met = shields.firstIndex(where: { $0.owner != index && $0.overlaps(shield) }) {
            let other = shields.remove(at: met)
            let at = (other.centre + centre) * 0.5
            events.append(.shieldBroken(player: other.owner, at: other.centre))
            events.append(.shieldBroken(player: index, at: centre))
            events.append(.shieldClashed(at: at, first: other, second: shield))
            clashAt = at
            holdHitStop(HitStopRules.clashFrames)
            return
        }
        shields.append(shield)
        // Raised on another body, it's pushed, unhit, the ball let go of; shoved out of the reach
        // as the shields step. Not a snatch's guard.
        for other in players.indices where other != index && !shield.guardOnly && shield.overlaps(players[other].body) {
            strip(other, by: index, knock: nil, stun: false)
        }
    }

    /// The shields age and go; a blade on one parries its swinger, a snatch on one breaks it and
    /// stuns the shielder, countered.
    mutating func stepShields() {
        guard !shields.isEmpty else { return }
        for index in shields.indices {
            let owner = shields[index].owner
            // Its clock is its raiser's: held as theirs is under water, so it keeps pace with the flip.
            // Lingering, it's left where it was and keeps the match's time.
            if !players.indices.contains(owner) || players[owner].clockTicked || shields[index].lingering { shields[index].age += 1 }
            // Carried round the body, but not on the frame it leaves: left where it was last drawn.
            if players.indices.contains(owner), !shields[index].planted, !shields[index].guardOnly, shields[index].age < shields[index].lifeFrames {
                shields[index].pivot = players[owner].body.center
            }
        }
        // A Shelter Seltzer shieldflip leaving leaves its planted shield where it ended.
        let planting = shields.filter { $0.leavesPlanted && $0.age >= $0.lifeFrames }.map(\.plantedCopy)
        shields.removeAll { $0.age >= $0.lifeFrames }
        shields += planting
        shoveOutOfShields()
        var broken: [(number: Int, by: Int)] = []
        for (number, shield) in shields.enumerated() {
            for other in players.indices where other != shield.owner {
                if let blade = players[other].slashHitbox, shield.overlaps(blade) {
                    players[other].slashHit = true
                    parry(other, by: shield.owner)
                    if players.indices.contains(shield.owner), players[shield.owner].state == .flipJump { players[shield.owner].shieldParried = true }
                } else if let reach = players[other].snatchHitbox, shield.overlaps(reach) || shield.touches(players[other].handCatchPoint, radius: BallRules.handCatchRadius) {
                    broken.append((number, other))
                }
            }
        }
        for (number, by) in broken.reversed() where shields.indices.contains(number) {
            let shield = shields.remove(at: number)
            events.append(.shieldBroken(player: shield.owner, at: shield.centre))
            // The shielder's stunned only through the shieldflip's own shield, round the body as it
            // flips: one left behind (Shelter Seltzer's planted one, its snatch's guard) just breaks,
            // whoever raised it far off.
            if shield.isShieldflips { counter(shield.owner, by: by) }
        }
    }

    /// Another's body inside a shield's reach shoved out sideways, up to `shoveSpeed` a frame, away
    /// from its middle; never into a wall. Never up, which off a reach round the whole body would
    /// launch one standing close.
    mutating func shoveOutOfShields() {
        for shield in shields where !shield.guardOnly {
            for other in players.indices where other != shield.owner && shield.overlaps(players[other].body) {
                let body = players[other].body
                let away = body.center.x - shield.pivot.x
                let side = Swift.abs(away) > 0.01 ? (away > 0 ? 1.0 : -1.0) : shield.side
                let clear = side > 0 ? shield.pivot.x + shield.reach - body.min.x : body.max.x - (shield.pivot.x - shield.reach)
                let step = Swift.min(Swift.max(clear, 0), ShieldRules.shoveSpeed) * side
                guard step != 0, !stage.overlapsSolid(body.offset(by: Vec2(x: step, y: 0))) else { continue }
                players[other].position.x += step
            }
        }
    }

    /// Every counter, the rock-paper-scissors won (a parry among them): `loser` stunned, knocked
    /// away and nothing answering through the stun and on past it; `winner` earns the counter's
    /// FLO; a long hit stop.
    mutating func counter(_ loser: Int, by winner: Int) {
        stunAsParried(loser, by: winner)
        events.append(.countered(player: loser, by: winner, at: players[loser].chest))
        earnFlo(FloRules.counter, by: winner, at: players[loser].chest)
        holdHitStop(HitStopRules.counterFrames)
    }

    /// The parry's stun on `loser`: knocked away from `winner`, nothing answering through the
    /// stun and on past it (`ParryRules`). Every counter's, and Pulsepistol's repelling snipe's.
    mutating func stunAsParried(_ loser: Int, by winner: Int) {
        guard !untouchable(loser) else { return }
        let away = players[loser].position.x >= players[winner].position.x ? 1.0 : -1.0
        strip(loser, by: winner, knock: Vec2(x: SnatchRules.parryKnock.x * away, y: SnatchRules.parryKnock.y), flo: 0)
        players[loser].attackLockout = players[loser].hitStun + ParryRules.attackLockoutAfterStunFrames
    }

    /// A thrown power at `point`, this big, fired by `firer`, meeting another's shield: whose, and
    /// whether met in its first frames, to be turned back.
    mutating func shieldMeets(_ point: Vec2, radius: Double, firedBy firer: Int) -> (owner: Int, perfect: Bool)? {
        guard let shield = shields.first(where: { $0.owner != firer && $0.touches(point, radius: radius) }) else { return nil }
        let perfect = shield.inPerfectWindow
        events.append(perfect ? .shieldPerfect(player: shield.owner, at: point) : .powerBlocked(player: shield.owner, at: point))
        return (shield.owner, perfect)
    }

    /// A beam along from `origin` this far meeting another's shield: how far it gets, stopped
    /// there; the first time a perfect shield meets it, a beam turned back the way it came, once.
    mutating func shieldTheBeam(_ beam: Beam) -> Double {
        var travelled = 0.0
        while travelled <= beam.reach {
            let at = beam.origin + beam.direction * travelled
            if let number = shields.firstIndex(where: { $0.owner != beam.owner && $0.touches(at, radius: ZRules.halfThickness) }) {
                let shield = shields[number]
                if !shield.metBeams.contains(beam.id) {
                    shields[number].metBeams.append(beam.id)
                    if shield.inPerfectWindow, !beam.turned {
                        var turned = Beam(id: stampId(), owner: shield.owner, origin: at, direction: -beam.direction,
                                          framesLeft: ShieldRules.turnedBeamFrames)
                        turned.turned = true
                        beams.append(turned)
                        events.append(.shieldPerfect(player: shield.owner, at: at))
                    } else {
                        events.append(.powerBlocked(player: shield.owner, at: at))
                    }
                }
                return travelled
            }
            travelled += 2
        }
        return beam.reach
    }

    /// The loose ball meeting a shield face on: a thrown one breaks it, but a floater; otherwise it reflects,
    /// or met in the shield's first frames it's stopped and popped up.
    /// Along the ball's whole path this frame, from `from`, a unit at a time, so a fast one can't jump past it.
    mutating func shieldTheBall(from start: Vec2) {
        guard !shields.isEmpty, ball.isLive, ball.holder == nil, ball.tether == nil, ball.frozen == 0 else { return }
        let path = ball.position - start
        let steps = Swift.max(Int(path.length.rounded(.up)), 1)
        var met: (number: Int, at: Vec2)?
        for step in 0...steps where met == nil {
            let at = start + path * (Double(step) / Double(steps))
            // Coming in at the body, inside the reach.
            // Under Exclusion, only its own player's shields touch it.
            if let number = shields.firstIndex(where: { shield in
                ball.isOpen(to: shield.owner) && shield.turnedFlight != ball.flight && shield.touches(at, radius: BallRules.radius) && ball.velocity.dot(shield.pivot - at) > 0
            }) {
                met = (number, at)
            }
        }
        guard let met else { return }
        shields[met.number].turnedFlight = ball.flight
        let shield = shields[met.number]
        // Met where its path first touched: put back there to turn.
        ball.position = met.at
        if ball.thrown, !ball.floaterShot {
            // Snatch beats shield, and so does the throw: broken, the shielder struck and countered.
            shields.remove(at: met.number)
            events.append(.shieldBroken(player: shield.owner, at: shield.centre))
            if let thrower = ball.lastTouched, thrower != shield.owner {
                counter(shield.owner, by: thrower)
                returnThrow(to: thrower)
            }
        } else if shield.inPerfectWindow {
            ball.popOffShield(up: ShieldRules.perfectPop)
            // The shielder's now, in their colour, and theirs alone to take for a while; and no
            // basket any more: a rim turns it back rather than letting it drop in.
            ball.lastTouched = shield.owner
            ball.owned = true
            ball.exclusiveTo = shield.owner
            ball.exclusionFrames = ExclusionRules.frames
            ball.scoring = false
            events.append(.shieldPerfect(player: shield.owner, at: ball.position))
            // As a parry, the flip ends in the air with every move, not the tumble.
            if players[shield.owner].state == .flipJump { players[shield.owner].shieldParried = true }
        } else {
            // Flicked off along the shield's face as it is now, at least the flick's speed.
            ball.flick(along: shield.normal, speed: ShieldRules.flickSpeed)
            events.append(.shieldReflected(player: shield.owner, at: ball.position))
        }
    }
}
