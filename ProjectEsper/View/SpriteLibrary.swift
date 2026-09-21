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
            texture = recoloured(texture, with: look.swaps)
        } else if name == "ball" {
            texture = recoloured(texture, with: BallLook.swaps)
        }
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    /// A copy of the frame with every pixel in the table replaced.
    private func recoloured(_ texture: SKTexture, with swaps: [RGB: RGB]) -> SKTexture {
        let image = texture.cgImage()
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return texture }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for index in stride(from: 0, to: width * height * 4, by: 4) where pixels[index + 3] == 255 {
            let colour = RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])
            guard let replacement = swaps[colour] ?? nearest(colour, in: swaps) else { continue }
            pixels[index] = UInt8((replacement >> 16) & 0xFF)
            pixels[index + 1] = UInt8((replacement >> 8) & 0xFF)
            pixels[index + 2] = UInt8(replacement & 0xFF)
        }
        guard let recoloured = context.makeImage() else { return texture }
        return SKTexture(cgImage: recoloured)
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
