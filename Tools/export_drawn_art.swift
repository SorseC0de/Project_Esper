// The body of `export_drawn_art.py`'s program: compiled after the types it cuts from the app, so
// it isn't a file of its own to build. Arguments: Glow.metal, the asset catalog, the output folder,
// output pixels an art pixel.

import ImageIO
import Metal
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
let shaderPath = arguments[1], assets = arguments[2], output = arguments[3]
let scale = Int(arguments[4]) ?? 4

func channels(_ rgb: RGB) -> SIMD4<Float> {
    SIMD4<Float>(Float((rgb >> 16) & 0xFF) / 255, Float((rgb >> 8) & 0xFF) / 255, Float(rgb & 0xFF) / 255, 1)
}

// MARK: Metal, as MetalGameView sets the cubes up

let device = MTLCreateSystemDefaultDevice()!
let library = try! device.makeLibrary(source: String(contentsOfFile: shaderPath, encoding: .utf8), options: nil)
let queue = device.makeCommandQueue()!

/// The cubes' pipeline, or the hexagons' (added on as light) with `additive`.
func pipeline(additive: Bool) -> MTLRenderPipelineState {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "cube_vertex")
    descriptor.fragmentFunction = library.makeFunction(name: "cube_fragment")
    descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    descriptor.colorAttachments[0].isBlendingEnabled = true
    descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
    descriptor.colorAttachments[0].destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = additive ? .one : .oneMinusSourceAlpha
    descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
    descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
    return try! device.makeRenderPipelineState(descriptor: descriptor)
}
let cubePipeline = pipeline(additive: false)
let hexPipeline = pipeline(additive: true)
let depthDescriptor = MTLDepthStencilDescriptor()
depthDescriptor.depthCompareFunction = .less
depthDescriptor.isDepthWriteEnabled = true
let cubeDepth = device.makeDepthStencilState(descriptor: depthDescriptor)!
depthDescriptor.isDepthWriteEnabled = false
let translucentDepth = device.makeDepthStencilState(descriptor: depthDescriptor)!

/// RGBA, straight, top row first.
struct Picture {
    var width: Int, height: Int
    var pixels: [UInt8]
}

/// `instances` drawn over nothing, `origin` (art pixels) at the picture's bottom left, `size` art pixels
/// across and up: the hexagon mesh added on as light, or the unit cube as the net's strokes are.
/// Light comes back as alpha its brightest channel, its colour that far up; the cubes as drawn.
func draw(_ instances: [CubeInstance], hexagons: Bool, origin: SIMD2<Float>, size: SIMD2<Int>) -> Picture {
    let width = size.x * scale, height = size.y * scale
    let colourDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    colourDescriptor.usage = [.renderTarget, .shaderRead]
    colourDescriptor.storageMode = .managed
    let target = device.makeTexture(descriptor: colourDescriptor)!
    let depthTexture = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float_stencil8, width: width, height: height, mipmapped: false)
    depthTexture.usage = .renderTarget
    depthTexture.storageMode = .private
    let depth = device.makeTexture(descriptor: depthTexture)!
    // Nothing in front: no body or rim for anything behind to keep out of.
    let coverDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    coverDescriptor.usage = [.shaderRead, .renderTarget]
    let cover = device.makeTexture(descriptor: coverDescriptor)!

    let commands = queue.makeCommandBuffer()!
    let clearCover = MTLRenderPassDescriptor()
    clearCover.colorAttachments[0].texture = cover
    clearCover.colorAttachments[0].loadAction = .clear
    clearCover.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    clearCover.colorAttachments[0].storeAction = .store
    commands.makeRenderCommandEncoder(descriptor: clearCover)!.endEncoding()

    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    pass.colorAttachments[0].storeAction = .store
    pass.depthAttachment.texture = depth
    pass.depthAttachment.loadAction = .clear
    pass.depthAttachment.clearDepth = 1
    pass.depthAttachment.storeAction = .dontCare
    pass.stencilAttachment.texture = depth
    pass.stencilAttachment.loadAction = .dontCare
    pass.stencilAttachment.storeAction = .dontCare
    let encoder = commands.makeRenderCommandEncoder(descriptor: pass)!
    // The game's orthographic camera, unturned, on this picture's middle.
    let viewWidth = Float(size.x), viewHeight = Float(size.y)
    let middle = origin + SIMD2<Float>(viewWidth, viewHeight) / 2
    let projection = simd_float4x4(columns: (
        SIMD4<Float>(2 / viewWidth, 0, 0, 0),
        SIMD4<Float>(0, 2 / viewHeight, 0, 0),
        SIMD4<Float>(0, 0, -0.001, 0),
        SIMD4<Float>(-2 * middle.x / viewWidth, -2 * middle.y / viewHeight, 0.5, 1)))
    var uniforms = CubeUniforms(viewProjection: projection, light: SIMD4<Float>(-0.4, 0.7, 0.6, 0))
    let mesh = hexagons ? HexSphere.tile : CubeMesh.unit
    if !instances.isEmpty {
        let vertices = device.makeBuffer(bytes: mesh, length: mesh.count * MemoryLayout<CubeVertex>.stride)!
        let buffer = device.makeBuffer(bytes: instances, length: instances.count * MemoryLayout<CubeInstance>.stride)!
        encoder.setRenderPipelineState(hexagons ? hexPipeline : cubePipeline)
        encoder.setDepthStencilState(hexagons ? translucentDepth : cubeDepth)
        encoder.setCullMode(hexagons ? .none : .back)
        encoder.setVertexBuffer(vertices, offset: 0, index: 0)
        encoder.setVertexBuffer(buffer, offset: 0, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<CubeUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CubeUniforms>.stride, index: 2)
        encoder.setFragmentTexture(cover, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.count, instanceCount: instances.count)
    }
    encoder.endEncoding()
    let blit = commands.makeBlitCommandEncoder()!
    blit.synchronize(resource: target)
    blit.endEncoding()
    commands.commit()
    commands.waitUntilCompleted()

    var bgra = [UInt8](repeating: 0, count: width * height * 4)
    target.getBytes(&bgra, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    for pixel in 0..<(width * height) {
        let at = pixel * 4
        let b = Double(bgra[at]), g = Double(bgra[at + 1]), r = Double(bgra[at + 2])
        if hexagons {
            let alpha = max(r, g, b)
            guard alpha > 0 else { continue }
            rgba[at] = UInt8(min(r / alpha * 255, 255).rounded())
            rgba[at + 1] = UInt8(min(g / alpha * 255, 255).rounded())
            rgba[at + 2] = UInt8(min(b / alpha * 255, 255).rounded())
            rgba[at + 3] = UInt8(alpha)
        } else {
            let alpha = Double(bgra[at + 3])
            guard alpha > 0 else { continue }
            rgba[at] = UInt8(min(r / alpha * 255, 255).rounded())
            rgba[at + 1] = UInt8(min(g / alpha * 255, 255).rounded())
            rgba[at + 2] = UInt8(min(b / alpha * 255, 255).rounded())
            rgba[at + 3] = UInt8(alpha)
        }
    }
    return Picture(width: width, height: height, pixels: rgba)
}

