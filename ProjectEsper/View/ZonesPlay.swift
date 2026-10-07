import EsperSim
import SpriteKit
import SwiftUI

/// ZONES as the scene plays it: one player on the stage at a time, the turn's state
/// (`ZonesGame`), the run being recorded or followed (`ZonesRecorder`), the set run played
/// back as a ghost, the phantoms left where each move started, the zone lines, and the
/// leader's crown. The scene owns one of these through a game and calls it from its loop.
@MainActor
final class ZonesPlay {
    /// Who the two sides are: two people passing one device, one person playing both sides
    /// (no hand-off screens), or the computer leading and following.
    enum Opponent { case passAndPlay, practice, cpu }

    /// What the scene's loop should do this frame.
    enum Step: Equatable {
        /// Held: nothing advances (a screen is up, or a result is being read).
        case hold
        /// The mover plays on their own input.
        case play
        /// The set run replays on its own input, drawn as a ghost.
        case replay(PlayerInput)
    }

    /// Something the screen's buttons or the pad ask for.
    enum Request { case record, keep, rewind, skip, replay, proceed, pickPower(Power) }

    var game: ZonesGame
    let opponent: Opponent
    private(set) var recorder: ZonesRecorder?
    /// Each side's FloState power pick.
    var powers: [Power] = [.none, .none]
    /// The screens between: the coin flip at the start, a hand-off between people, a result.
    enum Pause: Equatable { case coinFlip, handOff, result(String), choice }
    private(set) var pause: Pause? = .coinFlip
    /// After a run ends, frames to let the shot be seen, the sim running on, before the result's up.
    private var settle = 0
    /// The ghost replay: its frame, and after its last input the frames waited for its shot.
    private var replayFrame = 0
    private var replayTail = 0
    /// Skipped: the rest of the replay run through as fast as the loop allows, so its phantoms still drop.
    private(set) var fastForward = false
    /// The result of the run just ended, to act on once it's been seen.
    private var pendingResult: ZonesGame.Result?
    private var pendingOutcome: ZonesRecorder.Outcome?
    private var lastProceed = 0.0
    static let proceedGapSeconds = 0.4

    // What's drawn.
    private let lines = SKNode()
    private var phantoms: [SKNode] = []
    private let crown: SKSpriteNode
    private var crownTexture: (RGB, SKTexture?)?

    init(leader: Int, stage: StageChoice, opponent: Opponent) {
        game = ZonesGame(leader: leader, stage: stage)
        self.opponent = opponent
        crown = SKSpriteNode()
        crown.zPosition = 40
        crown.isHidden = true
    }

    var mover: Int { game.mover }
    /// The power the mover goes into FloState with: the follower's is the leader's.
    var moverPower: Power {
        switch game.phase {
        case .watching, .following: game.watched?.floStatePower ?? .none
        default: powers[game.leader]
        }
    }

    // MARK: The turn

    /// What to do this frame, and the frames of the loop before it.
    func step() -> Step {
        if pause != nil { return .hold }
        if settle > 0 {
            // The run's over: the sim plays on a moment so the shot's seen through, then the result.
            settle -= 1
            if settle == 0, let outcome = pendingOutcome {
                pendingOutcome = nil
                settleRun(outcome)
                return .hold
            }
            return .play
        }
        switch game.phase {
        case .lobby: return .play
        case .recording, .confirming, .following: return recorder == nil ? .hold : .play
        case .watching:
            guard let set = game.watched else { return .hold }
            if replayFrame < set.inputs.count {
                let input = set.inputs[replayFrame]
                replayFrame += 1
                return .replay(input)
            }
            return .replay(.idle)
        case .over: return .hold
        }
    }

