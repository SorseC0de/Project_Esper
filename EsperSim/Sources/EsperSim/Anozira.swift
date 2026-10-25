import Foundation

/// Anozira: a desert highway at sunset, drawn whole in Aseprite (`Anozira.aseprite`, 512 by 352,
/// its [DO NOT DRAW] box the stage: 512 by 256 at 0, 80). 32 tiles by 16, the Wreck Center's
/// height and two tiles narrower; two rows of road for its floor, slid along (`RoadRules`); the car
/// on it, the car's collision (`CarRules`) moving with it as it speeds up and slows down; and one
/// rim, both players', on the back of a pickup truck (`Truck.aseprite`) that drives in from the right
/// and shifts about there, idling, the pole in its bed jostling. The truck's bed, cab roof and hood
/// are one-ways at whole tile heights, its windshield a one-way slope, carrying whoever stands on
/// them; its pole isn't solid. Its vehicles' places are the match's state alone, the same online.
public enum AnoziraRules {
    public static let columns = 32
    public static let rows = 16
    public static let floorRows = 2
    /// The car (`Car_v4`, 128 by 48, facing right), its bottom at the road's top: its left edge at
    /// `carHome` through the match's first count, then speeding up and slowing down, a new place
    /// between `carLeftMost` and `carRightMost` every `carShiftFrames`, eased there over
    /// `carMoveFrames`. Art pixels from the stage's left. The players start on it, the first on its
    /// trunk and the second on its hood (`carSpawns`, units from its picture's bottom left).
    public static let carHome = 32.0
    public static let carLeftMost = 16.0
    public static let carRightMost = 112.0
    public static let carShiftFrames = 240
    public static let carMoveFrames = 120
    public static let carSpawns = [Vec2(x: 5, y: Stage.tileSize), Vec2(x: 70, y: Stage.tileSize)]

    /// The truck's picture, 128 by 176 art pixels, its bottom at the road's top. Its left edge comes
    /// in from off the stage's right to `truckHome` over `truckEnterFrames`, `hoopTruckDelay` after the
    /// ball truck first lets the ball out (`BallTruck.swift`), then shifts about, a new place between
    /// `truckLeftMost` and `truckRightMost` every `truckShiftFrames`, eased there over
    /// `truckMoveFrames`. Art pixels from the stage's left.
    public static let truckWidth = 128.0
    public static let truckEnterFrames = 360
    public static let truckHome = 320.0
    public static let truckLeftMost = 224.0
    public static let truckRightMost = 400.0
    public static let truckShiftFrames = 180
    public static let truckMoveFrames = 90
    public static let hoopTruckDelay = 180

    /// A place that shifts: `home` before `time` 0, then every `stretch` frames a new one between
    /// `low` and `high` off the stretch alone, eased there over `moving`.
    static func shifted(_ time: Int, home: Double, low: Double, high: Double, stretch: Int, moving: Int, salt: UInt32) -> Double {
        guard time >= 0 else { return home }
        func target(_ step: Int) -> Double {
            guard step >= 0 else { return home }
            var mixed = (UInt32(truncatingIfNeeded: step) &+ salt) &* 0x9E37_79B1
            mixed = (mixed ^ (mixed >> 15)) &* 0x85EB_CA6B
            mixed ^= mixed >> 13
            return low + (high - low) * Double(mixed % 1000) / 1000
        }
        let step = time / stretch
        let share = min(Double(time % stretch) / Double(moving), 1)
        let eased = share * share * (3 - 2 * share)
        return target(step - 1) + (target(step) - target(step - 1)) * eased
    }

    /// The car's picture's bottom left, units, on a frame, its clock running from `running`; veering, units, in the rain.
    public static func car(at frame: Int, running: Int?, veer: Double = 0, swerve: Double = 0) -> Vec2 {
        let left = shifted(running.map { frame - $0 } ?? -1, home: carHome, low: carLeftMost, high: carRightMost,
                           stretch: carShiftFrames, moving: carMoveFrames, salt: 0xCA7)
        return Vec2(x: left, y: Double(floorRows) * 16) / 1.6 + Vec2(x: swerve, y: veer)
    }

