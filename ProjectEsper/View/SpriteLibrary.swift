import CoreGraphics
import EsperSim
import SpriteKit

/// Every frame in the atlas, looked up by the importer's names, drawn as pixels. Player
/// frames come out in that player's look and the ball in its colour, recoloured once each
/// and kept, and the library remembers where the ball and the head sit in each frame.
final class SpriteLibrary {
    static let pixelsPerUnit = 1.6
    /// The sheets' white is the ball where it's the biggest blob of white in the frame and
    /// at least this many pixels; the rest of the white is energy. The importer agrees.
    static let ballMinPixels = 12

    private let atlas = SKTextureAtlas(named: "Sprites")
    private var cache: [String: SKTexture] = [:]
    /// Where the glowing parts sit in each player frame, in art pixels from the feet.
    private var landmarks: [String: [BodyPart: CGPoint]] = [:]
    /// The two players' looks, then the ice look frozen bodies and ice clones are drawn in,
    /// asked for as the player `icePlayer`.
    private var looks = Look.byPlayer + [Look.ice] + Look.byPlayer.map(\.transformed)
    static let icePlayer = Look.byPlayer.count
    /// A player's energy form, asked for as a player of its own.
    static func transformedPlayer(_ player: Int) -> Int { icePlayer + 1 + player }

    func look(for player: Int) -> Look {
        looks[min(player, looks.count - 1)]
    }

    /// Changes what a player is drawn in; everything in their old look is dropped and rebuilt
    /// in the new one off the main thread.
    func setLook(_ look: Look, for player: Int) {
        guard look != looks[player] else { return }
        looks[player] = look
        let energyForm = SpriteLibrary.transformedPlayer(player)
        looks[energyForm] = look.transformed
        cache = cache.filter { !$0.key.hasPrefix("p\(player)_") && !$0.key.hasPrefix("p\(energyForm)_") }
        rewarm(player: player)
        rewarm(player: energyForm)
    }

    /// Every player's frames dropped and rebuilt, for a change to how all looks are drawn.
    func redrawPlayers() {
        for player in looks.indices {
            cache = cache.filter { !$0.key.hasPrefix("p\(player)_") }
            rewarm(player: player)
        }
    }

    /// The toned sheets beyond the energy effects that a player's particles use.
    static let tonedParticleSheets = ["lightning_particle", "lightning_particle2"]
    private var rewarmGeneration: [Int: Int] = [:]
    private let rewarmQueue = DispatchQueue(label: "SpriteLibrary.rewarm", qos: .userInitiated)

    /// Everything drawn in a player's look rebuilt off the main thread after their look
    /// changes, then kept and sent to the GPU, so no frame, head, energy or toned effect is
    /// first made mid-match. Anything asked for before it lands is made as it always was;
    /// a newer change supersedes it.
    private func rewarm(player: Int) {
        let look = look(for: player)
        let generation = (rewarmGeneration[player] ?? 0) + 1
        rewarmGeneration[player] = generation
        var frameJobs: [(key: String, frame: AnimationFrame, source: SKTexture, ballAsEnergy: Bool)] = []
        for animation in Animation.allCases {
            for index in 0..<animation.frameCount {
                let frame = AnimationFrame(animation, index)
                let source = atlas.textureNamed("\(animation.rawValue)_\(index)")
                let key = "p\(player)_\(animation.rawValue)_\(index)"
                frameJobs.append((key, frame, source, false))
                if animation.holdsBall { frameJobs.append((key + "_whole", frame, source, true)) }
            }
        }
        var tonedJobs: [(key: String, source: SKTexture, capped: Bool)] = []
        let tonedNames = EnergyEffect.allCases.map(\.name) + Effect.inEnergyColour.map(\.name) + SpriteLibrary.tonedParticleSheets
        for name in tonedNames {
            for index in 0..<(EffectSheets.frames[name] ?? 0) {
                tonedJobs.append(("p\(player)_fx_\(name)_\(index)", texture(name, index), Effect.sparkNames.contains(name)))
            }
        }
        var silhouetteJobs: [(key: String, source: SKTexture)] = []
        for index in 0..<Effect.fireWallSpark.frameCount {
            silhouetteJobs.append(("p\(player)_sil_\(Effect.fireWallSpark.name)_\(index)", texture(Effect.fireWallSpark.name, index)))
        }
        rewarmQueue.async { [weak self] in
            guard let self else { return }
            var built: [String: SKTexture] = [:]
            var builtLandmarks: [String: [BodyPart: CGPoint]] = [:]
            for job in frameJobs {
                let made = makeFrame(job.frame, source: job.source, look: look, ballAsEnergy: job.ballAsEnergy)
                for (suffix, texture) in made.textures { built[job.key + suffix] = texture }
                builtLandmarks[job.key] = made.landmarks
            }
            for job in tonedJobs { built[job.key] = makeToned(job.source, look: look, capped: job.capped) }
            for job in silhouetteJobs { built[job.key] = makeSilhouette(job.source, look: look) }
            DispatchQueue.main.async {
                guard self.rewarmGeneration[player] == generation, self.look(for: player) == look else { return }
                for (key, texture) in built where self.cache[key] == nil { self.cache[key] = texture }
                for (key, marks) in builtLandmarks where self.landmarks[key] == nil { self.landmarks[key] = marks }
                for job in frameJobs { self.pairGlowMask(job.key) }
                SKTexture.preload(Array(built.values)) {}
            }
        }
    }

