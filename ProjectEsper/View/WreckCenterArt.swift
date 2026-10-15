import EsperSim
import SpriteKit
import UIKit

/// The Wreck Center drawn whole from its Aseprite map (`Tools/import_stage_art.py wreck`), in
/// place of the flat tiles: back to front the background and back wall, the back wall's
/// possession pixels (palette 60), the tiles, the tiles' possession pixels (palette 59), and the
/// extras. The sim's tiles are the court's as ever; the art's bigger than the court, its box one
/// tile in from the art's sides and bottom, the rest padding the camera doesn't frame.
enum WreckCenterArt {
    /// The art's bottom left from the stage's, in art pixels.
    static let origin = CGPoint(x: -16, y: -16)
    /// Past the art: its background's colour.
    static let beyond: RGB = 0x2A2F4E
    /// The possession pixels unheld: the tiles' palette 59; the back wall's, palette 60, this
    /// share of the tiles' colour, neutral or held.
    static let tilesNeutral: RGB = 0x5D5D5D
    static let backShare: CGFloat = CGFloat(0x3D) / CGFloat(0x5D)
    /// 47's three-point lines drawn on the back wall: over its possession pixels, under the tiles.
    static let threePointZ: CGFloat = -7.85

    /// Its pieces' frames a second, and the displays' pixels that light: white and its two greys.
    static let piecesPerSecond: Double = 10
    static let displayLitColours: Set<UInt32> = [0xFFFFFF, 0xC7CFDD, 0x92A1B9]
    static let piecesZ: CGFloat = -7.65

    final class Handles {
        /// The painted pictures, kept out of the glow.
        let flats: [SKSpriteNode]
        /// The possession pixels in white, tinted the court's colour, glowing.
        let backLit: SKSpriteNode
        let tilesLit: SKSpriteNode
        let parent: SKNode
        /// The map's pieces: each animated, the displays with their lit pixels over them.
        fileprivate(set) var pieces: [(kind: StageMap.PropKind, base: SKSpriteNode, lit: SKSpriteNode?)] = []
        fileprivate var displayColour = SKColor.white

        init(flats: [SKSpriteNode], backLit: SKSpriteNode, tilesLit: SKSpriteNode, parent: SKNode) {
            self.flats = flats
            self.backLit = backLit
            self.tilesLit = tilesLit
            self.parent = parent
        }

        /// The pieces as the mask should mark them: none of the art glows but the lit pixels.
        var pieceFlats: [BodySnapshot] {
            pieces.compactMap { piece in
                piece.base.texture.map { BodySnapshot(texture: $0, position: piece.base.position, anchor: .zero, xScale: piece.base.xScale, size: WreckCenterArt.size(piece.kind)) }
            }
        }

        /// What glows through the flats: the possession pixels, and the displays' lit ones.
        var glowing: [BodySnapshot] {
            let lit = [backLit, tilesLit].compactMap { node in
                node.texture.map { BodySnapshot(texture: $0, position: node.position, anchor: .zero, xScale: 1, size: node.size) }
            }
            return lit + pieces.compactMap { piece in
                guard let node = piece.lit, let texture = node.texture else { return nil }
                return BodySnapshot(texture: texture, position: node.position, anchor: .zero, xScale: node.xScale, size: WreckCenterArt.size(piece.kind))
            }
        }

        /// The map's pieces put down again, each with its bottom left on its cell.
        func setPieces(_ placed: [StageMap.Prop]) {
            pieces.forEach { $0.base.removeFromParent(); $0.lit?.removeFromParent() }
            pieces = placed.compactMap { prop in
                guard let frames = WreckCenterArt.frames[prop.kind] else { return nil }
                let size = WreckCenterArt.size(prop.kind)
                let flipped = WreckCenterArt.isFlipped(prop.kind)
                let origin = CGPoint(x: CGFloat(prop.cell.column) * 16 + (flipped ? size.width : 0), y: CGFloat(prop.cell.row) * 16)
                func node(_ texture: SKTexture, z: CGFloat) -> SKSpriteNode {
                    let sprite = SKSpriteNode(texture: texture)
                    sprite.anchorPoint = .zero
                    sprite.size = size
                    sprite.xScale = flipped ? -1 : 1
                    sprite.position = origin
                    sprite.zPosition = z
                    parent.addChild(sprite)
                    return sprite
                }
                let base = node(frames[0], z: WreckCenterArt.piecesZ)
                let lit = WreckCenterArt.litFrames[prop.kind].map { node($0[0], z: WreckCenterArt.piecesZ + 0.01) }
                lit?.colorBlendFactor = 1
                lit?.color = displayColour
                return (prop.kind, base, lit)
            }
        }
    }

