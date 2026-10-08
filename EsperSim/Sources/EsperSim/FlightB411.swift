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
    /// Rows of sky over the art before the ceiling, being tuned: the CEILING slider's, offline;
    /// online every phone plays the default.
    public static let defaultSkyRows = 2
    nonisolated(unsafe) public static var skyRows = defaultSkyRows

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

    /// The overhead bins: the five whole ones along the ceiling (the art's end bins are cut by
    /// the plane's ends and never open), each 48 art pixels wide, their band 88 to 112 art pixels
    /// up; the middle one holds the ball at a start. Measured off `Flight_Map.aseprite`'s Bins
    /// layer, whose panels repeat every 192 of its pixels from 160.
    public static let binLefts: [Double] = [40, 88, 136, 184, 232].map { $0 * 0.625 }
    public static let binWidth = 48 * 0.625
    public static let binBottom = 88 * 0.625
    public static let binTop = 112 * 0.625
    public static let centreBin = 2
    /// The ball waits this far up from the bin's bottom, in its mouth, before it drops.
    public static let ballInBin = 4 * 0.625
    /// The hoopcase hangs from an open bin: its ring's centre this many art pixels under the
    /// suitcase's top, which hangs `hoopcaseDrop` under the bin's bottom, the HOOPCASE Y
    /// slider's, offline; online every phone plays the default.
    public static let rimUnderCase = 18.0
    public static let defaultHoopcaseDrop = -17.0
    nonisolated(unsafe) public static var hoopcaseDrop = defaultHoopcaseDrop
    /// The hoopcase slides out of its bin over this many frames, and back in as it retreats.
    public static let caseSlideFrames = 20

    /// A start: the plane level and the bins still through the count and this long after.
    public static let startLevelFrames = 7 * 60
    /// The bins' cycle: one bin open at a time, for `binOpenFrames`, then another, never the
    /// same one twice running, with nothing in it, or one side's hoop, or the other's.
    public static let binOpenFrames = 600

    /// Where a bin is: its middle, and the ball's wait in its mouth, and its hoopcase's ring.
    public static func binCentre(_ index: Int) -> Double { binLefts[index] + binWidth / 2 }
    public static func ballSpot(in index: Int) -> Vec2 { Vec2(x: binCentre(index), y: binBottom + ballInBin) }
    public static func rimSpot(in index: Int) -> Vec2 { Vec2(x: binCentre(index), y: binBottom - (hoopcaseDrop + rimUnderCase) * 0.625) }
}

/// An overhead bin: shut, or open with what's in it, and the frames it stays open; its
/// hoopcase's slide, out from the bin to 1, and whether it's on its way back in.
public struct Bin: Equatable {
    public enum Load: Equatable {
        case empty
        /// A hoop, by whose it is to score on.
        case hoop(owner: Int)
    }
    public var open = false
    public var load = Load.empty
    public var framesLeft = 0
    /// Frames of the case's slide done, out of `FlightB411Rules.caseSlideFrames`.
    public var caseFrames = 0
    public var retreating = false

    /// How far the case is out, 0 in the bin to 1 hanging.
    public var caseOut: Double { Double(caseFrames) / Double(FlightB411Rules.caseSlideFrames) }
    /// Whether its hoop is out to be scored on: all the way out and not on its way back.
    public var hoopLive: Bool {
        if case .hoop = load { return open && !retreating && caseFrames >= FlightB411Rules.caseSlideFrames }
        return false
    }
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
    /// Flight B411's start: the bins all shut but the one the ball waits in, the hoops away.
    mutating func startFlightB411() {
        bins = Array(repeating: Bin(), count: FlightB411Rules.binLefts.count)
        startFromBin(FlightB411Rules.centreBin)
        lastBin = FlightB411Rules.centreBin
        for index in stage.hoops.indices { stage.hoops[index].position = HighwayRules.parked }
    }

    /// The ball to wait in `index`'s bin, open for it, until the count's done and the plane's
    /// first level spell is over: the middle bin at a start, or any on a round that says so.
    public mutating func startFromBin(_ index: Int) {
        guard bins.indices.contains(index) else { return }
        for other in bins.indices { bins[other] = Bin() }
        bins[index].open = true
        bins[index].framesLeft = countdown + FlightB411Rules.startLevelFrames
        ballBin = index
        lastBin = index
        ball.respawn(at: FlightB411Rules.ballSpot(in: index))
    }

    /// Frames into the match before the pitch and the bins' cycle start: the count, and the
    /// level spell after it.
    private var flightStartsAt: Int { countdownLength + FlightB411Rules.startLevelFrames }

    /// The pitch, the cart and the bins, a frame on, before anyone moves.
    mutating func stepFlightB411() {
        guard stage.features.tilts else { return }
        stepBins()
        // Level through the count and a while after, the bins still.
        if frame < flightStartsAt {
            stage.tilt = 0
            tiltClock = 0
            stepCart()
            return
        }
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

    /// The bins: the ball held in its bin's mouth through the count, then dropped. One bin is
    /// open at a time: its spell over, its hoopcase, if it has one, slides back in, then it
    /// shuts and another opens, never the same one twice running, with nothing, or one side's
    /// hoop, or the other's, which slides out. A hoop's rim hangs where its case is once it's
    /// all the way out, and is away otherwise.
    private mutating func stepBins() {
        guard !bins.isEmpty else { return }
        // The ball's wait in its bin (held in `advance`) is over with the count.
        if ballBin != nil, countdown == 0 || ball.holder != nil { ballBin = nil }
        for index in bins.indices where bins[index].open {
            if bins[index].retreating {
                bins[index].caseFrames = max(bins[index].caseFrames - 1, 0)
                if bins[index].caseFrames == 0 { bins[index] = Bin() }
                continue
            }
            if case .hoop = bins[index].load { bins[index].caseFrames = min(bins[index].caseFrames + 1, FlightB411Rules.caseSlideFrames) }
            bins[index].framesLeft -= 1
            if bins[index].framesLeft <= 0 {
                if case .hoop = bins[index].load, bins[index].caseFrames > 0 {
                    bins[index].retreating = true
                } else {
                    bins[index] = Bin()
                }
            }
        }
        // None open, past the start's spell: the next, any but the last.
        if frame >= flightStartsAt, !bins.contains(where: \.open) {
            let choices = bins.indices.filter { $0 != lastBin }
            let index = choices[fieldDice.roll(choices.count)]
            let roll = fieldDice.roll(3)
            bins[index].open = true
            bins[index].framesLeft = FlightB411Rules.binOpenFrames
            bins[index].load = roll == 0 ? .empty : .hoop(owner: roll - 1)
            lastBin = index
        }
        for hoop in stage.hoops.indices {
            let owner = stage.hoops[hoop].owner
            let holding = bins.indices.first { bins[$0].hoopLive && bins[$0].load == .hoop(owner: owner) }
            stage.hoops[hoop].position = holding.map(FlightB411Rules.rimSpot) ?? HighwayRules.parked
        }
    }

    /// Scored on: the hoop's case retreats into its bin at once, which then shuts and the next
    /// opens, so the same hoop can't take the ball twice.
    mutating func flightB411Scored(on hoop: Int) {
        guard stage.features.tilts, stage.hoops.indices.contains(hoop) else { return }
        let owner = stage.hoops[hoop].owner
        for index in bins.indices where bins[index].open && bins[index].load == .hoop(owner: owner) {
            bins[index].retreating = true
        }
        stage.hoops[hoop].position = HighwayRules.parked
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
