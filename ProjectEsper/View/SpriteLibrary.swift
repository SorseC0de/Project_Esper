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
    /// asked for as the player `icePlayer`, then each player's energy form, then each player
    /// turned round: a body mirrored to face left shows its sheet's back limbs in front, so the
    /// sleeves and boots swap over to stay on the same arm and leg; then each side as the
    /// customize screen shows it.
    private var looks = Look.byPlayer + [Look.ice] + Look.byPlayer.map(\.transformed) + Look.byPlayer.map(\.turnedRound) + Look.byPlayer
    static let icePlayer = Look.byPlayer.count
    /// A player's energy form, asked for as a player of its own.
    static func transformedPlayer(_ player: Int) -> Int { icePlayer + 1 + player }
    /// A player facing left, asked for as a player of its own.
    static func turnedPlayer(_ player: Int) -> Int { icePlayer + 1 + Look.byPlayer.count + player }
    /// A side as the customize screen shows it, asked for as a player of its own: only what that
    /// screen draws is made in it, so a pick never rebuilds the game's frames.
    static func customizePlayer(_ player: Int) -> Int { icePlayer + 1 + 2 * Look.byPlayer.count + player }

    /// Who a player's body is drawn as facing this way: turned round facing left, where that
    /// changes anything.
    func bodyPlayer(_ player: Int, facingLeft: Bool) -> Int {
        let turned = SpriteLibrary.turnedPlayer(player)
        return facingLeft && looks[turned] != looks[player] ? turned : player
    }

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
        let turned = SpriteLibrary.turnedPlayer(player)
        looks[turned] = look.turnedRound
        dropPlayer(player)
        dropPlayer(energyForm)
        dropPlayer(turned)
        rewarm(player: player)
        rewarm(player: energyForm)
        // Turned round, only where it differs: built ahead, so turning never makes frames.
        if looks[turned] != look { rewarm(player: turned) }
    }

    /// The customize screen's side drawn in `look`, as shown (the second side's turned round):
    /// what it drew in the last look dropped, nothing else made or touched.
    func setCustomizeLook(_ look: Look, for player: Int) {
        let slot = SpriteLibrary.customizePlayer(player)
        guard look != looks[slot] else { return }
        looks[slot] = look
        dropPlayer(slot)
    }

    /// Every player's frames dropped and rebuilt, for a change to how all looks are drawn; the
    /// customize screen's sides dropped, made again as it asks.
    func redrawPlayers() {
        for player in looks.indices {
            dropPlayer(player)
            if player < SpriteLibrary.customizePlayer(0) { rewarm(player: player) }
        }
    }

    /// The toned sheets beyond the energy effects that a player's particles use.
    static let tonedParticleSheets = ["lightning_particle", "lightning_particle2"]
    private var rewarmGeneration: [Int: Int] = [:]
    private let rewarmQueue = DispatchQueue(label: "SpriteLibrary.rewarm", qos: .userInitiated)
    /// Pieces asked for that came out empty (a frame with no front arm), so they aren't made again
    /// every frame; dropped with the player's cache.
    private var emptyPieces: Set<String> = []
    private func dropPlayer(_ player: Int) {
        cache = cache.filter { !$0.key.hasPrefix("p\(player)_") }
        emptyPieces = emptyPieces.filter { !$0.hasPrefix("p\(player)_") }
    }
    /// Each player's rebuild underway: its pieces made, of all of them, for the loading bar;
    /// and the pieces of the ones done (or overtaken, counted whole) since nothing was loading,
    /// so the count only ever climbs until it's all done.
    private var rebuilding: [Int: (made: Int, all: Int)] = [:]
    private var rebuilt = 0
    /// Pieces made of all of them while rebuilds are underway, or nil with none; told on the
    /// main thread as it changes.
    var onLoading: (((made: Int, all: Int)?) -> Void)?
    var loadingCounts: (made: Int, all: Int)? {
        guard !rebuilding.isEmpty else { return nil }
        return (rebuilt + rebuilding.values.reduce(0) { $0 + $1.made }, rebuilt + rebuilding.values.reduce(0) { $0 + $1.all })
    }
    /// The bar's told every this many pieces.
    private static let loadingReportEvery = 8

    /// A rebuild starting: one it overtakes is counted done.
    private func beginRebuilding(_ player: Int, pieces: Int) {
        if let overtaken = rebuilding[player] { rebuilt += overtaken.all }
        rebuilding[player] = (0, pieces)
        onLoading?(loadingCounts)
    }

    private func reportRebuilding(_ player: Int, generation: Int, made: Int?) {
        guard rewarmGeneration[player] == generation, let entry = rebuilding[player] else { return }
        if let made {
            rebuilding[player]?.made = made
        } else {
            rebuilding[player] = nil
            rebuilt += entry.all
            if rebuilding.isEmpty { rebuilt = 0 }
        }
        onLoading?(loadingCounts)
    }

    /// Everything drawn in a player's look rebuilt off the main thread after their look
    /// changes, then kept and sent to the GPU, so no frame, head, energy or toned effect is
    /// first made mid-match. Anything asked for before it lands is made as it always was;
    /// a newer change supersedes it.
    private func rewarm(player: Int) {
        let look = look(for: player)
        let generation = (rewarmGeneration[player] ?? 0) + 1
        rewarmGeneration[player] = generation
        var frameJobs: [(key: String, frame: AnimationFrame, source: SKTexture, holdsBall: Bool)] = []
        for animation in Animation.allCases {
            for index in 0..<animation.frameCount {
                let frame = AnimationFrame(animation, index)
                let source = atlas.textureNamed("\(animation.rawValue)_\(index)")
                let key = SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: false, ballLifted: false)
                frameJobs.append((key, frame, source, animation.holdsBall))
                if animation.holdsBall { frameJobs.append((SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: true, ballLifted: false), frame, source, false)) }
                if SpriteLibrary.liftsBall.contains(animation) { frameJobs.append((SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: false, ballLifted: true), frame, source, true)) }
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
        // Counted as pieces made, the last one the textures reaching the GPU.
        beginRebuilding(player, pieces: frameJobs.count + tonedJobs.count + silhouetteJobs.count + 1)
        rewarmQueue.async { [weak self] in
            guard let self else { return }
            var built: [String: SKTexture] = [:]
            var builtLandmarks: [String: [BodyPart: CGPoint]] = [:]
            var made = 0
            let lock = NSLock()
            /// One piece made, kept under the lock: the pieces are made on every core at once.
            func keep(_ textures: [String: SKTexture], landmarks: (key: String, marks: [BodyPart: CGPoint])? = nil) {
                lock.lock()
                built.merge(textures) { _, new in new }
                if let landmarks { builtLandmarks[landmarks.key] = landmarks.marks }
                made += 1
                let so = made
                lock.unlock()
                guard so % SpriteLibrary.loadingReportEvery == 0 else { return }
                DispatchQueue.main.async { self.reportRebuilding(player, generation: generation, made: so) }
            }
            // The sheets' images read out one at a time first, so the cores share nothing of SpriteKit's.
            // And the hood shapes, read out here once rather than first on some core.
            _ = (SpriteLibrary.hoodShapes, SpriteLibrary.turnedHoodShapes, SpriteLibrary.hoodDrawnForHead)
            let frameSources = frameJobs.map { $0.source.cgImage() }
            let tonedSources = tonedJobs.map { $0.source.cgImage() }
            let silhouetteSources = silhouetteJobs.map { $0.source.cgImage() }
            DispatchQueue.concurrentPerform(iterations: frameJobs.count) { index in
                let job = frameJobs[index]
                let frameMade = self.makeFrame(job.frame, source: frameSources[index], look: look, holdsBall: job.holdsBall)
                keep(Dictionary(uniqueKeysWithValues: frameMade.textures.map { (job.key + $0.key, $0.value) }), landmarks: (job.key, frameMade.landmarks))
            }
            DispatchQueue.concurrentPerform(iterations: tonedJobs.count) { index in
                keep([tonedJobs[index].key: self.makeToned(image: tonedSources[index], look: look, capped: tonedJobs[index].capped)])
            }
            DispatchQueue.concurrentPerform(iterations: silhouetteJobs.count) { index in
                keep([silhouetteJobs[index].key: self.makeSilhouette(image: silhouetteSources[index], look: look)])
            }
            DispatchQueue.main.async {
                guard self.rewarmGeneration[player] == generation else { return }
                // Its look changed since without a new rebuild (a turned look no longer differing): nothing to keep.
                guard self.look(for: player) == look else {
                    self.reportRebuilding(player, generation: generation, made: nil)
                    return
                }
                for (key, texture) in built where self.cache[key] == nil { self.cache[key] = texture }
                for (key, marks) in builtLandmarks where self.landmarks[key] == nil { self.landmarks[key] = marks }
                for job in frameJobs { self.pairGlowMask(job.key) }
                SKTexture.preload(Array(built.values)) {
                    DispatchQueue.main.async { self.reportRebuilding(player, generation: generation, made: nil) }
                }
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
    /// Blazing Boba's fireball: the basketball's every shade a step up the fire ramp, its seams
    /// gold and its outline orange, so it reads hot rather than as the ball.
    private(set) lazy var basketballFireFrames: [SKTexture] = basketballFrames.map { frame in
        let swaps: [RGB: RGB] = [PixelPalette.colours[7]: PixelPalette.colours[9], PixelPalette.colours[6]: PixelPalette.colours[8],
                                 PixelPalette.colours[5]: PixelPalette.colours[7], PixelPalette.colours[33]: PixelPalette.colours[7],
                                 PixelPalette.colours[43]: PixelPalette.colours[6]]
        let picture = frame.cgImage()
        let width = picture.width, height = picture.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else { return frame }
        context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        for pixel in 0..<(width * height) where pixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            let rgb = RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])
            guard let swap = swaps[rgb] else { continue }
            pixels[index] = UInt8((swap >> 16) & 0xFF)
            pixels[index + 1] = UInt8((swap >> 8) & 0xFF)
            pixels[index + 2] = UInt8(swap & 0xFF)
        }
        guard let made = context.makeImage() else { return frame }
        let texture = SKTexture(cgImage: made)
        texture.filteringMode = .nearest
        return texture
    }

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

    /// The sheets whose ball can be lifted off a frame and not drawn: FloState's snatch, which
    /// draws the ball it took, for a snatch that took none.
    static let liftsBall: Set<Animation> = [.snatchFloState]
    /// The sheets drawn while the hooded head can tip, flying and aiming Z Tea's beam: their line
    /// is made a second time without the hood's place, for the hood to carry its own.
    static let tippingHead: Set<Animation> = [.fly, .flyBall, .blast]

    /// A player frame's key in the cache: with `ballAsEnergy` the sheet's whites are all energy,
    /// with `ballLifted` its ball is lifted off and not drawn.
    static func frameKey(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool, ballLifted: Bool) -> String {
        "p\(player)_\(frame.animation.rawValue)_\(frame.frame)" + (ballAsEnergy ? "_whole" : "") + (ballLifted ? "_balllifted" : "")
    }

    /// A player frame in that player's look, without its head or its energy.
    /// With `ballAsEnergy`, a sheet that draws the ball has its whites taken as energy,
    /// ball and all, for a throw made with nothing in hand. With `ballLifted`, the ball the
    /// sheet draws is lifted off and not drawn, for a snatch that took nothing.
    func texture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture {
        let key = SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        if let texture = cache[key] { return texture }
        let made = makeFrame(frame, source: atlas.textureNamed("\(frame.animation.rawValue)_\(frame.frame)").cgImage(),
                             look: look(for: player), holdsBall: (frame.animation.holdsBall && !ballAsEnergy) || ballLifted)
        for (suffix, texture) in made.textures { cache[key + suffix] = texture }
        landmarks[key] = made.landmarks
        pairGlowMask(key)
        return cache[key]!
    }

    /// A player frame recoloured in a look: the body under "", and "_head" and "_energy"
    /// where the frame has them; and where its glowing parts sit. `holdsBall`: the sheet's
    /// ball is the ball, lifted off to be drawn apart, rather than energy. Touches nothing
    /// kept, so it can be made off the main thread.
    /// The frames whose arms are drawn the other way round, the front arm behind: the ground
    /// throw's follow-through, 5 on, where the back arm comes forward over the head. Their front
    /// and back arm and hand colours swap.
    static let armColoursSwapped: [Animation: ClosedRange<Int>] = [.throwForward: 4...7]
    static func look(_ look: Look, for frame: AnimationFrame) -> Look {
        guard armColoursSwapped[frame.animation]?.contains(frame.frame) == true else { return look }
        var swapped = look
        for (front, back) in [(BodyPart.frontArm, BodyPart.backArm), (.frontHand, .backHand)] {
            let was = swapped.colours[front]
            swapped.colours[front] = swapped.colours[back]
            swapped.colours[back] = was
        }
        return swapped
    }

    private func makeFrame(_ frame: AnimationFrame, source: CGImage, look: Look, holdsBall: Bool) -> (textures: [String: SKTexture], landmarks: [BodyPart: CGPoint]) {
        // A human's frame with its neck filled and its line round the hood, where the hood goes on it.
        let look = SpriteLibrary.look(look, for: frame)
        let result = recolour(image: source, look: look, holdsBall: holdsBall, detach: true,
                              hoodShape: look.human ? SpriteLibrary.hoodShape(skin: look.dressing.skinTone, for: frame) : nil,
                              bareLine: SpriteLibrary.tippingHead.contains(frame.animation))
        var textures = ["": result.texture]
        if let bareOutline = result.bareOutline { textures["_bareoutline"] = bareOutline }
        if let glowingParts = result.glowingParts { textures["_glowing"] = glowingParts }
        if let head = result.head { textures["_head"] = head }
        if let energy = result.energy { textures["_energy"] = energy }
        if let outline = result.outline { textures["_outline"] = outline }
        if let glowMask = result.glowMask { textures["_glowmask"] = glowMask }
        if let skin = result.skin { textures["_skin"] = skin }
        if let thinOutline = result.thinOutline { textures["_thinoutline"] = thinOutline }
        for texture in textures.values { texture.filteringMode = .nearest }
        let size = frame.animation.pixelSize, width = frame.animation.pixelWidth
        let landmarks = result.centres.mapValues { centre in
            CGPoint(x: centre.x - width / 2, y: size - centre.y - frame.animation.feetFromBottom)
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
    func energyTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        return cache[SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_energy"]
    }

    /// The line round a player frame alone, in white, on the same canvas as the body, for
    /// the view to colour. Nil when the frame has none.
    func outlineTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        return cache[SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_outline"]
    }

    /// A frame's glowing parts alone, as drawn, on the body's canvas; nil where it has none.
    func glowingPartsTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        return cache[SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_glowing"]
    }

    /// The glowing parts of the front arm and hand alone (a sleeve), for K&A's wash: drawn again
    /// unwashed over the front arm laid over the hood, as the body's are over the body.
    func frontArmGlowingTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        let key = SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_frontarmglowing"
        if let made = cache[key] { return made }
        guard !emptyPieces.contains(key) else { return nil }
        guard let glowing = glowingPartsTexture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted),
              let image = SpriteLibrary.partsImage(drawn: glowing.cgImage(), source: atlas.textureNamed("\(frame.animation.rawValue)_\(frame.frame)").cgImage(),
                                                   parts: [.frontArm, .frontHand]) else {
            emptyPieces.insert(key)
            return nil
        }
        let made = SKTexture(cgImage: image)
        made.filteringMode = .nearest
        cache[key] = made
        return made
    }

    /// The hooded head's face alone in its colours, on the hood's canvas: K&A's wash goes over it,
    /// as over the body's skin, while the hood glows unwashed.
    func hoodFace(skin: Int, player: Int, view: Int = 0) -> SKTexture? {
        let key = "p\(player)_hoodface_\(skin)_\(view)"
        if let made = cache[key] { return made }
        let head = hoodHead(skin: skin, player: player, view: view)
        let drawn = head.drawn.cgImage(), face = head.face.cgImage()
        let width = drawn.width, height = drawn.height
        guard face.width == width, face.height == height,
              let (context, pixels) = makeCanvas(width: width, height: height),
              let (maskContext, maskPixels) = makeCanvas(width: width, height: height) else { return nil }
        context.draw(drawn, in: CGRect(x: 0, y: 0, width: width, height: height))
        maskContext.draw(face, in: CGRect(x: 0, y: 0, width: width, height: height))
        for pixel in 0..<(width * height) where maskPixels[pixel * 4 + 3] == 0 {
            for channel in 0..<4 { pixels[pixel * 4 + channel] = 0 }
        }
        guard let image = context.makeImage() else { return nil }
        let made = SKTexture(cgImage: image)
        made.filteringMode = .nearest
        cache[key] = made
        return made
    }

    /// The line round a human's frame without the hood's place in it, for a tipped hood that
    /// carries its own line (`hoodLine`). Made with the frame on the sheets the head tips on,
    /// on the spot elsewhere; nil for a look with no hood.
    func bareOutlineTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        let look = look(for: player)
        guard look.human else { return nil }
        let key = SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        if let made = cache[key + "_bareoutline"] { return made }
        let result = recolour(atlas.textureNamed("\(frame.animation.rawValue)_\(frame.frame)"), look: SpriteLibrary.look(look, for: frame),
                              holdsBall: (frame.animation.holdsBall && !ballAsEnergy) || ballLifted, detach: true,
                              hoodShape: SpriteLibrary.hoodShape(skin: look.dressing.skinTone, for: frame), bareLine: true)
        result.bareOutline?.filteringMode = .nearest
        cache[key + "_bareoutline"] = result.bareOutline
        return result.bareOutline
    }

    /// The line round the hooded head alone, in white, on its canvas, a pixel out from it: drawn
    /// with the hood when it tips, under the body, so only what's outside the body shows.
    func hoodLine(skin: Int, view: Int = 0) -> SKTexture? {
        let key = "hoodline_\(skin)_\(view)"
        if let made = cache[key] { return made }
        let image = hoodHead(skin: skin, player: 0, view: view).drawn.cgImage()
        let width = image.width, height = image.height
        guard let (context, pixels) = makeCanvas(width: width, height: height),
              let (lineContext, linePixels) = makeCanvas(width: width, height: height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func filled(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height && pixels[(y * width + x) * 4 + 3] != 0 }
        for y in 0..<height {
            for x in 0..<width where !filled(x, y) {
                guard (-1...1).contains(where: { dy in (-1...1).contains { dx in (dx != 0 || dy != 0) && filled(x + dx, y + dy) } }) else { continue }
                for channel in 0..<4 { linePixels[(y * width + x) * 4 + channel] = 255 }
            }
        }
        let made = lineContext.makeImage().map { SKTexture(cgImage: $0) }
        made?.filteringMode = .nearest
        cache[key] = made
        return made
    }

    /// The line round a player frame at half its thickness, in white, on a canvas twice as fine.
    func thinOutlineTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        return cache[SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_thinoutline"]
    }

    /// A human's clothes alone from a player frame, the dark ones and the energy's (the shoes), in
    /// white, on the same canvas as the body: the FloState lockout's flash. Nil when the frame shows none.
    func clothesTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        return cache[SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_skin"]
    }

    /// The sheet's front leg alone from a player frame (its thigh, leg and foot) as drawn, and the
    /// line drawn round it, on the body's canvas: laid over the ball in hand where the sheet passes
    /// the ball behind that leg (the taunt's and the dribble walk's), the real ball drawn over the
    /// body otherwise. The sheet's front leg whichever way the body faces: turned round, the node's
    /// mirrored and only the clothes' colours swap. Nil with no front leg in the frame.
    func frontLegTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        partsTexture(frame, player: player, parts: [.frontThigh, .frontLeg, .frontFoot], suffix: "_frontleg", ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }

    /// The sheet's front arm alone (its arm and hand) as drawn with the line round it, on the body's
    /// canvas: laid over the hooded head on the frames `GameScene.frontArmOverHood` names, where the
    /// arm crosses the head. Nil with no front arm in the frame.
    func frontArmTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        partsTexture(frame, player: player, parts: [.frontArm, .frontHand], suffix: "_frontarm", ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }

    /// The front arm's own line, in white, for the line's node colour: round the arm and hand
    /// wherever they meet the hooded head or open air, so the arm laid over the hood is lined.
    func frontArmLineTexture(_ frame: AnimationFrame, player: Int) -> SKTexture? {
        let look = look(for: player)
        let key = "p\(player)_\(frame.animation.rawValue)_\(frame.frame)_frontarmline"
        if let made = cache[key] { return made }
        guard !emptyPieces.contains(key) else { return nil }
        let source = atlas.textureNamed("\(frame.animation.rawValue)_\(frame.frame)").cgImage()
        guard let image = SpriteLibrary.partsLine(source: source, parts: [.frontArm, .frontHand],
                                                  hood: look.human ? SpriteLibrary.hoodShape(skin: look.dressing.skinTone, for: frame) : nil) else {
            emptyPieces.insert(key)
            return nil
        }
        let made = SKTexture(cgImage: image)
        made.filteringMode = .nearest
        cache[key] = made
        return made
    }

    /// The line round `parts` on a sheet frame, in white: each pixel next to them that isn't them and
    /// is open air, the sheet's head, or under the hooded head placed as the game places it.
    static func partsLine(source: CGImage, parts: Set<BodyPart>, hood: CGImage?) -> CGImage? {
        let width = source.width, height = source.height
        guard let (sourceContext, sourcePixels) = canvas(width: width, height: height),
              let (lineContext, linePixels) = canvas(width: width, height: height) else { return nil }
        sourceContext.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        var owner = [BodyPart?](repeating: nil, count: width * height)
        var headSum = CGPoint.zero, heads = 0
        for pixel in 0..<(width * height) where sourcePixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            owner[pixel] = BodyPart.owning(RGB(sourcePixels[index]) << 16 | RGB(sourcePixels[index + 1]) << 8 | RGB(sourcePixels[index + 2]))
            if owner[pixel] == .head {
                headSum.x += CGFloat(pixel % width) + 0.5
                headSum.y += CGFloat(pixel / width) + 0.5
                heads += 1
            }
        }
        guard owner.contains(where: { $0.map(parts.contains) == true }) else { return nil }
        // Where the hood lands: its canvas moved by how far this head is from the one it's drawn for.
        var underHood = [Bool](repeating: false, count: width * height)
        if let hood, heads > 0, let there = hoodDrawnForHead, let (hoodContext, hoodPixels) = canvas(width: hood.width, height: hood.height) {
            hoodContext.draw(hood, in: CGRect(x: 0, y: 0, width: hood.width, height: hood.height))
            let offsetX = Int((headSum.x / CGFloat(heads) - there.x).rounded()), offsetY = Int((headSum.y / CGFloat(heads) - there.y).rounded())
            for y in 0..<hood.height {
                for x in 0..<hood.width where hoodPixels[(y * hood.width + x) * 4 + 3] != 0 {
                    let fx = x + offsetX, fy = y + offsetY
                    if fx >= 0, fy >= 0, fx < width, fy < height { underHood[fy * width + fx] = true }
                }
            }
        }
        func isPart(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height && owner[y * width + x].map(parts.contains) == true }
        var any = false
        for y in 0..<height {
            for x in 0..<width where !isPart(x, y) {
                let pixel = y * width + x
                let open = sourcePixels[pixel * 4 + 3] == 0 || owner[pixel] == .head || underHood[pixel]
                guard open, (-1...1).contains(where: { dy in (-1...1).contains { dx in (dx != 0 || dy != 0) && isPart(x + dx, y + dy) } }) else { continue }
                for channel in 0..<4 { linePixels[pixel * 4 + channel] = 255 }
                any = true
            }
        }
        return any ? lineContext.makeImage() : nil
    }

    private func partsTexture(_ frame: AnimationFrame, player: Int, parts: Set<BodyPart>, suffix: String, ballAsEnergy: Bool, ballLifted: Bool) -> SKTexture? {
        let key = SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + suffix
        if let made = cache[key] { return made }
        guard !emptyPieces.contains(key) else { return nil }
        let drawn = texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted).cgImage()
        let source = atlas.textureNamed("\(frame.animation.rawValue)_\(frame.frame)").cgImage()
        guard let image = SpriteLibrary.partsImage(drawn: drawn, source: source, parts: parts) else { emptyPieces.insert(key); return nil }
        let made = SKTexture(cgImage: image)
        made.filteringMode = .nearest
        cache[key] = made
        return made
    }

    /// The pixels of `parts` as `drawn` has them, found by the sheet's own colours in `source`, with
    /// the line drawn next to them; nil when the frame has none of them.
    static func partsImage(drawn: CGImage, source: CGImage, parts: Set<BodyPart>) -> CGImage? {
        let width = drawn.width, height = drawn.height
        guard source.width == width, source.height == height,
              let (drawnContext, drawnPixels) = SpriteLibrary.canvas(width: width, height: height),
              let (sourceContext, sourcePixels) = SpriteLibrary.canvas(width: width, height: height),
              let (partContext, partPixels) = SpriteLibrary.canvas(width: width, height: height) else { return nil }
        drawnContext.draw(drawn, in: CGRect(x: 0, y: 0, width: width, height: height))
        sourceContext.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        var isPart = [Bool](repeating: false, count: width * height)
        for pixel in 0..<(width * height) where sourcePixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            let colour = RGB(sourcePixels[index]) << 16 | RGB(sourcePixels[index + 1]) << 8 | RGB(sourcePixels[index + 2])
            if let part = BodyPart.owning(colour), parts.contains(part) { isPart[pixel] = true }
        }
        guard isPart.contains(true) else { return nil }
        for y in 0..<height {
            for x in 0..<width {
                let pixel = y * width + x
                var keep = isPart[pixel]
                // The line round it: drawn where the sheet has nothing, next to the part.
                if !keep, sourcePixels[pixel * 4 + 3] == 0, drawnPixels[pixel * 4 + 3] > 0 {
                    keep = (-1...1).contains { dy in (-1...1).contains { dx in
                        let nx = x + dx, ny = y + dy
                        return nx >= 0 && ny >= 0 && nx < width && ny < height && isPart[ny * width + nx]
                    } }
                }
                guard keep else { continue }
                for channel in 0..<4 { partPixels[pixel * 4 + channel] = drawnPixels[pixel * 4 + channel] }
            }
        }
        return partContext.makeImage()
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
    private func makeSilhouette(_ source: SKTexture, look: Look) -> SKTexture { makeSilhouette(image: source.cgImage(), look: look) }
    private func makeSilhouette(image: CGImage, look: Look) -> SKTexture {
        let source = SKTexture(cgImage: image)
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

    /// The brightest an energy face's lightest tone may be, as a grey level: lime (0.76) comes
    /// down to it, gold and teal (0.67, 0.68) a touch; the other colours are under it.
    static let energyFaceLevel = 0.6
    /// The hood's greys a touch down the ramp, nearer the legs' plain colour.
    static let hoodLevel = 0.9

    /// The hooded head, a frame of `player_hoodheads` for one skin: its hood, the white and the
    /// cool greys, toned through the player's energy ramp, the skin left as drawn; and the hood
    /// and the face each alone in white, for the glow's mask. As the ice player, the frozen
    /// bodies' and ice clones' look, the face too is toned, in the ice's front colour.
    /// In FloState (`energy`), the hood is the energy form's near-white clothes colour
    /// (`EnergyColour.body`), shaded by its greys, and the face the regular energy colour, its
    /// lighter skin tone the colour itself and the darker in proportion.
    /// `view`: which way the head faces (`HoodView`), the turned ones drawn from `player_hoodheads_v2`
    /// in the first skin and swapped into this one's two tones.
    func hoodHead(skin: Int, player: Int, energy: Bool = false, view: Int = 0) -> (drawn: SKTexture, hood: SKTexture, face: SKTexture) {
        let key = "p\(player)_hoodhead_\(skin)" + (view == 0 ? "" : "_v\(view)") + (energy ? "_energy" : "")
        if let drawn = cache[key], let hood = cache[key + "_hood"], let face = cache[key + "_face"] { return (drawn, hood, face) }
        let source = SpriteLibrary.hoodSource(skin: skin, view: view)
        // The robot's face: the frame it's drawn from with that frame's two tones in its own; a
        // turned view's, the first skin's two tones in this one's.
        var faceSwaps: [RGB: RGB] = [:]
        let drawnFrom = view == 0 ? HumanLook.hoodHeadFrame(skin) : HoodView.drawnInSkin
        if drawnFrom != skin {
            let from = HumanLook.skinTones[drawnFrom], to = HumanLook.skinTones[skin]
            faceSwaps = [PixelPalette.colours[from.front]: PixelPalette.colours[to.front], PixelPalette.colours[from.back]: PixelPalette.colours[to.back]]
        }
        let image = source.cgImage()
        let width = image.width, height = image.height
        let look = look(for: player)
        guard let (context, pixels) = makeCanvas(width: width, height: height),
              let (hoodContext, hoodPixels) = makeCanvas(width: width, height: height),
              let (faceContext, facePixels) = makeCanvas(width: width, height: height) else { return (source, source, source) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func level(_ index: Int) -> Double {
            (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / 255
        }
        // A light energy colour, lime's, is dimmed on the face so its features don't burn out in the glow.
        let glowLevel = (0.2126 * Double((look.glow >> 16) & 0xFF) + 0.7152 * Double((look.glow >> 8) & 0xFF) + 0.0722 * Double(look.glow & 0xFF)) / 255
        let faceDimming = energy ? min(SpriteLibrary.energyFaceLevel / max(glowLevel, 0.01), 1) : 1
        // The face's lightest tone, which the energy colour stands for.
        let faceLightest = (0..<(width * height)).filter { pixels[$0 * 4 + 3] != 0 && pixels[$0 * 4 + 2] < pixels[$0 * 4] }
            .map { level($0 * 4) }.max() ?? 1
        for pixel in 0..<(width * height) where pixels[pixel * 4 + 3] != 0 {
            let index = pixel * 4
            let red = Double(pixels[index]), green = Double(pixels[index + 1]), blue = Double(pixels[index + 2])
            // The hood is white and cool greys, blue at least as strong as red; skin is warm.
            let isHood = blue >= red
            let mask = isHood ? hoodPixels : facePixels
            for channel in 0..<4 { mask[index + channel] = 255 }
            guard isHood else {
                if energy || player == SpriteLibrary.icePlayer {
                    paint(pixels, index, Look.scaled(look.glow, min(level(index) / max(faceLightest, 0.01), 1) * faceDimming))
                } else if let swap = faceSwaps[RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])] {
                    paint(pixels, index, swap)
                }
                continue
            }
            let grey = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
            if energy, let body = look.body {
                paint(pixels, index, Look.scaled(body, min(grey, 1)))
            } else {
                paint(pixels, index, look.energyTone(luminance: min(grey * SpriteLibrary.hoodLevel, 1)))
            }
        }
        let made = [context, hoodContext, faceContext].map { context -> SKTexture in
            let texture = context.makeImage().map { SKTexture(cgImage: $0) } ?? source
            texture.filteringMode = .nearest
            return texture
        }
        cache[key] = made[0]
        cache[key + "_hood"] = made[1]
        cache[key + "_face"] = made[2]
        return (made[0], made[1], made[2])
    }

    /// A one-frame figure, the customize screen's, in a player's look and lined, without its
    /// head: the hooded head comes apart, to be drawn over it where the game would put it, moved
    /// from where it's drawn for (the idle's third frame) by how far this figure's head is from
    /// that one's (`hoodOffset`). With what of each glows (the sleeves, boots and shoes; the
    /// hood but not its face), and where the figure's parts and its limbs' tops are, all in its
    /// pixels from the top left.
    struct Portrait {
        let image: CGImage
        let glowing: CGImage
        let hood: CGImage?
        let hoodGlowing: CGImage?
        let hoodOffset: CGPoint
        let centres: [BodyPart: CGPoint]
        /// The limbs' tops, where a boot's or a sleeve's cubes come off.
        let tops: [BodyPart: CGPoint]
        /// The figure's line apart from it, in white, to be drawn in the look's line colour.
        let line: CGImage?
        /// Its front arm and hand again, and their own line in white, to go over the hood where the arm crosses the head.
        let frontArm: CGImage?
        let frontArmLine: CGImage?
        /// The line without the hood's place, and the hood's own line on its canvas, for when the
        /// hood turns and carries its line with it, as in play.
        let bareLine: CGImage?
        let hoodLine: CGImage?
    }
    private var portraits: [String: Portrait] = [:]

    /// Where the customize figure's hooded head goes and how big: its canvas's top left on the
    /// figure's, in pixels from the top left, and its scale. Moved from where the game would put
    /// it by `nudge` (art pixels right and up) and scaled about the head's middle, which the
    /// hood's own sits on.
    static func hoodPlace(head: CGPoint, offset: CGPoint, nudge: CGPoint, scale: CGFloat) -> (origin: CGPoint, scale: CGFloat) {
        let own = CGPoint(x: head.x - offset.x, y: head.y - offset.y)
        return (CGPoint(x: head.x - own.x * scale + nudge.x, y: head.y - own.y * scale - nudge.y), scale)
    }

    /// With the hood placed by `headNudge` and `headScale`: the figure's neck filled and its
    /// line run round the hood there, so nothing shows through where they meet.
    /// A frame of a sheet outside the game's animations (the Greateraid pick's drinker) in a
    /// player's look, lined, its hooded head on it where the game would put it and its neck
    /// filled, as a body is in play. Its towel, palette 22 and 37, isn't energy: kept as drawn.
    /// `headTilt`, degrees, turns the hooded head back about its middle (facing right); the
    /// sheet's pixels in `overHood`'s colours are drawn again over the hood.
    func standalone(_ name: String, frame: Int, player: Int, headTilt: CGFloat = 0, overHood: Set<RGB> = []) -> SKTexture {
        let key = "p\(player)_standalone_\(name)_\(frame)_\(headTilt)"
        if let made = cache[key] { return made }
        let look = look(for: player)
        let source = texture(name, frame).cgImage()
        let body = recolour(texture(name, frame), look: look, holdsBall: false, detach: false,
                            hoodShape: look.human ? SpriteLibrary.hoodShapes[HumanLook.hoodHeadFrame(look.dressing.skinTone)] : nil)
        var made = body.texture
        let image = body.texture.cgImage()
        if let (context, pixels) = makeCanvas(width: image.width, height: image.height),
           let (sourceContext, sourcePixels) = makeCanvas(width: source.width, height: source.height) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            sourceContext.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            let towel: Set<RGB> = [PixelPalette.colours[22], PixelPalette.colours[37]]
            for pixel in 0..<(min(image.width, source.width) * min(image.height, source.height)) where sourcePixels[pixel * 4 + 3] == 255 {
                let index = pixel * 4
                let colour = RGB(sourcePixels[index]) << 16 | RGB(sourcePixels[index + 1]) << 8 | RGB(sourcePixels[index + 2])
                guard towel.contains(colour) else { continue }
                for channel in 0..<4 { pixels[index + channel] = sourcePixels[index + channel] }
            }
            if let composed = context.makeImage() { made = SKTexture(cgImage: composed) }
        }
        if look.human, let here = body.centres[.head], let there = SpriteLibrary.hoodDrawnForHead,
           let (context, _) = makeCanvas(width: image.width, height: image.height) {
            context.draw(made.cgImage(), in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let hood = hoodHead(skin: look.dressing.skinTone, player: player).drawn.cgImage()
            // The offset counts rows down; the context's run up.
            let offset = CGPoint(x: (here.x - there.x).rounded(), y: (here.y - there.y).rounded())
            if headTilt != 0 {
                // About the head's middle; the context's rows run up.
                let pivot = CGPoint(x: here.x, y: CGFloat(image.height) - here.y)
                context.interpolationQuality = .none
                context.translateBy(x: pivot.x, y: pivot.y)
                context.rotate(by: headTilt * .pi / 180)
                context.translateBy(x: -pivot.x, y: -pivot.y)
            }
            context.draw(hood, in: CGRect(x: offset.x, y: -offset.y, width: CGFloat(hood.width), height: CGFloat(hood.height)))
            if var composed = context.makeImage() {
                if !overHood.isEmpty, let over = overlaid(composed, from: made.cgImage(), where: source, in: overHood) { composed = over }
                made = SKTexture(cgImage: composed)
            }
        }
        made.filteringMode = .nearest
        cache[key] = made
        return made
    }

    /// `top` with `under`'s pixels laid back over it wherever `source` is painted in one of `colours`.
    private func overlaid(_ top: CGImage, from under: CGImage, where source: CGImage, in colours: Set<RGB>) -> CGImage? {
        let width = top.width, height = top.height
        guard under.width == width, under.height == height, source.width == width, source.height == height,
              let (context, pixels) = makeCanvas(width: width, height: height),
              let (underContext, underPixels) = makeCanvas(width: width, height: height),
              let (sourceContext, sourcePixels) = makeCanvas(width: width, height: height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(top, in: rect)
        underContext.draw(under, in: rect)
        sourceContext.draw(source, in: rect)
        for pixel in 0..<(width * height) where sourcePixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            let colour = RGB(sourcePixels[index]) << 16 | RGB(sourcePixels[index + 1]) << 8 | RGB(sourcePixels[index + 2])
            guard colours.contains(colour) else { continue }
            for channel in 0..<4 { pixels[index + channel] = underPixels[index + channel] }
        }
        return context.makeImage()
    }

    /// `holdsBall`: the sheet draws the ball in hand, kept white rather than read as energy.
    func portrait(_ name: String, frame: Int = 0, player: Int, headDrawnFor: AnimationFrame, headNudge: CGPoint, headScale: CGFloat,
                  holdsBall: Bool = false) -> Portrait? {
        let key = "p\(player)_portrait_\(name)_\(frame)_\(headNudge.x)_\(headNudge.y)_\(headScale)"
        if cache[key] != nil, let made = portraits[key] { return made }
        // A game sheet's frame in the look it's drawn in, its arms swapped where they are.
        let playerLook = look(for: player)
        let sheetFrame = Animation(rawValue: name).map { AnimationFrame($0, frame) }
        let look = sheetFrame.map { SpriteLibrary.look(playerLook, for: $0) } ?? playerLook
        let view = sheetFrame.map(HoodView.of) ?? 0
        let flipped = sheetFrame.map(HoodView.isFlipped) ?? false
        /// The hooded head as this frame wears it: its view, mirrored where it looks back.
        func wornHood(_ image: CGImage) -> CGImage { flipped ? SpriteLibrary.mirrored(image) ?? image : image }
        let plain = recolour(texture(name, frame), look: look, holdsBall: holdsBall, detach: false)
        let drawnFor = recolour(atlas.textureNamed("\(headDrawnFor.animation.rawValue)_\(headDrawnFor.frame)"), look: look, holdsBall: false, detach: false)
        var figure = plain
        if look.human, let here = plain.centres[.head], let there = drawnFor.centres[.head] {
            let offset = CGPoint(x: (here.x - there.x).rounded(), y: (here.y - there.y).rounded())
            let place = SpriteLibrary.hoodPlace(head: here, offset: offset, nudge: headNudge, scale: headScale)
            figure = recolour(texture(name, frame), look: look, holdsBall: holdsBall, detach: true,
                              hood: (wornHood(hoodHead(skin: look.dressing.skinTone, player: player, view: view).drawn.cgImage()), place.origin, place.scale))
        }
        let body = figure.texture.cgImage()
        let width = body.width, height = body.height
        guard let (glowContext, glowPixels) = makeCanvas(width: width, height: height),
              let (sourceContext, sourcePixels) = makeCanvas(width: width, height: height) else { return nil }
        // What glows: the figure's pixels of the parts that do, as drawn.
        glowContext.draw(body, in: CGRect(x: 0, y: 0, width: width, height: height))
        let source = texture(name, frame).cgImage()
        sourceContext.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let colour = RGB(sourcePixels[index]) << 16 | RGB(sourcePixels[index + 1]) << 8 | RGB(sourcePixels[index + 2])
            let glows = look.human && sourcePixels[index + 3] == 255 && BodyPart.owning(colour).map(look.dressing.glowing.contains) == true
            if !glows { for channel in 0..<4 { glowPixels[index + channel] = 0 } }
        }
        var offset = CGPoint.zero
        var hood: CGImage?, hoodGlowing: CGImage?
        if look.human, let here = figure.centres[.head], let there = drawnFor.centres[.head] {
            let hoodHead = hoodHead(skin: look.dressing.skinTone, player: player, view: view)
            let drawn = wornHood(hoodHead.drawn.cgImage())
            hood = drawn
            offset = CGPoint(x: (here.x - there.x).rounded(), y: (here.y - there.y).rounded())
            // The hood glows; its face doesn't.
            if let (hoodContext, hoodPixels) = makeCanvas(width: drawn.width, height: drawn.height),
               let (maskContext, maskPixels) = makeCanvas(width: drawn.width, height: drawn.height) {
                hoodContext.draw(drawn, in: CGRect(x: 0, y: 0, width: drawn.width, height: drawn.height))
                maskContext.draw(wornHood(hoodHead.hood.cgImage()), in: CGRect(x: 0, y: 0, width: drawn.width, height: drawn.height))
                for pixel in 0..<(drawn.width * drawn.height) where maskPixels[pixel * 4 + 3] == 0 {
                    for channel in 0..<4 { hoodPixels[pixel * 4 + channel] = 0 }
                }
                hoodGlowing = hoodContext.makeImage()
            }
        }
        guard let glowing = glowContext.makeImage() else { return nil }
        let bare = look.human ? recolour(texture(name, frame), look: look, holdsBall: holdsBall, detach: true,
                                         hoodShape: SpriteLibrary.hoodShape(skin: look.dressing.skinTone, view: view, flipped: flipped), bareLine: true).bareOutline : nil
        let made = Portrait(image: body, glowing: glowing, hood: hood, hoodGlowing: hoodGlowing, hoodOffset: offset,
                            centres: figure.centres, tops: SpriteLibrary.partTops(source),
                            line: figure.outline?.cgImage(), frontArm: SpriteLibrary.partsImage(drawn: body, source: source, parts: [.frontArm, .frontHand]),
                            frontArmLine: SpriteLibrary.partsLine(source: source, parts: [.frontArm, .frontHand],
                                                                  hood: look.human ? SpriteLibrary.hoodShape(skin: look.dressing.skinTone, view: view, flipped: flipped) : nil),
                            bareLine: bare?.cgImage(), hoodLine: look.human ? hoodLine(skin: look.dressing.skinTone, view: view)?.cgImage() : nil)
        // Kept in the cache too, so a new look drops it with the rest of the player's.
        cache[key] = SKTexture(cgImage: body)
        portraits[key] = made
        return made
    }

    /// A grey frame through a look's energy ramp, or with `capped` the sparks' ramp, which
    /// stops at the colour; touches nothing kept.
    private func makeToned(_ source: SKTexture, look: Look, capped: Bool = false) -> SKTexture { makeToned(image: source.cgImage(), look: look, capped: capped) }
    private func makeToned(image: CGImage, look: Look, capped: Bool = false) -> SKTexture {
        let source = SKTexture(cgImage: image)
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
    /// `player_hoodheads`' frames, each the hood's shape for its skin, and where the head sits on
    /// the idle frame the hood is drawn for, in its pixels from the top left: the sheets' alone,
    /// read once.
    static let hoodDrawnFor = AnimationFrame(.idle, 2)
    static let hoodShapes: [CGImage] = (0..<6).map { SKTextureAtlas(named: "Sprites").textureNamed("player_hoodheads_\($0)").cgImage() }
    /// A turned view's frames, `player_hoodheads_v2`'s second and third (its first is the plain view).
    static let turnedHoodShapes: [Int: CGImage] = {
        let atlas = SKTextureAtlas(named: "Sprites")
        return Dictionary(uniqueKeysWithValues: (1..<HoodView.count).compactMap { view in
            atlas.textureNames.contains("player_hoodheads_v2_\(view)") ? (view, atlas.textureNamed("player_hoodheads_v2_\(view)").cgImage()) : nil
        })
    }()
    /// The hooded head's outline for a skin and view: where the body's line and neck go round it.
    static func hoodShape(skin: Int, view: Int, flipped: Bool = false) -> CGImage {
        let shape = view == 0 ? hoodShapes[HumanLook.hoodHeadFrame(skin)] : turnedHoodShapes[view] ?? hoodShapes[HumanLook.hoodHeadFrame(skin)]
        return flipped ? mirrored(shape) ?? shape : shape
    }
    /// A frame's hood shape: its view, mirrored where the head looks back.
    static func hoodShape(skin: Int, for frame: AnimationFrame) -> CGImage {
        hoodShape(skin: skin, view: HoodView.of(frame), flipped: HoodView.isFlipped(frame))
    }
    /// An image turned round left to right about its middle.
    static func mirrored(_ image: CGImage) -> CGImage? {
        guard let (context, _) = canvas(width: image.width, height: image.height) else { return nil }
        context.translateBy(x: CGFloat(image.width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
    /// The frame a skin and view's hooded head is drawn from.
    static func hoodSource(skin: Int, view: Int) -> SKTexture {
        let atlas = SKTextureAtlas(named: "Sprites")
        return view == 0 || turnedHoodShapes[view] == nil ? atlas.textureNamed("player_hoodheads_\(HumanLook.hoodHeadFrame(skin))")
            : atlas.textureNamed("player_hoodheads_v2_\(view)")
    }
    static let hoodDrawnForHead: CGPoint? = {
        let image = SKTextureAtlas(named: "Sprites").textureNamed("\(hoodDrawnFor.animation.rawValue)_\(hoodDrawnFor.frame)").cgImage()
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var sum = CGPoint.zero, heads = 0
        for pixel in 0..<(width * height) where pixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            guard BodyPart.owning(RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])) == .head else { continue }
            sum.x += CGFloat(pixel % width) + 0.5
            sum.y += CGFloat(pixel / width) + 0.5
            heads += 1
        }
        return heads > 0 ? CGPoint(x: sum.x / CGFloat(heads), y: sum.y / CGFloat(heads)) : nil
    }()

    /// Where a limb part starts at its top, the knee of a lower leg or the shoulder of an arm: the
    /// middle of its topmost row, in art pixels from the feet as landmarks are. The sheet's alone,
    /// the same in every look.
    private var partTops: [String: [BodyPart: CGPoint]] = [:]
    func top(_ part: BodyPart, in frame: AnimationFrame) -> CGPoint? {
        let key = "\(frame.animation.rawValue)_\(frame.frame)"
        if let found = partTops[key] { return found[part] }
        let size = frame.animation.pixelSize, width = frame.animation.pixelWidth
        let tops = SpriteLibrary.partTops(atlas.textureNamed(key).cgImage()).mapValues { top in
            CGPoint(x: top.x - width / 2, y: size - top.y - frame.animation.feetFromBottom)
        }
        partTops[key] = tops
        return tops[part]
    }

    /// The limbs' tops on a sheet frame, in its pixels from the top left.
    static func partTops(_ image: CGImage) -> [BodyPart: CGPoint] {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return [:] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let limbs: Set<BodyPart> = [.frontLeg, .backLeg, .frontArm, .backArm]
        var found: [BodyPart: (row: Int, xs: [Int])] = [:]
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] == 255 {
                let index = (y * width + x) * 4
                guard let part = BodyPart.owning(RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])),
                      limbs.contains(part) else { continue }
                if found[part] == nil { found[part] = (y, []) }
                if found[part]?.row == y { found[part]?.xs.append(x) }
            }
        }
        return found.mapValues { CGPoint(x: CGFloat($0.xs.reduce(0, +)) / CGFloat($0.xs.count) + 0.5, y: CGFloat($0.row) + 0.5) }
    }

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
        let size = frame.animation.pixelSize, width = frame.animation.pixelWidth
        return CGPoint(x: (head.x + width / 2) / width, y: (head.y + frame.animation.feetFromBottom) / size)
    }

    /// Everything made so far.
    var allTextures: [SKTexture] { Array(cache.values) }

    /// Builds every frame of every player up front and sends them to the GPU, so nothing
    /// is made mid-draw.
    func warmUp(players: Int, completion: @escaping () -> Void) {
        // The ice look's frames as well, and each player's energy form, so a freeze or a
        // change never makes them mid-match.
        let turned = (0..<players).map(SpriteLibrary.turnedPlayer).filter { look(for: $0) != look(for: $0 - SpriteLibrary.turnedPlayer(0)) }
        for drawn in [SpriteLibrary.icePlayer] + (0..<players).map(SpriteLibrary.transformedPlayer) + turned {
            for animation in Animation.allCases {
                for frame in 0..<animation.frameCount {
                    _ = texture(AnimationFrame(animation, frame), player: drawn)
                }
            }
        }
        // The limbs' tops, where boots' and sleeves' cubes come off.
        for animation in Animation.allCases {
            for frame in 0..<animation.frameCount { _ = top(.frontLeg, in: AnimationFrame(animation, frame)) }
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
    private func makeCanvas(width: Int, height: Int) -> (CGContext, UnsafeMutablePointer<UInt8>)? { SpriteLibrary.canvas(width: width, height: height) }

    static func canvas(width: Int, height: Int) -> (CGContext, UnsafeMutablePointer<UInt8>)? {
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
    /// `hood`: the hooded head, its shape (`player_hoodheads`' drawn pixels) placed on the
    /// canvas, or with `hoodShape` placed as the game places it, moved from the idle frame it's
    /// drawn for by how far this frame's head is from that one's: the sheet's head is kept under
    /// it as its neck, in the skin's shadow tone, and the outside line runs round the body and
    /// the hood together, the hood's own pixels left clear for it to be drawn in.
    private func recolour(_ texture: SKTexture, look: Look, holdsBall: Bool, detach: Bool,
                          hood given: (shape: CGImage, origin: CGPoint, scale: CGFloat)? = nil, hoodShape: CGImage? = nil,
                          bareLine: Bool = false) -> (texture: SKTexture, head: SKTexture?, energy: SKTexture?, outline: SKTexture?, glowMask: SKTexture?, skin: SKTexture?, thinOutline: SKTexture?, centres: [BodyPart: CGPoint], bareOutline: SKTexture?, glowingParts: SKTexture?) {
        recolour(image: texture.cgImage(), look: look, holdsBall: holdsBall, detach: detach, hood: given, hoodShape: hoodShape, bareLine: bareLine)
    }

    /// The same from the sheet's image itself: what the rebuild's cores are handed, so none of them
    /// reads a texture back through SpriteKit (which opens a GPU context on each thread that does).
    private func recolour(image: CGImage, look: Look, holdsBall: Bool, detach: Bool,
                          hood given: (shape: CGImage, origin: CGPoint, scale: CGFloat)? = nil, hoodShape: CGImage? = nil,
                          bareLine: Bool = false) -> (texture: SKTexture, head: SKTexture?, energy: SKTexture?, outline: SKTexture?, glowMask: SKTexture?, skin: SKTexture?, thinOutline: SKTexture?, centres: [BodyPart: CGPoint], bareOutline: SKTexture?, glowingParts: SKTexture?) {
        let texture = SKTexture(cgImage: image)
        let width = image.width, height = image.height
        guard let (context, pixels) = makeCanvas(width: width, height: height) else { return (texture, nil, nil, nil, nil, nil, nil, [:], nil, nil) }
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
        // Where the hood will be drawn over this canvas, if it's given or its shape is.
        var hood = given
        if hood == nil, look.human, let hoodShape, let there = SpriteLibrary.hoodDrawnForHead {
            var sum = CGPoint.zero, heads = 0
            for pixel in 0..<count where parts[pixel] == .head {
                sum.x += CGFloat(pixel % width) + 0.5
                sum.y += CGFloat(pixel / width) + 0.5
                heads += 1
            }
            if heads > 0 {
                hood = (hoodShape, CGPoint(x: (sum.x / CGFloat(heads) - there.x).rounded(), y: (sum.y / CGFloat(heads) - there.y).rounded()), 1)
            }
        }
        var hoodCover = [Bool](repeating: false, count: count)
        if let hood, let (shapeContext, shapePixels) = makeCanvas(width: hood.shape.width, height: hood.shape.height) {
            shapeContext.draw(hood.shape, in: CGRect(x: 0, y: 0, width: hood.shape.width, height: hood.shape.height))
            for pixel in 0..<count {
                let x = Int(((CGFloat(pixel % width) + 0.5 - hood.origin.x) / hood.scale).rounded(.down))
                let y = Int(((CGFloat(pixel / width) + 0.5 - hood.origin.y) / hood.scale).rounded(.down))
                guard (0..<hood.shape.width).contains(x), (0..<hood.shape.height).contains(y) else { continue }
                hoodCover[pixel] = shapePixels[(y * hood.shape.width + x) * 4 + 3] > 0
            }
        }

        // Each part to its colour; the energy to the tone of its own brightness.
        var sums: [BodyPart: (x: CGFloat, y: CGFloat, n: Int)] = [:]
        for pixel in 0..<count {
            guard let part = parts[pixel] else { continue }
            let index = pixel * 4
            // The glowing parts' middles, and the head's however it's drawn: where the head
            // and its particles go.
            // And the limbs' ends, where cubes come off them; and the torso, for the hood down behind it.
            if part.glows(human: look.human) || part == .head || [.frontLeg, .backLeg, .frontFoot, .backFoot, .frontHand, .backHand, .frontArm, .backArm, .torso].contains(part) {
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
            let headCanvas = sums[.head] != nil && look.headApart ? makeCanvas(width: width, height: height) : nil
            let energyCanvas = parts.contains { $0?.isEnergy == true } ? makeCanvas(width: width, height: height) : nil
            for pixel in 0..<count {
                // A human's head stays on the body.
                guard let part = parts[pixel], (part == .head && look.headApart) || part == .ball || part.isEnergy else { continue }
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
        // With the hood given, the head is only its neck: no line of its own.
        for group in look.strokedGroups where hood == nil || !group.contains(.head) {
            let stroked = (0..<count).map { parts[$0].map(group.contains) == true && !lined[$0] }
            for pixel in 0..<count where parts[pixel] != nil && !stroked[pixel] && !lined[pixel] && neighbours(pixel, { stroked[$0] }) {
                paint(pixels, pixel * 4, look.outline)
                lined[pixel] = true
            }
        }

        // With `bareLine` and the hood's place given, the same line again round the body alone,
        // the hood's place left out of it, for a tipped hood that carries its own.
        var bareLined: [Bool]?
        if bareLine, detach, hood != nil, look.outlineWidth > 0 {
            var lineHere = lined
            var filled = (0..<count).map { pixels[$0 * 4 + 3] != 0 }
            var body = (0..<count).map { filled[$0] && parts[$0]?.glows(human: look.human) != true }
            for _ in 0..<look.outlineWidth {
                let grown = (0..<count).filter { !filled[$0] && neighbours($0, { body[$0] }) }
                for pixel in grown {
                    filled[pixel] = true
                    body[pixel] = true
                    lineHere[pixel] = true
                }
            }
            bareLined = lineHere
        }

        // The outside line, grown a pixel at a time round the body. The glowing parts get
        // none: a clear pixel next to nothing but the ball stays clear.
        if look.outlineWidth > 0 {
            var body = (0..<count).map { (pixels[$0 * 4 + 3] != 0 && parts[$0]?.glows(human: look.human) != true) || hoodCover[$0] }
            for _ in 0..<look.outlineWidth {
                var grown: [Int] = []
                for pixel in 0..<count where pixels[pixel * 4 + 3] == 0 && !hoodCover[pixel] && neighbours(pixel, { body[$0] }) {
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

        // A human's head is the view's, `player_hoodheads` over it: the sheet's own is taken
        // out, its line left round where it was.
        // Under the hood, the neck in the skin's shadow tone.
        if look.human, hood != nil {
            for pixel in 0..<count where parts[pixel] == .head && !lined[pixel] {
                // The back hand's colour: the skin's back tone, or the ice look's back colour.
                paint(pixels, pixel * 4, look.colours[.backHand] ?? PixelPalette.colours[look.dressing.tone.back])
            }
        }
        if look.human, hood == nil {
            for pixel in 0..<count where parts[pixel] == .head && !lined[pixel] {
                for channel in 0..<4 { pixels[pixel * 4 + channel] = 0 }
            }
        }

        // A human's energy-coloured parts glow; the energy form glows all over but its bare
        // arms and legs, in their skin.
        func bareSkin(_ part: BodyPart?) -> Bool { part.map { $0 != .head && look.dressing.skin[$0] != nil } == true }
        let glowing = (0..<count).map { look.human ? parts[$0].map(look.dressing.glowing.contains) == true : parts[$0] != nil && !bareSkin(parts[$0]) }

        // The line at half its thickness, on a canvas twice as fine: of each line pixel only the
        // quarters against the body, so it hugs it. FloState's rainbow line.
        var thinOutline: SKTexture?
        if detach, lined.contains(true), let (thinContext, thinPixels) = makeCanvas(width: width * 2, height: height * 2) {
            // The hood's place counts as body, so the line hugs it too.
            let body = (0..<count).map { (pixels[$0 * 4 + 3] != 0 && !lined[$0]) || hoodCover[$0] }
            func isBody(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height && body[y * width + x] }
            for pixel in 0..<count where lined[pixel] {
                let x = pixel % width, y = pixel / width
                for half in 0..<4 {
                    let dx = half % 2 == 0 ? -1 : 1, dy = half / 2 == 0 ? -1 : 1
                    guard isBody(x + dx, y) || isBody(x, y + dy) || isBody(x + dx, y + dy) else { continue }
                    let index = ((y * 2 + half / 2) * width * 2 + x * 2 + half % 2) * 4
                    for channel in 0..<4 { thinPixels[index + channel] = 255 }
                }
            }
            thinOutline = thinContext.makeImage().map { SKTexture(cgImage: $0) }
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

        var bareOutline: SKTexture?
        if let bareLined, let (bareContext, barePixels) = makeCanvas(width: width, height: height) {
            for pixel in 0..<count where bareLined[pixel] {
                for channel in 0..<4 { barePixels[pixel * 4 + channel] = 255 }
            }
            bareOutline = bareContext.makeImage().map { SKTexture(cgImage: $0) }
        }

        // The glowing parts alone, as drawn: over K&A's wash, so the night doesn't dim them.
        var glowingParts: SKTexture?
        if detach, glowing.contains(true), let (partsContext, partsPixels) = makeCanvas(width: width, height: height) {
            for pixel in 0..<count where pixels[pixel * 4 + 3] != 0 && glowing[pixel] {
                for channel in 0..<4 { partsPixels[pixel * 4 + channel] = pixels[pixel * 4 + channel] }
            }
            glowingParts = partsContext.makeImage().map { SKTexture(cgImage: $0) }
        }

        // The body as the glow's mask sees it, in white, the glowing pixels black so they take
        // the glow's plain threshold rather than the body's, whatever's under them: left out, a
        // stage's flat backdrop showed through and they didn't glow. A human's skin is green, so
        // it never glows however light it is.
        var glowMask: SKTexture?
        if detach, glowing.contains(true), let (maskContext, maskPixels) = makeCanvas(width: width, height: height) {
            for pixel in 0..<count where pixels[pixel * 4 + 3] != 0 && glowing[pixel] {
                maskPixels[pixel * 4 + 3] = 255
            }
            for pixel in 0..<count where pixels[pixel * 4 + 3] != 0 && !glowing[pixel] {
                let index = pixel * 4
                let skin = look.human ? parts[pixel].map { look.dressing.skin[$0] != nil } == true : bareSkin(parts[pixel])
                maskPixels[index] = skin ? 0 : 255
                maskPixels[index + 1] = 255
                maskPixels[index + 2] = skin ? 0 : 255
                maskPixels[index + 3] = 255
            }
            glowMask = maskContext.makeImage().map { SKTexture(cgImage: $0) }
        }

        // A human's skin alone in white, as it's drawn: for the
        // FloState lockout's flash.
        // A human's clothes alone in white, the dark ones and the energy's, as drawn: for the
        // FloState lockout's flash.
        var skin: SKTexture?
        if detach, look.human, let (skinContext, skinPixels) = makeCanvas(width: width, height: height) {
            var any = false
            for pixel in 0..<count where pixels[pixel * 4 + 3] != 0 && !lined[pixel]
                && parts[pixel].map({ HumanLook.clothed.contains($0) || look.dressing.glowing.contains($0) }) == true {
                let index = pixel * 4
                for channel in 0..<4 { skinPixels[index + channel] = 255 }
                any = true
            }
            if any { skin = skinContext.makeImage().map { SKTexture(cgImage: $0) } }
        }

        guard let recoloured = context.makeImage() else { return (texture, nil, nil, nil, nil, nil, nil, [:], nil, nil) }
        let centres = sums.mapValues { CGPoint(x: $0.x / CGFloat($0.n), y: $0.y / CGFloat($0.n)) }
        return (SKTexture(cgImage: recoloured), head, energy, outline, glowMask, skin, thinOutline, centres, bareOutline, glowingParts)
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
    case lightningSpark, lightningSpark2, flashSpark2, flashSpark3, scoreStrike, floAbsorb
    /// Z Tea's beam's three pieces, and its burst.
    case beam, burst
    /// Two blades meeting.
    case slashClash

    /// The two sparks a hit ball throws, one or the other each time, and the four bolts.
    static let hitSparks: [EnergyEffect] = [.spark, .spark2]
    /// Volta Cola's hits spark with its own two sheets.
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
        case .flashSpark3: "flashspark3"
        case .lightning1: "lightning1"
        case .lightning2: "lightning2"
        case .lightning3: "lightning3"
        case .lightning4: "lightning4"
        case .charge: "esper_charge"
        case .lightningJump: "lightning_jump"
        case .lightningCharge: "lightning_charge"
        case .scoreStrike: "score_strike"
        case .floAbsorb: "flo_absorb"
        case .beam: "beam"
        case .burst: "burst"
        case .slashClash: "slashclash"
        }
    }

    /// Frames and the anchor come from the importer's measurements of the sheet.
    var frameCount: Int { EffectSheets.frames[name] ?? 1 }

    var fps: Double {
        switch self {
        case .charge: 30
        case .scoreStrike, .floAbsorb: 15
        default: 24
        }
    }

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

/// Which way the hooded head faces on a sheet's frames: 0 the plain three-quarter view
/// (`player_hoodheads`), 1 side on and 2 turned further away (`player_hoodheads_v2`'s second and
/// third frames, drawn in the first skin and swapped into the others'). Frames 0-based.
enum HoodView {
    static let count = 3
    static let drawnInSkin = 0
    static let frames: [Animation: [Int: Int]] = [
        .esperSlashFloState: [1: 1, 2: 2, 3: 2, 4: 1],
        .dunk: [0: 1, 1: 1, 2: 1, 3: 1, 4: 1, 5: 1],
        .blast: [3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1],
        .ledge: [0: 1, 1: 1, 2: 1, 3: 2, 4: 1],
        .gunShoot: every(1, of: .gunShoot), .gunShootAir: every(1, of: .gunShootAir), .gunSnipe: every(1, of: .gunSnipe),
        .gunRun: every(1, of: .gunRun), .gunRunShoot: every(1, of: .gunRunShoot),
        .layup: [2: 1, 3: 1, 4: 2, 5: 2, 6: 2, 7: 2, 8: 2],
        .esperSlash: [2: 1, 3: 1, 4: 1],
        .shoot: [2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1],
        .shootAir: [1: 1, 2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 1],
        .throwForward: [4: 1, 5: 2, 6: 2, 7: 1], .throwAir: [4: 1, 5: 2, 6: 2, 7: 1],
    ]
    private static func every(_ view: Int, of animation: Animation) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: (0..<animation.frameCount).map { ($0, view) })
    }
    static func of(_ frame: AnimationFrame) -> Int { frames[frame.animation]?[frame.frame] ?? 0 }
    /// The frames the hooded head is mirrored on, looking back the other way: FloState's snatch
    /// over its step-through, the pivot as it turns.
    static let flipped: [Animation: Set<Int>] = [.snatchFloState: [2], .pivot: [2]]
    static func isFlipped(_ frame: AnimationFrame) -> Bool { flipped[frame.animation]?.contains(frame.frame) ?? false }
}

/// The run, dash and skid-stop dust's place, art pixels ahead of the feet (mirrored with
/// facing) and up, and its scale.
enum DustTuning {
    static func offset(_ effect: Effect) -> CGPoint {
        switch effect {
        case .dustRun3: CGPoint(x: 6, y: 6)
        case .dustDash: CGPoint(x: 10, y: 0)
        case .dustSkid: CGPoint(x: -16, y: 0)
        default: .zero
        }
    }
    static func scale(_ effect: Effect) -> CGFloat { effect == .dustSkid ? 0.25 : 0.5 }
}

/// One-shot sprites: sparks, smoke, the swish, and Blazing Boba's fire and Flash Fizz's
/// flash, painted as they are. Each plays through and removes itself. The jump spark, the
/// smoke and the catch spark are drawn in the player's energy colour.
enum Effect {
    case smoke, jumpSpark, catchSpark, wallJumpSpark
    case fireJump, fireDash, fireWallSpark, fireSkid, fireTrail, fireCharge, fireCharge2, fireExplosion, fireballSummon
    case flashSpark, flashSpark2
    case dustWalk, dustRun, dustRun3, dustDash, dustSkid

    static let inEnergyColour: [Effect] = [.smoke, .jumpSpark, .catchSpark, .dustWalk, .dustRun, .dustRun3, .dustDash, .dustSkid]
    /// Toned no lighter than the energy colour itself: the jump spark, the smoke of the
    /// dash and slide, and the footfalls' dust. The catch spark keeps the paler ramp.
    static let sparkNames: Set<String> = [Effect.smoke.name, Effect.jumpSpark.name, Effect.dustWalk.name, Effect.dustRun.name,
                                          Effect.dustRun3.name, Effect.dustDash.name, Effect.dustSkid.name]

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
        case .dustWalk: "dust_walk"
        case .dustRun: "dust_run"
        case .dustRun3: "dust_run3"
        case .dustDash: "dust_dash"
        case .dustSkid: "dust_skid"
        }
    }

    /// A measured strip's frame count by name, 0 before it's imported.
    static func frameCount(named name: String) -> Int { EffectSheets.frames[name] ?? 0 }

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
        case .smoke, .wallJumpSpark, .dustWalk, .dustRun, .dustRun3, .dustDash, .dustSkid: 12
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
