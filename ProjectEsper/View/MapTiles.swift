import EsperSim
import SpriteKit

/// A hand-laid stage's tiles, for drawing it and for the map maker: its sheets, each cut into
/// square cells of its own size, a placed tile's art cell counting across the sheets side by
/// side, `stride` columns kept for each. Every cell is drawn one tile, 16 art pixels, whatever its size.
final class MapTiles {
    let sheets: [SKTexture]
    private let cellSizes: [CGFloat]
    let stride: Int
    private var cut: [StageMap.Cell: SKTexture] = [:]
    private var filledBySheet: [Int: [StageMap.Cell]] = [:]

    private init(sheets: [SKTexture], cellSizes: [CGFloat], stride: Int? = nil) {
        self.sheets = sheets
        self.cellSizes = cellSizes
        self.stride = stride ?? max(Int((sheets.first?.size().width ?? cellSizes[0]) / cellSizes[0]), 1)
    }

    /// The Elements' one 16-pixel sheet, and Flight's twelve: the floors, the walls, the B sheets
    /// and the five more, all of 48-pixel cells but the walls' and "2"'s, of 32.
    static let elements = MapTiles(sheets: [ElementsArt.tileset], cellSizes: [ElementsArt.tileSide])
    static let flight = MapTiles(sheets: (0..<12).map { index in
        let texture = SKTexture(imageNamed: "FlightTiles\(index)")
        // Painted, not pixel art: smoothed when it's drawn smaller than its own pixels.
        texture.filteringMode = .linear
        return texture
    }, cellSizes: (0..<12).map { [1, 8].contains($0) ? 32 : 48 }, stride: flightStride)
    /// Flight's columns kept for each sheet: room for a 32-pixel sheet's 24. Maps kept when each
    /// sheet had 16 are moved over once (`SavedStageMap`).
    static let flightStride = 32

    static func of(_ stage: MapStage) -> MapTiles { stage == .flight ? flight : elements }

    func cellPixels(of sheet: Int) -> CGFloat { cellSizes[sheet] }
    func sheet(of art: StageMap.Cell) -> Int { art.column / stride }
    func columns(of sheet: Int) -> Int { max(Int(sheets[sheet].size().width / cellSizes[sheet]), 1) }
    func rows(of sheet: Int) -> Int { max(Int(sheets[sheet].size().height / cellSizes[sheet]), 1) }

    /// One cell, by its art cell across all the sheets.
    func tile(_ art: StageMap.Cell) -> SKTexture {
        if let made = cut[art] { return made }
        let index = min(sheet(of: art), sheets.count - 1)
        let sheet = sheets[index]
        let columns = CGFloat(self.columns(of: index)), rows = CGFloat(self.rows(of: index))
        let column = CGFloat(art.column - index * stride)
        let rect = CGRect(x: column / columns, y: (rows - 1 - CGFloat(art.row)) / rows, width: 1 / columns, height: 1 / rows)
        let texture = SKTexture(rect: rect, in: sheet)
        texture.filteringMode = sheet.filteringMode
        cut[art] = texture
        return texture
    }

    /// A sheet's cells with anything drawn in them, as art cells: what the map maker offers.
    func filled(sheet index: Int) -> [StageMap.Cell] {
        if let found = filledBySheet[index] { return found }
        let image = sheets[index].cgImage()
        var cells: [StageMap.Cell] = []
        if let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
           let data = context.data {
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
            let side = Int(cellSizes[index])
            for row in 0..<(image.height / side) {
                for column in 0..<(image.width / side) {
                    let drawn = (0..<side).contains { y in (0..<side).contains { x in pixels[((row * side + y) * image.width + column * side + x) * 4 + 3] > 0 } }
                    if drawn { cells.append(StageMap.Cell(index * stride + column, row)) }
                }
            }
        }
        filledBySheet[index] = cells
        return cells
    }
}

/// Where a placed tile's sprite is: its cell and its layer.
struct TileSpot: Hashable {
    var cell: StageMap.Cell
    var layer: Int
    /// The ground layer under everything on the stage but the backdrop, the layer over it just above.
    static func z(_ layer: Int) -> CGFloat { -8 + CGFloat(layer) * 0.1 }
}

/// Flight's scenery: a sprite for every tile the map has placed, cut from its sheets.
enum FlightArt {
    /// What the stage's art gives back: each placed tile's sprite by its cell, to be changed by the map maker.
    struct Handles {
        var tiles: [TileSpot: SKSpriteNode] = [:]
        let parent: SKNode

        mutating func set(_ placed: StageMap.Placed?, at cell: StageMap.Cell, layer: Int) {
            let spot = TileSpot(cell: cell, layer: layer)
            tiles[spot]?.removeFromParent()
            tiles[spot] = nil
            // Only on the stage: a map kept from when it was bigger may have tiles past its edges.
            guard let placed, (0..<FlightRules.columns).contains(cell.column), (0..<FlightRules.rows).contains(cell.row) else { return }
            let node = SKSpriteNode(texture: MapTiles.flight.tile(placed.art))
            node.size = CGSize(width: ElementsArt.tileSide, height: ElementsArt.tileSide)
            node.anchorPoint = .zero
            node.position = CGPoint(x: CGFloat(cell.column) * ElementsArt.tileSide, y: CGFloat(cell.row) * ElementsArt.tileSide)
            node.zPosition = TileSpot.z(layer)
            parent.addChild(node)
            tiles[spot] = node
        }
    }

    static func build(map: StageMap, into parent: SKNode) -> Handles {
        var handles = Handles(parent: parent)
        for placed in map.tiles { handles.set(placed, at: placed.cell, layer: placed.layer) }
        return handles
    }
}
