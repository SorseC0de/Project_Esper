import EsperSim
import SpriteKit

/// The Elements' scenery: the mountains stretched over the stage on a flat ground, a bed of
/// lava along the bottom, and a sprite for every tile the map has placed, cut from the tileset.
enum ElementsArt {
    /// The flat colour behind everything: palette 29.
    static let background: RGB = PixelPalette.colours[29]
    static let tileSide: CGFloat = 16
    static let lavaFrames = 8
    /// The lava's orange below its surface, and the deep purple inside the ceiling's rock.
    static let lavaOrange: UInt32 = 0xFA6A0A
    static let ceilingPurple: UInt32 = 0x403353
    static let lavaSide: CGFloat = 48
    /// Seconds a lava frame shows.
    static let lavaFrameSeconds = 0.18
    static let tornadoFrames = 8
    static let tornadoSide: CGFloat = 48
    /// Seconds a tornado's frame shows: twelve a second.
    static let tornadoFrameSeconds = 1.0 / 12
    /// The icicles' sockets along the ceiling, 32 wide and 48 tall, the art at their tops.
    static let icicleWidth: CGFloat = 32
    static let icicleHeight: CGFloat = 48

    /// The tileset as many cells across and down as the sheet holds, so a bigger sheet is picked up as it is.
    static var tilesetColumns: Int { max(Int(tileset.size().width / tileSide), 1) }
    static var tilesetRows: Int { max(Int(tileset.size().height / tileSide), 1) }

    /// The tileset cells with anything drawn in them, read off the sheet: what the map maker offers.
    static let filled: [ElementsMap.Cell] = {
        let image = tileset.cgImage()
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let side = Int(tileSide)
        var cells: [ElementsMap.Cell] = []
        for row in 0..<(image.height / side) {
            for column in 0..<(image.width / side) {
                let drawn = (0..<side).contains { y in (0..<side).contains { x in pixels[((row * side + y) * image.width + column * side + x) * 4 + 3] > 0 } }
                if drawn { cells.append(ElementsMap.Cell(column, row)) }
            }
        }
        return cells
    }()

    static let tileset: SKTexture = {
        let texture = SKTexture(imageNamed: "ElementsTileset")
        texture.filteringMode = .nearest
        return texture
    }()

    private static var cutTiles: [ElementsMap.Cell: SKTexture] = [:]
    /// One 16 by 16 cell of the tileset.
    static func tile(_ art: ElementsMap.Cell) -> SKTexture {
        if let cut = cutTiles[art] { return cut }
        let columns = CGFloat(tilesetColumns), rows = CGFloat(tilesetRows)
        let rect = CGRect(x: CGFloat(art.column) / columns, y: (rows - 1 - CGFloat(art.row)) / rows, width: 1 / columns, height: 1 / rows)
        let texture = SKTexture(rect: rect, in: tileset)
        texture.filteringMode = .nearest
        cutTiles[art] = texture
        return texture
    }

    /// A tornado's first frame, for the map maker's hand, set as the stage is drawn.
    nonisolated(unsafe) static var tornadoPreview: SKTexture?

    static let mountains: SKTexture = {
        let texture = SKTexture(imageNamed: "ElementsMountains")
        texture.filteringMode = .nearest
        return texture
    }()

    /// What the stage's art gives back: each placed tile's sprite by its cell, to be changed by the map maker.
    struct Handles {
        var tiles: [ElementsMap.Cell: SKSpriteNode] = [:]
        var tornados: [SKSpriteNode] = []
        /// The stage's fixed art, for the glow's mask to leave out: the mountains, the icicles.
        var mountains: SKSpriteNode?
        var icicles: [SKSpriteNode] = []
        /// The rock's deep purple carried on above the ceiling into a taller screen's spare rows.
        var aboveCeiling: SKSpriteNode?
        let parent: SKNode
        let sprites: SpriteLibrary

        /// The tornados as the map has them, drawn whole, each animated on a frame of its own.
        mutating func setTornados(_ bases: [ElementsMap.Cell]) {
            tornados.forEach { $0.removeFromParent() }
            let frames = (0..<ElementsArt.tornadoFrames).map { sprites.texture("tornado", $0) }
            tornados = bases.enumerated().map { index, base in
                let node = SKSpriteNode(texture: frames[0])
                node.anchorPoint = .zero
                node.size = CGSize(width: ElementsArt.tornadoSide, height: ElementsArt.tornadoSide)
                node.position = CGPoint(x: CGFloat(base.column - 1) * ElementsArt.tileSide, y: CGFloat(base.row) * ElementsArt.tileSide)
                node.zPosition = -7
                let start = (index * 3) % ElementsArt.tornadoFrames
                node.run(.repeatForever(.animate(with: Array(frames[start...]) + Array(frames[..<start]), timePerFrame: ElementsArt.tornadoFrameSeconds)))
                parent.addChild(node)
                return node
            }
        }

