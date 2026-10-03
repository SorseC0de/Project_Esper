import SpriteKit

/// The FLO word's colours, picked in the match's bottom corner: a tone's button along the top,
/// FILL TOP, FILL BTM, LINE TOP or LINE BTM, then every swatch of the UI palette under it, as the
/// title's grids have them, its twelve ramps two to a row on a black plate, the pick ringed white.
/// A press on the picked swatch takes the pick back, to the standard colour.
final class FloColourPicker: SKNode {
    private var tone = FloTuning.Tone.fillTop
    private var toneButtons: [(node: SKSpriteNode, tone: FloTuning.Tone)] = []
    private var swatches: [(node: SKSpriteNode, index: Int)] = []
    private let ring = SKShapeNode()
    private let onChange: () -> Void

    /// Laid out up and to the right from its bottom left, at `origin`.
    init(origin: CGPoint, onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
        position = origin
        zPosition = 7
        let size = SwatchGrid.swatchSize
        let rowGap = size * 0.3, halfGap = size * 0.6, pad = size * 0.8
        let rows = EsperPalette.ramps.count / 2
        let gridWidth = size * 8 + halfGap, gridHeight = CGFloat(rows) * size + CGFloat(rows - 1) * rowGap
        // The tones' buttons, a row over the grid.
        let buttonHeight: CGFloat = 12, buttonGap: CGFloat = 3
        let buttonWidth = (gridWidth + pad * 2 - buttonGap * 3) / 4
        let plate = UIPiece.buttonBlack.node(size: CGSize(width: gridWidth + pad * 2, height: gridHeight + pad * 2))
        plate.anchorPoint = .zero
        // Depths set apart: the HUD draws siblings in no set order.
        plate.zPosition = -1
        addChild(plate)
        for (slot, tone) in FloTuning.Tone.allCases.enumerated() {
            let button = SKSpriteNode(color: SKColor(white: 0.1, alpha: 0.9), size: CGSize(width: buttonWidth, height: buttonHeight))
            button.anchorPoint = .zero
            button.position = CGPoint(x: CGFloat(slot) * (buttonWidth + buttonGap), y: gridHeight + pad * 2 + 3)
            let label = TitleText.node(tone.label, size: 5)
            label.position = CGPoint(x: buttonWidth / 2, y: buttonHeight / 2)
            label.zPosition = 1
            button.addChild(label)
            addChild(button)
            toneButtons.append((button, tone))
        }
        for row in 0..<rows {
            for half in 0..<2 {
                for shade in 0..<4 {
                    let index = (row * 2 + half) * 4 + shade
                    let swatch = SKSpriteNode(color: SKColor(rgb: EsperPalette.swatches[index]), size: CGSize(width: size, height: size))
                    swatch.anchorPoint = .zero
                    swatch.zPosition = 1
                    swatch.position = CGPoint(x: pad + CGFloat(half) * (size * 4 + halfGap) + CGFloat(shade) * size,
                                              y: pad + gridHeight - size - CGFloat(row) * (size + rowGap))
                    addChild(swatch)
                    swatches.append((swatch, index))
                }
            }
        }
        ring.strokeColor = .white
        ring.lineWidth = 1.5
        ring.fillColor = .clear
        ring.zPosition = 2
        ring.path = CGPath(rect: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
        addChild(ring)
        show()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The picked tone's button lit, its swatch ringed.
    private func show() {
        for (node, buttonTone) in toneButtons {
            node.color = buttonTone == tone ? SKColor(rgb: EsperPalette.gold.body) : SKColor(white: 0.1, alpha: 0.9)
        }
        if let picked = FloTuning.index(tone), let swatch = swatches.first(where: { $0.index == picked }) {
            ring.position = swatch.node.position
            ring.isHidden = false
        } else {
            ring.isHidden = true
        }
    }

    /// True when the press, a HUD point, landed on it.
    func tap(at point: CGPoint) -> Bool {
        let local = CGPoint(x: point.x - position.x, y: point.y - position.y)
        if let button = toneButtons.first(where: { $0.node.frame.contains(local) }) {
            tone = button.tone
            show()
            return true
        }
        if let swatch = swatches.first(where: { $0.node.frame.contains(local) }) {
            FloTuning.toggle(tone, swatch.index)
            show()
            onChange()
            return true
        }
        return calculateAccumulatedFrame().contains(point)
    }
}
