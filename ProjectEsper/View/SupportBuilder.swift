import SpriteKit
import UIKit

#if !os(tvOS)
/// The hoop support builder, on the Wreck Center: `hoop_support` pieces laid out round the right
/// hoop, its mirror drawn at the left one as it goes. Press where nothing is to put a piece down
/// there, in the kind picked (LIGHT, or DARK, ramped down, each whole or half as long); press a
/// piece to pick it, and drag to move it. The arrows nudge the picked one a pixel, TURN turns it,
/// FWD and BACK move it a step up or down the layering, DEL takes it away, UNDO steps back. RIM DROP
/// and RIM DEPTH move the whole hoop, backboard and net with it; BLOCK X and BLOCK Y the blocks
/// that hold them, by whole tiles, toward the wall and up. COPY puts the layout on the
/// clipboard as Swift for `HoopSupport.baked`. The match holds still meanwhile.
final class SupportBuilder: SKNode {
    private var pieces: [HoopSupport.Piece]
    private var picked: Int?
    private var dark = false
    private var half = false
    /// The layouts before each change, newest last.
    private var history: [[HoopSupport.Piece]] = []
    /// The piece being dragged and how far the press was from its middle, in art pixels.
    private var dragging: (index: Int, offset: CGPoint)?
    private var draggedSlider: Slider?
    /// A HUD point as art pixels from the right hoop's art point, and back.
    private let fromHud: (CGPoint) -> CGPoint
    private let toHud: (CGPoint) -> CGPoint
    private let artPixelsPerHud: CGFloat
    private let onChange: ([HoopSupport.Piece]) -> Void
    private let onMoveRims: (Double?, Double?) -> Void
    private let onMoveBlocks: (Int?, Int?) -> Void
    private let onClose: () -> Void
    private var buttons: [(node: SKNode, action: () -> Void)] = []
    private var kindButtons: [(node: SKSpriteNode, dark: Bool, half: Bool)] = []
    private var sliders: [Slider] = []
    private var turnSlider: Slider?
    private let outline = SKShapeNode()

