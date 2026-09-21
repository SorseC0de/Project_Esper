import EsperSim
import SpriteKit

/// The on-screen controls, drawn in the camera's space in game pixels. The left half is a
/// floating stick: the thumb's first touch is the centre. The right half holds three
/// buttons. Shoot and throw read the drag away from the touch-down point as the flick.
final class TouchControls: SKNode {
    static let stickRadius = 30.0
    static let flickRadius = 25.0

    private struct Button {
        let node: SKShapeNode
        let radius: CGFloat
        let set: (inout PlayerInput, Bool, Vec2) -> Void
    }

    private var buttons: [Button] = []
    private let stickBase = SKShapeNode(circleOfRadius: stickRadius)
    private let stickKnob = SKShapeNode(circleOfRadius: 10)
    private let resetButton = SKShapeNode(rectOf: CGSize(width: 34, height: 12), cornerRadius: 3)
    /// Called when the corner button is tapped.
    var onReset: (() -> Void)?
    private var stickTouch: UITouch?
    private var stickCenter = CGPoint.zero
    private var buttonTouches: [UITouch: (index: Int, origin: CGPoint)] = [:]

    private(set) var input = PlayerInput.idle

    /// `halfWidth` and `halfHeight` are what the camera shows, in game pixels.
    init(halfWidth: CGFloat, halfHeight: CGFloat) {
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

        let jump = makeButton("JUMP", radius: 22, at: CGPoint(x: halfWidth - 40, y: -halfHeight + 44)) { input, down, _ in
            input.jump = down
        }
        let shoot = makeButton("SHOOT", radius: 18, at: CGPoint(x: halfWidth - 92, y: -halfHeight + 66)) { input, down, aim in
            input.shoot = down
            if down { input.aim = aim }
        }
        let throwButton = makeButton("THROW", radius: 18, at: CGPoint(x: halfWidth - 108, y: -halfHeight + 22)) { input, down, aim in
            input.throwBall = down
            if down { input.aim = aim }
        }
        buttons = [jump, shoot, throwButton]

        resetButton.position = CGPoint(x: halfWidth - 24, y: halfHeight - 12)
        resetButton.fillColor = .init(white: 1, alpha: 0.1)
        resetButton.strokeColor = .init(white: 1, alpha: 0.4)
        resetButton.lineWidth = 1
        let resetText = SKLabelNode(text: "RESET")
        resetText.fontName = "Menlo-Bold"
        resetText.fontSize = 6
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
        text.fontSize = 7
        text.verticalAlignmentMode = .center
        text.fontColor = .init(white: 1, alpha: 0.8)
        node.addChild(text)
        addChild(node)
        return Button(node: node, radius: radius, set: set)
    }

    // MARK: Touches, in this node's space

    func began(_ touch: UITouch, at point: CGPoint) {
        if resetButton.frame.insetBy(dx: -6, dy: -6).contains(point) {
            onReset?()
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
        for (index, button) in buttons.enumerated() where hypot(point.x - button.node.position.x, point.y - button.node.position.y) <= button.radius + 8 {
            buttonTouches[touch] = (index, point)
            button.node.fillColor = .init(white: 1, alpha: 0.4)
            button.set(&input, true, .zero)
            return
        }
    }

    func moved(_ touch: UITouch, to point: CGPoint) {
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
        }
    }

    func ended(_ touch: UITouch) {
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
