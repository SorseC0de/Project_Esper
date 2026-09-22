import CoreGraphics
import EsperSim
import SpriteKit

/// Every frame in the atlas, looked up by the importer's names, drawn as pixels. Player
/// frames come out in that player's look and the ball in its colour, recoloured once each
/// and kept, and the library remembers where the ball and the head sit in each frame.
final class SpriteLibrary {
    static let pixelsPerUnit = 1.6
    /// The sheets' white is the ball where it's the biggest blob of white in the frame and
    /// at least this many pixels; the rest of the white is energy. The importer agrees.
    static let ballMinPixels = 12

    private let atlas = SKTextureAtlas(named: "Sprites")
    private var cache: [String: SKTexture] = [:]
    /// Where the glowing parts sit in each player frame, in art pixels from the feet.
    private var landmarks: [String: [BodyPart: CGPoint]] = [:]
    private var looks = Look.byPlayer

    func look(for player: Int) -> Look {
        looks[min(player, looks.count - 1)]
    }

    /// Changes what a player is drawn in; their frames are recoloured again as they're used.
    func setLook(_ look: Look, for player: Int) {
        guard look != looks[player] else { return }
        looks[player] = look
        cache = cache.filter { !$0.key.hasPrefix("p\(player)_") }
    }

    /// A non-player frame, from the atlas or, like the ball, from the catalog's root.
    func texture(_ name: String, _ frame: Int) -> SKTexture {
        let key = "\(name)_\(frame)"
        if let texture = cache[key] { return texture }
        let texture = atlas.textureNames.contains(key) ? atlas.textureNamed(key) : SKTexture(imageNamed: key)
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    /// A player frame in that player's look, without its head or its energy.
    func texture(_ frame: AnimationFrame, player: Int) -> SKTexture {
        let key = "p\(player)_\(frame.animation.rawValue)_\(frame.frame)"
        if let texture = cache[key] { return texture }
        let look = look(for: player)
        let result = recolour(atlas.textureNamed("\(frame.animation.rawValue)_\(frame.frame)"), look: look,
                              holdsBall: frame.animation.holdsBall, detach: true)
        let texture = result.texture
        texture.filteringMode = .nearest
        cache[key] = texture
        if let head = result.head {
            head.filteringMode = .nearest
            cache[key + "_head"] = head
        }
        if let energy = result.energy {
            energy.filteringMode = .nearest
            cache[key + "_energy"] = energy
        }
        let size = frame.animation.pixelSize
        landmarks[key] = result.centres.mapValues { centre in
            CGPoint(x: centre.x - size / 2, y: size - centre.y - frame.animation.feetFromBottom)
        }
        return texture
    }

    /// The head alone from a player frame, on the same canvas as the body, if the frame has one.
    func headTexture(_ frame: AnimationFrame, player: Int) -> SKTexture? {
        _ = texture(frame, player: player)
        return cache["p\(player)_\(frame.animation.rawValue)_\(frame.frame)_head"]
    }

    /// The energy alone from a player frame, on the same canvas as the body: the slash's
    /// blade, the skid's puffs, a release's streaks. Nil when the frame has none.
    func energyTexture(_ frame: AnimationFrame, player: Int) -> SKTexture? {
        _ = texture(frame, player: player)
        return cache["p\(player)_\(frame.animation.rawValue)_\(frame.frame)_energy"]
    }

    /// An effect frame in a player's energy colour: the sheet's greys through the look's
    /// tone ramp, its alpha kept.
    func effectTexture(_ name: String, _ frame: Int, player: Int) -> SKTexture {
        let key = "p\(player)_fx_\(name)_\(frame)"
        if let texture = cache[key] { return texture }
        let look = look(for: player)
        let source = texture(name, frame)
        let image = source.cgImage()
        let width = image.width, height = image.height
        guard let (context, pixels) = makeCanvas(width: width, height: height) else { return source }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let alpha = Int(pixels[index + 3])
            guard alpha > 0 else { continue }
            // The canvas is premultiplied: the grey level is the colour over the alpha.
            let grey = (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / Double(alpha)
            let tone = look.energyTone(luminance: min(grey, 1))
            pixels[index] = UInt8(Int((tone >> 16) & 0xFF) * alpha / 255)
            pixels[index + 1] = UInt8(Int((tone >> 8) & 0xFF) * alpha / 255)
            pixels[index + 2] = UInt8(Int(tone & 0xFF) * alpha / 255)
        }
        guard let toned = context.makeImage() else { return source }
        let result = SKTexture(cgImage: toned)
        result.filteringMode = .nearest
        cache[key] = result
        return result
    }

    func effectFrames(_ effect: EnergyEffect, player: Int) -> [SKTexture] {
        (0..<effect.frameCount).map { effectTexture(effect.name, $0, player: player) }
    }

    /// Where a glowing part is drawn in a player frame, from the feet in art pixels, if it's there.
    func landmark(_ part: BodyPart, in frame: AnimationFrame, player: Int) -> CGPoint? {
        _ = texture(frame, player: player)
        return landmarks["p\(player)_\(frame.animation.rawValue)_\(frame.frame)"]?[part]
    }

    func frames(_ name: String, count: Int) -> [SKTexture] {
        (0..<count).map { texture(name, $0) }
    }

    /// Where the feet sit in the sprite, as an anchor.
    func anchor(for animation: Animation) -> CGPoint {
        CGPoint(x: 0.5, y: animation.feetFromBottom / animation.pixelSize)
    }

    /// Units to whole screen pixels.
    static func point(_ v: Vec2) -> CGPoint {
        CGPoint(x: (v.x * pixelsPerUnit).rounded(), y: (v.y * pixelsPerUnit).rounded())
    }

    // MARK: Recolouring

    /// The head's centre in a player frame as an anchor on its canvas, for scaling the
    /// head about itself.
    func headAnchor(_ frame: AnimationFrame, player: Int) -> CGPoint? {
        guard let head = landmark(.head, in: frame, player: player) else { return nil }
        let size = frame.animation.pixelSize
        return CGPoint(x: (head.x + size / 2) / size, y: (head.y + frame.animation.feetFromBottom) / size)
    }

    /// Everything made so far.
    var allTextures: [SKTexture] { Array(cache.values) }

    /// Builds every frame of every player up front and sends them to the GPU, so nothing
    /// is made mid-draw.
    func warmUp(players: Int, completion: @escaping () -> Void) {
        for player in 0..<players {
            for animation in Animation.allCases {
                for frame in 0..<animation.frameCount {
                    _ = texture(AnimationFrame(animation, frame), player: player)
                }
            }
            for effect in EnergyEffect.allCases {
                _ = effectFrames(effect, player: player)
            }
        }
        _ = texture("ball", 0)
        _ = softGlow(diameter: 32)
        _ = softGlow(diameter: 8)
        _ = feather()
        _ = flatSquare(size: 16, alpha: 1)
        _ = flatSquare(size: 4, alpha: 1)
        _ = symbol("chevron.down", pointSize: 14)
        _ = symbol("chevron.down", pointSize: 10)
        SKTexture.preload(Array(cache.values), withCompletionHandler: completion)
    }

    /// A clear canvas. The memory a context is given isn't promised to be clean, and a frame
    /// drawn over leftovers keeps them in its transparent area, so it's wiped first.
    private func makeCanvas(width: Int, height: Int) -> (CGContext, UnsafeMutablePointer<UInt8>)? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return (context, data.bindMemory(to: UInt8.self, capacity: width * height * 4))
    }

