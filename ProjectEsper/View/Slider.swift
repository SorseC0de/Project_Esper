import SpriteKit

/// A track with a knob and the value printed over it, for a number to be felt out live.
final class Slider: SKNode {
    static let size = CGSize(width: 160, height: 14)

    private let track = SKShapeNode(rectOf: CGSize(width: Slider.size.width, height: 4), cornerRadius: 2)
    private let knob = SKShapeNode(circleOfRadius: 7)
    private let label = SKLabelNode()
    private let title: String
    private let range: ClosedRange<Float>
    private(set) var value: Float
    private let onChange: (Float) -> Void

    init(title: String, range: ClosedRange<Float>, value: Float, onChange: @escaping (Float) -> Void) {
        self.title = title
        self.range = range
        self.value = value
        self.onChange = onChange
        super.init()
        track.fillColor = .init(white: 1, alpha: 0.25)
        track.strokeColor = .clear
        addChild(track)
        knob.fillColor = .init(white: 1, alpha: 0.8)
        knob.strokeColor = .clear
        addChild(knob)
        label.fontName = "Menlo-Bold"
        label.fontSize = 8
        label.fontColor = .init(white: 1, alpha: 0.8)
        label.verticalAlignmentMode = .bottom
        label.position = CGPoint(x: 0, y: 8)
        addChild(label)
        show()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Whether `point`, in this node's space, is on the slider, with room around it.
    func covers(_ point: CGPoint) -> Bool {
        abs(point.x) <= Slider.size.width / 2 + 10 && abs(point.y) <= Slider.size.height
    }

    /// Sets the value from where the finger is along the track.
    func drag(to point: CGPoint) {
        let share = min(max((point.x + Slider.size.width / 2) / Slider.size.width, 0), 1)
        value = range.lowerBound + Float(share) * (range.upperBound - range.lowerBound)
        show()
        onChange(value)
    }

    private func show() {
        let share = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
        knob.position = CGPoint(x: -Slider.size.width / 2 + share * Slider.size.width, y: 0)
        label.text = String(format: "%@ %.2f", title, value)
    }
}