    /// Each piece's sheet in the sprite atlas; the flipped conveyors are their own strips mirrored.
    private static func sheet(_ kind: StageMap.PropKind) -> String? {
        switch kind {
        case .onewayPlatform: "oneway_platform"
        case .conveyorL, .flippedConveyorL: "conveyor_l"
        case .conveyorM, .flippedConveyorM: "conveyor_m"
        case .conveyorR, .flippedConveyorR: "conveyor_r"
        case .displayFloor: "display_floor"
        case .displayWall: "display_wall"
        default: nil
        }
    }
    private static func frameCount(_ kind: StageMap.PropKind) -> Int { kind == .onewayPlatform ? 8 : 4 }
    static func isFlipped(_ kind: StageMap.PropKind) -> Bool { [.flippedConveyorL, .flippedConveyorM, .flippedConveyorR].contains(kind) }
    static func size(_ kind: StageMap.PropKind) -> CGSize { CGSize(width: kind.pixelSize.width, height: kind.pixelSize.height) }

    /// Every piece's frames, and the displays' lit pixels in their own greys, made at loading.
    static let frames: [StageMap.PropKind: [SKTexture]] = {
        let atlas = SKTextureAtlas(named: "Sprites")
        var all: [StageMap.PropKind: [SKTexture]] = [:]
        for kind in StageMap.PropKind.kinds(for: .wreckCenter) {
            guard let sheet = sheet(kind) else { continue }
            all[kind] = (0..<frameCount(kind)).map { frame in
                let texture = atlas.textureNamed("\(sheet)_\(frame)")
                texture.filteringMode = .nearest
                return texture
            }
        }
        return all
    }()
    static let litFrames: [StageMap.PropKind: [SKTexture]] = {
        var all: [StageMap.PropKind: [SKTexture]] = [:]
        for kind in [StageMap.PropKind.displayFloor, .displayWall] {
            all[kind] = frames[kind]?.map(litPixels)
        }
        return all
    }()

    /// A frame's lit pixels alone, as drawn, so a white tint shows them unchanged.
    private static func litPixels(_ texture: SKTexture) -> SKTexture {
        let image = texture.cgImage()
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return texture }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let colour = UInt32(pixels[index]) << 16 | UInt32(pixels[index + 1]) << 8 | UInt32(pixels[index + 2])
            if pixels[index + 3] < 255 || !displayLitColours.contains(colour) { pixels[index..<index + 4] = [0, 0, 0, 0] }
        }
        guard let lit = context.makeImage() else { return texture }
        let made = SKTexture(cgImage: lit)
        made.filteringMode = .nearest
        return made
    }

    /// The pieces on their frame for this moment, all in step.
    static func animate(_ handles: Handles, at time: TimeInterval) {
        let tick = Int(time * piecesPerSecond)
        for piece in handles.pieces {
            guard let frames = frames[piece.kind] else { continue }
            let frame = tick % frames.count
            piece.base.texture = frames[frame]
            if let lit = piece.lit, let litFrames = litFrames[piece.kind] { lit.texture = litFrames[frame] }
        }
    }

    static func build(into parent: SKNode) -> Handles? {
        guard UIImage(named: "WreckCenterBack") != nil else { return nil }
        func picture(_ name: String, z: CGFloat) -> SKSpriteNode {
            let texture = SKTexture(imageNamed: name)
            texture.filteringMode = .nearest
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = .zero
            node.position = origin
            node.zPosition = z
            parent.addChild(node)
            return node
        }
        let back = picture("WreckCenterBack", z: -8.0)
        let backLit = picture("WreckCenterBackLit", z: -7.9)
        backLit.colorBlendFactor = 1
        let tiles = picture("WreckCenterTiles", z: -7.8)
        let tilesLit = picture("WreckCenterTilesLit", z: -7.7)
        tilesLit.colorBlendFactor = 1
        let extras = picture("WreckCenterExtras", z: -7.6)
        _ = litFrames
        return Handles(flats: [back, tiles, extras], backLit: backLit, tilesLit: tilesLit, parent: parent)
    }

    /// The possession pixels in the court's colour: the tiles' as it is, the back wall's its
    /// share; the displays' at full brightness, so the neutral grey leaves them as drawn.
    static func tint(_ handles: Handles, _ colour: SKColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        handles.tilesLit.color = colour
        handles.backLit.color = SKColor(red: r * backShare, green: g * backShare, blue: b * backShare, alpha: 1)
        let brightest = max(r, g, b, 0.001)
        handles.displayColour = SKColor(red: r / brightest, green: g / brightest, blue: b / brightest, alpha: 1)
        for piece in handles.pieces { piece.lit?.color = handles.displayColour }
    }
}
