import SpriteKit
import Metal

let device = MTLCreateSystemDefaultDevice()!
let queue = device.makeCommandQueue()!
let renderer = SKRenderer(device: device)
var clock = 0.0
func render(width: Int, height: Int, _ setup: (SKScene) -> Void) -> [UInt8] {
    let scene = SKScene(size: CGSize(width: width, height: height))
    scene.backgroundColor = .clear
    scene.anchorPoint = .zero
    setup(scene)
    renderer.scene = scene
    let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    desc.usage = [.renderTarget, .shaderRead]; desc.storageMode = .shared
    let target = device.makeTexture(descriptor: desc)!
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target; pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    clock += 1.0 / 60
    renderer.update(atTime: clock)
    let cb = queue.makeCommandBuffer()!
    renderer.render(withViewport: CGRect(x: 0, y: 0, width: width, height: height), commandBuffer: cb, renderPassDescriptor: pass)
    cb.commit(); cb.waitUntilCompleted()
    var out = [UInt8](repeating: 0, count: width * height * 4)
    target.getBytes(&out, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    return out
}

// The game's energy ramp and the glow mask's flat shader, as GameScene and MaskScene have them.
let energyRampShader: SKShader = {
    let shader = SKShader(source: """
    void main() {
        vec4 texel = texture2D(u_texture, v_tex_coord);
        float level = texel.a > 0.0 ? texel.r / texel.a : 0.0;
        vec3 toned = level > 0.9 ? a_glow : (level > 0.7 ? a_middle : (level > 0.5 ? a_deep : a_glow * (level * 2.0)));
        gl_FragColor = vec4(toned * texel.a, texel.a) * v_color_mix.a;
    }
    """)
    shader.attributes = [SKAttribute(name: "a_glow", type: .vectorFloat3), SKAttribute(name: "a_middle", type: .vectorFloat3), SKAttribute(name: "a_deep", type: .vectorFloat3)]
    return shader
}()
func flatShader(_ colour: vector_float4) -> SKShader {
    SKShader(source: """
    void main() {
        float alpha = texture2D(u_texture, v_tex_coord).a;
        gl_FragColor = vec4(u_flat.rgb * alpha, alpha);
    }
    """, uniforms: [SKUniform(name: "u_flat", vectorFloat4: colour)])
}

func runGPU() {
    let paletteRowsTotal = PlayerMapShaders.paletteLooks * PlayerRecolour.paletteRows
    let lookIndex = 5   // a block that isn't the first, so the look's offset is exercised
    let paletteUniform = SKUniform(name: "u_palette", texture: SKTexture())
    func shader(_ layer: PlayerMapShaders.Layer) -> SKShader {
        let shader = SKShader(source: PlayerMapShaders.source(layer))
        if layer.paletted { shader.uniforms = [paletteUniform] }
        var attributes = [SKAttribute(name: "a_texels", type: .vectorFloat2)]
        if layer.paletted { attributes.append(SKAttribute(name: "a_look", type: .float)) }
        if layer == .energy { attributes += ["a_glow", "a_middle", "a_deep"].map { SKAttribute(name: $0, type: .vectorFloat3) } }
        shader.attributes = attributes
        return shader
    }
    let shaders = Dictionary(uniqueKeysWithValues: PlayerMapShaders.Layer.allCases.map { ($0, shader($0)) })
    let flatColour = vector_float4(0.3, 1, 0, 1)
    let oldFlat = flatShader(flatColour)
    let flatG = SKShader(source: PlayerMapShaders.flatSource(channel: "g"), uniforms: [SKUniform(name: "u_flat", vectorFloat4: flatColour)])
    let flatB = SKShader(source: PlayerMapShaders.flatSource(channel: "b"), uniforms: [SKUniform(name: "u_flat", vectorFloat4: flatColour)])
    func texture(_ image: CGImage) -> SKTexture { let t = SKTexture(cgImage: image); t.filteringMode = .nearest; return t }
    struct Tint { let colour: SKColor; let factor: CGFloat; let alpha: CGFloat }
    let tints = [Tint(colour: .white, factor: 0, alpha: 1), Tint(colour: SKColor(red: 0.2, green: 0.6, blue: 1, alpha: 1), factor: 1, alpha: 1),
                 Tint(colour: SKColor(red: 1, green: 0.4, blue: 0.1, alpha: 1), factor: 0.85, alpha: 0.5),
                 Tint(colour: SKColor(red: 0.14, green: 0.13, blue: 0.2, alpha: 1), factor: 0.5, alpha: 1)]
    struct Placement { let scale: CGFloat; let turn: CGFloat; let flip: Bool; let nudge: CGPoint }
    let placements = [Placement(scale: 1, turn: 0, flip: false, nudge: .zero), Placement(scale: 3, turn: 0, flip: true, nudge: .zero),
                      Placement(scale: 2, turn: 0, flip: false, nudge: .zero), Placement(scale: 2.5, turn: 0.3, flip: false, nudge: CGPoint(x: 0.37, y: 0)),
                      Placement(scale: 3, turn: -0.17, flip: true, nudge: CGPoint(x: 0, y: 0.21)), Placement(scale: 5, turn: 0, flip: false, nudge: .zero),
                      Placement(scale: 1.5, turn: 0, flip: false, nudge: CGPoint(x: 0.5, y: 0.5)), Placement(scale: 4, turn: 0, flip: true, nudge: CGPoint(x: 0.5, y: 0))]
    var compared = 0, differing = 0, differingPixels = 0, worst = 0
    var byLayer: [String: (Int, Int)] = [:]
    let every = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3]) ?? 9 : 9
    let testLooks = looks.filter { ["p0", "p0T", "sl0R", "ice", "sl1", "p1"].contains($0.0) }
    for (name, look, style) in testLooks {
        var paletteBytes = [UInt8](repeating: 0, count: 32 * paletteRowsTotal * 4)
        let own = PlayerMap.palette(look)
        for row in 0..<PlayerRecolour.paletteRows {
            let target = lookIndex * PlayerRecolour.paletteRows + row
            for i in 0..<(32 * 4) { paletteBytes[target * 32 * 4 + i] = own[row * 32 * 4 + i] }
        }
        let palette = SKTexture(data: Data(paletteBytes), size: CGSize(width: 32, height: paletteRowsTotal), flipped: false)
        palette.filteringMode = .nearest
        paletteUniform.textureValue = palette
        for (frameIndex, (frame, image)) in frames.enumerated() where frameIndex % every == 0 || frame.animation == .spinBall || frame.animation == .throwForward {
            let r = row(frame)
            let layers = PlayerRecolour.recolour(image: image, look: PlayerRecolour.adjusted(look, row: r), holdsBall: frame.animation.holdsBall, detach: true,
                                                 hoodShape: hoodShape(view: HoodView.of(frame), flipped: HoodView.isFlipped(frame), energy: look.energyForm),
                                                 bareLine: !look.energyForm, lineStyle: style, hoodDrawnForHead: hoodDrawnForHead, ballMinPixels: 12, map: (r, own, false))
            guard let map = layers.map else { print("no map"); continue }
            let mapTexture = SKTexture(data: Data(map.bytes), size: CGSize(width: map.width, height: map.height), flipped: true)
            mapTexture.filteringMode = .nearest
            let coverageTexture = SKTexture(data: Data(map.coverage), size: CGSize(width: map.width, height: map.height), flipped: true)
            coverageTexture.filteringMode = .nearest
            let olds: [(PlayerMapShaders.Layer, CGImage?)] = [(.body, layers.drawn), (.glowing, layers.glowing), (.line, layers.outline),
                                                             (.glowLine, layers.glowLine), (.bareLine, layers.bareOutline), (.bareGlowLine, layers.bareGlowLine),
                                                             (.clothes, layers.skin), (.glowMask, layers.glowMask), (.energy, layers.energy), (.energyGrey, layers.energy)]
            for (layer, oldImage) in olds {
                guard let oldImage else { if map.present.contains(layer) { print("present but no image \(layer)") }; continue }
                let oldTexture = texture(oldImage)
                let newTexture = layer.fromCoverage ? coverageTexture : mapTexture
                for (placementIndex, placement) in placements.enumerated() {
                    let side = Int((CGFloat(max(map.width, map.height)) * placement.scale * 1.5).rounded(.up)) + 4
                    func node(_ tex: SKTexture) -> SKSpriteNode {
                        let node = SKSpriteNode(texture: tex)
                        node.size = CGSize(width: CGFloat(map.width) * placement.scale, height: CGFloat(map.height) * placement.scale)
                        node.anchorPoint = CGPoint(x: 0.5, y: 0.25)
                        node.position = CGPoint(x: CGFloat(side / 2) + placement.nudge.x, y: CGFloat(side / 4) + placement.nudge.y)
                        node.xScale = placement.flip ? -1 : 1
                        node.zRotation = placement.turn
                        return node
                    }
                    func count(_ before: [UInt8], _ after: [UInt8], _ label: String) {
                        compared += 1
                        var pixels = 0
                        for p in stride(from: 0, to: before.count, by: 4) where before[p..<p + 4] != after[p..<p + 4] {
                            pixels += 1
                            for c in 0..<4 { worst = max(worst, abs(Int(before[p + c]) - Int(after[p + c]))) }
                        }
                        byLayer[label, default: (0, 0)].0 += 1
                        if pixels > 0 {
                            differing += 1; differingPixels += pixels; byLayer[label, default: (0, 0)].1 += 1
                            if differing <= 12 { print("DIFF \(name) \(frame.animation.rawValue)_\(frame.frame) \(label) placement \(placementIndex): \(pixels) px") }
                        }
                    }
                    let tintsHere = layer == .energy ? [tints[0], tints[2]] : (placementIndex == 0 || layer == .energyGrey ? tints : [tints[1], tints[2]])
                    for tint in tintsHere {
                        let glow = vector_float3(1, 0.5, 0.1), middle = vector_float3(0.7, 0.3, 0.05), deep = vector_float3(0.4, 0.1, 0.02)
                        func ramp(_ n: SKSpriteNode) {
                            n.setValue(SKAttributeValue(vectorFloat3: glow), forAttribute: "a_glow")
                            n.setValue(SKAttributeValue(vectorFloat3: middle), forAttribute: "a_middle")
                            n.setValue(SKAttributeValue(vectorFloat3: deep), forAttribute: "a_deep")
                        }
                        let before = render(width: side, height: side) { scene in
                            let n = node(oldTexture)
                            n.color = tint.colour; n.colorBlendFactor = tint.factor; n.alpha = tint.alpha
                            if layer == .energy { n.shader = energyRampShader; ramp(n) }
                            scene.addChild(n)
                        }
                        let after = render(width: side, height: side) { scene in
                            let n = node(newTexture)
                            n.color = tint.colour; n.colorBlendFactor = tint.factor; n.alpha = tint.alpha
                            n.shader = shaders[layer]
                            n.setValue(SKAttributeValue(vectorFloat2: vector_float2(Float(map.width), Float(map.height))), forAttribute: "a_texels")
                            if layer.paletted { n.setValue(SKAttributeValue(float: Float(lookIndex)), forAttribute: "a_look") }
                            if layer == .energy { ramp(n) }
                            scene.addChild(n)
                        }
                        count(before, after, "\(layer)")
                    }
                    // The glow mask's flat colour over the layer's alpha, as MaskScene draws it.
                    let flats: [PlayerMapShaders.Layer: SKShader] = [.body: oldFlat, .line: oldFlat, .bareLine: flatB, .energy: flatG]
                    if let flat = flats[layer] {
                        let before = render(width: side, height: side) { scene in let n = node(oldTexture); n.shader = oldFlat; scene.addChild(n) }
                        let after = render(width: side, height: side) { scene in let n = node(newTexture); n.shader = flat; scene.addChild(n) }
                        count(before, after, "flat \(layer)")
                    }
                }
            }
        }
        print("look \(name): compared \(compared), differing \(differing)")
    }
    print("compared \(compared) renders, \(differing) differ (\(differingPixels) pixels, worst channel step \(worst))")
    for (k, v) in byLayer.sorted(by: { $0.key < $1.key }) { print("  \(k): \(v.0) renders, \(v.1) differ") }
}