    /// Idling: a pixel up every other `bobFrames`, in units.
    public static func idle(at frame: Int) -> Double { (frame / bobFrames) % 2 == 0 ? 0 : 1 / 1.6 }
    /// Idling, up a pixel and back every `bobFrames`.
    public static let bobFrames = 4
    /// The rim's middle and the pole's foot, which the pole leans about, art pixels from the
    /// truck picture's bottom left; the lean, anticlockwise, up to `leanMost`, a new one every
    /// `leanFrames`, eased into. The rim's place on RIM X and RIM Y in the pole builder.
    nonisolated(unsafe) public static var rimInTruck = Vec2(x: 4, y: 110)
    public static let poleFoot = Vec2(x: 37.5, y: 25)
    public static let leanMost = degrees(10)
    public static let leanFrames = 20
    /// The road's potholes (`pothole.aseprite`), in the near lane: now and then one comes in off the
    /// stage's right, one frame in `potholeOdds` off the frame alone, and slides left with the road,
    /// `potholeSpeed` units a frame. A vehicle's near wheel going over one jumps it: the hoop truck's
    /// pole and rim up in its bed through `hoopJump`, the car's body through `carJump` (the
    /// view's), art pixels a frame; whoever stands on it then is stripped, and so is whoever slides
    /// into one on the road.
    public static let potholeOdds: UInt32 = 200
    public static let potholeSpeed = 384 / 60 / 1.6
    public static let hoopJump: [Double] = [6, 7, 6, 5, 4, 3, 2, 1]
    public static let carJump: [Double] = [2, 3, 3, 2, 1]
    /// The near wheels' middles across, art pixels from each picture's left: the car's and the truck's.
    public static let carWheels: [Double] = [31.5, 87.5]
    public static let truckWheels: [Double] = [31.5, 87.5]

    /// The weather (`weather(at:)`): dry a long while, `dryFrames` at random, then overcast
    /// `rainFrames`, the sky turning over `rainTurnFrames` at each end, the turn the warning; the rain
    /// itself only once it's turned, coming on and off over `rainRampFrames`; the match's own time
    /// alone. While it rains the vehicles veer in their lanes, up to `veerMost` art pixels either
    /// way, a new way every `veerFrames`, and the car and the truck swerve, up to `swerveMost`
    /// across, a new way every `swerveFrames`, both eased; the sky, the drawing, the wind and the
    /// lightning are the view's.
    public static let dryFrames: ClosedRange<Int> = 2400...5400
    public static let rainFrames: ClosedRange<Int> = 1500...2700
    public static let rainTurnFrames = 240
    public static let rainRampFrames = 60
    public static let veerMost = 6.0
    public static let veerFrames = 45
    public static let swerveMost = 8.0
    public static let swerveFrames = 20
    /// The Phoenix (`Phoenix.aseprite`, 48 by 32, six frames), now and then while it's dry (one frame
    /// in `phoenixOdds`, and only with the dry spell long enough for the whole crossing): in off the
    /// stage's left, slowly across near the top, `phoenixSpeed` art pixels a frame, drifting up
    /// and down `phoenixDrift` over `phoenixDriftFrames`, its picture's foot `phoenixHeight` up, and
    /// off the right. Its tail's ring, `phoenixRing` on its picture, is a bonus rim (`Hoop.bonus`,
    /// the stage's second), `phoenixPoints` in 47 and a basket in Rounds. Through it, or someone
    /// reaching to dunk on it, and it swoops up and away, quickly, never to be scored on twice.
    public static let phoenixOdds: UInt32 = 1800
    /// Never at the match's start: not till this long after its first count.
    public static let phoenixEarliestFrames = 30 * 60
    public static let phoenixSpeed = 40.0 / 60
    public static let phoenixWidth = 48.0
    public static let phoenixHeight = 200.0
    public static let phoenixDrift = 10.0
    public static let phoenixDriftFrames = 180
    public static let phoenixRing = Vec2(x: 11.5, y: 11.5)
    public static let phoenixPoints = 5
    /// Its swoop: across this fast, art pixels a frame, and up, speeding up this much a frame.
    public static let phoenixSwoopAcross = 3.0
    public static let phoenixSwoopLift = 0.25
    public static var phoenixCrossingFrames: Int { Int(((Double(columns) * 16 + phoenixWidth * 2) / phoenixSpeed).rounded(.up)) }

    public struct Phoenix: Equatable {
        public var start: Int
        public var swoopAt: Int?

