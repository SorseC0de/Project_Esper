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
    private var plates: [Int: (plate: SKSpriteNode, piece: UIPiece, size: CGSize, label: SKSpriteNode, text: String, textSize: CGFloat)] = [:]
    /// Futuristic_UI choices, by choice: what's coloured, the blue or, under the cursor, gold.
    private var tinted: [Int: SKNode] = [:]

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
        plates[choices.count - 1] = (plate, piece, plateSize, label, text, size * tuned(.text))
        if choices.count == 1 { cursor = 0 }
        showCursor()
        return button
    }

    /// A black card from the pack behind a screen's content, `size` points round `centre`,
    /// its height at the panels' scale (its width comes from the header's, which has it).
    @discardableResult
    func addCard(size: CGSize, at centre: CGPoint, piece: UIPiece = .cardBlack) -> SKSpriteNode {
        let card = piece.node(size: CGSize(width: size.width, height: size.height * tuned(.panels)), corners: tuned(.panels))
        card.position = centre
        card.zPosition = -5
        addChild(card)
        return card
    }

    /// A royal blue header ribbon with title lettering on it; its width, for a card to match.
    @discardableResult
    func addHeader(_ text: String, size: CGFloat = 34, at point: CGPoint, width: CGFloat? = nil, height: CGFloat = 58) -> CGFloat {
        let header = SKNode()
        header.position = point
        let panels = tuned(.panels)
        let label = TitleText.node(text, size: size * tuned(.titles))
        // The ribbon at the panels' scale, grown only when the lettering needs the room.
        let ribbonSize = CGSize(width: max((width ?? 0) * panels, label.size.width + 60), height: max(height * panels, label.size.height + 18))
        let ribbon = UIPiece.headerBlue.node(size: ribbonSize, corners: panels)
        ribbon.zPosition = -1
        header.addChild(ribbon)
        let shift = TitleText.dropShift(size: size * tuned(.titles)) * UITuning.shared.textRise
        label.position = CGPoint(x: -shift, y: shift)
        header.addChild(label)
        addChild(header)
        return ribbonSize.width
    }

    /// A choice in one of Futuristic_UI's frames at `scale` of the menus' size, turned round
    /// across or down as asked, and in its face its lettering in the menus' face or `icon`: all
    /// in the menus' blue, gold and a tenth bigger under the cursor.
    @discardableResult
    func addFramed(_ text: String?, frame name: String, scale: CGFloat, mirroredX: Bool = false, mirroredY: Bool = false,
                   icon: SKNode? = nil, textSize: CGFloat = 16, at point: CGPoint, sound: SoundBoard.Effect = SoundBoard.confirm,
                   action: @escaping () -> Void) -> SKNode {
        let button = SKNode()
        button.position = point
        let frame = Futuristic.sprite(name, scale: scale)
        frame.xScale = mirroredX ? -1 : 1
        frame.yScale = mirroredY ? -1 : 1
        button.addChild(frame)
        let face = Futuristic.faces[name] ?? CGPoint(x: 0.5, y: 0.5)
        let faceX = mirroredX ? 1 - face.x : face.x, faceY = mirroredY ? 1 - face.y : face.y
        let middle = CGPoint(x: (faceX - 0.5) * frame.size.width, y: (0.5 - faceY) * frame.size.height)
        if let text {
            let label = Futuristic.label(text, size: textSize * tuned(.text))
            label.position = middle
            button.addChild(label)
        }
        if let icon {
            icon.position = middle
            button.addChild(icon)
        }
        addChild(button)
        let size = frame.size
        let hit = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
        choices.append(Choice(node: button, hit: hit, enabled: true, arrowAt: point, arrowTurn: 0, sound: sound, action: action))
        tinted[choices.count - 1] = button
        if choices.count == 1 { cursor = 0 }
        showCursor()
        return button
    }

    /// A node and everything in it in a colour: sprites tinted, lettering coloured.
    private static func colour(_ node: SKNode, _ colour: SKColor) {
        if let sprite = node as? SKSpriteNode, sprite.colorBlendFactor > 0 { sprite.color = colour }
        if let sprite = node as? SKSpriteNode, sprite.texture == nil { sprite.color = colour }
        if let label = node as? SKLabelNode { label.fontColor = colour }
        for child in node.children { Screen.colour(child, colour) }
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
            if let node = tinted[index] {
                choice.node.setScale(lit ? Futuristic.litGrowth : 1)
                Screen.colour(node, lit ? Futuristic.litColour : Futuristic.lineColour)
                continue
            }
            choice.node.setScale(lit ? 1.12 : 1)
            if let plate = plates[index] {
                (lit ? UIPiece.buttonGold : plate.piece).fit(plate.plate, to: plate.size, corners: tuned(.buttons))
                // On the gold plate the lettering's lower half goes light blue.
                TitleText.set(plate.label, to: plate.text, size: plate.textSize, lit: lit)
            }
        }
        if plates[cursor] != nil || !showsArrow {
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

    /// Whether the arrow points at the cursor's choice; a screen with its own mark goes without.
    var showsArrow: Bool { true }

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

    /// What circle or square (B or X) does here: nothing on a screen without a way back.
    var back: (() -> Void)?

    func goBack() {
        guard let back else { return }
        SoundBoard.shared.play(.menuBack)
        back()
    }
}

