import EsperSim
import SpriteKit

/// The on-screen controls, laid out in screen points from the centre. The left half is a
/// floating stick: the thumb's first touch is the centre. The right half holds three
/// buttons. Shoot and throw read the drag away from the touch-down point as the flick.
final class TouchControls: SKNode {
    static let stickRadius = 40.0
    static let flickRadius = 32.0

    /// A round button: its circle, invisible, for the touch; one of Futuristic_UI's rings over
    /// it, in the menus' blue, gold while it's held, turning a full circle as it's pressed; and
    /// its name in the menus' lettering inside it.
    private struct Button {
        let node: SKShapeNode
        let ring: SKSpriteNode
        let label: SKLabelNode
        /// Drawn instead of the name where the name has an icon (`icons`).
        let icon: SKSpriteNode
        var text: String
        let radius: CGFloat
    }
    /// The names shown as icons: the strike button's slash its own icon, Volta Cola's bolt a bolt.
    static let icons: [String: String] = ["SLASH": "StrikeIcon", "BOLT": "BoltIcon"]
    /// An icon's size against the button's diameter.
    static let iconShare: CGFloat = 0.6
    private static func iconTexture(_ name: String) -> SKTexture? {
        if let made = iconTextures[name] { return made }
        guard let source = UIImage(named: name) else { return nil }
        let side: CGFloat = 192
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            source.withTintColor(.white).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        let made = SKTexture(image: image)
        iconTextures[name] = made
        return made
    }
    nonisolated(unsafe) private static var iconTextures: [String: SKTexture] = [:]
    /// The button's name, or its icon in its place.
    private static func show(_ text: String, on button: Button) {
        button.label.text = text
        fit(button.label, inside: button.radius)
        let texture = icons[text].flatMap(iconTexture)
        button.icon.texture = texture
        button.icon.isHidden = texture == nil
        button.label.isHidden = texture != nil
    }
    /// A name shrunk to fit inside its ring: no wider than this share of the button's diameter.
    static let labelShare: CGFloat = 0.72
    private static func fit(_ label: SKLabelNode, inside radius: CGFloat) {
        label.setScale(1)
        label.setScale(min(1, radius * 2 * labelShare / max(label.frame.width, 1)))
    }
    /// A ring's turn on a press, in seconds.
    static let ringSpinSeconds = 0.35
    /// A ring's diameter over the button's.
    static let ringShare: CGFloat = 1.1
    private static let line = SKColor(rgb: Futuristic.lineRGB)
    private static let lit = SKColor(rgb: EsperPalette.gold.light)
    private var buttonSets: [(inout PlayerInput, Bool, Vec2) -> Void] = []

    /// The touch pad's tuned sizes (`UITuning`, TOUCH).
    private static var scale: CGFloat { UITuning.shared.scale(.touch, .buttons) }
    private static var textScale: CGFloat { UITuning.shared.scale(.touch, .text) }

    private var buttons: [Button] = []
    /// The stick: ring 3 its base and ring 7 the knob that moves inside it, both in the menus'
    /// blue. It reads one of eight ways, the knob shown on it.
    private let stickBase: SKNode = {
        let base = SKNode()
        let ring = Futuristic.sprite("ring3", scale: 1)
        ring.size = CGSize(width: stickRadius * 2, height: stickRadius * 2)
        base.addChild(ring)
        return base
    }()
    /// The stick on the nearest of its eight ways, its length kept.
    static func eightWays(_ stick: Vec2) -> Vec2 {
        let length = stick.length
        guard length > 0 else { return .zero }
        let eighth = Double.pi / 4
        let angle = (atan2(stick.y, stick.x) / eighth).rounded() * eighth
        return Vec2(x: cos(angle) * length, y: sin(angle) * length)
    }
    private let stickKnob: SKSpriteNode = {
        let knob = Futuristic.sprite("ring7", scale: 1)
        knob.size = CGSize(width: stickKnobSize, height: stickKnobSize)
        return knob
    }()
    private static let stickKnobSize: CGFloat = 32
    /// The corner switches: an invisible rect for the touch, a black plate on it, plum when on.
    private let resetButton = TouchControls.cornerButton("RESET")
    private let hitboxButton = TouchControls.cornerButton("HITBOX")
    private let aiButton = TouchControls.cornerButton("AI")
    private let wallsButton = TouchControls.cornerButton("WALLS")
    private let mapButton = TouchControls.cornerButton("MAP")
    /// Pause, offline: frame 1 small, a pause sign in its face, in the top right corner over the FLO meter.
    private let pauseButton = TouchControls.pauseIcon()
    static let pauseScale: CGFloat = 0.3

    private static let cornerSize = CGSize(width: 50, height: 22)