        public init(start: Int, swoopAt: Int? = nil) {
            self.start = start
            self.swoopAt = swoopAt
        }
    }

    /// The Phoenix's picture's bottom left, units, on a frame; nil once it's gone.
    public static func phoenix(_ phoenix: Phoenix, at frame: Int) -> Vec2? {
        let flown = Double(frame - phoenix.start)
        let drift = phoenixDrift * Trig.sin(2 * .pi * flown / Double(phoenixDriftFrames))
        var at = Vec2(x: -phoenixWidth + flown * phoenixSpeed, y: phoenixHeight + drift)
        if let swoop = phoenix.swoopAt {
            let since = Double(frame - swoop)
            at = at + Vec2(x: since * phoenixSwoopAcross, y: 0.5 * phoenixSwoopLift * since * since)
        }
        guard at.x < Double(columns) * 16 + phoenixWidth, at.y < Double(rows) * 16 * 2 else { return nil }
        return at / 1.6
    }

    /// While it's dry, frames till the sky starts to turn; nil while it's overcast.
    public static func dryLeft(at time: Int) -> Int? {
        guard rainForced == nil || rainForced == 0 else { return nil }
        if rainForced == 0 { return Int.max }
        guard time >= 0 else { return nil }
        var start = 0, turn = 0
        while true {
            let dry = dryFrames.lowerBound + Int(mixed(turn, salt: 0xD27) % UInt32(dryFrames.count))
            let wet = rainFrames.lowerBound + Int(mixed(turn, salt: 0x3A1) % UInt32(rainFrames.count))
            let into = time - start
            if into < dry { return dry - into }
            if into < dry + wet { return nil }
            start += dry + wet
            turn += 1
        }
    }

    /// Debug, offline: the weather held, on (1) or off (0), on the RAIN picker; nil, as it comes.
    nonisolated(unsafe) public static var rainForced: Double?
    /// A dunker hanging on the rim pulls the pole down, anticlockwise, this much more at most, this
    /// much more a frame, and lets it back as fast.
    public static let hangPullMost = degrees(10)
    public static let hangPullRate = degrees(1)
    /// Someone standing on the truck dips it this far, units.
    public static let riddenDip = 1 / 1.6
    /// A dunk off the rim: away from the backboard and up, units a frame.
    public static func dunkBounce(off rim: Hoop) -> Vec2 { Vec2(x: -rim.backboard.sign * 1.2, y: 2.5) }

    /// The truck's collision, cells from its picture's bottom-left one: the bed's three and the
    /// hood's two a row up, the cab roof's two a row over them, and the windshield's one-way slope
    /// down from the roof to the hood. Its idling isn't in it: whoever stands on it is drawn idling with it.
    public static let truckOneWays: [(column: Int, row: Int)] = [(0, 1), (1, 1), (2, 1), (6, 1), (7, 1), (3, 2), (4, 2)]
    public static let truckWindshield = (column: 5, row: 2)

    /// The truck as it stands on a frame, in units: its body's picture's bottom left, idling and
    /// dipping under a rider; where its wheels stand, and its collision, which neither; its pole's
    /// lean, the jostle and a hanging dunker's pull; and its pole's jump over a pothole.
    public struct Truck: Equatable {
        public var origin: Vec2
        public var standing: Vec2
        public var lean: Double
        public var jump: Double

        func square(_ cell: (column: Int, row: Int)) -> Box {
            let size = Stage.tileSize
            let corner = standing + Vec2(x: Double(cell.column) * size, y: Double(cell.row) * size)
            return Box(min: corner, max: corner + Vec2(x: size, y: size))
        }
        /// Its one-way tops and its windshield, where it stands.
        public var oneWays: [Box] { AnoziraRules.truckOneWays.map(square) }
        public var windshield: Slope { Slope(box: square(AnoziraRules.truckWindshield), rising: false, oneWay: true) }
    }