/// Three bottles of Greateraid to choose from, large, their bottoms off the screen, each
/// leaning a little, its name across it; what the raised one does is lettered in the
/// middle of the screen. A tap on a bottle raises it, a tap on the raised one drinks it;
/// on the pad the stick moves and jump drinks.
final class PickScreen: Screen {
    private let offers: [Greateraid]
    private let drinks: Drinks
    /// What the raised drink does, as many lines as it takes to fit the plate, and its quote
    /// over it, smaller, dimmer, in italics.
    private let blurb = SKNode()
    private let comment = SKSpriteNode()
    private let clock = SKSpriteNode()
    /// The raised drink's name, lettered as the FLO meter's word, in front of the drinker on the
    /// plate's top edge, and "(Second Sip)" over it when it is one.
    private let drinkName = SKNode()
    private let secondSip = SKSpriteNode()
    /// The plate's inside, for the lettering to fit: its width, and the room under the quote.
    private var plateInside = CGSize.zero
    private var blurbTop: CGFloat = 0
    /// Each bottle's white outline, shown on the raised one.
    private var outlines: [SKNode] = []
    private let onDrink: (Greateraid) -> Void

    /// `player_drinkchoice` in the picker's look, its frames played very slowly, standing on the
    /// blurb's banner in the middle; its art pixels this many points, on the UI panel's slider.
    static let drinkerScaleKey = "ui.pick.drinkerScale"
    static var drinkerScale: CGFloat { UserDefaults.standard.object(forKey: drinkerScaleKey).map { CGFloat(($0 as? Double) ?? 4) } ?? 4 }
    static let drinkerFrameSeconds = 0.5
    /// The sheet's feet, eight pixels up its 48.
    static let drinkerFeet: CGFloat = 8.0 / 48

