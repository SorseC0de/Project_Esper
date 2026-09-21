import EsperSim
import SpriteKit

/// The on-screen controls, laid out in screen points from the centre. The left half is a
/// floating stick: the thumb's first touch is the centre. The right half holds three
/// buttons. Shoot and throw read the drag away from the touch-down point as the flick.
final class TouchControls: SKNode {
    static let stickRadius = 40.0
    static let flickRadius = 32.0

    private struct Button {
        let node: SKShapeNode
        let radius: CGFloat
        let set: (inout PlayerInput, Bool, Vec2) -> Void
    }

    private var buttons: [Button] = []
    private let stickBase = SKShapeNode(circleOfRadius: stickRadius)
    private let stickKnob = SKShapeNode(circleOfRadius: 14)
    private let resetButton = SKShapeNode(rectOf: CGSize(width: 46, height: 16), cornerRadius: 4)
    /// Called when the corner button is tapped.
    var onReset: (() -> Void)?
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

        stickBase.strokeColor = .init(white: 1, alpha: 0.3)
        stickBase.fillColor = .init(white: 1, alpha: 0.08)
        stickBase.lineWidth = 1
        stickBase.isHidden = true
        stickKnob.fillColor = .init(white: 1, alpha: 0.5)
        stickKnob.strokeColor = .clear
        stickKnob.isHidden = true
        addChild(stickBase)
        addChild(stickKnob)

        // Shoot and jump side by side, throw below and between them.
        let jump = makeButton("JUMP", radius: 30, at: CGPoint(x: right - 38, y: bottom + 84)) { input, down, _ in
            input.jump = down
        }
        let shoot = makeButton("SHOOT", radius: 30, at: CGPoint(x: right - 114, y: bottom + 84)) { input, down, aim in
            input.shoot = down
            if down { input.aim = aim }
        }
        let throwButton = makeButton("THROW", radius: 24, at: CGPoint(x: right - 76, y: bottom + 26)) { input, down, aim in
            input.throwBall = down
            if down { input.aim = aim }
        }
        buttons = [jump, shoot, throwButton]

        resetButton.position = CGPoint(x: right - 23, y: top - 8)
        resetButton.fillColor = .init(white: 1, alpha: 0.1)
        resetButton.strokeColor = .init(white: 1, alpha: 0.4)
        resetButton.lineWidth = 1
        let resetText = SKLabelNode(text: "RESET")
        resetText.fontName = "Menlo-Bold"
        resetText.fontSize = 8
        resetText.verticalAlignmentMode = .center
        resetText.fontColor = .init(white: 1, alpha: 0.8)
        resetButton.addChild(resetText)
        addChild(resetButton)

    }

    required init?(coder: NSCoder) { fatalError() }

    private func makeButton(_ label: String, radius: CGFloat, at point: CGPoint,
                            set: @escaping (inout PlayerInput, Bool, Vec2) -> Void) -> Button {
        let node = SKShapeNode(circleOfRadius: radius)
        node.position = point
        node.fillColor = .init(white: 1, alpha: 0.1)
        node.strokeColor = .init(white: 1, alpha: 0.4)
        node.lineWidth = 1
        let text = SKLabelNode(text: label)
        text.fontName = "Menlo-Bold"
        text.fontSize = 9
        text.verticalAlignmentMode = .center
        text.fontColor = .init(white: 1, alpha: 0.8)
        node.addChild(text)
        addChild(node)
        return Button(node: node, radius: radius, set: set)
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
    func addPicker(title: String, options: [String], selected: Int, onSelect: @escaping (Int) -> Void) {
        let picker = SegmentedPicker(title: title, options: options, selected: selected, onSelect: onSelect)
        picker.position = CGPoint(x: pickerOrigin.x, y: pickerBottom)
        addChild(picker)
        pickers.append(picker)
    }

    /// Adds a slider across the top, under the score, below any already there.
    func addSlider(title: String, range: ClosedRange<Float>, value: Float, onChange: @escaping (Float) -> Void) {
        let slider = Slider(title: title, range: range, value: value, onChange: onChange)
        slider.position = CGPoint(x: topCentre.x, y: topCentre.y - 34 - CGFloat(sliders.count) * 26)
        addChild(slider)
        sliders.append(slider)
    }

    /// The top picker steps to its next option.
    func cycleTopPicker() {
        pickers.first?.selectNext()
    }

    /// Where the next picker would go, so other corner text can sit under them.
    var pickerBottom: CGFloat {
        pickerOrigin.y - CGFloat(pickers.count) * (SegmentedPicker.segmentSize.height + 4)
    }

    // MARK: Touches, in this node's space

    func began(_ touch: UITouch, at point: CGPoint) {
        if resetButton.frame.insetBy(dx: -8, dy: -8).contains(point) {
            onReset?()
            return
        }
        for picker in pickers where picker.tap(at: convert(point, to: picker)) {
            return
        }
        for slider in sliders where slider.covers(convert(point, to: slider)) {
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
            let button = buttons[reach.index]
            buttonTouches[touch] = (reach.index, point)
            button.node.fillColor = .init(white: 1, alpha: 0.4)
            button.set(&input, true, .zero)
            button.set(&latched, true, .zero)
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
            buttons[held.index].set(&input, true, aim)
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
            buttons[held.index].node.fillColor = .init(white: 1, alpha: 0.1)
            buttons[held.index].set(&input, false, .zero)
            if buttonTouches.isEmpty { input.aim = .zero }
        }
    }
}
