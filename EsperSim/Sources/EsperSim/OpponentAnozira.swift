import Foundation

/// Anozira's road (`RoadRules`): run on while there's FLO, but out of it the body slides and can't
/// take the ball, and holding it there spills it; a pothole run into strips and trips. So off the
/// road onto the car or the hoop truck when it's out of FLO or the ball's about to spill, and over
/// every pothole coming at it.
extension Opponent {
    /// Holding the ball on the road with this little FLO left: up off it before it spills.
    static let roadFloReserve = 3
    /// A pothole this far ahead of the body's front, units, is hopped: in the air before it's under it.
    static let potholeHopAhead: ClosedRange<Double> = 8...40
    /// A dribble kept this far in from a top's edge, units, the top moving under it.
    static let dribbleEdgeMargin = 4.0

    /// Standing on the road's floor.
    static func onRoad(_ me: Player, match: Match) -> Bool {
        match.stage.features.roadSlides && me.grounded && abs(me.position.y - match.stage.floorTop) < 0.01
    }

    /// Out of FLO on the road, sliding (or tripped by a pothole), or about to spill the ball there:
    /// a hop up onto the nearest top it reaches, the car's or the truck's, steered onto it, the
    /// second jump if it's falling short. True while it's doing that.
    mutating func keepOffTheRoad(_ match: Match, me: Player, into input: inout PlayerInput) -> Bool {
        guard match.stage.features.roadSlides else { mount = nil; return false }
        let tops = match.stage.oneWayBoxes
        if me.grounded, me.state != .jumpSquat, !Opponent.onRoad(me, match: match) { mount = nil }
        let sliding = Opponent.onRoad(me, match: match) && (me.roadSliding || me.roadTripped)
        let spilling = Opponent.onRoad(me, match: match) && me.hasBall && me.flo <= Opponent.roadFloReserve
        // Coming down onto the road with the ball and no FLO for it: it'd slide, and spill.
        let landingShort = !me.grounded && me.velocity.y < 0 && me.hasBall && me.flo <= Opponent.roadFloReserve
            && me.position.y - match.stage.drop(fromX: me.position.x, y: me.position.y) <= match.stage.floorTop + 0.01
        if mount == nil, sliding || spilling || landingShort {
            let reach = terrain?.rise ?? 40
            let from = me.grounded ? me.position.y : match.stage.floorTop
            mount = tops.indices.filter { tops[$0].max.y > from && tops[$0].max.y - from <= reach && (me.grounded || tops[$0].max.y < me.position.y) }
                .min { abs((tops[$0].min.x + tops[$0].max.x) / 2 - me.position.x) < abs((tops[$1].min.x + tops[$1].max.x) / 2 - me.position.x) }
        }
        guard let target = mount, tops.indices.contains(target) else { mount = nil; return false }
        let top = tops[target]
        let dx = (top.min.x + top.max.x) / 2 - me.position.x
        input.stick = Vec2(x: abs(dx) > 3 ? (dx > 0 ? 1 : -1) : 0, y: 0)
        if me.grounded {
            // A press, not the button held from before.
            if !pressed.jump { fullHop(&input) }
        } else if me.velocity.y < 0.5, me.jumpsLeft > 0, me.position.y < top.max.y + 2 {
            tapJump(&input)
        }
        return true
    }

    /// Running on the road with a pothole coming: the full hop, whatever else it was doing, so it
    /// passes under rather than tripping it and taking the ball.
    mutating func hopThePotholes(_ match: Match, me: Player, into input: inout PlayerInput) {
        guard match.stage.features.roadSlides, me.roadRunning, me.state == .run else { return }
        let front = me.body.max.x
        guard match.potholes.contains(where: { Opponent.potholeHopAhead.contains($0 - front) }) else { return }
        // The button let go first if it's still down, so the next frame's is a press.
        if pressed.jump { input.jump = false } else { fullHop(&input) }
    }

    /// The idle dribble's reach ahead, art pixels, for a body not dribbling yet (out of a stance).
    static let idleDribbleReach = Player.idleDribbleReach