    /// A non-player frame, from the atlas or, like the ball, from the catalog's root.
    func texture(_ name: String, _ frame: Int) -> SKTexture {
        let key = "\(name)_\(frame)"
        if let texture = cache[key] { return texture }
        let texture = atlas.textureNames.contains(key) ? atlas.textureNamed(key) : SKTexture(imageNamed: key)
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    /// The ball's three frames, cut from the 24x8 picture in the catalog's root, and the
    /// frozen ball's from its own.
    static let basketballFrameCount = 3
    private(set) lazy var basketballFrames: [SKTexture] = SpriteLibrary.cutBall("Basketball")
    private(set) lazy var basketballIceFrames: [SKTexture] = SpriteLibrary.cutBall("BasketballIce")

    private static func cutBall(_ name: String) -> [SKTexture] {
        let sheet = SKTexture(imageNamed: name)
        sheet.filteringMode = .nearest
        let share = 1 / CGFloat(basketballFrameCount)
        return (0..<basketballFrameCount).map { index in
            let frame = SKTexture(rect: CGRect(x: CGFloat(index) * share, y: 0, width: share, height: 1), in: sheet)
            frame.filteringMode = .nearest
            return frame
        }
    }

    /// A player frame in that player's look, without its head or its energy.
    /// With `ballAsEnergy`, a sheet that draws the ball has its whites taken as energy,
    /// ball and all, for a throw made with nothing in hand.
    func texture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false) -> SKTexture {
        let key = "p\(player)_\(frame.animation.rawValue)_\(frame.frame)" + (ballAsEnergy ? "_whole" : "")
        if let texture = cache[key] { return texture }
        let made = makeFrame(frame, source: atlas.textureNamed("\(frame.animation.rawValue)_\(frame.frame)"),
                             look: look(for: player), ballAsEnergy: ballAsEnergy)
        for (suffix, texture) in made.textures { cache[key + suffix] = texture }
        landmarks[key] = made.landmarks
        pairGlowMask(key)
        return cache[key]!
    }

    /// A player frame recoloured in a look: the body under "", and "_head" and "_energy"
    /// where the frame has them; and where its glowing parts sit. Touches nothing kept, so
    /// it can be made off the main thread.
    private func makeFrame(_ frame: AnimationFrame, source: SKTexture, look: Look, ballAsEnergy: Bool) -> (textures: [String: SKTexture], landmarks: [BodyPart: CGPoint]) {
        let result = recolour(source, look: look, holdsBall: frame.animation.holdsBall && !ballAsEnergy, detach: true)
        var textures = ["": result.texture]
        if let head = result.head { textures["_head"] = head }
        if let energy = result.energy { textures["_energy"] = energy }
        if let outline = result.outline { textures["_outline"] = outline }
        if let glowMask = result.glowMask { textures["_glowmask"] = glowMask }
        for texture in textures.values { texture.filteringMode = .nearest }
        let size = frame.animation.pixelSize
        let landmarks = result.centres.mapValues { centre in
            CGPoint(x: centre.x - size / 2, y: size - centre.y - frame.animation.feetFromBottom)
        }
        return (textures, landmarks)
    }

    /// Each body texture's glow mask, where it has one, looked up by the texture a node shows.
    private let glowMasks = NSMapTable<SKTexture, SKTexture>.weakToStrongObjects()
    private func pairGlowMask(_ key: String) {
        if let body = cache[key], let mask = cache[key + "_glowmask"] { glowMasks.setObject(mask, forKey: body) }
    }

    /// What the glow's mask draws for a body texture: its glow mask if it has glowing
    /// parts, else itself.
    func glowMask(for body: SKTexture) -> SKTexture { glowMasks.object(forKey: body) ?? body }

    /// The head alone from a player frame, on the same canvas as the body, if the frame has one.
    func headTexture(_ frame: AnimationFrame, player: Int) -> SKTexture? {
        _ = texture(frame, player: player)
        return cache["p\(player)_\(frame.animation.rawValue)_\(frame.frame)_head"]
    }