    /// The hoop truck on a frame, coming in from `arrival` (off the stage's right till then); jumped
    /// by the pothole it went over at `bumped`; veering, units, in the rain.
    public static func truck(at frame: Int, arrival: Int?, pull: Double = 0, ridden: Bool = false, bumped: Int? = nil, veer: Double = 0,
                             swerve: Double = 0) -> Truck {
        let units = 1 / 1.6
        let away = Double(columns) * 16
        let left: Double
        let since = arrival.map { frame - $0 } ?? -1
        if since < 0 {
            left = away
        } else if since < truckEnterFrames {
            // In from off the stage's right, slowing to a stop.
            let share = Double(since) / Double(truckEnterFrames)
            let eased = 1 - (1 - share) * (1 - share)
            left = away + (truckHome - away) * eased
        } else {
            left = shifted(since - truckEnterFrames, home: truckHome, low: truckLeftMost, high: truckRightMost,
                           stretch: truckShiftFrames, moving: truckMoveFrames, salt: 0x7A0C)
        }
        let standing = Vec2(x: left * units + swerve, y: Double(floorRows) * 16 * units + veer)
        let into = bumped.map { frame - $0 } ?? -1
        let jump = hoopJump.indices.contains(into) ? hoopJump[into] : 0
        return Truck(origin: standing + Vec2(x: 0, y: idle(at: frame) - (ridden ? riddenDip : 0)), standing: standing,
                     lean: lean(at: frame) + pull, jump: jump * units)
    }

    /// A number off a step and a salt alone, mixed, the same on every phone.
    public static func mixed(_ step: Int, salt: UInt32) -> UInt32 {
        var mixed = (UInt32(truncatingIfNeeded: step) &+ salt) &* 0x9E37_79B1
        mixed = (mixed ^ (mixed >> 15)) &* 0x85EB_CA6B
        mixed ^= mixed >> 13
        return mixed
    }

    /// The weather `time` frames into the match, each 0 to 1: how overcast the sky is, and how hard
    /// it's raining, only once it's fully overcast. Dry spells and overcast spells in turn, each its
    /// own length off its turn alone, eased on and off.
    public static func weather(at time: Int) -> (sky: Double, rain: Double) {
        if let rainForced { return (rainForced, rainForced) }
        guard time >= 0 else { return (0, 0) }
        func eased(_ share: Double) -> Double {
            let share = min(max(share, 0), 1)
            return share * share * (3 - 2 * share)
        }
        var start = 0, turn = 0
        while true {
            let dry = dryFrames.lowerBound + Int(mixed(turn, salt: 0xD27) % UInt32(dryFrames.count))
            let wet = rainFrames.lowerBound + Int(mixed(turn, salt: 0x3A1) % UInt32(rainFrames.count))
            let into = time - start - dry
            if into < 0 { return (0, 0) }
            if into < wet {
                let edge = min(into, wet - into)
                return (eased(Double(edge) / Double(rainTurnFrames)), eased(Double(edge - rainTurnFrames) / Double(rainRampFrames)))
            }
            start += dry + wet
            turn += 1
        }
    }
    public static func rain(at time: Int) -> Double { weather(at: time).rain }

    /// A vehicle's veer in its lane, units, `time` frames in, raining this hard; each vehicle its own.
    public static func veer(at time: Int, rain: Double, salt: UInt32) -> Double {
        guard rain > 0 else { return 0 }
        let way = shifted(time, home: 0, low: -1, high: 1, stretch: veerFrames, moving: veerFrames, salt: salt)
        return way * rain * veerMost / 1.6
    }

    /// The car's or the truck's swerve across, units, the same way.
    public static func swerve(at time: Int, rain: Double, salt: UInt32) -> Double {
        guard rain > 0 else { return 0 }
        let way = shifted(time, home: 0, low: -1, high: 1, stretch: swerveFrames, moving: swerveFrames, salt: salt &+ 0x5E)
        return way * rain * swerveMost / 1.6
    }

    /// The pole's lean: each `leanFrames` a new one off the frame alone, eased from the last.
    static func lean(at frame: Int) -> Double {
        func target(_ step: Int) -> Double {
            var mixed = UInt32(truncatingIfNeeded: step) &* 0x9E37_79B1
            mixed = (mixed ^ (mixed >> 15)) &* 0x85EB_CA6B
            mixed ^= mixed >> 13
            return Double(mixed % 1000) / 1000 * leanMost
        }
        let step = frame / leanFrames
        let share = Double(frame % leanFrames) / Double(leanFrames)
        let eased = share * share * (3 - 2 * share)
        return target(step) + (target(step + 1) - target(step)) * eased
    }

