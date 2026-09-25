import Foundation

/// Highway Traffic: standstill traffic on the road, the rim carried across by a helicopter.
/// The cars are solid and stand still; three hits from anything that would stun a player
/// wreck one, the fuel truck one hit of fire, and a new one takes its place. Which vehicle
/// stands in each slot comes off the match's dice, so both phones agree without sending a
/// word of it.
public enum Vehicle: Int, CaseIterable, Equatable {
    case ambulance, bus, cab, car, batmobile, droptop, police, racer, supercar, fuelTruck, hearse,
         limousine, moped, motorcycle, motorcycle2, truck, truck2, fireTruck, foodTruck, van, van2, van3, vespa

    /// The art's name in the catalogue.
    public var art: String {
        switch self {
        case .ambulance: "ambulancr"
        case .bus: "bus"
        case .cab: "cab"
        case .car: "car"
        case .batmobile: "car_batmobile"
        case .droptop: "car_droptop"
        case .police: "car_police"
        case .racer: "car_racer"
        case .supercar: "car_super"
        case .fuelTruck: "fuel_truck"
        case .hearse: "hearse"
        case .limousine: "limousine"
        case .moped: "moped"
        case .motorcycle: "motorcycle"
        case .motorcycle2: "motorcycle2"
        case .truck: "truck"
        case .truck2: "truck2"
        case .fireTruck: "truck_fire"
        case .foodTruck: "truck_food"
        case .van: "van"
        case .van2: "van2"
        case .van3: "van3"
        case .vespa: "vespa"
        }
    }

    /// Its length in tiles, roughly its size in the world against the others.
    public var lengthTiles: Double {
        switch self {
        case .moped, .motorcycle, .motorcycle2, .vespa: 3
        case .car, .batmobile, .droptop, .police, .racer, .supercar, .cab, .van, .van2, .van3: 5
        case .ambulance, .hearse, .foodTruck: 6
        case .limousine, .truck: 7
        case .bus, .truck2, .fuelTruck, .fireTruck: 8
        }
    }

    /// Height over length, the drawing's own, measured off the art.
    public var aspect: Double {
        switch self {
        case .ambulance, .cab: 154.0 / 256
        case .bus, .police: 104.0 / 256
        case .car: 118.0 / 256
        case .batmobile: 92.0 / 256
        case .droptop: 76.0 / 256
        case .racer: 74.0 / 256
        case .supercar: 80.0 / 256
        case .fuelTruck: 116.0 / 256
        case .hearse: 144.0 / 256
        case .limousine: 84.0 / 256
        case .moped: 160.0 / 256
        case .motorcycle: 140.0 / 256
        case .motorcycle2: 142.0 / 256
        case .truck: 220.0 / 256
        case .truck2: 121.0 / 256
        case .fireTruck: 142.0 / 256
        case .foodTruck: 212.0 / 256
        case .van: 134.0 / 256
        case .van2: 130.0 / 256
        case .van3: 180.0 / 256
        case .vespa: 199.0 / 256
        }
    }

    public var size: Vec2 {
        let length = lengthTiles * Stage.tileSize
        return Vec2(x: length, y: length * aspect)
    }

    /// One hit of fire wrecks it.
    public var burnsAtOnce: Bool { self == .fuelTruck }
}

public struct Car: Equatable {
    public var id: Int
    public var vehicle: Vehicle
    /// Which slot along the road it stands in.
    public var slot: Int
    public var box: Box
    public var hits = 0
    /// Frames before the same car can take another hit, so one swing counts once.
    public var guardFrames = 0
}

/// The helicopter carrying one rim across, from one wall to the other, the next carrying
/// the other side's.
public struct Helicopter: Equatable {
    public var id: Int
    /// The rim it carries, by its index in the stage's hoops.
    public var hoop: Int
    public var x: Double
    public var speed: Double
}