// MARK: Pictures

func load(_ name: String) -> Picture {
    let url = URL(fileURLWithPath: "\(assets)/\(name).imageset/\(name).png")
    let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    // Straight again (the art's alpha is all or nothing, so nothing's lost).
    for pixel in 0..<(image.width * image.height) where pixels[pixel * 4 + 3] > 0 && pixels[pixel * 4 + 3] < 255 {
        let alpha = Double(pixels[pixel * 4 + 3])
        for channel in 0..<3 { pixels[pixel * 4 + channel] = UInt8(min(Double(pixels[pixel * 4 + channel]) / alpha * 255, 255).rounded()) }
    }
    return Picture(width: image.width, height: image.height, pixels: pixels)
}

/// `top` over `bottom` at (x, y) from its top left, output pixels; `top` blown up `times` a pixel.
func lay(_ top: Picture, over bottom: inout Picture, x: Int, y: Int, times: Int = 1) {
    for row in 0..<(top.height * times) {
        for column in 0..<(top.width * times) {
            let toX = x + column, toY = y + row
            guard toX >= 0, toY >= 0, toX < bottom.width, toY < bottom.height else { continue }
            let from = ((row / times) * top.width + column / times) * 4
            let to = (toY * bottom.width + toX) * 4
            let a = Double(top.pixels[from + 3]) / 255
            guard a > 0 else { continue }
            let under = Double(bottom.pixels[to + 3]) / 255
            let out = a + under * (1 - a)
            for channel in 0..<3 {
                let mixed = (Double(top.pixels[from + channel]) * a + Double(bottom.pixels[to + channel]) * under * (1 - a)) / out
                bottom.pixels[to + channel] = UInt8(min(mixed, 255).rounded())
            }
            bottom.pixels[to + 3] = UInt8((out * 255).rounded())
        }
    }
}