    /// Where the rim is, in units, with the truck as it stands: turned with the pole about its foot.
    public static func rim(on truck: Truck) -> Vec2 {
        let units = 1 / 1.6
        let fromFoot = (rimInTruck - poleFoot) * units
        let c = Trig.cos(truck.lean), s = Trig.sin(truck.lean)
        let turned = Vec2(x: fromFoot.x * c - fromFoot.y * s, y: fromFoot.x * s + fromFoot.y * c)
        return truck.origin + poleFoot * units + turned + Vec2(x: 0, y: truck.jump)
    }
}

extension Stage {
    /// Anozira (`AnoziraRules`): the road for floor, the car on it, the truck's rim anyone's.
    public static var anozira: Stage {
        let columns = AnoziraRules.columns, rows = AnoziraRules.rows
        var stage = Stage(
            columns: columns, rows: rows,
            // The truck's rim, and the Phoenix's tail's ring, away till it flies by.
            hoops: [Hoop(position: AnoziraRules.rim(on: AnoziraRules.truck(at: 0, arrival: nil)), owner: 0, backboard: .right, shared: true),
                    Hoop(position: HighwayRules.parked, owner: 0, backboard: .right, shared: true)],
            // On the car for now: the first on its trunk, the second on its hood.
            playerSpawns: AnoziraRules.carSpawns.map { AnoziraRules.car(at: 0, running: nil) + $0 },
            playerFacings: [.right, .left],
            ballSpawn: Vec2(x: 16 * tileSize, y: 8.5 * tileSize)
        )
        stage.fill(.solid, columns: 0...(columns - 1), rows: 0...(AnoziraRules.floorRows - 1))
        stage.slopes = stage.fixedSlopes
        stage.features = StageFeatures(look: .anozira)
        stage.features.seenWhole = true
        // The rim rides the truck: a dunk lands but bounces off; and the road's for sliding.
        stage.features.dunksBounce = true
        stage.features.roadSlides = true
        stage.features.threeRadius = FortySevenRules.fallbackRadius
        stage.features.ballTruck = true
        stage.hoops[1].bonus = true
        return stage
    }
}

extension Match {
    /// How overcast it is and how hard it's raining (`AnoziraRules.weather`), and each vehicle's
    /// veer and swerve in it, units.
    public var overcast: Double { anoziraStart.map { AnoziraRules.weather(at: frame - $0).sky } ?? 0 }
    public var rain: Double { anoziraStart.map { AnoziraRules.rain(at: frame - $0) } ?? 0 }
    func veer(at frame: Int, salt: UInt32) -> Double {
        guard let start = anoziraStart else { return 0 }
        return AnoziraRules.veer(at: frame - start, rain: AnoziraRules.rain(at: frame - start), salt: salt)
    }
    func swerve(at frame: Int, salt: UInt32) -> Double {
        guard let start = anoziraStart else { return 0 }
        return AnoziraRules.swerve(at: frame - start, rain: AnoziraRules.rain(at: frame - start), salt: salt)
    }
    static let carVeerSalt: UInt32 = 0xC0, truckVeerSalt: UInt32 = 0x7C, ballTruckVeerSalt: UInt32 = 0xB7

    /// The car's picture's bottom left on a frame: home through the match's first count.
    func anoziraCar(at frame: Int) -> Vec2 {
        AnoziraRules.car(at: frame, running: anoziraStart.map { $0 + countdownLength }, veer: veer(at: frame, salt: Match.carVeerSalt),
                         swerve: swerve(at: frame, salt: Match.carVeerSalt))
    }
    public var anoziraCar: Vec2 { anoziraCar(at: frame) }

    /// The hoop truck as it stands on a frame.
    func anoziraTruck(at frame: Int) -> AnoziraRules.Truck {
        AnoziraRules.truck(at: frame, arrival: hoopTruckArrives, pull: hoopTruckPull, ridden: hoopTruckRidden, bumped: truckBumpAt,
                           veer: veer(at: frame, salt: Match.truckVeerSalt), swerve: swerve(at: frame, salt: Match.truckVeerSalt))
    }
    public var anoziraTruck: AnoziraRules.Truck { anoziraTruck(at: frame) }

