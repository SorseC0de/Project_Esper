import EsperSim
import SpriteKit

/// Wetshot Wake drawn: the background behind it all, and the map's props: the plants and
/// rocks, and the Hooperfish assembled from its parts under the rim it carries (the rim
/// itself is the stage's hoop, drawn with the other hoops).
enum WetshotArt {
    /// A tile's side in art pixels, as the Elements' and the court's.
    static let tileSide: CGFloat = 16
    /// The water's top colour and its floor's, for a taller or wider screen's spare.
    static let waterTop: RGB = PixelPalette.colours[19]
    static let floorColour: RGB = PixelPalette.colours[16]
    /// Rows of the floor's colour under the background.
    static let floorRows = 1

    private static func picture(_ name: String) -> SKTexture {
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .nearest
        return texture
    }

    static let background = picture("WetshotBackground")
    private static let rocks = picture("WetshotRocks")

    /// A prop's picture: a plant whole, a rock its half of the rocks sheet (the first the top),
    /// the Hooperfish's body for the map maker's hand.
    static func texture(_ kind: StageMap.PropKind) -> SKTexture {
        switch kind {
        case .plant1: picture("WetshotPlant1")
        case .plant2: picture("WetshotPlant2")
        case .plant3: picture("WetshotPlant3")
        case .plant4: picture("WetshotPlant4")
        case .plant5: picture("WetshotPlant5")
        case .rock1, .rock2:
            {
                let half = SKTexture(rect: CGRect(x: 0, y: kind == .rock1 ? 0.5 : 0, width: 1, height: 0.5), in: rocks)
                half.filteringMode = .nearest
                return half
            }()
        case .hooperfish: picture("HooperfishBody")
        }
    }

    /// The Hooperfish's parts back to front, each over the last, and how high each sits.
    static let hooperfishParts: [(name: String, z: CGFloat)] = [
        ("HooperfishTopfin", 5.1), ("HooperfishTailfin", 5.2), ("HooperfishBody", 5.3), ("HooperfishAntenna", 5.35), ("HooperfishFrontfin", 5.4),
    ]

    /// What's drawn for the map's props, to be redrawn when the map maker moves them.
    struct Handles {
        var props: [SKNode] = []
        /// The background and the spare under it, drawn once.
        var backdrop: [SKSpriteNode] = []
        let parent: SKNode

        /// Everything here as the glow's mask should mark it: none of it glows.
        var flats: [BodySnapshot] {
            var sprites: [(SKSpriteNode, CGPoint)] = backdrop.map { ($0, $0.position) }
            for prop in props {
                if let sprite = prop as? SKSpriteNode {
                    sprites.append((sprite, sprite.position))
                } else {
                    for case let part as SKSpriteNode in prop.children { sprites.append((part, prop.position + part.position)) }
                }
            }
            return sprites.compactMap { sprite, at in
                sprite.texture.map { BodySnapshot(texture: $0, position: at, anchor: sprite.anchorPoint, xScale: 1, size: sprite.size) }
            }
        }

        mutating func setProps(_ placed: [StageMap.Prop]) {
            props.forEach { $0.removeFromParent() }
            props = placed.map { prop in
                let origin = CGPoint(x: CGFloat(prop.cell.column) * WetshotArt.tileSide, y: CGFloat(prop.cell.row) * WetshotArt.tileSide)
                let size = CGSize(width: prop.kind.pixelSize.width, height: prop.kind.pixelSize.height)
                if prop.kind == .hooperfish {
                    // Its parts stacked, each animated on its own later.
                    let fish = SKNode()
                    fish.position = origin
                    for part in WetshotArt.hooperfishParts {
                        let node = SKSpriteNode(texture: WetshotArt.picture(part.name))
                        node.anchorPoint = .zero
                        node.size = size
                        node.zPosition = part.z
                        node.name = part.name
                        fish.addChild(node)
                    }
                    parent.addChild(fish)
                    return fish
                }
                let node = SKSpriteNode(texture: WetshotArt.texture(prop.kind))
                node.anchorPoint = .zero
                node.size = size
                node.position = origin
                // Behind the Hooperfish, in front of the background.
                node.zPosition = 4
                parent.addChild(node)
                return node
            }
        }
    }

    static func build(stage: Stage, map: StageMap, into parent: SKNode) -> Handles {
        let width = CGFloat(stage.columns) * tileSide
        // The background a row up off the floor's row, at its own size; the row of water over
        // it is the scene's background, the water's top colour.
        let back = SKSpriteNode(texture: background)
        back.anchorPoint = .zero
        back.size = background.size()
        back.position = CGPoint(x: 0, y: tileSide * CGFloat(WetshotArt.floorRows))
        back.zPosition = -20
        parent.addChild(back)
        // The floor's row under it, and a bigger screen's spare below that, in the floor's colour.
        let spare = tileSide * 16
        let below = SKSpriteNode(color: SKColor(rgb: floorColour), size: CGSize(width: width + spare * 2, height: spare + tileSide * CGFloat(WetshotArt.floorRows)))
        below.anchorPoint = .zero
        below.position = CGPoint(x: -spare, y: -spare)
        below.zPosition = -20
        parent.addChild(below)
        var handles = Handles(parent: parent)
        handles.backdrop = [back, below]
        handles.setProps(map.props)
        return handles
    }
}