    /// `timed` shows the seconds left, for a networked pick; `drinker`, the frames of the one picking.
    init(halfWidth: CGFloat, halfHeight: CGFloat, offers: [Greateraid], drinks: Drinks, colour: SKColor, timed: Bool = false,
         drinker: [SKTexture] = [], onDrink: @escaping (Greateraid) -> Void) {
        self.offers = offers
        self.drinks = drinks
        self.onDrink = onDrink
        super.init(halfWidth: halfWidth, halfHeight: halfHeight, kind: .pick)
        // Smaller than the other screens' headers, box and lettering: the drinks are the thing here.
        addHeader("GREATERAID", size: 26, at: CGPoint(x: 0, y: halfHeight * 0.8), width: 200, height: 38)
        let sub = TitleText.node("YOU WERE SCORED ON. DRINK UP.", size: 13 * tuned(.text))
        // Just under the ribbon.
        sub.position = CGPoint(x: 0, y: halfHeight * 0.8 - 19 * tuned(.panels) - sub.size.height / 2 - 4)
        addChild(sub)
        if timed {
            // The seconds in a blue round button, top right.
            let dial = UIPiece.circleBlue.node(size: CGSize(width: 52, height: 56).scaled(by: tuned(.buttons)), corners: tuned(.buttons))
            dial.position = CGPoint(x: halfWidth - 50, y: halfHeight * 0.74)
            dial.zPosition = -1
            addChild(dial)
            clock.position = CGPoint(x: dial.position.x, y: dial.position.y + UIPiece.circleBlue.faceRise * tuned(.buttons))
            addChild(clock)
            showSeconds(Series.pickSeconds)
        }
        // The quote and what the raised drink does, on a blue banner over the bottles: its top
        // where the drinker stands, as it was, and deep enough for three lines under the quote.
        let plateSize = CGSize(width: min(halfWidth * 1.7, 620), height: PickScreen.plateHeight).scaled(by: tuned(.panels))
        let plate = UIPiece.plateBlue.node(size: plateSize, corners: tuned(.panels))
        plate.position = CGPoint(x: 0, y: -halfHeight * 0.05 + 43 * tuned(.panels) - plateSize.height / 2)
        plate.zPosition = 1
        addChild(plate)
        let plateTop = plate.position.y + plateSize.height / 2
        plateInside = CGSize(width: plateSize.width - 40 * tuned(.panels), height: plateSize.height - 22 * tuned(.panels))
        if let first = drinker.first {
            let figure = SKSpriteNode(texture: first)
            figure.size = first.size().scaled(by: PickScreen.drinkerScale)
            figure.anchorPoint = CGPoint(x: 0.5, y: PickScreen.drinkerFeet)
            figure.position = CGPoint(x: 0, y: plate.position.y + plate.size.height / 2)
            figure.zPosition = 0.5
            figure.run(.repeatForever(.animate(with: drinker, timePerFrame: PickScreen.drinkerFrameSeconds)))
            addChild(figure)
        }

        let spacing = min(halfWidth * 0.55, 200)
        for (index, offer) in offers.enumerated() {
            let x = (CGFloat(index) - 1) * spacing
            let bottle = PickScreen.bottle(for: offer, colour: colour, height: 180 * tuned(.buttons))
            // Leaning between 5 and 30 degrees, either way; the bottom clipped by the screen's edge.
            let lean = CGFloat(5 + Int.random(in: 0...15)) * .pi / 180 * (Bool.random() ? 1 : -1)
            bottle.zRotation = lean
            bottle.position = CGPoint(x: x, y: -halfHeight - 24)
            // Over everything on the screen.
            bottle.zPosition = 5
            addChild(bottle)
            outlines.append(PickScreen.outline(of: bottle, width: 5 * tuned(.buttons)))
            let hit = CGRect(x: x - spacing / 2 + 6, y: -halfHeight, width: spacing - 12, height: halfHeight)
            addChoice(bottle, hit: hit, arrowAt: CGPoint(x: x, y: -halfHeight + 108), arrowTurn: 0) { [weak self] in
                guard let self else { return }
                self.onDrink(offer)
            }
        }
        // The quote just under the plate's top edge, below the name sitting across it.
        comment.position = CGPoint(x: 0, y: plateTop - 26 * tuned(.panels))
        comment.zPosition = 2
        comment.alpha = PickScreen.commentAlpha
        addChild(comment)
        blurbTop = plateTop - 40 * tuned(.panels)
        plateInside.height = blurbTop - (plate.position.y - plateSize.height / 2) - 10 * tuned(.panels)
        blurb.zPosition = 2
        addChild(blurb)
        // In front of the drinker (0.5) and the plate (1).
        drinkName.position = CGPoint(x: 0, y: plateTop)
        drinkName.zPosition = 3
        addChild(drinkName)
        secondSip.zPosition = 3
        addChild(secondSip)
        moved()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var tapFiresAtOnce: Bool { false }
    override var showsArrow: Bool { false }

    /// A thick white outline round a bottle, one white silhouette baked once and drawn behind
    /// it as its child, so it takes the bottle's lean and its raise. Hidden until the bottle is
    /// raised. (Sixteen recoloured copies of the vector bottle drew as a broken second bottle.)
    static func outline(of bottle: SKSpriteNode, width: CGFloat) -> SKNode {
        guard let image = bottleImages[bottle.name ?? ""] else { return SKNode() }
        let pad = ceil(width)
        let size = CGSize(width: image.size.width + pad * 2, height: image.size.height + pad * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let silhouette = UIGraphicsImageRenderer(size: size, format: format).image { context in
            for step in 0..<24 {
                let angle = CGFloat(step) / 24 * 2 * .pi
                image.draw(at: CGPoint(x: pad + cos(angle) * width, y: pad + sin(angle) * width))
            }
            UIColor.white.setFill()
            // Only where the copies drew: the plain fill's own blend is normal, a white box.
            context.fill(CGRect(origin: .zero, size: size), blendMode: .sourceIn)
        }
        let ring = SKSpriteNode(texture: SKTexture(image: silhouette))
        ring.size = size
        // The bottle's bottom middle where the silhouette's is, `pad` in from its edge.
        ring.anchorPoint = CGPoint(x: 0.5, y: pad / size.height)
        ring.zPosition = -0.5
        ring.isHidden = true
        bottle.addChild(ring)
        return ring
    }

    /// The seconds left on the pick.
    func showSeconds(_ seconds: Int) {
        guard clock.parent != nil else { return }
        TitleText.set(clock, to: "\(max(seconds, 0))", size: 24 * tuned(.text))
    }

    override func moved() {
        guard choices.indices.contains(cursor) else { return }
        let offer = offers[cursor]
        for (index, outline) in outlines.enumerated() { outline.isHidden = index != cursor }
        // The name as the FLO meter letters its word, straight, centred on the plate's top edge.
        drinkName.removeAllChildren()
        let name = FloText.node(offer.name.uppercased(), height: PickScreen.nameHeight * tuned(.titles))
        drinkName.addChild(name)
        if drinks.isSecondSip(offer) {
            TitleText.set(secondSip, to: "(Second Sip)", size: 14 * tuned(.titles), italic: true)
            secondSip.position = CGPoint(x: 0, y: drinkName.position.y + name.size.height / 2 + secondSip.size.height / 2)
            secondSip.isHidden = false
        } else {
            secondSip.isHidden = true
        }
        let text = drinks.level(of: offer) == 0 ? offer.blurbs.first : offer.blurbs.second
        let scale = tuned(.text)
        TitleText.set(comment, to: "\u{201C}\(offer.comment)\u{201D}", size: PickScreen.commentSize * scale, italic: true)
        layBlurb(text, scale: scale)
    }

    /// What the drink does in as many lines as it needs, at the largest of its sizes whose lines
    /// all fit the plate's width and stack within the room under the quote.
    private func layBlurb(_ text: String, scale: CGFloat) {
        blurb.removeAllChildren()
        var chosen: (lines: [String], size: CGFloat) = ([text], PickScreen.blurbSizes.last! * scale)
        for base in PickScreen.blurbSizes {
            let size = base * scale
            let lines = TitleText.wrapped(text, size: size, width: plateInside.width)
            let lineHeight = TitleText.node("Ag", size: size).size.height * PickScreen.lineShare
            if CGFloat(lines.count) * lineHeight <= plateInside.height {
                chosen = (lines, size)
                break
            }
            chosen = (lines, size)
        }
        let nodes = chosen.lines.map { TitleText.node($0, size: chosen.size) }
        let lineHeight = (nodes.first?.size.height ?? 0) * PickScreen.lineShare
        // Centred in the room under the quote.
        let middle = blurbTop - plateInside.height / 2
        for (index, node) in nodes.enumerated() {
            node.position = CGPoint(x: 0, y: middle + (CGFloat(nodes.count - 1) / 2 - CGFloat(index)) * lineHeight)
            blurb.addChild(node)
        }
    }
    /// The plate's depth before the panels' scale; the name's cap height; the quote's size and
    /// how much of it shows; the description's sizes, largest first; and its lines' spacing as a
    /// share of a line's drawn height (the lettering's outline and drop overlap).
    static let plateHeight: CGFloat = 120
    static let nameHeight: CGFloat = 16
    static let commentSize: CGFloat = 13
    static let commentAlpha: CGFloat = 0.7
    static let blurbSizes: [CGFloat] = [20, 18, 16, 14, 12]
    static let lineShare: CGFloat = 0.8

    /// The bottle, the user's vector from the catalog, 180 points tall and anchored at its
    /// bottom so that runs off the screen: blue for a booster, gold for a biomorph or
    /// Bio-Boba.
    static func bottle(for drink: Greateraid, colour: SKColor, height: CGFloat = 180) -> SKSpriteNode {
        let name = drink.kind == .booster ? "Greateraid" : "Greateraid-Gold"
        // The vector drawn once at the size it's shown, at the screen's scale, crisp, and kept
        // for its outline.
        let key = "\(name)|\(height)"
        let image: UIImage
        if let made = bottleImages[key] {
            image = made
        } else {
            let source = UIImage(named: name) ?? UIImage()
            let aspect = source.size.width / max(source.size.height, 1)
            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale * TitleText.renderScale
            image = UIGraphicsImageRenderer(size: CGSize(width: height * aspect, height: height), format: format).image { _ in
                source.draw(in: CGRect(x: 0, y: 0, width: height * aspect, height: height))
            }
            bottleImages[key] = image
        }
        let bottle = SKSpriteNode(texture: SKTexture(image: image))
        bottle.size = image.size
        bottle.anchorPoint = CGPoint(x: 0.5, y: 0)
        bottle.name = key
        return bottle
    }
    nonisolated(unsafe) private static var bottleImages: [String: UIImage] = [:]
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
        let dial = UIPiece.circleBlue.node(size: CGSize(width: 64, height: 69).scaled(by: tuned(.buttons)), corners: tuned(.buttons))
        dial.position = CGPoint(x: 0, y: -60)
        dial.zPosition = -1
        addChild(dial)
        clock.position = CGPoint(x: 0, y: dial.position.y + UIPiece.circleBlue.faceRise * tuned(.buttons))
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
        addCard(size: CGSize(width: headerWidth, height: halfHeight * 1.55), at: CGPoint(x: 0, y: -halfHeight * 0.1), piece: .cardPurple)
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
    /// Each stage: Futuristic_UI's box1, in the menus' blue or gold when raised, in a container
    /// that grows a tenth.
    private var tiles: [SKNode] = []
    private var tilePlates: [SKSpriteNode] = []
    /// Each stage's name in its lines, two when it has a space to break at, in the menus' face.
    private var tileLabels: [[SKLabelNode]] = []
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
        // The title lettered as FLO is.
        let title = FloText.node("STAGE SELECT", height: StageSelectScreen.titleHeight * tuned(.titles))
        title.position = CGPoint(x: 0, y: halfHeight * 0.7)
        addChild(title)
        if let heading {
            let sub = Futuristic.label(heading, size: 22 * tuned(.titles))
            sub.position = CGPoint(x: 0, y: halfHeight * 0.44)
            addChild(sub)
        }
        let buttons = tuned(.buttons)
        // More than four stages go in two rows, the first the longer; each as wide as fits its
        // row on the screen.
        let rows = stages.count > StageSelectScreen.oneRowMost ? 2 : 1
        let perRow = (stages.count + rows - 1) / rows
        let fitting = (halfWidth * 2 * 0.92 - 20 * CGFloat(perRow - 1)) / CGFloat(max(perRow, 1))
        let width = min(halfWidth * 0.56, 180 * buttons, fitting)
        let box = Futuristic.image("box1")
        tileSize = CGSize(width: width, height: width * box.size.height / max(box.size.width, 1))
        let spacing = width + 20
        let rowGap = tileSize.height + 14 * buttons
        for (index, name) in stages.enumerated() {
            let tile = SKNode()
            let row = index / perRow
            let inRow = row == 0 ? min(perRow, stages.count) : stages.count - perRow
            let column = index - row * perRow
            tile.position = CGPoint(x: (CGFloat(column) - CGFloat(inRow - 1) / 2) * spacing,
                                    y: -halfHeight * (rows == 2 ? 0.15 : 0.1) + (CGFloat(rows - 1) / 2 - CGFloat(row)) * rowGap)
            let plate = SKSpriteNode(texture: SKTexture(image: box))
            plate.size = tileSize
            plate.color = Futuristic.lineColour
            plate.colorBlendFactor = 1
            plate.zPosition = -1
            tile.addChild(plate)
            let textSize = 18 * tuned(.text)
            let lines = StageSelectScreen.lines(of: name)
            var labels: [SKLabelNode] = []
            for (number, line) in lines.enumerated() {
                let label = Futuristic.label(line, size: textSize)
                label.setScale(min(1, (width * 0.82) / max(label.frame.width, 1)))
                let step = textSize * StageSelectScreen.lineShare
                label.position = CGPoint(x: 0, y: (CGFloat(lines.count - 1) / 2 - CGFloat(number)) * step)
                tile.addChild(label)
                labels.append(label)
            }
            addChild(tile)
            tiles.append(tile)
            tilePlates.append(plate)
            tileLabels.append(labels)
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

    /// A row holds this many stages at most before they go in two.
    static let oneRowMost = 4
    /// The name's lines' spacing, a share of the lettering's size.
    static let lineShare: CGFloat = 1.05
    /// STAGE SELECT's cap height, in points.
    static let titleHeight: CGFloat = 15
    /// A name in two lines, broken at the space nearest its middle; one with no space in one.
    static func lines(of name: String) -> [String] {
        let spaces = name.indices.filter { name[$0] == " " }
        guard let middle = spaces.min(by: {
            abs(name.distance(from: name.startIndex, to: $0) * 2 - name.count) < abs(name.distance(from: name.startIndex, to: $1) * 2 - name.count)
        }) else { return [name] }
        return [String(name[..<middle]), String(name[name.index(after: middle)...])]
    }

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
            tile.setScale(lit ? Futuristic.litGrowth : 1)
            tilePlates[index].color = lit ? Futuristic.litColour : Futuristic.lineColour
            for label in tileLabels[index] { label.fontColor = lit ? Futuristic.litColour : Futuristic.lineColour }
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

/// The pause, against the computer: start the match over, the settings, go to the title, or play on.
/// The pause, over the match on a dark wash under a thin material (drawn by the SwiftUI layer):
/// each choice in Futuristic_UI's frame 8, every other one turned round, sliding and fading in
/// from the left, then the right, and so on down; RESUME frame 1 with arrow1 in it, on the
/// pause icon's own place, and the settings' gear in frame 9 turned upside down under it.
final class PauseScreen: Screen {
    /// The choices' frames' size against the menus', the gap between them, and their entrance.
    static let optionScale: CGFloat = 0.8
    /// The choices' lettering, small enough to sit inside the frame.
    static let optionTextSize: CGFloat = 12
    static let optionGap: CGFloat = 8
    static let slideDistance: CGFloat = 120
    static let slideSeconds = 0.3
    static let slideStagger = 0.07
    /// The gear's frame under RESUME's.
    static let gearGap: CGFloat = 4
    /// The wash under the material.
    static let washOpacity = 0.33

    /// `extras`: a game's own choices, ZONES' turn's, over the rest. `resumeAt`: the pause
    /// icon's frame, in the HUD's points.
    init(halfWidth: CGFloat, halfHeight: CGFloat, resumeAt: CGRect, onRestart: @escaping () -> Void, onSettings: @escaping () -> Void,
         onTitle: @escaping () -> Void, onResume: @escaping () -> Void, extras: [(String, () -> Void)] = []) {
        super.init(halfWidth: halfWidth, halfHeight: halfHeight, kind: .pause)
        let options: [(text: String, sound: SoundBoard.Effect, action: () -> Void)] =
            extras.map { ($0.0, SoundBoard.confirm, $0.1) } + [("RESTART MATCH", SoundBoard.confirm, onRestart), ("TITLE SCREEN", .menuBack, onTitle)]
        let image = Futuristic.image("8")
        let height = image.size.height * image.scale * Futuristic.pointsPerPixel * PauseScreen.optionScale
        let total = CGFloat(options.count) * height + CGFloat(options.count - 1) * PauseScreen.optionGap
        for (index, option) in options.enumerated() {
            let place = CGPoint(x: 0, y: total / 2 - height / 2 - CGFloat(index) * (height + PauseScreen.optionGap))
            // The second, fourth and so on turned round both ways.
            let turned = index % 2 == 1
            let node = addFramed(option.text, frame: "8", scale: PauseScreen.optionScale, mirroredX: turned, mirroredY: turned,
                                 textSize: PauseScreen.optionTextSize, at: place, sound: option.sound, action: option.action)
            // In from the left, then the right, each a beat after the one over it.
            let side: CGFloat = index % 2 == 0 ? -1 : 1
            node.position.x += side * PauseScreen.slideDistance
            node.alpha = 0
            let slide = SKAction.move(to: place, duration: PauseScreen.slideSeconds)
            slide.timingMode = .easeOut
            node.run(.sequence([.wait(forDuration: Double(index) * PauseScreen.slideStagger),
                                .group([slide, .fadeIn(withDuration: PauseScreen.slideSeconds)])]))
        }
        // RESUME on the pause icon, as big: frame 1, arrow1 in its face.
        let iconScale = TouchControls.pauseScale
        let arrowImage = Futuristic.image("arrow1")
        let arrow = Futuristic.sprite("arrow1", scale: 1)
        let resumeFrame = Futuristic.image("1")
        let faceHeight = resumeFrame.size.height * resumeFrame.scale * Futuristic.pointsPerPixel * iconScale * 0.45
        arrow.size = CGSize(width: faceHeight * arrowImage.size.width / max(arrowImage.size.height, 1), height: faceHeight)
        let resume = addFramed(nil, frame: "1", scale: iconScale, icon: arrow, at: CGPoint(x: resumeAt.midX, y: resumeAt.midY),
                               sound: .menuBack, action: onResume)
        // The gear under it: frame 9 upside down, centred under RESUME's face.
        let gearFrame = Futuristic.image("9")
        let gearSize = CGSize(width: gearFrame.size.width * gearFrame.scale * Futuristic.pointsPerPixel * iconScale,
                              height: gearFrame.size.height * gearFrame.scale * Futuristic.pointsPerPixel * iconScale)
        let gear = SKSpriteNode(texture: UIImage(named: "ui_icon_settings").map { SKTexture(image: $0) })
        gear.size = CGSize(width: gearSize.width * 0.5, height: gearSize.width * 0.5 * 31 / 30)
        gear.color = Futuristic.lineColour
        gear.colorBlendFactor = 1
        let resumeFace = Futuristic.faces["1"] ?? CGPoint(x: 0.5, y: 0.5)
        let faceX = resume.position.x + (resumeFace.x - 0.5) * resumeAt.width
        let nineFace = Futuristic.faces["9"] ?? CGPoint(x: 0.5, y: 0.5)
        addFramed(nil, frame: "9", scale: iconScale, mirroredY: true, icon: gear,
                  at: CGPoint(x: faceX - (nineFace.x - 0.5) * gearSize.width, y: resumeAt.minY - PauseScreen.gearGap - gearSize.height / 2),
                  action: onSettings)
        // On RESUME, so a press of jump straight after pausing plays on.
        place(cursor: options.count)
    }

    override var showsArrow: Bool { false }

    required init?(coder: NSCoder) { fatalError() }
}

extension CGSize {
    func scaled(by factor: CGFloat) -> CGSize { CGSize(width: width * factor, height: height * factor) }
}
