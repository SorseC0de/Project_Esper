import SpriteKit
import EsperSim

/// The football field's scenery, drawn once from flat shapes in art pixels: a night sky
/// with floodlight banks, the stands with their fanning lines and rail, and the turf with
/// its stripes, yard lines, hashes and numbers. The floor players walk on is invisible and
/// runs through the middle of the turf. Nothing here touches the match.
enum FieldArt {
    static let sky = SKColor(red: 0.04, green: 0.08, blue: 0.16, alpha: 1)
    static let stands = SKColor(red: 0.09, green: 0.21, blue: 0.29, alpha: 1)
    static let standLine = SKColor(red: 0.20, green: 0.45, blue: 0.54, alpha: 1)
    static let turfLight = SKColor(red: 0.47, green: 0.63, blue: 0.27, alpha: 1)
    static let turfDark = SKColor(red: 0.36, green: 0.53, blue: 0.20, alpha: 1)
    static let chalk = SKColor(white: 0.97, alpha: 1)
    static let gold = SKColor(red: 0.93, green: 0.70, blue: 0.29, alpha: 1)
    static let pad = SKColor(red: 0.13, green: 0.29, blue: 0.56, alpha: 1)

    /// Art pixels, the floor's top at 16: the turf from `turfBottom` to `turfTop`, the
    /// floor line through its middle, the stands above to `standsTop`, and the lights over them.
    static let turfBottom: CGFloat = -64
    static let turfTop: CGFloat = 96
    static let standsTop: CGFloat = 232
    static let railY: CGFloat = 176
    static let lightsBottom: CGFloat = 250
    /// How far down the camera looks below the floor, in art pixels, so the turf shows round
    /// the players.
    static let viewBelowFloor: CGFloat = 64

    static func build(for stage: Stage, into parent: SKNode, flat: (CGFloat) -> SKTexture) {
        let width = CGFloat(stage.columns) * 16
        let top = CGFloat(stage.rows + Stage.skyRows) * 16
        let centre = width / 2
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ colour: SKColor, z: CGFloat = -10) {
            let node = SKSpriteNode(texture: flat(4))
            node.anchorPoint = .zero
            node.position = CGPoint(x: x, y: y)
            node.size = CGSize(width: w, height: h)
            node.color = colour
            node.colorBlendFactor = 1
            node.zPosition = z
            parent.addChild(node)
        }
        func quad(_ points: [CGPoint], _ colour: SKColor, z: CGFloat) {
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            let node = SKShapeNode(path: path)
            node.fillColor = colour
            node.strokeColor = .clear
            node.zPosition = z
            parent.addChild(node)
        }
        // Lines lean toward a vanishing point over the middle: the higher, the nearer centre.
        func lean(_ x: CGFloat, at y: CGFloat, from bottom: CGFloat, to top: CGFloat, share: CGFloat) -> CGFloat {
            let rise = (y - bottom) / (top - bottom)
            return x + (centre - x) * share * rise
        }

        // Sky and stands.
        rect(-200, standsTop, width + 400, top - standsTop + 200, sky, z: -20)
        rect(-200, turfTop, width + 400, standsTop - turfTop, stands, z: -19)
        let standSpacing: CGFloat = 160
        var x: CGFloat = centre.truncatingRemainder(dividingBy: standSpacing)
        while x < width {
            let bottomLeft = x - 3, bottomRight = x + 3
            let topLeft = lean(x - 2, at: standsTop, from: turfTop, to: standsTop, share: 0.35)
            let topRight = lean(x + 2, at: standsTop, from: turfTop, to: standsTop, share: 0.35)
            quad([CGPoint(x: bottomLeft, y: turfTop), CGPoint(x: bottomRight, y: turfTop),
                  CGPoint(x: topRight, y: standsTop), CGPoint(x: topLeft, y: standsTop)], standLine, z: -18)
            x += standSpacing
        }
        // The rail: a black band with white squares along it.
        rect(-200, railY, width + 400, 6, .black, z: -17)
        var square: CGFloat = 20
        while square < width {
            rect(square, railY + 1, 6, 4, chalk, z: -16)
            square += 64
        }
        // A dark shadow where the stands meet the turf.
        rect(-200, turfTop - 4, width + 400, 6, SKColor(white: 0, alpha: 0.6), z: -12)

        // Floodlight banks: a grid of soft lamps on a dark panel, a glow behind.
        var bank: CGFloat = 60
        while bank < width {
            let glow = SKSpriteNode(color: SKColor(red: 0.45, green: 0.75, blue: 1, alpha: 0.25), size: CGSize(width: 150, height: 90))
            glow.anchorPoint = .zero
            glow.position = CGPoint(x: bank - 15, y: lightsBottom - 20)
            glow.blendMode = .add
            glow.zPosition = -15
            parent.addChild(glow)
            rect(bank, lightsBottom, 120, 44, SKColor(red: 0.08, green: 0.12, blue: 0.22, alpha: 1), z: -14)
            for row in 0..<4 {
                for column in 0..<9 {
                    let lamp = SKShapeNode(circleOfRadius: 4)
                    lamp.fillColor = SKColor(white: 0.95 - CGFloat(row) * 0.05, alpha: 1)
                    lamp.strokeColor = .clear
                    lamp.position = CGPoint(x: bank + 8 + CGFloat(column) * 13, y: lightsBottom + 7 + CGFloat(row) * 10)
                    lamp.zPosition = -13
                    parent.addChild(lamp)
                }
            }
            bank += 360
        }

