import EsperSim
import SpriteKit

/// A screen laid over the game in HUD points, on the SwiftUI layer's dark material: title
/// lettering and a few choices a tap or the pad picks from. The pad's cursor is the raised
/// choice.
class Screen: SKNode {
    struct Choice {
        let node: SKNode
        let hit: CGRect
        let enabled: Bool
        /// Where the arrow sits to point at this choice, and which way it turns from
        /// pointing down, as the drawing does.
        let arrowAt: CGPoint
        let arrowTurn: CGFloat
        let sound: SoundBoard.Effect
        let action: () -> Void
    }

    private(set) var choices: [Choice] = []
    private(set) var cursor = 0
    /// Lettered buttons' plates, by choice: the plate, its own piece, and its size. The
    /// cursor's plate turns gold.
    private var plates: [Int: (plate: SKSpriteNode, piece: UIPiece, size: CGSize)] = [:]

    /// This screen's tuned scale for one of its parts, 1 for a screen that isn't tuned.
    func tuned(_ part: UIPart) -> CGFloat {
        kind.map { UITuning.shared.scale($0, part) } ?? 1
    }
    let halfWidth: CGFloat
    let halfHeight: CGFloat
    /// CardCourt's selection arrow, the one that hangs over a man, in its own greys,
    /// pointing at the cursor's choice. It points down as drawn.
    private let arrow: SKSpriteNode = {
        let texture = SKTexture(imageNamed: "MenuArrow")
        texture.filteringMode = .nearest
        let node = SKSpriteNode(texture: texture)
        let width: CGFloat = 20
        node.size = CGSize(width: width, height: width * 104 / 144)
        node.zPosition = 3
        node.isHidden = true
        return node
    }()

    /// The screen whose tuned sizes its buttons, text and titles take, if it has any.
    let kind: UIScreenKind?