    /// A copy of the frame in the look: every part swapped to its colour, the stroked parts
    /// lined where they lie over the body, the silhouette lined round the outside, and the
    /// centre of each glowing part found. The ball is looked for only where the sheet
    /// `holdsBall`. With `detach`, the head and the energy come back as their own textures
    /// with no line, and the body is drawn and lined without them.
    private func recolour(_ texture: SKTexture, look: Look, holdsBall: Bool, detach: Bool) -> (texture: SKTexture, head: SKTexture?, energy: SKTexture?, centres: [BodyPart: CGPoint]) {
        let image = texture.cgImage()
        let width = image.width, height = image.height
        guard let (context, pixels) = makeCanvas(width: width, height: height) else { return (texture, nil, nil, [:]) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let count = width * height

        // Which part each pixel came from, before anything changes.
        var parts = [BodyPart?](repeating: nil, count: count)
        for pixel in 0..<count where pixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            let colour = RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])
            parts[pixel] = BodyPart.owning(colour)
        }
        markEnergy(&parts, holdsBall: holdsBall, width: width, height: height)

        // Each part to its colour; the energy to the tone of its own brightness.
        var sums: [BodyPart: (x: CGFloat, y: CGFloat, n: Int)] = [:]
        for pixel in 0..<count {
            guard let part = parts[pixel] else { continue }
            let index = pixel * 4
            if part.glows {
                var sum = sums[part] ?? (0, 0, 0)
                sum.x += CGFloat(pixel % width) + 0.5
                sum.y += CGFloat(pixel / width) + 0.5
                sum.n += 1
                sums[part] = sum
            }
            if part.isEnergy {
                let grey = (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / 255
                paint(pixels, index, look.energyTone(luminance: grey))
            } else if let target = look.colours[part] {
                paint(pixels, index, target)
            }
        }

        // The head and the energy onto their own canvases, and off this one; the ball off
        // this one too, since it's drawn as its own sprite wherever the frame puts it.
        var head: SKTexture?
        var energy: SKTexture?
        if detach {
            let headCanvas = sums[.head] != nil ? makeCanvas(width: width, height: height) : nil
            let energyCanvas = parts.contains { $0?.isEnergy == true } ? makeCanvas(width: width, height: height) : nil
            for pixel in 0..<count {
                guard let part = parts[pixel], part == .head || part == .ball || part.isEnergy else { continue }
                let index = pixel * 4
                if part == .head, let (_, headPixels) = headCanvas {
                    paint(headPixels, index, look.colours[.head] ?? look.glow)
                    headPixels[index + 3] = 255
                } else if part.isEnergy, let (_, energyPixels) = energyCanvas {
                    energyPixels[index] = pixels[index]
                    energyPixels[index + 1] = pixels[index + 1]
                    energyPixels[index + 2] = pixels[index + 2]
                    energyPixels[index + 3] = 255
                }
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
                pixels[index + 3] = 0
                parts[pixel] = nil
            }
            head = headCanvas?.0.makeImage().map { SKTexture(cgImage: $0) }
            energy = energyCanvas?.0.makeImage().map { SKTexture(cgImage: $0) }
        }

        func neighbours(_ pixel: Int, _ body: (Int) -> Bool) -> Bool {
            let x = pixel % width, y = pixel / width
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, ny >= 0, nx < width, ny < height, body(ny * width + nx) { return true }
                }
            }
            return false
        }

        // Stroked parts: the body pixels next to them take the line, so the part keeps its shape.
        if !look.strokedParts.isEmpty {
            let stroked = parts.map { $0.map(look.strokedParts.contains) ?? false }
            for pixel in 0..<count where parts[pixel] != nil && !stroked[pixel] && neighbours(pixel, { stroked[$0] }) {
                paint(pixels, pixel * 4, look.outline)
            }
        }

        // The outside line, grown a pixel at a time round the body. The glowing parts get
        // none: a clear pixel next to nothing but the ball stays clear.
        if look.outlineWidth > 0 {
            var body = (0..<count).map { pixels[$0 * 4 + 3] != 0 && parts[$0]?.glows != true }
            for _ in 0..<look.outlineWidth {
                var grown: [Int] = []
                for pixel in 0..<count where pixels[pixel * 4 + 3] == 0 && neighbours(pixel, { body[$0] }) {
                    grown.append(pixel)
                }
                for pixel in grown {
                    paint(pixels, pixel * 4, look.outline)
                    pixels[pixel * 4 + 3] = 255
                    body[pixel] = true
                }
            }
        }

        guard let recoloured = context.makeImage() else { return (texture, nil, nil, [:]) }
        let centres = sums.mapValues { CGPoint(x: $0.x / CGFloat($0.n), y: $0.y / CGFloat($0.n)) }
        return (SKTexture(cgImage: recoloured), head, energy, centres)
    }

    /// The sheets' white is the ball only on a sheet that holds it, and there only where
    /// it's the biggest 8-connected blob of white in the frame and big enough to be one;
    /// every other white pixel becomes energy: the skid's puffs, a release's streaks, the
    /// slide's speed lines.
    private func markEnergy(_ parts: inout [BodyPart?], holdsBall: Bool, width: Int, height: Int) {
        guard holdsBall else {
            for pixel in parts.indices where parts[pixel] == .ball { parts[pixel] = .energy }
            return
        }
        var label = [Int](repeating: 0, count: parts.count)
        var sizes = [0]
        for start in parts.indices where parts[start] == .ball && label[start] == 0 {
            let id = sizes.count
            sizes.append(0)
            label[start] = id
            var stack = [start]
            while let pixel = stack.popLast() {
                sizes[id] += 1
                let x = pixel % width, y = pixel / width
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let neighbour = ny * width + nx
                        if parts[neighbour] == .ball, label[neighbour] == 0 {
                            label[neighbour] = id
                            stack.append(neighbour)
                        }
                    }
                }
            }
        }
        guard sizes.count > 1, let biggest = sizes.indices.dropFirst().max(by: { sizes[$0] < sizes[$1] }) else { return }
        let ball = sizes[biggest] >= SpriteLibrary.ballMinPixels ? biggest : 0
        for pixel in parts.indices where parts[pixel] == .ball && label[pixel] != ball {
            parts[pixel] = .energy
        }
    }

    private func paint(_ pixels: UnsafeMutablePointer<UInt8>, _ index: Int, _ colour: RGB) {
        pixels[index] = UInt8((colour >> 16) & 0xFF)
        pixels[index + 1] = UInt8((colour >> 8) & 0xFF)
        pixels[index + 2] = UInt8(colour & 0xFF)
    }

    // MARK: Generated textures

    /// A soft round white glow, bright in the middle and clear at the edge, for additive
    /// halos and particles; the node colours it.
    func softGlow(diameter: Int) -> SKTexture {
        let colour = SKColor.white
        let key = "glow_\(diameter)"
        if let texture = cache[key] { return texture }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter), format: format)
        let image = renderer.image { context in
            let colours = [colour.cgColor, colour.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1])!
            let centre = CGPoint(x: CGFloat(diameter) / 2, y: CGFloat(diameter) / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                                 endRadius: CGFloat(diameter) / 2, options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    /// A flat white square, `size` pixels, at `alpha`, for tiles the node colours.
    func flatSquare(size: Int, alpha: CGFloat) -> SKTexture {
        let key = "square_\(size)_\(alpha)"
        if let texture = cache[key] { return texture }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let image = renderer.image { context in
            SKColor(white: 1, alpha: alpha).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    /// A soft white feather: a petal, bright down the middle and clear at the edges.
    func feather() -> SKTexture {
        let key = "feather"
        if let texture = cache[key] { return texture }
        let width = 12, height = 36
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            let path = CGMutablePath()
            path.move(to: CGPoint(x: width / 2, y: 0))
            path.addQuadCurve(to: CGPoint(x: width / 2, y: height), control: CGPoint(x: width + 2, y: height / 2))
            path.addQuadCurve(to: CGPoint(x: width / 2, y: 0), control: CGPoint(x: -2, y: height / 2))
            cg.addPath(path)
            cg.clip()
            let colours = [SKColor.white.cgColor, SKColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1])!
            let centre = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: CGFloat(height) / 2, options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    /// An SF Symbol as a white texture, `pointSize` art pixels tall.
    func symbol(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight = .heavy) -> SKTexture {
        let key = "symbol_\(name)_\(pointSize)"
        if let texture = cache[key] { return texture }
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = UIImage(systemName: name, withConfiguration: configuration)!
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let texture = SKTexture(image: renderer.image { _ in image.draw(at: .zero) })
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }
}

extension SKColor {
    convenience init(rgb: RGB) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// The grayscale effect sheets, drawn in a player's energy colour through the look's tone
/// ramp: the sparks off a hit ball, the crown and the lightning on a score, and the charge
/// round a held throw.
enum EnergyEffect: CaseIterable {
    case spark, spark2, spark3, lightning1, lightning2, lightning3, lightning4, charge

    /// The two sparks a hit ball throws, one or the other each time, and the four bolts.
    static let hitSparks: [EnergyEffect] = [.spark, .spark2]
    static let strikes: [EnergyEffect] = [.lightning1, .lightning2, .lightning3, .lightning4]
    /// The bolts' one colour on the sheets, (241, 246, 240), as a grey level: what their
    /// full-frame flash comes out as through the ramp.
    static let strikeLuminance = 0.958
    /// The bolt sheets' frames that are a full-frame flash.
    static let strikeFlashFrames = 5..<7

    var name: String {
        switch self {
        case .spark: "esper_spark"
        case .spark2: "esper_spark2"
        case .spark3: "esper_spark3"
        case .lightning1: "lightning1"
        case .lightning2: "lightning2"
        case .lightning3: "lightning3"
        case .lightning4: "lightning4"
        case .charge: "esper_charge"
        }
    }

    var frameCount: Int {
        switch self {
        case .spark: 9
        case .spark2: 10
        case .spark3: 7
        case .lightning1, .lightning2, .lightning3, .lightning4: 25
        case .charge: 82
        }
    }

    var fps: Double { self == .charge ? 30 : 24 }

    /// The sparks and the charge are centred; the crown rises from its base, 10 pixels up
    /// its 128; a bolt strikes at its bottom edge.
    var anchor: CGPoint {
        switch self {
        case .spark3: CGPoint(x: 0.5, y: 10.0 / 128)
        case .lightning1, .lightning2, .lightning3, .lightning4: CGPoint(x: 0.5, y: 0)
        default: CGPoint(x: 0.5, y: 0.5)
        }
    }

    /// A one-shot node in the player's colour that plays through and removes itself.
    func node(_ sprites: SpriteLibrary, player: Int, at point: CGPoint) -> SKSpriteNode {
        let frames = sprites.effectFrames(self, player: player)
        let node = SKSpriteNode(texture: frames[0])
        node.anchorPoint = anchor
        node.position = point
        node.zPosition = 30
        node.run(.sequence([.animate(with: frames, timePerFrame: 1 / fps), .removeFromParent()]))
        return node
    }
}

/// One-shot sprites: sparks, smoke, the swish. Each plays through and removes itself.
enum Effect {
    case smoke, jumpSpark, catchSpark, wallJumpSpark

    var name: String {
        switch self {
        case .smoke: "smoke"
        case .jumpSpark: "jumpspark"
        case .catchSpark: "catchspark"
        case .wallJumpSpark: "walljumpspark"
        }
    }

    var frameCount: Int {
        switch self {
        case .smoke: 6
        case .jumpSpark, .catchSpark, .wallJumpSpark: 5
        }
    }

    var fps: Double {
        switch self {
        case .catchSpark: 15
        default: 12
        }
    }

    /// Feet-anchored like the player sprites, except the wall spark which is centred.
    var anchor: CGPoint {
        self == .wallJumpSpark ? CGPoint(x: 0.5, y: 0.5) : CGPoint(x: 0.5, y: 8.0 / 48.0)
    }

    func node(_ sprites: SpriteLibrary, at point: CGPoint, flipped: Bool) -> SKSpriteNode {
        let frames = sprites.frames(name, count: frameCount)
        let node = SKSpriteNode(texture: frames[0])
        node.anchorPoint = anchor
        node.position = point
        node.xScale = flipped ? -1 : 1
        node.zPosition = 30
        node.run(.sequence([.animate(with: frames, timePerFrame: 1 / fps), .removeFromParent()]))
        return node
    }
}
