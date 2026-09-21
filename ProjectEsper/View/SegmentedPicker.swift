import SpriteKit

/// A row of lettered segments with a title on the left. One is lit.
final class SegmentedPicker: SKNode {
    static let segmentSize = CGSize(width: 14, height: 10)

    private var segments: [SKShapeNode] = []
    private(set) var selected: Int
    private let onSelect: (Int) -> Void

    /// Laid out from the top-left corner of the title.
    init(title: String, options: [String], selected: Int, onSelect: @escaping (Int) -> Void) {
        self.selected = selected
        self.onSelect = onSelect
        super.init()

        let label = SKLabelNode(text: title)
        label.fontName = "Menlo-Bold"
        label.fontSize = 6
        label.fontColor = .init(white: 1, alpha: 0.8)
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -SegmentedPicker.segmentSize.height / 2)
        addChild(label)

        let start = CGFloat(title.count) * 4 + 8
        for (index, option) in options.enumerated() {
            let segment = SKShapeNode(rectOf: SegmentedPicker.segmentSize, cornerRadius: 2)
            segment.position = CGPoint(x: start + (SegmentedPicker.segmentSize.width + 2) * CGFloat(index) + SegmentedPicker.segmentSize.width / 2,
                                       y: -SegmentedPicker.segmentSize.height / 2)
            segment.strokeColor = .init(white: 1, alpha: 0.4)
            segment.lineWidth = 1
            let text = SKLabelNode(text: option)
            text.fontName = "Menlo-Bold"
            text.fontSize = 6
            text.fontColor = .init(white: 1, alpha: 0.9)
            text.verticalAlignmentMode = .center
            segment.addChild(text)
            addChild(segment)
            segments.append(segment)
        }
        light()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Selects whichever segment is under `point`, in this node's space. True if one was.
    func tap(at point: CGPoint) -> Bool {
        for (index, segment) in segments.enumerated() where segment.frame.insetBy(dx: -2, dy: -3).contains(point) {
            selected = index
            light()
            onSelect(index)
            return true
        }
        return false
    }

    /// Steps to the next segment, wrapping.
    func selectNext() {
        selected = (selected + 1) % segments.count
        light()
        onSelect(selected)
    }

    private func light() {
        for (index, segment) in segments.enumerated() {
            segment.fillColor = .init(white: 1, alpha: index == selected ? 0.5 : 0.1)
        }
    }
}
