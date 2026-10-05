import EsperSim
import SpriteKit

/// A hand-laid stage's tiles, for drawing it and for the map maker: its sheets, each cut into
/// square cells `cellPixels` across, a placed tile's art cell counting across the sheets side by
/// side, `columnsPerSheet` to a sheet. Every cell is drawn one tile, 16 art pixels, whatever its size.
final class MapTiles {
    let sheets: [SKTexture]
    let cellPixels: CGFloat
    let columnsPerSheet: Int
    private var cut: [StageMap.Cell: SKTexture] = [:]
    private var filledBySheet: [Int: [StageMap.Cell]] = [:]

    private init(sheets: [SKTexture], cellPixels: CGFloat) {
        self.sheets = sheets
        self.cellPixels = cellPixels
        columnsPerSheet = max(Int((sheets.first?.size().width ?? cellPixels) / cellPixels), 1)
    }

    /// The Elements' one 16-pixel sheet, and Flight's twelve of 48-pixel cells: floors, walls,
    /// then the B sheets and the five more.
    static let elements = MapTiles(sheets: [ElementsArt.tileset], cellPixels: ElementsArt.tileSide)
    static let flight = MapTiles(sheets: (0..<12).map { index in
        let texture = SKTexture(imageNamed: "FlightTiles\(index)")
        // Painted, not pixel art: smoothed when it's drawn smaller than its own pixels.
        texture.filteringMode = .linear
        return texture
    }, cellPixels: 48)

    static func of(_ stage: MapStage) -> MapTiles { stage == .flight ? flight : elements }

    func sheet(of art: StageMap.Cell) -> Int { art.column / columnsPerSheet }
    func rows(of sheet: Int) -> Int { max(Int(sheets[sheet].size().height / cellPixels), 1) }

    /// One cell, by its art cell across all the sheets.
    func tile(_ art: StageMap.Cell) -> SKTexture {
        if let made = cut[art] { return made }
        let index = min(sheet(of: art), sheets.count - 1)
        let sheet = sheets[index]
        let columns = CGFloat(columnsPerSheet), rows = CGFloat(self.rows(of: index))
        let column = CGFloat(art.column - index * columnsPerSheet)
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
            let side = Int(cellPixels)
            for row in 0..<(image.height / side) {
                for column in 0..<(image.width / side) {
                    let drawn = (0..<side).contains { y in (0..<side).contains { x in pixels[((row * side + y) * image.width + column * side + x) * 4 + 3] > 0 } }
                    if drawn { cells.append(StageMap.Cell(index * columnsPerSheet + column, row)) }
                }
            }
        }
        filledBySheet[index] = cells
        return cells
    }
}

/// Flight's scenery: a sprite for every tile the map has placed, cut from its sheets.
enum FlightArt {
    /// What the stage's art gives back: each placed tile's sprite by its cell, to be changed by the map maker.
    struct Handles {
        var tiles: [StageMap.Cell: SKSpriteNode] = [:]
        let parent: SKNode

        mutating func set(_ placed: StageMap.Placed?, at cell: StageMap.Cell) {
            tiles[cell]?.removeFromParent()
            tiles[cell] = nil
            guard let placed else { return }
            let node = SKSpriteNode(texture: MapTiles.flight.tile(placed.art))
            node.size = CGSize(width: ElementsArt.tileSide, height: ElementsArt.tileSide)
            node.anchorPoint = .zero
            node.position = CGPoint(x: CGFloat(cell.column) * ElementsArt.tileSide, y: CGFloat(cell.row) * ElementsArt.tileSide)
            node.zPosition = -8
            parent.addChild(node)
            tiles[cell] = node
        }
    }

    static func build(map: StageMap, into parent: SKNode) -> Handles {
        var handles = Handles(parent: parent)
        for placed in map.tiles { handles.set(placed, at: placed.cell) }
        return handles
    }
}