    /// The match a frame on, on `input`, for the recorder; and the phantoms it earns.
    /// Returns the actions logged this frame, for the scene to mark.
    func observe(_ match: Match, input: PlayerInput) -> [ZoneAction] {
        if case .watching = game.phase, let set = game.watched {
            // The ghost: its moves drop phantoms at their frames; done once it's played through
            // and the shot's settled, then back to the try it's watched from, or the first.
            let dropped = set.actions.filter { $0.frame == replayFrame }
            if replayFrame >= set.inputs.count {
                replayTail += 1
                if replayTail > ZonesRules.shotSettleFrames / 4 || match.events.contains(where: { if case .scored = $0 { return true } else { return false } }) {
                    replayTail = 0
                    fastForward = false
                    game.beginFollowing()
                    switch game.phase {
                    case .confirming(let attempt): pause = .result("YOUR RUN: DO IT AGAIN, TRY \(attempt)")
                    case .following(let attempt): pause = .result(attempt == 1 ? "YOUR TURN: \(ZonesRules.tries) TRIES" : "TRY \(attempt)")
                    default: pause = .result("GO ON")
                    }
                }
            }
            return dropped
        }
        guard var recorder, recorder.outcome == nil else { return [] }
        let before = recorder.run.actions.count
        recorder.observe(match, input: input)
        self.recorder = recorder
        if let outcome = recorder.outcome {
            pendingOutcome = outcome
            settle = outcome == .made ? 90 : 30
        }
        return Array(recorder.run.actions.dropFirst(before))
    }

    /// The run's over and seen: what it means, and the screen for it.
    private func settleRun(_ outcome: ZonesRecorder.Outcome) {
        guard let run = recorder?.run else { return }
        let result = game.runEnded(run, outcome: outcome)
        pendingResult = result
        switch result {
        case .candidateMade(let last):
            if last, outcome != .made {
                // An earlier made run kept over this one: its phantoms, played back as the ghost.
                clearPhantoms()
                game.watchAgain()
                pause = .result("YOUR EARLIER RUN KEPT: WATCH IT")
            } else {
                pause = last ? .result("RUN KEPT: NOW DO IT AGAIN") : .choice
            }
        case .tryAgain(let left):
            // On to the next try now, so the count shows it.
            game.rewind()
            let strayed: Bool = { if case .strayed = outcome { return true } else { return false } }()
            pause = .result(strayed ? "STRAYED: \(left) LEFT" : outcome == .timedOut ? "TIME'S UP: \(left) LEFT" : "MISSED: \(left) LEFT")
        case .leadPassed: pause = .result("LEAD PASSES")
        case .runSet: pause = .result("RUN SET")
        case .followed: pause = .result("FOLLOWED!")
        case .letter(let count, let lost):
            pause = .result(lost ? "\(ZonesRules.word): GAME OVER" : "LETTER: \(String(ZonesRules.word.prefix(count)))")
        }
    }

    /// A button or the pad. Returns what the scene has to do about it.
    enum Effect: Equatable { case none, freshRun, lobby, replay, won(Int), power(Power) }

    func handle(_ request: Request) -> Effect {
        switch request {
        case .pickPower(let power):
            guard game.phase == .lobby else { return .none }
            powers[game.leader] = power
            return .power(power)
        case .record:
            guard pause == nil, game.phase == .lobby else { return .none }
            game.beginRecording()
            return .freshRun
        case .keep:
            guard pause == .choice else { return .none }
            pause = nil
            game.keepCandidate()
            return .freshRun
        case .rewind:
            if pause == .choice {
                pause = nil
                game.rewind()
                return .freshRun
            }
            // Given up on mid-run, it counts as a miss: the next try, or on the last the turn's end.
            guard pause == nil, settle == 0, let recorder, recorder.outcome == nil else { return .none }
            switch game.phase {
            case .recording, .confirming, .following: break
            default: return .none
            }
            settleRun(.missed)
            if case .tryAgain = pendingResult {
                pause = nil
                pendingResult = nil
                return .freshRun
            }
            return .none
        case .skip:
            // The rest of the ghost's run at speed, its phantoms still dropping.
            guard isReplaying else { return .none }
            fastForward = true
            return .none
        case .replay:
            guard canReplay else { return .none }
            game.watchAgain()
            return .replay
        case .proceed:
            // Not twice in a tap: a screen that replaces this one needs a tap of its own.
            guard let pause, CACurrentMediaTime() - lastProceed > ZonesPlay.proceedGapSeconds else { return .none }
            lastProceed = CACurrentMediaTime()
            switch pause {
            case .coinFlip:
                self.pause = nil
                return .lobby
            case .handOff:
                self.pause = nil
                return nextAfterPause()
            case .result:
                self.pause = nil
                // Between two people, a hand-off before the other side's turn.
                let changes = pendingResult.map(ZonesPlay.changesMover) ?? false
                pendingResult = nil
                if changes, opponent == .passAndPlay, game.winner == nil {
                    self.pause = .handOff
                    return .none
                }
                return nextAfterPause()
            case .choice:
                return .none
            }
        }
    }

