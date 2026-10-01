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
    /// A white square to colour, for fills the glow's mask must see.
    private static let flat: SKTexture = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return SKTexture(image: UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        })
    }()
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

    /// The Hooperfish's parts back to front, each over the last, how high each sits, and where
    /// each turns: where it meets the body, in art pixels from the picture's bottom left (the
    /// body's middle for the body, which breathes rather than turns).
    static let hooperfishParts: [(name: String, z: CGFloat, pivot: CGPoint)] = [
        ("HooperfishTopfin", 5.1, CGPoint(x: 60, y: 27)), ("HooperfishTailfin", 5.2, CGPoint(x: 68, y: 19)),
        ("HooperfishBody", 5.3, CGPoint(x: 51, y: 20.5)), ("HooperfishAntenna", 5.35, antennaPivot),
        ("HooperfishFrontfin", 5.4, CGPoint(x: 59, y: 13)),
    ]
    /// Where the antenna meets the body, which the rim on it turns about too.
    static let antennaPivot = CGPoint(x: 43, y: 29)

    /// Its swimming: the body breathing between 0.9 and 1.1, the fins swinging 10 degrees either
    /// way (the top one clockwise as the other two go counter-clockwise), and the antenna, and
    /// the rim with it, nodding 0 to 5 degrees counter-clockwise; still while someone dunks.
    static let breathSeconds = 3.0
    static let finSeconds = 1.5
    static let antennaSeconds = 2.0
    static let finSwing = CGFloat.pi / 18
    static let antennaNod = CGFloat.pi / 36

    static func antennaTurn(at time: Double, dunkedOn: Bool) -> CGFloat {
        dunkedOn ? 0 : antennaNod * CGFloat(0.5 - 0.5 * cos(time / antennaSeconds * 2 * .pi))
    }

    static func animate(_ fish: SKNode?, at time: Double, dunkedOn: Bool) {
        guard let fish else { return }
        let fin = finSwing * CGFloat(sin(time / finSeconds * 2 * .pi))
        for case let part as SKSpriteNode in fish.children {
            switch part.name {
            case "HooperfishBody": part.setScale(CGFloat(1 + 0.1 * sin(time / breathSeconds * 2 * .pi)))
            case "HooperfishTopfin": part.zRotation = -fin
            case "HooperfishTailfin", "HooperfishFrontfin": part.zRotation = fin
            case "HooperfishAntenna": part.zRotation = antennaTurn(at: time, dunkedOn: dunkedOn)
            default: break
            }
        }
    }

    /// What's drawn for the map's props, to be redrawn when the map maker moves them.
    struct Handles {
        var props: [SKNode] = []
        /// The Hooperfish as placed; in play it swims where the sim has it.
        var hooperfish: SKNode?
        /// The background and the spare under it, drawn once.
        var backdrop: [SKSpriteNode] = []
        let parent: SKNode

        /// Everything here as the glow's mask should mark it: none of it glows.
        var flats: [BodySnapshot] {
            var sprites: [(SKSpriteNode, CGPoint)] = backdrop.map { ($0, $0.position) }
            // The Hooperfish swims, so it's marked frame by frame instead (`fishFlats`).
            for case let sprite as SKSpriteNode in props { sprites.append((sprite, sprite.position)) }
            return sprites.compactMap { sprite, at in
                sprite.texture.map { BodySnapshot(texture: $0, position: at, anchor: sprite.anchorPoint, xScale: 1, size: sprite.size) }
            }
        }

        /// The Hooperfish's parts as drawn this frame, turned, breathing and flipped.
        var fishFlats: [BodySnapshot] {
            guard let fish = hooperfish else { return [] }
            return fish.children.compactMap { child in
                guard let part = child as? SKSpriteNode, let texture = part.texture else { return nil }
                let at = CGPoint(x: fish.position.x + part.position.x * fish.xScale, y: fish.position.y + part.position.y)
                return BodySnapshot(texture: texture, position: at, anchor: part.anchorPoint, xScale: fish.xScale,
                                    size: CGSize(width: part.size.width * part.yScale, height: part.size.height * part.yScale),
                                    zRotation: part.zRotation * fish.xScale)
            }
        }

        mutating func setProps(_ placed: [StageMap.Prop]) {
            props.forEach { $0.removeFromParent() }
            hooperfish = nil
            props = placed.map { prop in
                let origin = CGPoint(x: CGFloat(prop.cell.column) * WetshotArt.tileSide, y: CGFloat(prop.cell.row) * WetshotArt.tileSide)
                let size = CGSize(width: prop.kind.pixelSize.width, height: prop.kind.pixelSize.height)
                if prop.kind == .hooperfish {
                    // Its parts stacked, each animated on its own later.
                    let fish = SKNode()
                    fish.position = origin
                    for part in WetshotArt.hooperfishParts {
                        let node = SKSpriteNode(texture: WetshotArt.picture(part.name))
                        // Hung by where it turns, so it turns there.
                        node.anchorPoint = CGPoint(x: part.pivot.x / size.width, y: part.pivot.y / size.height)
                        node.position = part.pivot
                        node.size = size
                        node.zPosition = part.z
                        node.name = part.name
                        fish.addChild(node)
                    }
                    parent.addChild(fish)
                    hooperfish = fish
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

    /// The Hooperfish where it swims: its picture's bottom left, turned to face right by
    /// flipping about its middle; or, with nothing from the sim (the map maker), where it's placed.
    static func place(_ node: SKNode?, as fish: Hooperfish?, placed: StageMap.Prop?) {
        guard let node else { return }
        guard let fish else {
            if let placed { node.position = CGPoint(x: CGFloat(placed.cell.column) * tileSide, y: CGFloat(placed.cell.row) * tileSide) }
            node.xScale = 1
            return
        }
        let at = SpriteLibrary.point(fish.position)
        node.xScale = fish.facesRight ? -1 : 1
        node.position = CGPoint(x: (at.x + (fish.facesRight ? CGFloat(HooperfishRules.pixelWidth) : 0)).rounded(), y: at.y.rounded())
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
        // Textured, so the glow's mask can mark it as not glowing.
        let below = SKSpriteNode(texture: flat)
        below.color = SKColor(rgb: floorColour)
        below.colorBlendFactor = 1
        below.size = CGSize(width: width + spare * 2, height: spare + tileSide * CGFloat(WetshotArt.floorRows))
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
