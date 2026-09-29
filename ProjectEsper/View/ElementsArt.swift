import EsperSim
import SpriteKit

/// The Elements' scenery: the mountains stretched over the stage on a flat ground, a bed of
/// lava along the bottom, and a sprite for every tile the map has placed, cut from the tileset.
enum ElementsArt {
    /// The flat colour behind everything: palette 2.
    static let background: RGB = PixelPalette.colours[2]
    static let tileSide: CGFloat = 16
    static let tilesetColumns = 15, tilesetRows = 7
    static let lavaFrames = 8
    static let lavaSide: CGFloat = 48
    /// Seconds a lava frame shows.
    static let lavaFrameSeconds = 0.18

    /// The tileset cells with anything drawn in them: what the map maker offers.
    static let filled: [ElementsMap.Cell] = {
        let rows: [[Int]] = [[2, 4], [2, 3, 4, 5, 6, 7, 9, 11, 12, 13], [1, 2, 3, 4, 5],
                             [1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13], [1, 2, 3, 4, 5, 8, 9, 10, 11, 12], [9, 10, 11]]
        return rows.enumerated().flatMap { row, columns in columns.map { ElementsMap.Cell($0, row) } }
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

    static let mountains: SKTexture = {
        let texture = SKTexture(imageNamed: "ElementsMountains")
        texture.filteringMode = .nearest
        return texture
    }()

    /// What the stage's art gives back: each placed tile's sprite by its cell, to be changed by the map maker.
    struct Handles {
        var tiles: [ElementsMap.Cell: SKSpriteNode] = [:]
        let parent: SKNode
        let sprites: SpriteLibrary

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
        var handles = Handles(parent: parent, sprites: sprites)
        for placed in map.tiles { handles.set(placed, at: placed.cell) }
        return handles
    }
}