    /// Whether a result hands the stage to the other side.
    private static func changesMover(_ result: ZonesGame.Result) -> Bool {
        switch result {
        case .runSet, .leadPassed, .followed: true
        case .letter(_, let lost): !lost
        default: false
        }
    }

    /// After a pause: where the turn goes.
    private func nextAfterPause() -> Effect {
        if let winner = game.winner { return .won(winner) }
        switch game.phase {
        case .lobby: return .lobby
        case .watching:
            replayFrame = 0
            replayTail = 0
            return .replay
        case .recording, .confirming, .following: return .freshRun
        case .over(let winner): return .won(winner)
        }
    }

    /// Whether the run can be watched again: following or confirming, before the try's moved.
    var canReplay: Bool {
        guard pause == nil, settle == 0, let recorder, recorder.run.actions.isEmpty else { return false }
        switch game.phase {
        case .following, .confirming: return true
        default: return false
        }
    }

    /// Phantoms drop while the leader records and while the ghost plays; they stay through
    /// the tries that follow.
    var dropsPhantoms: Bool {
        if isReplaying { return true }
        if case .recording = game.phase { return pause == nil }
        return false
    }

    /// A fresh run's recorder, on a fresh match. Following, the set run is the target;
    /// confirming, the leader's own candidate is, so straying from either ends the try on the
    /// spot. A new recording clears the phantoms; the tries after keep them.
    func beginRun(on match: Match) {
        let target: ZonesRun? = {
            switch game.phase {
            case .following: game.set
            case .confirming: game.candidate
            default: nil
            }
        }()
        recorder = ZonesRecorder(match: match, player: 0, target: target)
        if case .recording = game.phase { clearPhantoms() }
    }

    func beginLobby() {
        recorder = nil
        clearPhantoms()
    }

    func beginReplay() {
        recorder = nil
        clearPhantoms()
        replayFrame = 0
        replayTail = 0
        fastForward = false
    }

    /// Whether the sim should be held still.
    var holds: Bool { pause != nil }
    var isReplaying: Bool { if case .watching = game.phase { return pause == nil } else { return false } }

    // MARK: What's drawn

    /// The phantom colours: one a move.
    static func colour(of kind: ZoneAction.Kind) -> RGB {
        switch kind {
        case .walk: PixelPalette.colours[36]
        case .run: PixelPalette.colours[5]
        case .jump: PixelPalette.colours[19]
        case .doubleJump: PixelPalette.colours[20]
        case .wallJump: PixelPalette.colours[18]
        case .crouch: PixelPalette.colours[34]
        case .slide: PixelPalette.colours[7]
        case .taunt: PixelPalette.colours[27]
        case .throwBall: PixelPalette.colours[8]
        case .catchBall: PixelPalette.colours[10]
        case .floStateOn: PixelPalette.colours[22]
        case .floStateOff: PixelPalette.colours[39]
        case .power: PixelPalette.colours[28]
        case .shoot: PixelPalette.colours[12]
        case .dunk: PixelPalette.colours[13]
        }
    }