    init(halfWidth: CGFloat, halfHeight: CGFloat, kind: UIScreenKind? = nil) {
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.kind = kind
        super.init()
        zPosition = 200
        addChild(arrow)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A lettered button on a plate from the pack, royal blue by default, plum for a way
    /// back. Disabled ones are dimmed and never fire. `width` makes a row of them even.
    @discardableResult
    func addButton(_ text: String, size: CGFloat = 26, at point: CGPoint, enabled: Bool = true, sound: SoundBoard.Effect = SoundBoard.confirm,
                   piece: UIPiece = .buttonBlue, width: CGFloat? = nil, action: @escaping () -> Void) -> SKNode {
        let button = SKNode()
        button.position = point
        button.alpha = enabled ? 1 : 0.45
        let label = TitleText.node(text, size: size * tuned(.text))
        let buttons = tuned(.buttons)
        let plateSize = CGSize(width: max((width ?? 0) * buttons, label.size.width + 44 * buttons), height: max(label.size.height + 12, (26 + 22) * buttons))
        let plate = piece.node(size: plateSize, corners: buttons)
        plate.zPosition = -1
        button.addChild(plate)
        // Centred on the plate's face, the drop taken off.
        let rise = UITuning.shared.textRise
        let shift = TitleText.dropShift(size: size * tuned(.text)) * rise
        label.position = CGPoint(x: -shift, y: piece.faceRise * buttons * rise + shift)
        button.addChild(label)
        addChild(button)
        let hit = CGRect(x: point.x - plateSize.width / 2, y: point.y - plateSize.height / 2, width: plateSize.width, height: plateSize.height)
        choices.append(Choice(node: button, hit: hit, enabled: enabled, arrowAt: CGPoint(x: hit.minX - 16, y: point.y), arrowTurn: .pi / 2, sound: sound, action: action))
        plates[choices.count - 1] = (plate, piece, plateSize)
        if choices.count == 1 { cursor = 0 }
        showCursor()
        return button
    }

    /// A black card from the pack behind a screen's content, `size` points round `centre`,
    /// its height at the panels' scale (its width comes from the header's, which has it).
    @discardableResult
    func addCard(size: CGSize, at centre: CGPoint) -> SKSpriteNode {
        let card = UIPiece.cardBlack.node(size: CGSize(width: size.width, height: size.height * tuned(.panels)), corners: tuned(.panels))
        card.position = centre
        card.zPosition = -5
        addChild(card)
        return card
    }

    /// A royal blue header ribbon with title lettering on it; its width, for a card to match.
    @discardableResult
    func addHeader(_ text: String, size: CGFloat = 34, at point: CGPoint, width: CGFloat? = nil) -> CGFloat {
        let header = SKNode()
        header.position = point
        let panels = tuned(.panels)
        let label = TitleText.node(text, size: size * tuned(.titles))
        // The ribbon at the panels' scale, grown only when the lettering needs the room.
        let ribbonSize = CGSize(width: max((width ?? 0) * panels, label.size.width + 60), height: max(58 * panels, label.size.height + 18))
        let ribbon = UIPiece.headerBlue.node(size: ribbonSize, corners: panels)
        ribbon.zPosition = -1
        header.addChild(ribbon)
        let shift = TitleText.dropShift(size: size * tuned(.titles)) * UITuning.shared.textRise
        label.position = CGPoint(x: -shift, y: shift)
        header.addChild(label)
        addChild(header)
        return ribbonSize.width
    }

    /// `arrowAt` is where the arrow sits for this choice, turned `arrowTurn` from pointing down.
    func addChoice(_ node: SKNode, hit: CGRect, enabled: Bool = true, arrowAt: CGPoint, arrowTurn: CGFloat, action: @escaping () -> Void) {
        choices.append(Choice(node: node, hit: hit, enabled: enabled, arrowAt: arrowAt, arrowTurn: arrowTurn, sound: SoundBoard.confirm, action: action))
        showCursor()
    }

    /// The cursor's choice is raised a little, a plated button's plate turning gold, the
    /// arrow points at any other kind, and the rest sit still.
    func showCursor() {
        for (index, choice) in choices.enumerated() {
            let lit = index == cursor && choice.enabled
            choice.node.setScale(lit ? 1.12 : 1)
            if let plate = plates[index] { (lit ? UIPiece.buttonGold : plate.piece).fit(plate.plate, to: plate.size, corners: tuned(.buttons)) }
        }
        if plates[cursor] != nil {
            arrow.isHidden = true
        } else if choices.indices.contains(cursor) {
            arrow.isHidden = false
            arrow.position = choices[cursor].arrowAt
            arrow.zRotation = choices[cursor].arrowTurn
        } else {
            arrow.isHidden = true
        }
    }

    /// A tap on a choice: the cursor's choice fires, another becomes the cursor. True
    /// when the tap landed on any choice.
    func tap(at point: CGPoint) -> Bool {
        guard let index = choices.firstIndex(where: { $0.hit.contains(point) }) else { return false }
        if index == cursor || tapFiresAtOnce {
            cursor = index
            showCursor()
            fire()
        } else {
            cursor = index
            showCursor()
            SoundBoard.shared.play(SoundBoard.navigate)
            moved()
        }
        return true
    }

    /// Whether a tap on a choice that isn't the cursor's fires it straight away.
    var tapFiresAtOnce: Bool { true }

    /// The cursor put on a choice without firing it.
    func place(cursor index: Int) {
        guard choices.indices.contains(index) else { return }
        cursor = index
        showCursor()
    }

    func move(_ delta: Int) {
        guard !choices.isEmpty else { return }
        cursor = (cursor + delta + choices.count) % choices.count
        showCursor()
        SoundBoard.shared.play(SoundBoard.navigate)
        moved()
    }

    func fire() {
        guard choices.indices.contains(cursor), choices[cursor].enabled else { return }
        SoundBoard.shared.play(choices[cursor].sound)
        choices[cursor].action()
    }

    /// The cursor moved to another choice.
    func moved() {}
}

/// Three bottles of Greateraid to choose from, large, their bottoms off the screen, each
/// leaning a little, its name across it; what the raised one does is lettered in the
/// middle of the screen. A tap on a bottle raises it, a tap on the raised one drinks it;
/// on the pad the stick moves and jump drinks.
final class PickScreen: Screen {
    private let offers: [Greateraid]
    private let drinks: Drinks
    private let blurb = SKSpriteNode()
    private let comment = SKSpriteNode()
    private let clock = SKSpriteNode()
    private let onDrink: (Greateraid) -> Void

