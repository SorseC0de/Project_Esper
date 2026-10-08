import EsperSim
import SpriteKit

/// A hand-laid stage's tiles, for drawing it and for the map maker: its sheets, each cut into
/// square cells of its own size, a placed tile's art cell counting across the sheets side by
/// side, `stride` columns kept for each. Every cell is drawn one tile, 16 art pixels, whatever its size.
final class MapTiles {
    let sheets: [SKTexture]
    private let cellSizes: [CGFloat]
    let stride: Int
    private var cut: [StageMap.Cell: SKTexture] = [:]
    private var filledBySheet: [Int: [StageMap.Cell]] = [:]

    private init(sheets: [SKTexture], cellSizes: [CGFloat], stride: Int? = nil) {
        self.sheets = sheets
        self.cellSizes = cellSizes
        self.stride = stride ?? max(Int((sheets.first?.size().width ?? cellSizes[0]) / cellSizes[0]), 1)
    }

    /// The Elements' one 16-pixel sheet.
    static let elements = MapTiles(sheets: [ElementsArt.tileset], cellSizes: [ElementsArt.tileSide])

    static func of(_ stage: MapStage) -> MapTiles { elements }

    func cellPixels(of sheet: Int) -> CGFloat { cellSizes[sheet] }
    func sheet(of art: StageMap.Cell) -> Int { art.column / stride }
    func columns(of sheet: Int) -> Int { max(Int(sheets[sheet].size().width / cellSizes[sheet]), 1) }
    func rows(of sheet: Int) -> Int { max(Int(sheets[sheet].size().height / cellSizes[sheet]), 1) }

    /// One cell, by its art cell across all the sheets.
    func tile(_ art: StageMap.Cell) -> SKTexture {
        if let made = cut[art] { return made }
        let index = min(sheet(of: art), sheets.count - 1)
        let sheet = sheets[index]
        let columns = CGFloat(self.columns(of: index)), rows = CGFloat(self.rows(of: index))
        let column = CGFloat(art.column - index * stride)
        let rect = CGRect(x: column / columns, y: (rows - 1 - CGFloat(art.row)) / rows, width: 1 / columns, height: 1 / rows)
        let texture = SKTexture(rect: rect, in: sheet)
        texture.filteringMode = sheet.filteringMode
        cut[art] = texture
        return texture
    }

    /// A sheet's cells with anything drawn in them, as art cells: what the map maker offers.
    func filled(sheet index: Int) -> [StageMap.Cell] {
        if let found = filledBySheet[index] { return found }
        let image = sheets[index].cgImage()
        var cells: [StageMap.Cell] = []
        if let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
           let data = context.data {
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixels = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
            let side = Int(cellSizes[index])
            for row in 0..<(image.height / side) {
                for column in 0..<(image.width / side) {
                    let drawn = (0..<side).contains { y in (0..<side).contains { x in pixels[((row * side + y) * image.width + column * side + x) * 4 + 3] > 0 } }
                    if drawn { cells.append(StageMap.Cell(index * stride + column, row)) }
                }
            }
        }
        filledBySheet[index] = cells
        return cells
    }
}

/// Where a placed tile's sprite is: its cell and its layer.
struct TileSpot: Hashable {
    var cell: StageMap.Cell
    var layer: Int
    /// The ground layer under everything on the stage but the backdrop, the layer over it just above.
    static func z(_ layer: Int) -> CGFloat { -8 + CGFloat(layer) * 0.1 }
}

