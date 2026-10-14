import Foundation

/// ZONES: HORSE on a grid. One player leads: from A1 with the ball they run, jump and do
/// whatever they like, then take their one shot. Where each action started is logged by zone,
/// and the other player has to follow the same sequence, zone for zone, and score; failing to
/// earns a letter of Z-O-N-E-S. Five letters loses. The leader records a run they like in up to
/// three tries, then has three tries to do it again to submit it; the follower has three
/// tries to match it. A leader who can't score, or can't repeat their run, hands over the lead
/// with no letter given. A follower's success or failure keeps the leader leading.
public enum ZonesRules {
    /// A zone is this many tiles across and up; what doesn't divide goes to A1's column and row.
    public static let zoneTiles = 4
    /// A run has this long to get to its shot.
    public static let runFrames = 30 * 60
    /// After the shot, this long at most for it to settle.
    public static let shotSettleFrames = 10 * 60
    public static let tries = 3
    public static let word = "ZONES"
    public static var lettersToLose: Int { word.count }
    /// The power picked for FloState comes at level two.
    public static let powerLevel = 2
    /// Where a run starts: the floor of the first zone, in from the left wall, facing right.
    public static let startX = 2.5 * Stage.tileSize
    /// The stages ZONES is played on: 47's, the small ones.
    /// Its stages: 47's but the plane, whose pitch and cart would make a run too much of a lottery.
    public static let stages: [StageChoice] = [.wreckCenter, .hoopfishHideaway, .kAndA]
}

/// A zone of the grid: its column, A upward, and its row, 1 upward from the floor.
public struct Zone: Hashable, Codable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    /// Its name, E5.
    public var name: String { "\(Zone.letter(column))\(row + 1)" }

    public static func letter(_ column: Int) -> String { String(Character(UnicodeScalar(65 + min(max(column, 0), 25))!)) }
}

/// How a stage divides into zones: `zoneTiles` wide and tall each but the first column and
/// row, which take what's left over.
public struct ZoneGrid: Equatable {
    public let columns: Int
    public let rows: Int
    /// The first column's width and the first row's height, in tiles.
    public let firstColumnTiles: Int
    public let firstRowTiles: Int

    public init(stage: Stage) {
        self.init(columns: stage.columns, rows: stage.rows)
    }

    public init(columns stageColumns: Int, rows stageRows: Int) {
        let across = max(stageColumns / ZonesRules.zoneTiles, 1), up = max(stageRows / ZonesRules.zoneTiles, 1)
        columns = across
        rows = up
        firstColumnTiles = stageColumns - (across - 1) * ZonesRules.zoneTiles
        firstRowTiles = stageRows - (up - 1) * ZonesRules.zoneTiles
    }

    public func zone(of point: Vec2) -> Zone {
        Zone(column: index(of: point.x, first: firstColumnTiles, count: columns),
             row: index(of: point.y, first: firstRowTiles, count: rows))
    }

    private func index(of distance: Double, first: Int, count: Int) -> Int {
        let tile = Int((distance / Stage.tileSize).rounded(.down))
        guard tile >= first else { return 0 }
        return min(1 + (tile - first) / ZonesRules.zoneTiles, count - 1)
    }

    /// Where the lines between columns stand, in units from the left, and between rows, up from the floor.
    public var columnLines: [Double] { (0..<(columns - 1)).map { Double(firstColumnTiles + $0 * ZonesRules.zoneTiles) * Stage.tileSize } }
    public var rowLines: [Double] { (0..<(rows - 1)).map { Double(firstRowTiles + $0 * ZonesRules.zoneTiles) * Stage.tileSize } }

    /// A column's span and a row's, in units.
    public func columnSpan(_ column: Int) -> ClosedRange<Double> {
        let left = column == 0 ? 0 : Double(firstColumnTiles + (column - 1) * ZonesRules.zoneTiles) * Stage.tileSize
        let width = Double(column == 0 ? firstColumnTiles : ZonesRules.zoneTiles) * Stage.tileSize
        return left...(left + width)
    }

