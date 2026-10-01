import EsperSim
import SpriteKit

/// Wetshot Wake drawn: the background behind it all, and the map's props: the plants and
/// rocks, and the Hooperfish assembled from its parts under the rim it carries (the rim
/// itself is the stage's hoop, drawn with the other hoops).
enum WetshotArt {
    /// A tile's side in art pixels, as the Elements' and the court's.
    static let tileSide: CGFloat = 16
    /// The water's top colour, over the background and behind; under it all, the outline colour.
    static let waterTop: RGB = PixelPalette.colours[19]
    /// Rows of the floor under the background.
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
    /// way: the top one out to 10 clockwise and back, the tail one counter-clockwise, the front one
    /// the whole arc, 15 either way; and the antenna, and
    /// the rim with it, nodding 0 to 5 degrees counter-clockwise; still while someone dunks.
    static let breathSeconds = 2.0
    static let finSeconds = 1.5
    static let antennaSeconds = 2.0
    static let finSwing = CGFloat.pi / 18
    static let frontFinSwing = CGFloat.pi / 12
    static let antennaNod = CGFloat.pi / 36

    static func antennaTurn(at time: Double, dunkedOn: Bool) -> CGFloat {
        dunkedOn ? 0 : antennaNod * CGFloat(0.5 - 0.5 * cos(time / antennaSeconds * 2 * .pi))
    }

    /// The plants swaying 5 degrees either way, slowly, each on its own beat.
    static let plantSway = CGFloat.pi / 36
    static let plantSwaySeconds = 4.0

    static func sway(_ props: [SKNode], at time: Double) {
        for (index, node) in props.enumerated() where node.name == "plant" {
            node.zRotation = plantSway * CGFloat(sin((time + Double(index) * 1.3) / plantSwaySeconds * 2 * .pi))
        }
    }

    /// The Hooperfish's body without its red rings and its eye, for the glow's mask: those glow.
    static let bodyGlowMask: SKTexture = {
        let glowing: Set<RGB> = [0xDF3E23, 0x8E5252, 0xDBA463, 0xBB7547]
        guard let image = UIImage(named: "HooperfishBody")?.cgImage else { return picture("HooperfishBody") }
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else { return picture("HooperfishBody") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Near enough each colour, as drawing the picture can shift a channel a step or two.
        for pixel in 0..<(width * height) where data[pixel * 4 + 3] > 0 {
            let close = glowing.contains { colour in
                (0..<3).allSatisfy { channel in abs(Int(data[pixel * 4 + channel]) - Int((colour >> RGB(16 - channel * 8)) & 0xFF)) <= 6 }
            }
            if close { for channel in 0..<4 { data[pixel * 4 + channel] = 0 } }
        }
        guard let masked = context.makeImage() else { return picture("HooperfishBody") }
        let texture = SKTexture(cgImage: masked)
        texture.filteringMode = .nearest
        return texture
    }()

    static func animate(_ fish: SKNode?, at time: Double, dunkedOn: Bool) {
        guard let fish else { return }
        let fin = finSwing * CGFloat(sin(time / finSeconds * 2 * .pi))
        let oneWay = finSwing * CGFloat(0.5 - 0.5 * cos(time / finSeconds * 2 * .pi))
        for case let part as SKSpriteNode in fish.children {
            switch part.name {
            case "HooperfishBody": part.setScale(CGFloat(1 + 0.1 * sin(time / breathSeconds * 2 * .pi)))
            // The top fin out to 10 degrees clockwise and back, the tail fin counter-clockwise; the
            // front fin the whole arc, 15 either way.
            case "HooperfishTopfin": part.zRotation = -oneWay
            case "HooperfishTailfin": part.zRotation = oneWay
            case "HooperfishFrontfin": part.zRotation = fin / finSwing * frontFinSwing
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
            // The Hooperfish swims and the plants sway, so they're marked frame by frame instead (`fishFlats`).
            for case let sprite as SKSpriteNode in props where sprite.name != "plant" { sprites.append((sprite, sprite.position)) }
            return sprites.compactMap { sprite, at in
                sprite.texture.map { BodySnapshot(texture: $0, position: at, anchor: sprite.anchorPoint, xScale: 1, size: sprite.size) }
            }
        }

        /// The plants as they sway, and the Hooperfish's parts as drawn this frame, turned,
        /// breathing and flipped, its rings and eyes left out of the body so they glow.
        var fishFlats: [BodySnapshot] {
            let plants = props.compactMap { node -> BodySnapshot? in
                guard let plant = node as? SKSpriteNode, plant.name == "plant", let texture = plant.texture else { return nil }
                return BodySnapshot(texture: texture, position: plant.position, anchor: plant.anchorPoint, xScale: 1, size: plant.size, zRotation: plant.zRotation)
            }
            guard let fish = hooperfish else { return plants }
            return plants + fish.children.compactMap { child in
                guard let part = child as? SKSpriteNode, let drawn = part.texture else { return nil }
                let texture = part.name == "HooperfishBody" ? WetshotArt.bodyGlowMask : drawn
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
                node.size = size
                if prop.kind.isPlant {
                    // Hung by its bottom middle, where it sways from.
                    node.anchorPoint = CGPoint(x: 0.5, y: 0)
                    node.position = CGPoint(x: origin.x + size.width / 2, y: origin.y)
                    node.name = "plant"
                } else {
                    node.anchorPoint = .zero
                    node.position = origin
                }
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
        below.color = SKColor(rgb: PixelPalette.outline)
        below.colorBlendFactor = 1
        below.size = CGSize(width: width + spare * 2, height: spare + tileSide * CGFloat(WetshotArt.floorRows))
        below.anchorPoint = .zero
        below.position = CGPoint(x: -spare, y: -spare)
        below.zPosition = -20
        parent.addChild(below)
        var handles = Handles(parent: parent)
        // Over the background to the stage's top and on up, the water's top colour, marked so it
        // doesn't glow (the water's tint over it would otherwise lift it off the background colour).
        let above = SKSpriteNode(texture: flat)
        above.color = SKColor(rgb: waterTop)
        above.colorBlendFactor = 1
        above.anchorPoint = .zero
        let backTop = back.position.y + back.size.height
        above.size = CGSize(width: width + spare * 2, height: CGFloat(stage.rows) * tileSide - backTop + spare)
        above.position = CGPoint(x: -spare, y: backTop)
        above.zPosition = -20
        parent.addChild(above)
        handles.backdrop = [back, below, above]
        handles.setProps(map.props)
        return handles
    }
}