/// K&A's scenery: the stage drawn whole in Aseprite (`K&A_Map.aseprite`, 592 by 304, one of its
/// pixels an art pixel, flattened by `Tools/aseprite.py`) in two pictures, the whole stage each:
/// `KAndABackdrop`, its layers up to the train tracks, behind the players; and `KAndAFront`, the
/// front pillars and the right train support, in front of them. The players draw between the
/// file's Train Tracks and Front Pillar L layers.
enum KAndAArt {
    struct Handles {
        var backdrop: SKSpriteNode?
        var front: SKSpriteNode?
        /// The red car's body, which sags under a body, and its wheels, which don't.
        var carBody: SKSpriteNode?
        var carWheels: SKSpriteNode?
        /// The street lights' cones, one a lamp.
        var cones: [SKSpriteNode] = []
    }
    /// Past the stage's edges: palette 30, the sky's own top.
    static let beyond: RGB = PixelPalette.colours[30]
    static let backdropZ: CGFloat = -7.8
    /// The car (`red_car.aseprite`, 128 by 48, its Body and Wheels layers each their own
    /// picture) just over the backdrop; its sag: down two pixels as someone lands on it, back up
    /// one and held there while they stay, up the last once they've gone, a pixel every few frames.
    static let carZ: CGFloat = backdropZ + 0.1
    static let sagStepFrames = 3
    /// The street lights' cones: from each lamp's bottom, a trapezoid `Light.topWidth` across at
    /// the lamp and `bottomWidth` at its foot, `drop` down, in the lamp's warm light, faint and
    /// added, fading to clear from `fadeFrom` of the way down; the LIGHT sliders', kept. Now and
    /// then one flickers.
    enum Light {
        static let keys = (top: "esper.kAndA.light.top", bottom: "esper.kAndA.light.bottom", drop: "esper.kAndA.light.drop", fade: "esper.kAndA.light.fade")
        nonisolated(unsafe) static var topWidth: CGFloat = stored(keys.top) ?? 8
        nonisolated(unsafe) static var bottomWidth: CGFloat = stored(keys.bottom) ?? 126
        nonisolated(unsafe) static var drop: CGFloat = stored(keys.drop) ?? 150
        nonisolated(unsafe) static var fadeFrom: CGFloat = stored(keys.fade) ?? 0.5
        private static func stored(_ key: String) -> CGFloat? { UserDefaults.standard.object(forKey: key).flatMap { $0 as? Double }.map { CGFloat($0) } }
        static func save() {
            UserDefaults.standard.set(Double(topWidth), forKey: keys.top)
            UserDefaults.standard.set(Double(bottomWidth), forKey: keys.bottom)
            UserDefaults.standard.set(Double(drop), forKey: keys.drop)
            UserDefaults.standard.set(Double(fadeFrom), forKey: keys.fade)
        }
    }
    static let coneAlpha: CGFloat = 0.12
    static let coneColour = SKColor(rgb: PixelPalette.colours[7])
    /// The cones over the wash, so the lights shine through it.
    static let coneZ: CGFloat = washZ + 1
    /// The wash over the whole stage: palette 30 at a tenth, on the camera at 95 as Hoopfish
    /// Hideaway's water is; the lights are drawn over it, the nets and the glow go through it.
    /// A tenth, WASH on the strip moving it, kept.
    static let washAlphaKey = "esper.kAndA.washAlpha"
    nonisolated(unsafe) static var washAlpha: CGFloat = {
        CGFloat(UserDefaults.standard.object(forKey: washAlphaKey) as? Double ?? 0.1)
    }()
    static let washZ: CGFloat = 95
    /// One chance in 600 a frame: a flicker every ten seconds or so.
    static let flickerChance = 1.0 / 600
    static let flickerFrames = 6...20

