import Foundation

/// Flight B411: the aisle of a plane, drawn whole in Aseprite (`Flight_Map.aseprite`, 1248 by 576,
/// four of its pixels an art pixel): 312 by 144 art pixels, 19 and a half tiles by 9, on a
/// grid of 20 whose last half column is walled off. Two rows of floor; the rims at the ends two
/// thirds of the way up; the starts two and a half tiles in; the ball in the open bin over the
/// middle. The plane pitches now and then, which leans gravity, and a cart rolls the aisle with it.
public enum FlightB411Rules {
    public static let columns = 20
    public static let rows = 9
    public static let width = 195.0
    public static let floorRows = 2
    public static let rimHeight = 65.0
    public static let rimInset = 5.0
    public static let startInset = 25.0
    public static let ballHeight = 60.0
    /// Every body's speeds on it, on the ground, in the air and in flight.
    public static let speedShare = 0.5

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

    /// The cart: 16 by 24 art pixels solid (its art 32 tall, the top row nothing), stood on and
    /// ridden, rolling with the pitch at the ball's pull, its drag a frame, no faster than its
    /// most; rolling into a body at least `cartHitSpeed` it knocks them its way, the ball out of
    /// their hands, and can't hit them again for `cartHitFrames`.
    public static let cartSize = Vec2(x: 10, y: 15)
    public static let cartDrag = 0.005
    public static let cartTopSpeed = 2.0
    public static let cartPush = Vec2(x: 3, y: 2)
    public static let cartHitSpeed = 0.2
    public static let cartHitFrames = 30
}

/// The serving cart on the aisle: where it is, its speed along it, and how far it's rolled in
/// all, for its wheels.
public struct Cart: Equatable {
    public var box: Box
    public var velocity: Double
    public var rolled = 0.0

    /// In the middle of the aisle, on the floor, still.
    static func starting(on stage: Stage) -> Cart {
        let floor = Double(FlightB411Rules.floorRows) * Stage.tileSize
        let left = stage.width / 2 - FlightB411Rules.cartSize.x / 2
        return Cart(box: Box(min: Vec2(x: left, y: floor), max: Vec2(x: left + FlightB411Rules.cartSize.x, y: floor + FlightB411Rules.cartSize.y)), velocity: 0)
    }
}

extension Match {
    /// The pitch and the cart, a frame on, before anyone moves.
    mutating func stepFlightB411() {
        guard stage.features.tilts else { return }
        // A round: a new lean off the dice, eased to and held, eased back level and held there.
        if tiltClock == 0 {
            tiltFrom = stage.tilt
            tiltTarget = Double(fieldDice.roll(2 * FlightB411Rules.tiltSteps + 1) - FlightB411Rules.tiltSteps) / Double(FlightB411Rules.tiltSteps) * FlightB411Rules.tiltMax
        }
        tiltClock += 1
        func eased(_ frames: Int) -> Double {
            let share = min(max(Double(frames) / Double(FlightB411Rules.tiltOverFrames), 0), 1)
            return share * share * (3 - 2 * share)
        }
        let backAt = FlightB411Rules.tiltOverFrames + FlightB411Rules.tiltHoldFrames
        if tiltClock < backAt {
            stage.tilt = tiltFrom + (tiltTarget - tiltFrom) * eased(tiltClock)
        } else {
            stage.tilt = tiltTarget * (1 - eased(tiltClock - backAt))
        }
        if tiltClock >= FlightB411Rules.tiltEveryFrames {
            tiltClock = 0
            stage.tilt = 0
        }
        stepCart()
    }

    private mutating func stepCart() {
        guard var cart else { return }
        for index in cartHitFrames.indices where cartHitFrames[index] > 0 { cartHitFrames[index] -= 1 }
        // Whoever stands on it rides it.
        let riders = players.indices.filter { stands(players[$0], on: cart.box) }
        // Rolling with the pitch, slowed by its drag, no faster than its most; stopped at the walls.
        cart.velocity -= BallRules.gravity * stage.tiltPull
        let slowed = max(abs(cart.velocity) - FlightB411Rules.cartDrag, 0)
        cart.velocity = min(slowed, FlightB411Rules.cartTopSpeed) * (cart.velocity < 0 ? -1 : 1)
        var left = cart.box.min.x + cart.velocity
        if left < 0 {
            left = 0
            cart.velocity = 0
        }
        if left > stage.width - FlightB411Rules.cartSize.x {
            left = stage.width - FlightB411Rules.cartSize.x
            cart.velocity = 0
        }
        let moved = left - cart.box.min.x
        cart.rolled += moved
        cart.box = Box(min: Vec2(x: left, y: cart.box.min.y), max: Vec2(x: left + FlightB411Rules.cartSize.x, y: cart.box.max.y))
        self.cart = cart
        refreshExtras()
        for index in riders { carry(index, by: moved) }
        // Into a body: the ball out of their hands, and they're knocked its way.
        if abs(cart.velocity) >= FlightB411Rules.cartHitSpeed {
            let way: Double = cart.velocity < 0 ? -1 : 1
            for index in players.indices where !riders.contains(index) && cartHitFrames.indices.contains(index) && cartHitFrames[index] == 0
                && players[index].body.overlaps(cart.box) {
                cartHitFrames[index] = FlightB411Rules.cartHitFrames
                if ball.holder == index {
                    let from = players[index].heldBallPoint
                    players[index].loseBall()
                    ball.pop(from: from)
                    ball.velocity.x = 0
                    holdHitStop(HitStopRules.hitFrames)
                }
                players[index].knock(Vec2(x: way * FlightB411Rules.cartPush.x, y: FlightB411Rules.cartPush.y))
                players[index].hitStun = BallRules.hitStunFrames
                events.append(.cartHit(player: index, at: cart.box.center))
            }
        }
    }
}