    public func rowSpan(_ row: Int) -> ClosedRange<Double> {
        let bottom = row == 0 ? 0 : Double(firstRowTiles + (row - 1) * ZonesRules.zoneTiles) * Stage.tileSize
        let height = Double(row == 0 ? firstRowTiles : ZonesRules.zoneTiles) * Stage.tileSize
        return bottom...(bottom + height)
    }
}

/// What a run logs: the action and the zone it started in. Two match when both do.
public struct ZoneAction: Hashable, Codable {
    public enum Kind: String, Codable, CaseIterable {
        /// Moving along the ground, a walk, a dash or a run alike: the stick's push isn't told apart.
        case move
        case jump, doubleJump, wallJump, crouch, slide, taunt, throwBall, catchBall
        case floStateOn, floStateOff
        /// A power's move; `label` says which.
        case power
        /// The shot that ends the run, or the dunk.
        case shoot, dunk

        public var label: String {
            switch self {
            case .move: "Move"
            case .jump: "Jump"
            case .doubleJump: "Double Jump"
            case .wallJump: "Wall Jump"
            case .crouch: "Crouch"
            case .slide: "Slide"
            case .taunt: "Taunt"
            case .throwBall: "Throw"
            case .catchBall: "Catch"
            case .floStateOn: "FloState"
            case .floStateOff: "FloState Off"
            case .power: "Power"
            case .shoot: "Shoot"
            case .dunk: "Dunk"
            }
        }

        /// The shot or the dunk: the run's end.
        public var endsRun: Bool { self == .shoot || self == .dunk }
    }

    public var kind: Kind
    /// A power move's name; the kind's own for the rest.
    public var label: String
    public var zone: Zone
    /// The frame of the run it started on.
    public var frame: Int

    public init(kind: Kind, label: String? = nil, zone: Zone, frame: Int) {
        self.kind = kind
        self.label = label ?? kind.label
        self.zone = zone
        self.frame = frame
    }

    /// Whether `other` is the same move in the same zone: the frame doesn't count.
    public func matches(_ other: ZoneAction) -> Bool { kind == other.kind && label == other.label && zone == other.zone }

    /// As the log reads it: "Jump at E1".
    public var line: String { "\(label) at \(zone.name)" }
}

/// A run as recorded: its actions, the inputs that made it (so another phone can replay it to
/// the frame), and the power picked for FloState.
public struct ZonesRun: Equatable, Codable {
    public var actions: [ZoneAction] = []
    public var inputs: [PlayerInput] = []
    public var floStatePower: Power = .none

    public init(actions: [ZoneAction] = [], inputs: [PlayerInput] = [], floStatePower: Power = .none) {
        self.actions = actions
        self.inputs = inputs
        self.floStatePower = floStatePower
    }

    public var frames: Int { inputs.count }

    // Coded with the inputs packed as they go over the wire, five bytes a frame, so a run of
    // thirty seconds is nine kilobytes, well inside a turn's room; what plays back is the
    // quantized input the recorder was given.
    private enum CodingKeys: String, CodingKey { case actions, inputs, floStatePower }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        actions = try container.decode([ZoneAction].self, forKey: .actions)
        floStatePower = try container.decode(Power.self, forKey: .floStatePower)
        inputs = ZonesRun.unpack(try container.decode(Data.self, forKey: .inputs))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actions, forKey: .actions)
        try container.encode(floStatePower, forKey: .floStatePower)
        try container.encode(ZonesRun.pack(inputs), forKey: .inputs)
    }

    public static func pack(_ inputs: [PlayerInput]) -> Data {
        var data = Data()
        data.reserveCapacity(inputs.count * PlayerInput.wireBytes)
        for input in inputs { input.encode(into: &data) }
        return data
    }

    public static func unpack(_ data: Data) -> [PlayerInput] {
        let bytes = [UInt8](data)
        let whole = bytes.count - bytes.count % PlayerInput.wireBytes
        return stride(from: 0, to: whole, by: PlayerInput.wireBytes).map { PlayerInput.decode(bytes, at: $0) }
    }

    /// Whether `other` follows this run move for move, zone for zone.
    public func isFollowed(by other: ZonesRun) -> Bool {
        actions.count == other.actions.count && zip(actions, other.actions).allSatisfy { $0.matches($1) }
    }
}