    /// A cone's picture as the sliders have it: the trapezoid, full at the top, clear at the
    /// foot from `fadeFrom` of the way down; its size, the wider width by the drop.
    static func conePicture() -> (texture: SKTexture, size: CGSize)? {
        let width = max(Light.topWidth, Light.bottomWidth, 1), height = max(Light.drop, 1)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            let cg = context.cgContext
            let path = CGMutablePath()
            path.move(to: CGPoint(x: width / 2 - Light.topWidth / 2, y: 0))
            path.addLine(to: CGPoint(x: width / 2 + Light.topWidth / 2, y: 0))
            path.addLine(to: CGPoint(x: width / 2 + Light.bottomWidth / 2, y: height))
            path.addLine(to: CGPoint(x: width / 2 - Light.bottomWidth / 2, y: height))
            path.closeSubpath()
            cg.addPath(path)
            cg.clip()
            let fade = min(max(Light.fadeFrom, 0), 0.999)
            let colours = [coneColour.cgColor, coneColour.cgColor, coneColour.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, fade, 1]) else { return }
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: height), options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return (texture, CGSize(width: width, height: height))
    }

    /// Each cone drawn again from the sliders, hung from its lamp's bottom.
    static func layCones(_ cones: [SKSpriteNode]) {
        guard let picture = conePicture() else { return }
        for (index, cone) in cones.enumerated() where index < KAndARules.lampXs.count {
            cone.texture = picture.texture
            cone.size = picture.size
            cone.anchorPoint = CGPoint(x: 0.5, y: 1)
            cone.position = CGPoint(x: CGFloat(KAndARules.lampXs[index] * SpriteLibrary.pixelsPerUnit), y: CGFloat(KAndARules.lampBottom * SpriteLibrary.pixelsPerUnit))
        }
    }

    static func build(into parent: SKNode, front frontParent: SKNode) -> Handles {
        var handles = Handles()
        func picture(_ name: String, z: CGFloat, into parent: SKNode) -> SKSpriteNode {
            let texture = SKTexture(imageNamed: name)
            texture.filteringMode = .nearest
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = .zero
            node.size = texture.size()
            node.zPosition = z
            parent.addChild(node)
            SKTexture.preload([texture]) {}
            return node
        }
        handles.backdrop = picture("KAndABackdrop", z: backdropZ, into: parent)
        handles.front = picture("KAndAFront", z: 0, into: frontParent)
        let carAt = CGPoint(x: CGFloat(KAndARules.carLeft * SpriteLibrary.pixelsPerUnit), y: CGFloat(KAndARules.floorRows) * ElementsArt.tileSide)
        let wheels = picture("KAndACarWheels", z: carZ, into: parent)
        wheels.position = carAt
        let body = picture("KAndACarBody", z: carZ + 0.1, into: parent)
        body.position = carAt
        handles.carWheels = wheels
        handles.carBody = body
        handles.cones = KAndARules.lampXs.map { _ in
            let cone = SKSpriteNode()
            cone.alpha = coneAlpha
            cone.blendMode = .add
            cone.zPosition = coneZ
            parent.addChild(cone)
            return cone
        }
        layCones(handles.cones)
        return handles
    }
}

/// Flight B411's scenery: the stage drawn whole in Aseprite (`Flight_Map.aseprite`, 1248 by 576, four
/// of its pixels to an art pixel, flattened by `Tools/aseprite.py`) in two pictures, the whole
/// stage each: `FlightB411Backdrop`, its layers up to the open bin, behind the players; and
/// `FlightB411Front`, the front chairs and the fade over them, in front of the players. The file's
/// hidden Player layer sits between the two, and is where the players draw.
enum FlightB411Art {
    struct Handles {
        var backdrop: SKSpriteNode?
        var front: SKSpriteNode?
    }

    /// Past the stage's edges, above, below and beside it as it leans: palette 30.
    static let beyond: RGB = PixelPalette.colours[30]
    /// Under everything else on the stage; the pictures' pixels to an art pixel.
    static let backdropZ: CGFloat = -7.8
    static let backdropScale: CGFloat = 4

    /// The backdrop into `parent` on the stage's ground, the front into `front`, over the players.
    /// The cart's sheet, `Cart`: 48 by 64 drawn at 2x, so 24 by 32 art pixels in 8-pixel cells;
    /// the cart its first two columns, 16 by 32, standing on its box's bottom left; the wheel the
    /// bottom right cell, two of them centred on the cart's bottom two cells, a pixel down. The
    /// wheels turn by the cart's rolling.
    static let wheelRadius: CGFloat = 3.5
    static func cart() -> (node: SKSpriteNode, wheels: [SKSpriteNode]) {
        let sheet = SKTexture(imageNamed: "Cart")
        sheet.filteringMode = .nearest
        let body = SKTexture(rect: CGRect(x: 0, y: 0, width: 2.0 / 3.0, height: 1), in: sheet)
        let node = SKSpriteNode(texture: body)
        // Stood on its wheels' line, so it tips about them.
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.size = CGSize(width: 16, height: 32)
        node.zPosition = 5
        let wheelArt = SKTexture(rect: CGRect(x: 2.0 / 3.0, y: 0, width: 1.0 / 3.0, height: 0.25), in: sheet)
        let wheels = [-4, 4].map { x -> SKSpriteNode in
            let wheel = SKSpriteNode(texture: wheelArt)
            wheel.size = CGSize(width: 8, height: 8)
            wheel.position = CGPoint(x: x, y: 4 - 1)
            wheel.zPosition = -0.1
            node.addChild(wheel)
            return wheel
        }
        // A texture draws as a blank square until it's reached the GPU, and these cuts of the
        // sheet aren't among what's warmed before play: loaded first, the cart hidden till then.
        node.isHidden = true
        SKTexture.preload([sheet, body, wheelArt]) { DispatchQueue.main.async { node.isHidden = false } }
        return (node, wheels)
    }