    /// The zone lines: dashed, glowing, 48 art pixels up from the floor between columns and in
    /// from the walls between rows, each column's letter at its foot and each row's number by
    /// the wall, in `colour`.
    func drawLines(stage: Stage, into parent: SKNode, colour: RGB) {
        lines.removeAllChildren()
        lines.removeFromParent()
        parent.addChild(lines)
        let grid = ZoneGrid(stage: stage)
        let floor = SpriteLibrary.point(Vec2(x: 0, y: Stage.tileSize)).y
        let left = SpriteLibrary.point(Vec2(x: Stage.tileSize, y: 0)).x, right = SpriteLibrary.point(Vec2(x: stage.width - Stage.tileSize, y: 0)).x
        let reach: CGFloat = 48
        let tint = SKColor(rgb: colour)
        func dashed(from a: CGPoint, to b: CGPoint) {
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            let node = SKShapeNode(path: path.copy(dashingWithPhase: 0, lengths: [4, 3]))
            node.strokeColor = tint
            node.lineWidth = 1.5
            node.glowWidth = 1
            node.alpha = 0.85
            lines.addChild(node)
        }
        func label(_ text: String, at point: CGPoint) {
            let node = SKLabelNode(fontNamed: "Bigdex")
            node.text = text
            node.fontSize = 9
            node.fontColor = tint
            node.verticalAlignmentMode = .center
            node.horizontalAlignmentMode = .center
            node.position = point
            lines.addChild(node)
        }
        for (index, x) in grid.columnLines.enumerated() {
            let at = SpriteLibrary.point(Vec2(x: x, y: 0)).x
            dashed(from: CGPoint(x: at, y: floor), to: CGPoint(x: at, y: floor + reach))
            // The letter under the middle of the column to the line's left, and the last past it.
            let span = grid.columnSpan(index)
            label(Zone.letter(index), at: CGPoint(x: SpriteLibrary.point(Vec2(x: (span.lowerBound + span.upperBound) / 2, y: 0)).x, y: floor + reach + 6))
            if index == grid.columnLines.count - 1 {
                let last = grid.columnSpan(index + 1)
                label(Zone.letter(index + 1), at: CGPoint(x: SpriteLibrary.point(Vec2(x: (last.lowerBound + last.upperBound) / 2, y: 0)).x, y: floor + reach + 6))
            }
        }
        for (index, y) in grid.rowLines.enumerated() {
            let at = SpriteLibrary.point(Vec2(x: 0, y: y)).y
            dashed(from: CGPoint(x: left, y: at), to: CGPoint(x: left + reach, y: at))
            dashed(from: CGPoint(x: right, y: at), to: CGPoint(x: right - reach, y: at))
            let span = grid.rowSpan(index)
            let middle = SpriteLibrary.point(Vec2(x: 0, y: (span.lowerBound + span.upperBound) / 2)).y
            label("\(index + 1)", at: CGPoint(x: left + reach + 6, y: middle))
            label("\(index + 1)", at: CGPoint(x: right - reach - 6, y: middle))
            if index == grid.rowLines.count - 1 {
                let last = grid.rowSpan(index + 1)
                let top = SpriteLibrary.point(Vec2(x: 0, y: (last.lowerBound + last.upperBound) / 2)).y
                label("\(index + 2)", at: CGPoint(x: left + reach + 6, y: top))
                label("\(index + 2)", at: CGPoint(x: right - reach - 6, y: top))
            }
        }
    }

    func removeLines() { lines.removeFromParent() }

    /// A phantom where a move started: the body as drawn, in the move's colour, half seen,
    /// its name over it.
    /// `at` and `facing` are the sim's at the drop, since the nodes show the frame before.
    func dropPhantom(for action: ZoneAction, body: SKSpriteNode, hood: SKSpriteNode, at: CGPoint, facing: CGFloat, into parent: SKNode, ghost: Bool) {
        let colour = SKColor(rgb: ZonesPlay.colour(of: action.kind))
        // Behind the figures, which sit at 0 and up in their layer.
        let group = SKNode()
        group.zPosition = ghost ? -0.6 : -0.5
        for source in [body, hood] where !source.isHidden && source.texture != nil {
            let copy = SKSpriteNode(texture: source.texture)
            copy.size = CGSize(width: abs(source.size.width), height: abs(source.size.height))
            copy.anchorPoint = source.anchorPoint
            // Where it sits off the body, turned about the body if the sim's facing differs.
            let offset = CGPoint(x: (source.position.x - body.position.x) * (facing == (source.xScale < 0 ? -1 : 1) || source === body ? 1 : -1),
                                 y: source.position.y - body.position.y)
            copy.position = CGPoint(x: at.x + offset.x, y: at.y + offset.y)
            copy.xScale = facing
            copy.zRotation = source.zRotation
            copy.color = colour
            copy.colorBlendFactor = 1
            copy.alpha = 0.55
            group.addChild(copy)
        }
        let tag = SKLabelNode(fontNamed: "Bigdex")
        tag.text = action.label.uppercased()
        tag.fontSize = 7
        tag.fontColor = colour
        tag.horizontalAlignmentMode = .center
        tag.verticalAlignmentMode = .bottom
        tag.position = CGPoint(x: at.x, y: at.y + abs(body.size.height) * (1 - body.anchorPoint.y) + 12)
        group.addChild(tag)
        parent.addChild(group)
        phantoms.append(group)
    }

