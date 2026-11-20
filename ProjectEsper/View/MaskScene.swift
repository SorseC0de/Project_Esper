import SpriteKit

/// What a body sprite looks like this frame, for the mask to copy.
struct BodySnapshot {
    var texture: SKTexture
    var position: CGPoint
    var anchor: CGPoint
    var xScale: CGFloat
    var size: CGSize
    var zRotation: CGFloat = 0
    var warp: SKWarpGeometry? = nil
    /// The channel of the texture its flat colour's drawn through: a player's map keeps some layers' alpha elsewhere.
    var channel: MaskChannel = .alpha
    /// Drawn through its own shader rather than its category's (a player's glow mask with the halo off).
    var shader: SKShader? = nil
    var attributes: [String: SKAttributeValue] = [:]
}

/// The bodies alone on black, drawn by its own renderer for the glow's mask, and in pure
/// green whatever must not glow at all. Drawing the game scene a second time in one frame
/// is what put white squares on the bodies: SpriteKit reuses its per-frame buffers
/// between the two renders.
final class MaskScene: SKScene {
    private let cameraNode = SKCameraNode()
    private var bodies: [SKSpriteNode] = []
    private var cutOuts: [SKSpriteNode] = []
    /// The hooded heads' hoods, in magenta: the plain threshold, at the hood's share of the glow.
    private var hoods: [SKSpriteNode] = []
    private var shielded: [SKSpriteNode] = []
    private var flats: [SKSpriteNode] = []
    /// The players' lines, in a green with some red: flat, and the bloom kept off them, so they're
    /// drawn over it. Under the hoods but for the lines drawn over them, `linesOver`.
    private var lines: [SKSpriteNode] = []
    private var linesOver: [SKSpriteNode] = []
    private var underFlats: [SKSpriteNode] = []
    /// What the world's wash is left off, in yellow, over the still layer and under what's in front of it.
    private var washFree: [SKSpriteNode] = []
    /// What glows though it's over something that doesn't, as the Hoopfish's rings over Hoopfish
    /// Hideaway's background: drawn blue over the still layer, so the plain threshold holds there
    /// again, and the glow takes its colour from under the water's tint.
    private var glowingThrough: [SKSpriteNode] = []
    /// The same for what's drawn in front of the Hoopfish: the rims, and the nets' strands.
    private var glowingThroughFront: [SKSpriteNode] = []
    private var netStrands: [SKShapeNode] = []
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
    private static let flatBlue = flat(SIMD4<Float>(0, 0, 1, 1))
    private static let flatBlack = flat(SIMD4<Float>(0, 0, 0, 1))
    private static let flatRed = flat(SIMD4<Float>(1, 0, 0, 1))
    private static let flatMagenta = flat(SIMD4<Float>(1, 0, 1, 1))
    /// Yellow: left out of the world's wash in the composite (Anozira's far lightning).
    private static let flatYellow = flat(SIMD4<Float>(1, 1, 0, 1))
    private static let flatLine = flat(SIMD4<Float>(0.3, 1, 0, 1))
    /// A flat shader's colour through another channel than the alpha, made as first asked for.
    private var channelFlats: [ObjectIdentifier: [MaskChannel: SKShader]] = [:]
    private func flat(_ base: SKShader, through channel: MaskChannel) -> SKShader {
        guard channel != .alpha else { return base }
        if let made = channelFlats[ObjectIdentifier(base)]?[channel] { return made }
        let colour = base.uniformNamed("u_flat")?.vectorFloat4Value ?? SIMD4<Float>(1, 1, 1, 1)
        let made = SKShader(source: PlayerMapShaders.flatSource(channel: channel == .green ? "g" : "b"),
                            uniforms: [SKUniform(name: "u_flat", vectorFloat4: colour)])
        channelFlats[ObjectIdentifier(base), default: [:]][channel] = made
        return made
    }

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
            node.xScale = flat.xScale
            staticLayer.addChild(node)
        }
    }

    /// Copies the game's bodies and camera, and the flat things in green.
    /// `cutOut`: drawn black over the bodies, so what's there takes the plain threshold.
    /// `shield`: drawn red under the cut-outs: no glow, its own or any spread onto it.
    /// `hoods`: drawn magenta with the cut-outs: the plain threshold, at the hood's share.
    func mirror(_ snapshots: [BodySnapshot], flat: [BodySnapshot], under: [BodySnapshot] = [], through: [BodySnapshot] = [],
                throughFront: [BodySnapshot] = [], throughNets: [CGPath] = [], cutOut: [BodySnapshot] = [], hoods: [BodySnapshot] = [], shield: [BodySnapshot] = [],
                washFree: [BodySnapshot] = [], lines: [BodySnapshot] = [], linesOver: [BodySnapshot] = [],
                size: CGSize, cameraPosition: CGPoint, cameraScale: CGFloat, cameraRotation: CGFloat = 0) {
        if self.size != size { self.size = size }
        cameraNode.position = cameraPosition
        cameraNode.setScale(cameraScale)
        cameraNode.zRotation = cameraRotation
        place(snapshots, in: &bodies, green: false)
        place(shield, in: &shielded, green: false, depth: 2.5, shader: MaskScene.flatRed)
        place(cutOut, in: &cutOuts, green: false, depth: 3, shader: MaskScene.flatBlack)
        place(hoods, in: &self.hoods, green: false, depth: 3, shader: MaskScene.flatMagenta)
        place(flat, in: &flats, green: true)
        place(lines, in: &self.lines, green: false, depth: 1.5, shader: MaskScene.flatLine)
        place(linesOver, in: &self.linesOver, green: false, depth: 3.5, shader: MaskScene.flatLine)
        place(under, in: &underFlats, green: true, depth: -0.5)
        place(washFree, in: &self.washFree, green: false, depth: -0.9, shader: MaskScene.flatYellow)
        place(through, in: &glowingThrough, green: false, depth: -0.75, shader: MaskScene.flatBlue)
        place(throughFront, in: &glowingThroughFront, green: false, depth: -0.25, shader: MaskScene.flatBlue)
        while netStrands.count < throughNets.count {
            let strands = SKShapeNode()
            strands.strokeColor = SKColor(red: 0, green: 0, blue: 1, alpha: 1)
            strands.lineWidth = NetTuning.lineWidth
            strands.lineCap = .square
            strands.isAntialiased = false
            strands.zPosition = -0.25
            addChild(strands)
            netStrands.append(strands)
        }
        for (index, strands) in netStrands.enumerated() {
            strands.isHidden = index >= throughNets.count
            if index < throughNets.count { strands.path = throughNets[index] }
        }
    }

    private func place(_ snapshots: [BodySnapshot], in nodes: inout [SKSpriteNode], green: Bool, depth: CGFloat? = nil, shader: SKShader? = nil) {
        // Its own colour, whatever the art's. Flat through the art's alpha for the occluder: a tint
        // multiplies the art's own colours, so a dark rim or body tinted would come out too dark to
        // read. Pure green through the art's alpha, as the static art is: a tint multiplies, so dark
        // art came out a dark green the glow took for a body.
        let base = shader ?? (whiteBodies ? (green ? MaskScene.flatGreen : MaskScene.flatWhite) : (green ? MaskScene.flatGreen : nil))
        while nodes.count < snapshots.count {
            let node = SKSpriteNode()
            node.shader = base
            if shader == nil, whiteBodies {
                node.zPosition = green ? 1 : 2
            } else if shader == nil, green {
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
            let drawnThrough = snapshot.shader ?? base.map { flat($0, through: snapshot.channel) }
            if node.shader !== drawnThrough { node.shader = drawnThrough }
            if snapshot.shader != nil { node.attributeValues = snapshot.attributes }
            node.size = snapshot.size
            node.anchorPoint = snapshot.anchor
            node.position = snapshot.position
            node.xScale = snapshot.xScale
            node.zRotation = snapshot.zRotation
            node.warpGeometry = snapshot.warp
        }
    }
}