    /// The energy alone from a player frame, on the same canvas as the body: the slash's
    /// blade, the skid's puffs, a release's streaks. In grey, for the view's energy tone
    /// (`Look.energyTone` in a shader) in the look's colour or the zone's. Nil when the
    /// frame has none.
    func energyTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false) -> SKTexture? {
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy)
        return cache["p\(player)_\(frame.animation.rawValue)_\(frame.frame)" + (ballAsEnergy ? "_whole" : "") + "_energy"]
    }

    /// The line round a player frame alone, in white, on the same canvas as the body, for
    /// the view to colour. Nil when the frame has none.
    func outlineTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false) -> SKTexture? {
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy)
        return cache["p\(player)_\(frame.animation.rawValue)_\(frame.frame)" + (ballAsEnergy ? "_whole" : "") + "_outline"]
    }

    /// A strip's frame as a silhouette in the player's energy: every painted pixel white,
    /// its alpha kept, then toned as white energy is.
    func silhouetteTexture(_ name: String, _ frame: Int, player: Int) -> SKTexture {
        let key = "p\(player)_sil_\(name)_\(frame)"
        if let texture = cache[key] { return texture }
        let result = makeSilhouette(texture(name, frame), look: look(for: player))
        cache[key] = result
        return result
    }

    /// A frame as a silhouette in a look's white energy; touches nothing kept.
    private func makeSilhouette(_ source: SKTexture, look: Look) -> SKTexture {
        let image = source.cgImage()
        let width = image.width, height = image.height
        guard let (context, pixels) = makeCanvas(width: width, height: height) else { return source }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let tone = look.sparkTone(luminance: 1)
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let alpha = Int(pixels[index + 3])
            guard alpha > 0 else { continue }
            pixels[index] = UInt8(Int((tone >> 16) & 0xFF) * alpha / 255)
            pixels[index + 1] = UInt8(Int((tone >> 8) & 0xFF) * alpha / 255)
            pixels[index + 2] = UInt8(Int(tone & 0xFF) * alpha / 255)
        }
        guard let toned = context.makeImage() else { return source }
        let result = SKTexture(cgImage: toned)
        result.filteringMode = .nearest
        return result
    }

    /// An effect frame in a player's energy colour: the sheet's greys through the look's
    /// tone ramp, its alpha kept.
    func effectTexture(_ name: String, _ frame: Int, player: Int) -> SKTexture {
        let key = "p\(player)_fx_\(name)_\(frame)"
        if let texture = cache[key] { return texture }
        let result = makeToned(texture(name, frame), look: look(for: player), capped: Effect.sparkNames.contains(name))
        cache[key] = result
        return result
    }

    /// A grey frame through a look's energy ramp, or with `capped` the sparks' ramp, which
    /// stops at the colour; touches nothing kept.
    private func makeToned(_ source: SKTexture, look: Look, capped: Bool = false) -> SKTexture {
        let image = source.cgImage()
        let width = image.width, height = image.height
        guard let (context, pixels) = makeCanvas(width: width, height: height) else { return source }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let alpha = Int(pixels[index + 3])
            guard alpha > 0 else { continue }
            // The canvas is premultiplied: the grey level is the colour over the alpha.
            let grey = (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / Double(alpha)
            let tone = capped ? look.sparkTone(luminance: min(grey, 1)) : look.energyTone(luminance: min(grey, 1))
            pixels[index] = UInt8(Int((tone >> 16) & 0xFF) * alpha / 255)
            pixels[index + 1] = UInt8(Int((tone >> 8) & 0xFF) * alpha / 255)
            pixels[index + 2] = UInt8(Int(tone & 0xFF) * alpha / 255)
        }
        guard let toned = context.makeImage() else { return source }
        let result = SKTexture(cgImage: toned)
        result.filteringMode = .nearest
        return result
    }

    /// Frost Tea's snowflake, from the catalog's root.
    var snowflake: SKTexture {
        if let texture = cache["Snowflake"] { return texture }
        let texture = SKTexture(imageNamed: "Snowflake")
        cache["Snowflake"] = texture
        return texture
    }

    /// A grey frame toned in the snowflake's two blues, dark to light, for Frost Tea.
    func iceTexture(_ name: String, _ frame: Int) -> SKTexture {
        let key = "ice_\(name)_\(frame)"
        if let texture = cache[key] { return texture }
        let source = texture(name, frame)
        let image = source.cgImage()
        let width = image.width, height = image.height
        guard let (context, pixels) = makeCanvas(width: width, height: height) else { return source }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let dark = (0x8F, 0xCE, 0xFA), light = (0xB5, 0xE6, 0xF8)
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let alpha = Int(pixels[index + 3])
            guard alpha > 0 else { continue }
            let grey = min(Double(pixels[index]) / Double(alpha), 1)
            func mix(_ a: Int, _ b: Int) -> UInt8 { UInt8(Int(Double(a) + Double(b - a) * grey) * alpha / 255) }
            pixels[index] = mix(dark.0, light.0)
            pixels[index + 1] = mix(dark.1, light.1)
            pixels[index + 2] = mix(dark.2, light.2)
        }
        guard let toned = context.makeImage() else { return source }
        let result = SKTexture(cgImage: toned)
        result.filteringMode = .nearest
        cache[key] = result
        return result
    }

    func effectFrames(_ effect: EnergyEffect, player: Int) -> [SKTexture] {
        (0..<effect.frameCount).map { effectTexture(effect.name, $0, player: player) }
    }

    func effectFrames(_ effect: Effect, player: Int) -> [SKTexture] {
        (0..<effect.frameCount).map { effectTexture(effect.name, $0, player: player) }
    }

    /// Where a glowing part is drawn in a player frame, from the feet in art pixels, if it's there.
    func landmark(_ part: BodyPart, in frame: AnimationFrame, player: Int) -> CGPoint? {
        _ = texture(frame, player: player)
        return landmarks["p\(player)_\(frame.animation.rawValue)_\(frame.frame)"]?[part]
    }

    func frames(_ name: String, count: Int) -> [SKTexture] {
        (0..<count).map { texture(name, $0) }
    }

    /// Where the feet sit in the sprite, as an anchor.
    func anchor(for animation: Animation) -> CGPoint {
        CGPoint(x: 0.5, y: animation.feetFromBottom / animation.pixelSize)
    }

    /// Units to whole screen pixels.
    static func point(_ v: Vec2) -> CGPoint {
        CGPoint(x: (v.x * pixelsPerUnit).rounded(), y: (v.y * pixelsPerUnit).rounded())
    }

    // MARK: Recolouring

    /// The head's centre in a player frame as an anchor on its canvas, for scaling the
    /// head about itself.
    func headAnchor(_ frame: AnimationFrame, player: Int) -> CGPoint? {
        guard let head = landmark(.head, in: frame, player: player) else { return nil }
        let size = frame.animation.pixelSize
        return CGPoint(x: (head.x + size / 2) / size, y: (head.y + frame.animation.feetFromBottom) / size)
    }

    /// Everything made so far.
    var allTextures: [SKTexture] { Array(cache.values) }

    /// Builds every frame of every player up front and sends them to the GPU, so nothing
    /// is made mid-draw.
    func warmUp(players: Int, completion: @escaping () -> Void) {
        // The ice look's frames as well, and each player's energy form, so a freeze or a
        // change never makes them mid-match.
        for drawn in [SpriteLibrary.icePlayer] + (0..<players).map(SpriteLibrary.transformedPlayer) {
            for animation in Animation.allCases {
                for frame in 0..<animation.frameCount {
                    _ = texture(AnimationFrame(animation, frame), player: drawn)
                }
            }
        }
        for player in 0..<players {
            for animation in Animation.allCases {
                for frame in 0..<animation.frameCount {
                    _ = texture(AnimationFrame(animation, frame), player: player)
                }
            }
            for effect in EnergyEffect.allCases {
                _ = effectFrames(effect, player: player)
            }
            for effect in Effect.inEnergyColour {
                _ = effectFrames(effect, player: player)
            }
        }
        _ = texture("ball", 0)
        _ = softGlow(diameter: 32)
        _ = softGlow(diameter: 8)
        _ = feather()
        _ = flatSquare(size: 16, alpha: 1)
        _ = flatSquare(size: 4, alpha: 1)
        _ = symbol("chevron.down", pointSize: 14)
        _ = symbol("chevron.down", pointSize: 10)
        _ = snowflake
        for frame in 0..<(EffectSheets.frames["ice_jumpspark"] ?? 0) { _ = iceTexture("ice_jumpspark", frame) }
        // The whole atlas too, every page, so nothing first drawn mid-match loads one.
        let group = DispatchGroup()
        group.enter()
        SKTexture.preload(Array(cache.values)) { group.leave() }
        group.enter()
        SKTextureAtlas.preloadTextureAtlases([atlas]) { group.leave() }
        group.notify(queue: .main, execute: completion)
    }

    /// A clear canvas. The memory a context is given isn't promised to be clean, and a frame
    /// drawn over leftovers keeps them in its transparent area, so it's wiped first.
    private func makeCanvas(width: Int, height: Int) -> (CGContext, UnsafeMutablePointer<UInt8>)? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return (context, data.bindMemory(to: UInt8.self, capacity: width * height * 4))
    }

    /// A copy of the frame in the look: every part swapped to its colour, the stroked parts
    /// lined where they lie over the body, the silhouette lined round the outside, and the
    /// centre of each glowing part found. The ball is looked for only where the sheet
    /// `holdsBall`. With `detach`, the head and the energy come back as their own textures
    /// with no line, and the body is drawn and lined without them.
    private func recolour(_ texture: SKTexture, look: Look, holdsBall: Bool, detach: Bool) -> (texture: SKTexture, head: SKTexture?, energy: SKTexture?, outline: SKTexture?, glowMask: SKTexture?, centres: [BodyPart: CGPoint]) {
        let image = texture.cgImage()
        let width = image.width, height = image.height
        guard let (context, pixels) = makeCanvas(width: width, height: height) else { return (texture, nil, nil, nil, nil, [:]) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let count = width * height
        // The line's pixels, for `detach` to lift onto their own canvas; each energy pixel's
        // grey, for the view to tone in any colour.
        var lined = [Bool](repeating: false, count: count)
        var greys = [Double](repeating: 0, count: count)

        // Which part each pixel came from, before anything changes.
        var parts = [BodyPart?](repeating: nil, count: count)
        for pixel in 0..<count where pixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            let colour = RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])
            parts[pixel] = BodyPart.owning(colour)
        }
        markEnergy(&parts, holdsBall: holdsBall, width: width, height: height)

        // Each part to its colour; the energy to the tone of its own brightness.
        var sums: [BodyPart: (x: CGFloat, y: CGFloat, n: Int)] = [:]
        for pixel in 0..<count {
            guard let part = parts[pixel] else { continue }
            let index = pixel * 4
            // The glowing parts' middles, and the head's however it's drawn: where the head
            // and its particles go.
            // And the limbs' ends, where cubes come off them.
            if part.glows(human: look.human) || part == .head || [.frontLeg, .backLeg, .frontHand, .backHand].contains(part) {
                var sum = sums[part] ?? (0, 0, 0)
                sum.x += CGFloat(pixel % width) + 0.5
                sum.y += CGFloat(pixel / width) + 0.5
                sum.n += 1
                sums[part] = sum
            }
            if part.isEnergy {
                let grey = (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / 255
                greys[pixel] = grey
                paint(pixels, index, look.energyTone(luminance: grey))
            } else if let target = look.colours[part] {
                paint(pixels, index, target)
            }
        }

        // The head and the energy onto their own canvases, and off this one; the ball off
        // this one too, since it's drawn as its own sprite wherever the frame puts it.
        var head: SKTexture?
        var energy: SKTexture?
        if detach {
            let headCanvas = sums[.head] != nil && !look.human ? makeCanvas(width: width, height: height) : nil
            let energyCanvas = parts.contains { $0?.isEnergy == true } ? makeCanvas(width: width, height: height) : nil
            for pixel in 0..<count {
                // A human's head stays on the body.
                guard let part = parts[pixel], (part == .head && !look.human) || part == .ball || part.isEnergy else { continue }
                let index = pixel * 4
                if part == .head, let (_, headPixels) = headCanvas {
                    paint(headPixels, index, look.colours[.head] ?? look.glow)
                    headPixels[index + 3] = 255
                } else if part.isEnergy, let (_, energyPixels) = energyCanvas {
                    // In grey: the view tones it through the energy ramp in whatever colour.
                    let level = UInt8((greys[pixel] * 255).rounded())
                    energyPixels[index] = level
                    energyPixels[index + 1] = level
                    energyPixels[index + 2] = level
                    energyPixels[index + 3] = 255
                }
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
                pixels[index + 3] = 0
                parts[pixel] = nil
            }
            head = headCanvas?.0.makeImage().map { SKTexture(cgImage: $0) }
            energy = energyCanvas?.0.makeImage().map { SKTexture(cgImage: $0) }
        }

        func neighbours(_ pixel: Int, _ body: (Int) -> Bool) -> Bool {
            let x = pixel % width, y = pixel / width
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, ny >= 0, nx < width, ny < height, body(ny * width + nx) { return true }
                }
            }
            return false
        }

        // Stroked groups: the body pixels next to one take the line, so it keeps its shape. A
        // pixel already lined is neither lined again nor counted as the group's, so where two
        // groups meet there's one line, not two.
        for group in look.strokedGroups {
            let stroked = (0..<count).map { parts[$0].map(group.contains) == true && !lined[$0] }
            for pixel in 0..<count where parts[pixel] != nil && !stroked[pixel] && !lined[pixel] && neighbours(pixel, { stroked[$0] }) {
                paint(pixels, pixel * 4, look.outline)
                lined[pixel] = true
            }
        }

        // The outside line, grown a pixel at a time round the body. The glowing parts get
        // none: a clear pixel next to nothing but the ball stays clear.
        if look.outlineWidth > 0 {
            var body = (0..<count).map { pixels[$0 * 4 + 3] != 0 && parts[$0]?.glows(human: look.human) != true }
            for _ in 0..<look.outlineWidth {
                var grown: [Int] = []
                for pixel in 0..<count where pixels[pixel * 4 + 3] == 0 && neighbours(pixel, { body[$0] }) {
                    grown.append(pixel)
                }
                for pixel in grown {
                    paint(pixels, pixel * 4, look.outline)
                    pixels[pixel * 4 + 3] = 255
                    body[pixel] = true
                    lined[pixel] = true
                }
            }
        }

        // A human's head tops out in the energy: its top third, line and all, grades from the
        // look's colour at the crown down into the skin, leading into the particles off it.
        // The line there stays on the body in its grade rather than lifting off with the rest.
        // A human's energy-coloured parts glow; so does the crown's grade where it's mostly energy.
        var glowing = (0..<count).map { look.human && parts[$0].map(HumanLook.glowingParts.contains) == true }
        if look.human {
            let isHead = (0..<count).map { parts[$0] == .head }
            let crown = (0..<count).map { isHead[$0] || (lined[$0] && neighbours($0, { isHead[$0] })) }
            if let top = crown.firstIndex(of: true).map({ $0 / width }), let bottom = crown.lastIndex(of: true).map({ $0 / width }) {
                let band = Int((Double(bottom - top + 1) * HumanLook.headEnergyShare).rounded())
                for pixel in (top * width)..<(min(top + band, height) * width) where band > 0 && crown[pixel] {
                    let share = 1 - Double(pixel / width - top) / Double(band)
                    let index = pixel * 4
                    let under = RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])
                    paint(pixels, index, mix(under, look.glow, share))
                    lined[pixel] = false
                    if share >= 0.5 { glowing[pixel] = true }
                }
            }
        }

        // With `detach`, the line comes off onto its own canvas in white, so the view can
        // draw it in any colour, frame by frame.
        var outline: SKTexture?
        if detach, lined.contains(true), let (lineContext, linePixels) = makeCanvas(width: width, height: height) {
            for pixel in 0..<count where lined[pixel] {
                let index = pixel * 4
                linePixels[index] = 255
                linePixels[index + 1] = 255
                linePixels[index + 2] = 255
                linePixels[index + 3] = 255
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
                pixels[index + 3] = 0
            }
            outline = lineContext.makeImage().map { SKTexture(cgImage: $0) }
        }

        // The body as the glow's mask sees it, in white, the glowing pixels left out so they
        // take the glow's plain threshold rather than the body's.
        var glowMask: SKTexture?
        if detach, glowing.contains(true), let (maskContext, maskPixels) = makeCanvas(width: width, height: height) {
            for pixel in 0..<count where pixels[pixel * 4 + 3] != 0 && !glowing[pixel] {
                let index = pixel * 4
                maskPixels[index] = 255
                maskPixels[index + 1] = 255
                maskPixels[index + 2] = 255
                maskPixels[index + 3] = 255
            }
            glowMask = maskContext.makeImage().map { SKTexture(cgImage: $0) }
        }

        guard let recoloured = context.makeImage() else { return (texture, nil, nil, nil, nil, [:]) }
        let centres = sums.mapValues { CGPoint(x: $0.x / CGFloat($0.n), y: $0.y / CGFloat($0.n)) }
        return (SKTexture(cgImage: recoloured), head, energy, outline, glowMask, centres)
    }

    /// The sheets' white is the ball only on a sheet that holds it, and there only where
    /// it's the biggest 8-connected blob of white in the frame and big enough to be one;
    /// every other white pixel becomes energy: the skid's puffs, a release's streaks, the
    /// slide's speed lines.
    private func markEnergy(_ parts: inout [BodyPart?], holdsBall: Bool, width: Int, height: Int) {
        guard holdsBall else {
            for pixel in parts.indices where parts[pixel] == .ball { parts[pixel] = .energy }
            return
        }
        var label = [Int](repeating: 0, count: parts.count)
        var sizes = [0]
        for start in parts.indices where parts[start] == .ball && label[start] == 0 {
            let id = sizes.count
            sizes.append(0)
            label[start] = id
            var stack = [start]
            while let pixel = stack.popLast() {
                sizes[id] += 1
                let x = pixel % width, y = pixel / width
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let neighbour = ny * width + nx
                        if parts[neighbour] == .ball, label[neighbour] == 0 {
                            label[neighbour] = id
                            stack.append(neighbour)
                        }
                    }
                }
            }
        }
        guard sizes.count > 1, let biggest = sizes.indices.dropFirst().max(by: { sizes[$0] < sizes[$1] }) else { return }
        let ball = sizes[biggest] >= SpriteLibrary.ballMinPixels ? biggest : 0
        for pixel in parts.indices where parts[pixel] == .ball && label[pixel] != ball {
            parts[pixel] = .energy
        }
    }

    /// `from` moved `share` of the way to `to`, channel by channel.
    private func mix(_ from: RGB, _ to: RGB, _ share: Double) -> RGB {
        [16, 8, 0].reduce(RGB(0)) { result, shift in
            let a = Double((from >> RGB(shift)) & 0xFF), b = Double((to >> RGB(shift)) & 0xFF)
            return result | RGB((a + (b - a) * share).rounded()) << RGB(shift)
        }
    }

    private func paint(_ pixels: UnsafeMutablePointer<UInt8>, _ index: Int, _ colour: RGB) {
        pixels[index] = UInt8((colour >> 16) & 0xFF)
        pixels[index + 1] = UInt8((colour >> 8) & 0xFF)
        pixels[index + 2] = UInt8(colour & 0xFF)
    }

    // MARK: Generated textures

    /// A soft round white glow, bright in the middle and clear at the edge, for additive
    /// halos and particles; the node colours it.
    func softGlow(diameter: Int) -> SKTexture {
        let colour = SKColor.white
        let key = "glow_\(diameter)"
        if let texture = cache[key] { return texture }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter), format: format)
        let image = renderer.image { context in
            let colours = [colour.cgColor, colour.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1])!
            let centre = CGPoint(x: CGFloat(diameter) / 2, y: CGFloat(diameter) / 2)
            context.cgContext.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                                 endRadius: CGFloat(diameter) / 2, options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    /// A flat white square, `size` pixels, at `alpha`, for tiles the node colours.
    func flatSquare(size: Int, alpha: CGFloat) -> SKTexture {
        let key = "square_\(size)_\(alpha)"
        if let texture = cache[key] { return texture }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let image = renderer.image { context in
            SKColor(white: 1, alpha: alpha).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    /// A soft white feather: a petal, bright down the middle and clear at the edges.
    func feather() -> SKTexture {
        let key = "feather"
        if let texture = cache[key] { return texture }
        let width = 12, height = 36
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            let path = CGMutablePath()
            path.move(to: CGPoint(x: width / 2, y: 0))
            path.addQuadCurve(to: CGPoint(x: width / 2, y: height), control: CGPoint(x: width + 2, y: height / 2))
            path.addQuadCurve(to: CGPoint(x: width / 2, y: 0), control: CGPoint(x: -2, y: height / 2))
            cg.addPath(path)
            cg.clip()
            let colours = [SKColor.white.cgColor, SKColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1])!
            let centre = CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: CGFloat(height) / 2, options: [])
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    /// An SF Symbol as a white texture, `pointSize` art pixels tall.
    /// The symbol in `fill` with a `stroke` outline `width` points thick, walked round a ring
    /// as the title lettering's is. Drawn in its colours, so leave it untinted, or fill it
    /// white and tint to colour the fill alone.
    func outlinedSymbol(_ name: String, pointSize: CGFloat, fill: UIColor, stroke: UIColor, width: CGFloat = 2,
                        weight: UIImage.SymbolWeight = .heavy) -> SKTexture {
        let key = "symbol_\(name)_\(pointSize)_\(fill)_\(stroke)_\(width)"
        if let texture = cache[key] { return texture }
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let base = UIImage(systemName: name, withConfiguration: configuration)!
        let outline = base.withTintColor(stroke, renderingMode: .alwaysOriginal)
        let body = base.withTintColor(fill, renderingMode: .alwaysOriginal)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: base.size.width + width * 2, height: base.size.height + width * 2)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            for step in 0..<16 {
                let angle = CGFloat(step) / 16 * 2 * .pi
                outline.draw(at: CGPoint(x: width + cos(angle) * width, y: width + sin(angle) * width))
            }
            body.draw(at: CGPoint(x: width, y: width))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    func symbol(_ name: String, pointSize: CGFloat, weight: UIImage.SymbolWeight = .heavy) -> SKTexture {
        let key = "symbol_\(name)_\(pointSize)"
        if let texture = cache[key] { return texture }
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = UIImage(systemName: name, withConfiguration: configuration)!
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let texture = SKTexture(image: renderer.image { _ in image.draw(at: .zero) })
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }
}