    private static func cornerButton(_ text: String) -> SKShapeNode {
        let size = cornerSize.scaled(by: scale)
        let node = SKShapeNode(rectOf: size, cornerRadius: 4)
        node.fillColor = .clear
        node.strokeColor = .clear
        let plate = UIPiece.buttonBlack.node(size: size, corners: scale * 0.5)
        plate.name = "plate"
        plate.zPosition = -1
        node.addChild(plate)
        let label = TitleText.node(text, size: 9 * textScale)
        label.position = CGPoint(x: 0, y: UIPiece.buttonBlack.faceRise * scale * 0.5)
        node.addChild(label)
        return node
    }

    /// Frame 1 at `pauseScale` of the menus' size, in their blue, two bars in its face.
    private static func pauseIcon() -> SKSpriteNode {
        let image = Futuristic.image("1")
        let frame = SKSpriteNode(texture: SKTexture(image: image))
        frame.size = CGSize(width: image.size.width * image.scale * Futuristic.pointsPerPixel * pauseScale,
                            height: image.size.height * image.scale * Futuristic.pointsPerPixel * pauseScale)
        frame.color = line
        frame.colorBlendFactor = 1
        let face = Futuristic.faces["1"] ?? CGPoint(x: 0.5, y: 0.5)
        let middle = CGPoint(x: (face.x - 0.5) * frame.size.width, y: (0.5 - face.y) * frame.size.height)
        let bar = CGSize(width: frame.size.height * 0.1, height: frame.size.height * 0.36)
        for side: CGFloat in [-1, 1] {
            let piece = SKSpriteNode(color: line, size: bar)
            piece.position = CGPoint(x: middle.x + side * bar.width, y: middle.y)
            frame.addChild(piece)
        }
        return frame
    }

    /// The corner row: pause at the right, under `top`, the switches to its left.
    func placeCornerRow(top: CGFloat, right: CGFloat) {
        pauseButton.position = CGPoint(x: right - pauseButton.size.width / 2, y: top - pauseButton.size.height / 2)
        let k = TouchControls.scale
        let step = (TouchControls.cornerSize.width + 6) * k
        let rowY = top - TouchControls.cornerSize.height * k / 2
        let start = pauseButton.position.x - pauseButton.size.width / 2 - 6 - TouchControls.cornerSize.width * k / 2
        for (index, button) in [resetButton, hitboxButton, aiButton].enumerated() {
            button.position = CGPoint(x: start - CGFloat(index) * step, y: rowY)
        }
        wallsButton.position = CGPoint(x: hitboxButton.position.x, y: hitboxButton.position.y - (TouchControls.cornerSize.height + 6) * k)
        mapButton.position = CGPoint(x: aiButton.position.x, y: wallsButton.position.y)
    }
    /// Where pause is, in this node's space.
    var pauseFrame: CGRect { pauseButton.frame }

    /// A corner switch on or off: plum when on, black when off.
    private static func light(_ button: SKShapeNode, on: Bool) {
        guard let plate = button.childNode(withName: "plate") as? SKSpriteNode else { return }
        (on ? UIPiece.buttonPlum : UIPiece.buttonBlack).fit(plate, to: cornerSize.scaled(by: scale), corners: scale * 0.5)
    }
    /// The PAUSE button, offline only.
    var onPause: (() -> Void)?
    /// Called when the corner button is tapped.
    var onReset: (() -> Void)?
    /// The HITBOX toggle beside it: whether the sim's boxes are drawn, and who to tell.
    var showHitboxes = false { didSet { TouchControls.light(hitboxButton, on: showHitboxes) } }
    /// The WALLS toggle under it: the stage's solids drawn over the world.
    var showWalls = false { didSet { TouchControls.light(wallsButton, on: showWalls) } }
    var onToggleWalls: ((Bool) -> Void)?
    /// The MAP button beside it: the map editor, on a stage that has one, offline.
    var mapOpen = false { didSet { TouchControls.light(mapButton, on: mapOpen) } }
    var mapAvailable = false { didSet { refreshMapButton() } }
    var onMap: (() -> Void)?
    private func refreshMapButton() { mapButton.isHidden = !DebugUI.enabled || online || !mapAvailable }
    var onToggleHitboxes: ((Bool) -> Void)?
    /// The AI switch beside that: whether the computer plays the other side.
    var aiOn = true { didSet { TouchControls.light(aiButton, on: aiOn) } }
    var onToggleAI: ((Bool) -> Void)?
    private var pickers: [SegmentedPicker] = []
    private let pickerOrigin: CGPoint
    private var sliders: [Slider] = []
    /// The debug pickers, top left, and the sliders, top middle, each under a tab that folds
    /// them away and opens them again; kept between launches.
    private let pickerTab = TouchControls.benchTab()
    private let sliderTab = TouchControls.benchTab()
    static let pickersOpenKey = "debug.bench.pickersOpen", slidersOpenKey = "debug.bench.slidersOpen"
    private var pickersOpen = UserDefaults.standard.bool(forKey: TouchControls.pickersOpenKey) {
        didSet { UserDefaults.standard.set(pickersOpen, forKey: TouchControls.pickersOpenKey); refreshBenches() }
    }
    private var slidersOpen = UserDefaults.standard.bool(forKey: TouchControls.slidersOpenKey) {
        didSet { UserDefaults.standard.set(slidersOpen, forKey: TouchControls.slidersOpenKey); refreshBenches() }
    }
    private var online = false
    /// Capture Mode: the benches gone, tabs and all.
    var capturing = false { didSet { if capturing != oldValue { refreshBenches() } } }
    /// A bench opened or folded: what sits under the pickers moves with them.
    var onBenchesChanged: (() -> Void)?
    static let benchTabSize = CGSize(width: 76, height: 16)
    /// The first slider's row under the slider tab.
    private static let slidersTop: CGFloat = 50

