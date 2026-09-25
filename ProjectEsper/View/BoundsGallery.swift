import SpriteKit
import UIKit
import EsperSim

/// The bounds gallery: each vehicle blown up with a grid of eight-pixel blocks over it, to
/// be filled in like bricks for where it's solid. A tap adds or takes away a block; the
/// arrows go through the vehicles; RESET puts one back to its measured outline; COPY puts
/// the whole table on the clipboard as Swift, for `Vehicle.set`. Edits are kept between
/// launches and stand in for the cars' shapes live, offline.
final class BoundsGallery: SKNode {
    private static let saved = "esper.vehicleBlocks"
    private var index = 0
    private let halfWidth: CGFloat, halfHeight: CGFloat
    private let onChange: () -> Void
    private let onClose: () -> Void
    private let board = SKNode()
    private var buttons: [(node: SKNode, action: () -> Void)] = []
    private var cells: [[SKSpriteNode]] = []
    private var cellSide: CGFloat = 1
    private var origin = CGPoint.zero

    init(halfWidth: CGFloat, halfHeight: CGFloat, onChange: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.onChange = onChange
        self.onClose = onClose
        super.init()
        zPosition = 500
        let backdrop = SKSpriteNode(color: SKColor(white: 0.08, alpha: 0.94), size: CGSize(width: halfWidth * 2, height: halfHeight * 2))
        addChild(backdrop)
        addChild(board)
        let labels: [(String, () -> Void)] = [
            ("\u{25C0}", { [weak self] in self?.step(-1) }), ("\u{25B6}", { [weak self] in self?.step(1) }),
            ("RESET", { [weak self] in self?.reset() }), ("COPY", { [weak self] in self?.copy() }),
            ("CLOSE", { [weak self] in self?.onClose() }),
        ]
        for (slot, (title, action)) in labels.enumerated() {
            let button = TitleText.node(title, size: 18)
            button.position = CGPoint(x: -halfWidth * 0.6 + CGFloat(slot) * halfWidth * 0.3, y: -halfHeight + 30)
            addChild(button)
            buttons.append((button, action))
        }
        show()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The edits kept from before, into the sim's table.
    static func loadSaved() {
        guard let data = UserDefaults.standard.data(forKey: saved),
              let table = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        for vehicle in Vehicle.allCases { if let rows = table[vehicle.art] { Vehicle.edited[vehicle] = rows } }
    }

    private func store() {
        let table = Dictionary(uniqueKeysWithValues: Vehicle.edited.map { ($0.key.art, $0.value) })
        if let data = try? JSONEncoder().encode(table) { UserDefaults.standard.set(data, forKey: BoundsGallery.saved) }
        onChange()
    }

    private var vehicle: Vehicle { Vehicle.allCases[index] }

    private func step(_ by: Int) {
        index = (index + by + Vehicle.allCases.count) % Vehicle.allCases.count
        show()
    }

    private func reset() {
        Vehicle.edited[vehicle] = nil
        store()
        show()
    }

    /// The whole table as Swift, for `Vehicle.set`.
    private func copy() {
        var lines = ["    public static let set: [Vehicle: [String]] = ["]
        for vehicle in Vehicle.allCases {
            let rows = vehicle.blocks.map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("        .\(vehicle): [\(rows)],")
        }
        lines.append("    ]")
        UIPasteboard.general.string = lines.joined(separator: "\n")
    }

    /// The vehicle, its name, and its grid of blocks over it.
    private func show() {
        board.removeAllChildren()
        cells = []
        let columns = vehicle.blockColumns, rows = vehicle.blockRows
        cellSide = min(halfWidth * 1.5 / CGFloat(columns), halfHeight * 1.2 / CGFloat(rows)).rounded(.down)
        let width = cellSide * CGFloat(columns), height = cellSide * CGFloat(rows)
        origin = CGPoint(x: -width / 2, y: -height / 2 + 20)
        let name = TitleText.node(vehicle.art.uppercased() + "  \(index + 1)/\(Vehicle.allCases.count)", size: 16)
        name.position = CGPoint(x: 0, y: halfHeight - 30)
        board.addChild(name)
        // The drawing, its art's rows filling the grid's height; it's drawn a block taller
        // at most, so its roof lies under the top row.
        let artHeight = CGFloat(vehicle.size.y) / CGFloat(Vehicle.blockSize) * cellSide
        for part in ["body", "wheels"] {
            guard let texture = HighwayArt.texture("vehicle_\(vehicle.art)_\(part)", art: vehicle.art) else { continue }
            let sprite = SKSpriteNode(texture: texture)
            sprite.size = CGSize(width: width, height: artHeight)
            sprite.anchorPoint = .zero
            sprite.position = origin
            board.addChild(sprite)
        }
        let blocks = vehicle.blocks.map { Array($0) }
        for row in 0..<rows {
            var line: [SKSpriteNode] = []
            for column in 0..<columns {
                let cell = SKSpriteNode(color: SKColor(red: 0.2, green: 1, blue: 0.4, alpha: 1), size: CGSize(width: cellSide - 1, height: cellSide - 1))
                cell.anchorPoint = .zero
                cell.position = CGPoint(x: origin.x + CGFloat(column) * cellSide, y: origin.y + CGFloat(rows - 1 - row) * cellSide)
                let solid = row < blocks.count && column < blocks[row].count && blocks[row][column] == "#"
                cell.alpha = solid ? 0.45 : 0.08
                board.addChild(cell)
                line.append(cell)
            }
            cells.append(line)
        }
    }

    /// True when the gallery took the tap, which it always does while it's open.
    func tap(at point: CGPoint) -> Bool {
        for button in buttons where button.node.frame.insetBy(dx: -12, dy: -12).contains(point) {
            button.action()
            return true
        }
        let column = Int(((point.x - origin.x) / cellSide).rounded(.down))
        let fromBottom = Int(((point.y - origin.y) / cellSide).rounded(.down))
        let rows = vehicle.blockRows
        let row = rows - 1 - fromBottom
        guard column >= 0, column < vehicle.blockColumns, row >= 0, row < rows else { return true }
        var blocks = vehicle.blocks.map { Array($0) }
        while blocks.count < rows { blocks.append(Array(repeating: ".", count: vehicle.blockColumns)) }
        blocks[row][column] = blocks[row][column] == "#" ? "." : "#"
        Vehicle.edited[vehicle] = blocks.map { String($0) }
        cells[row][column].alpha = blocks[row][column] == "#" ? 0.45 : 0.08
        store()
        return true
    }
}
