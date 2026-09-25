import SpriteKit
import EsperSim

/// Highway Traffic's scenery and its vehicles' drawings. The background is one dark blue;
/// the road runs through where the field's grass does, the floor an invisible strip
/// through its middle. Nothing here touches the match.
enum HighwayArt {
    static let night = SKColor(red: 0.05, green: 0.08, blue: 0.20, alpha: 1)
    static let asphalt = SKColor(red: 0.14, green: 0.14, blue: 0.17, alpha: 1)
    static let kerb = SKColor(red: 0.28, green: 0.28, blue: 0.32, alpha: 1)
    static let paint = SKColor(red: 0.90, green: 0.78, blue: 0.30, alpha: 1)

    static func build(for stage: Stage, into parent: SKNode, flat: (CGFloat) -> SKTexture) {
        let width = CGFloat(stage.columns) * 16
        let top = CGFloat(stage.rows + Stage.skyRows) * 16
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ colour: SKColor, z: CGFloat) {
            let node = SKSpriteNode(texture: flat(4))
            node.anchorPoint = .zero
            node.position = CGPoint(x: x, y: y)
            node.size = CGSize(width: w, height: h)
            node.color = colour
            node.colorBlendFactor = 1
            node.zPosition = z
            parent.addChild(node)
        }
        rect(-400, FieldArt.turfBottom - 200, width + 800, top + 400, night, z: -20)
        // The road where the grass would be, a kerb along its far edge and its near one,
        // and the lane's dashes through the middle, under the wheels.
        rect(-400, FieldArt.turfBottom, width + 800, FieldArt.turfTop - FieldArt.turfBottom, asphalt, z: -10)
        rect(-400, FieldArt.turfTop - 3, width + 800, 3, kerb, z: -9)
        rect(-400, FieldArt.turfBottom, width + 800, 3, kerb, z: -9)
        var dash: CGFloat = 0
        while dash < width {
            rect(dash, FieldArt.turfBottom + 10, 20, 2, paint, z: -8)
            dash += 40
        }
    }

    /// Where the art sits in its square canvas, top and bottom as shares down it, measured
    /// off the drawings, so a vehicle's bottom sits on the road and its top is its roof.
    static let artRows: [String: (top: CGFloat, bottom: CGFloat)] = [
        "ambulancr": (51, 205), "bus": (76, 180), "cab": (51, 205), "car": (69, 187),
        "car_batmobile": (82, 174), "car_droptop": (90, 166), "car_police": (76, 180), "car_racer": (91, 165),
        "car_super": (88, 168), "fuel_truck": (70, 186), "hearse": (56, 200), "limousine": (86, 170),
        "moped": (48, 208), "motorcycle": (58, 198), "motorcycle2": (57, 199), "truck": (18, 238),
        "truck2": (68, 189), "truck_fire": (57, 199), "truck_food": (22, 234), "van": (61, 195),
        "van2": (63, 193), "van3": (38, 218), "vespa": (29, 228), "helicopter": (27, 229),
    ].mapValues { (top: $0.0 / 256, bottom: $0.1 / 256) }

    /// The rotors' hubs on the helicopter's 800 square, as shares across and down: the top
    /// rotor's middle and the tail rotor's.
    static let topRotorHub = CGPoint(x: 482.7 / 800, y: 119.5 / 800)
    static let tailRotorHub = CGPoint(x: 82.9 / 800, y: 394.2 / 800)

    /// A catalog vector as a texture, cut to its art's rows; `tint` fills it through its own
    /// alpha in one colour.
    static func texture(_ name: String, art: String, tint: SKColor? = nil) -> SKTexture? {
        guard let image = UIImage(named: name) else { return nil }
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            image.draw(in: rect)
            if let tint {
                context.cgContext.setBlendMode(.sourceIn)
                tint.setFill()
                context.cgContext.fill(rect)
            }
        }
        let full = SKTexture(image: drawn)
        guard let rows = artRows[art] else { return full }
        // Texture space has y up: the art's bottom row is 1 - bottom from the foot.
        return SKTexture(rect: CGRect(x: 0, y: 1 - rows.bottom, width: 1, height: rows.bottom - rows.top), in: full)
    }
}