    /// On a top, the car's or the truck's, with the ball: whether its dribble, the stick carrying it
    /// on `stickX`, would come down on the road, which takes it out of the hands.
    static func dribbleWouldSpill(_ match: Match, me: Player, stickX: Double) -> Bool {
        guard match.stage.features.roadSlides, me.hasBall, me.grounded, !onRoad(me, match: match) else { return false }
        let dribbling = Animation.dribbles.contains(me.animationFrame.animation)
        let reach = dribbling ? BallLandmarks.offset(me.animationFrame)?.x ?? idleDribbleReach : idleDribbleReach
        let ballX = me.position.x + (reach / 1.6 * me.spec.scale + dribbleEdgeMargin) * me.facing.sign + stickX * 6
        return me.position.y - match.stage.drop(fromX: ballX, y: me.position.y) <= match.stage.floorTop + 0.01
    }

    /// Dribbling on a top toward its edge: the bounce would land on the road and go out of the
    /// hands, so it hops down rather than walking off, or, short of FLO for the road, backs a step
    /// from the edge.
    mutating func keepTheDribbleOnTheTop(_ match: Match, me: Player, into input: inout PlayerInput) {
        guard !input.jump, [.idle, .walk, .run, .dash, .pivot].contains(me.state),
              Opponent.dribbleWouldSpill(match, me: me, stickX: input.stick.x) else { return }
        if input.stick.x != 0, me.flo > Opponent.roadFloReserve, !pressed.jump {
            fullHop(&input)
        } else {
            input.stick = Vec2(x: me.facing == .right ? -0.6 : 0.6, y: 0)
        }
    }

    /// A stance on a top's edge being called off: on the ground the dribble would come down on the
    /// road and go, so it's up off the top first, the stance held into the air, and called off there.
    mutating func keepTheStanceOnTheTop(_ match: Match, me: Player, into input: inout PlayerInput) {
        guard me.state == .shootStance, input.throwBall, !pressed.throwBall, Opponent.dribbleWouldSpill(match, me: me, stickX: 0) else { return }
        input.throwBall = false
        input.shoot = true
        if !pressed.jump { fullHop(&input) }
    }

    /// A pothole this many frames from passing under a near wheel of the vehicle it's standing on is
    /// hopped: the vehicle's jump strips whoever's on it holding the ball.
    static let bumpHopFrames: ClosedRange<Double> = 2...10

    /// Holding the ball on the car or the hoop truck with a pothole about to go under its near wheel.
    static func vehicleBumpComing(_ match: Match, me: Player) -> Bool {
        guard match.stage.features.look == .anozira, me.hasBall, me.grounded, !onRoad(me, match: match), !match.potholes.isEmpty else { return false }
        let body = me.body
        func on(_ tops: [Box], _ slopes: [Slope]) -> Bool {
            let middle = (body.min.x + body.max.x) / 2
            return tops.contains { body.min.x < $0.max.x && body.max.x > $0.min.x && abs($0.max.y - body.min.y) < 0.01 }
                || slopes.contains { $0.box.min.x <= middle && middle <= $0.box.max.x && abs($0.surface(at: middle) - body.min.y) < 0.01 }
        }
        let car = match.anoziraCar, truck = match.anoziraTruck
        let carCollision = CarRules.collision(at: car, facesRight: true)
        var wheels: [Double] = []
        if on(carCollision.tops, carCollision.slopes) { wheels += AnoziraRules.carWheels.map { car.x + $0 / 1.6 } }
        if on(truck.oneWays, [truck.windshield]) { wheels += AnoziraRules.truckWheels.map { truck.standing.x + $0 / 1.6 } }
        let speed = AnoziraRules.potholeSpeed
        return match.potholes.contains { hole in wheels.contains { bumpHopFrames.contains((hole - $0) / speed) } }
    }

    /// The ball held on a vehicle about to jump over a pothole: up off it first.
    mutating func hopTheVehicleBump(_ match: Match, me: Player, into input: inout PlayerInput) {
        guard me.state != .jumpSquat, Opponent.vehicleBumpComing(match, me: me) else { return }
        if pressed.jump { input.jump = false } else { fullHop(&input) }
    }
}