    /// `timed` shows the seconds left, for a networked pick.
    init(halfWidth: CGFloat, halfHeight: CGFloat, offers: [Greateraid], drinks: Drinks, colour: SKColor, timed: Bool = false,
         onDrink: @escaping (Greateraid) -> Void) {
        self.offers = offers
        self.drinks = drinks
        self.onDrink = onDrink
        super.init(halfWidth: halfWidth, halfHeight: halfHeight, kind: .pick)
        addHeader("GREATERAID", size: 44, at: CGPoint(x: 0, y: halfHeight * 0.74), width: 360)
        let sub = TitleText.node("YOU WERE SCORED ON. DRINK UP.", size: 13 * tuned(.text))
        sub.position = CGPoint(x: 0, y: halfHeight * 0.5)
        addChild(sub)
        if timed {
            // The seconds in a black round button, top right.
            let dial = UIPiece.circleBlack.node(size: CGSize(width: 52, height: 56).scaled(by: tuned(.buttons)), corners: tuned(.buttons))
            dial.position = CGPoint(x: halfWidth - 50, y: halfHeight * 0.74)
            dial.zPosition = -1
            addChild(dial)
            clock.position = CGPoint(x: dial.position.x, y: dial.position.y + UIPiece.circleBlack.faceRise * tuned(.buttons))
            addChild(clock)
            showSeconds(Series.pickSeconds)
        }
        // The quote and what the raised drink does, on a black plate over the bottles.
        let plate = UIPiece.plateBlack.node(size: CGSize(width: min(halfWidth * 1.7, 620), height: 86).scaled(by: tuned(.panels)), corners: tuned(.panels))
        plate.position = CGPoint(x: 0, y: 28)
        plate.zPosition = 1
        addChild(plate)

        let spacing = min(halfWidth * 0.55, 200)
        for (index, offer) in offers.enumerated() {
            let x = (CGFloat(index) - 1) * spacing
            let bottle = PickScreen.bottle(for: offer, colour: colour, height: 180 * tuned(.buttons))
            // Leaning between 5 and 30 degrees, either way; the bottom clipped by the screen's edge.
            let lean = CGFloat(5 + Int.random(in: 0...15)) * .pi / 180 * (Bool.random() ? 1 : -1)
            bottle.zRotation = lean
            bottle.position = CGPoint(x: x, y: -halfHeight - 24)
            addChild(bottle)
            let name = TitleText.node(offer.name.uppercased(), size: (offer.name.count > 14 ? 21 : 23) * tuned(.text))
            name.position = CGPoint(x: x, y: -halfHeight + 84)
            name.zPosition = 2
            addChild(name)
            if drinks.isSecondSip(offer) {
                let sip = TitleText.node("(Second Sip)", size: 20 * tuned(.text), italic: true)
                sip.position = CGPoint(x: x, y: -halfHeight + 68)
                sip.zPosition = 2
                addChild(sip)
            }
            let hit = CGRect(x: x - spacing / 2 + 6, y: -halfHeight, width: spacing - 12, height: halfHeight)
            // The arrow hangs over the name, pointing down at the bottle.
            addChoice(bottle, hit: hit, arrowAt: CGPoint(x: x, y: -halfHeight + 84 + 24), arrowTurn: 0) { [weak self] in
                guard let self else { return }
                self.onDrink(offer)
            }
        }
        comment.position = CGPoint(x: 0, y: 44)
        comment.zPosition = 2
        addChild(comment)
        blurb.position = CGPoint(x: 0, y: 14)
        blurb.zPosition = 2
        addChild(blurb)
        moved()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var tapFiresAtOnce: Bool { false }

    /// The seconds left on the pick.
    func showSeconds(_ seconds: Int) {
        guard clock.parent != nil else { return }
        TitleText.set(clock, to: "\(max(seconds, 0))", size: 24 * tuned(.text))
    }

    override func moved() {
        guard choices.indices.contains(cursor) else { return }
        let offer = offers[cursor]
        let text = drinks.level(of: offer) == 0 ? offer.blurbs.first : offer.blurbs.second
        let scale = tuned(.text)
        TitleText.set(blurb, to: text, size: (text.count > 70 ? 17 : (text.count > 50 ? 19 : 22)) * scale)
        TitleText.set(comment, to: "\u{201C}\(offer.comment)\u{201D}", size: 18 * scale, italic: true)
    }

    /// The bottle, the user's vector from the catalog, 180 points tall and anchored at its
    /// bottom so that runs off the screen: blue for a booster, gold for a biomorph or
    /// Bio-Boba.
    static func bottle(for drink: Greateraid, colour: SKColor, height: CGFloat = 180) -> SKNode {
        let texture = SKTexture(imageNamed: drink.kind == .booster ? "Greateraid" : "Greateraid-Gold")
        let aspect = texture.size().width / max(texture.size().height, 1)
        let bottle = SKSpriteNode(texture: texture)
        bottle.size = CGSize(width: height * aspect, height: height)
        bottle.anchorPoint = CGPoint(x: 0.5, y: 0)
        return bottle
    }
}

/// The other side is drinking: nothing to pick, only the clock to watch.
final class WaitScreen: Screen {
    private let clock = SKSpriteNode()