    func clearPhantoms() {
        phantoms.forEach { $0.removeFromParent() }
        phantoms = []
    }

    /// The crown over the leader's head, in their colour, bobbing; only while the leader's the
    /// one on the stage, the ghost included.
    func placeCrown(over hood: SKSpriteNode, colour: RGB, into parent: SKNode, shown: Bool, time: Double) {
        if crown.parent == nil { parent.addChild(crown) }
        if crownTexture?.0 != colour {
            crownTexture = (colour, ZonesPlay.tinted("Crown", colour: SKColor(rgb: colour)))
        }
        // Without its picture there's nothing to draw.
        crown.isHidden = !shown || hood.isHidden || crownTexture?.1 == nil
        guard crown.isHidden == false else { return }
        crown.texture = crownTexture?.1
        crown.size = CGSize(width: 18, height: 18)
        let bob = CGFloat(sin(time * 2 * .pi * 0.8)) * 1.5
        crown.position = CGPoint(x: hood.position.x, y: hood.position.y + abs(hood.size.height) * (1 - hood.anchorPoint.y) + 6 + bob)
    }

    /// A vector drawn black, filled in a colour through its own alpha; nil without the picture.
    static func tinted(_ name: String, colour: SKColor) -> SKTexture? {
        guard let image = UIImage(named: name) else { return nil }
        let side: CGFloat = 128
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let filled = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            image.draw(in: rect)
            context.cgContext.setBlendMode(.sourceIn)
            colour.setFill()
            context.cgContext.fill(rect)
        }
        return SKTexture(image: filled)
    }

    func removeAll() {
        removeLines()
        clearPhantoms()
        crown.removeFromParent()
    }

    // MARK: The HUD

    /// What the SwiftUI layer shows.
    func hud(names: [String], colours: [RGB]) -> ZonesHud {
        var hud = ZonesHud(names: names, colours: colours, leader: game.leader, mover: game.mover, letters: game.letters)
        hud.pause = pause
        hud.powerPickable = game.phase == .lobby && pause == nil
        hud.power = moverPower
        let attemptLine: String
        switch game.phase {
        case .lobby: attemptLine = "\(names[game.leader]) LEADS"
        case .recording(let attempt): attemptLine = "RECORDING \(attempt)/\(ZonesRules.tries)"
        case .confirming(let attempt): attemptLine = "DO IT AGAIN \(attempt)/\(ZonesRules.tries)"
        case .watching: attemptLine = "\(names[game.leader])'S RUN"
        case .following(let attempt): attemptLine = "FOLLOWING \(attempt)/\(ZonesRules.tries)"
        case .over(let winner): attemptLine = "\(names[winner]) WINS"
        }
        hud.phaseLine = attemptLine
        if let recorder, recorder.outcome == nil, recorder.run.actions.last?.kind.endsRun != true {
            hud.secondsLeft = max(ZonesRules.runFrames - recorder.run.frames, 0) / 60
        }
        // The log: the run being matched (the set's, or the leader's own to confirm), with how
        // far along it is; else the run so far.
        if let target = recorder?.target {
            hud.log = target.actions.map(\.line)
            hud.matched = recorder?.followed ?? 0
        } else if case .watching = game.phase, let set = game.watched {
            hud.log = set.actions.filter { $0.frame <= replayFrame }.map(\.line)
            hud.matched = hud.log.count
        } else if let recorder {
            hud.log = recorder.run.actions.map(\.line)
            hud.matched = hud.log.count
        } else if case .confirming = game.phase, let candidate = game.candidate {
            hud.log = candidate.actions.map(\.line)
        }
        hud.canRecord = game.phase == .lobby && pause == nil
        hud.canRewind = pause == nil && settle == 0 && recorder != nil && {
            switch game.phase {
            case .recording(let a), .confirming(let a), .following(let a): a < ZonesRules.tries
            default: false
            }
        }()
        hud.canSkip = isReplaying && !fastForward
        hud.canReplay = canReplay
        return hud
    }
}