    /// The bins' open doors, `FlightB411OpenBin` (the file's Open Bin layer, 45 by 19 art pixels),
    /// one over each whole bin, its bottom left on the bin's, shown while the bin's open.
    static func openBins(into parent: SKNode) -> [SKSpriteNode] {
        let texture = SKTexture(imageNamed: "FlightB411OpenBin")
        texture.filteringMode = .nearest
        let doors = FlightB411Rules.binLefts.map { left -> SKSpriteNode in
            let door = SKSpriteNode(texture: texture)
            door.anchorPoint = .zero
            door.size = CGSize(width: 45, height: 19)
            door.position = CGPoint(x: (left * SpriteLibrary.pixelsPerUnit).rounded(), y: (FlightB411Rules.binBottom * SpriteLibrary.pixelsPerUnit).rounded())
            door.zPosition = backdropZ + 0.1
            door.isHidden = true
            parent.addChild(door)
            return door
        }
        SKTexture.preload([texture]) {}
        return doors
    }

    /// The hoopcase on its 48 by 48 canvas: the suitcase's middle 17 in from the left; the
    /// suitcase's top row 15 down from the canvas's top, its lowest row 39; the ring's centre 33
    /// down, its front half (over the net and the ball) from row 34. The top `caseMaskRows` of
    /// the suitcase are never drawn: the case rotates about that line and slides out past it.
    static let hoopcaseCanvas: CGFloat = 48
    static let hoopcaseRing = CGPoint(x: 17, y: 33)
    static let caseTopRow: CGFloat = 15
    static let caseBottomRow: CGFloat = 40
    static let caseFrontRow: CGFloat = 34
    static let caseMaskRows: CGFloat = 3
    /// How much of the plane's lean the hanging case takes, swinging about its top.
    static let caseSwing: CGFloat = 0.5

    /// The case's two pieces, cut from the sheet once as textures of their own (a shader's
    /// texture coordinates run over the whole of a texture, so a cut of a sheet would mislay
    /// the mask): the back, the suitcase and the ring's back half, and the front, the ring's
    /// front half.
    static func casePieces(sheet: CGImage) -> (back: SKTexture, front: SKTexture)? {
        func rows(_ first: CGFloat, _ last: CGFloat) -> SKTexture? {
            guard let cut = sheet.cropping(to: CGRect(x: 0, y: first, width: hoopcaseCanvas, height: last - first)) else { return nil }
            let texture = SKTexture(cgImage: cut)
            texture.filteringMode = .nearest
            return texture
        }
        guard let back = rows(caseTopRow, caseFrontRow), let front = rows(caseFrontRow, caseBottomRow) else { return nil }
        return (back, front)
    }

    /// The mask line in the stage's frame: whatever of a piece is above the line, as the piece
    /// is turned and slid, isn't drawn. The line passes through the piece's anchor; `u_anchor`
    /// and `u_size` put a fragment in the piece's own units, `u_swing` turns it as the piece is.
    /// Checked in a headless render (a sprite turned 0.4 cuts level at its anchor's height):
    /// the fragment's place turned by the swing is `(sin, cos)` of it, and the sample is
    /// snapped to the texel so the piece stays crisp as drawn.
    static let caseMaskSource = """
    void main() {
        vec2 texel = floor(v_tex_coord * u_size) + 0.5;
        vec2 uv = texel / u_size;
        vec2 p = (uv - u_anchor) * u_size;
        float up = sin(u_swing) * p.x + cos(u_swing) * p.y;
        if (up > 0.0) discard;
        gl_FragColor = texture2D(u_texture, uv);
    }
    """
    static func caseMaskShader() -> SKShader {
        let shader = SKShader(source: caseMaskSource)
        shader.uniforms = [SKUniform(name: "u_swing", float: 0), SKUniform(name: "u_size", vectorFloat2: vector_float2(1, 1)),
                           SKUniform(name: "u_anchor", vectorFloat2: vector_float2(0, 1))]
        return shader
    }