    private static func benchTab() -> SKShapeNode {
        let tab = SKShapeNode(rectOf: benchTabSize, cornerRadius: 4)
        tab.fillColor = SKColor(white: 0, alpha: 0.6)
        tab.strokeColor = SKColor(rgb: Futuristic.lineRGB)
        tab.lineWidth = 1
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.name = "label"
        label.fontSize = 9
        label.fontColor = SKColor(rgb: Futuristic.lineRGB)
        label.verticalAlignmentMode = .center
        tab.addChild(label)
        return tab
    }

    /// The benches shown, folded or open, and what's in them shown with them.
    private func refreshBenches() {
        (pickerTab.childNode(withName: "label") as? SKLabelNode)?.text = "PICKERS " + (pickersOpen ? "▾" : "▸")
        (sliderTab.childNode(withName: "label") as? SKLabelNode)?.text = "SLIDERS " + (slidersOpen ? "▾" : "▸")
        let away = online || capturing
        pickerTab.isHidden = away || pickers.isEmpty
        sliderTab.isHidden = away || sliders.isEmpty
        for picker in pickers { picker.isHidden = away || !pickersOpen }
        for slider in sliders { slider.isHidden = away || !slidersOpen }
        onBenchesChanged?()
    }
    private var sliderTouches: [UITouch: Slider] = [:]
    private let topCentre: CGPoint
    private var stickTouch: UITouch?
    private var stickCenter = CGPoint.zero
    private var buttonTouches: [UITouch: (index: Int, origin: CGPoint)] = [:]

    private(set) var input = PlayerInput.idle
    /// Buttons that went down since the last sample, so a tap shorter than a frame still lands.
    private var latched = PlayerInput.idle

    static let padding: CGFloat = 12

    /// `halfWidth` and `halfHeight` are half the view in points; `insets` is the safe area.
    /// Everything keeps `padding` inside the safe area.
    init(halfWidth: CGFloat, halfHeight: CGFloat, insets: UIEdgeInsets) {
        let left = -halfWidth + insets.left + TouchControls.padding
        let right = halfWidth - insets.right - TouchControls.padding
        let top = halfHeight - insets.top - TouchControls.padding
        let bottom = -halfHeight + insets.bottom + TouchControls.padding
        safeBounds = CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
        pickerOrigin = CGPoint(x: left, y: top)
        topCentre = CGPoint(x: 0, y: top)
        super.init()
        zPosition = 100

        stickBase.alpha = 0.55
        stickBase.isHidden = true
        stickKnob.alpha = 0.85
        stickKnob.isHidden = true
        addChild(stickBase)
        addChild(stickKnob)

        _ = Onomatopoeia.registered
        // Strike (shoot) and Guard (throw) side by side, Strike on the left as the keyboard's J
        // and the pad's square; jump below and between them, all at the tuned size: jump and
        // throw in ring6, shoot in ring4.
        let k = TouchControls.scale
        let jump = makeButton("JUMP", ring: "ring6", radius: 30 * k, at: CGPoint(x: right - 76 * k, y: bottom + 26 * k)) { input, down, _ in
            input.jump = down
        }
        let shoot = makeButton("SHOOT", ring: "ring4", radius: 30 * k, at: CGPoint(x: right - 114 * k, y: bottom + 84 * k)) { input, down, aim in
            input.shoot = down
            if down { input.aim = aim }
        }
        let throwButton = makeButton("THROW", ring: "ring6", radius: 24 * k, at: CGPoint(x: right - 38 * k, y: bottom + 84 * k)) { input, down, aim in
            input.throwBall = down
            if down { input.aim = aim }
        }
        buttons = [jump.button, shoot.button, throwButton.button]
        buttonSets = [jump.set, shoot.set, throwButton.set]
        homes = buttons.map(\.node.position)
        // The shield's: a capsule round the throw (snatch) button, a small gap off its ring, shown
        // only on defence; it goes where the throw button goes, at its size.
        shieldButton.isHidden = true
        addChild(shieldButton)
        applyPlaces()

        pickerTab.position = CGPoint(x: left + TouchControls.benchTabSize.width / 2, y: top - TouchControls.benchTabSize.height / 2)
        sliderTab.position = CGPoint(x: 0, y: top - 30)
        addChild(pickerTab)
        addChild(sliderTab)
        refreshBenches()
        // The corner row along the top, right to left, till the FLO meter's laid out and it's put under it.
        for button in [resetButton, hitboxButton, aiButton, wallsButton, mapButton] as [SKNode] + [pauseButton] { addChild(button) }
        placeCornerRow(top: top, right: right)
        TouchControls.light(aiButton, on: aiOn)
        // The switches for working on the game, in a debug build only.
        for button in [hitboxButton, wallsButton, aiButton] { button.isHidden = !DebugUI.enabled }
        refreshMapButton()
    }

