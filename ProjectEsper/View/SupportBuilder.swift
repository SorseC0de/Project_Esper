import SpriteKit
import UIKit

#if !os(tvOS)
/// The hoop support builder, on the Wreck Center: `hoop_support` pieces laid out round the right
/// hoop, its mirror drawn at the left one as it goes. Press where nothing is to put a piece down
/// there, in the kind picked (LIGHT, or DARK, ramped down); press a piece to pick it, and drag to
/// move it. The arrows nudge the picked one a pixel, TURN turns it, DEL takes it away. RIM DROP
/// and RIM DEPTH move the whole hoop, backboard and net with it. COPY puts the layout on the
/// clipboard as Swift for `HoopSupport.baked`. The match holds still meanwhile.
final class SupportBuilder: SKNode {
    private var pieces: [HoopSupport.Piece]
    private var picked: Int?
    private var dark = false
    /// The piece being dragged and how far the press was from its middle, in art pixels.
    private var dragging: (index: Int, offset: CGPoint)?
    private var draggedSlider: Slider?
    private let halfWidth: CGFloat, halfHeight: CGFloat
    /// A HUD point as art pixels from the right hoop's art point, and back.
    private let fromHud: (CGPoint) -> CGPoint
    private let toHud: (CGPoint) -> CGPoint
    private let artPixelsPerHud: CGFloat
    private let onChange: ([HoopSupport.Piece]) -> Void
    private let onMoveRims: (Double?, Double?) -> Void
    private let onClose: () -> Void
    private var buttons: [(node: SKNode, action: () -> Void)] = []
    private var kindButtons: [(node: SKSpriteNode, dark: Bool)] = []
    private var sliders: [Slider] = []
    private var turnSlider: Slider?
    private let outline = SKShapeNode()

