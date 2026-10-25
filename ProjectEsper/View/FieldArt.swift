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
    /// The turf's stripes and its chalk, EDG64 28, 27 and 16; below the sideline the lighter green.
    static let turfLight: RGB = PixelPalette.colours[28]
    static let turfDark: RGB = PixelPalette.colours[27]
    static let chalk: RGB = PixelPalette.colours[16]
    /// Shadows: a dark, greyed purple at two thirds.
    static let shadow = SKColor(red: 0.17, green: 0.13, blue: 0.21, alpha: 1)
    static let shadowAlpha: CGFloat = 0.66
    /// A shadow thins out and shrinks as its body rises: gone by this many art pixels up,
    /// and down to this share of its size there.
    static let shadowFadeHeight: CGFloat = 160
    static let shadowSmallest: CGFloat = 0.5
    /// The turf's lean: yard lines tip this share of their distance to the middle across
    /// the turf's height.
    static let turfLean: CGFloat = 0.12
    /// The floor line the feet stand on, in art pixels.
    static let floorLine: CGFloat = 16
    /// The down marker's height, standing on the top of the grass, in art pixels; its
    /// width follows the vector's 121 by 512.
    static let markerHeight: CGFloat = 48

    /// Sideways shift per pixel of height at `x`, the yard lines' slope there: positive up
    /// toward the middle. A shadow cast down takes it the other way.
    static func slope(at x: CGFloat, centre: CGFloat) -> CGFloat {
        (centre - x) * turfLean / (turfTop - (turfBottom + 4))
    }

    /// A point mirrored under the floor line and sheared with the turf, as its shadow falls.
    static func shadowPoint(_ point: CGPoint, centre: CGFloat) -> CGPoint {
        let height = point.y - floorLine
        return CGPoint(x: point.x - slope(at: point.x, centre: centre) * height, y: floorLine - height)
    }
    static let gold = SKColor(red: 0.93, green: 0.70, blue: 0.29, alpha: 1)
    static let pad = SKColor(red: 0.06, green: 0.13, blue: 0.31, alpha: 1)

    /// Art pixels, the floor's top at 16: the turf from `turfBottom` to `turfTop`, the
    /// floor line through its middle, the stands above to `standsTop`, and the lights over them.
    static let turfBottom: CGFloat = -24
    static let turfTop: CGFloat = 56
    static let standsTop: CGFloat = 192
    static let railY: CGFloat = 136
    static let lightsBottom: CGFloat = 210
    /// How far down the camera looks below the floor, in art pixels, so the turf shows round
    /// the players.
    static let viewBelowFloor: CGFloat = 32

    /// What the scene keeps hold of: the rail under the stands, which wears the possession's
    /// colour like the court's walls; the floodlights' blooms, likewise; and each yard
    /// number with its arrow, for the size slider.
    struct Handles {
        /// The two rails under the stands, one over the other.
        var rails: [SKSpriteNode]
        var blooms: [SKSpriteNode] = []
        /// The panels the lamps sit on, which also wear the possession's colour.
        var panels: [SKShapeNode] = []
        var numbers: [SKNode] = []
        /// The turf's picture, which doesn't glow; the end zones past its goal lines, left and right,
        /// white, for the scene to tint each its side's darkest tone.
        var turf: SKSpriteNode?
        var endZones: [SKSpriteNode] = []
    }

    static let railHeight: CGFloat = 12
    static let railGap: CGFloat = 4
    /// The bottoms of the two rails.
    static var railLines: [CGFloat] { [railY, railY - railHeight - railGap] }

    /// The turf's picture: from `turfLeft` along and from `turfBelow` up to `turfTop`, the stage's
    /// width and `turfOverhang` each side.
    static let turfLeft: CGFloat = -200
    static let turfOverhang: CGFloat = 200
    static var turfBelow: CGFloat { turfBottom - 40 }
    static let sidelineHeight = 4
    /// The yard lines' widths: every ten yards (the goal lines too), and the fives between.
    static let tenLineWidth = 2
    static let fiveLineWidth = 1

    /// The turf in art pixels, as pixel art's drawn: below the sideline the lighter green, the
    /// sideline, then the stripes every five yards between the yard lines, each line a stack of
    /// whole-pixel rows stepping in toward the middle as the turf leans back (`turfLean`); a hash
    /// every yard along the bottom and, shorter, the top, on the same lean. Past the goal lines,
    /// above the sideline, the end zones, each its own white picture the turf's size.
    static func turfTextures(width: CGFloat, centre: CGFloat) -> (turf: SKTexture, endZones: [SKTexture]) {
        let columns = Int(width + 2 * turfOverhang), rows = Int(turfTop - turfBelow)
        var pixels = [RGB](repeating: turfLight, count: columns * rows)
        var zones = [[RGB]](repeating: [RGB](repeating: 0, count: columns * rows), count: 2)
        let inner = CGFloat(Stage.tileSize) * CGFloat(SpriteLibrary.pixelsPerUnit)
        let yard = (width - 2 * inner) / 100
        let leanBottom = turfBottom + CGFloat(sidelineHeight)
        // Up from the picture's foot; a row's lean is at its middle.
        func set(_ x: Int, _ row: Int, _ colour: RGB) {
            guard x >= 0, x < columns, row >= 0, row < rows else { return }
            pixels[(rows - 1 - row) * columns + x] = colour
        }
        func column(_ x: CGFloat, row: Int) -> Int {
            let y = turfBelow + CGFloat(row) + 0.5
            let rise = (y - leanBottom) / (turfTop - leanBottom)
            return Int((x + (centre - x) * turfLean * rise - turfLeft).rounded(.down))
        }
        // A leaning line as pixel art draws one: each row's run reaches to just short of where the
        // next row's begins, so the runs meet corner to corner, never side by side; a steep line a
        // pixel a row. Wider, the run again a column over (steep) or a row up (shallow).
        func chalkStep(x: Int, next: Int, row: Int, width: Int) {
            let run = next > x ? x...(next - 1) : next < x ? (next + 1)...x : x...x
            for extra in 0..<width {
                let shallow = run.count > 1
                for at in run { set(at + (shallow ? 0 : extra), row + (shallow ? extra : 0), chalk) }
            }
        }
        let sideline = Int(turfBottom - turfBelow)
        for row in sideline..<rows {
            if row < sideline + sidelineHeight {
                for x in 0..<columns { set(x, row, chalk) }
                continue
            }
            let edges = (0...20).map { column(inner + CGFloat($0) * 5 * yard, row: row) }
            for band in 0..<20 {
                for x in edges[band]..<edges[band + 1] { set(x, row, band % 2 == 0 ? turfLight : turfDark) }
            }
            // Outside the goal lines, the end zones.
            for x in 0..<edges[0] {
                set(x, row, 0)
                zones[0][(rows - 1 - row) * columns + x] = 0xFFFFFF
            }
            for x in edges[20]..<columns {
                set(x, row, 0)
                zones[1][(rows - 1 - row) * columns + x] = 0xFFFFFF
            }
        }
        // The lines over every row's stripes, so a wide one's second row isn't painted over.
        for row in (sideline + sidelineHeight)..<rows {
            for line in 0...20 {
                let at = inner + CGFloat(line) * 5 * yard
                chalkStep(x: column(at, row: row), next: column(at, row: row + 1), row: row, width: line % 2 == 0 ? tenLineWidth : fiveLineWidth)
            }
        }
        // The hashes: five rows a little over the sideline, three a little under the top.
        let bottomHash = sideline + sidelineHeight + 4, topHash = rows - 4 - 3
        for step in 1..<100 where step % 5 != 0 {
            let at = inner + CGFloat(step) * yard
            for row in Array(bottomHash..<(bottomHash + 5)) + Array(topHash..<(topHash + 3)) {
                chalkStep(x: column(at, row: row), next: column(at, row: row + 1), row: row, width: 1)
            }
        }
        // Transparent where it's 0; opaque otherwise.
        func texture(_ pixels: [RGB]) -> SKTexture {
            let bytes = pixels.flatMap { colour -> [UInt8] in
                colour == 0 ? [0, 0, 0, 0] : [UInt8(colour >> 16 & 0xFF), UInt8(colour >> 8 & 0xFF), UInt8(colour & 0xFF), 255]
            }
            return pixelTexture(bytes, width: columns, height: rows)
        }
        return (texture(pixels), zones.map(texture))
    }

    /// Where a line along the turf at `x` (at its foot) is at height `y`, on the turf's lean.
    static func leaned(_ x: CGFloat, at y: CGFloat, centre: CGFloat) -> CGFloat {
        let leanBottom = turfBottom + CGFloat(sidelineHeight)
        return x + (centre - x) * turfLean * (y - leanBottom) / (turfTop - leanBottom)
    }

    /// Top-down RGBA bytes, premultiplied (each pixel opaque or clear), as a nearest-filtered texture.
    static func pixelTexture(_ bytes: [UInt8], width: Int, height: Int) -> SKTexture {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        return texture
    }

    /// The yard numbers' face (YARD FONT on the debug strip), each at the size its pixels are drawn
    /// for, one art pixel to its pixel.
    enum NumberFont: Int, CaseIterable {
        case boldPixels, sevenPixels, upheaval
        var label: String { ["BOLD", "7PX", "UPHEAVAL"][rawValue] }
        var name: String { ["BoldPixels", "7pixelsOfPerfect", "UpheavalTT-BRK-"][rawValue] }
        var size: CGFloat { [16, 16, 20][rawValue] }
    }
    nonisolated(unsafe) static var numberFont = NumberFont.boldPixels
    /// The numbers' middles this far up from the turf's foot, at this many art pixels to a face pixel.
    static let numberLift: CGFloat = 18
    static let numberScale = 2
    /// The 50's digits this far, in art pixels, from its line, the line running between them; every
    /// other number beside its line on the middle's side, its arrow's tip this far off the line,
    /// pointing at it, and the number this far past the arrow; the arrow's columns' heights, back to tip,
    /// in face pixels.
    static let digitGap = 4
    /// Between a number's two digits, in face pixels.
    static let digitSpacing = 1
    static let arrowGap = 3
    static let arrowColumns = [5, 3, 3, 1, 1]

    /// A digit's pixels in `numberFont`, rows top down, and its size, one pixel to a face pixel.
    private static func digitPixels(_ digit: String) -> (on: Set<[Int]>, width: Int, height: Int) {
        _ = Onomatopoeia.registered
        let font = CTFontCreateWithName(numberFont.name as CFString, numberFont.size, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: digit, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]))
        let ink = CTLineGetImageBounds(line, nil).integral
        let width = Int(ink.width), height = Int(ink.height)
        guard width > 0, height > 0 else { return ([], 0, 0) }
        var alpha = [UInt8](repeating: 0, count: width * height)
        alpha.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.setFillColor(gray: 1, alpha: 1)
            context.setShouldAntialias(false)
            context.textPosition = CGPoint(x: -ink.minX, y: -ink.minY)
            CTLineDraw(line, context)
        }
        var on = Set<[Int]>()
        for y in 0..<height { for x in 0..<width where alpha[y * width + x] >= 128 { on.insert([x, y]) } }
        return (on, width, height)
    }

    /// A yard number's pixels, from the group's `ten` and `slope`, in `numberFont`: the 50 either
    /// side of its line, the rest beside theirs with the arrow pointing at it; slid with the line's
    /// lean, a whole pixel at a time. Drawn again when the face changes.
    static func letter(_ group: SKNode) {
        group.removeAllChildren()
        guard let ten = group.userData?["ten"] as? Int else { return }
        // Laid flat on the turf: each row slid with the yard line's lean where it stands.
        let slope = group.userData?["slope"] as? CGFloat ?? 0
        let number = ten <= 5 ? ten * 10 : (10 - ten) * 10
        let scale = numberScale
        let tens = digitPixels("\(number / 10)"), ones = digitPixels("0")
        let height = max(tens.height, ones.height) * scale
        // Art pixels about the number's middle on its line, x right, y up.
        var on = Set<[Int]>()
        func paint(_ digit: (on: Set<[Int]>, width: Int, height: Int), left: Int) {
            let top = (digit.height * scale + height) / 2
            for pixel in digit.on {
                for dx in 0..<scale { for dy in 0..<scale { on.insert([left + pixel[0] * scale + dx, top - 1 - pixel[1] * scale - dy - height / 2]) } }
            }
        }
        let spaced = tens.width * scale + digitSpacing * scale + ones.width * scale
        if number == 50 {
            // The 50 straddles its line, a digit either side.
            paint(tens, left: -digitGap - tens.width * scale)
            paint(ones, left: digitGap)
        } else {
            // The rest beside their line on the middle's side, the arrow between pointing at it.
            let away = ten < 5 ? 1 : -1
            for (step, columnHeight) in arrowColumns.reversed().enumerated() {
                let near = digitGap + step * scale
                let x = away > 0 ? near : -near - scale
                let bottom = -columnHeight * scale / 2
                for dx in 0..<scale { for y in bottom..<(bottom + columnHeight * scale) { on.insert([x + dx, y]) } }
            }
            let start = digitGap + (arrowColumns.count + arrowGap) * scale
            let left = away > 0 ? start : -start - spaced
            paint(tens, left: left)
            paint(ones, left: left + spaced - ones.width * scale)
        }
        // Each row slid with the lean at its height, rounded to the pixel.
        let skewed = Set(on.map { [$0[0] + Int((slope * (CGFloat($0[1]) + 0.5)).rounded(.down)), $0[1]] })
        guard let minX = skewed.map({ $0[0] }).min(), let maxX = skewed.map({ $0[0] }).max(),
              let minY = skewed.map({ $0[1] }).min(), let maxY = skewed.map({ $0[1] }).max() else { return }
        let columns = maxX - minX + 1, rows = maxY - minY + 1
        let r = UInt8(chalk >> 16 & 0xFF), g = UInt8(chalk >> 8 & 0xFF), b = UInt8(chalk & 0xFF)
        var bytes = [UInt8](repeating: 0, count: columns * rows * 4)
        for pixel in skewed {
            let at = ((maxY - pixel[1]) * columns + pixel[0] - minX) * 4
            bytes[at] = r; bytes[at + 1] = g; bytes[at + 2] = b; bytes[at + 3] = 255
        }
        let sprite = SKSpriteNode(texture: pixelTexture(bytes, width: columns, height: rows))
        sprite.anchorPoint = .zero
        sprite.position = CGPoint(x: minX, y: minY)
        group.addChild(sprite)
    }

    static func build(for stage: Stage, into parent: SKNode, flat: (CGFloat) -> SKTexture, glow: SKTexture) -> Handles {
        let width = CGFloat(stage.columns) * 16
        let top = CGFloat(stage.rows + stage.skyRows) * 16
        let centre = width / 2
        @discardableResult
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ colour: SKColor, z: CGFloat = -10) -> SKSpriteNode {
            let node = SKSpriteNode(texture: flat(4))
            node.anchorPoint = .zero
            node.position = CGPoint(x: x, y: y)
            node.size = CGSize(width: w, height: h)
            node.color = colour
            node.colorBlendFactor = 1
            node.zPosition = z
            parent.addChild(node)
            return node
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
        // The rails: two bands in the possession's colour, a small gap between; the scene
        // fills them with chevrons.
        var handles = Handles(rails: railLines.map { rect(-200, $0, width + 400, railHeight, .black, z: -17) })
        // A dark shadow where the stands meet the turf.
        rect(-200, turfTop - 4, width + 400, 6, SKColor(white: 0, alpha: 0.6), z: -12)

        // Floodlight banks: a grid of soft lamps on a dark panel, a glow behind.
        var bank: CGFloat = 60
        while bank < width {
            // A wide soft bloom round the bank, spilling down onto the stands.
            let bloom = SKSpriteNode(texture: glow)
            bloom.size = CGSize(width: 300, height: 200)
            bloom.position = CGPoint(x: bank + 60, y: lightsBottom + 12)
            bloom.color = SKColor(red: 0.45, green: 0.75, blue: 1, alpha: 1)
            bloom.colorBlendFactor = 1
            bloom.alpha = 0.45
            bloom.blendMode = .add
            bloom.zPosition = -15
            parent.addChild(bloom)
            handles.blooms.append(bloom)
            // The panel, a trapezoid wider at the top.
            let panelPath = CGMutablePath()
            panelPath.addLines(between: [CGPoint(x: bank + 4, y: lightsBottom), CGPoint(x: bank + 116, y: lightsBottom),
                                         CGPoint(x: bank + 124, y: lightsBottom + 44), CGPoint(x: bank - 4, y: lightsBottom + 44)])
            panelPath.closeSubpath()
            let panel = SKShapeNode(path: panelPath)
            panel.strokeColor = SKColor(rgb: PixelPalette.aap64Outline)
            panel.lineWidth = GoalpostTuning.outline
            panel.zPosition = -14
            parent.addChild(panel)
            handles.panels.append(panel)
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

        // The turf, drawn in art pixels; its numbers apart, for the face picker.
        let textures = turfTextures(width: width, centre: centre)
        let turf = SKSpriteNode(texture: textures.turf)
        turf.anchorPoint = .zero
        turf.position = CGPoint(x: turfLeft, y: turfBelow)
        turf.zPosition = -10
        parent.addChild(turf)
        handles.turf = turf
        handles.endZones = textures.endZones.map { texture in
            let zone = SKSpriteNode(texture: texture)
            zone.anchorPoint = .zero
            zone.position = turf.position
            zone.zPosition = -10.01
            zone.colorBlendFactor = 1
            parent.addChild(zone)
            return zone
        }
        let inner = CGFloat(Stage.tileSize) * CGFloat(SpriteLibrary.pixelsPerUnit)
        let yard = (width - 2 * inner) / 100
        for ten in 1...9 {
            let group = SKNode()
            // On its line where it stands, the line through its middle; twice its face's size, whole pixels.
            let y = turfBottom + numberLift
            let foot = inner + CGFloat(ten) * 10 * yard
            // The ten-yard line's two pixels start at its leaned column; the number's middle between them.
            group.position = CGPoint(x: leaned(foot, at: y, centre: centre).rounded(.down) + CGFloat(tenLineWidth / 2), y: y)
            group.zPosition = -7
            group.userData = ["ten": ten, "slope": slope(at: foot, centre: centre)]
            parent.addChild(group)
            letter(group)
            handles.numbers.append(group)
        }
        return handles
    }

    /// A goalpost at a rim: the padded base behind it on the floor, the gold pole bending
    /// forward to the crossbar under the rim, and the two uprights rising from its ends.
    /// With `shadowOf`, the field's middle, it draws the goalpost's shadow instead: every
    /// point mirrored under the floor and sheared with the turf, all in the shadow colour.
    static func goalpost(at rim: CGPoint, backboard: Facing, into parent: SKNode, crossbarBelowRim: CGFloat, prongHeight: CGFloat,
                         angle: CGFloat, thickness: CGFloat, outline: CGFloat, padColour: SKColor, shadowOf centre: CGFloat? = nil) {
        let cast: (CGPoint) -> CGPoint = { point in centre.map { shadowPoint(point, centre: $0) } ?? point }
        let back = CGFloat(backboard.sign)
        let floor: CGFloat = 16
        let baseX = rim.x + back * 26
        let crossbarY = rim.y - crossbarBelowRim
        let halfSpan: CGFloat = 24
        // The pad is the pole's width and five more.
        let padHalf = (thickness + 5) / 2
        let padPath = CGMutablePath()
        padPath.addLines(between: [CGPoint(x: baseX - padHalf, y: floor), CGPoint(x: baseX + padHalf, y: floor),
                                   CGPoint(x: baseX + padHalf, y: floor + 40), CGPoint(x: baseX - padHalf, y: floor + 40)].map(cast))
        padPath.closeSubpath()
        let base = SKShapeNode(path: padPath)
        base.fillColor = centre == nil ? padColour : shadow
        base.strokeColor = centre == nil ? SKColor(rgb: PixelPalette.aap64Outline) : .clear
        base.lineWidth = outline
        base.zPosition = -5
        parent.addChild(base)
        // The back rod, from the pad bending forward to the crossbar's middle.
        let rod = CGMutablePath()
        rod.move(to: cast(CGPoint(x: baseX, y: floor + 40)))
        rod.addLine(to: cast(CGPoint(x: baseX, y: crossbarY - 30)))
        rod.addQuadCurve(to: cast(CGPoint(x: rim.x, y: crossbarY)), control: cast(CGPoint(x: baseX, y: crossbarY)))
        // The crossbar and its uprights, outlined on their own over the rod.
        let path = CGMutablePath()
        // The crossbar tilts about its middle, the end toward the field rising; each upright
        // stands on its end of it.
        let rise = tan(angle) * halfSpan * -back
        let ends = [(x: rim.x - halfSpan, y: crossbarY - rise), (x: rim.x + halfSpan, y: crossbarY + rise)]
        path.move(to: cast(CGPoint(x: ends[0].x, y: ends[0].y)))
        path.addLine(to: cast(CGPoint(x: ends[1].x, y: ends[1].y)))
        for end in ends {
            path.move(to: cast(CGPoint(x: end.x, y: end.y)))
            path.addLine(to: cast(CGPoint(x: end.x, y: end.y + prongHeight)))
        }
        // Each part the gold over a black line as wide as it plus the outline each side.
        let layers: [(SKColor, CGFloat, CGFloat)] = centre == nil
            ? [(SKColor(rgb: PixelPalette.aap64Outline), thickness + outline * 2, 0), (gold, thickness, 0.05)]
            : [(shadow, thickness, 0)]
        for (part, z) in [(rod as CGPath, CGFloat(-4.6)), (path as CGPath, CGFloat(-4.4))] {
            for (colour, width, lift) in layers {
                let post = SKShapeNode(path: part)
                post.strokeColor = colour
                post.lineWidth = width
                post.lineCap = .round
                post.lineJoin = .round
                post.zPosition = z + lift
                parent.addChild(post)
            }
        }
    }
}
