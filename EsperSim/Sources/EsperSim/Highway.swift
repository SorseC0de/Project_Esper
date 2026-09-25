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

    /// Its outline, tile by tile from the drawing's left: each tile's height as a share of
    /// the whole, measured off the art at the top that four in five of its pixel columns
    /// reach, so an aerial or a stack doesn't count. One solid box a tile.
    public var outline: [Double] {
        switch self {
        case .ambulance: [0.84, 0.93, 0.98, 0.93, 0.81, 0.49]
        case .bus: [0.90, 1.00, 1.00, 0.97, 0.97, 0.97, 0.97, 0.88]
        case .cab: [0.49, 0.80, 0.84, 0.58, 0.49]
        case .car: [0.70, 1.00, 1.00, 0.68, 0.50]
        case .batmobile: [0.42, 0.81, 0.92, 0.59, 0.44]
        case .droptop: [0.54, 0.76, 0.76, 0.71, 0.54]
        case .police: [0.48, 0.89, 0.89, 0.59, 0.43]
        case .racer: [0.53, 0.78, 0.79, 0.73, 0.55]
        case .supercar: [0.79, 0.97, 0.91, 0.73, 0.45]
        case .fuelTruck: [0.84, 0.93, 1.00, 0.98, 0.93, 0.82, 0.99, 0.63]
        case .hearse: [0.90, 1.00, 1.00, 1.00, 0.87, 0.52]
        case .limousine: [0.59, 0.71, 1.00, 1.00, 0.99, 0.71, 0.62]
        case .moped: [0.74, 0.61, 0.58]
        case .motorcycle: [0.52, 0.71, 0.49]
        case .motorcycle2: [0.54, 0.69, 0.50]
        case .truck: [0.21, 0.34, 0.25, 0.63, 0.83, 0.73, 0.60]
        case .truck2: [1.00, 1.00, 1.00, 1.00, 1.00, 1.00, 0.95, 0.86]
        case .fireTruck: [0.79, 0.82, 0.86, 0.89, 0.91, 0.95, 0.97, 0.65]
        case .foodTruck: [0.52, 0.84, 0.84, 0.52, 0.52, 0.29]
        case .van: [0.98, 1.00, 1.00, 1.00, 0.57]
        case .van2: [0.85, 0.97, 0.97, 0.84, 0.48]
        case .van3: [0.88, 0.91, 1.00, 0.76, 0.42]
        case .vespa: [0.52, 0.19, 0.33]
        }
    }
}

public struct Car: Equatable {
    public var id: Int
    public var vehicle: Vehicle
    /// Which slot along the road it stands in, and in which lane: 0 the near lane, which
    /// plays, 1 the far one above the lane line, which is only scenery.
    public var slot: Int
    public var level = 0
    /// The whole of it, and the one-tile boxes that follow its outline, which are what's
    /// solid and what takes hits. Facing left, the drawing and the outline are mirrored.
    public var box: Box
    public var facesLeft: Bool
    public var boxes: [Box] {
        let tile = Stage.tileSize
        let heights = facesLeft ? Array(vehicle.outline.reversed()) : vehicle.outline
        return heights.enumerated().map { column, share in
            let left = box.min.x + Double(column) * tile
            return Box(min: Vec2(x: left, y: box.min.y), max: Vec2(x: left + tile, y: box.min.y + max(share, 0.1) * box.height))
        }
    }
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
    /// Each level is cut into this many slots, each wide enough for the longest vehicle.
    public static let slots = 4
    /// The near lane's cars stand this far down into the road from the floor, so their
    /// wheels are in the near half of it and their roofs lower; their boxes go with them.
    /// The far lane's stand this far up, over the lane line, the other way round from the
    /// near lane's; drawn behind, not solid, never hit.
    public static let nearLaneDrop = 17.5
    public static let farLaneLift = 7.5
    public static let hitsToWreck = 3
    public static let hitGuardFrames = 20
    /// The helicopter flies at this height, the rim hanging this far under it, at this speed.
    public static let helicopterHeight = 140.0
    /// The rim against the helicopter: this far ahead of it the way it flies, and this far
    /// under it; on the HOOP X and HOOP Y sliders offline until they're settled.
    nonisolated(unsafe) public static var rimAhead = 0.0
    nonisolated(unsafe) public static var rimBelowHelicopter = 32.0
    public static let helicopterSpeed = 1.0
    /// Where the rim waits while its helicopter isn't out: far over the sky, out of play.
    public static let parked = Vec2(x: -1000, y: 5000)
}

extension Match {
    /// The slots' cars at the start, one each, off the dice.
    mutating func fillTraffic() {
        cars = (0..<2).flatMap { level in (0..<HighwayRules.slots).map { makeCar(in: $0, level: level) } }
        refreshExtras()
    }

    func slotCentre(_ slot: Int) -> Double {
        let inner = stage.width - 2 * Stage.tileSize
        return Stage.tileSize + inner * (Double(slot) + 0.5) / Double(HighwayRules.slots)
    }

    /// The near lane faces right and the far one left.
    private mutating func makeCar(in slot: Int, level: Int) -> Car {
        let vehicle = Vehicle.allCases[fieldDice.roll(Vehicle.allCases.count)]
        let size = vehicle.size
        let centre = slotCentre(slot)
        let floor = level == 0 ? Stage.tileSize - HighwayRules.nearLaneDrop : Stage.tileSize + HighwayRules.farLaneLift
        let box = Box(min: Vec2(x: centre - size.x / 2, y: floor), max: Vec2(x: centre + size.x / 2, y: floor + size.y))
        return Car(id: stampId(), vehicle: vehicle, slot: slot, level: level, box: box, facesLeft: level == 1)
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
            cars[index] = makeCar(in: wrecked.slot, level: wrecked.level)
            events.append(.carArrived(id: cars[index].id))
            refreshExtras()
        }
    }

    /// The first car a box touches, if any.
    func car(touching box: Box) -> Int? {
        cars.firstIndex { car in car.level == 0 && car.box.overlaps(box) && car.boxes.contains { $0.overlaps(box) } }
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
                ? Vec2(x: flying.x + HighwayRules.rimAhead * (flying.speed > 0 ? 1 : -1), y: HighwayRules.helicopterHeight - HighwayRules.rimBelowHelicopter)
                : HighwayRules.parked
        }
        helicopter = gone ? nil : flying
    }

    /// The boxes solid to bodies: made slabs, helmets and cars.
    mutating func refreshExtras() {
        stage.extras = platforms.map(\.box) + helmets.map(\.box) + cars.filter { $0.level == 0 }.flatMap(\.boxes)
    }
}
