import SpriteKit

/// What a body sprite looks like this frame, for the mask to copy.
struct BodySnapshot {
    var texture: SKTexture
    var position: CGPoint
    var anchor: CGPoint
    var xScale: CGFloat
    var size: CGSize
}

/// The bodies alone on black, drawn by its own renderer for the glow's mask. Drawing the
/// game scene a second time in one frame is what put white squares on the bodies: SpriteKit
/// reuses its per-frame buffers between the two renders.
final class MaskScene: SKScene {
    private let cameraNode = SKCameraNode()
    private var bodies: [SKSpriteNode] = []

    override init() {
        super.init(size: CGSize(width: 640, height: 288))
        scaleMode = .fill
        backgroundColor = .black
        camera = cameraNode
        addChild(cameraNode)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Copies the game's bodies and camera.
    func mirror(_ snapshots: [BodySnapshot], size: CGSize, cameraPosition: CGPoint, cameraScale: CGFloat) {
        if self.size != size { self.size = size }
        cameraNode.position = cameraPosition
        cameraNode.setScale(cameraScale)
        while bodies.count < snapshots.count {
            let node = SKSpriteNode()
            addChild(node)
            bodies.append(node)
        }
        for (index, node) in bodies.enumerated() {
            guard index < snapshots.count else { node.isHidden = true; continue }
            let snapshot = snapshots[index]
            node.isHidden = false
            node.texture = snapshot.texture
            node.size = snapshot.size
            node.anchorPoint = snapshot.anchor
            node.position = snapshot.position
            node.xScale = snapshot.xScale
        }
    }
}