    /// Whoever stands on these tops or slopes.
    func riders(tops: [Box], slopes: [Slope]) -> [Int] {
        players.indices.filter { index in
            let body = players[index].body, middle = (body.min.x + body.max.x) / 2
            return players[index].grounded
                && (tops.contains { body.min.x < $0.max.x && body.max.x > $0.min.x && abs($0.max.y - body.min.y) < 0.01 }
                    || slopes.contains { $0.box.min.x <= middle && middle <= $0.box.max.x && abs($0.surface(at: middle) - body.min.y) < 0.01 })
        }
    }

    /// Anozira's vehicles this frame: the truck's rim where it has it, and how far it moved, for a
    /// shot to lead it; the truck's and the car's collision; whoever stood on either carried along.
    public mutating func placeAnoziraTruck() {
        guard stage.features.look == .anozira, !stage.hoops.isEmpty else { return }
        if anoziraStart == nil { anoziraStart = frame }
        // A dunker hanging on, past the slam, pulls the pole down; let go, it comes back up.
        let hanging = players.contains { $0.state == .dunking && $0.dunkHoop == 0 && $0.stateTimer >= BallRules.dunkFrames / 2 }
        let pullTo = hanging ? AnoziraRules.hangPullMost : 0
        hoopTruckPull += min(max(pullTo - hoopTruckPull, -AnoziraRules.hangPullRate), AnoziraRules.hangPullRate)
        let truck = anoziraTruck
        let was = stage.hoops[0].position
        stage.hoops[0].position = AnoziraRules.rim(on: truck)
        stage.hoops[0].velocity = stage.hoops[0].position - was
        // On either as it stood last frame, on a top or on a slope: carried as far as it went, across
        // and, veering in the rain, up and down.
        let before = anoziraTruck(at: frame - 1)
        let truckRiders = riders(tops: before.oneWays, slopes: [before.windshield])
        for index in truckRiders { players[index].position += truck.standing - before.standing }
        let car = anoziraCar
        let carBefore = anoziraCar(at: frame - 1)
        let wasCar = CarRules.collision(at: carBefore, facesRight: true)
        let carRiders = riders(tops: wasCar.tops, slopes: wasCar.slopes)
        for index in carRiders { players[index].position += car - carBefore }
        stepPotholes(car: car, truck: truck, carRiders: carRiders, truckRiders: truckRiders)
        hoopTruckRidden = !riders(tops: truck.oneWays, slopes: [truck.windshield]).isEmpty
        flyPhoenix()
        let carNow = CarRules.collision(at: car, facesRight: true)
        stage.oneWayBoxes = truck.oneWays + carNow.tops
        // The backboard, behind the rim: a wall to one jumping into it from the left, nothing else.
        let rim = stage.hoops[0].position
        stage.rightwardWalls = [Box(min: Vec2(x: rim.x + Stage.backboardFace, y: rim.y + Stage.backboardBottom),
                                    max: Vec2(x: rim.x + Stage.backboardFace + Stage.backboardDepth, y: rim.y + Stage.backboardTop))]
        stage.slopes = stage.fixedSlopes + [truck.windshield] + carNow.slopes
    }

    /// The Phoenix a frame on: in now and then while it's dry, with time for the whole crossing; up and
    /// away, swooping, once the sky starts to turn or someone reaches to dunk on it; its ring where
    /// it is, or away.
    mutating func flyPhoenix() {
        guard stage.hoops.count > 1, let start = anoziraStart else { return }
        if phoenix == nil, let left = AnoziraRules.dryLeft(at: frame - start), left > AnoziraRules.phoenixCrossingFrames + AnoziraRules.rainTurnFrames,
           frame - start > countdownLength + AnoziraRules.phoenixEarliestFrames, AnoziraRules.mixed(frame, salt: 0x9F0E) % AnoziraRules.phoenixOdds == 0 {
            phoenix = AnoziraRules.Phoenix(start: frame)
        }
        let was = stage.hoops[1].position
        guard var flying = phoenix, let at = AnoziraRules.phoenix(flying, at: frame) else {
            phoenix = nil
            stage.hoops[1].position = HighwayRules.parked
            stage.hoops[1].velocity = .zero
            return
        }
        let ring = at + AnoziraRules.phoenixRing / 1.6
        let reaching = players.contains { $0.hasBall && $0.state == .throwStance && $0.chest.distance(to: ring) <= BallRules.dunkRadius * $0.spec.scale }
        if flying.swoopAt == nil, overcast > 0 || reaching {
            flying.swoopAt = frame
            phoenix = flying
        }
        stage.hoops[1].position = ring
        stage.hoops[1].velocity = was == HighwayRules.parked ? .zero : ring - was
    }

