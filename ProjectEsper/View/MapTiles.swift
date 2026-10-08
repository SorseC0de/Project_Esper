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
        // Stood on its wheels' line, so it tips about them.
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.size = CGSize(width: 16, height: 32)
        node.zPosition = 5
        let wheelArt = SKTexture(rect: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 0.25), in: sheet)
        let wheels = [-4, 4].map { x -> SKSpriteNode in
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

    /// The hoopcase on its 48 by 48 canvas: the suitcase's middle 17 in from the left; the
    /// suitcase's top row 15 down from the canvas's top, its lowest row 39; the ring's centre 33
    /// down, its front half (over the net and the ball) from row 34. The top `caseMaskRows` of
    /// the suitcase are never drawn: the case rotates about that line and slides out past it.
    static let hoopcaseCanvas: CGFloat = 48
    static let hoopcaseRing = CGPoint(x: 17, y: 33)
    static let caseTopRow: CGFloat = 15
    static let caseBottomRow: CGFloat = 40
    static let caseFrontRow: CGFloat = 34
    static let caseMaskRows: CGFloat = 3
    /// How much of the plane's lean the hanging case takes, swinging about its top.
    static let caseSwing: CGFloat = 0.5

    /// The case's two sprites for a slide of `out` (0 in the bin to 1 hanging): the back, the
    /// suitcase and the ring's back half, and the front, the ring's front half; each cut to the
    /// rows below the mask line as the case stands now, their sizes with them. Sized and
    /// positioned to hang from `anchor` (the mask line, at the suitcase's middle), turned by `swing`.
    static func layCase(back: SKSpriteNode, front: SKSpriteNode, sheet: SKTexture, out: CGFloat, anchor: CGPoint, swing: CGFloat) {
        let caseRows = caseBottomRow - caseTopRow
        // The case's top row, as it stands: slid up into the bin by what's not out yet.
        let top = caseTopRow - (1 - out) * caseRows
        let line = caseTopRow + caseMaskRows
        func cut(_ node: SKSpriteNode, from first: CGFloat, to last: CGFloat) {
            // Rows of the canvas, top down, kept below the line; the sprite holds what's left.
            let firstKept = max(first, line), lastKept = last
            let rows = lastKept - firstKept
            node.isHidden = rows <= 0
            guard rows > 0 else { return }
            let height = hoopcaseCanvas
            node.texture = SKTexture(rect: CGRect(x: 0, y: (height - lastKept) / height, width: 1, height: rows / height), in: sheet)
            node.size = CGSize(width: hoopcaseCanvas, height: rows)
            node.anchorPoint = CGPoint(x: hoopcaseRing.x / hoopcaseCanvas, y: 1)
            // Its top sits this far under the line, turned with the case about the line.
            let drop = firstKept - line
            node.position = CGPoint(x: anchor.x + drop * sin(swing), y: anchor.y - drop * cos(swing))
            node.zRotation = swing
        }
        let frontTop = top + (caseFrontRow - caseTopRow)
        cut(back, from: top, to: frontTop)
        cut(front, from: frontTop, to: top + caseRows)
    }

    /// A hoopcase in a side's colours: the suitcase's main grey, as drawn, becomes the energy's
    /// glow and its lighter grey the glow lifted as a body's is; the ring and the lines stay.
    /// Cached by colour.
    nonisolated(unsafe) private static var hoopcases: [String: SKTexture] = [:]
    static func hoopcase(glow: SKColor, lifted: SKColor) -> SKTexture? {
        let key = "\(glow)|\(lifted)"
        if let made = hoopcases[key] { return made }
        guard let image = UIImage(named: "Hoopcase")?.cgImage else { return nil }
        let width = image.width, height = image.height
        func bytes(_ colour: SKColor) -> (UInt8, UInt8, UInt8) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            colour.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (UInt8((r * 255).rounded()), UInt8((g * 255).rounded()), UInt8((b * 255).rounded()))
        }
        let light = bytes(lifted), dark = bytes(glow)
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
    static func noDunkingSign(into parent: SKNode) -> (holder: SKNode, sprites: [SKSpriteNode]) {
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
        // The "no" drawn once as a picture, so the glow can be told of it as of the sign.
        let no = SKSpriteNode(texture: noTexture)
        no.size = CGSize(width: noRadius * 2 + 4, height: noRadius * 2 + 4)
        no.zPosition = 0.1
        holder.addChild(no)
        parent.addChild(holder)
        SKTexture.preload([texture, noTexture]) {}
        return (holder, [sign, no])
    }
    static let noRadius: CGFloat = 16
    /// Red, lifted enough to pass the glow's threshold.
    static let noRed = SKColor(red: 1, green: 0.16, blue: 0.16, alpha: 1)
    /// The ring and the slash, red, on a clear square.
    static let noTexture: SKTexture = {
        let side = noRadius * 2 + 4
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(noRed.cgColor)
            cg.setLineWidth(2)
            cg.setLineCap(.round)
            cg.strokeEllipse(in: CGRect(x: 2, y: 2, width: noRadius * 2, height: noRadius * 2))
            let across = noRadius * 0.7071
            cg.move(to: CGPoint(x: side / 2 - across, y: side / 2 - across))
            cg.addLine(to: CGPoint(x: side / 2 + across, y: side / 2 + across))
            cg.strokePath()
        }
        return SKTexture(image: image)
    }()
    /// The sign's size, the NO DUNK SCALE slider's, kept between launches.
    static let signScaleKey = "esper.flightB411.signScale"
    nonisolated(unsafe) static var signScale: CGFloat = {
        CGFloat(UserDefaults.standard.object(forKey: signScaleKey) as? Double ?? 1)
    }()
    /// How much of the plane's lean the cart tips, about its wheels, and how much its speed.
    static let cartLean: CGFloat = 0.25
    static let cartSpeedTip: CGFloat = 0.03

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