    init(halfWidth: CGFloat, halfHeight: CGFloat, who: String) {
        super.init(halfWidth: halfWidth, halfHeight: halfHeight, kind: .pick)
        addHeader("GREATERAID", size: 38, at: CGPoint(x: 0, y: halfHeight * 0.62), width: 320)
        let sub = TitleText.node("\(who) IS DRINKING", size: 26 * tuned(.titles))
        sub.position = CGPoint(x: 0, y: 10)
        addChild(sub)
        let dial = UIPiece.circleBlack.node(size: CGSize(width: 64, height: 69).scaled(by: tuned(.buttons)), corners: tuned(.buttons))
        dial.position = CGPoint(x: 0, y: -60)
        dial.zPosition = -1
        addChild(dial)
        clock.position = CGPoint(x: 0, y: dial.position.y + UIPiece.circleBlack.faceRise * tuned(.buttons))
        addChild(clock)
        showSeconds(Series.pickSeconds)
    }

    required init?(coder: NSCoder) { fatalError() }

    func showSeconds(_ seconds: Int) {
        TitleText.set(clock, to: "\(max(seconds, 0))", size: 28 * tuned(.text))
    }
}

/// Who won, the final score large under it, and the two ways on. `again` is NEW MATCH
/// offline and REMATCH online, where it waits for the other side to press theirs.
final class WinScreen: Screen {
    private let waiting = SKSpriteNode()

