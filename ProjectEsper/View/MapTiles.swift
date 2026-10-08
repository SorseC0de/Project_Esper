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

/// Flight B411's scenery: the stage drawn whole in Aseprite (`Flight_Map.aseprite`, 1248 by 576, four
/// of its pixels to an art pixel, flattened by `Tools/aseprite.py`) in two pictures, the whole
/// stage each: `FlightB411Backdrop`, its layers up to the open bin, behind the players; and
/// `FlightB411Front`, the front chairs and the fade over them, in front of the players. The file's
/// hidden Player layer sits between the two, and is where the players draw.
enum FlightB411Art {
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
        let body = SKTexture(rect: CGRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1), in: sheet)
        let node = SKSpriteNode(texture: body)
        node.anchorPoint = .zero
        node.size = CGSize(width: 16, height: 32)
        node.zPosition = 5
        let wheelArt = SKTexture(rect: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 0.25), in: sheet)
        let wheels = [4, 12].map { x -> SKSpriteNode in
            let wheel = SKSpriteNode(texture: wheelArt)
            wheel.size = CGSize(width: 8, height: 8)
            wheel.position = CGPoint(x: x, y: 4 - 1)
            wheel.zPosition = 0.1
            node.addChild(wheel)
            return wheel
        }
        // A texture draws as a blank square until it's reached the GPU, and these cuts of the
        // sheet aren't among what's warmed before play: loaded first, the cart hidden till then.
        node.isHidden = true
        SKTexture.preload([sheet, body, wheelArt]) { DispatchQueue.main.async { node.isHidden = false } }
        return (node, wheels)
    }

    /// The bins' open doors, `FlightB411OpenBin` (the file's Open Bin layer, 45 by 19 art pixels),
    /// one over each whole bin, its bottom left on the bin's, shown while the bin's open.
    static func openBins(into parent: SKNode) -> [SKSpriteNode] {
        let texture = SKTexture(imageNamed: "FlightB411OpenBin")
        texture.filteringMode = .nearest
        let doors = FlightB411Rules.binLefts.map { left -> SKSpriteNode in
            let door = SKSpriteNode(texture: texture)
            door.anchorPoint = .zero
            door.size = CGSize(width: 45, height: 19)
            door.position = CGPoint(x: (left * SpriteLibrary.pixelsPerUnit).rounded(), y: (FlightB411Rules.binBottom * SpriteLibrary.pixelsPerUnit).rounded())
            door.zPosition = backdropZ + 0.1
            door.isHidden = true
            parent.addChild(door)
            return door
        }
        SKTexture.preload([texture]) {}
        return doors
    }

    /// Where a hoopcase's canvas sits for its ring's centre: the suitcase's middle is 17 in from
    /// the canvas's left, the ring's centre 33 down from its top, on its 48 by 48.
    static let hoopcaseCanvas: CGFloat = 48
    static let hoopcaseRing = CGPoint(x: 17, y: 33)

    /// A hoopcase in a side's colours: the suitcase's two greys, as drawn, become the energy's
    /// glow and its ramp down; the ring and the lines stay. Cached by colour.
    nonisolated(unsafe) private static var hoopcases: [String: SKTexture] = [:]
    static func hoopcase(glow: SKColor, shade: SKColor) -> SKTexture? {
        let key = "\(glow)|\(shade)"
        if let made = hoopcases[key] { return made }
        guard let image = UIImage(named: "Hoopcase")?.cgImage else { return nil }
        let width = image.width, height = image.height
        func bytes(_ colour: SKColor) -> (UInt8, UInt8, UInt8) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            colour.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (UInt8((r * 255).rounded()), UInt8((g * 255).rounded()), UInt8((b * 255).rounded()))
        }
        let light = bytes(glow), dark = bytes(shade)
        // The context's bytes are the array's, so everything with it happens while the array's
        // pointer holds: drawn in, swapped, and the image made before the pointer's scope ends.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let made: CGImage? = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            for index in stride(from: 0, to: data.count, by: 4) where data[index + 3] == 255 {
                let pixel = (data[index], data[index + 1], data[index + 2])
                let swap: (UInt8, UInt8, UInt8)?
                if pixel == (139, 147, 175) { swap = light } else if pixel == (109, 117, 141) { swap = dark } else { swap = nil }
                if let swap { (data[index], data[index + 1], data[index + 2]) = swap }
            }
            return context.makeImage()
        }
        guard let made else { return nil }
        let texture = SKTexture(cgImage: made)
        texture.filteringMode = .nearest
        hoopcases[key] = texture
        return texture
    }

    /// NO DUNKING, in the dark over the bins: the sign in palette 7, glowing, and over it the red
    /// "no", a ring and a slash, glowing too. Centred on the stage, halfway up the band over the bins.
    static func noDunkingSign(into parent: SKNode) -> SKNode {
        let holder = SKNode()
        let centre = CGPoint(x: (CGFloat(FlightB411Rules.width / Stage.tileSize) * ElementsArt.tileSide / 2).rounded(),
                             y: ((FlightB411Rules.binTop * SpriteLibrary.pixelsPerUnit + CGFloat(FlightB411Rules.rows) * ElementsArt.tileSide) / 2).rounded())
        holder.position = centre
        holder.zPosition = backdropZ + 0.2
        let texture = SKTexture(imageNamed: "FlightB411NoDunking")
        texture.filteringMode = .nearest
        let sign = SKSpriteNode(texture: texture)
        sign.size = CGSize(width: 22, height: 24)
        holder.addChild(sign)
        let no = SKShapeNode()
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -noRadius, y: -noRadius, width: noRadius * 2, height: noRadius * 2))
        let across = noRadius * 0.7071
        path.move(to: CGPoint(x: -across, y: across))
        path.addLine(to: CGPoint(x: across, y: -across))
        no.path = path
        no.strokeColor = noRed
        no.lineWidth = 2
        no.lineCap = .round
        no.zPosition = 0.1
        holder.addChild(no)
        parent.addChild(holder)
        SKTexture.preload([texture]) {}
        return holder
    }
    static let noRadius: CGFloat = 16
    /// Red, lifted enough to pass the glow's threshold.
    static let noRed = SKColor(red: 1, green: 0.16, blue: 0.16, alpha: 1)

    /// A cloud, `FlightB411Cloud` (192 by 64), for the sky beyond the plane.
    static let cloud: SKTexture = {
        let texture = SKTexture(imageNamed: "FlightB411Cloud")
        texture.filteringMode = .nearest
        SKTexture.preload([texture]) {}
        return texture
    }()

    static func build(into parent: SKNode, front frontParent: SKNode) -> Handles {
        var handles = Handles()
        func picture(_ name: String, z: CGFloat, into parent: SKNode) -> SKSpriteNode {
            let texture = SKTexture(imageNamed: name)
            texture.filteringMode = .nearest
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = .zero
            node.size = CGSize(width: texture.size().width / backdropScale, height: texture.size().height / backdropScale)
            node.position = CGPoint(x: ((CGFloat(FlightB411Rules.width / Stage.tileSize) * ElementsArt.tileSide - node.size.width) / 2).rounded(), y: 0)
            node.zPosition = z
            parent.addChild(node)
            return node
        }
        handles.backdrop = picture("FlightB411Backdrop", z: backdropZ, into: parent)
        handles.front = picture("FlightB411Front", z: 0, into: frontParent)
        return handles
    }
}