/// Watches one player through a run, logging each action as it starts, and tells how the run
/// ended: the shot made, missed, the time up, or, following a set run, the first move that
/// strayed from it.
public struct ZonesRecorder: Equatable {
    public enum Outcome: Equatable {
        case made, missed, timedOut
        /// Following, the action logged that didn't match the set run's next.
        case strayed(at: Int)
    }

    public private(set) var run: ZonesRun
    public private(set) var outcome: Outcome?
    /// The run being followed, if any: each action logged is checked against its next.
    public let target: ZonesRun?
    private let player: Int
    private let grid: ZoneGrid
    private var lastState: PlayerState
    private var wasInFloState: Bool
    private var shotFrame: Int?

    public init(match: Match, player: Int, target: ZonesRun? = nil) {
        self.player = player
        self.target = target
        grid = ZoneGrid(stage: match.stage)
        run = ZonesRun(floStatePower: match.players.indices.contains(player) ? match.players[player].floStatePower : .none)
        lastState = match.players.indices.contains(player) ? match.players[player].state : .idle
        wasInFloState = match.players.indices.contains(player) && match.players[player].inFloState
    }

    public var ended: Bool { outcome != nil }
    /// How many of the target's actions have been matched so far.
    /// How many of the target's actions have been matched: the strayed one isn't.
    public var followed: Int {
        if case .strayed = outcome { return max(run.actions.count - 1, 0) }
        return run.actions.count
    }

    /// The ground states that are one move.
    static let moving: Set<PlayerState> = [.walk, .dash, .run, .pivot]

    /// A frame on, after the match has advanced on `input`.
    public mutating func observe(_ match: Match, input: PlayerInput) {
        guard outcome == nil, match.players.indices.contains(player) else { return }
        run.inputs.append(input)
        let frame = run.frames
        let me = match.players[player]
        let zone = grid.zone(of: me.position)
        var logged: [ZoneAction] = []
        func log(_ kind: ZoneAction.Kind, _ label: String? = nil) { logged.append(ZoneAction(kind: kind, label: label, zone: zone, frame: frame)) }

        if shotFrame == nil {
            // The states that begin a move, as they're entered.
            let state = me.state
            if state != lastState {
                switch state {
                // Walking, dashing, running and turning in a run are one move, from its start.
                case .walk, .dash, .run, .pivot: if !ZonesRecorder.moving.contains(lastState) { log(.move) }
                case .crouch, .crouchWalk: if lastState != .crouch && lastState != .crouchWalk { log(.crouch) }
                case .taunt: log(.taunt)
                case .slide: log(.slide)
                case .transforming: log(.floStateOn)
                default: break
                }
            }
            lastState = state
            if !me.inFloState, wasInFloState { log(.floStateOff) }
            wasInFloState = me.inFloState
            // The moves the match reports.
            for event in match.events {
                switch event {
                case .jumped(let who) where who == player: log(.jump)
                case .doubleJumped(let who) where who == player: log(.doubleJump)
                case .wallJumped(let who, _) where who == player: log(.wallJump)
                // An up-throw is the floater, and a throw down at the Hoopfish's rim goes
                // through it: shots, the run's end.
                case .thrown(let who) where who == player:
                    if match.ball.floaterShot { log(.shoot, "Floater") } else if match.ball.scoring { log(.shoot, "Throw Down") } else { log(.throwBall) }
                case .caught(let who) where who == player: log(.catchBall)
                case .shot(let who) where who == player: log(.shoot)
                case .dunked(let who) where who == player: log(.dunk)
                case .boltFired(let who) where who == player: log(.power, "Bolt")
                case .beamFired(let who, _, _) where who == player: log(.power, "Beam")
                case .galeMade: if me.power == .galeAle { log(.power, "Gale") }
                case .flew(let who) where who == player: log(.power, "Fly")
                case .webSwung(let who) where who == player: log(.power, "Web")
                case .webLine(let who, _) where who == player: log(.power, "Web")
                case .flashed(let who, _, _) where who == player: log(.power, "Flash")
                case .platformMade(let who) where who == player: log(.power, "Wall")
                case .pulsed(let who, _) where who == player: log(.power, "Pulse")
                case .fireballMade(let who) where who == player: log(.power, "Fireball")
                case .quaked(let who) where who == player: log(.power, "Quake")
                default: break
                }
            }
        }

        for action in logged where shotFrame == nil {
            let index = run.actions.count
            run.actions.append(action)
            if let target {
                guard target.actions.indices.contains(index), target.actions[index].matches(action) else {
                    outcome = .strayed(at: index)
                    return
                }
            }
            if action.kind.endsRun { shotFrame = frame }
        }

        if let shotFrame {
            // The shot: made as it goes through; missed once the ball's falling wholly under
            // the rim it can't drop into any more (a floater's still rising), or caught or
            // gone; or not settled in time.
            if match.events.contains(where: { if case .scored(let who, _, _, _, _) = $0 { return who == player } else { return false } }) {
                outcome = .made
            } else if frame - shotFrame > ZonesRules.shotSettleFrames {
                outcome = .missed
            } else if match.ball.holder != nil || !match.ball.isLive {
                outcome = .missed
            } else if match.ball.floater == 0, match.ball.enteringHoop == nil, match.ball.velocity.y < 0,
                      match.stage.hoops.allSatisfy({ $0.rimless || match.ball.position.y + BallRules.radius < $0.position.y }) {
                outcome = .missed
            }
        } else if frame >= ZonesRules.runFrames {
            outcome = .timedOut
        }
    }
}