extension SKColor {
    convenience init(rgb: RGB) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

/// The grayscale effect sheets, drawn in a player's energy colour through the look's tone
/// ramp: the sparks off a hit ball, the crown and the lightning on a score, and the charge
/// round a held throw.
enum EnergyEffect: CaseIterable {
    case spark, spark2, spark3, lightning1, lightning2, lightning3, lightning4, charge, lightningJump, lightningCharge
    case lightningSpark, lightningSpark2, flashSpark2, scoreStrike

    /// The two sparks a hit ball throws, one or the other each time, and the four bolts.
    static let hitSparks: [EnergyEffect] = [.spark, .spark2]
    /// Zeus Juice's hits spark with its own two sheets.
    static let lightningSparks: [EnergyEffect] = [.lightningSpark, .lightningSpark2]
    static let strikes: [EnergyEffect] = [.lightning1, .lightning2, .lightning3, .lightning4]
    /// The bolt sheets' frames that are a full-frame flash, and their one colour on the
    /// sheets, (241, 246, 240), as a grey level: what the flash comes out as through the ramp.
    static let strikeFlashFrames = 5..<7
    static let strikeLuminance = 0.958
    /// The charge plays up to here, then loops from here while the throw is held; the
    /// frames after play out where the throw was let go. Drawn at this size over its sheet.
    static let chargeLoopEnd = 67
    static let chargeLoopStart = 35
    /// The swirl at its sheet's own 128 pixels, as the user tuned it on screen.
    static let chargeScale: CGFloat = 1

