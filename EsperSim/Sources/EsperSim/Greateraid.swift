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
/// to two drinks; Biomorphs are the powers, one at a time, and the one in hand comes
/// round again as a second sip that raises it to level two.
public enum Greateraid: CaseIterable, Equatable, Hashable {
    case hastyHorchata, jumperJuice, lungeLemonade, cannonCola, slideCider
    case webWater, superSmoothie, flashFizz, platformShake
    case quakeUp, zeusJuice, frostTea, blazingBoba, pulsepistol

    public enum Kind: Equatable { case booster, biomorph }

    public static let boosters: [Greateraid] = [.hastyHorchata, .jumperJuice, .lungeLemonade, .cannonCola, .slideCider]
    public static let biomorphs: [Greateraid] = [.webWater, .superSmoothie, .flashFizz, .platformShake,
                                                 .quakeUp, .zeusJuice, .frostTea, .blazingBoba, .pulsepistol]

    public var kind: Kind {
        Greateraid.boosters.contains(self) ? .booster : .biomorph
    }

    public var name: String {
        switch self {
        case .hastyHorchata: "Hasty Horchata"
        case .jumperJuice: "Jumper Juice"
        case .lungeLemonade: "Lunge Lemonade"
        case .cannonCola: "Cannon Cola"
        case .slideCider: "Slide Cider"
        case .webWater: "Web Water"
        case .superSmoothie: "Super Smoothie"
        case .flashFizz: "Flash Fizz"
        case .platformShake: "Platform Protein Shake"
        case .quakeUp: "Quake-Up Coffee"
        case .zeusJuice: "Zeus Juice"
        case .frostTea: "Frost Tea"
        case .blazingBoba: "Blazing Boba"
        case .pulsepistol: "Pulsepistol Punch"
        }
    }

    /// The power a biomorph gives.
    public var power: Power? {
        switch self {
        case .webWater: .webWater
        case .superSmoothie: .superSmoothie
        case .flashFizz: .flashFizz
        case .platformShake: .platformShake
        case .quakeUp: .quakeUp
        case .zeusJuice: .zeusJuice
        case .frostTea: .frostTea
        case .blazingBoba: .blazingBoba
        case .pulsepistol: .pulsepistol
        default: nil
        }
    }

    /// The line on the bottle, above what it does.
    public var comment: String {
        switch self {
        case .hastyHorchata: "The perfect drink for fasting"
        case .jumperJuice: "Don't get too hopped up on this"
        case .lungeLemonade: "Just a dash of sugar"
        case .cannonCola: "Best served as a shooter"
        case .slideCider: "DMs not included"
        case .webWater: "I thought this was alkaline not radioactive"
        case .superSmoothie: "So THIS is what was in that Special Stuff MJ drank"
        case .flashFizz: "Now you see me, now I dunk"
        case .platformShake: "From staring up to the basket to stairing up to the basket"
        case .quakeUp: "Suddenly everyone around you seems so grounded"
        case .zeusJuice: "A shocking amount of flavor"
        case .frostTea: "Not to be confused with the gas station beverage"
        case .blazingBoba: "...Wait are those fireballs?"
        case .pulsepistol: "For those gunning for first place"
        }
    }

