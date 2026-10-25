import Foundation

/// The ball truck (`BallTruck.aseprite`, 160 by 80 art pixels), on a stage that has one
/// (`StageFeatures.ballTruck`; Anozira's): it brings the ball in at the start of the match and of
/// each Rounds round. Through the count it waits on the stage's right, its picture's bottom at the
/// floor's top and `fromRight` in from the stage's right edge, the ball shut in its cargo at
/// `ballInCargo`, its cargo door shut. In neutral the door opens as the count ends ("Ball Out") and
/// the ball's let out the back at `outPoint` at `outVelocity`, units a frame; going to someone (the
/// side just scored on), it opens `tossAfter` into the count and the ball's tossed into their hands
/// over `tossFrames`, rising `tossHeight` over the straight way there. `waits` after the door
/// opens it pulls away right, speeding up by `acceleration` a frame, till it's off the stage.
/// Art pixels from its picture's bottom left, but the speeds. The match's state alone, so it's the
/// same online.
public enum BallTruckRules {
    public static let width = 160.0
    public static let fromRight = 16.0
    public static let ballInCargo = Vec2(x: 60, y: 36)
    public static let outPoint = Vec2(x: 20, y: 30)
    public static let outVelocity = Vec2(x: -2.5, y: 1.5)
    public static let tossAfter = 30
    public static let tossFrames = 40
    public static let tossHeight = 24.0
    public static let waits = 40
    public static let acceleration = 0.04
    /// Its near wheels' middles across, art pixels from its picture's left.
    public static let wheels: [Double] = [47.5, 119.5]

    /// The ball truck as it stands: its body's picture's bottom left in units, idling; where its
    /// wheels stand, which don't; and whether its cargo door is open.
    public struct Truck: Equatable {
        public var origin: Vec2
        public var standing: Vec2
        public var doorOpen: Bool
    }

    /// Where it waits on a stage, its picture's bottom left in units.
    public static func parked(on stage: Stage) -> Vec2 {
        Vec2(x: stage.width - (width + fromRight) / 1.6, y: stage.floorTop)
    }
}

extension Stage {
    /// The floor's top: the solid rows along the bottom, at the left edge, from the bottom up.
    var floorTop: Double {
        var rows = 0
        while rows < self.rows, tile(column: 0, row: rows) == .solid { rows += 1 }
        return Double(rows) * Stage.tileSize
    }
}

extension Match {
    /// The ball truck as it stands this frame, or nil once it's gone (or the stage has none).
    public var ballTruck: BallTruckRules.Truck? {
        guard stage.features.ballTruck else { return nil }
        var origin = BallTruckRules.parked(on: stage)
        if let out = ballOutAt {
            let pulling = Double(max(frame - out - BallTruckRules.waits, 0))
            origin.x += 0.5 * BallTruckRules.acceleration * pulling * pulling
            guard origin.x < stage.width + Stage.tileSize * 2 else { return nil }
        } else if !ballInTruck {
            return nil
        }
        origin.y += veer(at: frame, salt: Match.ballTruckVeerSalt)
        return BallTruckRules.Truck(origin: origin + Vec2(x: 0, y: AnoziraRules.idle(at: frame)), standing: origin, doorOpen: ballOutAt != nil)
    }

    /// The ball on its way out of the truck into someone's hands: drawn trailing, as a throw is.
    public var ballTossing: Bool { ballInTruck && ballOutAt != nil && ballTruckReceiver != nil }

    /// The ball shut in the ball truck, which waits on the right through the count: for whoever's
    /// to have it, or let out loose in neutral.
    mutating func shutBallInTruck(for receiver: Int?) {
        ballInTruck = true
        ballOutAt = nil
        ballTruckReceiver = receiver
        if let receiver, players.indices.contains(receiver) { players[receiver].hasBall = false }
        ball.respawn(at: BallTruckRules.parked(on: stage) + BallTruckRules.ballInCargo / 1.6)
    }

    /// A frame of the ball in the truck's hands: waiting in the cargo, then let out the back as the
    /// count ends, or tossed early in the count to whoever's to have it and given them.
    mutating func holdBallInTruck() {
        let parked = BallTruckRules.parked(on: stage)
        let out = parked + BallTruckRules.outPoint / 1.6
        guard let released = ballOutAt else {
            let due = ballTruckReceiver == nil ? countdown == 0 : countdownLength - countdown >= BallTruckRules.tossAfter
            guard due else {
                ball.position = parked + BallTruckRules.ballInCargo / 1.6
                ball.velocity = .zero
                return
            }
            ballOutAt = frame
            // Anozira's hoop truck comes in a while after the match's first ball.
            if stage.features.look == .anozira, hoopTruckArrives == nil { hoopTruckArrives = frame + AnoziraRules.hoopTruckDelay }
            ball.position = out
            if ballTruckReceiver == nil {
                ballInTruck = false
                ball.velocity = BallTruckRules.outVelocity
            } else {
                ball.velocity = .zero
            }
            return
        }
        guard let receiver = ballTruckReceiver, players.indices.contains(receiver) else {
            ballInTruck = false
            return
        }
        // Over to their hands, arcing up over the straight way there.
        let share = min(Double(frame - released) / Double(BallTruckRules.tossFrames), 1)
        let hands = players[receiver].heldBallPoint
        let was = ball.position
        ball.position = out + (hands - out) * share + Vec2(x: 0, y: BallTruckRules.tossHeight / 1.6 * 4 * share * (1 - share))
        ball.velocity = ball.position - was
        guard share >= 1 else { return }
        ballInTruck = false
        ballTruckReceiver = nil
        ball.velocity = .zero
        ball.holder = receiver
        players[receiver].hasBall = true
        ball.position = hands
    }
}