    /// Online there's no reset, no pause, no computer and no tuning: only the pad and HITBOX.
    func setOnline(_ online: Bool) {
        resetButton.isHidden = online
        pauseButton.isHidden = online
        aiButton.isHidden = online || !DebugUI.enabled
        self.online = online
        refreshMapButton()
        refreshBenches()
    }

    /// The buttons' names, for what they'd do right now.
    func setLabels(jump: String, shoot: String, throwBall: String) {
        for (index, text) in [jump, shoot, throwBall].enumerated() where buttons.indices.contains(index) && buttons[index].text != text {
            buttons[index].text = text
            TouchControls.show(text, on: buttons[index])
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeButton(_ label: String, ring name: String, radius: CGFloat, at point: CGPoint,
                            set: @escaping (inout PlayerInput, Bool, Vec2) -> Void) -> (button: Button, set: (inout PlayerInput, Bool, Vec2) -> Void) {
        let node = SKShapeNode(circleOfRadius: radius)
        node.position = point
        node.fillColor = .clear
        node.strokeColor = .clear
        let image = Futuristic.image(name)
        let ring = SKSpriteNode(texture: SKTexture(image: image))
        let across = radius * 2 * TouchControls.ringShare
        ring.size = CGSize(width: across, height: across * image.size.height / max(image.size.width, 1))
        ring.color = TouchControls.line
        ring.colorBlendFactor = 1
        ring.zPosition = -1
        node.addChild(ring)
        let text = Futuristic.label(label, size: 10 * TouchControls.textScale)
        node.addChild(text)
        let icon = SKSpriteNode()
        let iconSide = radius * 2 * TouchControls.iconShare
        icon.size = CGSize(width: iconSide, height: iconSide)
        icon.color = TouchControls.line
        icon.colorBlendFactor = 1
        node.addChild(icon)
        addChild(node)
        let button = Button(node: node, ring: ring, label: text, icon: icon, text: label, radius: radius)
        TouchControls.show(label, on: button)
        return (button, set)
    }

    // MARK: The player's layout

    /// Each round button moved from its home and sized, as the player left it in the layout
    /// editor (BUTTON LAYOUT on the pause), kept on this device; the shield's goes with the throw's.
    struct ButtonPlace: Codable, Equatable {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var scale: CGFloat = 1
    }
    static let placesKey = "touch.buttonPlaces"
    static let placeNames = ["jump", "shoot", "throw"]
    static let scaleRange: ClosedRange<CGFloat> = 0.5...2
    private static func savedPlaces() -> [String: ButtonPlace] {
        UserDefaults.standard.data(forKey: placesKey).flatMap { try? JSONDecoder().decode([String: ButtonPlace].self, from: $0) } ?? [:]
    }
    private var places = TouchControls.savedPlaces()
    private var homes: [CGPoint] = []
    /// Inside the safe area and the padding, in this node's space.
    private let safeBounds: CGRect

    private func place(_ index: Int) -> ButtonPlace { places[TouchControls.placeNames[index]] ?? ButtonPlace() }

    /// Every button where and how big its place has it, and the shield's round the throw's.
    private func applyPlaces() {
        for index in buttons.indices where homes.indices.contains(index) {
            let place = place(index)
            buttons[index].node.position = CGPoint(x: homes[index].x + place.x, y: homes[index].y + place.y)
            buttons[index].node.setScale(place.scale)
        }
        let k = TouchControls.scale
        let snatch = buttons[TouchControls.shieldHost], size = place(TouchControls.shieldHost).scale
        shieldCentre = snatch.node.position
        shieldThickness = TouchControls.shieldThickness * k * size
        shieldBandRadius = snatch.radius * size + TouchControls.shieldGap * k * size + shieldThickness / 2
        drawShieldButton(lit: shieldTouch != nil)
    }

    /// The nearest button whose halo a point's in, at the size it's drawn.
    private func button(at point: CGPoint) -> (index: Int, distance: CGFloat)? {
        buttons.enumerated()
            .map { (index: $0.offset, distance: hypot(point.x - $0.element.node.position.x, point.y - $0.element.node.position.y)) }
            .filter { $0.distance <= buttons[$0.index].radius * buttons[$0.index].node.xScale + 8 }
            .min { $0.distance < $1.distance }
    }

    // MARK: The layout editor

    /// Laying the buttons out: drag one to move it, pinch it (or a second finger down) to size it,
    /// kept to the screen's right half; DONE keeps it, RESET puts every one home.
    private(set) var editing = false
    private var editOverlay: SKNode?
    private var editDone: SKShapeNode?
    private var editReset: SKShapeNode?
    private var editPoints: [UITouch: CGPoint] = [:]
    private var editTarget: (index: Int, grab: CGPoint, scale: CGFloat, spread: CGFloat?)?
    private var onEditDone: (() -> Void)?

    func beginEditing(onDone: @escaping () -> Void) {
        editing = true
        onEditDone = onDone
        input = .idle
        latched = .idle
        let overlay = SKNode()
        overlay.zPosition = 50
        let hint = Futuristic.label("DRAG TO MOVE · PINCH TO RESIZE", size: 10 * TouchControls.textScale)
        hint.position = CGPoint(x: safeBounds.midX, y: safeBounds.maxY - 50 * TouchControls.scale)
        overlay.addChild(hint)
        let done = TouchControls.cornerButton("DONE"), reset = TouchControls.cornerButton("RESET")
        done.position = CGPoint(x: safeBounds.midX + 40 * TouchControls.scale, y: safeBounds.maxY - 22 * TouchControls.scale)
        reset.position = CGPoint(x: safeBounds.midX - 40 * TouchControls.scale, y: safeBounds.maxY - 22 * TouchControls.scale)
        overlay.addChild(done)
        overlay.addChild(reset)
        // The half the buttons keep to, outlined.
        let half = SKShapeNode(rect: CGRect(x: 0, y: safeBounds.minY, width: safeBounds.maxX, height: safeBounds.height))
        half.strokeColor = TouchControls.line.withAlphaComponent(0.35)
        half.lineWidth = 1
        overlay.addChild(half)
        addChild(overlay)
        editOverlay = overlay
        editDone = done
        editReset = reset
        for index in buttons.indices { buttons[index].ring.color = TouchControls.lit }
        setShieldShown(shieldWanted)
    }

    private func endEditing() {
        editing = false
        editOverlay?.removeFromParent()
        editOverlay = nil
        editPoints = [:]
        editTarget = nil
        for index in buttons.indices { buttons[index].ring.color = TouchControls.line }
        setShieldShown(shieldWanted)
        if let data = try? JSONEncoder().encode(places) { UserDefaults.standard.set(data, forKey: TouchControls.placesKey) }
        let done = onEditDone
        onEditDone = nil
        done?()
    }

    private func editBegan(_ touch: UITouch, at point: CGPoint) {
        if let done = editDone, done.frame.insetBy(dx: -8, dy: -6).contains(point) { endEditing(); return }
        if let reset = editReset, reset.frame.insetBy(dx: -8, dy: -6).contains(point) {
            places = [:]
            applyPlaces()
            return
        }
        editPoints[touch] = point
        if var target = editTarget {
            // A second finger: from here, the two pinch the button.
            let fingers = Array(editPoints.values)
            if fingers.count == 2 {
                target.scale = place(target.index).scale
                target.spread = max(hypot(fingers[0].x - fingers[1].x, fingers[0].y - fingers[1].y), 1)
                editTarget = target
            }
            return
        }
        let onShield = onShieldButton(point)
        guard let hit = onShield ? (TouchControls.shieldHost, 0) : button(at: point) else { return }
        let node = buttons[hit.index].node
        editTarget = (hit.index, CGPoint(x: point.x - node.position.x, y: point.y - node.position.y), place(hit.index).scale, nil)
    }

    private func editMoved(_ touch: UITouch, to point: CGPoint) {
        guard editPoints[touch] != nil, let target = editTarget else { return }
        editPoints[touch] = point
        var place = place(target.index)
        let fingers = Array(editPoints.values)
        if let spread = target.spread, fingers.count >= 2 {
            let now = hypot(fingers[0].x - fingers[1].x, fingers[0].y - fingers[1].y)
            place.scale = min(max(target.scale * now / spread, TouchControls.scaleRange.lowerBound), TouchControls.scaleRange.upperBound)
        } else if target.spread == nil {
            let home = homes[target.index]
            place.x = point.x - target.grab.x - home.x
            place.y = point.y - target.grab.y - home.y
        }
        // Kept whole on the right half, inside the safe area.
        let reach = buttons[target.index].radius * place.scale
        let x = min(max(homes[target.index].x + place.x, reach), safeBounds.maxX - reach)
        let y = min(max(homes[target.index].y + place.y, safeBounds.minY + reach), safeBounds.maxY - reach)
        place.x = x - homes[target.index].x
        place.y = y - homes[target.index].y
        places[TouchControls.placeNames[target.index]] = place
        applyPlaces()
    }

    private func editEnded(_ touch: UITouch) {
        editPoints.removeValue(forKey: touch)
        if editPoints.isEmpty {
            editTarget = nil
        } else if var target = editTarget, target.spread != nil {
            // Down to one finger: it drags from where it is.
            if let finger = editPoints.values.first {
                let node = buttons[target.index].node
                target.grab = CGPoint(x: finger.x - node.position.x, y: finger.y - node.position.y)
            }
            target.spread = nil
            editTarget = target
        }
    }

    // MARK: The shield's button

    /// The button the capsule goes round: throw, the snatch on defence.
    private static let shieldHost = 2
    /// The capsule (SHIELD GAP, LENGTH, ANGLE): its band this far off the throw ring, this many
    /// degrees long, its middle this many degrees round from the right; this thick.
    static var shieldGap: CGFloat = 7
    static var shieldLengthDegrees: CGFloat = 90
    static var shieldAngleDegrees: CGFloat = 45
    private static let shieldThickness: CGFloat = 16
    private static var shieldArc: ClosedRange<CGFloat> {
        let middle = shieldAngleDegrees * .pi / 180, half = shieldLengthDegrees * .pi / 360
        return (middle - half)...(middle + half)
    }
    /// The capsule redrawn after its sliders move.
    func relayoutShield() { applyPlaces() }
    /// The capsule shown only while the other player has the ball.
    func setShieldShown(_ shown: Bool) {
        shieldWanted = shown
        let visible = shown || editing
        guard shieldButton.isHidden == visible else { return }
        shieldButton.isHidden = !visible
        if !visible, shieldTouch != nil {
            shieldTouch = nil
            input.shield = false
            drawShieldButton(lit: false)
        }
    }
    private let shieldButton = SKShapeNode()
    /// The shield's icon on the band, upright, this share of the band's thickness.
    private let shieldIcon = SKSpriteNode()
    private static let shieldIconShare: CGFloat = 0.8
    private var shieldCentre = CGPoint.zero
    private var shieldBandRadius: CGFloat = 0
    private var shieldThickness: CGFloat = 0
    private var shieldTouch: UITouch?
    private var shieldWanted = false

    /// The band's outline, round at both ends: gold and filled while held.
    private func drawShieldButton(lit: Bool) {
        let arc = TouchControls.shieldArc, half = shieldThickness / 2
        let outer = shieldBandRadius + half, inner = shieldBandRadius - half
        func point(_ angle: CGFloat, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: shieldCentre.x + cos(angle) * radius, y: shieldCentre.y + sin(angle) * radius)
        }
        let path = CGMutablePath()
        path.addArc(center: shieldCentre, radius: outer, startAngle: arc.lowerBound, endAngle: arc.upperBound, clockwise: false)
        path.addArc(center: point(arc.upperBound, shieldBandRadius), radius: half, startAngle: arc.upperBound, endAngle: arc.upperBound + .pi, clockwise: false)
        path.addArc(center: shieldCentre, radius: inner, startAngle: arc.upperBound, endAngle: arc.lowerBound, clockwise: true)
        path.addArc(center: point(arc.lowerBound, shieldBandRadius), radius: half, startAngle: arc.lowerBound + .pi, endAngle: arc.lowerBound + 2 * .pi, clockwise: false)
        path.closeSubpath()
        shieldButton.path = path
        shieldButton.lineWidth = 2 * TouchControls.scale
        shieldButton.strokeColor = lit ? TouchControls.lit : TouchControls.line
        shieldButton.fillColor = lit ? TouchControls.lit.withAlphaComponent(0.3) : .clear
        if shieldIcon.parent == nil {
            shieldIcon.texture = TouchControls.iconTexture("GuardIcon")
            shieldIcon.colorBlendFactor = 1
            shieldButton.addChild(shieldIcon)
        }
        let middle = (arc.lowerBound + arc.upperBound) / 2
        let iconSide = shieldThickness * TouchControls.shieldIconShare
        shieldIcon.size = CGSize(width: iconSide, height: iconSide)
        shieldIcon.position = point(middle, shieldBandRadius)
        shieldIcon.color = lit ? TouchControls.lit : TouchControls.line
    }

    /// Whether a point's on the band, a little over its edges and ends to spare.
    private func onShieldButton(_ point: CGPoint) -> Bool {
        guard !shieldButton.isHidden else { return false }
        let dx = point.x - shieldCentre.x, dy = point.y - shieldCentre.y
        // The angle off the band's middle, either way round.
        let middle = TouchControls.shieldAngleDegrees * .pi / 180
        var off = atan2(dy, dx) - middle
        off = atan2(sin(off), cos(off))
        let spare: CGFloat = 4 * TouchControls.scale, angleSpare: CGFloat = 8 * .pi / 180
        return abs(hypot(dx, dy) - shieldBandRadius) <= shieldThickness / 2 + spare
            && abs(off) <= TouchControls.shieldLengthDegrees * .pi / 360 + angleSpare
    }

    /// A round button held or let go: gold while held, its ring turning a full circle as it goes down.
    private func press(_ index: Int, down: Bool) {
        let button = buttons[index]
        button.ring.color = down ? TouchControls.lit : TouchControls.line
        button.label.fontColor = down ? TouchControls.lit : TouchControls.line
        button.icon.color = down ? TouchControls.lit : TouchControls.line
        guard down else { return }
        button.ring.removeAction(forKey: "spin")
        button.ring.zRotation = 0
        let spin = SKAction.rotate(byAngle: -2 * .pi, duration: TouchControls.ringSpinSeconds)
        spin.timingMode = .easeOut
        button.ring.run(spin, withKey: "spin")
    }

    /// The FLO meter tapped: throw and shoot together for a frame, the change into FloState or out.
    func tapFloState() {
        latched.shoot = true
        latched.throwBall = true
    }

    /// The controls as the sim should see them this frame: what's held, plus anything that
    /// was tapped and let go since the last sample.
    func sample() -> PlayerInput {
        var frame = input
        frame.jump = frame.jump || latched.jump
        frame.shoot = frame.shoot || latched.shoot
        frame.throwBall = frame.throwBall || latched.throwBall
        frame.shield = frame.shield || latched.shield
        if latched.aim != .zero, frame.aim == .zero { frame.aim = latched.aim }
        latched = .idle
        return frame
    }

    /// Adds a picker under the ones already in the top-left corner.
    func addPicker(title: String, options: [String], selected: Int, perRow: Int = .max, onSelect: @escaping (Int) -> Void) {
        let picker = SegmentedPicker(title: title, options: options, selected: selected, perRow: perRow, onSelect: onSelect)
        picker.position = CGPoint(x: pickerOrigin.x, y: pickersBottom)
        addChild(picker)
        pickers.append(picker)
        refreshBenches()
    }

    /// Adds a slider across the top, under the score, below any already there, eight to a column.
    @discardableResult
    func addSlider(title: String, range: ClosedRange<Float>, notch: Float, value: Float, onChange: @escaping (Float) -> Void) -> Slider {
        let slider = Slider(title: title, range: range, notch: notch, value: value, onChange: onChange)
        // Parked: made but not put on the bench (`ParkedSliders.shown`).
        guard ParkedSliders.shown(title) else { return slider }
        addChild(slider)
        sliders.append(slider)
        // As many to a column as fit down the screen above the pad (eight at least), the columns
        // side by side about the middle, so a long set stays clear of the pickers at the left.
        let perColumn = sliderRows
        let columns = (sliders.count + perColumn - 1) / perColumn
        for (index, placed) in sliders.enumerated() {
            let column = CGFloat(index / perColumn) - CGFloat(columns - 1) / 2
            placed.position = CGPoint(x: topCentre.x + column * (Slider.size.width + 14),
                                      y: topCentre.y - TouchControls.slidersTop - CGFloat(index % perColumn) * 16)
        }
        refreshBenches()
        return slider
    }

    /// A picker shown on an option the game chose, without calling back.
    func showPicker(titled title: String, at index: Int) {
        pickers.first { $0.title == title }?.show(index)
    }

    /// The newest picker steps to its next option.
    func cyclePicker(titled title: String) {
        pickers.first { $0.title == title }?.selectNext()
    }

    /// Under the sliders across the top, or under the score with none.
    var slidersBottom: CGFloat {
        guard slidersOpen else { return topCentre.y - 30 - TouchControls.benchTabSize.height }
        return topCentre.y - TouchControls.slidersTop - CGFloat(max(min(sliders.count, sliderRows) - 1, 0)) * 16 - 10
    }
    /// Sliders to a column: down to the pad's height, above the buttons.
    private var sliderRows: Int { max(8, Int((safeBounds.height - TouchControls.slidersTop - 130) / 16)) }

    /// Where the next picker goes, under the tab and the ones there.
    private var pickersBottom: CGFloat {
        pickerOrigin.y - TouchControls.benchTabSize.height - 4 - pickers.reduce(0) { $0 + $1.height + 4 }
    }
    /// The foot of the pickers' bench, open or folded, so other corner text can sit under it.
    var pickerBottom: CGFloat {
        pickersOpen ? pickersBottom : pickerOrigin.y - TouchControls.benchTabSize.height - 4
    }

    // MARK: Touches, in this node's space

    /// Whether a point is on the debug UI: the benches' tabs, the corner switches, an open
    /// picker or a slider. It goes here before anything else in the HUD can take it.
    func claims(_ point: CGPoint) -> Bool {
        let tabs = [pickerTab, sliderTab].contains { !$0.isHidden && $0.frame.insetBy(dx: -4, dy: -4).contains(point) }
        let switches = [resetButton, hitboxButton, aiButton, wallsButton, mapButton].contains { !$0.isHidden && $0.frame.insetBy(dx: -8, dy: -3).contains(point) }
        let benches = pickers.contains { !$0.isHidden && $0.calculateAccumulatedFrame().contains(point) }
            || sliders.contains { !$0.isHidden && $0.covers(convert(point, to: $0)) }
        return tabs || switches || benches
    }

    func began(_ touch: UITouch, at point: CGPoint) {
        if editing { editBegan(touch, at: point); return }
        if !pickerTab.isHidden, pickerTab.frame.insetBy(dx: -4, dy: -4).contains(point) {
            pickersOpen.toggle()
            return
        }
        if !sliderTab.isHidden, sliderTab.frame.insetBy(dx: -4, dy: -4).contains(point) {
            slidersOpen.toggle()
            return
        }
        if !resetButton.isHidden, resetButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
            onReset?()
            return
        }
        if !pauseButton.isHidden, pauseButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
            onPause?()
            return
        }
        if !hitboxButton.isHidden, hitboxButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
            showHitboxes.toggle()
            onToggleHitboxes?(showHitboxes)
            return
        }
        if !wallsButton.isHidden, wallsButton.frame.insetBy(dx: -8, dy: -3).contains(point) {
            showWalls.toggle()
            onToggleWalls?(showWalls)
            return
        }
        if !mapButton.isHidden, mapButton.frame.insetBy(dx: -8, dy: -3).contains(point) {
            onMap?()
            return
        }
        if !aiButton.isHidden, aiButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
            aiOn.toggle()
            onToggleAI?(aiOn)
            return
        }
        for picker in pickers where !picker.isHidden && picker.tap(at: convert(point, to: picker)) {
            return
        }
        for slider in sliders where !slider.isHidden && slider.covers(convert(point, to: slider)) {
            sliderTouches[touch] = slider
            slider.drag(to: convert(point, to: slider))
            return
        }
        if point.x < 0 {
            guard stickTouch == nil else { return }
            stickTouch = touch
            stickCenter = point
            stickBase.position = point
            stickBase.isHidden = false
            stickKnob.position = point
            stickKnob.isHidden = false
            input.stick = .zero
            return
        }
        if shieldTouch == nil, onShieldButton(point) {
            shieldTouch = touch
            input.shield = true
            latched.shield = true
            drawShieldButton(lit: true)
            return
        }
        // The nearest button whose halo the touch is in, so a thumb between two goes to the closer one.
        let reach = button(at: point)
        if let reach {
            buttonTouches[touch] = (reach.index, point)
            press(reach.index, down: true)
            buttonSets[reach.index](&input, true, .zero)
            buttonSets[reach.index](&latched, true, .zero)
        }
    }

    func moved(_ touch: UITouch, to point: CGPoint) {
        if editing { editMoved(touch, to: point); return }
        if let slider = sliderTouches[touch] {
            slider.drag(to: convert(point, to: slider))
            return
        }
        if touch == stickTouch {
            let raw = TouchControls.eightWays(Vec2(x: (point.x - stickCenter.x) / TouchControls.stickRadius,
                                                   y: (point.y - stickCenter.y) / TouchControls.stickRadius).clamped(to: 1))
            input.stick = InputHub.deadzoned(raw)
            stickKnob.position = CGPoint(x: stickCenter.x + raw.x * TouchControls.stickRadius,
                                         y: stickCenter.y + raw.y * TouchControls.stickRadius)
            return
        }
        if let held = buttonTouches[touch] {
            let aim = Vec2(x: (point.x - held.origin.x) / TouchControls.flickRadius,
                           y: (point.y - held.origin.y) / TouchControls.flickRadius).clamped(to: 1)
            buttonSets[held.index](&input, true, aim)
            if aim.length >= BallRules.flickThreshold { latched.aim = aim }
        }
    }

    func ended(_ touch: UITouch) {
        if editing { editEnded(touch); return }
        if sliderTouches.removeValue(forKey: touch) != nil { return }
        if touch == stickTouch {
            stickTouch = nil
            input.stick = .zero
            stickBase.isHidden = true
            stickKnob.isHidden = true
            return
        }
        if touch == shieldTouch {
            shieldTouch = nil
            input.shield = false
            drawShieldButton(lit: false)
            return
        }
        if let held = buttonTouches.removeValue(forKey: touch) {
            press(held.index, down: false)
            buttonSets[held.index](&input, false, .zero)
            if buttonTouches.isEmpty { input.aim = .zero }
        }
    }
}