    var name: String {
        switch self {
        case .spark: "esper_spark"
        case .spark2: "esper_spark2"
        case .spark3: "esper_spark3"
        case .lightningSpark: "lightning_spark"
        case .lightningSpark2: "lightning_spark2"
        case .flashSpark2: "flashspark2"
        case .lightning1: "lightning1"
        case .lightning2: "lightning2"
        case .lightning3: "lightning3"
        case .lightning4: "lightning4"
        case .charge: "esper_charge"
        case .lightningJump: "lightning_jump"
        case .lightningCharge: "lightning_charge"
        case .scoreStrike: "score_strike"
        }
    }

    /// Frames and the anchor come from the importer's measurements of the sheet.
    var frameCount: Int { EffectSheets.frames[name] ?? 1 }

    var fps: Double { self == .charge ? 30 : 24 }

    var anchor: CGPoint { CGPoint(x: 0.5, y: EffectSheets.anchorY[name] ?? 0.5) }

    /// A one-shot node in the player's colour that plays through, or through `range` of
    /// its frames, and removes itself.
    func node(_ sprites: SpriteLibrary, player: Int, at point: CGPoint, frames range: Range<Int>? = nil, scale: CGFloat = 1) -> SKSpriteNode {
        let frames = Array(sprites.effectFrames(self, player: player)[range ?? 0..<frameCount])
        let node = SKSpriteNode(texture: frames[0])
        node.anchorPoint = anchor
        node.position = point
        node.zPosition = 30
        node.setScale(scale)
        node.run(.sequence([.animate(with: frames, timePerFrame: 1 / fps), .removeFromParent()]))
        return node
    }
}

/// One-shot sprites: sparks, smoke, the swish, and Blazing Boba's fire and Flash Fizz's
/// flash, painted as they are. Each plays through and removes itself. The jump spark, the
/// smoke and the catch spark are drawn in the player's energy colour.
enum Effect {
    case smoke, jumpSpark, catchSpark, wallJumpSpark
    case fireJump, fireDash, fireWallSpark, fireSkid, fireTrail, fireCharge, fireCharge2, fireExplosion, fireballSummon
    case flashSpark, flashSpark2