/// A game of ZONES: who leads, the letters, what's been set and where the turn is.
public struct ZonesGame: Equatable, Codable {
    public enum Phase: Equatable, Codable {
        /// The leader loose on the stage before recording.
        case lobby
        /// The leader recording, their `attempt` of three.
        case recording(attempt: Int)
        /// The leader doing their recorded run again to submit it.
        case confirming(attempt: Int)
        /// The follower watching the set run play.
        case watching
        /// The follower on their `attempt` of three at the set run.
        case following(attempt: Int)
        case over(winner: Int)
    }

    public var leader: Int
    public var letters = [0, 0]
    public var phase = Phase.lobby
    /// The leader's made run, kept to be confirmed.
    public var candidate: ZonesRun?
    /// The run the follower has to match.
    public var set: ZonesRun?
    /// Watching the run again mid-turn: the phase to go back to after.
    public var resumeAfterWatching: Phase?
    public var stage: StageChoice
    /// How many runs each side has led, for the log.
    public var turns = 0
    /// How often the lead has passed without a run set.
    public var leadPasses = 0

    public init(leader: Int, stage: StageChoice) {
        self.leader = leader
        self.stage = stage
    }

    public var follower: Int { 1 - leader }
    /// Whose turn it is to move.
    public var mover: Int {
        switch phase {
        case .lobby, .recording, .confirming: leader
        case .watching: { if case .confirming = resumeAfterWatching { leader } else { follower } }()
        case .following: follower
        case .over(let winner): winner
        }
    }
    public var winner: Int? { if case .over(let winner) = phase { winner } else { nil } }
    /// Before anything's happened: the coin's just been flipped.
    public var isAtStart: Bool { phase == .lobby && turns == 0 && leadPasses == 0 && letters == [0, 0] && candidate == nil && set == nil }

    /// The leader presses to begin recording.
    public mutating func beginRecording() {
        guard phase == .lobby else { return }
        candidate = nil
        phase = .recording(attempt: 1)
    }

    /// The leader, happy with a made run, goes on to confirm it.
    public mutating func keepCandidate() {
        guard case .recording = phase, candidate != nil else { return }
        phase = .confirming(attempt: 1)
    }