    /// Laid out about the middle from `top` down: the kinds and buttons, then the sliders.
    init(top: CGFloat, artPixelsPerHud: CGFloat, rimDrop: Double, rimDepth: Double,
         blockShift: (toWall: Int, up: Int),
         fromHud: @escaping (CGPoint) -> CGPoint, toHud: @escaping (CGPoint) -> CGPoint,
         onChange: @escaping ([HoopSupport.Piece]) -> Void, onMoveRims: @escaping (Double?, Double?) -> Void,
         onMoveBlocks: @escaping (Int?, Int?) -> Void, onClose: @escaping () -> Void) {
        pieces = HoopSupport.pieces
        self.artPixelsPerHud = artPixelsPerHud
        self.fromHud = fromHud
        self.toHud = toHud
        self.onChange = onChange
        self.onMoveRims = onMoveRims
        self.onMoveBlocks = onMoveBlocks
        self.onClose = onClose
        super.init()
        zPosition = 500
        outline.strokeColor = SKColor(red: 1, green: 0.8, blue: 0.2, alpha: 0.9)
        outline.lineWidth = 1
        outline.fillColor = .clear
        addChild(outline)

        // A row of the two kinds, the nudges and the rest, centred.
        let rowY = top - 16
        var row: [(node: SKNode, width: CGFloat)] = []
        for (kindIsDark, kindIsHalf) in [(false, false), (true, false), (false, true), (true, true)] {
            let picture = HoopSupport.picture(dark: kindIsDark, half: kindIsHalf)
            let swatch = SKSpriteNode(texture: picture.map { SKTexture(cgImage: $0) })
            swatch.texture?.filteringMode = .nearest
            swatch.size = CGSize(width: kindIsHalf ? 12 : 24, height: 24)
            let label = TitleText.node((kindIsDark ? "DARK" : "LIGHT") + (kindIsHalf ? " \u{00BD}" : ""), size: 7)
            label.position = CGPoint(x: 0, y: -14)
            swatch.addChild(label)
            addChild(swatch)
            kindButtons.append((swatch, kindIsDark, kindIsHalf))
            row.append((swatch, 34))
        }
        let labels: [(String, () -> Void)] = [
            ("\u{25C0}", { [weak self] in self?.nudge(-1, 0) }), ("\u{25B2}", { [weak self] in self?.nudge(0, 1) }),
            ("\u{25BC}", { [weak self] in self?.nudge(0, -1) }), ("\u{25B6}", { [weak self] in self?.nudge(1, 0) }),
            ("FWD", { [weak self] in self?.layer(1) }), ("BACK", { [weak self] in self?.layer(-1) }),
            ("DEL", { [weak self] in self?.deletePicked() }), ("UNDO", { [weak self] in self?.undo() }),
            ("COPY", { [weak self] in self?.copy() }), ("DONE", { [weak self] in self?.onClose() }),
        ]
        for (title, action) in labels {
            let button = TitleText.node(title, size: 12)
            addChild(button)
            buttons.append((button, action))
            row.append((button, button.size.width))
        }
        let gap: CGFloat = 10
        var x = -(row.reduce(0) { $0 + $1.width } + gap * CGFloat(row.count - 1)) / 2
        for item in row {
            item.node.position = CGPoint(x: x + item.width / 2, y: rowY)
            x += item.width + gap
        }
        // Under it, the turn and the hoop's place, side by side about the middle.
        let turn = Slider(title: "TURN", range: -180...180, notch: 1, value: 0) { [weak self] value in self?.turnPicked(to: Int(value)) }
        let drop = Slider(title: "RIM DROP", range: 0...40, notch: 1, value: Float(rimDrop)) { [weak self] in
            self?.onMoveRims(Double($0), nil)
            self?.show()
        }
        let depth = Slider(title: "RIM DEPTH", range: -20...20, notch: 1, value: Float(rimDepth)) { [weak self] in
            self?.onMoveRims(nil, Double($0))
            self?.show()
        }
        // The backboard blocks, whole tiles, toward the wall and up.
        let blockX = Slider(title: "BLOCK X", range: -10...2, notch: 1, value: Float(blockShift.toWall)) { [weak self] in self?.onMoveBlocks(Int($0), nil) }
        let blockY = Slider(title: "BLOCK Y", range: -7...5, notch: 1, value: Float(blockShift.up)) { [weak self] in self?.onMoveBlocks(nil, Int($0)) }
        for (slot, slider) in [turn, drop, depth, blockX, blockY].enumerated() {
            let column = CGFloat(slot % 3) - 1, line = CGFloat(slot / 3)
            slider.position = CGPoint(x: column * (Slider.size.width + 14), y: rowY - 38 - line * 22)
            addChild(slider)
            sliders.append(slider)
        }
        turnSlider = turn
        show()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The picked kind lit, and an outline round the picked piece.
    private func show() {
        for (node, kindIsDark, kindIsHalf) in kindButtons { node.alpha = kindIsDark == dark && kindIsHalf == half ? 1 : 0.4 }
        guard let picked, pieces.indices.contains(picked) else {
            outline.isHidden = true
            return
        }
        let piece = pieces[picked]
        let side = 32 / artPixelsPerHud, width = piece.half ? side / 2 : side
        let path = CGMutablePath()
        path.addRect(CGRect(x: -width / 2, y: -side / 2, width: width, height: side))
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

    /// The layout as it is, for UNDO to come back to.
    private func remember() {
        history.append(pieces)
        if history.count > 200 { history.removeFirst() }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        pieces = last
        if let picked, !pieces.indices.contains(picked) { self.picked = nil }
        changed()
    }

    /// The picked piece a step later in the drawing, over the next, or earlier, under it.
    private func layer(_ by: Int) {
        guard let picked, pieces.indices.contains(picked), pieces.indices.contains(picked + by) else { return }
        remember()
        pieces.swapAt(picked, picked + by)
        self.picked = picked + by
        changed()
    }

    private func nudge(_ dx: Int, _ dy: Int) {
        guard let picked, pieces.indices.contains(picked) else { return }
        remember()
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
        remember()
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
        for (node, kindIsDark, kindIsHalf) in kindButtons where node.frame.insetBy(dx: -6, dy: -6).contains(point) {
            dark = kindIsDark
            half = kindIsHalf
            show()
            return
        }
        if let slider = sliders.first(where: { $0.covers(point - $0.position) }) {
            // A turn is one step back for UNDO, however far it's dragged.
            if slider === turnSlider, picked != nil { remember() }
            draggedSlider = slider
            slider.drag(to: point - slider.position)
            return
        }
        let art = fromHud(point)
        if let index = piece(at: art) {
            remember()
            picked = index
            dragging = (index, CGPoint(x: art.x - CGFloat(pieces[index].x), y: art.y - CGFloat(pieces[index].y)))
            show()
            return
        }
        remember()
        pieces.append(.init(dark: dark, half: half, x: Int(art.x.rounded()), y: Int(art.y.rounded()), rotation: 0))
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