    static let inEnergyColour: [Effect] = [.smoke, .jumpSpark, .catchSpark]
    /// Toned no lighter than the energy colour itself: the jump spark, and the smoke of the
    /// dash and slide. The catch spark keeps the paler ramp.
    static let sparkNames: Set<String> = [Effect.smoke.name, Effect.jumpSpark.name]

    var name: String {
        switch self {
        case .smoke: "smoke"
        case .jumpSpark: "jumpspark"
        case .catchSpark: "catchspark"
        case .wallJumpSpark: "walljumpspark"
        case .fireJump: "fire_jump"
        case .fireDash: "fire_dash"
        case .fireWallSpark: "fire_wallspark"
        case .fireSkid: "fire_skid"
        case .fireTrail: "fire_trail"
        case .fireCharge: "fire_charge"
        case .fireCharge2: "fire_charge2"
        case .fireExplosion: "fire_explosion"
        case .fireballSummon: "fireball_summon"
        case .flashSpark: "flashspark"
        case .flashSpark2: "flashspark2"
        }
    }

    /// Whether the sheet has been imported: a sheet named before it lands falls back.
    var available: Bool { EffectSheets.frames[name] != nil }
    static var fireParticleAvailable: Bool { EffectSheets.frames["fire_particle"] != nil }

