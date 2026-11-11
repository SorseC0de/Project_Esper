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
public enum Greateraid: CaseIterable, Equatable, Hashable, Codable {
    case hastyHorchata, jumperJuice, cannonCola, slideCider, featherFloat, quakeUp, guarderade, shelterSeltzer, flobackFresca
    case webWater, superSmoothie, flashFizz, platformShake
    case voltaCola, frostTea, blazingBoba, pulsepistol, surfSoda, titanTea, galeAle, zTea, phantomFrappe

    public enum Kind: Equatable { case booster, biomorph }

    public static let boosters: [Greateraid] = [.hastyHorchata, .jumperJuice, .cannonCola, .slideCider, .featherFloat, .quakeUp,
                                                .guarderade, .shelterSeltzer, .flobackFresca]
    public static let biomorphs: [Greateraid] = [.webWater, .superSmoothie, .flashFizz, .platformShake,
                                                 .voltaCola, .frostTea, .blazingBoba, .pulsepistol, .surfSoda, .titanTea, .galeAle, .zTea,
                                                 .phantomFrappe]
    /// Drinks kept out of the offers for now, still drinkable by the debug picker.
    public static let parked: Set<Greateraid> = [.surfSoda]
    /// Every drink that can be offered or picked: all but the parked.
    public static let offered: [Greateraid] = allCases.filter { !parked.contains($0) }

    public var kind: Kind {
        Greateraid.boosters.contains(self) ? .booster : .biomorph
    }

    public var name: String {
        switch self {
        case .hastyHorchata: "Hasty Horchata"
        case .jumperJuice: "Jumper Juice"
        case .cannonCola: "Cannon Cola"
        case .slideCider: "Slide Cider"
        case .featherFloat: "Feather Float"
        case .webWater: "Web Water"
        case .superSmoothie: "Super Smoothie"
        case .flashFizz: "Flash Fizz"
        case .platformShake: "Platform Protein Shake"
        case .quakeUp: "Quake-Up Coffee"
        case .guarderade: "Guarderade"
        case .shelterSeltzer: "Shelter Seltzer"
        case .flobackFresca: "Floback Fresca"
        case .voltaCola: "Volta Cola"
        case .frostTea: "Frost Tea"
        case .blazingBoba: "Blazing Boba"
        case .pulsepistol: "Pulsepistol Punch"
        case .surfSoda: "Surf Soda"
        case .titanTea: "Titan Tea"
        case .galeAle: "Gale Ale"
        case .zTea: "Z Tea"
        case .phantomFrappe: "Phantom Frappe"
        }
    }

    /// The drink's own bottle in the asset catalog, when it has one: "Bottle-" and its name's
    /// letters ("Bottle-QuakeUpCoffee"); without one, the kind's bottle is drawn.
    public var bottleArt: String { "Bottle-" + name.filter(\.isLetter) }

    /// The power a biomorph gives.
    public var power: Power? {
        switch self {
        case .webWater: .webWater
        case .superSmoothie: .superSmoothie
        case .flashFizz: .flashFizz
        case .platformShake: .platformShake
        case .voltaCola: .voltaCola
        case .frostTea: .frostTea
        case .blazingBoba: .blazingBoba
        case .pulsepistol: .pulsepistol
        case .surfSoda: .surfSoda
        case .titanTea: .titanTea
        case .galeAle: .galeAle
        case .zTea: .zTea
        case .phantomFrappe: .phantomFrappe
        default: nil
        }
    }

    /// The line on the bottle, above what it does.
    public var comment: String {
        switch self {
        case .hastyHorchata: "The perfect drink for fasting"
        case .jumperJuice: "Don't get too hopped up on this"
        case .cannonCola: "Best served as a shooter"
        case .slideCider: "DMs not included"
        case .webWater: "I thought this was alkaline not radioactive"
        case .superSmoothie: "So THIS is what was in that Special Stuff MJ drank"
        case .flashFizz: "Now you see me, now I dunk"
        case .platformShake: "From staring up to the basket to stairing up to the basket"
        case .quakeUp: "Suddenly everyone around you seems so grounded"
        case .guarderade: "The sweet taste of rejection"
        case .shelterSeltzer: "In your defense, the aftertaste does linger"
        case .flobackFresca: "The sweet taste of payback"
        case .voltaCola: "A shocking amount of flavor"
        case .frostTea: "Not to be confused with the gas station beverage"
        case .blazingBoba: "...Wait are those fireballs?"
        case .pulsepistol: "For those gunning for first place"
        case .surfSoda: "..."
        case .featherFloat: "Slowly fall with every sip"
        case .titanTea: "An attack on heightlessness"
        case .galeAle: "Wind did things become such a breeze?"
        case .zTea: "Your opponent will have a blast with this one"
        case .phantomFrappe: "Goes right through you"
        }
    }

