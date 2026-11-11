import EsperSim

extension GameMode {
    /// Modes shown but not open yet: greyed on the title and the multiplayer screen, nothing
    /// happening when picked. ZONES, until it's had its attention.
    static let parked: Set<GameMode> = [.zones]
}

extension GameMode {
    /// The mode's name on the customize and multiplayer screens.
    var title: String {
        switch self {
        case .rounds: "ROUNDS"
        case .fortySeven: "47"
        case .zones: "ZONES"
        case .breakerBall: "BREAKER BALL"
        }
    }
}