        mutating func set(_ placed: ElementsMap.Placed?, at cell: ElementsMap.Cell) {
            tiles[cell]?.removeFromParent()
            tiles[cell] = nil
            guard let placed else { return }
            let node = SKSpriteNode(texture: ElementsArt.tile(placed.art))
            node.size = CGSize(width: ElementsArt.tileSide, height: ElementsArt.tileSide)
            node.anchorPoint = .zero
            node.position = CGPoint(x: CGFloat(cell.column) * ElementsArt.tileSide, y: CGFloat(cell.row) * ElementsArt.tileSide)
            node.zPosition = -8
            parent.addChild(node)
            tiles[cell] = node
        }
    }

    static func build(stage: Stage, map: ElementsMap, into parent: SKNode, sprites: SpriteLibrary) -> Handles {
        let width = CGFloat(stage.columns) * tileSide, height = CGFloat(stage.rows) * tileSide
        tornadoPreview = sprites.texture("tornado", 0)
        // The mountains over the whole stage, stretched to fill.
        let range = SKSpriteNode(texture: mountains)
        range.anchorPoint = .zero
        range.size = CGSize(width: width, height: height)
        range.zPosition = -20
        parent.addChild(range)
        // The lava along the bottom, each strip a step further through its frames.
        let frames = (0..<lavaFrames).map { sprites.texture("lava", $0) }
        var strip = 0
        var x: CGFloat = 0
        while x < width {
            let lava = SKSpriteNode(texture: frames[0])
            lava.anchorPoint = .zero
            lava.size = CGSize(width: lavaSide, height: lavaSide)
            lava.position = CGPoint(x: x, y: 0)
            lava.zPosition = -9
            let start = (strip * 3) % lavaFrames
            let shifted = Array(frames[start...]) + Array(frames[..<start])
            lava.run(.repeatForever(.animate(with: shifted, timePerFrame: lavaFrameSeconds)))
            parent.addChild(lava)
            x += lavaSide
            strip += 1
        }
        // The ceiling lined with icicle sockets, side by side across it, centred, hanging
        // from the ceiling row's underside.
        let socket = sprites.texture("icicle_empty", 0)
        let count = Int(width / icicleWidth)
        var icicleX = (width - CGFloat(count) * icicleWidth) / 2
        var icicles: [SKSpriteNode] = []
        for _ in 0..<count {
            let icicle = SKSpriteNode(texture: socket)
            icicle.anchorPoint = .zero
            icicle.size = CGSize(width: icicleWidth, height: icicleHeight)
            icicle.position = CGPoint(x: icicleX, y: height - tileSide - icicleHeight)
            icicle.zPosition = -7.5
            parent.addChild(icicle)
            icicles.append(icicle)
            icicleX += icicleWidth
        }
        // A taller screen's spare rows: the lava's orange on down below it, the ceiling's deep
        // purple on up above it, wider than the stage so nothing shows past either end.
        let spare = tileSide * 16
        func fill(_ colour: UInt32, y: CGFloat, z: CGFloat) -> SKSpriteNode {
            let node = SKSpriteNode(texture: sprites.flatSquare(size: 16, alpha: 1))
            node.color = SKColor(rgb: colour)
            node.colorBlendFactor = 1
            node.anchorPoint = .zero
            node.size = CGSize(width: width + spare * 2, height: spare)
            node.position = CGPoint(x: -spare, y: y)
            node.zPosition = z
            parent.addChild(node)
            return node
        }
        _ = fill(lavaOrange, y: -spare, z: -9)
        let above = fill(ceilingPurple, y: height, z: -8)
        var handles = Handles(parent: parent, sprites: sprites)
        handles.aboveCeiling = above
        handles.mountains = range
        handles.icicles = icicles
        for placed in map.tiles { handles.set(placed, at: placed.cell) }
        handles.setTornados(map.tornados)
        return handles
    }
}
