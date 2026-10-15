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

    struct Handles {
        /// The painted pictures, kept out of the glow.
        let flats: [SKSpriteNode]
        /// The possession pixels in white, tinted the court's colour, glowing.
        let backLit: SKSpriteNode
        let tilesLit: SKSpriteNode
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
        return Handles(flats: [back, tiles, extras], backLit: backLit, tilesLit: tilesLit)
    }

    /// The possession pixels in the court's colour: the tiles' as it is, the back wall's its share.
    static func tint(_ handles: Handles, _ colour: SKColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        handles.tilesLit.color = colour
        handles.backLit.color = SKColor(red: r * backShare, green: g * backShare, blue: b * backShare, alpha: 1)
    }
}
