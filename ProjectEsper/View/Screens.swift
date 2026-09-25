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
        let action: () -> Void
    }

    private(set) var choices: [Choice] = []
    private(set) var cursor = 0
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

    init(halfWidth: CGFloat, halfHeight: CGFloat) {
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        super.init()
        zPosition = 200
        addChild(arrow)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A lettered button. Disabled ones are dimmed and never fire.
    @discardableResult
    func addButton(_ text: String, size: CGFloat = 26, at point: CGPoint, enabled: Bool = true, action: @escaping () -> Void) -> SKNode {
        let label = TitleText.node(text, size: size)
        label.position = point
        label.alpha = enabled ? 1 : 0.35
        addChild(label)
        let hit = CGRect(x: point.x - label.size.width / 2 - 12, y: point.y - label.size.height / 2 - 8,
                         width: label.size.width + 24, height: label.size.height + 16)
        // The arrow sits to the left of a lettered button, turned to point at it.
        let arrowAt = CGPoint(x: hit.minX - 16, y: point.y)
        choices.append(Choice(node: label, hit: hit, enabled: enabled, arrowAt: arrowAt, arrowTurn: .pi / 2, action: action))
        if choices.count == 1 { cursor = 0 }
        showCursor()
        return label
    }

    /// `arrowAt` is where the arrow sits for this choice, turned `arrowTurn` from pointing down.
    func addChoice(_ node: SKNode, hit: CGRect, enabled: Bool = true, arrowAt: CGPoint, arrowTurn: CGFloat, action: @escaping () -> Void) {
        choices.append(Choice(node: node, hit: hit, enabled: enabled, arrowAt: arrowAt, arrowTurn: arrowTurn, action: action))
        showCursor()
    }

    /// The cursor's choice is raised a little, the arrow points at it, and the rest sit still.
    func showCursor() {
        for (index, choice) in choices.enumerated() {
            choice.node.setScale(index == cursor && choice.enabled ? 1.12 : 1)
        }
        if choices.indices.contains(cursor) {
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
        moved()
    }

    func fire() {
        guard choices.indices.contains(cursor), choices[cursor].enabled else { return }
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
        super.init(halfWidth: halfWidth, halfHeight: halfHeight)
        let header = TitleText.node("GREATERAID", size: 60)
        header.position = CGPoint(x: 0, y: halfHeight - 44)
        addChild(header)
        let sub = SKLabelNode(text: "You were scored on. Drink up.")
        sub.fontName = "Menlo-Bold"
        sub.fontSize = 11
        sub.fontColor = SKColor(white: 1, alpha: 0.7)
        sub.position = CGPoint(x: 0, y: halfHeight - 82)
        addChild(sub)
        if timed {
            clock.position = CGPoint(x: halfWidth - 60, y: halfHeight - 50)
            addChild(clock)
            showSeconds(Series.pickSeconds)
        }

        let spacing = min(halfWidth * 0.55, 200)
        for (index, offer) in offers.enumerated() {
            let x = (CGFloat(index) - 1) * spacing
            let bottle = PickScreen.bottle(for: offer, colour: colour)
            // Leaning between 5 and 30 degrees, either way; the bottom clipped by the screen's edge.
            let lean = CGFloat(5 + Int.random(in: 0...15)) * .pi / 180 * (Bool.random() ? 1 : -1)
            bottle.zRotation = lean
            bottle.position = CGPoint(x: x, y: -halfHeight - 24)
            addChild(bottle)
            let name = TitleText.node(offer.name.uppercased(), size: offer.name.count > 14 ? 21 : 23)
            name.position = CGPoint(x: x, y: -halfHeight + 84)
            name.zPosition = 2
            addChild(name)
            if drinks.isSecondSip(offer) {
                let sip = TitleText.node("(Second Sip)", size: 20, italic: true)
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
        addChild(comment)
        blurb.position = CGPoint(x: 0, y: 14)
        addChild(blurb)
        moved()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var tapFiresAtOnce: Bool { false }

    /// The seconds left on the pick.
    func showSeconds(_ seconds: Int) {
        guard clock.parent != nil else { return }
        TitleText.set(clock, to: "\(max(seconds, 0))", size: 32)
    }

    override func moved() {
        guard choices.indices.contains(cursor) else { return }
        let offer = offers[cursor]
        let text = drinks.level(of: offer) == 0 ? offer.blurbs.first : offer.blurbs.second
        TitleText.set(blurb, to: text, size: text.count > 70 ? 23 : (text.count > 50 ? 26 : 30))
        TitleText.set(comment, to: "\u{201C}\(offer.comment)\u{201D}", size: 25, italic: true)
    }

    /// The bottle, the user's vector from the catalog, 180 points tall and anchored at its
    /// bottom so that runs off the screen: blue for a booster, gold for a biomorph or
    /// Bio-Boba.
    static func bottle(for drink: Greateraid, colour: SKColor) -> SKNode {
        let height: CGFloat = 180
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
        super.init(halfWidth: halfWidth, halfHeight: halfHeight)
        let header = TitleText.node("GREATERAID", size: 40)
        header.position = CGPoint(x: 0, y: halfHeight - 44)
        addChild(header)
        let sub = TitleText.node("\(who) IS DRINKING", size: 26)
        sub.position = CGPoint(x: 0, y: 10)
        addChild(sub)
        clock.position = CGPoint(x: 0, y: -50)
        addChild(clock)
        showSeconds(Series.pickSeconds)
    }

    required init?(coder: NSCoder) { fatalError() }

    func showSeconds(_ seconds: Int) {
        TitleText.set(clock, to: "\(max(seconds, 0))", size: 32)
    }
}

/// Who won, and the two ways on. `again` is NEW MATCH offline and REMATCH online, where
/// it waits for the other side to press theirs.
final class WinScreen: Screen {
    private let waiting = SKSpriteNode()

    init(halfWidth: CGFloat, halfHeight: CGFloat, winner: String, again: String, onAgain: @escaping () -> Void, onTitle: @escaping () -> Void) {
        super.init(halfWidth: halfWidth, halfHeight: halfHeight)
        let title = TitleText.node("\(winner) WINS", size: 56)
        title.position = CGPoint(x: 0, y: halfHeight * 0.35)
        addChild(title)
        addButton(again, at: CGPoint(x: 0, y: -halfHeight * 0.1), action: onAgain)
        addButton("TITLE", at: CGPoint(x: 0, y: -halfHeight * 0.4), action: onTitle)
        waiting.position = CGPoint(x: 0, y: -halfHeight * 0.25)
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
    private var tiles: [SKShapeNode] = []
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
        super.init(halfWidth: halfWidth, halfHeight: halfHeight)
        let header = TitleText.node("STAGE SELECT", size: 44)
        header.position = CGPoint(x: 0, y: halfHeight - 44)
        addChild(header)
        if let heading {
            let sub = TitleText.node(heading, size: 22)
            sub.position = CGPoint(x: 0, y: halfHeight - 80)
            addChild(sub)
        }
        let width = min(halfWidth * 0.56, 180), height: CGFloat = 96
        let spacing = width + 20
        for (index, name) in stages.enumerated() {
            let tile = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: 8)
            tile.position = CGPoint(x: (CGFloat(index) - CGFloat(stages.count - 1) / 2) * spacing, y: -12)
            tile.fillColor = SKColor(white: 1, alpha: 0.08)
            tile.strokeColor = SKColor(white: 1, alpha: 0.7)
            tile.lineWidth = 2
            let label = TitleText.node(name, size: 20)
            label.setScale(min(1, (width - 16) / max(label.size.width, 1)))
            tile.addChild(label)
            addChild(tile)
            tiles.append(tile)
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
        refresh()
    }

    func lock(voter: Int) {
        guard picks[voter] == nil, flipLit == nil, let at = cursors[voter] else { return }
        picks[voter] = at
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
              let index = tiles.firstIndex(where: { $0.frame.contains(point) }) else { return false }
        if cursors[voter] == index {
            lock(voter: voter)
        } else if picks[voter] == nil {
            cursors[voter] = index
            refresh()
        }
        return true
    }

    private func refresh() {
        let raised: Set<Int> = flipLit.map { [$0] } ?? Set(voters.compactMap { picks[$0] ?? cursors[$0] })
        for (index, tile) in tiles.enumerated() {
            tile.setScale(raised.contains(index) ? 1.12 : 1)
            tile.fillColor = SKColor(white: 1, alpha: raised.contains(index) ? 0.18 : 0.08)
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
            let frame = tile.frame
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
        super.init(halfWidth: halfWidth, halfHeight: halfHeight)
        let title = TitleText.node("PAUSED", size: 56)
        title.position = CGPoint(x: 0, y: halfHeight * 0.45)
        addChild(title)
        addButton("RESTART MATCH", at: CGPoint(x: 0, y: halfHeight * 0.05), action: onRestart)
        addButton("TITLE SCREEN", at: CGPoint(x: 0, y: -halfHeight * 0.25), action: onTitle)
        addButton("RESUME", at: CGPoint(x: 0, y: -halfHeight * 0.55), action: onResume)
        // On RESUME, so a press of jump straight after pausing plays on.
        place(cursor: 2)
    }

    required init?(coder: NSCoder) { fatalError() }
}
