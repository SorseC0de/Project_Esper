import MetalKit
import SpriteKit
import SwiftUI

/// The Metal layer: SpriteKit draws the scene into a texture through `SKRenderer`, and the
/// glow pass composites it onto the screen. Effects that need their own pass go here.
struct MetalGameView: UIViewRepresentable {
    let scene: GameScene

    func makeUIView(context: Context) -> GameMetalView {
        GameMetalView(scene: scene)
    }

    func updateUIView(_ uiView: GameMetalView, context: Context) {}
}

/// The view itself. Touches land on the HUD's view over it, never here.
final class GameMetalView: MTKView {
    let scene: GameScene
    private let renderer: GlowRenderer

    init(scene: GameScene) {
        self.scene = scene
        let device = MTLCreateSystemDefaultDevice()!
        renderer = GlowRenderer(scene: scene, device: device)
        super.init(frame: .zero, device: device)
        colorPixelFormat = .bgra8Unorm
        preferredFramesPerSecond = 60
        isUserInteractionEnabled = false
        delegate = renderer
    }

    required init(coder: NSCoder) { fatalError() }
}

/// Matches `GlowUniforms` in Glow.metal.
struct GlowUniforms {
    var texelSize: SIMD2<Float>
    var direction: SIMD2<Float>
    var threshold: Float
    var bodyThreshold: Float
    var softness: Float
    var intensity: Float
    var tint: SIMD4<Float>
}

/// Draws the scene, then the glow: bright pass at half size, a few blurs, and the composite.
final class GlowRenderer: NSObject, MTKViewDelegate {
    private let scene: GameScene
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let skRenderer: SKRenderer
    /// The bodies on black, by a renderer of their own.
    private let maskScene = MaskScene()
    private let maskRenderer: SKRenderer
    /// The ball cam: its own scene and renderer, drawn every few frames into a small
    /// texture that's laid over the screen as a trapezoid.
    private let ballCamScene = BallCamScene()
    private let ballCamRenderer: SKRenderer
    private let ballCamPipeline: MTLRenderPipelineState
    private let nearest: MTLSamplerState
    private var ballCamTexture: MTLTexture?
    private var ballCamDepthStencil: MTLTexture?
    /// Its glow, as the screen's is made: the bright parts at half size, blurred.
    private var ballCamMask: MTLTexture?
    private var ballCamGlowA: MTLTexture?
    private var ballCamGlowB: MTLTexture?
    private var ballCamFrames = 0
    /// Drawn one frame in this many, to keep its cost down.
    private static let ballCamEvery = 3
    /// Texture pixels per art pixel it shows.
    private static let ballCamResolution = 2
    private let bright: MTLRenderPipelineState
    private let blur: MTLRenderPipelineState
    private let composite: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var framesDrawn = 0
    private var fpsWindowStart = CACurrentMediaTime()
    private var lastDraw = CACurrentMediaTime()
    private var worstGap = 0.0
    private var sceneTexture: MTLTexture?
    /// The bodies alone, for the glow's per-object threshold.
    private var bodyMask: MTLTexture?
    /// SpriteKit draws with the stencil buffer, so its pass needs one.
    private var sceneDepthStencil: MTLTexture?
    private var glowA: MTLTexture?
    private var glowB: MTLTexture?

