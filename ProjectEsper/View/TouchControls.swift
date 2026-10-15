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
        var text: String
        let radius: CGFloat
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
    /// The stick: ring 3 its base, a small arrow 2 out from it each of the four ways, and ring 7
    /// the knob that moves inside it, all in the menus' blue.
    private let stickBase: SKNode = {
        let base = SKNode()
        let ring = Futuristic.sprite("ring3", scale: 1)
        ring.size = CGSize(width: stickRadius * 2, height: stickRadius * 2)
        base.addChild(ring)
        for quarter in 0..<4 {
            let arrow = Futuristic.sprite("arrow2", scale: 1)
            let image = Futuristic.image("arrow2")
            arrow.size = CGSize(width: stickArrowSize * image.size.width / max(image.size.height, 1), height: stickArrowSize)
            let angle = CGFloat(quarter) * .pi / 2
            let out = stickRadius + stickArrowSize / 2 + stickArrowGap
            arrow.position = CGPoint(x: cos(angle) * out, y: sin(angle) * out)
            arrow.zRotation = angle
            base.addChild(arrow)
        }
        return base
    }()
    private let stickKnob: SKSpriteNode = {
        let knob = Futuristic.sprite("ring7", scale: 1)
        knob.size = CGSize(width: stickKnobSize, height: stickKnobSize)
        return knob
    }()
    private static let stickArrowSize: CGFloat = 10
    private static let stickArrowGap: CGFloat = 2
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
        pickerTab.isHidden = online || pickers.isEmpty
        sliderTab.isHidden = online || sliders.isEmpty
        for picker in pickers { picker.isHidden = online || !pickersOpen }
        for slider in sliders { slider.isHidden = online || !slidersOpen }
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
        // Throw and shoot side by side, jump below and between them, all at the tuned size:
        // jump and throw in ring6, shoot in ring4.
        let k = TouchControls.scale
        let jump = makeButton("JUMP", ring: "ring6", radius: 30 * k, at: CGPoint(x: right - 76 * k, y: bottom + 26 * k)) { input, down, _ in
            input.jump = down
        }
        let shoot = makeButton("SHOOT", ring: "ring4", radius: 30 * k, at: CGPoint(x: right - 38 * k, y: bottom + 84 * k)) { input, down, aim in
            input.shoot = down
            if down { input.aim = aim }
        }
        let throwButton = makeButton("THROW", ring: "ring6", radius: 24 * k, at: CGPoint(x: right - 114 * k, y: bottom + 84 * k)) { input, down, aim in
            input.throwBall = down
            if down { input.aim = aim }
        }
        buttons = [jump.button, shoot.button, throwButton.button]
        buttonSets = [jump.set, shoot.set, throwButton.set]

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
            buttons[index].label.text = text
            TouchControls.fit(buttons[index].label, inside: buttons[index].radius)
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
        TouchControls.fit(text, inside: radius)
        node.addChild(text)
        addChild(node)
        return (Button(node: node, ring: ring, label: text, text: label, radius: radius), set)
    }

    /// A round button held or let go: gold while held, its ring turning a full circle as it goes down.
    private func press(_ index: Int, down: Bool) {
        let button = buttons[index]
        button.ring.color = down ? TouchControls.lit : TouchControls.line
        button.label.fontColor = down ? TouchControls.lit : TouchControls.line
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
        addChild(slider)
        sliders.append(slider)
        // Eight to a column, the columns side by side about the middle, so a long set fits.
        let perColumn = 8
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
        return topCentre.y - TouchControls.slidersTop - CGFloat(max(min(sliders.count, 8) - 1, 0)) * 16 - 10
    }

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
        // The nearest button whose halo the touch is in, so a thumb between two goes to the closer one.
        let reach = buttons.enumerated()
            .map { (index: $0.offset, distance: hypot(point.x - $0.element.node.position.x, point.y - $0.element.node.position.y)) }
            .filter { $0.distance <= buttons[$0.index].radius + 8 }
            .min { $0.distance < $1.distance }
        if let reach {
            buttonTouches[touch] = (reach.index, point)
            press(reach.index, down: true)
            buttonSets[reach.index](&input, true, .zero)
            buttonSets[reach.index](&latched, true, .zero)
        }
    }

    func moved(_ touch: UITouch, to point: CGPoint) {
        if let slider = sliderTouches[touch] {
            slider.drag(to: convert(point, to: slider))
            return
        }
        if touch == stickTouch {
            let raw = Vec2(x: (point.x - stickCenter.x) / TouchControls.stickRadius,
                           y: (point.y - stickCenter.y) / TouchControls.stickRadius).clamped(to: 1)
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
        if sliderTouches.removeValue(forKey: touch) != nil { return }
        if touch == stickTouch {
            stickTouch = nil
            input.stick = .zero
            stickBase.isHidden = true
            stickKnob.isHidden = true
            return
        }
        if let held = buttonTouches.removeValue(forKey: touch) {
            press(held.index, down: false)
            buttonSets[held.index](&input, false, .zero)
            if buttonTouches.isEmpty { input.aim = .zero }
        }
    }
}