/// What the ZONES overlay shows, snapped from the scene each frame.
struct ZonesHud: Equatable {
    var names: [String]
    var colours: [RGB]
    var leader: Int
    var mover: Int
    var letters: [Int]
    var phaseLine = ""
    var secondsLeft: Int?
    var log: [String] = []
    var matched = 0
    var pause: ZonesPlay.Pause?
    var powerPickable = false
    var power = Power.none
    var canRecord = false
    var canRewind = false
    var canSkip = false
    var canReplay = false
}

/// The ZONES screen over play: each side's letters at the top, the crown by the leader's,
/// the turn and the clock in the middle, the run's log down the side, the buttons at the
/// bottom; and over everything the coin flip, a hand-off, a result, or the power wheel.
struct ZonesOverlay: View {
    @ObservedObject var flow: FlowState
    @State private var wheelOpen = false
    @State private var flipped = false

    var body: some View {
        if let hud = flow.zonesHud {
            ZStack {
                top(hud)
                side(hud)
                buttons(hud)
                if wheelOpen, hud.powerPickable { wheel(hud) }
                if let pause = hud.pause { curtain(pause, hud) }
            }
            .environment(\.colorScheme, .dark)
        }
    }

    private func name(_ index: Int, _ hud: ZonesHud) -> some View {
        Text(hud.names[index])
            .font(.custom("Bigdex", size: 14))
            .foregroundStyle(Color(rgb: hud.colours[index]))
    }

    /// A side's letters, the ones earned lit.
    private func letters(_ index: Int, _ hud: ZonesHud) -> some View {
        HStack(spacing: 3) {
            if hud.leader == index, let crown = UIImage(named: "Crown") {
                Image(uiImage: crown).resizable().renderingMode(.template).foregroundStyle(Color(rgb: hud.colours[index])).frame(width: 16, height: 16)
            }
            ForEach(Array(ZonesRules.word.enumerated()), id: \.offset) { at, letter in
                Text(String(letter))
                    .font(.custom("Bigdex", size: 18))
                    .foregroundStyle(at < hud.letters[index] ? Color(rgb: hud.colours[index]) : .white.opacity(0.25))
            }
        }
    }

    private func top(_ hud: ZonesHud) -> some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) { name(0, hud); letters(0, hud) }
                Spacer()
                VStack(spacing: 2) {
                    Text(hud.phaseLine).font(.custom("Bigdex", size: 12)).foregroundStyle(.white)
                    if let seconds = hud.secondsLeft {
                        Text("\(seconds)").font(.custom("Bigdex", size: 22)).foregroundStyle(seconds <= 5 ? .red : .white)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) { name(1, hud); letters(1, hud) }
            }
            .padding(.horizontal, 60)
            .padding(.top, 8)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    /// The log down the right: the set run's lines while following, the matched ones lit.
    private func side(_ hud: ZonesHud) -> some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                ForEach(Array(hud.log.enumerated()), id: \.offset) { at, line in
                    Text(line.uppercased())
                        .font(.custom("Bigdex", size: 9))
                        .foregroundStyle(at < hud.matched ? .white : .white.opacity(0.45))
                }
            }
            .padding(.trailing, 8)
        }
        .padding(.top, 60)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }

    /// The turn's buttons, under the turn line at the top, clear of the pad at the bottom.
    private func buttons(_ hud: ZonesHud) -> some View {
        VStack {
            HStack(spacing: 10) {
                if hud.powerPickable {
                    button(hud.power == .none ? "POWER" : hud.power.shortName.uppercased()) { wheelOpen.toggle() }
                }
                if hud.canRecord { button("RECORD") { flow.scene.zonesRequest(.record) } }
                if hud.canRewind { button("REWIND") { flow.scene.zonesRequest(.rewind) } }
                if hud.canReplay { button("REPLAY") { flow.scene.zonesRequest(.replay) } }
                if hud.canSkip { button("SKIP") { flow.scene.zonesRequest(.skip) } }
            }
            .padding(.top, 58)
            Spacer()
        }
    }

    private func button(_ text: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.custom("Bigdex", size: 12))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(rgb: EsperPalette.plum.body), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .noSystemFocus()
    }

    /// The power wheel: the powers round a ring, the pick lit.
    private func wheel(_ hud: ZonesHud) -> some View {
        let choices = Power.allPicks
        return ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { wheelOpen = false }
            ForEach(Array(choices.enumerated()), id: \.offset) { at, power in
                let angle = Double(at) / Double(choices.count) * 2 * .pi - .pi / 2
                Button {
                    flow.scene.zonesRequest(.pickPower(power))
                    wheelOpen = false
                } label: {
                    Text(power.shortName.uppercased())
                        .font(.custom("Bigdex", size: 10))
                        .foregroundStyle(hud.power == power ? Color(rgb: hud.colours[hud.mover]) : .white)
                        .padding(6)
                        .background(Color(rgb: EsperPalette.black.light).opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
                .noSystemFocus()
                .offset(x: cos(angle) * 120, y: sin(angle) * 95)
            }
            Text("FLOSTATE POWER").font(.custom("Bigdex", size: 12)).foregroundStyle(.white)
        }
    }

    /// The screens between: tapped through.
    private func curtain(_ pause: ZonesPlay.Pause, _ hud: ZonesHud) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                switch pause {
                case .coinFlip:
                    CoinFlipDisc(colours: hud.colours, landsOn: hud.leader, flipped: $flipped)
                    if flipped {
                        Text("\(hud.names[hud.leader]) LEADS").font(.custom("Bigdex", size: 22)).foregroundStyle(Color(rgb: hud.colours[hud.leader]))
                        Text("TAP TO START").font(.custom("Bigdex", size: 11)).foregroundStyle(.white.opacity(0.7))
                    }
                case .handOff:
                    Text("PASS TO \(hud.names[hud.mover])").font(.custom("Bigdex", size: 22)).foregroundStyle(Color(rgb: hud.colours[hud.mover]))
                    Text("TAP WHEN READY").font(.custom("Bigdex", size: 11)).foregroundStyle(.white.opacity(0.7))
                case .result(let text):
                    Text(text).font(.custom("Bigdex", size: 22)).foregroundStyle(.white)
                    Text("TAP TO GO ON").font(.custom("Bigdex", size: 11)).foregroundStyle(.white.opacity(0.7))
                case .choice:
                    Text("RUN MADE").font(.custom("Bigdex", size: 22)).foregroundStyle(.white)
                    HStack(spacing: 14) {
                        button("KEEP IT") { flow.scene.zonesRequest(.keep) }
                        button("REWIND") { flow.scene.zonesRequest(.rewind) }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if pause == .choice { return }
            if pause == .coinFlip, !flipped { return }
            flow.scene.zonesRequest(.proceed)
        }
        .onAppear { if pause == .coinFlip { flipped = false } }
    }
}