    /// What the first drink does, and what the second adds.
    public var blurbs: (first: String, second: String) {
        switch self {
        case .hastyHorchata: ("Run, dash and air speed up.", "And up again.")
        case .jumperJuice: ("Both jumps higher.", "A third jump, half as high.")
        case .lungeLemonade: ("A longer dash.", "Longer still.")
        case .cannonCola: ("A faster shot.", "Faster still.")
        case .slideCider: ("A longer slide.", "Longer still.")
        case .webWater: ("Double jump is a web swing.", "Throw fires a web line.")
        case .superSmoothie: ("Hold jump in the air to fly, on a cape of energy.", "Forward is a fast glide, and the flight lasts longer.")
        case .flashFizz: ("Shoot flashes you a short way, or to your ball while it's still yours.", "Flashes tear the ball into your hands and out of theirs, further.")
        case .platformShake: ("A fast fall makes a slab.", "Shoot makes a wall.")
        case .quakeUp: ("A fast fall's landing shakes the floor: the ball hops and whoever stands on it is stripped.", "The whole screen is the floor.")
        case .zeusJuice: ("Shoot throws a bolt that strips whoever it hits and pops the ball back to you.", "Throw calls a strike down on the ball in hand, or on your snatch.")
        case .frostTea: ("Snatch freezes what it reaches. Slides never stop until you say so.", "Double jumps and slides leave an ice clone that freezes on touch.")
        case .blazingBoba: ("Full runs and slides leave fire. Your shots burn: nobody else can catch them.", "Hold shoot through a slash for a fireball, shot or thrown, that bursts.")
        case .pulsepistol: ("Shoot fires a pulse across the screen that knocks the ball and them away.", "Shoot on the run, and throw pulls everything in.")
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
        }
    }

    /// Whether the offer of `drink` is the second sip of the biomorph in hand.
    public func isSecondSip(_ drink: Greateraid) -> Bool {
        drink.kind == .biomorph && biomorph == drink
    }

    public var power: Power { biomorph?.power ?? .none }
    public var powerLevel: Int { max(biomorphLevel, 1) }

    /// Three bottles to choose from: boosters not yet drunk twice, weighted three to one
    /// over biomorphs; with a biomorph in hand, only that one comes round, as its second
    /// sip, until it's level two. Never the same bottle twice in one offer.
    public func offers(_ dice: inout Dice) -> [Greateraid] {
        // Weighted so the boosters as a group are three times the biomorphs as a group,
        // however many of each are left.
        let boostersLeft = Greateraid.boosters.filter { level(of: $0) < Drinks.maxBoosterLevel }
        let biomorphsLeft: [Greateraid]
        if let biomorph {
            biomorphsLeft = biomorphLevel < 2 ? [biomorph] : []
        } else {
            biomorphsLeft = Greateraid.biomorphs
        }
        var pool: [(drink: Greateraid, weight: Int)] = []
        for booster in boostersLeft { pool.append((booster, Drinks.boosterWeight * max(biomorphsLeft.count, 1))) }
        for biomorph in biomorphsLeft { pool.append((biomorph, max(boostersLeft.count, 1))) }
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
            if biomorph == drink {
                biomorphLevel = 2
            } else {
                biomorph = drink
                biomorphLevel = 1
            }
        }
    }

    /// The body's numbers with these drinks in it, from the starting body: Hasty Horchata
    /// adds half a unit of run, dash and air speed a drink; Jumper Juice makes both jumps
    /// a tenth higher, then adds a third jump half as high as the first; Lunge Lemonade
    /// four frames of dash a drink; Cannon Cola a quarter more shot pace a drink, the
    /// same arc run faster; Slide Cider eight frames of slide a drink.
    public func spec(from base: FighterSpec = .starting) -> FighterSpec {
        var spec = base
        let hasty = Double(level(of: .hastyHorchata))
        spec.runSpeed += 0.5 * hasty
        spec.dashInitialVelocity = spec.runSpeed + 0.4
        spec.airSpeedMax += 0.5 * hasty
        spec.jumpHorizontalVelocity += 0.5 * hasty
        spec.doubleJumpHorizontalVelocity += 0.5 * hasty
        let jumper = level(of: .jumperJuice)
        if jumper >= 1 {
            spec.fullHopVelocity *= 1.1
            spec.shortHopVelocity *= 1.1
            spec.doubleJumpVelocity *= 1.1
        }
        if jumper >= 2 {
            // Half the first jump's height: height goes with the square of the speed.
            spec.jumps = 3
            spec.thirdJumpVelocity = spec.fullHopVelocity * 0.5.squareRoot()
        }
        spec.dashFrames += 4 * level(of: .lungeLemonade)
        spec.shotPace += 0.25 * Double(level(of: .cannonCola))
        spec.slideFrames += 8 * level(of: .slideCider)
        return spec
    }
}
