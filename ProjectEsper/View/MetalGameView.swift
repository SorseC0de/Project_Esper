import MetalKit
import MetalPerformanceShaders
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
        #else
        // On a Mac the iPad app is drawn at the 12.9-inch iPad Pro's 2732 by 2048, every pass
        // across 5.6 million pixels: there it draws at the scene's render share of the screen's
        // scale, half where every game pixel stays whole at that, doubled up unsmoothed as the TV
        // is, a quarter of the work; the camera's framing is the screen's own scale's either way.
        if GameMetalView.onMac { layer.magnificationFilter = .nearest }
        #endif
        if FootageRun.requested {
            // Footage: drawn at the video's size whatever the window, the drawable readable for the recorder.
            autoResizeDrawable = false
            drawableSize = FootageRun.videoSize
            framebufferOnly = false
        }
        isUserInteractionEnabled = false
        delegate = renderer
    }

    required init(coder: NSCoder) { fatalError() }

    static let onMac = ProcessInfo.processInfo.isiOSAppOnMac

    #if os(tvOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        if drawableSize != bounds.size { drawableSize = bounds.size }
    }
    /// The TV frames and draws at 1080p, one pixel a point.
    var framingScale: CGFloat { 1 }
    func applyRenderShare() {}
    #else
    /// The screen's own scale, the camera's framing's; 1 for footage, as the TV's.
    var framingScale: CGFloat { FootageRun.requested ? 1 : (traitCollection.displayScale > 0 ? traitCollection.displayScale : contentScaleFactor) }
    /// On a Mac the drawable kept at the scene's render share of the screen's scale; the window's
    /// screen sets it back on a move or a resize. Checked every frame, cheaply.
    func applyRenderShare() {
        guard !FootageRun.requested, GameMetalView.onMac, framingScale >= 2 else { return }
        let wanted = framingScale * scene.renderShare
        if contentScaleFactor != wanted { contentScaleFactor = wanted }
    }
    override func layoutSubviews() {
        applyRenderShare()
        super.layoutSubviews()
    }
    #endif

    /// Drawable pixels per point: the screen's scale, or 1 on the TV. Not read off the
    /// drawable: when the delegate hears of a new size the drawable still has the old one,
    /// 0 on the first, which put the camera at scale 0 and drew no world at all.
    var renderScale: CGFloat {
        #if os(tvOS)
        1
        #else
        FootageRun.requested ? 1 : contentScaleFactor
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
    var unglowed: SIMD4<Float> = .zero
    var wave: SIMD4<Float> = .zero
    var waterTop: SIMD4<Float> = .zero
    var waterBottom: SIMD4<Float> = .zero
    var hood = SIMD4<Float>(GlowSettings.hoodShare, 0, 0, 0)
    var energy = GlowSettings.energyUniforms
    /// A clash's colour split: where it's centred, as a share of the screen, its reach and strength;
    /// and the two colours the fringes take. None at a reach of 0.
    var aberration: SIMD4<Float> = .zero
    var aberrationFirst: SIMD4<Float> = .zero
    var aberrationSecond: SIMD4<Float> = .zero
    /// A wash over the whole world, its colour and its strength in w, left off what the mask has in
    /// yellow; none at 0.
    var wash: SIMD4<Float> = .zero
    /// Each energy colour's hood tones, its light and its shadow, so the glow keeps the shadow under the light.
    var hoodLight = GlowSettings.hoodLightUniforms
    var hoodShadow = GlowSettings.hoodShadowUniforms
}