    /// The case's two pieces laid for a slide of `out` (0 in the bin to 1 hanging): each hung
    /// from `anchor`, the mask line at the suitcase's middle, and turned about it by `swing`,
    /// the case's top `caseMaskRows` above the line when it's out, and further up as it slides
    /// in; its shader cuts what's above the line.
    static func layCase(back: SKSpriteNode, front: SKSpriteNode, out: CGFloat, anchor: CGPoint, swing: CGFloat) {
        let caseRows = caseBottomRow - caseTopRow
        // Rows from the case's top down to the line, as it stands.
        let toLine = caseMaskRows + (1 - out) * caseRows
        func lay(_ node: SKSpriteNode, top: CGFloat, rows: CGFloat) {
            node.size = CGSize(width: hoopcaseCanvas, height: rows)
            // The anchor on the line: this piece's top is `top` rows under the case's.
            let anchorPoint = CGPoint(x: hoopcaseRing.x / hoopcaseCanvas, y: 1 - (toLine - top) / rows)
            node.anchorPoint = anchorPoint
            node.position = anchor
            node.zRotation = swing
            node.isHidden = toLine - top >= rows
            if let shader = node.shader {
                shader.uniformNamed("u_swing")?.floatValue = Float(swing)
                shader.uniformNamed("u_size")?.vectorFloat2Value = vector_float2(Float(hoopcaseCanvas), Float(rows))
                shader.uniformNamed("u_anchor")?.vectorFloat2Value = vector_float2(Float(anchorPoint.x), Float(anchorPoint.y))
            }
        }
        lay(back, top: 0, rows: caseFrontRow - caseTopRow)
        lay(front, top: caseFrontRow - caseTopRow, rows: caseBottomRow - caseFrontRow)
    }

