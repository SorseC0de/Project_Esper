import Foundation

/// A best of seven: the rounds won, what each side has drunk, and the dice the offers
/// come from. A round is a point. Whoever is scored on drinks.
public struct Series: Equatable {
    public static let bestOf = 7
    /// Seconds to choose a drink in a networked match; not enforced yet.
    public static let pickSeconds = 20

    public var wins = [0, 0]
    public var drinks = [Drinks.none, Drinks.none]
    /// Who won each round so far.
    public var rounds: [Int] = []
    public var dice: Dice

    public init(seed: UInt32 = 1) {
        dice = Dice(seed: seed)
    }

    public var needed: Int { Series.bestOf / 2 + 1 }
    public var winner: Int? { wins.firstIndex { $0 >= needed } }

    /// Circles across the top: five, then one more for each round past the fifth.
    public var circles: Int { min(max(5, rounds.count + 1), Series.bestOf) }

    public mutating func record(pointFor player: Int) {
        wins[player] += 1
        rounds.append(player)
    }

    public mutating func offers(for player: Int) -> [Greateraid] {
        drinks[player].offers(&dice)
    }

    public mutating func drink(_ drink: Greateraid, by player: Int) {
        drinks[player].drink(drink)
    }

    /// A fresh series on the same dice, everything drunk gone.
    public func fresh() -> Series {
        var next = Series(seed: 1)
        next.dice = dice
        return next
    }
}