/// Draws the scene, then the glow: bright pass at half size, a few blurs, and the composite.
final class GlowRenderer: NSObject, MTKViewDelegate {
    /// The machine as the readout shows it: its thermal state, Low Power Mode, and this app's memory
    /// footprint. Every CPU section and GPU pass slowing together at once is the machine, not the
    /// game: throttled hot, saving power, or short of memory.
    static func machineReadout() -> String {
        let thermal = switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "SERIOUS"
        case .critical: "CRITICAL"
        @unknown default: "?"
        }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        let footprint = result == KERN_SUCCESS ? "\(info.phys_footprint / 1_048_576) MB" : "?"
        return "thermal \(thermal)  low power \(ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "off")  memory \(footprint)"
    }

    /// Every node under one, for the readout: a count that only climbs is something left behind.
    static func nodeCount(_ node: SKNode) -> Int { node.children.reduce(node.children.count) { $0 + nodeCount($1) } }

    private static func channels(_ colour: RGB) -> SIMD3<Float> {
        SIMD3(Float((colour >> 16) & 0xFF), Float((colour >> 8) & 0xFF), Float(colour & 0xFF)) / 255
    }

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
    /// FLO's orbs, spheres drawn by the cubes' pipeline.
    private let sphereVertices: MTLBuffer?
    private var sphereInstanceBuffers: [MTLBuffer] = []
    private static let sphereCapacity = 512
    /// FloState's strings' diamonds, drawn by the cubes' pipeline.
    private let diamondVertices: MTLBuffer?
    private var diamondInstanceBuffers: [MTLBuffer] = []
    private static let diamondCapacity = 512
    /// 47's locked rims' hexagons (`HexSphere`), drawn last, added on as light, writing no depth.
    private let hexVertices: MTLBuffer?
    private var hexInstanceBuffers: [MTLBuffer] = []
    private static let hexCapacity = 384
    /// Scored-on rims' glass (`GlassShatter`), drawn as the hexagons are.
    private let glassVertices: MTLBuffer?
    private var glassInstanceBuffers: [MTLBuffer] = []
    private static let glassCapacity = 256
    private let translucentDepth: MTLDepthStencilState?
    private let hexPipeline: MTLRenderPipelineState?
    /// Platform Protein Shake's blocks, cubes sized to the slabs, added on as the hexagons are.
    private let blockPipeline: MTLRenderPipelineState?
    private var blockInstanceBuffers: [MTLBuffer] = []
    private static let blockCapacity = 32
    private static let cubeCapacity = 2048
    /// The players' bodies and lines in white and the rims' art in green, on black, by a
    /// renderer of their own, drawn only on a frame with cubes behind them: a back leg's
    /// leaves out the bodies, the net's the bodies and the rims.
    private let occluderScene = MaskScene(whiteBodies: true)
    private let occluderRenderer: SKRenderer
    private var occluderTexture: MTLTexture?
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
    /// The last frame's own laps and update sections, and the worst frame's of this second, named.
    private var frameLaps: [String: Double] = [:]
    private var worstBreakdown = ""
    private let gpuTotals = StageTimes()
    private static let stageOrder = ["update", "scene", "nets", "occl", "cubes", "mask", "glow", "cam", "comp"]
    private var sceneTexture: MTLTexture?
    /// The bodies alone, for the glow's per-object threshold.
    private var bodyMask: MTLTexture?
    /// SpriteKit draws with the stencil buffer, so its pass needs one.
    private var sceneDepthStencil: MTLTexture?
    private var glowA: MTLTexture?
    private var glowB: MTLTexture?
    /// The stage preview's page: the frame drawn off the screen, each panel's picture, and the
    /// pipeline that copies one into the other and lays the panels down.
    private var shotTexture: MTLTexture?
    private var panelTextures: [MTLTexture] = []
    private let mangaPipeline: MTLRenderPipelineState
    /// Footage: the HUD's scene drawn into the video by a renderer of its own, over the world blurred
    /// and washed while a screen with the pause's ground is up, the veil's share faded in and out.
    private var hudRenderer: SKRenderer?
    private var footageBlurred: MTLTexture?
    private var footageWash: SKSpriteNode?
    private var footageVeil = 0.0
    /// The recording the veil's share belongs to: a new scene's starts clear.
    private var footageVeilRecording: ObjectIdentifier?

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
        occluderRenderer = SKRenderer(device: device)
        occluderRenderer.scene = occluderScene

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
        let mangaDescriptor = MTLRenderPipelineDescriptor()
        mangaDescriptor.vertexFunction = library.makeFunction(name: "mangaVertex")
        mangaDescriptor.fragmentFunction = library.makeFunction(name: "mangaFragment")
        mangaDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        mangaPipeline = try! device.makeRenderPipelineState(descriptor: mangaDescriptor)
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
        // The hexagons the same, but added onto what's under them, as light.
        cubeDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        cubeDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        hexPipeline = try? device.makeRenderPipelineState(descriptor: cubeDescriptor)
        cubeDescriptor.vertexFunction = library.makeFunction(name: "block_vertex")
        cubeDescriptor.fragmentFunction = library.makeFunction(name: "block_fragment")
        blockPipeline = try? device.makeRenderPipelineState(descriptor: cubeDescriptor)
        blockInstanceBuffers = (0..<3).compactMap { _ in
            device.makeBuffer(length: GlowRenderer.blockCapacity * MemoryLayout<CubeInstance>.stride, options: .storageModeShared)
        }
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .less
        depth.isDepthWriteEnabled = true
        cubeDepth = device.makeDepthStencilState(descriptor: depth)
        depth.isDepthWriteEnabled = false
        translucentDepth = device.makeDepthStencilState(descriptor: depth)
        hexVertices = device.makeBuffer(bytes: HexSphere.tile, length: HexSphere.tile.count * MemoryLayout<CubeVertex>.stride)
        glassVertices = device.makeBuffer(bytes: ShardMesh.unit, length: ShardMesh.unit.count * MemoryLayout<CubeVertex>.stride)
        glassInstanceBuffers = (0..<3).compactMap { _ in
            device.makeBuffer(length: GlowRenderer.glassCapacity * MemoryLayout<CubeInstance>.stride, options: .storageModeShared)
        }
        hexInstanceBuffers = (0..<3).compactMap { _ in
            device.makeBuffer(length: GlowRenderer.hexCapacity * MemoryLayout<CubeInstance>.stride, options: .storageModeShared)
        }
        cubeVertices = device.makeBuffer(bytes: CubeMesh.unit, length: CubeMesh.unit.count * MemoryLayout<CubeVertex>.stride)
        sphereVertices = device.makeBuffer(bytes: SphereMesh.unit, length: SphereMesh.unit.count * MemoryLayout<CubeVertex>.stride)
        diamondVertices = device.makeBuffer(bytes: DiamondMesh.unit, length: DiamondMesh.unit.count * MemoryLayout<CubeVertex>.stride)
        diamondInstanceBuffers = (0..<3).compactMap { _ in
            device.makeBuffer(length: GlowRenderer.diamondCapacity * MemoryLayout<CubeInstance>.stride, options: .storageModeShared)
        }
        sphereInstanceBuffers = (0..<3).compactMap { _ in
            device.makeBuffer(length: GlowRenderer.sphereCapacity * MemoryLayout<CubeInstance>.stride, options: .storageModeShared)
        }
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
        occluderTexture = makeTexture(width: Int(size.width), height: Int(size.height))
        shotTexture = makeTexture(width: Int(size.width), height: Int(size.height))
        // Each panel's picture the size it's drawn on the page.
        let fit = MangaPage.fit(in: size)
        panelTextures = MangaPage.panels.indices.map { panel in
            let box = MangaPage.bounds(panel)
            return makeTexture(width: Int((box.width * fit.scale).rounded()), height: Int((box.height * fit.scale).rounded()))
        }
        makeGlowTextures(for: size)
        // Laid out just after: a new size arrives inside SwiftUI's own layout, and the scene's
        // layout publishes to it (the pause button's place, the screens' grounds).
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view else { return }
            self.scene.attach(size: view.bounds.size, displayScale: (view as? GameMetalView)?.renderScale ?? view.contentScaleFactor,
                              framingScale: (view as? GameMetalView)?.framingScale, insets: view.safeAreaInsets)
        }
    }

    private func makeGlowTextures(for size: CGSize) {
        glowA = makeTexture(width: Int(size.width) / 2, height: Int(size.height) / 2)
        glowB = makeTexture(width: Int(size.width) / 2, height: Int(size.height) / 2)
    }

    /// Footage: what the HUD's view and the screens' ground lay over the world on the screen, laid
    /// onto the video's frame instead, the HUD's actions on the footage's clock.
    private func layFootageHud(_ commands: MTLCommandBuffer, onto target: MTLTexture, depth: MTLTexture, now: CFTimeInterval, recording: ObjectIdentifier) {
        let hudScene = scene.hudScene
        let renderer = hudRenderer ?? {
            let made = SKRenderer(device: device)
            made.scene = hudScene
            made.ignoresSiblingOrder = true
            hudRenderer = made
            return made
        }()
        let wash = footageWash ?? {
            let made = SKSpriteNode(color: .black, size: CGSize(width: 100_000, height: 100_000))
            // Under the HUD's own layer.
            made.zPosition = hudScene.hud.zPosition - 1
            hudScene.addChild(made)
            footageWash = made
            return made
        }()
        hudScene.isPaused = false
        if footageVeilRecording != recording {
            footageVeilRecording = recording
            footageVeil = scene.footageVeiled ? 1 : 0
        }
        let step = 1 / FootageRun.veilFrames
        footageVeil = scene.footageVeiled ? min(footageVeil + step, 1) : max(footageVeil - step, 0)
        wash.alpha = FootageRun.veilWash * footageVeil
        renderer.update(atTime: now)
        if footageVeil > 0 {
            if footageBlurred.map({ $0.width != target.width || $0.height != target.height }) ?? true {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: target.pixelFormat, width: target.width, height: target.height, mipmapped: false)
                descriptor.usage = [.shaderRead, .shaderWrite]
                descriptor.storageMode = .private
                footageBlurred = device.makeTexture(descriptor: descriptor)
            }
            if let blurred = footageBlurred {
                let blur = MPSImageGaussianBlur(device: device, sigma: Float(FootageRun.veilBlur * footageVeil))
                blur.edgeMode = .clamp
                blur.encode(commandBuffer: commands, sourceTexture: target, destinationTexture: blurred)
                if let blit = commands.makeBlitCommandEncoder() {
                    blit.copy(from: blurred, to: target)
                    blit.endEncoding()
                }
            }
        }
        guard scene.footageShowsHud || footageVeil > 0 else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .load
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.stencilAttachment.texture = depth
        pass.stencilAttachment.loadAction = .clear
        pass.stencilAttachment.storeAction = .dontCare
        renderer.render(withViewport: CGRect(x: 0, y: 0, width: target.width, height: target.height), commandBuffer: commands, renderPassDescriptor: pass)
    }

    private func makeTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: max(width, 1), height: max(height, 1), mipmapped: false)
        descriptor.usage = pixelFormat == .bgra8Unorm ? [.renderTarget, .shaderRead] : [.renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)!
    }

    func draw(in view: MTKView) {
        (view as? GameMetalView)?.applyRenderShare()
        // A drawable sized by hand may not have told the delegate.
        if sceneTexture.map({ $0.width != Int(view.drawableSize.width) || $0.height != Int(view.drawableSize.height) }) ?? true {
            mtkView(view, drawableSizeWillChange: view.drawableSize)
        }
        guard let drawable = view.currentDrawable, let screenPass = view.currentRenderPassDescriptor,
              let sceneTexture, let sceneDepthStencil, let bodyMask, let glowA, let glowB,
              let commands = queue.makeCommandBuffer() else { return }

        // Footage is framed and drawn at the video's size, whatever the window's.
        let viewSize = FootageRun.requested ? FootageRun.videoSize : view.bounds.size
        let insets = FootageRun.requested ? UIEdgeInsets.zero : view.safeAreaInsets
        if scene.size != viewSize || scene.safeInsets != insets {
            scene.attach(size: viewSize, displayScale: (view as? GameMetalView)?.renderScale ?? view.contentScaleFactor,
                         framingScale: (view as? GameMetalView)?.framingScale, insets: insets)
        }
        let now = scene.transformCapture?.tick() ?? scene.footage?.tick() ?? CACurrentMediaTime()
        framesDrawn += 1
        let lastFrameSections = scene.takeFrameSectionTimes()
        if now - lastDraw > worstGap {
            worstGap = now - lastDraw
            func named(_ times: [String: Double]) -> String {
                times.filter { $0.value >= 0.0005 }.sorted { $0.value > $1.value }.prefix(5)
                    .map { "\($0.key) \(String(format: "%.1f", $0.value * 1000))" }.joined(separator: " ")
            }
            let ours = frameLaps.values.reduce(0, +) * 1000
            worstBreakdown = String(format: "worst %.1f, ours %.1f: ", worstGap * 1000, ours) + named(frameLaps) + "\n  update: " + named(lastFrameSections)
        }
        frameLaps = [:]
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
                + "\nnodes scene \(GlowRenderer.nodeCount(scene))  mask \(GlowRenderer.nodeCount(maskScene))  hud \(GlowRenderer.nodeCount(scene.hudScene))"
                + "\n\(GlowRenderer.machineReadout())"
                + "\n\(worstBreakdown)"
            cpuTotals = [:]
            framesDrawn = 0
            worstGap = 0
            fpsWindowStart = now
        }
        var mark = CACurrentMediaTime()
        func lap(_ name: String) {
            let time = CACurrentMediaTime()
            cpuTotals[name, default: 0] += time - mark
            frameLaps[name, default: 0] += time - mark
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
        // Capturing, over black, or white for the frame's second drawing.
        if let capture = scene.transformCapture {
            let white: Double = capture.drawsOverWhite ? 1 : 0
            scenePass.colorAttachments[0].clearColor = MTLClearColor(red: white, green: white, blue: white, alpha: 1)
        } else {
            scenePass.colorAttachments[0].clearColor = MTLClearColor(red: red, green: green, blue: blue, alpha: 1)
        }
        scenePass.depthAttachment.texture = sceneDepthStencil
        scenePass.depthAttachment.loadAction = .clear
        scenePass.depthAttachment.storeAction = .dontCare
        scenePass.stencilAttachment.texture = sceneDepthStencil
        scenePass.stencilAttachment.loadAction = .clear
        scenePass.stencilAttachment.storeAction = .dontCare
        skRenderer.render(withViewport: CGRect(x: 0, y: 0, width: sceneTexture.width, height: sceneTexture.height),
                          commandBuffer: sceneCommands, renderPassDescriptor: scenePass)
        lap("scene")
        drawCubes(sceneCommands, into: sceneTexture, depth: sceneDepthStencil, frame: frame, now: now, lap: lap)
        sceneCommands.commit()
        lap("cubes")

        // The bodies alone, mirrored into their own scene and drawn by their own renderer.
        maskScene.syncStatic(scene.staticFlats, version: scene.staticFlatsVersion)
        maskScene.mirror(scene.bodySnapshots, flat: scene.flatSnapshots, under: scene.tornadoSnapshots + scene.soundWordSnapshots, through: scene.glowThroughSnapshots, throughFront: scene.glowThroughFrontSnapshots, throughNets: scene.glowThroughNets, cutOut: scene.cutOutSnapshots, hoods: scene.hoodSnapshots, shield: scene.shieldedSnapshots,
                         washFree: scene.washFreeSnapshots, size: scene.size, cameraPosition: scene.cameraPosition, cameraScale: scene.cameraScale, cameraRotation: scene.cameraRotation)
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
        if scene.transformCapture?.drawsOverWhite == true {
            // The white the capture's second drawing goes over doesn't glow.
            uniforms.unglowed = SIMD4(1, 1, 1, 1)
        } else if let background = scene.unglowedBackground {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            background.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            uniforms.unglowed = SIMD4(Float(red), Float(green), Float(blue), 1)
        }
        if let water = scene.waterTint {
            uniforms.waterTop = SIMD4(GlowRenderer.channels(water.top), Float(water.alpha))
            uniforms.waterBottom = SIMD4(GlowRenderer.channels(water.bottom), 0)
        }
        uniforms.hood = SIMD4(scene.hoodGlowShare, 0, 0, 0)
        if let wash = scene.worldWash { uniforms.wash = SIMD4(GlowRenderer.channels(wash.colour), Float(wash.alpha)) }

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
        if let wave = scene.screenWave {
            // A share of a screen pixel's width per game pixel of reach.
            uniforms.wave = SIMD4(Float(wave.reach) / Float(max(view.drawableSize.width, 1)), Float(wave.waves), Float(wave.phase), Float(wave.calmTop))
        }
        if let split = scene.clashAberration {
            uniforms.aberration = SIMD4(split.centre.x, split.centre.y, split.split, split.fringe)
            uniforms.aberrationFirst = SIMD4(GlowRenderer.channels(split.first), 0)
            uniforms.aberrationSecond = SIMD4(GlowRenderer.channels(split.second), 0)
        }
        if let page = scene.mangaPage, let shotTexture, panelTextures.count == MangaPage.panels.count {
            // The stage preview: the frame drawn off the screen, the playing panel's cut taken
            // from its middle, and the page laid on the screen in the stage's place.
            let shotPass = MTLRenderPassDescriptor()
            shotPass.colorAttachments[0].texture = shotTexture
            shotPass.colorAttachments[0].loadAction = .dontCare
            shotPass.colorAttachments[0].storeAction = .store
            pass(commands, pipeline: composite, descriptor: shotPass, sources: [sceneTexture, glowA, bodyMask], uniforms: uniforms)
            if let live = page.live, panelTextures.indices.contains(live) {
                capture(commands, from: shotTexture, into: panelTextures[live], panel: live, screen: view.drawableSize)
            }
            layPage(commands, descriptor: screenPass, shown: page.shown, screen: view.drawableSize)
            // The page full and the big panel's last frame in (captured just above): its picture kept
            // for the stage select's window.
            if let stage = scene.previewShotStage, page.shown >= MangaPage.panels.count, page.settled {
                scene.previewShotStage = nil
                keep(panelTextures[MangaPage.bigPanel], with: commands) { image in
                    StageShots.shared.store(image, for: stage)
                    FootageRun.keepStill(image, named: "preview_\(stage)")
                }
            }
        } else {
            pass(commands, pipeline: composite, descriptor: screenPass, sources: [sceneTexture, glowA, bodyMask], uniforms: uniforms,
                 then: camReady ? { [weak self] encoder in self?.layBallCam(encoder, aspect: Float(view.drawableSize.width / max(view.drawableSize.height, 1))) } : nil)
            // Footage: the frame as shown, the HUD and its screens over it, off the drawable into the scene's video.
            if let recorder = scene.footage?.recorder {
                layFootageHud(commands, onto: drawable.texture, depth: sceneDepthStencil, now: now, recording: ObjectIdentifier(recorder))
                recorder.capture(drawable.texture, with: commands)
            }
        }

        if let capture = scene.transformCapture, let shotTexture, let taken = capture.take() {
            // The frame again into a texture that can be read.
            let shotPass = MTLRenderPassDescriptor()
            shotPass.colorAttachments[0].texture = shotTexture
            shotPass.colorAttachments[0].loadAction = .dontCare
            shotPass.colorAttachments[0].storeAction = .store
            pass(commands, pipeline: composite, descriptor: shotPass, sources: [sceneTexture, glowA, bodyMask], uniforms: uniforms)
            readBack([shotTexture], with: commands) { pictures, width, height in
                capture.save(taken.index, overWhite: taken.overWhite, composite: pictures[0], width: width, height: height)
            }
        }
        commands.present(drawable)
        commands.commit()
        lap("comp")
    }

    /// The scene's cubes over what SpriteKit drew, on the scene's camera: orthographic, one
    /// art pixel to the scene's, depth only sorting a cube's own faces; lit from above left.
    /// `lap` closes the CPU timer's stages inside it: the instances built ("nets", the cylinder nets most of it), the bodies' occluder pass ("occl"), apart from the cubes drawn.
    private func drawCubes(_ commands: MTLCommandBuffer, into target: MTLTexture, depth: MTLTexture, frame: Int, now: CFTimeInterval, lap: (String) -> Void) {
        let cubes = Array(scene.cubeInstances.prefix(GlowRenderer.cubeCapacity))
        let spheres = Array(scene.sphereInstances.prefix(GlowRenderer.sphereCapacity))
        let diamonds = Array(scene.diamondInstances.prefix(GlowRenderer.diamondCapacity))
        let hexes = Array(scene.hexInstances.prefix(GlowRenderer.hexCapacity))
        let blocks = Array(scene.platformInstances.prefix(GlowRenderer.blockCapacity))
        let glass = Array(scene.glassInstances.prefix(GlowRenderer.glassCapacity))
        lap("nets")
        guard !cubes.isEmpty || !spheres.isEmpty || !diamonds.isEmpty || !hexes.isEmpty || !blocks.isEmpty || !glass.isEmpty, let cubePipeline, let cubeDepth, let cubeVertices, !cubeInstanceBuffers.isEmpty,
              let occluderTexture else { return }
        if cubes.contains(where: { $0.flags.x > 0.5 }) || diamonds.contains(where: { $0.flags.x > 0.5 }) || blocks.contains(where: { $0.flags.x > 0.5 })
            || hexes.contains(where: { $0.flags.x > 0.5 }) {
            // The bodies as they stand, for the cubes behind them to keep out of.
            occluderScene.mirror(scene.occluderSnapshots, flat: scene.rimSnapshots, size: scene.size, cameraPosition: scene.cameraPosition, cameraScale: scene.cameraScale, cameraRotation: scene.cameraRotation)
            occluderRenderer.update(atTime: now)
            let occluderPass = MTLRenderPassDescriptor()
            occluderPass.colorAttachments[0].texture = occluderTexture
            occluderPass.colorAttachments[0].loadAction = .clear
            occluderPass.colorAttachments[0].storeAction = .store
            occluderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            occluderPass.depthAttachment.texture = depth
            occluderPass.depthAttachment.loadAction = .clear
            occluderPass.depthAttachment.storeAction = .dontCare
            occluderPass.stencilAttachment.texture = depth
            occluderPass.stencilAttachment.loadAction = .clear
            occluderPass.stencilAttachment.storeAction = .dontCare
            occluderRenderer.render(withViewport: CGRect(x: 0, y: 0, width: occluderTexture.width, height: occluderTexture.height),
                                    commandBuffer: commands, renderPassDescriptor: occluderPass)
        }
        lap("occl")
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
        // screen's points times its scale across, turned back by the camera's turn (Flight B411's
        // lean); a cube's depth sorts only its own faces.
        let viewWidth = Float(scene.size.width * scene.cameraScale), viewHeight = Float(scene.size.height * scene.cameraScale)
        let camera = scene.cameraPosition
        let turn = Float(scene.cameraRotation)
        let c = cos(turn), s = sin(turn)
        let projection = simd_float4x4(columns: (
            SIMD4<Float>(2 * c / viewWidth, -2 * s / viewHeight, 0, 0),
            SIMD4<Float>(2 * s / viewWidth, 2 * c / viewHeight, 0, 0),
            SIMD4<Float>(0, 0, -0.001, 0),
            SIMD4<Float>(-2 * (c * Float(camera.x) + s * Float(camera.y)) / viewWidth,
                         -2 * (-s * Float(camera.x) + c * Float(camera.y)) / viewHeight, 0.5, 1)))
        var uniforms = CubeUniforms(viewProjection: projection, light: SIMD4<Float>(-0.4, 0.7, 0.6, 0))
        if let water = scene.waterTint {
            uniforms.waterTop = SIMD4(GlowRenderer.channels(water.top), Float(water.alpha))
            uniforms.waterBottom = SIMD4(GlowRenderer.channels(water.bottom), Float(target.height))
        }
        encoder.setRenderPipelineState(cubePipeline)
        encoder.setDepthStencilState(cubeDepth)
        encoder.setCullMode(.back)
        encoder.setVertexBuffer(cubeVertices, offset: 0, index: 0)
        encoder.setVertexBuffer(buffer, offset: 0, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<CubeUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CubeUniforms>.stride, index: 2)
        encoder.setFragmentTexture(occluderTexture, index: 0)
        if !cubes.isEmpty {
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: CubeMesh.unit.count, instanceCount: cubes.count)
        }
        if !spheres.isEmpty, let sphereVertices, !sphereInstanceBuffers.isEmpty {
            let sphereBuffer = sphereInstanceBuffers[frame % sphereInstanceBuffers.count]
            sphereBuffer.contents().copyMemory(from: spheres, byteCount: spheres.count * MemoryLayout<CubeInstance>.stride)
            // No culling: the depth test keeps the near half, whichever way the mesh winds.
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(sphereVertices, offset: 0, index: 0)
            encoder.setVertexBuffer(sphereBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: SphereMesh.unit.count, instanceCount: spheres.count)
        }
        if !diamonds.isEmpty, let diamondVertices, !diamondInstanceBuffers.isEmpty {
            let diamondBuffer = diamondInstanceBuffers[frame % diamondInstanceBuffers.count]
            diamondBuffer.contents().copyMemory(from: diamonds, byteCount: diamonds.count * MemoryLayout<CubeInstance>.stride)
            encoder.setCullMode(.back)
            encoder.setVertexBuffer(diamondVertices, offset: 0, index: 0)
            encoder.setVertexBuffer(diamondBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: DiamondMesh.unit.count, instanceCount: diamonds.count)
        }
        if !blocks.isEmpty, let translucentDepth, let blockPipeline, !blockInstanceBuffers.isEmpty {
            let blockBuffer = blockInstanceBuffers[frame % blockInstanceBuffers.count]
            blockBuffer.contents().copyMemory(from: blocks, byteCount: blocks.count * MemoryLayout<CubeInstance>.stride)
            // Every face, the far ones through the near.
            encoder.setRenderPipelineState(blockPipeline)
            encoder.setCullMode(.none)
            encoder.setDepthStencilState(translucentDepth)
            encoder.setVertexBuffer(cubeVertices, offset: 0, index: 0)
            encoder.setVertexBuffer(blockBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: CubeMesh.unit.count, instanceCount: blocks.count)
        }
        if !hexes.isEmpty, let hexVertices, let translucentDepth, let hexPipeline, !hexInstanceBuffers.isEmpty {
            let hexBuffer = hexInstanceBuffers[frame % hexInstanceBuffers.count]
            hexBuffer.contents().copyMemory(from: hexes, byteCount: hexes.count * MemoryLayout<CubeInstance>.stride)
            // Both sides of every tile, the far half through the gaps of the near.
            encoder.setRenderPipelineState(hexPipeline)
            encoder.setCullMode(.none)
            encoder.setDepthStencilState(translucentDepth)
            encoder.setVertexBuffer(hexVertices, offset: 0, index: 0)
            encoder.setVertexBuffer(hexBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: HexSphere.tile.count, instanceCount: hexes.count)
        }
        if !glass.isEmpty, let glassVertices, let translucentDepth, let hexPipeline, !glassInstanceBuffers.isEmpty {
            let glassBuffer = glassInstanceBuffers[frame % glassInstanceBuffers.count]
            glassBuffer.contents().copyMemory(from: glass, byteCount: glass.count * MemoryLayout<CubeInstance>.stride)
            encoder.setRenderPipelineState(hexPipeline)
            encoder.setCullMode(.none)
            encoder.setDepthStencilState(translucentDepth)
            encoder.setVertexBuffer(glassVertices, offset: 0, index: 0)
            encoder.setVertexBuffer(glassBuffer, offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: ShardMesh.unit.count, instanceCount: glass.count)
        }
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
        var uniforms = GlowUniforms(texelSize: SIMD2(1 / Float(glow.width), 1 / Float(glow.height)), direction: .zero,
                                    threshold: GlowSettings.threshold, bodyThreshold: GlowSettings.bodyThreshold,
                                    softness: GlowSettings.softness, intensity: GlowSettings.intensity, tint: GlowSettings.tint)
        uniforms.hood = SIMD4(scene.hoodGlowShare, 0, 0, 0)
        return uniforms
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

    /// A picture off the GPU: copied to a texture the CPU can read, read once the copy's done, and
    /// handed over on the main thread.
    /// Textures of one size read back as BGRA bytes once the commands are done.
    private func readBack(_ textures: [MTLTexture], with commands: MTLCommandBuffer, then: @escaping @MainActor ([[UInt8]], Int, Int) -> Void) {
        guard let first = textures.first, let blit = commands.makeBlitCommandEncoder() else { return }
        let width = first.width, height = first.height
        let readable = textures.compactMap { texture -> MTLTexture? in
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead]
            guard let copy = device.makeTexture(descriptor: descriptor) else { return nil }
            blit.copy(from: texture, to: copy)
            return copy
        }
        blit.endEncoding()
        guard readable.count == textures.count else { return }
        commands.addCompletedHandler { _ in
            let pictures = readable.map { texture in
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
                return bytes
            }
            DispatchQueue.main.async { then(pictures, width, height) }
        }
    }

    private func keep(_ texture: MTLTexture, with commands: MTLCommandBuffer, then: @escaping @MainActor (CGImage) -> Void) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width, height: texture.height, mipmapped: false)
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]
        guard let readable = device.makeTexture(descriptor: descriptor), let blit = commands.makeBlitCommandEncoder() else { return }
        blit.copy(from: texture, to: readable)
        blit.endEncoding()
        commands.addCompletedHandler { _ in
            let width = readable.width, height = readable.height, rowBytes = width * 4
            var bytes = [UInt8](repeating: 0, count: rowBytes * height)
            readable.getBytes(&bytes, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: rowBytes,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
            DispatchQueue.main.async { then(image) }
        }
    }

    /// A panel's cut: the frame's middle, as wide or as tall as the frame, at the panel's shape,
    /// into the panel's picture.
    private func capture(_ commands: MTLCommandBuffer, from frame: MTLTexture, into panel: MTLTexture, panel index: Int, screen: CGSize) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = panel
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        let share = MangaPage.cropShare(index, screen: screen)
        let left = Float((1 - share.width) / 2), top = Float((1 - share.height) / 2)
        let right = left + Float(share.width), bottom = top + Float(share.height)
        var corners: [SIMD4<Float>] = [
            SIMD4(-1, 1, left, top), SIMD4(1, 1, right, top), SIMD4(-1, -1, left, bottom), SIMD4(1, -1, right, bottom),
        ]
        encoder.setRenderPipelineState(mangaPipeline)
        encoder.setVertexBytes(&corners, length: MemoryLayout<SIMD4<Float>>.stride * corners.count, index: 0)
        encoder.setFragmentTexture(frame, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    /// The page on the screen: its ground, and the first `shown` panels, each its picture.
    private func layPage(_ commands: MTLCommandBuffer, descriptor: MTLRenderPassDescriptor, shown: Int, screen: CGSize) {
        let ground = MangaPage.ground
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: Double((ground >> 16) & 0xFF) / 255, green: Double((ground >> 8) & 0xFF) / 255,
                                                                  blue: Double(ground & 0xFF) / 255, alpha: 1)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(mangaPipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)
        let fit = MangaPage.fit(in: screen)
        for panel in 0..<min(shown, panelTextures.count) {
            let points = MangaPage.panels[panel]
            let box = MangaPage.bounds(panel)
            func vertex(_ point: CGPoint) -> SIMD4<Float> {
                let x = (fit.origin.x + point.x * fit.scale) / screen.width * 2 - 1
                let y = 1 - (fit.origin.y + point.y * fit.scale) / screen.height * 2
                return SIMD4(Float(x), Float(y), Float((point.x - box.minX) / box.width), Float((point.y - box.minY) / box.height))
            }
            // A fan from the first corner: every panel is convex.
            var triangles: [SIMD4<Float>] = []
            for corner in 1..<(points.count - 1) {
                triangles += [vertex(points[0]), vertex(points[corner]), vertex(points[corner + 1])]
            }
            encoder.setVertexBytes(&triangles, length: MemoryLayout<SIMD4<Float>>.stride * triangles.count, index: 0)
            encoder.setFragmentTexture(panelTextures[panel], index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: triangles.count)
        }
        encoder.endEncoding()
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
