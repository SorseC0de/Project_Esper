import SpriteKit

/// What a body sprite looks like this frame, for the mask to copy.
struct BodySnapshot {
    var texture: SKTexture
    var position: CGPoint
    var anchor: CGPoint
    var xScale: CGFloat
    var size: CGSize
    var zRotation: CGFloat = 0
}

/// The bodies alone on black, drawn by its own renderer for the glow's mask, and in pure
/// green whatever must not glow at all. Drawing the game scene a second time in one frame
/// is what put white squares on the bodies: SpriteKit reuses its per-frame buffers
/// between the two renders.
final class MaskScene: SKScene {
    private let cameraNode = SKCameraNode()
    private var bodies: [SKSpriteNode] = []
    private var flats: [SKSpriteNode] = []

    override init() {
        super.init(size: CGSize(width: 640, height: 288))
        scaleMode = .fill
        backgroundColor = .black
        camera = cameraNode
        addChild(cameraNode)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Copies the game's bodies and camera, and the flat things in green.
    func mirror(_ snapshots: [BodySnapshot], flat: [BodySnapshot], size: CGSize, cameraPosition: CGPoint, cameraScale: CGFloat) {
        if self.size != size { self.size = size }
        cameraNode.position = cameraPosition
        cameraNode.setScale(cameraScale)
        place(snapshots, in: &bodies, green: false)
        place(flat, in: &flats, green: true)
    }

    private func place(_ snapshots: [BodySnapshot], in nodes: inout [SKSpriteNode], green: Bool) {
        while nodes.count < snapshots.count {
            let node = SKSpriteNode()
            if green {
                node.color = SKColor(red: 0, green: 1, blue: 0, alpha: 1)
                node.colorBlendFactor = 1
                node.zPosition = 1
            }
            addChild(node)
            nodes.append(node)
        }
        for (index, node) in nodes.enumerated() {
            guard index < snapshots.count else { node.isHidden = true; continue }
            let snapshot = snapshots[index]
            node.isHidden = false
            node.texture = snapshot.texture
            node.size = snapshot.size
            node.anchorPoint = snapshot.anchor
            node.position = snapshot.position
            node.xScale = snapshot.xScale
            node.zRotation = snapshot.zRotation
        }
    }
}