    init(halfWidth: CGFloat, halfHeight: CGFloat, artPixelsPerHud: CGFloat, rimDrop: Double, rimDepth: Double,
         fromHud: @escaping (CGPoint) -> CGPoint, toHud: @escaping (CGPoint) -> CGPoint,
         onChange: @escaping ([HoopSupport.Piece]) -> Void, onMoveRims: @escaping (Double?, Double?) -> Void, onClose: @escaping () -> Void) {
        pieces = HoopSupport.pieces
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.artPixelsPerHud = artPixelsPerHud
        self.fromHud = fromHud
        self.toHud = toHud
        self.onChange = onChange
        self.onMoveRims = onMoveRims
        self.onClose = onClose
        super.init()
        zPosition = 500
        outline.strokeColor = SKColor(red: 1, green: 0.8, blue: 0.2, alpha: 0.9)
        outline.lineWidth = 1
        outline.fillColor = .clear
        addChild(outline)

        // Along the top: the two kinds, then the nudges and the rest.
        let top = halfHeight - 18
        var x = -halfWidth + 30
        for kindIsDark in [false, true] {
            let swatch = SKSpriteNode(texture: HoopSupport.picture(dark: kindIsDark).map { SKTexture(cgImage: $0) })
            swatch.texture?.filteringMode = .nearest
            swatch.size = CGSize(width: 28, height: 28)
            swatch.position = CGPoint(x: x, y: top)
            addChild(swatch)
            kindButtons.append((swatch, kindIsDark))
            let label = TitleText.node(kindIsDark ? "DARK" : "LIGHT", size: 8)
            label.position = CGPoint(x: x, y: top - 18)
            addChild(label)
            x += 36
        }
        x += 10
        let labels: [(String, () -> Void)] = [
            ("\u{25C0}", { [weak self] in self?.nudge(-1, 0) }), ("\u{25B2}", { [weak self] in self?.nudge(0, 1) }),
            ("\u{25BC}", { [weak self] in self?.nudge(0, -1) }), ("\u{25B6}", { [weak self] in self?.nudge(1, 0) }),
            ("DEL", { [weak self] in self?.deletePicked() }), ("COPY", { [weak self] in self?.copy() }),
            ("DONE", { [weak self] in self?.onClose() }),
        ]
        for (title, action) in labels {
            let button = TitleText.node(title, size: 14)
            button.position = CGPoint(x: x + button.size.width / 2, y: top)
            addChild(button)
            buttons.append((button, action))
            x += button.size.width + 14
        }
        // Down the right: the turn, and the hoop's place.
        let turn = Slider(title: "TURN", range: -180...180, notch: 1, value: 0) { [weak self] value in self?.turnPicked(to: Int(value)) }
        let drop = Slider(title: "RIM DROP", range: 0...40, notch: 1, value: Float(rimDrop)) { [weak self] in self?.onMoveRims(Double($0), nil) }
        let depth = Slider(title: "RIM DEPTH", range: -20...20, notch: 1, value: Float(rimDepth)) { [weak self] in self?.onMoveRims(nil, Double($0)) }
        for (row, slider) in [turn, drop, depth].enumerated() {
            slider.position = CGPoint(x: halfWidth - Slider.size.width / 2 - 20, y: top - 40 - CGFloat(row) * 24)
            addChild(slider)
            sliders.append(slider)
        }
        turnSlider = turn
        show()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The picked kind lit, and an outline round the picked piece.
    private func show() {
        for (node, kindIsDark) in kindButtons { node.alpha = kindIsDark == dark ? 1 : 0.4 }
        guard let picked, pieces.indices.contains(picked) else {
            outline.isHidden = true
            return
        }
        let piece = pieces[picked]
        let side = 32 / artPixelsPerHud
        let path = CGMutablePath()
        path.addRect(CGRect(x: -side / 2, y: -side / 2, width: side, height: side))
        outline.path = path
        outline.position = toHud(CGPoint(x: piece.x, y: piece.y))
        outline.zRotation = CGFloat(piece.rotation) * .pi / 180
        outline.isHidden = false
        turnSlider?.set(Float(piece.rotation))
    }

    private func changed() {
        HoopSupport.pieces = pieces
        onChange(pieces)
        show()
    }

    private func nudge(_ dx: Int, _ dy: Int) {
        guard let picked, pieces.indices.contains(picked) else { return }
        pieces[picked].x += dx
        pieces[picked].y += dy
        changed()
    }

    private func turnPicked(to degrees: Int) {
        guard let picked, pieces.indices.contains(picked) else { return }
        pieces[picked].rotation = degrees
        changed()
    }

    private func deletePicked() {
        guard let picked, pieces.indices.contains(picked) else { return }
        pieces.remove(at: picked)
        self.picked = nil
        changed()
    }

    private func copy() {
        UIPasteboard.general.string = HoopSupport.source(pieces)
    }

    /// The newest piece under a point, within its picture's middle.
    private func piece(at art: CGPoint) -> Int? {
        pieces.lastIndex { abs(CGFloat($0.x) - art.x) <= 10 && abs(CGFloat($0.y) - art.y) <= 10 }
    }

    func began(at point: CGPoint) {
        for button in buttons where button.node.frame.insetBy(dx: -6, dy: -6).contains(point) {
            button.action()
            return
        }
        for (node, kindIsDark) in kindButtons where node.frame.insetBy(dx: -4, dy: -4).contains(point) {
            dark = kindIsDark
            show()
            return
        }
        if let slider = sliders.first(where: { $0.covers(point - $0.position) }) {
            draggedSlider = slider
            slider.drag(to: point - slider.position)
            return
        }
        let art = fromHud(point)
        if let index = piece(at: art) {
            picked = index
            dragging = (index, CGPoint(x: art.x - CGFloat(pieces[index].x), y: art.y - CGFloat(pieces[index].y)))
            show()
            return
        }
        pieces.append(.init(dark: dark, x: Int(art.x.rounded()), y: Int(art.y.rounded()), rotation: 0))
        picked = pieces.count - 1
        dragging = (pieces.count - 1, .zero)
        changed()
    }

    func moved(to point: CGPoint) {
        if let slider = draggedSlider {
            slider.drag(to: point - slider.position)
            return
        }
        guard let dragging, pieces.indices.contains(dragging.index) else { return }
        let art = fromHud(point)
        let x = Int((art.x - dragging.offset.x).rounded()), y = Int((art.y - dragging.offset.y).rounded())
        guard x != pieces[dragging.index].x || y != pieces[dragging.index].y else { return }
        pieces[dragging.index].x = x
        pieces[dragging.index].y = y
        changed()
    }

    func ended(at point: CGPoint) {
        draggedSlider = nil
        dragging = nil
    }
}
#endif
