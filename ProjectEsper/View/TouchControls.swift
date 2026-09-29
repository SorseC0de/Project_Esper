import EsperSim
import SpriteKit

/// The on-screen controls, laid out in screen points from the centre. The left half is a
/// floating stick: the thumb's first touch is the centre. The right half holds three
/// buttons. Shoot and throw read the drag away from the touch-down point as the flick.
final class TouchControls: SKNode {
    static let stickRadius = 40.0
    static let flickRadius = 32.0

    /// A round button: its circle, invisible, for the touch; the pack's round button over
    /// it, gold while it's held; and its name in title lettering on the face.
    private struct Button {
        let node: SKShapeNode
        let plate: SKSpriteNode
        let piece: UIPiece
        let label: SKSpriteNode
        var text: String
        let radius: CGFloat
    }
    private var buttonSets: [(inout PlayerInput, Bool, Vec2) -> Void] = []

    /// The touch pad's tuned sizes (`UITuning`, TOUCH).
    private static var scale: CGFloat { UITuning.shared.scale(.touch, .buttons) }
    private static var textScale: CGFloat { UITuning.shared.scale(.touch, .text) }

    private var buttons: [Button] = []
    private let stickBase = UIPiece.circleBlack.node(size: CGSize(width: stickRadius * 2, height: stickRadius * 2 * 117 / 109))
    private let stickKnob = UIPiece.circleBlue.node(size: CGSize(width: 30, height: 32))
    /// The corner switches: an invisible rect for the touch, a black plate on it, plum when on.
    private let resetButton = TouchControls.cornerButton("RESET")
    private let hitboxButton = TouchControls.cornerButton("HITBOX")
    private let aiButton = TouchControls.cornerButton("AI")
    private let pauseButton = TouchControls.cornerButton("PAUSE")

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
    var onToggleHitboxes: ((Bool) -> Void)?
    /// The AI switch beside that: whether the computer plays the other side.
    var aiOn = true { didSet { TouchControls.light(aiButton, on: aiOn) } }
    var onToggleAI: ((Bool) -> Void)?
    private var pickers: [SegmentedPicker] = []
    private let pickerOrigin: CGPoint
    private var sliders: [Slider] = []
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

        // Throw and shoot side by side, jump below and between them, all at the tuned size.
        let k = TouchControls.scale
        let jump = makeButton("JUMP", piece: .circleBlue, radius: 30 * k, at: CGPoint(x: right - 76 * k, y: bottom + 26 * k)) { input, down, _ in
            input.jump = down
        }
        let shoot = makeButton("SHOOT", piece: .circlePlum, radius: 30 * k, at: CGPoint(x: right - 38 * k, y: bottom + 84 * k)) { input, down, aim in
            input.shoot = down
            if down { input.aim = aim }
        }
        let throwButton = makeButton("THROW", piece: .circleBlack, radius: 24 * k, at: CGPoint(x: right - 114 * k, y: bottom + 84 * k)) { input, down, aim in
            input.throwBall = down
            if down { input.aim = aim }
        }
        buttons = [jump.button, shoot.button, throwButton.button]
        buttonSets = [jump.set, shoot.set, throwButton.set]

        // The corner switches in a row along the top, right to left.
        let step = (TouchControls.cornerSize.width + 6) * k
        for (index, button) in [resetButton, hitboxButton, aiButton, pauseButton].enumerated() {
            button.position = CGPoint(x: right - TouchControls.cornerSize.width * k / 2 - CGFloat(index) * step, y: top - TouchControls.cornerSize.height * k / 2)
            addChild(button)
        }
        TouchControls.light(aiButton, on: aiOn)
    }

    /// Online there's no reset, no pause, no computer and no tuning: only the pad and HITBOX.
    func setOnline(_ online: Bool) {
        resetButton.isHidden = online
        pauseButton.isHidden = online
        aiButton.isHidden = online
        for picker in pickers { picker.isHidden = online }
        for slider in sliders { slider.isHidden = online }
    }

    /// The buttons' names, for what they'd do right now.
    func setLabels(jump: String, shoot: String, throwBall: String) {
        for (index, text) in [jump, shoot, throwBall].enumerated() where buttons.indices.contains(index) && buttons[index].text != text {
            buttons[index].text = text
            TitleText.set(buttons[index].label, to: text, size: 10 * TouchControls.textScale)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeButton(_ label: String, piece: UIPiece, radius: CGFloat, at point: CGPoint,
                            set: @escaping (inout PlayerInput, Bool, Vec2) -> Void) -> (button: Button, set: (inout PlayerInput, Bool, Vec2) -> Void) {
        let node = SKShapeNode(circleOfRadius: radius)
        node.position = point
        node.fillColor = .clear
        node.strokeColor = .clear
        let corners = radius * 2 / (109 * UIPiece.pointsPerPixel)
        let plate = piece.node(size: CGSize(width: radius * 2, height: radius * 2 * 117 / 109), corners: corners)
        plate.alpha = 0.9
        plate.zPosition = -1
        node.addChild(plate)
        let text = TitleText.node(label, size: 10 * TouchControls.textScale)
        text.position = CGPoint(x: 0, y: piece.faceRise * corners)
        node.addChild(text)
        addChild(node)
        return (Button(node: node, plate: plate, piece: piece, label: text, text: label, radius: radius), set)
    }

    /// A round button held or let go: gold while held.
    private func press(_ index: Int, down: Bool) {
        let button = buttons[index]
        let corners = button.radius * 2 / (109 * UIPiece.pointsPerPixel)
        (down ? UIPiece.circleGold : button.piece).fit(button.plate, to: CGSize(width: button.radius * 2, height: button.radius * 2 * 117 / 109), corners: corners)
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
        picker.position = CGPoint(x: pickerOrigin.x, y: pickerBottom)
        addChild(picker)
        pickers.append(picker)
    }

    /// Adds a slider across the top, under the score, below any already there, six to a column.
    @discardableResult
    func addSlider(title: String, range: ClosedRange<Float>, notch: Float, value: Float, onChange: @escaping (Float) -> Void) -> Slider {
        let slider = Slider(title: title, range: range, notch: notch, value: value, onChange: onChange)
        addChild(slider)
        sliders.append(slider)
        // Six to a column, the columns side by side about the middle, so a long set fits.
        let perColumn = 6
        let columns = (sliders.count + perColumn - 1) / perColumn
        for (index, placed) in sliders.enumerated() {
            let column = CGFloat(index / perColumn) - CGFloat(columns - 1) / 2
            placed.position = CGPoint(x: topCentre.x + column * (Slider.size.width + 20),
                                      y: topCentre.y - 34 - CGFloat(index % perColumn) * 26)
        }
        return slider
    }

    /// The newest picker steps to its next option.
    func cyclePicker(titled title: String) {
        pickers.first { $0.title == title }?.selectNext()
    }

    /// Where the next picker would go, so other corner text can sit under them.
    var pickerBottom: CGFloat {
        pickerOrigin.y - pickers.reduce(0) { $0 + $1.height + 4 }
    }

    // MARK: Touches, in this node's space

    func began(_ touch: UITouch, at point: CGPoint) {
        if !resetButton.isHidden, resetButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
            onReset?()
            return
        }
        if !pauseButton.isHidden, pauseButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
            onPause?()
            return
        }
        if hitboxButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
            showHitboxes.toggle()
            onToggleHitboxes?(showHitboxes)
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
