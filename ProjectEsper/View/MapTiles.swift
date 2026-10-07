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

    /// The Elements' one 16-pixel sheet.
    static let elements = MapTiles(sheets: [ElementsArt.tileset], cellSizes: [ElementsArt.tileSide])

    static func of(_ stage: MapStage) -> MapTiles { elements }

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

/// Flight's scenery: the stage drawn whole in Aseprite (`Flight_Map.aseprite`, 1248 by 576, four
/// of its pixels to an art pixel, flattened by `Tools/aseprite.py`) in two pictures, the whole
/// stage each: `FlightBackdrop`, its layers up to the open bin, behind the players; and
/// `FlightFront`, the front chairs and the fade over them, in front of the players. The file's
/// hidden Player layer sits between the two, and is where the players draw.
enum FlightArt {
    struct Handles {
        var backdrop: SKSpriteNode?
        var front: SKSpriteNode?
    }

    /// Past the stage's edges, above, below and beside it as it leans: palette 30.
    static let beyond: RGB = PixelPalette.colours[30]
    /// Under everything else on the stage; the pictures' pixels to an art pixel.
    static let backdropZ: CGFloat = -7.8
    static let backdropScale: CGFloat = 4

    /// The backdrop into `parent` on the stage's ground, the front into `front`, over the players.
    /// The cart's sheet, `Cart`: 48 by 64 drawn at 2x, so 24 by 32 art pixels in 8-pixel cells;
    /// the cart its first two columns, 16 by 32, standing on its box's bottom left; the wheel the
    /// bottom right cell, two of them centred on the cart's bottom two cells, a pixel down. The
    /// wheels turn by the cart's rolling.
    static let wheelRadius: CGFloat = 3.5
    static func cart() -> (node: SKSpriteNode, wheels: [SKSpriteNode]) {
        let sheet = SKTexture(imageNamed: "Cart")
        sheet.filteringMode = .nearest
        let body = SKTexture(rect: CGRect(x: 0, y: 0, width: 2 / 3, height: 1), in: sheet)
        let node = SKSpriteNode(texture: body)
        node.anchorPoint = .zero
        node.size = CGSize(width: 16, height: 32)
        node.zPosition = 5
        let wheelArt = SKTexture(rect: CGRect(x: 2 / 3, y: 0, width: 1 / 3, height: 1 / 4), in: sheet)
        let wheels = [4, 12].map { x -> SKSpriteNode in
            let wheel = SKSpriteNode(texture: wheelArt)
            wheel.size = CGSize(width: 8, height: 8)
            wheel.position = CGPoint(x: x, y: 4 - 1)
            wheel.zPosition = 0.1
            node.addChild(wheel)
            return wheel
        }
        return (node, wheels)
    }

    static func build(into parent: SKNode, front frontParent: SKNode) -> Handles {
        var handles = Handles()
        func picture(_ name: String, z: CGFloat, into parent: SKNode) -> SKSpriteNode {
            let texture = SKTexture(imageNamed: name)
            texture.filteringMode = .nearest
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = .zero
            node.size = CGSize(width: texture.size().width / backdropScale, height: texture.size().height / backdropScale)
            node.position = CGPoint(x: ((CGFloat(FlightRules.width / Stage.tileSize) * ElementsArt.tileSide - node.size.width) / 2).rounded(), y: 0)
            node.zPosition = z
            parent.addChild(node)
            return node
        }
        handles.backdrop = picture("FlightBackdrop", z: backdropZ, into: parent)
        handles.front = picture("FlightFront", z: 0, into: frontParent)
        return handles
    }
}