    /// What the first drink does, and what the second adds.
    public var blurbs: (first: String, second: String) {
        switch self {
        case .hastyHorchata: ("[Movement Speed] Up.", "[Movement Speed] Up.")
        case .jumperJuice: ("Increased [Jump Height].", "Increased [Jump Height] + an [Extra Jump].")
        case .cannonCola: ("[Shooting Speed] Up.", "[Shooting Speed] Up.")
        case .slideCider: ("Your [Slides] have increased knockback and can catch the ball.", "Your [Slides] cause [Stun].")
        case .webWater: ("Your [Double Jump] becomes a [Web Swing]", "Your [Snatch] becomes a pulling [Web Line].")
        case .superSmoothie: ("Hold [Jump] in the air to [Fly] in any direction.", "From grounded, hold [Up] + [Jump] to [Super Jump] into [Flight].")
        case .flashFizz: ("Your [Double Jump] becomes a [Teleport]. Press [Up] or [Down] + [Strike] to [Teleport] to the ball after a [Shot] or [Throw].", "You can [Teleport] a second time with [Jump]. You can [Teleport] to a loose ball.")
        case .platformShake: ("[Fast Fall] to create a [Platform] below.", "Press [Up] or [Down] + [Strike] to create a vertical [Platform] in front.")
        case .quakeUp: ("Your [Fast Fall] causes a [Quake] to shared ground.", "Your [Fast Fall] causes a [Quake] to ground anywhere.")
        case .guarderade: ("Your [Shield] is bigger.", "[Shield] a second time before you land.")
        case .shelterSeltzer: ("Your [Shield] lingers where it's created.", "Your [Snatches] raise a [Shield].")
        case .flobackFresca: ("Gain [FLO] when hit or [Stripped].", "Gain [FLO] when [Throwing] the ball")
        case .voltaCola: ("[Strike] becomes a [Lightning Bolt] throw.", "Your [Throws] call down a [Lightning Strike] on the ball.")
        case .frostTea: ("Your [Snatches] cause [Freeze]", "[Double Jump] and [Slide] leave an [Ice Clone] that freezes on touch.")
        case .blazingBoba: ("Your [Shots] and [Throws] are too hot to catch or [Snatch].", "Press [Up] or [Down] + [Strike] to create a [Fireball].")
        case .pulsepistol: ("[Up] or [Down] + [Strike] fires a [Kinesis Pulse].", "You can fire [Kinesis Pulses] while moving. Hold [Down] while grounded to [Kinesis Snipe].")
        case .surfSoda: ("Ride a board: jumps are a crescent, and in the air you flip it to shield yourself.", "...")
        case .featherFloat: ("You [Weigh Less].", "You [Weigh Less].")
        case .titanTea: ("You become [Giant] but cannot [Double Jump].",
                         "[Trample] the opponent to [Strip] them of the ball.")
        case .galeAle: ("Your [Double Jumps] leave a [Tornado].", "Press [Up] or [Down] + [Strike] to fire a moving [Tornado].")
        case .zTea: ("Press [Up] + [Strike] to fire a [Blast]. Press [Down] + [Strike] to charge and fire an aimable [Beam].",
                     "You fire [Blasts] faster and can [Store] a charged [Beam] to release at any time")
        case .phantomFrappe: ("[Spin Move] or [Taunt] to toggle [Phantom Mode]: you phase through everything including walls, floors, and attacks.",
                              "You can [Spin Move] a second time before landing.")
        }
    }
}