    init(scene: GameScene, device: MTLDevice) {
        self.scene = scene
        self.device = device
        queue = device.makeCommandQueue()!
        skRenderer = SKRenderer(device: device)
        skRenderer.scene = scene
        maskRenderer = SKRenderer(device: device)
        maskRenderer.scene = maskScene
        ballCamRenderer = SKRenderer(device: device)
        ballCamRenderer.scene = ballCamScene

        let library = device.makeDefaultLibrary()!
        func pipeline(_ fragment: String) -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "glowVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try! device.makeRenderPipelineState(descriptor: descriptor)
        }
        let camDescriptor = MTLRenderPipelineDescriptor()
        camDescriptor.vertexFunction = library.makeFunction(name: "ballCamVertex")
        camDescriptor.fragmentFunction = library.makeFunction(name: "ballCamFragment")
        camDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        ballCamPipeline = try! device.makeRenderPipelineState(descriptor: camDescriptor)
        let nearestDescriptor = MTLSamplerDescriptor()
        nearestDescriptor.minFilter = .nearest
        nearestDescriptor.magFilter = .nearest
        nearestDescriptor.sAddressMode = .clampToEdge
        nearestDescriptor.tAddressMode = .clampToEdge
        nearest = device.makeSamplerState(descriptor: nearestDescriptor)!
        bright = pipeline("glowBright")
        blur = pipeline("glowBlur")
        composite = pipeline("glowComposite")

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        sampler = device.makeSamplerState(descriptor: samplerDescriptor)!
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        sceneTexture = makeTexture(width: Int(size.width), height: Int(size.height))
        sceneDepthStencil = makeTexture(width: Int(size.width), height: Int(size.height), pixelFormat: .depth32Float_stencil8)
        bodyMask = makeTexture(width: Int(size.width), height: Int(size.height))
        glowA = makeTexture(width: Int(size.width) / 2, height: Int(size.height) / 2)
        glowB = makeTexture(width: Int(size.width) / 2, height: Int(size.height) / 2)
        scene.attach(size: view.bounds.size, displayScale: view.contentScaleFactor, insets: view.safeAreaInsets)
    }

    private func makeTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: max(width, 1), height: max(height, 1), mipmapped: false)
        descriptor.usage = pixelFormat == .bgra8Unorm ? [.renderTarget, .shaderRead] : [.renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)!
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let screenPass = view.currentRenderPassDescriptor,
              let sceneTexture, let sceneDepthStencil, let bodyMask, let glowA, let glowB,
              let commands = queue.makeCommandBuffer() else { return }

        if scene.size != view.bounds.size || scene.safeInsets != view.safeAreaInsets {
            scene.attach(size: view.bounds.size, displayScale: view.contentScaleFactor, insets: view.safeAreaInsets)
        }
        let now = CACurrentMediaTime()
        framesDrawn += 1
        worstGap = max(worstGap, now - lastDraw)
        lastDraw = now
        if now - fpsWindowStart >= 1 {
            scene.framesPerSecond = Int((Double(framesDrawn) / (now - fpsWindowStart)).rounded())
            scene.worstFrameMilliseconds = Int((worstGap * 1000).rounded())
            framesDrawn = 0
            worstGap = 0
            fpsWindowStart = now
        }
        skRenderer.update(atTime: now)

        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = sceneTexture
        scenePass.colorAttachments[0].loadAction = .clear
        scenePass.colorAttachments[0].storeAction = .store
        let background = scene.backgroundColor
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        background.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        scenePass.colorAttachments[0].clearColor = MTLClearColor(red: red, green: green, blue: blue, alpha: 1)
        scenePass.depthAttachment.texture = sceneDepthStencil
        scenePass.depthAttachment.loadAction = .clear
        scenePass.depthAttachment.storeAction = .dontCare
        scenePass.stencilAttachment.texture = sceneDepthStencil
        scenePass.stencilAttachment.loadAction = .clear
        scenePass.stencilAttachment.storeAction = .dontCare
        skRenderer.render(withViewport: CGRect(x: 0, y: 0, width: sceneTexture.width, height: sceneTexture.height),
                          commandBuffer: commands, renderPassDescriptor: scenePass)

        // The bodies alone, mirrored into their own scene and drawn by their own renderer.
        maskScene.mirror(scene.bodySnapshots, flat: scene.flatSnapshots, size: scene.size, cameraPosition: scene.cameraPosition, cameraScale: scene.cameraScale)
        maskRenderer.update(atTime: now)
        let maskPass = MTLRenderPassDescriptor()
        maskPass.colorAttachments[0].texture = bodyMask
        maskPass.colorAttachments[0].loadAction = .clear
        maskPass.colorAttachments[0].storeAction = .store
        maskPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        maskPass.depthAttachment.texture = sceneDepthStencil
        maskPass.depthAttachment.loadAction = .clear
        maskPass.depthAttachment.storeAction = .dontCare
        maskPass.stencilAttachment.texture = sceneDepthStencil
        maskPass.stencilAttachment.loadAction = .clear
        maskPass.stencilAttachment.storeAction = .dontCare
        maskRenderer.render(withViewport: CGRect(x: 0, y: 0, width: bodyMask.width, height: bodyMask.height),
                            commandBuffer: commands, renderPassDescriptor: maskPass)

        var uniforms = GlowUniforms(
            texelSize: SIMD2(1 / Float(glowA.width), 1 / Float(glowA.height)),
            direction: .zero,
            threshold: GlowSettings.threshold,
            bodyThreshold: GlowSettings.bodyThreshold,
            softness: GlowSettings.softness,
            intensity: GlowSettings.intensity,
            tint: GlowSettings.tint)

        pass(commands, pipeline: bright, into: glowA, sources: [sceneTexture, bodyMask], uniforms: uniforms)
        for _ in 0..<GlowSettings.blurPasses {
            uniforms.direction = SIMD2(1, 0)
            pass(commands, pipeline: blur, into: glowB, sources: [glowA], uniforms: uniforms)
            uniforms.direction = SIMD2(0, 1)
            pass(commands, pipeline: blur, into: glowA, sources: [glowB], uniforms: uniforms)
        }
        let camReady = drawBallCam(commands, at: now)
        pass(commands, pipeline: composite, descriptor: screenPass, sources: [sceneTexture, glowA], uniforms: uniforms,
             then: camReady ? { [weak self] encoder in self?.layBallCam(encoder, aspect: Float(view.drawableSize.width / max(view.drawableSize.height, 1))) } : nil)

        commands.present(drawable)
        commands.commit()
    }

    private func pass(_ commands: MTLCommandBuffer, pipeline: MTLRenderPipelineState, into target: MTLTexture,
                      sources: [MTLTexture], uniforms: GlowUniforms) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        pass(commands, pipeline: pipeline, descriptor: descriptor, sources: sources, uniforms: uniforms)
    }

    /// Every few frames, the ball cam's scene on the ball into its texture. True once there's
    /// a picture to lay down.
    private func drawBallCam(_ commands: MTLCommandBuffer, at now: CFTimeInterval) -> Bool {
        guard scene.ballCamEnabled else { return false }
        if ballCamTexture == nil {
            let resolution = GlowRenderer.ballCamResolution
            let width = Int(BallCamScene.view.width) * resolution, height = Int(BallCamScene.view.height) * resolution
            ballCamTexture = makeTexture(width: width, height: height)
            ballCamDepthStencil = makeTexture(width: width, height: height, pixelFormat: .depth32Float_stencil8)
            ballCamMask = makeTexture(width: width, height: height)
            ballCamGlowA = makeTexture(width: width / 2, height: height / 2)
            ballCamGlowB = makeTexture(width: width / 2, height: height / 2)
            scene.fillBallCam(ballCamScene)
            ballCamFrames = 0
        }
        guard let target = ballCamTexture, let depth = ballCamDepthStencil else { return false }
        if ballCamFrames % GlowRenderer.ballCamEvery == 0 {
            ballCamScene.mirror(scene.ballCamSnapshots, centre: scene.ballCamCentre)
            ballCamRenderer.update(atTime: now)
            let camPass = MTLRenderPassDescriptor()
            camPass.colorAttachments[0].texture = target
            camPass.colorAttachments[0].loadAction = .clear
            camPass.colorAttachments[0].storeAction = .store
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
            FieldArt.sky.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            camPass.colorAttachments[0].clearColor = MTLClearColor(red: red, green: green, blue: blue, alpha: 1)
            camPass.depthAttachment.texture = depth
            camPass.depthAttachment.loadAction = .clear
            camPass.depthAttachment.storeAction = .dontCare
            camPass.stencilAttachment.texture = depth
            camPass.stencilAttachment.loadAction = .clear
            camPass.stencilAttachment.storeAction = .dontCare
            ballCamRenderer.render(withViewport: CGRect(x: 0, y: 0, width: target.width, height: target.height),
                                   commandBuffer: commands, renderPassDescriptor: camPass)
            // The glow: an empty mask, so everything takes the plain threshold.
            if let mask = ballCamMask, let glowA = ballCamGlowA, let glowB = ballCamGlowB {
                let clear = MTLRenderPassDescriptor()
                clear.colorAttachments[0].texture = mask
                clear.colorAttachments[0].loadAction = .clear
                clear.colorAttachments[0].storeAction = .store
                clear.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                commands.makeRenderCommandEncoder(descriptor: clear)?.endEncoding()
                var uniforms = camGlowUniforms(glowA)
                pass(commands, pipeline: bright, into: glowA, sources: [target, mask], uniforms: uniforms)
                for _ in 0..<GlowSettings.blurPasses {
                    uniforms.direction = SIMD2(1, 0)
                    pass(commands, pipeline: blur, into: glowB, sources: [glowA], uniforms: uniforms)
                    uniforms.direction = SIMD2(0, 1)
                    pass(commands, pipeline: blur, into: glowA, sources: [glowB], uniforms: uniforms)
                }
            }
        }
        ballCamFrames += 1
        return true
    }

    private func camGlowUniforms(_ glow: MTLTexture) -> GlowUniforms {
        GlowUniforms(texelSize: SIMD2(1 / Float(glow.width), 1 / Float(glow.height)), direction: .zero,
                     threshold: GlowSettings.threshold, bodyThreshold: GlowSettings.bodyThreshold,
                     softness: GlowSettings.softness, intensity: GlowSettings.intensity, tint: GlowSettings.tint)
    }

    /// The ball cam's texture on a trapezoid, a quarter of the screen across at the top and a
    /// little less at the bottom, over the upper screen at the cam's place across.
    private func layBallCam(_ encoder: MTLRenderCommandEncoder, aspect screenAspect: Float) {
        guard let texture = ballCamTexture else { return }
        assert(MemoryLayout<SIMD3<Float>>.stride == 16)
        let camAspect = Float(BallCamScene.view.width / BallCamScene.view.height)
        let topWidth: Float = 0.5, bottomWidth: Float = 0.42
        let height = (topWidth + bottomWidth) / 2 * screenAspect / camAspect
        let centreX = Float(scene.ballCamScreenX) * 2 - 1
        let top: Float = 0.9, bottom = top - height
        // Laid out as Metal's float2 then float3: the float3 sits at 16, 32 bytes a corner.
        struct Corner { var position: SIMD2<Float>; var pad: SIMD2<Float> = .zero; var uvq: SIMD3<Float> }
        var corners: [Corner] = [
            Corner(position: SIMD2(centreX - topWidth / 2, top), uvq: SIMD3(0, 0, 1) * topWidth),
            Corner(position: SIMD2(centreX + topWidth / 2, top), uvq: SIMD3(1, 0, 1) * topWidth),
            Corner(position: SIMD2(centreX - bottomWidth / 2, bottom), uvq: SIMD3(0, 1, 1) * bottomWidth),
            Corner(position: SIMD2(centreX + bottomWidth / 2, bottom), uvq: SIMD3(1, 1, 1) * bottomWidth),
        ]
        encoder.setRenderPipelineState(ballCamPipeline)
        encoder.setVertexBytes(&corners, length: MemoryLayout<Corner>.stride * corners.count, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentTexture(ballCamGlowA ?? texture, index: 1)
        encoder.setFragmentSamplerState(nearest, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 1)
        var uniforms = camGlowUniforms(ballCamGlowA ?? texture)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GlowUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func pass(_ commands: MTLCommandBuffer, pipeline: MTLRenderPipelineState, descriptor: MTLRenderPassDescriptor,
                      sources: [MTLTexture], uniforms: GlowUniforms, then extra: ((MTLRenderCommandEncoder) -> Void)? = nil) {
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipeline)
        for (index, texture) in sources.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        encoder.setFragmentSamplerState(sampler, index: 0)
        var uniforms = uniforms
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GlowUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        extra?(encoder)
        encoder.endEncoding()
    }
}