    /// `score` is each side's, player one's first, as the match ended.
    init(halfWidth: CGFloat, halfHeight: CGFloat, winner: String, score: [Int], again: String,
         onAgain: @escaping () -> Void, onTitle: @escaping () -> Void) {
        super.init(halfWidth: halfWidth, halfHeight: halfHeight, kind: .win)
        let width: CGFloat = 220
        let headerWidth = addHeader("\(winner) WINS", size: 36, at: CGPoint(x: 0, y: halfHeight * 0.64), width: width + 170)
        addCard(size: CGSize(width: headerWidth, height: halfHeight * 1.55), at: CGPoint(x: 0, y: -halfHeight * 0.1))
        let final = TitleText.node(score.map(String.init).joined(separator: " - "), size: 80 * tuned(.titles))
        final.position = CGPoint(x: 0, y: halfHeight * 0.2)
        addChild(final)
        addButton(again, at: CGPoint(x: 0, y: -halfHeight * 0.2), width: width, action: onAgain)
        addButton("TITLE", at: CGPoint(x: 0, y: -halfHeight * 0.52), sound: .menuBack, piece: .buttonPlum, width: width, action: onTitle)
        waiting.position = CGPoint(x: 0, y: -halfHeight * 0.35)
        waiting.isHidden = true
        addChild(waiting)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The rematch is asked for; now the other side has to.
    func showWaiting() {
        TitleText.set(waiting, to: "WAITING FOR THEM", size: 14)
        waiting.isHidden = false
    }
}

/// The stages as rectangles in a row with their names inside. The one under a voter's
/// cursor grows, and a circle in its bottom-right corner in that voter's colour marks
/// their choice: a ring while they look, filled once they've picked. The other phone's
/// voter shows only once their pick is in. Two different picks flip a coin between them,
/// the light going back and forth before it lands.
final class StageSelectScreen: Screen {
    /// Each stage: its plate, royal blue or gold when raised, in a container that grows.
    private var tiles: [SKNode] = []
    private var tilePlates: [SKSpriteNode] = []
    private var tileSize = CGSize.zero
    private var cursors: [Int: Int] = [:]
    private var picks: [Int: Int] = [:]
    private var marks: [Int: SKShapeNode] = [:]
    private var flipLit: Int?
    private let voters: [Int]
    private let localVoters: [Int]
    private let colours: [SKColor]
    private let onPick: (Int, Int) -> Void
    private static let markRadius: CGFloat = 7

