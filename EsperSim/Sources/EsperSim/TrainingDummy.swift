/// The Test Center's training dummy: the other side, doing one thing over and over where it
/// stands, picked with the debug buttons. Each move waits till the body's settled on the ground
/// a moment, then goes again.
public struct TrainingDummy: Equatable {
    public enum Routine: Int, CaseIterable {
        /// Stands still.
        case idle
        /// Shield backflip, turn, shield backflip, turn.
        case shield
        case slash
        case snatch
        /// Jump, the Spin Move at the top, land; the ball handed back whenever it's loose.
        case spin

        public var label: String {
            switch self {
            case .idle: "IDLE"
            case .shield: "SHIELD"
            case .slash: "SLASH"
            case .snatch: "SNATCH"
            case .spin: "SPIN"
            }
        }
    }

    public let index: Int
    public var routine: Routine {
        didSet { if routine != oldValue { settledFrames = 0; turnsNext = false; jumpHeld = 0; throwHeld = 0; airFrames = 0 } }
    }
    /// Frames it's stood settled on the ground; at `restFrames` it moves.
    private var settledFrames = 0
    private var turnsNext = false
    private var jumpHeld = 0
    private var throwHeld = 0
    private var airFrames = 0

    public static let restFrames = 12
    /// The spin's jump held this long, and the throw down pressed this many frames into the air.
    public static let jumpHoldFrames = 12
    public static let spinAirFrame = 14
    public static let throwHoldFrames = 3

    public init(index: Int = 1, routine: Routine = .shield) {
        self.index = index
        self.routine = routine
    }

    /// This frame's input; for the Spin Move, the ball handed over first when it's loose.
    public mutating func decide(_ match: inout Match) -> PlayerInput {
        guard match.players.indices.contains(index) else { return .idle }
        let player = match.players[index]
        let settled = player.grounded && player.state.isGroundState && player.hitStun == 0 && player.frozen == 0
        settledFrames = settled ? settledFrames + 1 : 0
        airFrames = player.grounded ? 0 : airFrames + 1
        let moves = settledFrames >= TrainingDummy.restFrames
        switch routine {
        case .idle:
            return .idle
        case .shield:
            guard moves else { return .idle }
            settledFrames = 0
            let turns = turnsNext
            turnsNext.toggle()
            return turns ? PlayerInput(stick: Vec2(x: -player.facing.sign, y: 0)) : PlayerInput(shield: true)
        case .slash:
            guard moves else { return .idle }
            settledFrames = 0
            return PlayerInput(shoot: true)
        case .snatch:
            guard moves else { return .idle }
            settledFrames = 0
            return PlayerInput(throwBall: true)
        case .spin:
            if jumpHeld > 0 {
                jumpHeld -= 1
                return PlayerInput(jump: true)
            }
            if throwHeld > 0 {
                throwHeld -= 1
                return PlayerInput(stick: Vec2(x: 0, y: -1), throwBall: true)
            }
            if settled, !player.hasBall, match.ball.isLive, match.ball.holder == nil {
                match.giveBall(to: index)
                settledFrames = 0
                return .idle
            }
            if moves, player.hasBall {
                settledFrames = 0
                jumpHeld = TrainingDummy.jumpHoldFrames - 1
                return PlayerInput(jump: true)
            }
            if airFrames == TrainingDummy.spinAirFrame, player.hasBall {
                throwHeld = TrainingDummy.throwHoldFrames - 1
                return PlayerInput(stick: Vec2(x: 0, y: -1), throwBall: true)
            }
            return .idle
        }
    }
}

extension Match {
    /// The ball into a player's hands from wherever it is: the Test Center's dummy's.
    public mutating func giveBall(to index: Int) {
        guard players.indices.contains(index), ball.holder == nil else { return }
        ball.tornadoCentre = nil
        hand(ballTo: index)
    }
}