public enum HighwayRules {
    /// The road is cut into this many slots, each wide enough for the longest vehicle.
    public static let slots = 4
    public static let hitsToWreck = 3
    public static let hitGuardFrames = 20
    /// The helicopter flies at this height, the rim hanging this far under it, at this speed.
    public static let helicopterHeight = 120.0
    public static let rimBelowHelicopter = 32.0
    public static let helicopterSpeed = 1.0
    /// Where the rim waits while its helicopter isn't out: far over the sky, out of play.
    public static let parked = Vec2(x: -1000, y: 5000)
}

extension Match {
    /// The slots' cars at the start, one each, off the dice.
    mutating func fillTraffic() {
        cars = (0..<HighwayRules.slots).map { makeCar(in: $0) }
        refreshExtras()
    }

    func slotCentre(_ slot: Int) -> Double {
        let inner = stage.width - 2 * Stage.tileSize
        return Stage.tileSize + inner * (Double(slot) + 0.5) / Double(HighwayRules.slots)
    }

    private mutating func makeCar(in slot: Int) -> Car {
        let vehicle = Vehicle.allCases[fieldDice.roll(Vehicle.allCases.count)]
        let size = vehicle.size
        let centre = slotCentre(slot)
        let box = Box(min: Vec2(x: centre - size.x / 2, y: Stage.tileSize), max: Vec2(x: centre + size.x / 2, y: Stage.tileSize + size.y))
        return Car(id: stampId(), vehicle: vehicle, slot: slot, box: box)
    }

    /// A hit on a car, from anything that would stun a player; `fire` for fire's own.
    /// Wrecked, a new car takes its slot.
    mutating func hitCar(_ index: Int, fire: Bool) {
        guard cars.indices.contains(index), cars[index].guardFrames == 0 else { return }
        cars[index].hits += 1
        cars[index].guardFrames = HighwayRules.hitGuardFrames
        events.append(.carHit(id: cars[index].id))
        if cars[index].hits >= HighwayRules.hitsToWreck || (fire && cars[index].vehicle.burnsAtOnce) {
            let wrecked = cars[index]
            events.append(.carWrecked(id: wrecked.id, at: wrecked.box.center))
            cars[index] = makeCar(in: wrecked.slot)
            events.append(.carArrived(id: cars[index].id))
            refreshExtras()
        }
    }

    /// The first car a box touches, if any.
    func car(touching box: Box) -> Int? {
        cars.firstIndex { $0.box.overlaps(box) }
    }

    /// The traffic and the helicopter a frame on.
    mutating func stepHighway() {
        for index in cars.indices where cars[index].guardFrames > 0 { cars[index].guardFrames -= 1 }
        guard stage.hoops.count >= 2 else { return }
        if helicopter == nil {
            // The next rim, the other side's from the last, from the wall it's away from.
            let next = (lastHelicopterHoop ?? fieldDice.roll(2)) == 0 ? 1 : 0
            lastHelicopterHoop = next
            let fromLeft = fieldDice.roll(2) == 0
            helicopter = Helicopter(id: stampId(), hoop: next, x: fromLeft ? -40 : stage.width + 40,
                                    speed: HighwayRules.helicopterSpeed * (fromLeft ? 1 : -1))
            events.append(.helicopterArrived(hoop: next))
        }
        guard var flying = helicopter else { return }
        flying.x += flying.speed
        let gone = flying.speed > 0 ? flying.x > stage.width + 40 : flying.x < -40
        for index in stage.hoops.indices {
            stage.hoops[index].position = index == flying.hoop && !gone
                ? Vec2(x: flying.x, y: HighwayRules.helicopterHeight - HighwayRules.rimBelowHelicopter)
                : HighwayRules.parked
        }
        helicopter = gone ? nil : flying
    }

    /// The boxes solid to bodies: made slabs, helmets and cars.
    mutating func refreshExtras() {
        stage.extras = platforms.map(\.box) + helmets.map(\.box) + cars.map(\.box)
    }
}
