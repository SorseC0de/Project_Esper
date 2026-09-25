import SpriteKit

/// A sprite as drawn this frame, for a scene of its own to copy.
struct SpriteSnapshot {
    var texture: SKTexture
    var position: CGPoint
    var anchor: CGPoint
    var size: CGSize
    var xScale: CGFloat
    var yScale: CGFloat
    var zRotation: CGFloat
    var colour: SKColor
    var colourBlend: CGFloat
    var alpha: CGFloat
    var zPosition: CGFloat
    var blendMode: SKBlendMode = .alpha
    var shader: SKShader?
    var warp: SKWarpGeometry?
}

/// The ball cam: a close view of the ball, drawn by its own renderer into a small texture
/// the Metal view lays over the screen. The game scene can't be drawn twice in a frame,
/// so this scene carries its own copy of the field's scenery, built once, and mirrors the
/// moving sprites from the game each time it's drawn.
final class BallCamScene: SKScene {
    /// Art pixels of the world it shows, across and up.
    static let view = CGSize(width: 128, height: 80)
    /// Where it hangs on the screen, in the screen's -1 to 1 across and up: the trapezoid's
    /// widths at the top and bottom and its top edge. Its height follows from the view's
    /// shape. Laid down at a third.
    static let topWidth: CGFloat = 0.5
    static let bottomWidth: CGFloat = 0.42
    static let top: CGFloat = 0.9
    static let opacity: CGFloat = 0.33

    /// The trapezoid's corners for a screen of this aspect, top left, top right, bottom
    /// left, bottom right, with the cam's middle at `centre` across.
    static func corners(centre: CGFloat, screenAspect: CGFloat) -> [CGPoint] {
        let height = (topWidth + bottomWidth) / 2 * screenAspect / (view.width / view.height)
        let bottom = top - height
        return [CGPoint(x: centre - topWidth / 2, y: top), CGPoint(x: centre + topWidth / 2, y: top),
                CGPoint(x: centre - bottomWidth / 2, y: bottom), CGPoint(x: centre + bottomWidth / 2, y: bottom)]
    }

    private let cameraNode = SKCameraNode()
    let scenery = SKNode()
    private var sprites: [SKSpriteNode] = []
    var built = false

    override init() {
        super.init(size: BallCamScene.view)
        scaleMode = .fill
        backgroundColor = FieldArt.sky
        camera = cameraNode
        addChild(cameraNode)
        addChild(scenery)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// On the ball, with this frame's moving sprites.
    func mirror(_ snapshots: [SpriteSnapshot], centre: CGPoint) {
        cameraNode.position = centre
        while sprites.count < snapshots.count {
            let node = SKSpriteNode()
            addChild(node)
            sprites.append(node)
        }
        for (index, node) in sprites.enumerated() {
            guard index < snapshots.count else { node.isHidden = true; continue }
            let snapshot = snapshots[index]
            node.isHidden = false
            node.texture = snapshot.texture
            node.setScale(1)
            node.size = snapshot.size
            node.anchorPoint = snapshot.anchor
            node.xScale = snapshot.xScale
            node.yScale = snapshot.yScale
            node.zRotation = snapshot.zRotation
            node.position = snapshot.position
            node.color = snapshot.colour
            node.colorBlendFactor = snapshot.colourBlend
            node.alpha = snapshot.alpha
            node.zPosition = snapshot.zPosition
            node.blendMode = snapshot.blendMode
            node.shader = snapshot.shader
            node.warpGeometry = snapshot.warp
        }
    }
}
