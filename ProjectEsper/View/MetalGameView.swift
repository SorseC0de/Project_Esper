import MetalKit
import simd
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
        #if os(tvOS)
        // 1080p, whatever the TV: the pixel art doubles exactly onto a 4K screen, unsmoothed.
        // The view's scale won't hold at 1 there, so the drawable is sized by hand.
        autoResizeDrawable = false
        layer.magnificationFilter = .nearest
        #endif
        isUserInteractionEnabled = false
        delegate = renderer
    }

    required init(coder: NSCoder) { fatalError() }

    #if os(tvOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        if drawableSize != bounds.size { drawableSize = bounds.size }
    }
    #endif

    /// Drawable pixels per point: the screen's scale, or 1 on the TV. Not read off the
    /// drawable: when the delegate hears of a new size the drawable still has the old one,
    /// 0 on the first, which put the camera at scale 0 and drew no world at all.
    var renderScale: CGFloat {
        #if os(tvOS)
        1
        #else
        contentScaleFactor
        #endif
    }
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
    /// The head's energy cubes, drawn into the scene after SpriteKit, before the glow.
    private let cubePipeline: MTLRenderPipelineState?
    private let cubeDepth: MTLDepthStencilState?
    private let cubeVertices: MTLBuffer?
    private var cubeInstanceBuffers: [MTLBuffer] = []
    private static let cubeCapacity = 512
    private var framesDrawn = 0
    private var fpsWindowStart = CACurrentMediaTime()
    private var lastDraw = CACurrentMediaTime()
    private var worstGap = 0.0
    /// The blur's step in the glow's texels. The TV renders at 1080p, half what the 4K screen
    /// was drawn at, so its half-size glow steps half a texel to spread as far as it did.
    #if os(tvOS)
    private let blurStep: Float = 0.5
    #else
    private let blurStep: Float = 1
    #endif
    private var frameNumber = 0
    /// Each stage's CPU time on this thread and GPU time in its own command buffer, summed
    /// over the second and shown under the frame rate as milliseconds a frame.
    private var cpuTotals: [String: Double] = [:]
    private let gpuTotals = StageTimes()
    private static let stageOrder = ["update", "scene", "mask", "glow", "cam", "comp"]
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
        // Laid over the screen at two thirds.
        camDescriptor.colorAttachments[0].isBlendingEnabled = true
        camDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        camDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        camDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        camDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
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

        let cubeDescriptor = MTLRenderPipelineDescriptor()
        cubeDescriptor.vertexFunction = library.makeFunction(name: "cube_vertex")
        cubeDescriptor.fragmentFunction = library.makeFunction(name: "cube_fragment")
        cubeDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        cubeDescriptor.colorAttachments[0].isBlendingEnabled = true
        cubeDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        cubeDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        cubeDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        cubeDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        cubeDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        cubeDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        cubePipeline = try? device.makeRenderPipelineState(descriptor: cubeDescriptor)
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        cubeDepth = device.makeDepthStencilState(descriptor: depth)
        cubeVertices = device.makeBuffer(bytes: CubeMesh.unit, length: CubeMesh.unit.count * MemoryLayout<CubeVertex>.stride)
        cubeInstanceBuffers = (0..<3).compactMap { _ in
            device.makeBuffer(length: GlowRenderer.cubeCapacity * MemoryLayout<CubeInstance>.stride, options: .storageModeShared)
        }
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        sceneTexture = makeTexture(width: Int(size.width), height: Int(size.height))
        sceneDepthStencil = makeTexture(width: Int(size.width), height: Int(size.height), pixelFormat: .depth32Float_stencil8)
        bodyMask = makeTexture(width: Int(size.width), height: Int(size.height))
        makeGlowTextures(for: size)
        scene.attach(size: view.bounds.size, displayScale: (view as? GameMetalView)?.renderScale ?? view.contentScaleFactor, insets: view.safeAreaInsets)
    }

    private func makeGlowTextures(for size: CGSize) {
        glowA = makeTexture(width: Int(size.width) / 2, height: Int(size.height) / 2)
        glowB = makeTexture(width: Int(size.width) / 2, height: Int(size.height) / 2)
    }

    private func makeTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: max(width, 1), height: max(height, 1), mipmapped: false)
        descriptor.usage = pixelFormat == .bgra8Unorm ? [.renderTarget, .shaderRead] : [.renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)!
    }

    func draw(in view: MTKView) {
        // A drawable sized by hand may not have told the delegate.
        if sceneTexture.map({ $0.width != Int(view.drawableSize.width) || $0.height != Int(view.drawableSize.height) }) ?? true {
            mtkView(view, drawableSizeWillChange: view.drawableSize)
        }
        guard let drawable = view.currentDrawable, let screenPass = view.currentRenderPassDescriptor,
              let sceneTexture, let sceneDepthStencil, let bodyMask, let glowA, let glowB,
              let commands = queue.makeCommandBuffer() else { return }

        if scene.size != view.bounds.size || scene.safeInsets != view.safeAreaInsets {
            scene.attach(size: view.bounds.size, displayScale: (view as? GameMetalView)?.renderScale ?? view.contentScaleFactor, insets: view.safeAreaInsets)
        }
        let now = CACurrentMediaTime()
        framesDrawn += 1
        worstGap = max(worstGap, now - lastDraw)
        lastDraw = now
        if now - fpsWindowStart >= 1 {
            scene.framesPerSecond = Int((Double(framesDrawn) / (now - fpsWindowStart)).rounded())
            scene.worstFrameMilliseconds = Int((worstGap * 1000).rounded())
            let frames = Double(max(framesDrawn, 1))
            let gpu = gpuTotals.take()
            func line(_ totals: [String: Double]) -> String {
                GlowRenderer.stageOrder.compactMap { name in totals[name].map { "\(name) \(String(format: "%.1f", $0 * 1000 / frames))" } }.joined(separator: "  ")
            }
            let span = gpu["frame"].map { String(format: "%.1f", $0 * 1000 / frames) } ?? "-"
            // Ours on the CPU against the whole frame: the difference is everything else on
            // the main thread, the HUD's view among it.
            let ours = cpuTotals.values.reduce(0, +) * 1000 / frames
            let interval = (now - fpsWindowStart) * 1000 / frames
            let readout = String(format: "cpu ours %.1f of %.1f frame", ours, interval)
            // The update's own sections, the costliest first.
            let sections = scene.takeSectionTimes().sorted { $0.value > $1.value }.prefix(6)
                .map { "\($0.key) \(String(format: "%.1f", $0.value * 1000 / frames))" }.joined(separator: "  ")
            scene.frameReadout = "cpu  \(line(cpuTotals))\nupdate  \(sections)\n\(readout)\ngpu  \(line(gpu))\ngpu frame \(span)  \n\(Int(view.drawableSize.width))x\(Int(view.drawableSize.height))  glow \(glowA.width)x\(glowA.height)"
            cpuTotals = [:]
            framesDrawn = 0
            worstGap = 0
            fpsWindowStart = now
        }
        var mark = CACurrentMediaTime()
        func lap(_ name: String) {
            let time = CACurrentMediaTime()
            cpuTotals[name, default: 0] += time - mark
            mark = time
        }
        frameNumber += 1
        let frame = frameNumber
        func timed(_ name: String) -> MTLCommandBuffer? {
            let buffer = queue.makeCommandBuffer()
            buffer?.addCompletedHandler { [gpuTotals] done in
                gpuTotals.add(name, done.gpuEndTime - done.gpuStartTime)
                if name == "scene" { gpuTotals.begin(frame, at: done.gpuStartTime) }
            }
            return buffer
        }
        skRenderer.update(atTime: now)
        lap("update")
        guard let sceneCommands = timed("scene"), let maskCommands = timed("mask"), let glowCommands = timed("glow"),
              let camCommands = timed("cam") else { return }
        commands.addCompletedHandler { [gpuTotals] done in
            gpuTotals.add("comp", done.gpuEndTime - done.gpuStartTime)
            gpuTotals.end(frame, at: done.gpuEndTime)
        }

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
                          commandBuffer: sceneCommands, renderPassDescriptor: scenePass)
        drawCubes(sceneCommands, into: sceneTexture, depth: sceneDepthStencil, frame: frame)
        sceneCommands.commit()
        lap("scene")

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
                            commandBuffer: maskCommands, renderPassDescriptor: maskPass)
        maskCommands.commit()
        lap("mask")

        var uniforms = GlowUniforms(
            texelSize: SIMD2(blurStep / Float(glowA.width), blurStep / Float(glowA.height)),
            direction: .zero,
            threshold: GlowSettings.threshold,
            bodyThreshold: GlowSettings.bodyThreshold,
            softness: GlowSettings.softness,
            intensity: GlowSettings.intensity,
            tint: GlowSettings.tint)

        pass(glowCommands, pipeline: bright, into: glowA, sources: [sceneTexture, bodyMask], uniforms: uniforms)
        for _ in 0..<GlowSettings.blurPasses {
            uniforms.direction = SIMD2(1, 0)
            pass(glowCommands, pipeline: blur, into: glowB, sources: [glowA], uniforms: uniforms)
            uniforms.direction = SIMD2(0, 1)
            pass(glowCommands, pipeline: blur, into: glowA, sources: [glowB], uniforms: uniforms)
        }
        glowCommands.commit()
        lap("glow")
        let camReady = drawBallCam(camCommands, at: now)
        camCommands.commit()
        lap("cam")
        pass(commands, pipeline: composite, descriptor: screenPass, sources: [sceneTexture, glowA], uniforms: uniforms,
             then: camReady ? { [weak self] encoder in self?.layBallCam(encoder, aspect: Float(view.drawableSize.width / max(view.drawableSize.height, 1))) } : nil)

        commands.present(drawable)
        commands.commit()
        lap("comp")
    }

    /// The scene's cubes over what SpriteKit drew, on the scene's camera: orthographic, one
    /// art pixel to the scene's, depth only sorting a cube's own faces; lit from above left.
    private func drawCubes(_ commands: MTLCommandBuffer, into target: MTLTexture, depth: MTLTexture, frame: Int) {
        let cubes = Array(scene.cubeInstances.prefix(GlowRenderer.cubeCapacity))
        guard !cubes.isEmpty, let cubePipeline, let cubeDepth, let cubeVertices, !cubeInstanceBuffers.isEmpty else { return }
        let buffer = cubeInstanceBuffers[frame % cubeInstanceBuffers.count]
        buffer.contents().copyMemory(from: cubes, byteCount: cubes.count * MemoryLayout<CubeInstance>.stride)
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.depthAttachment.texture = depth
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.clearDepth = 1
        descriptor.depthAttachment.storeAction = .dontCare
        descriptor.stencilAttachment.texture = depth
        descriptor.stencilAttachment.loadAction = .dontCare
        descriptor.stencilAttachment.storeAction = .dontCare
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        // Scene coordinates to clip space: the camera's middle at the centre, its view the
        // screen's points times its scale across; a cube's depth sorts only its own faces.
        let viewWidth = Float(scene.size.width * scene.cameraScale), viewHeight = Float(scene.size.height * scene.cameraScale)
        let camera = scene.cameraPosition
        let projection = simd_float4x4(columns: (
            SIMD4<Float>(2 / viewWidth, 0, 0, 0),
            SIMD4<Float>(0, 2 / viewHeight, 0, 0),
            SIMD4<Float>(0, 0, -0.001, 0),
            SIMD4<Float>(-2 * Float(camera.x) / viewWidth, -2 * Float(camera.y) / viewHeight, 0.5, 1)))
        var uniforms = CubeUniforms(viewProjection: projection, light: SIMD4<Float>(-0.4, 0.7, 0.6, 0))
        encoder.setRenderPipelineState(cubePipeline)
        encoder.setDepthStencilState(cubeDepth)
        encoder.setCullMode(.back)
        encoder.setVertexBuffer(cubeVertices, offset: 0, index: 0)
        encoder.setVertexBuffer(buffer, offset: 0, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<CubeUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CubeUniforms>.stride, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: CubeMesh.unit.count, instanceCount: cubes.count)
        encoder.endEncoding()
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
        let points = BallCamScene.corners(centre: scene.ballCamScreenX * 2 - 1, screenAspect: CGFloat(screenAspect))
        let topWidth = Float(BallCamScene.topWidth), bottomWidth = Float(BallCamScene.bottomWidth)
        // Laid out as Metal's float2 then float3: the float3 sits at 16, 32 bytes a corner.
        struct Corner { var position: SIMD2<Float>; var pad: SIMD2<Float> = .zero; var uvq: SIMD3<Float> }
        let uvq = [SIMD3<Float>(0, 0, 1) * topWidth, SIMD3<Float>(1, 0, 1) * topWidth,
                   SIMD3<Float>(0, 1, 1) * bottomWidth, SIMD3<Float>(1, 1, 1) * bottomWidth]
        var corners = points.indices.map { Corner(position: SIMD2(Float(points[$0].x), Float(points[$0].y)), uvq: uvq[$0]) }
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

/// GPU times by stage, added from the command buffers' completion handlers on their own
/// thread and taken on the main one.
final class StageTimes: @unchecked Sendable {
    private let lock = NSLock()
    private var totals: [String: Double] = [:]

    func add(_ name: String, _ seconds: Double) {
        lock.lock()
        totals[name, default: 0] += seconds
        lock.unlock()
    }

    /// The whole frame on the GPU: its first stage's start to its last one's end, as "frame".
    private var starts: [Int: Double] = [:]

    func begin(_ frame: Int, at time: Double) {
        lock.lock()
        starts[frame] = time
        lock.unlock()
    }

    func end(_ frame: Int, at time: Double) {
        lock.lock()
        if let start = starts.removeValue(forKey: frame) { totals["frame", default: 0] += time - start }
        starts = starts.filter { $0.key > frame - 10 }
        lock.unlock()
    }

    func take() -> [String: Double] {
        lock.lock()
        defer { totals = [:]; lock.unlock() }
        return totals
    }
}