        // The turf: stripes every five yards, the yard lines leaning in, hashes, numbers.
        let inner = CGFloat(Stage.tileSize) * CGFloat(SpriteLibrary.pixelsPerUnit)
        let fieldWidth = width - 2 * inner
        let yard = fieldWidth / 100
        rect(-200, turfBottom - 40, width + 400, 40, turfLight, z: -11)
        rect(-200, turfBottom, width + 400, 4, chalk, z: -9)
        for band in 0..<20 {
            let left = inner + CGFloat(band) * 5 * yard, right = left + 5 * yard
            let colour = band % 2 == 0 ? turfLight : turfDark
            let bottom = turfBottom + 4
            quad([CGPoint(x: left, y: bottom), CGPoint(x: right, y: bottom),
                  CGPoint(x: lean(right, at: turfTop, from: bottom, to: turfTop, share: 0.12), y: turfTop),
                  CGPoint(x: lean(left, at: turfTop, from: bottom, to: turfTop, share: 0.12), y: turfTop)], colour, z: -10)
        }
        for line in 0...20 {
            let at = inner + CGFloat(line) * 5 * yard
            let bottom = turfBottom + 4
            let thick: CGFloat = line % 2 == 0 ? 2 : 1.5
            quad([CGPoint(x: at - thick, y: bottom), CGPoint(x: at + thick, y: bottom),
                  CGPoint(x: lean(at + thick * 0.6, at: turfTop, from: bottom, to: turfTop, share: 0.12), y: turfTop),
                  CGPoint(x: lean(at - thick * 0.6, at: turfTop, from: bottom, to: turfTop, share: 0.12), y: turfTop)], chalk, z: -8)
        }
        // Hashes each yard, a row near the bottom and one near the top.
        for step in 1..<100 where step % 5 != 0 {
            let at = inner + CGFloat(step) * yard
            for (y, height) in [(turfBottom + 8, CGFloat(6)), (turfTop - 18, CGFloat(4))] {
                let top = lean(at, at: y + height, from: turfBottom + 4, to: turfTop, share: 0.12)
                quad([CGPoint(x: at - 0.6, y: y), CGPoint(x: at + 0.6, y: y), CGPoint(x: top + 0.5, y: y + height), CGPoint(x: top - 0.5, y: y + height)], chalk, z: -8)
            }
        }
        // Numbers every ten yards, with the arrow toward the nearer goal.
        for ten in 1...9 {
            let at = inner + CGFloat(ten) * 10 * yard
            let number = ten <= 5 ? ten * 10 : (10 - ten) * 10
            let label = SKLabelNode(text: "\(number)")
            label.fontName = "Georgia-Bold"
            label.fontSize = 22
            label.fontColor = chalk
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: at, y: turfBottom + 30)
            label.yScale = 0.8
            label.zPosition = -7
            parent.addChild(label)
            if number != 50 {
                let pointsLeft = ten < 5
                let tip = at + (pointsLeft ? -22 : 22), back = at + (pointsLeft ? -15 : 15)
                quad([CGPoint(x: tip, y: turfBottom + 30), CGPoint(x: back, y: turfBottom + 33), CGPoint(x: back, y: turfBottom + 27)], chalk, z: -7)
            }
        }
    }

    /// A goalpost at a rim: the padded base behind it on the floor, the gold pole bending
    /// forward to the crossbar under the rim, and the two uprights rising from its ends.
    static func goalpost(at rim: CGPoint, backboard: Facing, into parent: SKNode) {
        let back = CGFloat(backboard.sign)
        let floor: CGFloat = 16
        let baseX = rim.x + back * 26
        let crossbarY = rim.y - 14
        let halfSpan: CGFloat = 24
        let base = SKShapeNode(rectOf: CGSize(width: 8, height: 40), cornerRadius: 3)
        base.fillColor = pad
        base.strokeColor = .clear
        base.position = CGPoint(x: baseX, y: floor + 20)
        base.zPosition = -5
        parent.addChild(base)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: baseX, y: floor + 40))
        path.addLine(to: CGPoint(x: baseX, y: crossbarY - 30))
        path.addQuadCurve(to: CGPoint(x: rim.x, y: crossbarY), control: CGPoint(x: baseX, y: crossbarY))
        path.move(to: CGPoint(x: rim.x - halfSpan, y: crossbarY))
        path.addLine(to: CGPoint(x: rim.x + halfSpan, y: crossbarY))
        for side in [-halfSpan, halfSpan] {
            path.move(to: CGPoint(x: rim.x + side, y: crossbarY))
            path.addLine(to: CGPoint(x: rim.x + side, y: crossbarY + 130))
        }
        let post = SKShapeNode(path: path)
        post.strokeColor = gold
        post.lineWidth = 3
        post.lineCap = .round
        post.lineJoin = .round
        post.zPosition = -4
        parent.addChild(post)
    }
}
