import CoreGraphics
import EsperSim
import SpriteKit

/// Every frame in the atlas, looked up by the importer's names, drawn as pixels. Player
/// frames come out in the current look and the ball in its colour, recoloured once each
/// and kept.
final class SpriteLibrary {
    static let pixelsPerUnit = 1.6

    private let atlas = SKTextureAtlas(named: "Sprites")
    private var cache: [String: SKTexture] = [:]
    /// Where the ball sits in each player frame that has one, in art pixels from the feet.
    private var ballInHand: [String: CGPoint?] = [:]
    private var look = Look.plain

    /// Changes what the players are drawn in; frames are recoloured again as they're used.
    func setLook(_ look: Look) {
        guard look != self.look else { return }
        self.look = look
        cache = cache.filter { !$0.key.hasPrefix("player_") }
    }

    func texture(_ name: String, _ frame: Int) -> SKTexture {
        let key = "\(name)_\(frame)"
        if let texture = cache[key] { return texture }
        var texture = atlas.textureNamed(key)
        if name.hasPrefix("player_") {
            let animation = Animation(rawValue: name)
            let result = recoloured(texture, with: look.swaps.merging(BallLook.swaps) { a, _ in a },
                                    outline: look.outline, outlineWidth: look.outlineWidth, locate: BallLook.white)
            texture = result.texture
            if let animation, let centre = result.located {
                ballInHand[key] = CGPoint(x: centre.x - animation.pixelSize / 2,
                                          y: animation.pixelSize - centre.y - animation.feetFromBottom)
            } else {
                ballInHand[key] = .some(nil)
            }
        } else if name == "ball" {
            texture = recoloured(texture, with: BallLook.swaps, outline: nil, outlineWidth: 0, locate: nil).texture
        }
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    /// Where the ball is drawn in a player frame, from the feet in art pixels, if it's there.
    func ballInHand(_ frame: AnimationFrame) -> CGPoint? {
        _ = texture(frame)
        return ballInHand["\(frame.animation.rawValue)_\(frame.frame)"] ?? nil
    }

    /// A copy of the frame with every pixel in the table replaced, a line drawn round the
    /// silhouette, and the centre of the pixels that were `locate` before the swap.
    private func recoloured(_ texture: SKTexture, with swaps: [RGB: RGB], outline: RGB?, outlineWidth: Int,
                            locate: RGB?) -> (texture: SKTexture, located: CGPoint?) {
        let image = texture.cgImage()
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return (texture, nil) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var locatedSum = CGPoint.zero
        var locatedCount = 0
        for index in stride(from: 0, to: width * height * 4, by: 4) where pixels[index + 3] == 255 {
            let colour = RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])
            if let locate, colour == locate || nearest(colour, in: [locate: locate]) != nil {
                let pixel = index / 4
                locatedSum.x += CGFloat(pixel % width) + 0.5
                locatedSum.y += CGFloat(pixel / width) + 0.5
                locatedCount += 1
            }
            guard let replacement = swaps[colour] ?? nearest(colour, in: swaps) else { continue }
            pixels[index] = UInt8((replacement >> 16) & 0xFF)
            pixels[index + 1] = UInt8((replacement >> 8) & 0xFF)
            pixels[index + 2] = UInt8(replacement & 0xFF)
        }
        if let outline, outlineWidth > 0 {
            draw(outline: outline, width: outlineWidth, pixels: pixels, imageWidth: width, imageHeight: height)
        }
        guard let recoloured = context.makeImage() else { return (texture, nil) }
        let located = locatedCount > 0 ? CGPoint(x: locatedSum.x / CGFloat(locatedCount), y: locatedSum.y / CGFloat(locatedCount)) : nil
        return (SKTexture(cgImage: recoloured), located)
    }

    /// Grows the silhouette outward by `width` pixels in the outline colour: any clear pixel
    /// touching a filled one, `width` times over. Only the outside edge gets a line.
    private func draw(outline: RGB, width: Int, pixels: UnsafeMutablePointer<UInt8>, imageWidth: Int, imageHeight: Int) {
        let r = UInt8((outline >> 16) & 0xFF), g = UInt8((outline >> 8) & 0xFF), b = UInt8(outline & 0xFF)
        for _ in 0..<width {
            var filled = [Bool](repeating: false, count: imageWidth * imageHeight)
            for pixel in 0..<(imageWidth * imageHeight) { filled[pixel] = pixels[pixel * 4 + 3] != 0 }
            for y in 0..<imageHeight {
                for x in 0..<imageWidth where !filled[y * imageWidth + x] {
                    var touches = false
                    for dy in -1...1 where !touches {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let nx = x + dx, ny = y + dy
                            if nx >= 0, ny >= 0, nx < imageWidth, ny < imageHeight, filled[ny * imageWidth + nx] {
                                touches = true
                                break
                            }
                        }
                    }
                    if touches {
                        let index = (y * imageWidth + x) * 4
                        pixels[index] = r
                        pixels[index + 1] = g
                        pixels[index + 2] = b
                        pixels[index + 3] = 255
                    }
                }
            }
        }
    }

    /// A soft round glow, bright in the middle and clear at the edge, for additive halos.
    func softGlow(diameter: Int, colour: SKColor) -> SKTexture {
        let key = "glow_\(diameter)_\(colour.description)"
        if let texture = cache[key] { return texture }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
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
        let renderer = UIGraphicsImageRenderer(size: image.size, format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let texture = SKTexture(image: renderer.image { _ in image.draw(at: .zero) })
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    /// A table entry within two steps per channel, in case the draw rounded a value.
    private func nearest(_ colour: RGB, in swaps: [RGB: RGB]) -> RGB? {
        let r = Int((colour >> 16) & 0xFF), g = Int((colour >> 8) & 0xFF), b = Int(colour & 0xFF)
        for (source, replacement) in swaps {
            let sr = Int((source >> 16) & 0xFF), sg = Int((source >> 8) & 0xFF), sb = Int(source & 0xFF)
            if abs(sr - r) <= 2, abs(sg - g) <= 2, abs(sb - b) <= 2 { return replacement }
        }
        return nil
    }

    func texture(_ frame: AnimationFrame) -> SKTexture {
        texture(frame.animation.rawValue, frame.frame)
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
