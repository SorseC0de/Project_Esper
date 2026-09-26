import Foundation

/// A best of seven: the rounds won, what each side has drunk, and the dice the offers
/// come from. A round is a point. Whoever is scored on drinks. A stage stays for a best of
/// three: the first to two points on it sends both to the stage select.
public struct Series: Equatable {
    public static let bestOf = 7
    public static let pointsPerStage = 2
    /// Seconds to choose a drink in a networked match; not enforced yet.
    public static let pickSeconds = 20

    public var wins = [0, 0]
    public var drinks = [Drinks.none, Drinks.none]
    /// Who won each round so far.
    public var rounds: [Int] = []
    public var dice: Dice
    public var stage = StageChoice.wreckCenter
    /// Points won on this stage, and how many stages have been played out before it.
    public var stageWins = [0, 0]
    public var stagesPlayed = 0

    public init(seed: UInt32 = 1) {
        dice = Dice(seed: seed)
    }

    public var needed: Int { Series.bestOf / 2 + 1 }
    public var winner: Int? { wins.firstIndex { $0 >= needed } }

    /// Circles across the top: five, then one more for each round past the fifth.
    public var circles: Int { min(max(5, rounds.count + 1), Series.bestOf) }

    public mutating func record(pointFor player: Int) {
        wins[player] += 1
        stageWins[player] += 1
        rounds.append(player)
    }

    /// Who took this stage's best of three, if anyone has yet.
    public var stageWinner: Int? { stageWins.firstIndex { $0 >= Series.pointsPerStage } }
    /// This stage is done and the series isn't: on to the stage select.
    public var stageSelectDue: Bool { stageWinner != nil && winner == nil }

    public mutating func move(to next: StageChoice) {
        stage = next
        stageWins = [0, 0]
        stagesPlayed += 1
    }

    /// Two votes the same go there; two different, a coin flip between them on the dice.
    public mutating func settle(votes: [StageChoice]) -> StageChoice {
        guard let first = votes.first else { return stage }
        guard votes.contains(where: { $0 != first }) else { return first }
        return votes[dice.roll(votes.count)]
    }

    public mutating func offers(for player: Int) -> [Greateraid] {
        drinks[player].offers(&dice)
    }

    public mutating func drink(_ drink: Greateraid, by player: Int) {
        drinks[player].drink(drink)
    }

    /// A fresh series on the same dice and stage, everything drunk gone.
    public func fresh() -> Series {
        var next = Series(seed: 1)
        next.dice = dice
        next.stage = stage
        return next
    }
}

/// What a match is played to: a best of seven of rounds, a point each and a drink
/// between, or 47, played on through its baskets, two or three points each, to 47.
public enum GameMode: UInt8, CaseIterable {
    case rounds, fortySeven
}

/// 47's numbers. A basket from outside the three-point line, a circle round the rim out
/// to the middle platform's nearest edge, is three; from inside it, or a dunk, two. The
/// scorer can't take the ball for a second after, so play goes the other way.
public enum FortySevenRules {
    public static let target = 47
    public static let scorerLockoutFrames = 120
    /// Without a one-way platform to reach, this far.
    public static let fallbackRadius = 90.0

    public static func threePointRadius(for hoop: Hoop, on stage: Stage) -> Double {
        var nearest: Double?
        for column in 0..<stage.columns {
            guard (0..<stage.rows).contains(where: { stage.tile(column: column, row: $0) == .oneWay }) else { continue }
            for edge in [Double(column) * Stage.tileSize, Double(column + 1) * Stage.tileSize] {
                let reach = abs(edge - hoop.position.x)
                if reach < nearest ?? .infinity { nearest = reach }
            }
        }
        return nearest ?? fallbackRadius
    }

    /// Two or three for a basket through `hoop`, by where the ball left a hand.
    public static func points(from launch: Vec2?, through hoop: Hoop, on stage: Stage) -> Int {
        guard let launch else { return 2 }
        return launch.distance(to: hoop.position) > threePointRadius(for: hoop, on: stage) ? 3 : 2
    }
}
