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

        let library = device.makeDefaultLibrary()!
        func pipeline(_ fragment: String) -> MTLRenderPipelineState {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "glowVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try! device.makeRenderPipelineState(descriptor: descriptor)
        }
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
        maskScene.mirror(scene.bodySnapshots, size: scene.size, cameraPosition: scene.cameraPosition, cameraScale: scene.cameraScale)
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
        pass(commands, pipeline: composite, descriptor: screenPass, sources: [sceneTexture, glowA], uniforms: uniforms)

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

    private func pass(_ commands: MTLCommandBuffer, pipeline: MTLRenderPipelineState, descriptor: MTLRenderPassDescriptor,
                      sources: [MTLTexture], uniforms: GlowUniforms) {
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipeline)
        for (index, texture) in sources.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        encoder.setFragmentSamplerState(sampler, index: 0)
        var uniforms = uniforms
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GlowUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