    /// The potholes a frame on: in now and then off the right, slid left with the road, gone off the
    /// left. One under a near wheel of the car, the hoop truck or the ball truck jumps it, and strips
    /// whoever stood on it; one under someone running or sliding on the road strips them and trips them into the forced slide till they jump and land. Either shakes the screen.
    mutating func stepPotholes(car: Vec2, truck: AnoziraRules.Truck, carRiders: [Int], truckRiders: [Int]) {
        let speed = AnoziraRules.potholeSpeed
        let was = potholes
        potholes = potholes.map { $0 - speed }.filter { $0 > -Stage.tileSize }
        if AnoziraRules.mixed(frame, salt: 0x9077) % AnoziraRules.potholeOdds == 0 { potholes.append(stage.width + Stage.tileSize) }
        func crossed(_ x: Double) -> Bool { was.contains { $0 > x && $0 - speed <= x } }
        func strip(_ index: Int) {
            guard players[index].hasBall, ball.holder == index else { return }
            let from = players[index].heldBallPoint
            players[index].loseBall()
            players[index].hitStun = BallRules.hitStunFrames
            ball.pop(from: from)
            events.append(.roadSpilled(player: index))
        }
        if AnoziraRules.carWheels.contains(where: { crossed(car.x + $0 / 1.6) }) {
            carBumpAt = frame
            carRiders.forEach(strip)
            events.append(.potholeBump(at: car))
        }
        if AnoziraRules.truckWheels.contains(where: { crossed(truck.standing.x + $0 / 1.6) }) {
            truckBumpAt = frame
            truckRiders.forEach(strip)
            events.append(.potholeBump(at: truck.standing))
        }
        if let ballTruck, BallTruckRules.wheels.contains(where: { crossed(ballTruck.standing.x + $0 / 1.6) }) {
            ballTruckBumpAt = frame
        }
        for index in players.indices where (players[index].roadSliding || players[index].roadRunning) && !players[index].roadTripped {
            let body = players[index].body
            guard was.contains(where: { $0 - speed >= body.min.x && $0 - speed <= body.max.x && !($0 >= body.min.x && $0 <= body.max.x) }) else { continue }
            strip(index)
            players[index].roadTripped = true
            events.append(.potholeBump(at: players[index].position))
        }
    }

    /// A road's: whoever holds the ball on it spills it, stunned a moment, flashing; and a dribble
    /// bouncing down off something onto it goes out of the hands; either bounces off it.
    mutating func spillOnRoad() {
        guard stage.features.roadSlides, let holder = ball.holder, players.indices.contains(holder) else { return }
        let player = players[holder]
        if player.roadSliding {
            let from = player.heldBallPoint
            players[holder].loseBall()
            players[holder].hitStun = BallRules.hitStunFrames
            players[holder].roadSpill = RoadRules.spillFrames
            ball.release(from: from, velocity: RoadRules.bounce, by: holder, straight: false)
            events.append(.roadSpilled(player: holder))
            return
        }
        let frame = player.animationFrame
        guard player.grounded, !player.roadRunning, Animation.dribbles.contains(frame.animation), frame.animation.dribbleBounceFrames().contains(frame.frame),
              let landing = player.overhangBall(in: stage), abs(landing.y - BallRules.radius - stage.floorTop) < 0.01 else { return }
        players[holder].loseBall()
        ball.release(from: landing, velocity: RoadRules.bounce, by: holder, straight: false)
        events.append(.roadSpilled(player: holder))
    }

}

/// A road (`StageFeatures.roadSlides`): whoever's on it runs on it while they've FLO, and slides left with it
/// once they haven't; whoever holds the ball sliding on it spills it, sent up and back, north-west,
/// at `bounce` units a frame, in the stunned pose `spillFrames`, then sliding, flashing.
public enum RoadRules {
    public static let bounce = Vec2(x: -1.5, y: 3.5)
    public static let spillFrames = 12
    /// Running on it: a FLO spent every this many frames (FloState's rate), the run's cycle at this many frames a second.
    public static let runSpendFrames = FloStateRules.spendFrames
    public static let runCycleFramesPerSecond = 30.0
}