    /// A hoopcase in a side's colours, as a picture to cut: the suitcase's main grey, as drawn,
    /// becomes the energy's glow and its lighter grey the glow lifted as a body's is; the ring
    /// and the lines stay. Cached by colour.
    nonisolated(unsafe) private static var hoopcases: [String: CGImage] = [:]
    static func hoopcase(glow: SKColor, lifted: SKColor) -> CGImage? {
        let key = "\(glow)|\(lifted)"
        if let made = hoopcases[key] { return made }
        guard let image = UIImage(named: "Hoopcase")?.cgImage else { return nil }
        let width = image.width, height = image.height
        func bytes(_ colour: SKColor) -> (UInt8, UInt8, UInt8) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            colour.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (UInt8((r * 255).rounded()), UInt8((g * 255).rounded()), UInt8((b * 255).rounded()))
        }
        let light = bytes(lifted), dark = bytes(glow)
        // The context's bytes are the array's, so everything with it happens while the array's
        // pointer holds: drawn in, swapped, and the image made before the pointer's scope ends.
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let made: CGImage? = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            for index in stride(from: 0, to: data.count, by: 4) where data[index + 3] == 255 {
                let pixel = (data[index], data[index + 1], data[index + 2])
                let swap: (UInt8, UInt8, UInt8)?
                if pixel == (139, 147, 175) { swap = light } else if pixel == (109, 117, 141) { swap = dark } else { swap = nil }
                if let swap { (data[index], data[index + 1], data[index + 2]) = swap }
            }
            return context.makeImage()
        }
        guard let made else { return nil }
        hoopcases[key] = made
        return made
    }

    /// NO DUNKING, in the dark over the bins: the sign in palette 7, glowing, and over it the red
    /// "no", a ring and a slash, glowing too. Centred on the stage, halfway up the band over the bins.
    static func noDunkingSign(into parent: SKNode) -> (holder: SKNode, sprites: [SKSpriteNode]) {
        let holder = SKNode()
        let centre = CGPoint(x: (CGFloat(FlightB411Rules.width / Stage.tileSize) * ElementsArt.tileSide / 2).rounded(),
                             y: ((FlightB411Rules.binTop * SpriteLibrary.pixelsPerUnit + CGFloat(FlightB411Rules.rows) * ElementsArt.tileSide) / 2).rounded())
        holder.position = centre
        holder.zPosition = backdropZ + 0.2
        let texture = SKTexture(imageNamed: "FlightB411NoDunking")
        texture.filteringMode = .nearest
        let belt = seatbelt
        // Side by side, a gap between, the row centred: NO DUNKING, then the seatbelt.
        let row = signWidth + signGap + beltWidth
        let sign = SKSpriteNode(texture: texture)
        sign.size = CGSize(width: signWidth, height: 24)
        sign.position = CGPoint(x: -row / 2 + signWidth / 2, y: 0)
        holder.addChild(sign)
        // The "no" drawn once as a picture, so the glow can be told of it as of the sign.
        let no = SKSpriteNode(texture: noTexture)
        no.size = CGSize(width: noRadius * 2 + 4, height: noRadius * 2 + 4)
        no.position = sign.position
        no.zPosition = 0.1
        holder.addChild(no)
        let seatbelt = SKSpriteNode(texture: belt)
        seatbelt.size = CGSize(width: beltWidth, height: 24)
        seatbelt.position = CGPoint(x: row / 2 - beltWidth / 2, y: 0)
        holder.addChild(seatbelt)
        laySigns(sign: sign, no: no, seatbelt: seatbelt)
        parent.addChild(holder)
        SKTexture.preload([texture, noTexture, belt, seatbeltOff]) {}
        return (holder, [sign, no, seatbelt])
    }
    /// The seatbelt sign lit, glowing, through the count while the ball's shut in its bin: its
    /// arrow red and the rest palette 7.
    static let seatbelt: SKTexture = {
        let texture = SKTexture(imageNamed: "FlightB411Seatbelt")
        texture.filteringMode = .nearest
        return texture
    }()
    /// The seatbelt sign off once play's begun, not glowing: the red palette 2, the gold palette 33.
    static let seatbeltOff: SKTexture = {
        guard let image = UIImage(named: "FlightB411Seatbelt")?.cgImage else { return seatbelt }
        let width = image.width, height = image.height
        let red = PixelPalette.colours[2], gold = PixelPalette.colours[33]
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let made: CGImage? = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            for index in stride(from: 0, to: data.count, by: 4) where data[index + 3] > 0 {
                // The arrow's red has hardly any green in it; the gold's green is two thirds its red.
                let isRed = Double(data[index + 1]) < Double(data[index]) * 0.4
                let target = isRed ? red : gold
                let alpha = Double(data[index + 3]) / 255
                data[index] = UInt8((Double((target >> 16) & 0xFF) * alpha).rounded())
                data[index + 1] = UInt8((Double((target >> 8) & 0xFF) * alpha).rounded())
                data[index + 2] = UInt8((Double(target & 0xFF) * alpha).rounded())
            }
            return context.makeImage()
        }
        guard let made else { return seatbelt }
        let texture = SKTexture(cgImage: made)
        texture.filteringMode = .nearest
        return texture
    }()
    static let noRadius: CGFloat = 16
    /// Red, lifted enough to pass the glow's threshold.
    static let noRed = SKColor(red: 1, green: 0.16, blue: 0.16, alpha: 1)
    /// The ring and the slash, red, on a clear square.
    static let noTexture: SKTexture = {
        let side = noRadius * 2 + 4
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            cg.setStrokeColor(noRed.cgColor)
            cg.setLineWidth(2)
            cg.setLineCap(.round)
            cg.strokeEllipse(in: CGRect(x: 2, y: 2, width: noRadius * 2, height: noRadius * 2))
            let across = noRadius * 0.7071
            cg.move(to: CGPoint(x: side / 2 - across, y: side / 2 - across))
            cg.addLine(to: CGPoint(x: side / 2 + across, y: side / 2 + across))
            cg.strokePath()
        }
        return SKTexture(image: image)
    }()
    /// The signs in their row, the seatbelt at its own scale (`beltScale`), a gap of 12 between, the row centred.
    static let signWidth: CGFloat = 22, beltWidth: CGFloat = 118, signGap: CGFloat = 12
    static func laySigns(sign: SKSpriteNode, no: SKSpriteNode, seatbelt: SKSpriteNode) {
        let belt = beltWidth * beltScale
        let row = signWidth + signGap + belt
        sign.position = CGPoint(x: -row / 2 + signWidth / 2, y: 0)
        no.position = sign.position
        seatbelt.setScale(beltScale)
        seatbelt.position = CGPoint(x: row / 2 - belt / 2, y: 0)
    }
    /// The seatbelt's own scale against the sign's: 0.4, baked.
    static let beltScale: CGFloat = 0.4
    /// The signs' size, the NO DUNK SCALE slider's, kept between launches; half to start.
    static let signScaleKey = "esper.flightB411.signScale.2"
    nonisolated(unsafe) static var signScale: CGFloat = {
        CGFloat(UserDefaults.standard.object(forKey: signScaleKey) as? Double ?? 0.5)
    }()
    /// How much the cart tips with its speed, into the way it's going, about its wheels; flat
    /// at rest.
    static let cartSpeedTip: CGFloat = 0.06

    /// A cloud, `FlightB411Cloud` (192 by 64), for the sky beyond the plane, at two thirds.
    static let cloud: SKTexture = {
        let texture = SKTexture(imageNamed: "FlightB411Cloud")
        texture.filteringMode = .nearest
        SKTexture.preload([texture]) {}
        return texture
    }()
    static let cloudAlpha: CGFloat = 0.66
    /// The plane itself, `FlightB411Plane` (464 by 368, `plane.png`), faint under the clouds and
    /// pitching with the stage: fitted to the stage's width, centred on it, at a fifth.
    static let plane: SKTexture = {
        let texture = SKTexture(imageNamed: "FlightB411Plane")
        texture.filteringMode = .nearest
        SKTexture.preload([texture]) {}
        return texture
    }()
    static let planeAlpha: CGFloat = 0.2
    /// The hoopcase's suitcase in brown, anyone's: its light grey (palette 39) as palette 34, its
    /// dark grey (40) as 33.
    static let caseLight: RGB = PixelPalette.colours[34]
    static let caseDark: RGB = PixelPalette.colours[33]
    /// The plane's size against the stage's width, the PLANE SCALE slider's, kept; 3 baked.
    static let planeScaleKey = "esper.flightB411.planeScale"
    nonisolated(unsafe) static var planeScale: CGFloat = {
        CGFloat(UserDefaults.standard.object(forKey: planeScaleKey) as? Double ?? 3)
    }()
    /// The plane moved up from the stage's middle, in art pixels: PLANE Y on the strip, kept; -80 baked.
    static let planeYKey = "esper.flightB411.planeY"
    nonisolated(unsafe) static var planeY: CGFloat = {
        CGFloat(UserDefaults.standard.object(forKey: planeYKey) as? Double ?? -80)
    }()
    static var planeSize: CGSize {
        let width = CGFloat(FlightB411Rules.width / Stage.tileSize) * ElementsArt.tileSide * planeScale
        return CGSize(width: width, height: width * plane.size().height / max(plane.size().width, 1))
    }
    /// The stage's middle, in its ground's space.
    static var stageCentre: CGPoint {
        CGPoint(x: CGFloat(FlightB411Rules.width / Stage.tileSize) * ElementsArt.tileSide / 2, y: CGFloat(FlightB411Rules.rows) * ElementsArt.tileSide / 2)
    }

    static func build(into parent: SKNode, front frontParent: SKNode) -> Handles {
        var handles = Handles()
        func picture(_ name: String, z: CGFloat, into parent: SKNode) -> SKSpriteNode {
            let texture = SKTexture(imageNamed: name)
            texture.filteringMode = .nearest
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = .zero
            node.size = CGSize(width: texture.size().width / backdropScale, height: texture.size().height / backdropScale)
            node.position = CGPoint(x: ((CGFloat(FlightB411Rules.width / Stage.tileSize) * ElementsArt.tileSide - node.size.width) / 2).rounded(), y: 0)
            node.zPosition = z
            parent.addChild(node)
            return node
        }
        handles.backdrop = picture("FlightB411Backdrop", z: backdropZ, into: parent)
        handles.front = picture("FlightB411Front", z: 0, into: frontParent)
        return handles
    }
}
