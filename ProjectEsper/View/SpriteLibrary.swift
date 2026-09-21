import CoreGraphics
import EsperSim
import SpriteKit

/// Every frame in the atlas, looked up by the importer's names, drawn as pixels. Player
/// frames come out in that player's look and the ball in its colour, recoloured once each
/// and kept, and the library remembers where the ball and the head sit in each frame.
final class SpriteLibrary {
    static let pixelsPerUnit = 1.6

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

    /// A non-player frame.
    func texture(_ name: String, _ frame: Int) -> SKTexture {
        let key = "\(name)_\(frame)"
        if let texture = cache[key] { return texture }
        var texture = atlas.textureNamed(key)
        if name == "ball" {
            texture = recolour(texture, swaps: BallLook.swaps).texture
        }
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    /// A player frame in that player's look.
    func texture(_ frame: AnimationFrame, player: Int) -> SKTexture {
        let key = "p\(player)_\(frame.animation.rawValue)_\(frame.frame)"
        if let texture = cache[key] { return texture }
        let look = look(for: player)
        let result = recolour(atlas.textureNamed("\(frame.animation.rawValue)_\(frame.frame)"), look: look)
        let texture = result.texture
        texture.filteringMode = .nearest
        cache[key] = texture
        let size = frame.animation.pixelSize
        landmarks[key] = result.centres.mapValues { centre in
            CGPoint(x: centre.x - size / 2, y: size - centre.y - frame.animation.feetFromBottom)
        }
        return texture
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

    private func recolour(_ texture: SKTexture, swaps: [RGB: RGB]) -> (texture: SKTexture, centres: [BodyPart: CGPoint]) {
        var look = Look(colours: [:], glow: 0, outline: 0, outlineWidth: 0)
        for (source, target) in swaps {
            if let part = BodyPart.owning(source) { look.colours[part] = target }
        }
        return recolour(texture, look: look)
    }

    /// A copy of the frame in the look: every part swapped to its colour, the stroked parts
    /// lined where they lie over the body, the silhouette lined round the outside, and the
    /// centre of each glowing part found.
    private func recolour(_ texture: SKTexture, look: Look) -> (texture: SKTexture, centres: [BodyPart: CGPoint]) {
        let image = texture.cgImage()
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return (texture, [:]) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let count = width * height

        // Which part each pixel came from, before anything changes.
        var parts = [BodyPart?](repeating: nil, count: count)
        var sums: [BodyPart: (x: CGFloat, y: CGFloat, n: Int)] = [:]
        for pixel in 0..<count where pixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            let colour = RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])
            guard let part = BodyPart.owning(colour) else { continue }
            parts[pixel] = part
            if part.glows {
                var sum = sums[part] ?? (0, 0, 0)
                sum.x += CGFloat(pixel % width) + 0.5
                sum.y += CGFloat(pixel / width) + 0.5
                sum.n += 1
                sums[part] = sum
            }
            if let target = look.colours[part] {
                paint(pixels, index, target)
            }
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

        // The outside line, grown a pixel at a time. Next to a glowing part it takes that
        // part's colour, and a grown pixel passes its colour on.
        if look.outlineWidth > 0 {
            var lineColour = [RGB?](repeating: nil, count: count)
            for pixel in 0..<count where parts[pixel]?.glows == true { lineColour[pixel] = look.glow }
            for _ in 0..<look.outlineWidth {
                let filled = (0..<count).map { pixels[$0 * 4 + 3] != 0 }
                var grown: [(pixel: Int, colour: RGB)] = []
                for pixel in 0..<count where !filled[pixel] {
                    var touching: RGB?
                    var touches = false
                    let x = pixel % width, y = pixel / width
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let nx = x + dx, ny = y + dy
                            guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                            let near = ny * width + nx
                            if filled[near] {
                                touches = true
                                if let colour = lineColour[near] { touching = colour }
                            }
                        }
                    }
                    if touches { grown.append((pixel, touching ?? look.outline)) }
                }
                for (pixel, colour) in grown {
                    paint(pixels, pixel * 4, colour)
                    pixels[pixel * 4 + 3] = 255
                    if colour == look.glow { lineColour[pixel] = colour }
                }
            }
        }

        guard let recoloured = context.makeImage() else { return (texture, [:]) }
        let centres = sums.mapValues { CGPoint(x: $0.x / CGFloat($0.n), y: $0.y / CGFloat($0.n)) }
        return (SKTexture(cgImage: recoloured), centres)
    }

    private func paint(_ pixels: UnsafeMutablePointer<UInt8>, _ index: Int, _ colour: RGB) {
        pixels[index] = UInt8((colour >> 16) & 0xFF)
        pixels[index + 1] = UInt8((colour >> 8) & 0xFF)
        pixels[index + 2] = UInt8(colour & 0xFF)
    }

    // MARK: Generated textures

    /// A soft round glow, bright in the middle and clear at the edge, for additive halos.
    func softGlow(diameter: Int, colour: SKColor) -> SKTexture {
        let key = "glow_\(diameter)_\(colour.description)"
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