    /// `onPick` gets the voter and the stage's place in the row.
    init(halfWidth: CGFloat, halfHeight: CGFloat, stages: [String], voters: [Int], localVoters: [Int], colours: [SKColor],
         heading: String?, start: Int, onPick: @escaping (Int, Int) -> Void) {
        self.voters = voters
        self.localVoters = localVoters
        self.colours = colours
        self.onPick = onPick
        super.init(halfWidth: halfWidth, halfHeight: halfHeight, kind: .stageSelect)
        addHeader("STAGE SELECT", size: 38, at: CGPoint(x: 0, y: halfHeight * 0.7), width: 360)
        if let heading {
            let sub = TitleText.node(heading, size: 22 * tuned(.titles))
            sub.position = CGPoint(x: 0, y: halfHeight * 0.44)
            addChild(sub)
        }
        let buttons = tuned(.buttons)
        let width = min(halfWidth * 0.56, 180 * buttons)
        tileSize = CGSize(width: width, height: 96 * buttons)
        let spacing = width + 20
        let rise = UITuning.shared.textRise
        for (index, name) in stages.enumerated() {
            let tile = SKNode()
            tile.position = CGPoint(x: (CGFloat(index) - CGFloat(stages.count - 1) / 2) * spacing, y: -halfHeight * 0.1)
            let plate = UIPiece.buttonBlue.node(size: tileSize, corners: buttons)
            plate.zPosition = -1
            tile.addChild(plate)
            let textSize = 20 * tuned(.text)
            let label = TitleText.node(name, size: textSize)
            label.setScale(min(1, (width - 20) / max(label.size.width, 1)))
            let shift = TitleText.dropShift(size: textSize) * rise
            label.position = CGPoint(x: -shift, y: UIPiece.buttonBlue.faceRise * buttons * rise + shift)
            tile.addChild(label)
            addChild(tile)
            tiles.append(tile)
            tilePlates.append(plate)
        }
        for voter in localVoters { cursors[voter] = min(max(start, 0), stages.count - 1) }
        for voter in voters {
            let mark = SKShapeNode(circleOfRadius: StageSelectScreen.markRadius)
            mark.strokeColor = colours.indices.contains(voter) ? colours[voter] : .white
            mark.lineWidth = 2
            mark.zPosition = 2
            addChild(mark)
            marks[voter] = mark
        }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func move(voter: Int, by delta: Int) {
        guard picks[voter] == nil, flipLit == nil, let at = cursors[voter] else { return }
        cursors[voter] = (at + delta + tiles.count) % tiles.count
        SoundBoard.shared.play(SoundBoard.navigate)
        refresh()
    }

    func lock(voter: Int) {
        guard picks[voter] == nil, flipLit == nil, let at = cursors[voter] else { return }
        picks[voter] = at
        SoundBoard.shared.play(SoundBoard.confirm)
        refresh()
        onPick(voter, at)
    }

    /// A pick made elsewhere: the other phone's, or one already in when the screen is rebuilt.
    func show(vote index: Int, by voter: Int) {
        picks[voter] = index
        cursors[voter] = index
        refresh()
    }

    /// The coin flip's light on one stage.
    func showFlip(lit index: Int) {
        guard flipLit != index else { return }
        flipLit = index
        refresh()
    }

    override func move(_ delta: Int) {
        if let voter = localVoters.first { move(voter: voter, by: delta) }
    }

    override func fire() {
        if let voter = localVoters.first { lock(voter: voter) }
    }

    /// A tap on a stage moves the first local voter's cursor there, or picks it if it's there already.
    override func tap(at point: CGPoint) -> Bool {
        guard let voter = localVoters.first,
              let index = tiles.firstIndex(where: { $0.calculateAccumulatedFrame().contains(point) }) else { return false }
        if cursors[voter] == index {
            lock(voter: voter)
        } else if picks[voter] == nil {
            cursors[voter] = index
            SoundBoard.shared.play(SoundBoard.navigate)
            refresh()
        }
        return true
    }

    private func refresh() {
        let raised: Set<Int> = flipLit.map { [$0] } ?? Set(voters.compactMap { picks[$0] ?? cursors[$0] })
        for (index, tile) in tiles.enumerated() {
            let lit = raised.contains(index)
            tile.setScale(lit ? 1.12 : 1)
            (lit ? UIPiece.buttonGold : UIPiece.buttonBlue).fit(tilePlates[index], to: tileSize, corners: tuned(.buttons))
        }
        // Each voter's circle in the bottom-right corner of their stage, the second beside the first.
        var taken: [Int: Int] = [:]
        for voter in voters {
            guard let mark = marks[voter] else { continue }
            guard let index = picks[voter] ?? cursors[voter] else {
                mark.isHidden = true
                continue
            }
            let tile = tiles[index]
            let frame = tile.calculateAccumulatedFrame()
            let order = taken[index, default: 0]
            taken[index] = order + 1
            let radius = StageSelectScreen.markRadius
            mark.isHidden = false
            mark.position = CGPoint(x: frame.maxX - radius - 8 - CGFloat(order) * (radius * 2 + 4), y: frame.minY + radius + 8)
            mark.fillColor = picks[voter] != nil ? mark.strokeColor : .clear
        }
    }
}

/// The pause, against the computer: start the match over, go to the title, or play on.
final class PauseScreen: Screen {
    init(halfWidth: CGFloat, halfHeight: CGFloat, onRestart: @escaping () -> Void, onTitle: @escaping () -> Void, onResume: @escaping () -> Void) {
        super.init(halfWidth: halfWidth, halfHeight: halfHeight, kind: .pause)
        let width: CGFloat = 230
        // The card as wide as the header over it, so their edges line up.
        let headerWidth = addHeader("PAUSED", at: CGPoint(x: 0, y: halfHeight * 0.62), width: width + 90)
        addCard(size: CGSize(width: headerWidth, height: halfHeight * 1.5), at: CGPoint(x: 0, y: -halfHeight * 0.12))
        addButton("RESTART MATCH", at: CGPoint(x: 0, y: halfHeight * 0.25), width: width, action: onRestart)
        addButton("TITLE SCREEN", at: CGPoint(x: 0, y: -halfHeight * 0.1), sound: .menuBack, piece: .buttonPlum, width: width, action: onTitle)
        addButton("RESUME", at: CGPoint(x: 0, y: -halfHeight * 0.45), sound: .menuBack, piece: .buttonPlum, width: width, action: onResume)
        // On RESUME, so a press of jump straight after pausing plays on.
        place(cursor: 2)
    }

    required init?(coder: NSCoder) { fatalError() }
}

extension CGSize {
    func scaled(by factor: CGFloat) -> CGSize { CGSize(width: width * factor, height: height * factor) }
}