func save(_ picture: Picture, to path: String) {
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    let provider = CGDataProvider(data: Data(picture.pixels) as CFData)!
    let image = CGImage(width: picture.width, height: picture.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: picture.width * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(path) (\(picture.width)×\(picture.height))")
}

// MARK: The barrier shattering

/// As GameScene draws it: its radius the body's posture radius, the middle unfaded with no body
/// in it, unturned, no hit on it, the shatter from the same turn.
let barrierRadius: Float = 24
let shatterSeed: UInt32 = 1
let columns = 10

for energy in EnergyColour.allCases {
    let look = energy.look
    let colour = channels(look.glow), flash = channels(look.bright)
    let accents = energy.mixedBarrier ? ZoneTuning.colours.map(channels) : []
    var frames: [[CubeInstance]] = [BarrierLook.instances(centre: .zero, radius: barrierRadius, tileRadius: barrierRadius, tileShare: 1, spin: 0,
                                                          colour: colour, flash: flash, time: 0, hits: [], wobble: 0, wobbleStep: 0, accents: accents)]
    var shatter = BarrierShatter(centre: .zero, radius: barrierRadius, tileRadius: barrierRadius, spin: 0, colour: colour, flash: flash,
                                 seed: shatterSeed, accents: accents)
    while !shatter.finished {
        let instances = shatter.instances()
        if !instances.isEmpty { frames.append(instances) }
        shatter.age += 1
    }
    // One frame size for all: every tile's corners over the whole of it, a pixel spare.
    var low = SIMD2<Float>(repeating: .infinity), high = SIMD2<Float>(repeating: -.infinity)
    for instance in frames.joined() {
        for vertex in HexSphere.tile {
            let point = instance.model * vertex.position
            low = simd_min(low, SIMD2<Float>(point.x, point.y))
            high = simd_max(high, SIMD2<Float>(point.x, point.y))
        }
    }
    // Square, centred on the barrier, whole pixels.
    let reach = (max(abs(low.x), abs(low.y), high.x, high.y) + 1).rounded(.up)
    let side = Int(reach) * 2
    let origin = SIMD2<Float>(-reach, -reach)
    var pictures = frames.map { draw($0, hexagons: true, origin: origin, size: SIMD2(side, side)) }
    // The fade's last frames, faded past a step of alpha, are nothing: left off.
    while let last = pictures.last, !stride(from: 3, to: last.pixels.count, by: 4).contains(where: { last.pixels[$0] > 0 }) { pictures.removeLast() }
    let rows = (pictures.count + columns - 1) / columns
    var sheet = Picture(width: side * scale * columns, height: side * scale * rows, pixels: [])
    sheet.pixels = [UInt8](repeating: 0, count: sheet.width * sheet.height * 4)
    for (index, frame) in pictures.enumerated() {
        lay(frame, over: &sheet, x: (index % columns) * side * scale, y: (index / columns) * side * scale)
    }
    save(sheet, to: "\(output)/breaker_barrier_shatter/breaker_barrier_shatter_\(energy.rawValue).png")
    print("  \(pictures.count) frames, \(side * scale)×\(side * scale) each, \(columns) across")
}

// MARK: The front-facing hoop

/// The Tutorial hub's, as TutorialHubArt stands it: board, net, the rim's back, its front, on the
/// 48 by 48 pictures' rim point; the net white (a shared hoop's) hung `NetTuning.frontOffsetY`
/// under it, at rest, and kept behind both rim layers as the game keeps it.
let rimOnPicture = SIMD2<Float>(24, 11)
let net = CylinderNet.instances(cache: CylinderNet.Cache(), top: CGPoint(x: CGFloat(rimOnPicture.x), y: CGFloat(rimOnPicture.y) + NetTuning.frontOffsetY),
                                turn: 0, mirrored: false, sways: [], spreads: [], flare: 0, swish: 0, colour: SIMD4<Float>(1, 1, 1, 1), front: true)
var netLow: Float = 0
for instance in net {
    for vertex in CubeMesh.unit { netLow = min(netLow, (instance.model * vertex.position).y) }
}
// The picture's 48 across, and down past its bottom as far as the net hangs, a pixel spare.
let below = max(Int((-netLow + 1).rounded(.up)), 0)
let hoopSize = SIMD2<Int>(48, 48 + below)
let netPicture = draw(net, hexagons: false, origin: SIMD2<Float>(0, -Float(below)), size: hoopSize)
var hoop = Picture(width: hoopSize.x * scale, height: hoopSize.y * scale, pixels: [UInt8](repeating: 0, count: hoopSize.x * hoopSize.y * scale * scale * 4))
lay(load("HoopFrontBoard"), over: &hoop, x: 0, y: 0, times: scale)
lay(netPicture, over: &hoop, x: 0, y: 0)
lay(load("HoopFrontBackRim"), over: &hoop, x: 0, y: 0, times: scale)
lay(load("HoopFrontFrontRim"), over: &hoop, x: 0, y: 0, times: scale)
save(hoop, to: "\(output)/hoop_front/hoop_front.png")