/// What a player has drunk.
public struct Drinks: Equatable {
    public static let maxBoosterLevel = 2
    public static let offerCount = 3
    /// A booster's weight against a biomorph's in an offer.
    public static let boosterWeight = 3
    /// Titan Tea's jumps leave this much faster, so a body twice the size gets well off the floor.
    public static let titanJumpShare = 1.25

    /// Levels by booster, looked up only, never walked.
    public var boosters: [Greateraid: Int] = [:]
    public var biomorph: Greateraid?
    public var biomorphLevel = 0

    public static let none = Drinks()

    public init() {}

    /// The one drink picked before a series in a mode without the Greateraid between rounds
    /// (47), at its second level: a booster drunk twice, or a biomorph's second sip. None, none.
    public static func levelTwo(_ drink: Greateraid?) -> Drinks {
        var drinks = Drinks()
        guard let drink else { return drinks }
        switch drink.kind {
        case .booster: drinks.boosters[drink] = Drinks.maxBoosterLevel
        case .biomorph:
            drinks.biomorph = drink
            drinks.biomorphLevel = 2
        }
        return drinks
    }

    public func level(of drink: Greateraid) -> Int {
        switch drink.kind {
        case .booster: boosters[drink] ?? 0
        case .biomorph: biomorph == drink ? biomorphLevel : 0
        }
    }

    /// Whether the offer of `drink` is the second sip of the biomorph in hand.
    public func isSecondSip(_ drink: Greateraid) -> Bool {
        (drink.kind == .biomorph && biomorph == drink) || (drink.kind == .booster && level(of: drink) == 1)
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
            biomorphsLeft = Greateraid.biomorphs.filter { !Greateraid.parked.contains($0) }
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
    /// adds half a unit of run, dash and air speed and four frames of dash a drink; Jumper
    /// Juice makes both jumps a tenth higher, then adds a third jump half as high as the first;
    /// Cannon Cola a quarter more shot pace a drink, the same arc run faster and the shot's
    /// pose with it; Slide Cider's level for the slide's knock, catch and stun (`SlideRules`).
    public func spec(from base: FighterSpec = .starting) -> FighterSpec {
        var spec = base
        let hasty = Double(level(of: .hastyHorchata))
        spec.runSpeed += 0.5 * hasty
        spec.dashInitialVelocity = spec.runSpeed + 0.4
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
        spec.dashFrames += 4 * level(of: .hastyHorchata)
        spec.shotPace += 0.25 * Double(level(of: .cannonCola))
        spec.slideCiderLevel = level(of: .slideCider)
        spec.guarderadeLevel = level(of: .guarderade)
        spec.shelterSeltzerLevel = level(of: .shelterSeltzer)
        spec.flobackFrescaLevel = level(of: .flobackFresca)
        // Quake-Up Coffee: a fast fall's landing quakes the floor; at level two, all of it.
        spec.quakeLevel = level(of: .quakeUp)
        // Feather Float: falling, a quarter of gravity gone a drink.
        spec.fallGravityShare = 1 - 0.25 * Double(level(of: .featherFloat))
        if biomorph == .titanTea {
            // Titan Tea: twice the size, half the knock, a fifth more gravity falling (the jumps
            // as high as ever) and a fifth more fall speed; a tenth off the walk and run, the
            // dash still 0.4 over the run, and at level one actions a tenth slower. One jump,
            // unless Jumper Juice gives the rest back.
            spec.scale = 2
            spec.bodyWidth *= 2
            spec.bodyHeight *= 2
            spec.knockbackShare = 0.5
            spec.fallGravityShare *= 1.2
            spec.fallSpeed *= 1.2
            spec.fastFallSpeed *= 1.2
            spec.canCrouch = false
            spec.fullHopVelocity *= Drinks.titanJumpShare
            spec.shortHopVelocity *= Drinks.titanJumpShare
            spec.doubleJumpVelocity *= Drinks.titanJumpShare
            spec.thirdJumpVelocity *= Drinks.titanJumpShare
            spec.jumps = jumper == 0 ? 1 : spec.jumps
            spec.walkMaxSpeed *= 0.9
            spec.runSpeed *= 0.9
            spec.dashInitialVelocity = spec.runSpeed + 0.4
            if biomorphLevel < 2 { spec.actionHoldInterval = 10 }
        }
        return spec
    }
}
