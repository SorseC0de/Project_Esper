import EsperSim
import SpriteKit

/// The Elements' scenery: the mountains stretched over the stage on a flat ground, a bed of
/// lava along the bottom, and a sprite for every tile the map has placed, cut from the tileset.
enum ElementsArt {
    /// The flat colour behind everything: palette 29.
    static let background: RGB = PixelPalette.colours[17]
    static let tileSide: CGFloat = 16
    static let lavaFrames = 8
    /// The lava's orange below its surface, and the deep purple inside the ceiling's rock.
    static let lavaOrange: RGB = PixelPalette.colours[6]
    static let ceilingPurple: RGB = 0x403353
    static let lavaSide: CGFloat = 48
    /// Seconds a lava frame shows.
    static let lavaFrameSeconds = 0.18
    static let tornadoFrames = 8
    static let burstFrames = 10
    static let tornadoSide: CGFloat = 48
    /// Seconds a tornado's frame shows: twelve a second.
    static let tornadoFrameSeconds = 1.0 / 12
    /// The copy of each tornado drawn over the players.
    static let tornadoOverlayAlpha: CGFloat = 0.33
    /// Pixels round the circle a tornado hovers on, clockwise, and a body held in one, counter-clockwise.
    static let hoverRadius: CGFloat = 2
    /// Where the lava's art tops out, for what sinks into it.
    static var lavaTop: CGFloat { lavaSide }
    /// No icicle hangs over these columns or their mirror: the ceiling's ends, over the rock and the shafts.
    static let icicleFreeColumns = 16
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
        var tornadoOverlays: [SKSpriteNode] = []
        /// The stage's fixed art, for the glow's mask to leave out: the mountains, the icicles.
        var mountains: SKSpriteNode?
        var icicles: [SKSpriteNode] = []
        /// A taller screen's spare rows, the lava's orange below and the rock's purple above, and
        /// the shafts' walls up through them: none of it glows.
        var spareFills: [SKSpriteNode] = []
        var shaftWalls: [SKSpriteNode] = []
        let parent: SKNode
        let overlayParent: SKNode
        let sprites: SpriteLibrary

        /// The tornados as the map has them, drawn whole, and each again over the players, faint,
        /// in `overlayParent`, cropped to above the lava.
        mutating func setTornados(_ bases: [ElementsMap.Cell]) {
            (tornados + tornadoOverlays).forEach { $0.removeFromParent() }
            func node(_ base: ElementsMap.Cell, z: CGFloat, alpha: CGFloat, into layer: SKNode) -> SKSpriteNode {
                let node = SKSpriteNode(texture: sprites.texture("tornado", 0))
                node.anchorPoint = .zero
                node.size = CGSize(width: ElementsArt.tornadoSide, height: ElementsArt.tornadoSide)
                node.position = CGPoint(x: CGFloat(base.column - 1) * ElementsArt.tileSide, y: CGFloat(base.row) * ElementsArt.tileSide)
                node.zPosition = z
                node.alpha = alpha
                layer.addChild(node)
                return node
            }
            // Behind the lava, so one sinks into it.
            tornados = bases.map { node($0, z: -9.5, alpha: 1, into: parent) }
            tornadoOverlays = bases.map { node($0, z: 0, alpha: ElementsArt.tornadoOverlayAlpha, into: overlayParent) }
        }

        /// The tornados where the sim has them this frame, each on a frame of its own, in fire or not.
        func placeTornados(_ boxes: [Box], fire: Bool, time: Double, burstFrame: Int?, hoverLap: Double) {
            let hover = CGPoint(x: (cos(-hoverLap) * Double(ElementsArt.hoverRadius)).rounded(),
                                y: (sin(-hoverLap) * Double(ElementsArt.hoverRadius)).rounded())
            let sheet = fire ? "fire_tornado" : "tornado"
            let step = Int(time / ElementsArt.tornadoFrameSeconds)
            for (index, box) in boxes.enumerated() where index < tornados.count {
                // Bursting where it stands, the burst's sheet through once, all together.
                let texture = burstFrame.map { sprites.texture(sheet + "_burst", min($0 * TornadoRules.burstSheetFramesPerSecond / 60, ElementsArt.burstFrames - 1)) }
                    ?? sprites.texture(sheet, (step + index * 3) % ElementsArt.tornadoFrames)
                for node in [tornados[index], tornadoOverlays[index]] {
                    node.texture = texture
                    node.position = SpriteLibrary.point(box.min) + hover
                }
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

    static func build(stage: Stage, map: ElementsMap, into parent: SKNode, overlayParent: SKNode, sprites: SpriteLibrary) -> Handles {
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
            let firstColumn = Int(icicleX / tileSide), lastColumn = Int((icicleX + icicleWidth) / tileSide) - 1
            guard firstColumn > icicleFreeColumns, lastColumn < stage.columns - 1 - icicleFreeColumns else {
                icicleX += icicleWidth
                continue
            }
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
        func fill(_ colour: RGB, y: CGFloat, z: CGFloat) -> SKSpriteNode {
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
        let below = fill(lavaOrange, y: -spare, z: -9)
        // The rock's purple above, but for the shafts, which show the background.
        let ceilingRow = stage.rows - 1
        var above: [SKSpriteNode] = []
        var runStart: CGFloat? = -spare
        for column in 0...stage.columns {
            let solid = column == stage.columns || map.wall(at: .init(column, ceilingRow)) == .solid
            let x = CGFloat(column) * tileSide
            if solid, runStart == nil { runStart = x }
            if !solid || column == stage.columns, let start = runStart {
                let end = column == stage.columns ? width + spare : x
                let piece = fill(ceilingPurple, y: height, z: -8)
                piece.position.x = start
                piece.size.width = end - start
                above.append(piece)
                runStart = nil
            }
        }
        // The shafts up through the sky over the ceiling's gaps, walled in rock edges.
        var shaftWalls: [SKSpriteNode] = []
        for column in 0..<stage.columns where map.wall(at: .init(column, ceilingRow)) != .solid {
            for (wallColumn, art) in [(column - 1, ElementsMap.Cell(5, 3)), (column + 1, ElementsMap.Cell(1, 3))]
            where (0..<stage.columns).contains(wallColumn) && map.wall(at: .init(wallColumn, ceilingRow)) == .solid {
                for row in stage.rows..<(stage.rows + Int(spare / tileSide)) {
                    let wall = SKSpriteNode(texture: tile(art))
                    wall.size = CGSize(width: tileSide, height: tileSide)
                    wall.anchorPoint = .zero
                    wall.position = CGPoint(x: CGFloat(wallColumn) * tileSide, y: CGFloat(row) * tileSide)
                    wall.zPosition = -7.9
                    parent.addChild(wall)
                    shaftWalls.append(wall)
                }
            }
        }
        var handles = Handles(parent: parent, overlayParent: overlayParent, sprites: sprites)
        handles.spareFills = [below] + above
        handles.shaftWalls = shaftWalls
        handles.mountains = range
        handles.icicles = icicles
        for placed in map.tiles { handles.set(placed, at: placed.cell) }
        handles.setTornados(map.tornados)
        return handles
    }
}
