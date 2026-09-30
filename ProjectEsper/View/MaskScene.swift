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
    private var underFlats: [SKSpriteNode] = []
    /// The bodies drawn in plain white rather than as they are, for the cubes' occluder.
    private let whiteBodies: Bool
    /// What the stage keeps still and must not glow, drawn once under the bodies; rebuilt
    /// only when its version changes.
    private let staticLayer = SKNode()
    private var staticVersion = -1

    init(whiteBodies: Bool = false) {
        self.whiteBodies = whiteBodies
        super.init(size: CGSize(width: 640, height: 288))
        scaleMode = .fill
        backgroundColor = .black
        camera = cameraNode
        addChild(cameraNode)
        staticLayer.zPosition = -1
        addChild(staticLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Every drawn pixel one colour, its alpha kept.
    private static func flat(_ colour: SIMD4<Float>) -> SKShader {
        let shader = SKShader(source: """
        void main() {
            float alpha = texture2D(u_texture, v_tex_coord).a;
            gl_FragColor = vec4(u_flat.rgb * alpha, alpha);
        }
        """)
        shader.uniforms = [SKUniform(name: "u_flat", vectorFloat4: colour)]
        return shader
    }
    private static let flatWhite = flat(SIMD4<Float>(1, 1, 1, 1))
    private static let flatGreen = flat(SIMD4<Float>(0, 1, 0, 1))

    /// The stage's still, non-glowing art in green, redone when `version` changes.
    func syncStatic(_ flats: [BodySnapshot], version: Int) {
        guard version != staticVersion else { return }
        staticVersion = version
        staticLayer.removeAllChildren()
        for flat in flats {
            let node = SKSpriteNode(texture: flat.texture)
            node.shader = MaskScene.flatGreen
            node.anchorPoint = flat.anchor
            node.position = flat.position
            node.size = flat.size
            staticLayer.addChild(node)
        }
    }

    /// Copies the game's bodies and camera, and the flat things in green.
    func mirror(_ snapshots: [BodySnapshot], flat: [BodySnapshot], under: [BodySnapshot] = [], size: CGSize, cameraPosition: CGPoint, cameraScale: CGFloat) {
        if self.size != size { self.size = size }
        cameraNode.position = cameraPosition
        cameraNode.setScale(cameraScale)
        place(snapshots, in: &bodies, green: false)
        place(flat, in: &flats, green: true)
        place(under, in: &underFlats, green: true, depth: -0.5)
    }

    private func place(_ snapshots: [BodySnapshot], in nodes: inout [SKSpriteNode], green: Bool, depth: CGFloat? = nil) {
        while nodes.count < snapshots.count {
            let node = SKSpriteNode()
            if whiteBodies {
                // Flat through the art's alpha: a tint multiplies the art's own colours, so a
                // dark rim or body tinted would come out too dark to read.
                node.shader = green ? MaskScene.flatGreen : MaskScene.flatWhite
                node.zPosition = green ? 1 : 2
            } else if green {
                node.color = SKColor(red: 0, green: 1, blue: 0, alpha: 1)
                node.colorBlendFactor = 1
                node.zPosition = 1
            }
            if let depth { node.zPosition = depth }
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
