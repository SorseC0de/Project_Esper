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
        let sound: SoundBoard.Effect
        let action: () -> Void
    }

    private(set) var choices: [Choice] = []
    private(set) var cursor = 0
    /// Futuristic_UI choices, by choice: what's coloured, the blue or, under the cursor, gold.
    private var tinted: [Int: SKNode] = [:]

    /// This screen's tuned scale for one of its parts, 1 for a screen that isn't tuned.
    func tuned(_ part: UIPart) -> CGFloat {
        kind.map { UITuning.shared.scale($0, part) } ?? 1
    }
    let halfWidth: CGFloat
    let halfHeight: CGFloat

    /// The screen whose tuned sizes its buttons, text and titles take, if it has any.
    let kind: UIScreenKind?

    init(halfWidth: CGFloat, halfHeight: CGFloat, kind: UIScreenKind? = nil) {
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.kind = kind
        super.init()
        zPosition = 200
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A banner across the top left corner at 30 degrees, its title in FLO lettering along it: a
    /// band in black's first, edged in the menus' blue.
    func addCornerBanner(_ text: String) {
        let banner = SKNode()
        let band = SKSpriteNode(color: SKColor(rgb: EsperPalette.black.light), size: CGSize(width: Screen.bannerLength, height: Screen.bannerThickness))
        banner.addChild(band)
        for side: CGFloat in [-1, 1] {
            let edge = SKSpriteNode(color: Futuristic.lineColour, size: CGSize(width: Screen.bannerLength, height: Screen.bannerEdge))
            edge.position = CGPoint(x: 0, y: side * (Screen.bannerThickness / 2 - Screen.bannerEdge / 2))
            banner.addChild(edge)
        }
        let title = FloText.node(text, height: Screen.bannerTextHeight * tuned(.titles))
        title.zPosition = 1
        banner.addChild(title)
        banner.zRotation = Screen.bannerAngle
        banner.position = CGPoint(x: -halfWidth + Screen.bannerInset, y: halfHeight - Screen.bannerInset)
        banner.zPosition = 10
        addChild(banner)
    }
    static let bannerLength: CGFloat = 320
    static let bannerThickness: CGFloat = 30
    static let bannerEdge: CGFloat = 1.5
    static let bannerTextHeight: CGFloat = 10.5
    static let bannerAngle: CGFloat = .pi / 6
    /// The band's middle in from the corner, along both edges.
    static let bannerInset: CGFloat = 52

    /// A frame with lettering in its face and nothing to pick: a label, as the win screen's name.
    func addPlate(_ text: String, frame name: String, scale: CGFloat, textSize: CGFloat, at point: CGPoint) {
        let plate = SKNode()
        plate.position = point
        let frame = Futuristic.sprite(name, scale: scale)
        plate.addChild(frame)
        let face = Futuristic.faces[name] ?? CGPoint(x: 0.5, y: 0.5)
        let label = Futuristic.label(text, size: textSize * tuned(.text))
        label.position = CGPoint(x: (face.x - 0.5) * frame.size.width, y: (0.5 - face.y) * frame.size.height)
        plate.addChild(label)
        addChild(plate)
    }

    /// A choice in one of Futuristic_UI's frames at `scale` of the menus' size, turned round
    /// across or down as asked, and in its face its lettering in the menus' face or `icon`: all
    /// in the menus' blue, gold under the cursor.
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
        choices.append(Choice(node: button, hit: hit, enabled: true, sound: sound, action: action))
        tinted[choices.count - 1] = button
        if choices.count == 1 { cursor = 0 }
        showCursor()
        return button
    }

    /// A node and everything in it in a colour: sprites tinted, lettering coloured.
    static func colour(_ node: SKNode, _ colour: SKColor) {
        if let sprite = node as? SKSpriteNode, sprite.colorBlendFactor > 0 { sprite.color = colour }
        if let sprite = node as? SKSpriteNode, sprite.texture == nil { sprite.color = colour }
        if let label = node as? SKLabelNode { label.fontColor = colour }
        for child in node.children { Screen.colour(child, colour) }
    }

    /// A choice of any kind: `node` is what's raised under the cursor.
    func addChoice(_ node: SKNode, hit: CGRect, enabled: Bool = true, action: @escaping () -> Void) {
        choices.append(Choice(node: node, hit: hit, enabled: enabled, sound: SoundBoard.confirm, action: action))
        showCursor()
    }

    /// The cursor's choice is raised a little, a framed one gold, and the rest sit still.
    func showCursor() {
        for (index, choice) in choices.enumerated() {
            let lit = index == cursor && choice.enabled
            if let node = tinted[index] {
                Screen.colour(node, lit ? Futuristic.litColour : Futuristic.lineColour)
                continue
            }
            choice.node.setScale(lit ? 1.12 : 1)
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

    /// What circle or square (B or X) does here: nothing on a screen without a way back.
    var back: (() -> Void)?

    func goBack() {
        guard let back else { return }
        SoundBoard.shared.play(.menuBack)
        back()
    }
}

/// The Greateraid pick, a column top to bottom: GREATERAID in FLO lettering; the drinker on
/// their bench; rule 6; the raised drink's quote in italics; what it does; and the three bottles,
/// their bottoms off the screen, each leaning a little, its name in frame 12 over it. A tap on a
/// bottle raises it, a tap on the raised one drinks it; on the pad the stick moves and jump drinks.
final class PickScreen: Screen {
    private let offers: [Greateraid]
    private let drinks: Drinks
    /// What the raised drink does, as many lines as it takes, and its quote over it.
    private let blurb = SKNode()
    private let comment = SKLabelNode()
    private let clock = SKLabelNode(fontNamed: Futuristic.fontName)
    /// Each bottle's name in its frame, lit gold on the raised one.
    private var names: [SKNode] = []
    /// Each bottle's white outline, shown on the raised one.
    private var outlines: [SKNode] = []
    private let onDrink: (Greateraid) -> Void

    /// `player_drinkchoice` in the picker's look, its frames played very slowly, on its bench;
    /// its art pixels this many points, on the UI panel's slider.
    static let drinkerScaleKey = "ui.pick.drinkerScale"
    static var drinkerScale: CGFloat { UserDefaults.standard.object(forKey: drinkerScaleKey).map { CGFloat(($0 as? Double) ?? 3.75) } ?? 3.75 }
    static let drinkerFrameSeconds = 0.5
    /// Picked: `player_drink` this many times through at the same pace, then `player_transform`
    /// at 15 a second, raised `transformLift` art pixels off the chair, and only then on; the bottles and the words falling away meanwhile.
    static let drinkLoops = 2
    static let transformFramesPerSecond = 15.0
    static let transformLift: CGFloat = 8
    /// `player_drink`'s head tipped back, degrees, frame by frame.
    static let drinkHeadTilts: [CGFloat] = [25, 35]
    /// The drinking arm, its hand and the bottle (its three greys), drawn again over the hood.
    static let drinkOverHood: Set<RGB> = [0x793A80, 0xBC4A9B, 0x4A5462, 0x6D758D, 0x8B93AF]
    static let fallSeconds = 0.5
    private var finishing = false
    /// Picked and playing the drink out: the clock's stopped and no other pick lands.
    var isFinishing: Bool { finishing }
    private var drinkerNode: SKSpriteNode?
    private var bottleNodes: [SKNode] = []
    private let drinking: [SKTexture]
    private let transforming: [SKTexture]
    /// The sheet's feet, eight pixels up its 48.
    static let drinkerFeet: CGFloat = 8.0 / 48

    /// The column, in the HUD's points: the title's middle down from the top and its cap height;
    /// the drinker's feet; rule 6 under them and its scale; the quote's size; the description's
    /// top, its room down and across, its sizes largest first and its lines' spacing; the
    /// bottles' height and the name frames' scale and lettering, two lines at most.
    static let drinkerFeetY: CGFloat = 40
    static let ruleY: CGFloat = 32
    static let ruleScale: CGFloat = 0.5
    static let commentY: CGFloat = 20
    static let commentSize: CGFloat = 9
    static let commentAlpha: CGFloat = 0.8
    static let blurbTop: CGFloat = 10
    static let blurbRoom = CGSize(width: 520, height: 46)
    static let blurbSizes: [CGFloat] = [14, 13, 12, 11, 10]
    static let lineShare: CGFloat = 1.15
    /// The bottles' height, how far their bottoms sit under the screen's edge, and their name
    /// frames', which may sit over the bottle's top.
    static let bottleHeight: CGFloat = 184
    static let bottleSink: CGFloat = 70
    static let nameScale: CGFloat = 0.9
    static let nameSizes: [CGFloat] = [18, 17, 16, 15, 14, 13, 12, 11, 10]
    static let nameOverBottle: CGFloat = 26

    /// `timed` shows the seconds left, for a networked pick; `drinker`, the frames of the one picking.
    init(halfWidth: CGFloat, halfHeight: CGFloat, offers: [Greateraid], drinks: Drinks, colour: SKColor, timed: Bool = false,
         drinker: [SKTexture] = [], bench: SKTexture? = nil, drinking: [SKTexture] = [], transforming: [SKTexture] = [],
         onDrink: @escaping (Greateraid) -> Void) {
        self.offers = offers
        self.drinks = drinks
        self.onDrink = onDrink
        self.drinking = drinking
        self.transforming = transforming
        super.init(halfWidth: halfWidth, halfHeight: halfHeight, kind: .pick)
        addCornerBanner("Greateraid")
        if timed {
            // The seconds, top right, in the menus' face.
            clock.fontColor = Futuristic.lineColour
            clock.verticalAlignmentMode = .center
            clock.position = CGPoint(x: halfWidth - 40, y: halfHeight - 30)
            addChild(clock)
            showSeconds(Series.pickSeconds)
        }
        // The bench, its own sheet, under the one on it.
        let feet = CGPoint(x: 0, y: PickScreen.drinkerFeetY)
        if let bench {
            let seat = SKSpriteNode(texture: bench)
            seat.size = bench.size().scaled(by: PickScreen.drinkerScale)
            seat.anchorPoint = CGPoint(x: 0.5, y: PickScreen.drinkerFeet)
            seat.position = feet
            seat.zPosition = 0.4
            addChild(seat)
        }
        if let first = drinker.first {
            let figure = SKSpriteNode(texture: first)
            figure.size = first.size().scaled(by: PickScreen.drinkerScale)
            figure.anchorPoint = CGPoint(x: 0.5, y: PickScreen.drinkerFeet)
            figure.position = feet
            figure.zPosition = 0.5
            figure.run(.repeatForever(.animate(with: drinker, timePerFrame: PickScreen.drinkerFrameSeconds)))
            addChild(figure)
            drinkerNode = figure
        }
        let rule = Futuristic.sprite("rule6", scale: PickScreen.ruleScale)
        rule.position = CGPoint(x: 0, y: PickScreen.ruleY)
        addChild(rule)
        comment.alpha = PickScreen.commentAlpha
        comment.verticalAlignmentMode = .center
        comment.position = CGPoint(x: 0, y: PickScreen.commentY)
        addChild(comment)
        addChild(blurb)

        let spacing = min(halfWidth * 0.55, 200)
        for (index, offer) in offers.enumerated() {
            let x = (CGFloat(index) - 1) * spacing
            let bottle = PickScreen.bottle(for: offer, colour: colour, height: PickScreen.bottleHeight * tuned(.buttons))
            // Leaning between 5 and 20 degrees, either way; the bottom clipped by the screen's edge.
            let lean = CGFloat(5 + Int.random(in: 0...15)) * .pi / 180 * (Bool.random() ? 1 : -1)
            bottle.zRotation = lean
            bottle.position = CGPoint(x: x, y: -halfHeight - PickScreen.bottleSink)
            bottle.zPosition = 5
            addChild(bottle)
            bottleNodes.append(bottle)
            outlines.append(PickScreen.outline(of: bottle, width: 4 * tuned(.buttons)))
            // Its name in frame 12 over it.
            let name = nameFrame(offer.name)
            name.position = CGPoint(x: x, y: bottle.position.y + bottle.size.height - PickScreen.nameOverBottle + name.calculateAccumulatedFrame().height / 2)
            name.zPosition = 5
            addChild(name)
            names.append(name)
            let hit = CGRect(x: x - spacing / 2 + 6, y: -halfHeight, width: spacing - 12, height: name.position.y + halfHeight + 30)
            addChoice(bottle, hit: hit) { [weak self] in
                self?.finish(with: offer)
            }
        }
        moved()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A drink's name in frame 12, in the menus' face: on one line if it fits the frame's face,
    /// else on two, split at a space where the longer line is shortest ("Quake-Up" over "Coffee"),
    /// at the largest size whose lines fit across and stack within it.
    private func nameFrame(_ text: String) -> SKNode {
        let node = SKNode()
        let frame = Futuristic.sprite("12", scale: PickScreen.nameScale * tuned(.buttons))
        node.addChild(frame)
        let faceShare = Futuristic.faces["12"] ?? CGPoint(x: 0.5, y: 0.5)
        let face = CGSize(width: frame.size.width * PickScreen.nameFaceShare.width, height: frame.size.height * PickScreen.nameFaceShare.height)
        let middle = CGPoint(x: (faceShare.x - 0.5) * frame.size.width, y: (0.5 - faceShare.y) * frame.size.height)
        func width(_ line: String, _ size: CGFloat) -> CGFloat {
            let font = UIFont(name: Futuristic.fontName, size: Futuristic.fontSize(size)) ?? .systemFont(ofSize: size)
            return (line as NSString).size(withAttributes: [.font: font]).width
        }
        let words = text.split(separator: " ").map(String.init)
        var chosen: (lines: [String], size: CGFloat) = ([text], PickScreen.nameSizes.last!)
        for size in PickScreen.nameSizes {
            if width(text, size) <= face.width { chosen = ([text], size); break }
            let splits = (1..<max(words.count, 1)).map { cut in
                [words[..<cut].joined(separator: " "), words[cut...].joined(separator: " ")]
            }
            guard let best = splits.min(by: { max(width($0[0], size), width($0[1], size)) < max(width($1[0], size), width($1[1], size)) }) else { continue }
            chosen = (best, size)
            let lineHeight = Futuristic.fontSize(size) * PickScreen.lineShare
            if best.allSatisfy({ width($0, size) <= face.width }), lineHeight * 2 <= face.height { break }
        }
        let lineHeight = Futuristic.fontSize(chosen.size) * PickScreen.lineShare
        for (index, line) in chosen.lines.enumerated() {
            let label = Futuristic.label(line, size: chosen.size)
            label.position = CGPoint(x: middle.x, y: middle.y + (CGFloat(chosen.lines.count - 1) / 2 - CGFloat(index)) * lineHeight)
            node.addChild(label)
        }
        return node
    }
    /// Frame 12's face as a share of the picture, inside its bars.
    static let nameFaceShare = CGSize(width: 0.8, height: 0.5)

    /// Picked: the bottles and the words fall away; the drinker drinks it, twice through, then
    /// changes a little off the chair; then the pick goes on. Once.
    private func finish(with offer: Greateraid) {
        guard !finishing else { return }
        finishing = true
        let fall = SKAction.group([.moveBy(x: 0, y: -halfHeight * 1.5, duration: PickScreen.fallSeconds), .fadeOut(withDuration: PickScreen.fallSeconds)])
        fall.timingMode = .easeIn
        for node in bottleNodes + names + [blurb, comment] { node.run(fall) }
        guard let figure = drinkerNode, !drinking.isEmpty else { return onDrink(offer) }
        figure.removeAllActions()
        var steps: [SKAction] = [.repeat(.animate(with: drinking, timePerFrame: PickScreen.drinkerFrameSeconds), count: PickScreen.drinkLoops)]
        if !transforming.isEmpty {
            let lift = PickScreen.transformLift * PickScreen.drinkerScale
            steps.append(.run { figure.position.y += lift })
            steps.append(.animate(with: transforming, timePerFrame: 1 / PickScreen.transformFramesPerSecond))
        }
        steps.append(.run { [weak self] in self?.onDrink(offer) })
        figure.run(.sequence(steps))
    }

    override var tapFiresAtOnce: Bool { false }

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
        clock.text = "\(max(seconds, 0))"
        clock.fontSize = Futuristic.fontSize(20 * tuned(.text))
    }

    override func moved() {
        guard choices.indices.contains(cursor) else { return }
        let offer = offers[cursor]
        for (index, outline) in outlines.enumerated() { outline.isHidden = index != cursor }
        for (index, name) in names.enumerated() {
            Screen.colour(name, index == cursor ? Futuristic.litColour : Futuristic.lineColour)
        }
        // In the system's italic: none of the menus' faces has one.
        comment.attributedText = NSAttributedString(string: "\u{201C}\(offer.comment)\u{201D}", attributes: [
            .font: UIFont.italicSystemFont(ofSize: PickScreen.commentSize * tuned(.text)),
            .foregroundColor: Futuristic.lineColour,
        ])
        let text = drinks.level(of: offer) == 0 ? offer.blurbs.first : offer.blurbs.second
        layBlurb((drinks.isSecondSip(offer) ? "Second sip: " : "") + text)
    }

    /// What the drink does in the menus' face, in as many lines as it needs, at the largest of its
    /// sizes whose lines all fit across and stack within its room.
    private func layBlurb(_ text: String) {
        blurb.removeAllChildren()
        let room = CGSize(width: min(PickScreen.blurbRoom.width, halfWidth * 1.6), height: PickScreen.blurbRoom.height)
        func wrapped(_ size: CGFloat) -> [String] {
            let font = UIFont(name: Futuristic.fontName, size: Futuristic.fontSize(size)) ?? .systemFont(ofSize: size)
            func fits(_ line: String) -> Bool { (line as NSString).size(withAttributes: [.font: font]).width <= room.width }
            var lines: [String] = []
            var line = ""
            for word in text.split(separator: " ").map(String.init) {
                let tried = line.isEmpty ? word : line + " " + word
                if line.isEmpty || fits(tried) { line = tried } else { lines.append(line); line = word }
            }
            if !line.isEmpty { lines.append(line) }
            return lines
        }
        var chosen: (lines: [String], size: CGFloat) = ([text], PickScreen.blurbSizes.last! * tuned(.text))
        for base in PickScreen.blurbSizes {
            let size = base * tuned(.text)
            chosen = (wrapped(size), size)
            if CGFloat(chosen.lines.count) * Futuristic.fontSize(size) * PickScreen.lineShare <= room.height { break }
        }
        let lineHeight = Futuristic.fontSize(chosen.size) * PickScreen.lineShare
        for (index, line) in chosen.lines.enumerated() {
            let label = Futuristic.label(line, size: chosen.size)
            label.position = CGPoint(x: 0, y: PickScreen.blurbTop - lineHeight / 2 - CGFloat(index) * lineHeight)
            blurb.addChild(label)
        }
    }

    /// The bottle, the user's vector from the catalog, `height` points tall and anchored at its
    /// bottom so that runs off the screen: blue for a booster, gold for a biomorph or
    /// Bio-Boba.
    static func bottle(for drink: Greateraid, colour: SKColor, height: CGFloat) -> SKSpriteNode {
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

/// The other side is drinking: nothing to pick, only the clock to watch. As the pick is drawn:
/// Greateraid in FLO lettering, who's drinking in the menus' face, and the seconds in ring 8.
final class WaitScreen: Screen {
    private let clock = SKLabelNode(fontNamed: Futuristic.fontName)
    static let whoY: CGFloat = 30
    static let whoSize: CGFloat = 18
    static let ringY: CGFloat = -40
    static let ringSide: CGFloat = 70

    init(halfWidth: CGFloat, halfHeight: CGFloat, who: String) {
        super.init(halfWidth: halfWidth, halfHeight: halfHeight, kind: .pick)
        addCornerBanner("Greateraid")
        let drinking = Futuristic.label("\(who) is drinking", size: WaitScreen.whoSize * tuned(.text))
        drinking.position = CGPoint(x: 0, y: WaitScreen.whoY)
        addChild(drinking)
        let ring = Futuristic.sprite("ring8", scale: 1)
        ring.size = CGSize(width: WaitScreen.ringSide, height: WaitScreen.ringSide)
        ring.position = CGPoint(x: 0, y: WaitScreen.ringY)
        addChild(ring)
        clock.fontColor = Futuristic.lineColour
        clock.verticalAlignmentMode = .center
        clock.position = ring.position
        addChild(clock)
        showSeconds(Series.pickSeconds)
    }

    required init?(coder: NSCoder) { fatalError() }

    func showSeconds(_ seconds: Int) {
        clock.text = "\(max(seconds, 0))"
        clock.fontSize = Futuristic.fontSize(24 * tuned(.text))
    }
}

/// Who won, the two ways on and the final score between them. `again` is NEW MATCH offline and
/// REMATCH online, where it waits for the other side to press theirs.
final class WinScreen: Screen {
    private let waiting = SKSpriteNode()
    /// The winner and their pose, drawn by the SwiftUI layer under this one (`WinStage`).
    let figure: WinFigure

    /// The column, top to bottom, in the HUD's points from the middle: the halo's ring (the
    /// winner stands on the projector under it, `figurePixel` points an art pixel), the winner's
    /// hood in FLO lettering, and the two options side by side in frame 4, the final score in box 2
    /// between them.
    static let ringY: CGFloat = 20
    static let figurePixel: CGFloat = 2
    static let nameY: CGFloat = -40
    static let nameHeight: CGFloat = 26
    static let optionsY: CGFloat = -105
    static let optionScale: CGFloat = 0.75
    static let optionTextSize: CGFloat = 10
    static let optionGap: CGFloat = 6
    static let scoreScale: CGFloat = 0.4
    static let scoreTextSize: CGFloat = 16

    /// `score` is each side's, player one's first, as the match ended.
    init(halfWidth: CGFloat, halfHeight: CGFloat, winner: String, player: Int, score: [Int], again: String,
         onAgain: @escaping () -> Void, onTitle: @escaping () -> Void) {
        figure = WinFigure(player: player, pose: .taunt)
        super.init(halfWidth: halfWidth, halfHeight: halfHeight, kind: .win)
        let name = FloText.node("\(winner) Wins", height: WinScreen.nameHeight)
        name.position = CGPoint(x: 0, y: WinScreen.nameY)
        addChild(name)
        let width = Futuristic.sprite("4", scale: WinScreen.optionScale).size.width
        let scoreWidth = Futuristic.sprite("box2", scale: WinScreen.scoreScale).size.width
        addPlate(score.map(String.init).joined(separator: " - "), frame: "box2", scale: WinScreen.scoreScale,
                 textSize: WinScreen.scoreTextSize, at: CGPoint(x: 0, y: WinScreen.optionsY))
        let across = scoreWidth / 2 + WinScreen.optionGap + width / 2
        // The left one turned round, its lead out to the right.
        addFramed(again, frame: "4", scale: WinScreen.optionScale, mirroredX: true, textSize: WinScreen.optionTextSize,
                  at: CGPoint(x: -across, y: WinScreen.optionsY), action: onAgain)
        addFramed("TITLE", frame: "4", scale: WinScreen.optionScale, textSize: WinScreen.optionTextSize,
                  at: CGPoint(x: across, y: WinScreen.optionsY), sound: .menuBack, action: onTitle)
        waiting.position = CGPoint(x: 0, y: WinScreen.optionsY - Futuristic.sprite("4", scale: WinScreen.optionScale).size.height / 2 - 14)
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
    /// Each stage: Futuristic_UI's box1, in the menus' blue or gold when raised.
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
    /// The window behind the stages, as the ball cam is drawn: a trapezoid, its bottom 0.84 of its
    /// top across, see-through; showing the raised stage's whole-stage shot, or static.
    private let window = SKSpriteNode()
    private var windowSparks: [(node: SKSpriteNode, edge: Int, share: CGFloat)] = []
    static let windowHeightShare: CGFloat = 1.3
    static let windowAspect: CGFloat = 1.09
    static let windowOpacity: CGFloat = 0.5
    static let windowBottomShare: CGFloat = BallCamScene.bottomWidth / BallCamScene.topWidth
    /// Which stage's raised, told on a change: the first local voter's, or the coin flip's light.
    var onRaised: ((Int?) -> Void)? {
        didSet {
            raisedTold = nil
            tellRaised()
        }
    }
    private var raisedTold: Int??
    /// Static: a few frames of grey noise, run round.
    private static let staticFrames: [SKTexture] = (0..<6).map { _ in
        let width = 64, height = 40
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for pixel in 0..<(width * height) {
            let grey = UInt8.random(in: 20...200)
            bytes[pixel * 4] = grey
            bytes[pixel * 4 + 1] = grey
            bytes[pixel * 4 + 2] = grey
        }
        let texture = SKTexture(data: Data(bytes), size: CGSize(width: width, height: height))
        texture.filteringMode = .nearest
        return texture
    }

    /// `onPick` gets the voter and the stage's place in the row.
    init(halfWidth: CGFloat, halfHeight: CGFloat, stages: [String], voters: [Int], localVoters: [Int], colours: [SKColor],
         heading: String?, start: Int, onPick: @escaping (Int, Int) -> Void) {
        self.voters = voters
        self.localVoters = localVoters
        self.colours = colours
        self.onPick = onPick
        super.init(halfWidth: halfWidth, halfHeight: halfHeight, kind: .stageSelect)
        // The title lettered as FLO is, at the bottom.
        let title = FloText.node("STAGE SELECT", height: StageSelectScreen.titleHeight * tuned(.titles))
        title.position = CGPoint(x: 0, y: -halfHeight * StageSelectScreen.titleDrop)
        addChild(title)
        // The window behind the stages, warped to the ball cam's trapezoid.
        let windowHeight = halfHeight * StageSelectScreen.windowHeightShare
        window.size = CGSize(width: windowHeight * StageSelectScreen.windowAspect, height: windowHeight)
        window.alpha = StageSelectScreen.windowOpacity
        window.zPosition = -10
        let inset = Float((1 - StageSelectScreen.windowBottomShare) / 2)
        window.warpGeometry = SKWarpGeometryGrid(columns: 1, rows: 1, sourcePositions: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)],
                                                 destinationPositions: [SIMD2(inset, 0), SIMD2(1 - inset, 0), SIMD2(0, 1), SIMD2(1, 1)])
        addChild(window)
        showWindow(nil)
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
    /// STAGE SELECT's cap height, in points, and its middle down from the screen's, a share of half its height.
    static let titleHeight: CGFloat = 15
    static let titleDrop: CGFloat = 0.85

    /// The window showing a stage's shot, as tall as the shot is for the window's width (at most
    /// its full height), or static without one.
    func showWindow(_ shot: SKTexture?) {
        window.removeAction(forKey: "static")
        let fullHeight = halfHeight * StageSelectScreen.windowHeightShare
        let width = fullHeight * StageSelectScreen.windowAspect
        if let shot {
            window.texture = shot
            let size = shot.size()
            window.size = CGSize(width: width, height: min(fullHeight, width * size.height / max(size.width, 1)))
            laySparks()
        } else {
            window.size = CGSize(width: width, height: fullHeight)
            laySparks()
            window.run(.repeatForever(.animate(with: StageSelectScreen.staticFrames, timePerFrame: 1.0 / 20)), withKey: "static")
        }
    }

    /// Flashes round the window's edges, as round the ball cam's, each on its own frame.
    func frameWindow(with frames: [SKTexture]) {
        guard !frames.isEmpty else { return }
        windowSparks.forEach { $0.node.removeFromParent() }
        windowSparks = []
        let perEdge = [9, 4, 8, 4]
        for (edge, sparks) in perEdge.enumerated() {
            for step in 0..<sparks {
                let spark = SKSpriteNode(texture: frames[0])
                spark.setScale(BackboardTuning.size)
                spark.alpha = StageSelectScreen.windowOpacity
                spark.zPosition = window.zPosition + 1
                let start = (edge * 5 + step * 7) % frames.count
                spark.run(.repeatForever(.animate(with: Array(frames[start...]) + Array(frames[..<start]), timePerFrame: 1.0 / 24)))
                addChild(spark)
                windowSparks.append((spark, edge, CGFloat(step) / CGFloat(sparks)))
            }
        }
        laySparks()
    }

    /// The flashes round the window as it's sized now.
    private func laySparks() {
        // Round the trapezoid clockwise from the top left.
        let half = CGSize(width: window.size.width / 2, height: window.size.height / 2)
        let bottomHalf = half.width * StageSelectScreen.windowBottomShare
        let ring = [CGPoint(x: -half.width, y: half.height), CGPoint(x: half.width, y: half.height),
                    CGPoint(x: bottomHalf, y: -half.height), CGPoint(x: -bottomHalf, y: -half.height)]
        for spark in windowSparks {
            let from = ring[spark.edge], to = ring[(spark.edge + 1) % 4]
            spark.node.position = CGPoint(x: window.position.x + from.x + (to.x - from.x) * spark.share,
                                          y: window.position.y + from.y + (to.y - from.y) * spark.share)
        }
    }

    private func tellRaised() {
        let raised = flipLit ?? localVoters.first.flatMap { picks[$0] ?? cursors[$0] }
        guard raisedTold != .some(raised) else { return }
        raisedTold = .some(raised)
        onRaised?(raised)
    }
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
        defer { tellRaised() }
        let raised: Set<Int> = flipLit.map { [$0] } ?? Set(voters.compactMap { picks[$0] ?? cursors[$0] })
        for index in tiles.indices {
            let lit = raised.contains(index)
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
        // The settings' SF Symbol gear, outlined, drawn into a picture in white to be coloured (a
        // symbol handed to SpriteKit as it is comes out black).
        let gear = SKSpriteNode(texture: UIImage(systemName: "gearshape", withConfiguration: UIImage.SymbolConfiguration(pointSize: 64, weight: .regular))
            .map { symbol in
                let white = symbol.withTintColor(.white, renderingMode: .alwaysOriginal)
                return SKTexture(image: UIGraphicsImageRenderer(size: white.size).image { _ in white.draw(at: .zero) })
            })
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


    required init?(coder: NSCoder) { fatalError() }
}

extension CGSize {
    func scaled(by factor: CGFloat) -> CGSize { CGSize(width: width * factor, height: height * factor) }
}