/// A coin thrown where it can be seen: a disc turning over, slowing, landing on the side
/// that leads, in its colour. On the clock, since a turn count read in the body would land
/// on its end at once.
struct CoinFlipDisc: View {
    let colours: [RGB]
    let landsOn: Int
    @Binding var flipped: Bool
    @State private var thrown = Date()

    /// How long it turns, and the half turns: eight, and one more to land it on the second side.
    static let seconds = 1.4
    var halfTurns: Double { 8 + (landsOn == 0 ? 0 : 1) }

    var body: some View {
        TimelineView(.animation) { timeline in
            // Never under 0: the clock can tick once before the throw's own stamp.
            let share = min(max(timeline.date.timeIntervalSince(thrown) / CoinFlipDisc.seconds, 0), 1)
            let eased = 1 - pow(1 - share, 3)
            let turns = halfTurns * eased
            let side = Int(turns.rounded(.down)) % 2
            ZStack {
                Circle().fill(Color(rgb: colours[side]))
                Circle().stroke(.white, lineWidth: 3)
                Text(side == 0 ? "1" : "2").font(.custom("Bigdex", size: 36)).foregroundStyle(.white)
            }
            .frame(width: 90, height: 90)
            .scaleEffect(y: abs(cos(turns * .pi)) * 0.9 + 0.1)
            .onChange(of: share >= 1) { _, landed in if landed { flipped = true } }
        }
        .onAppear { thrown = Date() }
    }
}

extension Power {
    /// The powers to pick from for FloState: all but none.
    static let allPicks: [Power] = [.webWater, .superSmoothie, .flashFizz, .platformShake, .quakeUp, .voltaCola, .frostTea,
                                    .blazingBoba, .pulsepistol, .surfSoda, .titanTea, .galeAle, .zTea]

    /// Its drink's name, short.
    var shortName: String {
        Greateraid.allCases.first { $0.power == self }?.name ?? "None"
    }
}