    /// The GMS2 sheets keep their counts; a strip's come from the importer's measurements.
    var frameCount: Int {
        if let measured = EffectSheets.frames[name] { return measured }
        switch self {
        case .smoke: return 6
        default: return 5
        }
    }

    var fps: Double {
        switch self {
        case .catchSpark: 15
        case .smoke, .wallJumpSpark: 12
        default: 24
        }
    }

    /// A strip's anchor is where the importer found its art: on the bottom edge, on the
    /// feet line, or centred. The GMS2 sheets are feet-anchored, except the wall spark.
    var anchor: CGPoint {
        if let measured = EffectSheets.anchorY[name] { return CGPoint(x: 0.5, y: measured) }
        return self == .wallJumpSpark ? CGPoint(x: 0.5, y: 0.5) : CGPoint(x: 0.5, y: 8.0 / 48.0)
    }

    /// Whether the art sits on the bottom edge of its cell: a jump spark drawn there goes
    /// six pixels under the feet.
    var bottomAligned: Bool { (EffectSheets.anchorY[name] ?? 0.5) == 0 }

    /// The fire sheets are painted three times their playing size, the jump spark half
    /// again as much and the charge a little less; the flash's reduced sheet twice.
    var scale: CGFloat {
        switch self {
        case .fireJump: 2.0 / 3
        case .fireCharge: 0.8
        case .fireCharge2: 0.5
        case .fireballSummon: 2.0 / 3
        case .fireDash, .fireSkid, .fireTrail, .fireWallSpark, .fireExplosion: 1.0 / 3
        default: 1
        }
    }

    /// With a `player`, the frames come in that player's energy colour.
    func node(_ sprites: SpriteLibrary, at point: CGPoint, flipped: Bool, player: Int? = nil) -> SKSpriteNode {
        let frames = player.map { sprites.effectFrames(self, player: $0) } ?? sprites.frames(name, count: frameCount)
        let node = SKSpriteNode(texture: frames[0])
        node.anchorPoint = anchor
        node.position = point
        node.xScale = (flipped ? -1 : 1) * scale
        node.yScale = scale
        node.zPosition = 30
        node.run(.sequence([.animate(with: frames, timePerFrame: 1 / fps), .removeFromParent()]))
        return node
    }
}