    /// A rewind pressed: another try at the same thing, while there are any.
    public mutating func rewind() {
        switch phase {
        case .recording(let attempt) where attempt < ZonesRules.tries: phase = .recording(attempt: attempt + 1)
        case .confirming(let attempt) where attempt < ZonesRules.tries: phase = .confirming(attempt: attempt + 1)
        case .following(let attempt) where attempt < ZonesRules.tries: phase = .following(attempt: attempt + 1)
        default: break
        }
    }

    /// The run being watched: the set one, or the leader's own candidate while confirming.
    public var watched: ZonesRun? { self.set ?? candidate }

    /// The watching done: the follower's first try, or back to the try it was watched from.
    public mutating func beginFollowing() {
        guard phase == .watching else { return }
        phase = resumeAfterWatching ?? .following(attempt: 1)
        resumeAfterWatching = nil
    }

    /// The run watched again, from a try of following it or confirming it, which goes on after.
    public mutating func watchAgain() {
        switch phase {
        case .following, .confirming:
            guard watched != nil else { return }
            resumeAfterWatching = phase
            phase = .watching
        default: break
        }
    }

    /// A run over: what it means for the turn. Returns what happened, for the screen.
    public enum Result: Equatable {
        /// The leader made a run: kept as the candidate; on the last try it's kept outright.
        case candidateMade(last: Bool)
        /// A try failed with more to come.
        case tryAgain(left: Int)
        /// The leader couldn't score, or couldn't repeat the run: the other leads.
        case leadPassed
        /// The leader confirmed the run: the follower's turn.
        case runSet
        /// The follower matched it.
        case followed
        /// The follower failed every try: a letter, and maybe the game.
        case letter(count: Int, lost: Bool)
    }

    @discardableResult
    public mutating func runEnded(_ run: ZonesRun, outcome: ZonesRecorder.Outcome) -> Result {
        switch phase {
        case .recording(let attempt):
            if outcome == .made {
                candidate = run
                if attempt >= ZonesRules.tries { phase = .confirming(attempt: 1) }
                return .candidateMade(last: attempt >= ZonesRules.tries)
            }
            if attempt < ZonesRules.tries { return .tryAgain(left: ZonesRules.tries - attempt) }
            // Out of tries with nothing made, unless an earlier try was.
            if candidate != nil {
                phase = .confirming(attempt: 1)
                return .candidateMade(last: true)
            }
            passLead()
            return .leadPassed
        case .confirming(let attempt):
            if outcome == .made, let candidate, candidate.isFollowed(by: run) {
                set = candidate
                self.candidate = nil
                phase = .watching
                turns += 1
                return .runSet
            }
            if attempt < ZonesRules.tries { return .tryAgain(left: ZonesRules.tries - attempt) }
            passLead()
            return .leadPassed
        case .following(let attempt):
            if outcome == .made, let set, set.isFollowed(by: run) {
                self.set = nil
                phase = .lobby
                return .followed
            }
            if attempt < ZonesRules.tries { return .tryAgain(left: ZonesRules.tries - attempt) }
            letters[follower] += 1
            let lost = letters[follower] >= ZonesRules.lettersToLose
            set = nil
            phase = lost ? .over(winner: leader) : .lobby
            return .letter(count: letters[follower], lost: lost)
        default:
            return .tryAgain(left: 0)
        }
    }

    /// The mover gave their turn up (online, a turn timed out): a leader passes the lead, a
    /// follower takes the letter, with no run.
    public mutating func forfeitTurn() {
        switch phase {
        case .lobby, .recording, .confirming:
            passLead()
        case .watching, .following:
            letters[follower] += 1
            let lost = letters[follower] >= ZonesRules.lettersToLose
            set = nil
            resumeAfterWatching = nil
            phase = lost ? .over(winner: leader) : .lobby
        case .over:
            break
        }
    }

    private mutating func passLead() {
        candidate = nil
        set = nil
        leader = follower
        leadPasses += 1
        phase = .lobby
    }

    /// The letters a side has, as shown: Z, ZO, ZON...
    public func lettersShown(_ player: Int) -> String {
        String(ZonesRules.word.prefix(min(max(letters[player], 0), ZonesRules.word.count)))
    }
}
