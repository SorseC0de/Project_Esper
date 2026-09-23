import EsperSim
import SpriteKit

/// A screen laid over the game in HUD points: title lettering and a few choices a tap or
/// the pad picks from. The pad's cursor is the raised choice.
class Screen: SKNode {
    struct Choice {
        let node: SKNode
        let hit: CGRect
        let enabled: Bool
        let action: () -> Void
    }

    private(set) var choices: [Choice] = []
    private(set) var cursor = 0
    let halfWidth: CGFloat
    let halfHeight: CGFloat

    init(halfWidth: CGFloat, halfHeight: CGFloat) {
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        super.init()
        zPosition = 200
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A dark veil over the world, so the lettering reads.
    func veil(alpha: CGFloat = 0.55) {
        let veil = SKSpriteNode(color: SKColor(red: 0.1, green: 0.06, blue: 0.14, alpha: alpha),
                                size: CGSize(width: halfWidth * 2 + 4, height: halfHeight * 2 + 4))
        veil.zPosition = -1
        addChild(veil)
    }

    /// A lettered button. Disabled ones are dimmed and never fire.
    @discardableResult
    func addButton(_ text: String, size: CGFloat = 26, at point: CGPoint, enabled: Bool = true, action: @escaping () -> Void) -> SKNode {
        let label = TitleText.node(text, size: size)
        label.position = point
        label.alpha = enabled ? 1 : 0.35
        addChild(label)
        let hit = CGRect(x: point.x - label.size.width / 2 - 12, y: point.y - label.size.height / 2 - 8,
                         width: label.size.width + 24, height: label.size.height + 16)
        choices.append(Choice(node: label, hit: hit, enabled: enabled, action: action))
        if choices.count == 1 { cursor = 0 }
        showCursor()
        return label
    }

    func addChoice(_ node: SKNode, hit: CGRect, enabled: Bool = true, action: @escaping () -> Void) {
        choices.append(Choice(node: node, hit: hit, enabled: enabled, action: action))
        showCursor()
    }

    /// The cursor's choice is raised a little and the rest sit still.
    func showCursor() {
        for (index, choice) in choices.enumerated() {
            choice.node.setScale(index == cursor && choice.enabled ? 1.12 : 1)
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

/// The title: the name and the two ways in, one of them not open yet.
final class TitleScreen: Screen {
    init(halfWidth: CGFloat, halfHeight: CGFloat, onBestOfSeven: @escaping () -> Void) {
        super.init(halfWidth: halfWidth, halfHeight: halfHeight)
        veil()
        let title = TitleText.node("PROJECT ESPER", size: 56)
        title.position = CGPoint(x: 0, y: halfHeight * 0.35)
        addChild(title)
        addButton("BEST OF 7", at: CGPoint(x: 0, y: -halfHeight * 0.1), action: onBestOfSeven)
        addButton("MULTIPLAYER", at: CGPoint(x: 0, y: -halfHeight * 0.4), enabled: false) {}
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Three bottles of Greateraid to choose from, large, their bottoms off the screen, each
/// leaning a little, its name across it; what the raised one does is lettered in the
/// middle of the screen. A tap on a bottle raises it, a tap on the raised one drinks it;
/// on the pad the stick moves and jump drinks.
final class PickScreen: Screen {
    private let offers: [Greateraid]
    private let drinks: Drinks
    private let blurb = SKSpriteNode()
    private let onDrink: (Greateraid) -> Void

    init(halfWidth: CGFloat, halfHeight: CGFloat, offers: [Greateraid], drinks: Drinks, colour: SKColor, onDrink: @escaping (Greateraid) -> Void) {
        self.offers = offers
        self.drinks = drinks
        self.onDrink = onDrink
        super.init(halfWidth: halfWidth, halfHeight: halfHeight)
        veil(alpha: 0.7)
        let header = TitleText.node("GREATERAID", size: 40)
        header.position = CGPoint(x: 0, y: halfHeight - 44)
        addChild(header)
        let sub = SKLabelNode(text: "You were scored on. Drink up.")
        sub.fontName = "Menlo-Bold"
        sub.fontSize = 11
        sub.fontColor = SKColor(white: 1, alpha: 0.7)
        sub.position = CGPoint(x: 0, y: halfHeight - 72)
        addChild(sub)

        let spacing = min(halfWidth * 0.62, 260)
        for (index, offer) in offers.enumerated() {
            let x = (CGFloat(index) - 1) * spacing
            let bottle = PickScreen.bottle(for: offer, colour: colour)
            // Leaning between 5 and 30 degrees, either way; the bottom clipped by the screen's edge.
            let lean = CGFloat(5 + Int.random(in: 0...25)) * .pi / 180 * (Bool.random() ? 1 : -1)
            bottle.zRotation = lean
            bottle.position = CGPoint(x: x, y: -halfHeight - 30)
            addChild(bottle)
            let name = TitleText.node(offer.name.uppercased(), size: offer.name.count > 14 ? 13 : 16)
            name.position = CGPoint(x: x, y: -halfHeight + 118)
            name.zPosition = 2
            addChild(name)
            let hit = CGRect(x: x - spacing / 2 + 6, y: -halfHeight, width: spacing - 12, height: halfHeight * 1.2)
            addChoice(bottle, hit: hit) { [weak self] in
                guard let self else { return }
                self.onDrink(offer)
            }
        }
        blurb.position = CGPoint(x: 0, y: 20)
        addChild(blurb)
        moved()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var tapFiresAtOnce: Bool { false }

    override func moved() {
        guard choices.indices.contains(cursor) else { return }
        let offer = offers[cursor]
        let text: String
        switch offer.kind {
        case .booster: text = drinks.level(of: offer) == 0 ? offer.blurbs.first : offer.blurbs.second
        case .biomorph: text = offer.blurbs.first
        case .bioBoba: text = drinks.biomorph.map { "\($0.name) to level two: \($0.blurbs.second)" } ?? offer.blurbs.first
        }
        TitleText.set(blurb, to: text, size: text.count > 50 ? 16 : 20)
    }

    /// A bottle: a rounded body, shoulders, a neck and a cap, in the drink's colour with a
    /// black line, tall enough that its bottom runs off the screen.
    static func bottle(for drink: Greateraid, colour: SKColor) -> SKNode {
        let width: CGFloat = 96, height: CGFloat = 250
        let path = CGMutablePath()
        let bodyTop = height * 0.6
        let neckWidth = width * 0.38
        path.move(to: CGPoint(x: -width / 2, y: 0))
        path.addLine(to: CGPoint(x: -width / 2, y: bodyTop))
        path.addQuadCurve(to: CGPoint(x: -neckWidth / 2, y: bodyTop + 36), control: CGPoint(x: -width / 2, y: bodyTop + 30))
        path.addLine(to: CGPoint(x: -neckWidth / 2, y: height - 16))
        path.addLine(to: CGPoint(x: neckWidth / 2, y: height - 16))
        path.addLine(to: CGPoint(x: neckWidth / 2, y: bodyTop + 36))
        path.addQuadCurve(to: CGPoint(x: width / 2, y: bodyTop), control: CGPoint(x: width / 2, y: bodyTop + 30))
        path.addLine(to: CGPoint(x: width / 2, y: 0))
        path.closeSubpath()
        let fill: SKColor
        switch drink.kind {
        case .booster: fill = SKColor(rgb: 0xFFB040)
        case .biomorph: fill = SKColor(rgb: 0xBF7BFF)
        case .bioBoba: fill = SKColor(rgb: 0xF040E0)
        }
        let bottle = SKShapeNode(path: path)
        bottle.fillColor = fill
        bottle.strokeColor = .black
        bottle.lineWidth = 3
        let cap = SKShapeNode(rect: CGRect(x: -neckWidth / 2 - 4, y: height - 18, width: neckWidth + 8, height: 18), cornerRadius: 3)
        cap.fillColor = colour
        cap.strokeColor = .black
        cap.lineWidth = 3
        bottle.addChild(cap)
        let label = SKShapeNode(rect: CGRect(x: -width / 2 + 10, y: height * 0.18, width: width - 20, height: height * 0.3), cornerRadius: 6)
        label.fillColor = SKColor(white: 1, alpha: 0.85)
        label.strokeColor = .black
        label.lineWidth = 2
        bottle.addChild(label)
        return bottle
    }
}

/// Who won, and the two ways on.
final class WinScreen: Screen {
    init(halfWidth: CGFloat, halfHeight: CGFloat, winner: String, onNewMatch: @escaping () -> Void, onTitle: @escaping () -> Void) {
        super.init(halfWidth: halfWidth, halfHeight: halfHeight)
        veil()
        let title = TitleText.node("\(winner) WINS", size: 56)
        title.position = CGPoint(x: 0, y: halfHeight * 0.35)
        addChild(title)
        addButton("NEW MATCH", at: CGPoint(x: 0, y: -halfHeight * 0.1), action: onNewMatch)
        addButton("TITLE", at: CGPoint(x: 0, y: -halfHeight * 0.4), action: onTitle)
    }

    required init?(coder: NSCoder) { fatalError() }
}
