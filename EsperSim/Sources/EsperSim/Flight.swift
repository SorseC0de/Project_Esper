import Foundation

/// Flight: the aisle of a plane, drawn whole in Aseprite (`Flight_Map.aseprite`, 1248 by 576,
/// four of its pixels an art pixel): 312 by 144 art pixels, 19 and a half tiles by 9, on a
/// grid of 20 whose last half column is walled off. Two rows of floor; the rims at the ends two
/// thirds of the way up; the starts two and a half tiles in; the ball in the open bin over the
/// middle. The plane pitches now and then, which leans gravity, and a cart rolls the aisle with it.
public enum FlightRules {
    public static let columns = 20
    public static let rows = 9
    public static let width = 195.0
    public static let floorRows = 2
    public static let rimHeight = 65.0
    public static let rimInset = 5.0
    public static let startInset = 25.0
    public static let ballHeight = 60.0

    /// The pitch: its most, in degrees, and the leans come in tenths of it. A lean's round:
    /// the lean over `tiltOverFrames`, held `tiltHoldFrames`, back level over `tiltOverFrames`
    /// again, and level for `levelFrames` before the next is rolled; one round in all.
    public static let tiltMaxDegrees = 60.0
    public static var tiltMax: Double { tiltMaxDegrees * .pi / 180 }
    /// Pitched this far or more, the floor is a slide: nobody stands on it.
    public static let slideTiltDegrees = 45.0
    public static var slideTilt: Double { slideTiltDegrees * .pi / 180 }
    public static let tiltSteps = 10
    public static let tiltOverFrames = 90
    public static let tiltHoldFrames = 300
    public static let levelFrames = 120
    public static var tiltEveryFrames: Int { tiltOverFrames + tiltHoldFrames + tiltOverFrames + levelFrames }

    /// The cart: 40 by 64 art pixels, rolling with the pitch at the ball's pull, its drag a
    /// frame, no faster than its most; rolling into a body at least `cartHitSpeed` it knocks
    /// them its way, the ball out of their hands, and can't hit them again for `cartHitFrames`.
    public static let cartSize = Vec2(x: 25, y: 40)
    public static let cartDrag = 0.005
    public static let cartTopSpeed = 2.0
    public static let cartPush = Vec2(x: 3, y: 2)
    public static let cartHitSpeed = 0.2
    public static let cartHitFrames = 30
}

/// The serving cart on the aisle: where it is, and its speed along it.
public struct Cart: Equatable {
    public var box: Box
    public var velocity: Double

    /// In the middle of the aisle, on the floor, still.
    static func starting(on stage: Stage) -> Cart {
        let floor = Double(FlightRules.floorRows) * Stage.tileSize
        let left = stage.width / 2 - FlightRules.cartSize.x / 2
        return Cart(box: Box(min: Vec2(x: left, y: floor), max: Vec2(x: left + FlightRules.cartSize.x, y: floor + FlightRules.cartSize.y)), velocity: 0)
    }
}

extension Match {
    /// The pitch and the cart, a frame on, before anyone moves.
    mutating func stepFlight() {
        guard stage.features.tilts else { return }
        // A round: a new lean off the dice, eased to and held, eased back level and held there.
        if tiltClock == 0 {
            tiltFrom = stage.tilt
            tiltTarget = Double(fieldDice.roll(2 * FlightRules.tiltSteps + 1) - FlightRules.tiltSteps) / Double(FlightRules.tiltSteps) * FlightRules.tiltMax
        }
        tiltClock += 1
        func eased(_ frames: Int) -> Double {
            let share = min(max(Double(frames) / Double(FlightRules.tiltOverFrames), 0), 1)
            return share * share * (3 - 2 * share)
        }
        let backAt = FlightRules.tiltOverFrames + FlightRules.tiltHoldFrames
        if tiltClock < backAt {
            stage.tilt = tiltFrom + (tiltTarget - tiltFrom) * eased(tiltClock)
        } else {
            stage.tilt = tiltTarget * (1 - eased(tiltClock - backAt))
        }
        if tiltClock >= FlightRules.tiltEveryFrames {
            tiltClock = 0
            stage.tilt = 0
        }
        stepCart()
    }

    private mutating func stepCart() {
        guard var cart else { return }
        for index in cartHitFrames.indices where cartHitFrames[index] > 0 { cartHitFrames[index] -= 1 }
        // Rolling with the pitch, slowed by its drag, no faster than its most; stopped at the walls.
        cart.velocity -= BallRules.gravity * stage.tiltPull
        let slowed = max(abs(cart.velocity) - FlightRules.cartDrag, 0)
        cart.velocity = min(slowed, FlightRules.cartTopSpeed) * (cart.velocity < 0 ? -1 : 1)
        var left = cart.box.min.x + cart.velocity
        if left < 0 {
            left = 0
            cart.velocity = 0
        }
        if left > stage.width - FlightRules.cartSize.x {
            left = stage.width - FlightRules.cartSize.x
            cart.velocity = 0
        }
        cart.box = Box(min: Vec2(x: left, y: cart.box.min.y), max: Vec2(x: left + FlightRules.cartSize.x, y: cart.box.max.y))
        // Into a body: the ball out of their hands, and they're knocked its way.
        if abs(cart.velocity) >= FlightRules.cartHitSpeed {
            let way: Double = cart.velocity < 0 ? -1 : 1
            for index in players.indices where cartHitFrames.indices.contains(index) && cartHitFrames[index] == 0 && players[index].body.overlaps(cart.box) {
                cartHitFrames[index] = FlightRules.cartHitFrames
                if ball.holder == index {
                    let from = players[index].heldBallPoint
                    players[index].loseBall()
                    ball.pop(from: from)
                    ball.velocity.x = 0
                    holdHitStop(HitStopRules.hitFrames)
                }
                players[index].knock(Vec2(x: way * FlightRules.cartPush.x, y: FlightRules.cartPush.y))
                players[index].hitStun = BallRules.hitStunFrames
                events.append(.cartHit(player: index, at: cart.box.center))
            }
        }
        self.cart = cart
    }
}
