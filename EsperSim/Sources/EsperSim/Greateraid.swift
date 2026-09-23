import Foundation

/// A small deterministic random stream for anything the game itself rolls, so both
/// sides of a match roll the same.
public struct Dice: Equatable {
    private var state: UInt32

    public init(seed: UInt32) {
        state = seed
    }

    public mutating func roll(_ sides: Int) -> Int {
        state = state &* 1664525 &+ 1013904223
        return Int((state >> 16) % UInt32(max(sides, 1)))
    }
}

/// Greateraid: the drinks a player takes between rounds. Boosters raise a stat and stack
/// to two drinks; Biomorphs are the powers, one at a time; and once you hold one,
/// Bio-Boba stands in for the biomorphs in the offers and raises yours to level two.
public enum Greateraid: CaseIterable, Equatable, Hashable {
    case hastyHorchata, jumperJuice, lungeLemonade, cannonCola, slideCider
    case webWater, superSoda, flashFizz, platformShake
    case bioBoba

    public enum Kind: Equatable { case booster, biomorph, bioBoba }

    public static let boosters: [Greateraid] = [.hastyHorchata, .jumperJuice, .lungeLemonade, .cannonCola, .slideCider]
    public static let biomorphs: [Greateraid] = [.webWater, .superSoda, .flashFizz, .platformShake]

    public var kind: Kind {
        switch self {
        case .hastyHorchata, .jumperJuice, .lungeLemonade, .cannonCola, .slideCider: .booster
        case .webWater, .superSoda, .flashFizz, .platformShake: .biomorph
        case .bioBoba: .bioBoba
        }
    }

    public var name: String {
        switch self {
        case .hastyHorchata: "Hasty Horchata"
        case .jumperJuice: "Jumper Juice"
        case .lungeLemonade: "Lunge Lemonade"
        case .cannonCola: "Cannon Cola"
        case .slideCider: "Slide Cider"
        case .webWater: "Web Water"
        case .superSoda: "Super Soda"
        case .flashFizz: "Flash Fizz"
        case .platformShake: "Platform Protein Shake"
        case .bioBoba: "Bio-Boba"
        }
    }

    /// The power a biomorph gives.
    public var power: Power? {
        switch self {
        case .webWater: .webWater
        case .superSoda: .superSoda
        case .flashFizz: .flashFizz
        case .platformShake: .platformShake
        default: nil
        }
    }

    /// What the first drink does, and what the second adds.
    public var blurbs: (first: String, second: String) {
        switch self {
        case .hastyHorchata: ("Run, dash and air speed up.", "And up again.")
        case .jumperJuice: ("A second jump.", "Both jumps higher.")
        case .lungeLemonade: ("A longer dash.", "Longer still.")
        case .cannonCola: ("A faster shot.", "Faster still.")
        case .slideCider: ("A longer slide.", "Longer still.")
        case .webWater: ("Double jump is a web swing.", "Throw fires a web line.")
        case .superSoda: ("Hold jump in the air to fly.", "Faster, and for longer.")
        case .flashFizz: ("Shoot flashes you a short way, or to your ball while it's still yours.", "Flashes tear the ball into your hands and out of theirs, further.")
        case .platformShake: ("A fast fall makes a slab.", "Shoot makes a wall.")
        case .bioBoba: ("Your biomorph to level two.", "")
        }
    }
}

/// What a player has drunk.
public struct Drinks: Equatable {
    public static let maxBoosterLevel = 2
    public static let offerCount = 3
    /// A booster's weight against a biomorph's in an offer.
    public static let boosterWeight = 3

    /// Levels by booster, looked up only, never walked.
    public var boosters: [Greateraid: Int] = [:]
    public var biomorph: Greateraid?
    public var biomorphLevel = 0

    public static let none = Drinks()

    public init() {}

    public func level(of drink: Greateraid) -> Int {
        switch drink.kind {
        case .booster: boosters[drink] ?? 0
        case .biomorph: biomorph == drink ? biomorphLevel : 0
        case .bioBoba: 0
        }
    }

    public var power: Power { biomorph?.power ?? .none }
    public var powerLevel: Int { max(biomorphLevel, 1) }

    /// Three bottles to choose from: boosters not yet drunk twice, weighted three to one
    /// over biomorphs; with a biomorph in hand, Bio-Boba stands in for the biomorphs until
    /// it's level two. Never the same bottle twice in one offer.
    public func offers(_ dice: inout Dice) -> [Greateraid] {
        var pool: [(drink: Greateraid, weight: Int)] = []
        for booster in Greateraid.boosters where level(of: booster) < Drinks.maxBoosterLevel {
            pool.append((booster, Drinks.boosterWeight))
        }
        if biomorph == nil {
            for biomorph in Greateraid.biomorphs { pool.append((biomorph, 1)) }
        } else if biomorphLevel < 2 {
            pool.append((.bioBoba, 1))
        }
        var picks: [Greateraid] = []
        while picks.count < Drinks.offerCount, !pool.isEmpty {
            var roll = dice.roll(pool.reduce(0) { $0 + $1.weight })
            var index = pool.count - 1
            for (candidate, entry) in pool.enumerated() {
                if roll < entry.weight { index = candidate; break }
                roll -= entry.weight
            }
            picks.append(pool[index].drink)
            pool.remove(at: index)
        }
        return picks
    }

    public mutating func drink(_ drink: Greateraid) {
        switch drink.kind {
        case .booster:
            boosters[drink] = min(level(of: drink) + 1, Drinks.maxBoosterLevel)
        case .biomorph:
            biomorph = drink
            biomorphLevel = 1
        case .bioBoba:
            if biomorph != nil { biomorphLevel = 2 }
        }
    }

    /// The body's numbers with these drinks in it, from the starting body: Hasty Horchata
    /// adds half a unit of run, dash and air speed a drink; Jumper Juice gives the second
    /// jump, then both jumps a tenth higher; Lunge Lemonade four frames of dash a drink;
    /// Cannon Cola a quarter more shot pace a drink, the same arc run faster; Slide Cider
    /// four frames of slide a drink.
    public func spec(from base: FighterSpec = .starting) -> FighterSpec {
        var spec = base
        let hasty = Double(level(of: .hastyHorchata))
        spec.runSpeed += 0.5 * hasty
        spec.dashInitialVelocity = spec.runSpeed + 0.4
        spec.airSpeedMax += 0.5 * hasty
        spec.jumpHorizontalVelocity += 0.5 * hasty
        spec.doubleJumpHorizontalVelocity += 0.5 * hasty
        let jumper = level(of: .jumperJuice)
        if jumper >= 1 { spec.jumps = 2 }
        if jumper >= 2 {
            spec.fullHopVelocity *= 1.1
            spec.shortHopVelocity *= 1.1
            spec.doubleJumpVelocity *= 1.1
        }
        spec.dashFrames += 4 * level(of: .lungeLemonade)
        spec.shotPace += 0.25 * Double(level(of: .cannonCola))
        spec.slideFrames += 4 * level(of: .slideCider)
        return spec
    }
}
