import EsperSim
import SpriteKit

/// Every frame in the atlas, looked up by the importer's names, drawn as pixels.
final class SpriteLibrary {
    static let pixelsPerUnit = 1.6

    private let atlas = SKTextureAtlas(named: "Sprites")
    private var cache: [String: SKTexture] = [:]

    func texture(_ name: String, _ frame: Int) -> SKTexture {
        let key = "\(name)_\(frame)"
        if let texture = cache[key] { return texture }
        let texture = atlas.textureNamed(key)
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
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
