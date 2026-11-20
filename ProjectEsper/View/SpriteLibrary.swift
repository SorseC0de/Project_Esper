import Accelerate
import CoreGraphics
import CoreImage
import EsperSim
import QuartzCore
import SpriteKit

/// Every frame in the atlas, looked up by the importer's names, drawn as pixels. Player
/// frames come out in that player's look and the ball in its colour, recoloured once each
/// and kept, and the library remembers where the ball and the head sit in each frame.
final class SpriteLibrary {
    static let pixelsPerUnit = 1.6
    /// The sheets' white is the ball where it's the biggest blob of white in the frame and
    /// at least this many pixels; the rest of the white is energy. The importer agrees.
    static let ballMinPixels = 12
    /// Frames whose ball is tucked behind the body, too little of it showing to find: the white
    /// that shows is the ball, and its centre is given, art pixels from the feet, facing right.
    /// The importer's TUCKED_BALLS has to agree.
    static let tuckedBalls: [String: CGPoint] = ["player_spin_ball_3": CGPoint(x: -3.5, y: 20.5), "player_dunk2_2": CGPoint(x: -3.5, y: 21.5)]
    static func tuckedBall(_ frame: AnimationFrame) -> CGPoint? { tuckedBalls["\(frame.animation.rawValue)_\(frame.frame)"] }

    private let atlas = SKTextureAtlas(named: "Sprites")
    /// The atlas's sprites by name, each looked up once and kept: SpriteKit's own lookup compares
    /// the name against every one in the atlas, making temporary strings each time, and a
    /// rebuild asks for thousands, so asked again it held the main thread seconds and its
    /// temporaries ran the TV out of memory. Looked up inside a pool, the temporaries go at once.
    private var atlasNames: Set<String> { SpriteLibrary.atlasNames }
    private static let atlasNames: Set<String> = Set(SKTextureAtlas(named: "Sprites").textureNames.map { ($0 as NSString).deletingPathExtension })
    private var atlasTextures: [String: SKTexture] = [:]
    private let atlasLock = NSLock()
    func atlasTexture(_ name: String) -> SKTexture {
        atlasLock.lock()
        let kept = atlasTextures[name]
        atlasLock.unlock()
        if let kept { return kept }
        let found = autoreleasepool { atlas.textureNamed(name) }
        atlasLock.lock()
        atlasTextures[name] = found
        atlasLock.unlock()
        return found
    }
    private var cache: [String: SKTexture] = [:]
    /// How many textures are kept, for `MemoryTrace`.
    var cachedCount: Int { cache.count }
    /// For `MemoryTrace`: the cache's textures by kind, how many and their MB as pixels, largest
    /// first, and the kept pictures behind them.
    func memoryBreakdown() -> String {
        let kinds = ["_halo", "_head", "_hands", "_armsoverhood", "_armsoverhoodglowing", "_armsoverhoodline", "_overball", "_overballline"]
        var totals: [String: (count: Int, bytes: Double)] = [:]
        func add(_ kind: String, _ texture: SKTexture) {
            let size = texture.size()
            totals[kind, default: (0, 0)].count += 1
            totals[kind, default: (0, 0)].bytes += Double(size.width * size.height * 4)
        }
        for (key, texture) in cache {
            add(kinds.first { key.hasSuffix($0) } ?? (key.hasPrefix("p") || key.contains("_standalone_") ? "piece" : "other"), texture)
        }
        for maps in frameMaps.values {
            add("_map", maps.map)
            add("_coverage", maps.coverage)
            if let thin = maps.thinLine { add("_thinline", thin) }
        }
        var distinct = Set<ObjectIdentifier>(), distinctBytes = 0.0
        for texture in allTextures where distinct.insert(ObjectIdentifier(texture)).inserted {
            distinctBytes += Double(texture.size().width * texture.size().height * 4)
        }
        let kept = keptImages.values.reduce(0.0) { $0 + Double($1.bytesPerRow * $1.height) }
        let parts = totals.sorted { $0.value.bytes > $1.value.bytes }
            .map { String(format: "%@ %d/%.0f MB", $0.key, $0.value.count, $0.value.bytes / 1_048_576) }
        return String(format: "distinct %d/%.0f MB; ", distinct.count, distinctBytes / 1_048_576) + parts.joined(separator: ", ")
            + String(format: "; kept pictures %d/%.0f MB", keptImages.count, kept / 1_048_576)
    }
    /// The pictures behind some of the cache's textures, kept as made, so what draws them again
    /// (the win screen, a hood's line) never reads one back off the GPU, which opens a context and
    /// logs a leak each time. Dropped with the player's cache.
    private var keptImages: [String: CGImage] = [:]
    /// Where the glowing parts sit in each player frame, in art pixels from the feet.
    private var landmarks: [String: [BodyPart: CGPoint]] = [:]
    /// The two players' looks, then the ice look frozen bodies and ice clones are drawn in,
    /// asked for as the player `icePlayer`, then each player's energy form, then each player
    /// turned round: a body mirrored to face left shows its sheet's back limbs in front, so the
    /// sleeves and boots swap over to stay on the same arm and leg; then each side as the
    /// customize screen shows it.
    private var looks = Look.byPlayer + [Look.ice] + Look.byPlayer.map(\.transformed) + Look.byPlayer.map(\.turnedRound) + Look.byPlayer
        + Look.byPlayer
    static let icePlayer = Look.byPlayer.count
    /// A player's energy form, asked for as a player of its own.
    static func transformedPlayer(_ player: Int) -> Int { icePlayer + 1 + player }
    /// A player facing left, asked for as a player of its own.
    static func turnedPlayer(_ player: Int) -> Int { icePlayer + 1 + Look.byPlayer.count + player }
    /// A side as the customize screen shows it, asked for as a player of its own: only what that
    /// screen draws is made in it, so a pick never rebuilds the game's frames.
    static func customizePlayer(_ player: Int) -> Int { icePlayer + 1 + 2 * Look.byPlayer.count + player }
    /// A side as a saved replay's VTV screen shows it, a player of its own like the customize screen's.
    static func replayPlayer(_ player: Int) -> Int { customizePlayer(Look.byPlayer.count) + player }

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
    init() {
        artShaders.setLooks(looks)
    }

    func setLook(_ look: Look, for player: Int) {
        guard look != looks[player] else { return }
        looks[player] = look
        let energyForm = SpriteLibrary.transformedPlayer(player)
        looks[energyForm] = look.transformed
        let turned = SpriteLibrary.turnedPlayer(player)
        looks[turned] = look.turnedRound
        looksChanged()
        dropPlayer(player)
        dropPlayer(energyForm)
        dropPlayer(turned)
        rewarm(player: player)
        rewarm(player: energyForm)
        // Turned round, only where it differs: built ahead, so turning never makes frames.
        if looks[turned] != look { rewarm(player: turned) }
    }

    /// The player gallery's FloState: player 0 in `look` and its energy form in its transformed
    /// self, as `setLook` has them, what it drew in the last look dropped and nothing made ahead.
    func setGalleryLook(_ look: Look) {
        guard look != looks[0] else { return }
        looks[0] = look
        let energyForm = SpriteLibrary.transformedPlayer(0)
        looks[energyForm] = look.transformed
        looksChanged()
        dropPlayer(0)
        dropPlayer(energyForm)
    }

    /// The customize screen's side drawn in `look`, as shown (the second side's turned round):
    /// what it drew in the last look dropped, nothing else made or touched.
    func setCustomizeLook(_ look: Look, for player: Int) {
        let slot = SpriteLibrary.customizePlayer(player)
        guard look != looks[slot] else { return }
        looks[slot] = look
        looksChanged()
        dropPlayer(slot)
    }

    /// A replay's side drawn in `look` for VTV: what it drew in the last look dropped, nothing else made or touched.
    func setReplayLook(_ look: Look, for player: Int) {
        let slot = SpriteLibrary.replayPlayer(player)
        guard look != looks[slot] else { return }
        looks[slot] = look
        looksChanged()
        dropPlayer(slot)
    }

    /// Every player's frames dropped and rebuilt, for a change to how all looks are drawn; the
    /// customize screen's sides dropped, made again as it asks.
    /// How a body's line is drawn. Normal: one pixel, only where a pixel's straight beside the
    /// body, above or below it, never at a corner alone, as drawn by hand. Semibold: one pixel,
    /// corners too (the stepped line). Bold: two pixels, as Normal's grown again.
    /// Settings' PLAYER VISIBILITY picks the in-match players'; everywhere else it's Normal.
    typealias LineStyle = PlayerLineStyle
    /// The style a player slot's line is drawn in: the setting's for those in the match (the
    /// sides, the ice look, FloState's and the turned), Normal for the customize screen's and on.
    static func lineStyle(for player: Int) -> LineStyle {
        player < customizePlayer(0) ? GameSettings.playerVisibility : (customizeLineStyle ?? .normal)
    }
    /// The player gallery's OLD LINE: the customize sides drawn in another style (Semibold, the
    /// line before build 12, corners and all); nil, Normal.
    nonisolated(unsafe) static var customizeLineStyle: LineStyle?
    /// The customize sides' line style changed, their frames dropped to be drawn again in it.
    func setCustomizeLineStyle(_ style: LineStyle?) {
        guard style != SpriteLibrary.customizeLineStyle else { return }
        SpriteLibrary.customizeLineStyle = style
        looksChanged()
        for side in 0..<2 { dropPlayer(SpriteLibrary.customizePlayer(side)) }
    }
    /// The pixels round `mask`, `passes` deep, each pass the pixels next to the last (`LineStyle.reaches`)
    /// where `open` allows: a line round it.
    static func lineRound(_ mask: [Bool], width: Int, height: Int, style: LineStyle, open: (Int) -> Bool) -> [Bool] {
        var inside = mask
        var line = [Bool](repeating: false, count: mask.count)
        for _ in 0..<style.width {
            var grown: [Int] = []
            for y in 0..<height {
                for x in 0..<width where !inside[y * width + x] && open(y * width + x) {
                    let touches = (-1...1).contains { dy in (-1...1).contains { dx in
                        let nx = x + dx, ny = y + dy
                        return style.reaches(dx, dy) && nx >= 0 && ny >= 0 && nx < width && ny < height && inside[ny * width + nx]
                    } }
                    if touches { grown.append(y * width + x) }
                }
            }
            for pixel in grown {
                inside[pixel] = true
                line[pixel] = true
            }
        }
        return line
    }
    /// PLAYER VISIBILITY changed: everything the in-match players are drawn from dropped and made
    /// again in the new style as the launch's warm-up makes it, off the main thread, all of it sent
    /// to the GPU before `completion`, so nothing's first made mid-match; the loading counts told
    /// meanwhile (`onLoading`).
    func reloadMatchLines(players: Int, completion: @escaping () -> Void) {
        for key in cache.keys where key.hasPrefix("hoodline_") && key.contains("_line") { cache[key] = nil }
        for key in keptImages.keys where key.hasPrefix("hoodline_") && key.contains("_line") { keptImages[key] = nil }
        for player in looks.indices where player < SpriteLibrary.customizePlayer(0) { dropPlayer(player) }
        looksChanged()
        warmUp(players: players, completion: completion)
    }

    func redrawPlayers() {
        for player in looks.indices {
            dropPlayer(player)
            if player < SpriteLibrary.customizePlayer(0) { rewarm(player: player) }
        }
    }

    /// The toned sheets beyond the energy effects: a player's particles' and Z Tea's beam charge.
    static let tonedParticleSheets = ["lightning_particle", "lightning_particle2", GameScene.beamChargeSheet]
    private var rewarmGeneration: [Int: Int] = [:]
    private let rewarmQueue = DispatchQueue(label: "SpriteLibrary.rewarm", qos: .userInitiated)
    /// The sheets' frames as read out of the atlas, by name (`sourceImage`).
    nonisolated(unsafe) private var sourceImages: [String: CGImage] = [:]

    /// A sheet frame's picture, read out of this library's own atlas once and kept: the launch's
    /// build reads every player frame before anything's drawn, so a later ask (the customize
    /// screen's figure) never copies one back off the GPU, which on the TV is invalid. Not a
    /// second atlas of its own: each read through one that's never drawn kept a whole page.
    /// `texture`: the frame's own, where the key isn't its name in the atlas (a toned effect's).
    func sourceImage(_ key: String, texture given: SKTexture? = nil) -> CGImage {
        sourceImageLock.lock()
        let kept = sourceImages[key]
        sourceImageLock.unlock()
        if let kept { return kept }
        // Read with the lock let go: the read goes through SpriteKit's renderer, which the main
        // thread may be holding mid-render while it asks for a frame here. Held across it, the two wait on each other.
        // The catalog's own picture of an atlas frame, read straight from the asset catalog: read out of
        // SpriteKit's packed atlas instead, the launch's few hundred took seconds.
        let image: CGImage
        if atlasNames.contains(key), let catalogued = UIImage(named: key)?.cgImage {
            image = catalogued
        } else {
            image = (given ?? (atlasNames.contains(key) ? atlasTexture(key) : SKTexture(imageNamed: key))).cgImage()
        }
        sourceImageLock.lock()
        defer { sourceImageLock.unlock() }
        if let raced = sourceImages[key] { return raced }
        sourceImages[key] = image
        return image
    }
    private let sourceImageLock = NSLock()
    /// Pieces asked for that came out empty (a frame with no front arm), so they aren't made again
    /// every frame; dropped with the player's cache.
    private var emptyPieces: Set<String> = []
    /// Debug: anything made on the main thread while a match is being played, logged with its
    /// time, so what's still first made mid-match can be named. Set by the game scene each frame.
    var reportsMisses = false
    private func reportMiss(_ key: String, since start: Double) {
        guard reportsMisses, DebugUI.enabled, Thread.isMainThread else { return }
        let milliseconds = (CACurrentMediaTime() - start) * 1000
        guard milliseconds >= 1 else { return }
        print(String(format: "made mid-match: %@ %.1f ms", key, milliseconds))
    }

    private func dropPlayer(_ player: Int) {
        if reportsMisses, DebugUI.enabled { print("dropped p\(player)'s pieces") }
        cache = cache.filter { !$0.key.hasPrefix("p\(player)_") }
        // Its frames counted unmade (`maps`): its maps may stay, shared by its shape, but its halos and pieces go.
        landmarks = landmarks.filter { !$0.key.hasPrefix("p\(player)_") }
        keptImages = keptImages.filter { !$0.key.hasPrefix("p\(player)_") }
        portraits = portraits.filter { !$0.key.hasPrefix("p\(player)_") }
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
        LoadTrace.mark("rebuild player \(player) begun, \(pieces) pieces")
        onLoading?(loadingCounts)
    }

    private func reportRebuilding(_ player: Int, generation: Int, made: Int?) {
        guard rewarmGeneration[player] == generation, let entry = rebuilding[player] else { return }
        if let made {
            rebuilding[player]?.made = made
        } else {
            LoadTrace.mark("rebuild player \(player) landed")
            rebuilding[player] = nil
            rebuilt += entry.all
            if rebuilding.isEmpty { rebuilt = 0 }
        }
        onLoading?(loadingCounts)
        if rebuilding.isEmpty, !whenRebuilt.isEmpty {
            let waiting = whenRebuilt
            whenRebuilt = []
            waiting.forEach { $0() }
        }
    }
    /// The launch's rebuilds of anything but the sides' own looks, held till those have landed;
    /// nil once they have.
    private var heldForLaunch: Set<Int>? = []
    /// What waits for every rebuild underway to land: the launch's warm-up.
    private var whenRebuilt: [() -> Void] = []
    /// Work run once every rebuild underway has landed, or now with none: what reads its pieces.
    func afterRebuilds(_ work: @escaping () -> Void) {
        if rebuilding.isEmpty { work() } else { whenRebuilt.append(work) }
    }

    /// The customize screen's hooded-head place, kept between launches by its sliders.
    static var customizeHeadPlace: (nudge: CGPoint, scale: CGFloat) {
        let defaults = UserDefaults.standard
        return (CGPoint(x: defaults.object(forKey: "esper.customize.headX") as? Double ?? 1, y: defaults.object(forKey: "esper.customize.headY") as? Double ?? 1),
                CGFloat(defaults.object(forKey: "esper.customize.headScale") as? Double ?? 1))
    }

    /// Everything drawn in a player's look rebuilt off the main thread after their look
    /// changes, then kept and sent to the GPU, so no frame, head, energy or toned effect is
    /// first made mid-match. Anything asked for before it lands is made as it always was;
    /// a newer change supersedes it.
    private func rewarm(player: Int) {
        // At launch the sides' own looks go first, alone on the cores; the rest wait their turn.
        if let held = heldForLaunch, player >= SpriteLibrary.icePlayer {
            heldForLaunch = held.union([player])
            return
        }
        let look = look(for: player)
        let lineStyle = SpriteLibrary.lineStyle(for: player)
        let generation = (rewarmGeneration[player] ?? 0) + 1
        rewarmGeneration[player] = generation
        // Each frame's maps made only where its shape's aren't yet: another slot's look may share them.
        var frameJobs: [(key: String, frame: AnimationFrame, source: SKTexture, holdsBall: Bool, mapKey: String, mapMade: Bool)] = []
        for animation in Animation.allCases {
            for index in 0..<animation.frameCount {
                let frame = AnimationFrame(animation, index)
                let source = atlasTexture("\(animation.rawValue)_\(index)")
                for (ballAsEnergy, ballLifted) in [(false, false)] + (animation.holdsBall ? [(true, false)] : []) + (SpriteLibrary.liftsBall.contains(animation) ? [(false, true)] : []) {
                    let mapKey = mapKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
                    let mapMade = frameMaps[mapKey] != nil || mapsUnderway.contains(mapKey)
                    if !mapMade { mapsUnderway.insert(mapKey) }
                    frameJobs.append((SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted), frame, source,
                                      (animation.holdsBall && !ballAsEnergy) || ballLifted, mapKey, mapMade))
                }
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
        // The wall spark's, and the dash spark's for a clash's slide.
        for effect in [Effect.fireWallSpark, .fireDash] {
            for index in 0..<effect.frameCount {
                silhouetteJobs.append(("p\(player)_sil_\(effect.name)_\(index)", texture(effect.name, index)))
            }
        }
        // A human's hooded heads, every view plain, in FloState and frozen, with each view's line
        // and face (`warmHoods`); and, for a side, every frame of the
        // win screen's pose (`portrait`), the head placed as the customize screen's sliders have it.
        var hoodJobs: [(key: String, sourceName: String, source: SKTexture, look: Look, ice: Bool, energy: Bool)] = []
        var portraitJobs: [(key: String, name: String, frame: Int, source: SKTexture, view: Int, look: Look)] = []
        let skin = look.dressing.skinTone
        let humanHooded = !look.energyForm && player < SpriteLibrary.icePlayer
        if humanHooded {
            let iceLook = self.look(for: SpriteLibrary.icePlayer)
            for view in 0..<HoodView.count {
                let name = SpriteLibrary.hoodSourceName(view: view, energy: false)
                let source = atlasTexture(name)
                let floStateName = SpriteLibrary.hoodSourceName(view: view, energy: true)
                hoodJobs.append((SpriteLibrary.hoodHeadKey(skin: skin, player: player, energy: false, view: view), name, source, look, false, false))
                hoodJobs.append((SpriteLibrary.hoodHeadKey(skin: skin, player: player, energy: true, view: view), floStateName, atlasTexture(floStateName), look, false, true))
                hoodJobs.append((SpriteLibrary.hoodHeadKey(skin: skin, player: SpriteLibrary.icePlayer, energy: false, view: view), name, source, iceLook, true, false))
            }
            if player < Look.byPlayer.count {
                let place = SpriteLibrary.customizeHeadPlace
                for pose in WinPose.winning.map(\.animation) {
                    for frame in 0..<pose.frameCount {
                        let sheet = AnimationFrame(pose, frame)
                        portraitJobs.append((SpriteLibrary.portraitKey(pose.rawValue, frame: frame, player: player, headNudge: place.nudge, headScale: place.scale),
                                             pose.rawValue, frame, texture(pose.rawValue, frame), HoodView.of(sheet), SpriteLibrary.look(look, for: sheet)))
                    }
                }
            }
        }
        let drawnForTexture = atlasTexture("\(GameScene.hoodDrawnFor.animation.rawValue)_\(GameScene.hoodDrawnFor.frame)")
        let headPlace = SpriteLibrary.customizeHeadPlace
        // Counted as pieces made, the last one the textures reaching the GPU.
        beginRebuilding(player, pieces: frameJobs.count + tonedJobs.count + silhouetteJobs.count + hoodJobs.count + portraitJobs.count + 1)
        rewarmQueue.async { [weak self] in
            guard let self else { return }
            var built: [String: SKTexture] = [:]
            var builtLandmarks: [String: [BodyPart: CGPoint]] = [:]
            var builtEmpty: [String] = []
            var builtTops: [String: [BodyPart: CGPoint]] = [:]
            var builtImages: [String: CGImage] = [:]
            var builtHoods: [String: (drawn: CGImage, hood: CGImage, face: CGImage)] = [:]
            var builtPortraits: [String: Portrait] = [:]
            var builtMaps: [String: PlayerFrameMaps] = [:]
            var made = 0
            let lock = NSLock()
            /// One piece made, kept under the lock: the pieces are made on every core at once.
            func keep(_ textures: [String: SKTexture], landmarks: (key: String, marks: [BodyPart: CGPoint])? = nil, empty: [String] = [],
                      tops: (key: String, marks: [BodyPart: CGPoint])? = nil, images: [String: CGImage] = [:], portrait: (key: String, made: Portrait)? = nil,
                      maps: (key: String, made: PlayerFrameMaps)? = nil) {
                lock.lock()
                if let maps { builtMaps[maps.key] = maps.made }
                builtImages.merge(images) { _, new in new }
                if let portrait { builtPortraits[portrait.key] = portrait.made }
                if let tops { builtTops[tops.key] = tops.marks }
                built.merge(textures) { _, new in new }
                builtEmpty += empty
                if let landmarks { builtLandmarks[landmarks.key] = landmarks.marks }
                made += 1
                let so = made
                lock.unlock()
                guard so % SpriteLibrary.loadingReportEvery == 0 else { return }
                DispatchQueue.main.async { self.reportRebuilding(player, generation: generation, made: so) }
            }
            // The sheets' images read out one at a time first, so the cores share nothing of SpriteKit's.
            // And the hood shapes, read out here once rather than first on some core.
            _ = (SpriteLibrary.plainHoodShape, SpriteLibrary.turnedHoodShapes, SpriteLibrary.hoodDrawnForHead)
            // Each sheet frame read out of the atlas once and kept for every look's rebuild, not
            // once a look: each read logs a context leak, and the launch runs several.
            func source(_ key: String, _ texture: SKTexture) -> CGImage {
                self.sourceImage(key, texture: texture)
            }
            // Each phase's wall time, for the launch's [LOAD] lines.
            var phaseStart = CACurrentMediaTime()
            var phases: [String] = []
            func phaseDone(_ name: String) {
                let now = CACurrentMediaTime()
                phases.append(String(format: "%@ %.0f", name, (now - phaseStart) * 1000))
                phaseStart = now
            }
            let frameSources = frameJobs.map { source("\($0.frame.animation.rawValue)_\($0.frame.frame)", $0.source) }
            let tonedSources = tonedJobs.map { source(String($0.key.split(separator: "_", maxSplits: 2).last ?? ""), $0.source) }
            let silhouetteSources = silhouetteJobs.map { source(String($0.key.split(separator: "_", maxSplits: 2).last ?? ""), $0.source) }
            phaseDone("sources")
            let mapsToMake = frameJobs.filter { !$0.mapMade }.count
            DispatchQueue.concurrentPerform(iterations: frameJobs.count) { index in
                let job = frameJobs[index]
                let frameMade = self.makeFrame(job.frame, source: frameSources[index], look: look, holdsBall: job.holdsBall, lineStyle: lineStyle,
                                               makesMap: !job.mapMade, key: job.key)
                // The limbs' tops too, the same for every look, where the cubes come off.
                let size = job.frame.animation.pixelSize, width = job.frame.animation.pixelWidth
                let tops = SpriteLibrary.partTops(frameSources[index]).mapValues { top in
                    CGPoint(x: top.x - width / 2, y: size - top.y - job.frame.animation.feetFromBottom)
                }
                keep(Dictionary(uniqueKeysWithValues: frameMade.textures.map { (job.key + $0.key, $0.value) }), landmarks: (job.key, frameMade.landmarks),
                     empty: frameMade.empty.map { job.key + $0 }, tops: ("\(job.frame.animation.rawValue)_\(job.frame.frame)", tops),
                     images: Dictionary(uniqueKeysWithValues: frameMade.images.map { (job.key + $0.key, $0.value) }),
                     maps: frameMade.maps.map { (job.mapKey, $0) })
            }
            phaseDone("frames(\(frameJobs.count), \(mapsToMake) maps)")
            DispatchQueue.concurrentPerform(iterations: tonedJobs.count) { index in
                keep([tonedJobs[index].key: self.makeToned(image: tonedSources[index], look: look, capped: tonedJobs[index].capped)])
            }
            DispatchQueue.concurrentPerform(iterations: silhouetteJobs.count) { index in
                keep([silhouetteJobs[index].key: self.makeSilhouette(image: silhouetteSources[index], look: look)])
            }
            phaseDone("toned+silhouettes(\(tonedJobs.count + silhouetteJobs.count))")
            // The hoods, then each view's line and face from its plain head, then the portraits wearing them.
            let hoodSources = hoodJobs.map { source($0.sourceName, $0.source) }
            for (job, image) in zip(hoodJobs, hoodSources) {
                if let head = self.makeHoodHead(source: image, skin: skin, look: job.look, ice: job.ice, energy: job.energy) {
                    builtHoods[job.key] = head
                }
                keep([:])
            }
            var hoodViews: [Int: (drawn: CGImage, hood: CGImage, line: CGImage?)] = [:]
            if humanHooded {
                for view in 0..<HoodView.count {
                    guard let head = builtHoods[SpriteLibrary.hoodHeadKey(skin: skin, player: player, energy: false, view: view)] else { continue }
                    // The win screen's portraits' line Normal; play's in the in-match style.
                    let line = self.makeHoodLine(drawn: head.drawn, style: .normal)
                    hoodViews[view] = (head.drawn, head.hood, line)
                    if let line { builtImages[SpriteLibrary.hoodLineKey(skin: skin, view: view, energy: false, style: .normal)] = line }
                    if lineStyle != .normal, let matchLine = self.makeHoodLine(drawn: head.drawn, style: lineStyle) {
                        builtImages[SpriteLibrary.hoodLineKey(skin: skin, view: view, energy: false, style: lineStyle)] = matchLine
                    }
                    if let face = self.makeHoodFace(drawn: head.drawn, face: head.face) { builtImages["p\(player)_hoodface_\(skin)_\(view)"] = face }
                    if let floState = builtHoods[SpriteLibrary.hoodHeadKey(skin: skin, player: player, energy: true, view: view)],
                       let floStateLine = self.makeHoodLine(drawn: floState.drawn, style: lineStyle) {
                        builtImages[SpriteLibrary.hoodLineKey(skin: skin, view: view, energy: true, style: lineStyle)] = floStateLine
                    }
                }
            }
            phaseDone("hoods(\(hoodJobs.count))")
            let portraitSources = portraitJobs.map { source("\($0.name)_\($0.frame)", $0.source) }
            let drawnForSource = portraitJobs.isEmpty ? nil : source("\(GameScene.hoodDrawnFor.animation.rawValue)_\(GameScene.hoodDrawnFor.frame)", drawnForTexture)
            DispatchQueue.concurrentPerform(iterations: portraitJobs.count) { index in
                let job = portraitJobs[index]
                guard let drawnForSource, let made = self.makePortrait(job.name, frame: job.frame, look: job.look, source: portraitSources[index], drawnFor: drawnForSource,
                                                                      hood: hoodViews[job.view], headNudge: headPlace.nudge, headScale: headPlace.scale,
                                                                      holdsBall: WinPose.taunt.holdsBall) else { keep([:]); return }
                keep([:], portrait: (job.key, made))
            }
            phaseDone("portraits(\(portraitJobs.count))")
            let workerPhases = phases.joined(separator: ", ")
            let landing = CACurrentMediaTime()
            DispatchQueue.main.async {
                LoadTrace.mark(String(format: "rebuild player %d made: %@; waited %.0f ms for the main thread", player, workerPhases,
                                      (CACurrentMediaTime() - landing) * 1000))
                // Its maps kept whatever became of its look: other slots' rebuilds of the shape left them to this one.
                for (key, maps) in builtMaps where self.frameMaps[key] == nil { self.frameMaps[key] = maps }
                self.mapsUnderway.subtract(frameJobs.filter { !$0.mapMade }.map(\.mapKey))
                guard self.rewarmGeneration[player] == generation else { return }
                // Its look changed since without a new rebuild (a turned look no longer differing): nothing to keep.
                guard self.look(for: player) == look else {
                    self.reportRebuilding(player, generation: generation, made: nil)
                    return
                }
                for (key, texture) in built where self.cache[key] == nil { self.cache[key] = texture }
                for (key, marks) in builtLandmarks where self.landmarks[key] == nil { self.landmarks[key] = marks }
                self.emptyPieces.formUnion(builtEmpty)
                for (key, tops) in builtTops where self.partTops[key] == nil { self.partTops[key] = tops }
                for (key, image) in builtImages where self.keptImages[key] == nil {
                    self.keptImages[key] = image
                    // The hood's lines and faces are textures of their own too.
                    if key.hasPrefix("hoodline_") || key.contains("_hoodface_"), self.cache[key] == nil {
                        let texture = SKTexture(cgImage: image)
                        texture.filteringMode = .nearest
                        self.cache[key] = texture
                    }
                }
                for (key, head) in builtHoods where self.cache[key] == nil { self.keep(hoodHead: head, key: key) }
                for (key, portrait) in builtPortraits where self.portraits[key] == nil { self.keep(portrait: portrait, key: key) }
                SKTexture.preload(Array(built.values) + builtMaps.values.flatMap(\.textures) + self.warmHoods(player: player)) {
                    DispatchQueue.main.async { self.reportRebuilding(player, generation: generation, made: nil) }
                }
            }
        }
    }

    /// A non-player frame, from the atlas or, like the ball, from the catalog's root.
    func texture(_ name: String, _ frame: Int) -> SKTexture {
        let key = "\(name)_\(frame)"
        if let texture = cache[key] { return texture }
        let texture = atlasNames.contains(key) ? atlasTexture(key) : SKTexture(imageNamed: key)
        texture.filteringMode = .nearest
        cache[key] = texture
        return texture
    }

    /// The ball's three frames, cut from the 24x8 picture in the catalog's root, and the
    /// frozen ball's from its own.
    static let basketballFrameCount = 3
    private(set) lazy var basketballFrames: [SKTexture] = SpriteLibrary.cutBall("Basketball")
    private(set) lazy var basketballIceFrames: [SKTexture] = SpriteLibrary.cutBall("BasketballIce")
    /// Breaker Ball's balls: the basketball's two lightest shades in the energy's
    /// `breakerBallTones` light, its middle in the middle, its two darkest in the dark.
    private(set) lazy var breakerBallFrames: [EnergyColour: [SKTexture]] = Dictionary(uniqueKeysWithValues: EnergyColour.allCases.map { colour in
        let tones = colour.breakerBallTones
        let swaps: [RGB: RGB] = [0xFFA214: tones.light, 0xED7614: tones.light, 0xC64524: tones.middle, 0x8A4836: tones.dark, 0x5D2C28: tones.dark]
        return (colour, basketballFrames.map { SpriteLibrary.swapped($0, swaps) })
    })
    /// A player's Breaker Ball look, in their energy.
    func breakerBallLook(for player: Int) -> BallLook? {
        guard let colour = EnergyColour.withGlow(look(for: player).glow), breakerBallFrames[colour] != nil else { return nil }
        return .breaker(colour)
    }
    /// Blazing Boba's fireball: the basketball's every shade a step up the fire ramp, its seams
    /// with its shadow and its outline the red under them, so it reads hot rather than as the ball.
    private(set) lazy var basketballFireFrames: [SKTexture] = basketballFrames.map { frame in
        SpriteLibrary.swapped(frame, [0xFFA214: PixelPalette.fire[0], 0xED7614: PixelPalette.fire[1], 0xC64524: PixelPalette.fire[2],
                                      0x8A4836: PixelPalette.fire[2], 0x5D2C28: PixelPalette.fire[3]])
    }

    /// A ball frame with its colours swapped, the rest as it was.
    private static func swapped(_ frame: SKTexture, _ swaps: [RGB: RGB]) -> SKTexture {
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
    /// draws the ball it took, for a snatch that took none; the Spin Move's, for Gale Ale's
    /// level-two double jump, which spins on it with or without the ball.
    static let liftsBall: Set<Animation> = [.snatchFloState, .spinBall]

    // MARK: The sheet's own ball

    /// The sheets whose ball is read off each frame as drawn. Where it's the plain round ball, the
    /// ball's drawn there with what the sheet puts in front of it drawn again over it; where the
    /// sheet reshapes it, its white is painted from the ball's art, stretched to fit.
    static let sheetBallSheets: Set<Animation> = [.taunt, .dribbleIdle, .dribbleWalk, .dribbleRun, .spinDunk, .idleBallFloState, .shoot, .shootAir, .tauntFloState]
    /// White off the biggest blob joins the ball while the two together stay this many pixels
    /// across and high: the ball split by a leg in front of it, not a streak beside it.
    static let sheetBallReach = 9

    /// A frame's ball as the sheet draws it, on the canvas, counted from the top left: its pixels
    /// and their bounds; where the round ball fits over them whole, its top left (nil where the
    /// sheet reshapes it); and the sheet's pixels inside the round ball that aren't it, in front of it.
    struct SheetBall {
        let pixels: Set<Int>
        let canvasWidth: Int
        let bounds: (x: Int, y: Int, width: Int, height: Int)
        let roundAt: (x: Int, y: Int)?
        let covering: [Int]
    }

    /// The round ball's shape, its first frame's pixels, from the top left.
    static let roundBall: (mask: [Bool], side: Int) = {
        guard let art = UIImage(named: "Basketball")?.cgImage?.cropping(to: CGRect(x: 0, y: 0, width: 8, height: 8)),
              let (context, pixels) = canvas(width: art.width, height: art.height) else { return ([Bool](repeating: true, count: 64), 8) }
        context.draw(art, in: CGRect(x: 0, y: 0, width: art.width, height: art.height))
        return ((0..<(art.width * art.height)).map { pixels[$0 * 4 + 3] > 0 }, art.width)
    }()

    nonisolated(unsafe) private static var sheetBalls: [String: SheetBall?] = [:]
    private static let sheetBallLock = NSLock()
    static func sheetBall(_ frame: AnimationFrame, source: CGImage) -> SheetBall? {
        guard sheetBallSheets.contains(frame.animation) else { return nil }
        let key = "\(frame.animation.rawValue)_\(frame.frame)"
        sheetBallLock.lock()
        if let made = sheetBalls[key] {
            sheetBallLock.unlock()
            return made
        }
        sheetBallLock.unlock()
        let made = findSheetBall(source)
        sheetBallLock.lock()
        sheetBalls[key] = made
        sheetBallLock.unlock()
        return made
    }

    /// The round ball's place over a frame's white on every sheet that holds the ball, so the ball in
    /// hand sits on the art's pixels and what the sheet draws in front of it is drawn again over it:
    /// the sheet's own ball where the sheet's ball is read off the frame, else the round fit, nil
    /// where the round ball doesn't fit the white.
    nonisolated(unsafe) private static var fittedBalls: [String: SheetBall?] = [:]
    static func fittedBall(_ frame: AnimationFrame, source: CGImage) -> SheetBall? {
        if sheetBallSheets.contains(frame.animation) { return sheetBall(frame, source: source) }
        guard frame.animation.holdsBall else { return nil }
        let key = "\(frame.animation.rawValue)_\(frame.frame)"
        sheetBallLock.lock()
        if let made = fittedBalls[key] {
            sheetBallLock.unlock()
            return made
        }
        sheetBallLock.unlock()
        let found = findSheetBall(source)
        let made = found?.roundAt != nil ? found : nil
        sheetBallLock.lock()
        fittedBalls[key] = made
        sheetBallLock.unlock()
        return made
    }

    private static func findSheetBall(_ source: CGImage) -> SheetBall? {
        let width = source.width, height = source.height, count = width * height
        guard let (context, pixels) = canvas(width: width, height: height) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let opaque = (0..<count).map { pixels[$0 * 4 + 3] == 255 }
        let white = (0..<count).map { pixel in
            opaque[pixel] && BodyPart.owning(RGB(pixels[pixel * 4]) << 16 | RGB(pixels[pixel * 4 + 1]) << 8 | RGB(pixels[pixel * 4 + 2])) == .ball
        }
        // The white in 8-connected blobs, biggest first.
        var label = [Int](repeating: -1, count: count)
        var blobs: [[Int]] = []
        for start in 0..<count where white[start] && label[start] < 0 {
            var blob: [Int] = []
            var stack = [start]
            label[start] = blobs.count
            while let pixel = stack.popLast() {
                blob.append(pixel)
                let x = pixel % width, y = pixel / width
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let neighbour = ny * width + nx
                        if white[neighbour], label[neighbour] < 0 {
                            label[neighbour] = blobs.count
                            stack.append(neighbour)
                        }
                    }
                }
            }
            blobs.append(blob)
        }
        blobs.sort { $0.count > $1.count }
        guard let biggest = blobs.first, biggest.count >= ballMinPixels else { return nil }
        func bounds(_ pixels: [Int]) -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
            pixels.reduce((Int.max, Int.max, Int.min, Int.min)) { box, pixel in
                (min(box.0, pixel % width), min(box.1, pixel / width), max(box.2, pixel % width), max(box.3, pixel / width))
            }
        }
        var ball = biggest
        for blob in blobs.dropFirst() {
            let joined = bounds(ball + blob)
            if joined.maxX - joined.minX < sheetBallReach, joined.maxY - joined.minY < sheetBallReach { ball += blob }
        }
        let box = bounds(ball)
        // The round ball's place over it whole, nearest its middle, where every pixel of the round
        // ball is the sheet's white or something in front of it: a squash smaller than it isn't it.
        let side = roundBall.side
        let middleX = ball.reduce(0.0) { $0 + Double($1 % width) + 0.5 } / Double(ball.count)
        let middleY = ball.reduce(0.0) { $0 + Double($1 / width) + 0.5 } / Double(ball.count)
        var roundAt: (x: Int, y: Int)?
        var nearest = Double.infinity
        if box.maxX - box.minX < side, box.maxY - box.minY < side {
            for y in (box.maxY - side + 1)...box.minY {
                for x in (box.maxX - side + 1)...box.minX {
                    let whole = (0..<(side * side)).allSatisfy { spot in
                        let spotX = x + spot % side, spotY = y + spot / side
                        return !roundBall.mask[spot] || (spotX >= 0 && spotY >= 0 && spotX < width && spotY < height && opaque[spotY * width + spotX])
                    }
                    let fits = whole && ball.allSatisfy { roundBall.mask[(($0 / width) - y) * side + ($0 % width) - x] }
                    let distance = hypot(Double(x + side / 2) - middleX, Double(y + side / 2) - middleY)
                    if fits, distance < nearest {
                        nearest = distance
                        roundAt = (x, y)
                    }
                }
            }
        }
        let pixelSet = Set(ball)
        var covering: [Int] = []
        if let roundAt {
            for my in 0..<side {
                for mx in 0..<side where roundBall.mask[my * side + mx] {
                    let x = roundAt.x + mx, y = roundAt.y + my
                    guard x >= 0, y >= 0, x < width, y < height else { continue }
                    let pixel = y * width + x
                    if opaque[pixel], !pixelSet.contains(pixel) { covering.append(pixel) }
                }
            }
        }
        return SheetBall(pixels: pixelSet, canvasWidth: width,
                         bounds: (box.minX, box.minY, box.maxX - box.minX + 1, box.maxY - box.minY + 1), roundAt: roundAt, covering: covering)
    }

    /// The painted ball's picture, its bounds made even each way so its middle sits on a pixel's edge.
    static func paintedBallSize(_ ball: SheetBall) -> (width: Int, height: Int) {
        (ball.bounds.width + ball.bounds.width % 2, ball.bounds.height + ball.bounds.height % 2)
    }

    /// Where a frame's ball sits, art pixels from the feet, facing right: the round ball's middle,
    /// or the painted one's.
    static func sheetBallCentre(_ ball: SheetBall, in frame: AnimationFrame) -> CGPoint {
        let side = CGFloat(roundBall.side)
        let painted = paintedBallSize(ball)
        let middle = ball.roundAt.map { CGPoint(x: CGFloat($0.x) + side / 2, y: CGFloat($0.y) + side / 2) }
            ?? CGPoint(x: CGFloat(ball.bounds.x) + CGFloat(painted.width) / 2, y: CGFloat(ball.bounds.y) + CGFloat(painted.height) / 2)
        return CGPoint(x: middle.x - frame.animation.pixelWidth / 2, y: frame.animation.pixelSize - middle.y - frame.animation.feetFromBottom)
    }

    /// A reshaped ball's white painted from one of the ball's frames, the art stretched over its
    /// bounds; a pixel the stretch puts off the round art takes the nearest of it.
    static func paintBall(_ ball: SheetBall, art: CGImage) -> CGImage? {
        let side = art.width
        guard art.height == side, let (artContext, artPixels) = canvas(width: side, height: side) else { return nil }
        artContext.draw(art, in: CGRect(x: 0, y: 0, width: side, height: side))
        let filled = (0..<(side * side)).filter { artPixels[$0 * 4 + 3] > 0 }
        guard !filled.isEmpty else { return nil }
        let size = paintedBallSize(ball)
        guard let (context, pixels) = canvas(width: size.width, height: size.height) else { return nil }
        for pixel in ball.pixels {
            let x = pixel % ball.canvasWidth - ball.bounds.x, y = pixel / ball.canvasWidth - ball.bounds.y
            let u = x * side / ball.bounds.width, v = y * side / ball.bounds.height
            var from = v * side + u
            if artPixels[from * 4 + 3] == 0 {
                from = filled.min { hypot(Double($0 % side - u), Double($0 / side - v)) < hypot(Double($1 % side - u), Double($1 / side - v)) }!
            }
            for channel in 0..<4 { pixels[(y * size.width + x) * 4 + channel] = artPixels[from * 4 + channel] }
        }
        return context.makeImage()
    }

    /// Only `pixels` of a picture on the sheet's canvas: what the sheet draws in front of its ball.
    static func picked(_ image: CGImage, pixels chosen: [Int]) -> CGImage? {
        let width = image.width, height = image.height
        guard !chosen.isEmpty, let (sourceContext, sourcePixels) = canvas(width: width, height: height),
              let (context, pixels) = canvas(width: width, height: height) else { return nil }
        sourceContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var any = false
        for pixel in chosen where pixel < width * height && sourcePixels[pixel * 4 + 3] > 0 {
            for channel in 0..<4 { pixels[pixel * 4 + channel] = sourcePixels[pixel * 4 + channel] }
            any = true
        }
        return any ? context.makeImage() : nil
    }

    /// The ball in hand's look: the basketball, Blazing Boba's fireball, or frozen.
    enum BallLook: Hashable {
        case plain, fire, ice, breaker(EnergyColour)
        static let unbroken: [BallLook] = [.plain, .fire, .ice]
    }
    func ballFrames(_ look: BallLook) -> [SKTexture] {
        switch look {
        case .plain: basketballFrames
        case .fire: basketballFireFrames
        case .ice: basketballIceFrames
        case .breaker(let colour): breakerBallFrames[colour] ?? basketballFrames
        }
    }

    /// A reshaped frame's ball painted in a look and one of the ball's spin frames; nil where the
    /// frame's ball is the round one.
    func paintedBallTexture(_ frame: AnimationFrame, look: BallLook, spin: Int) -> SKTexture? {
        let key = "paintedball_\(frame.animation.rawValue)_\(frame.frame)_\(look)_\(spin)"
        if let made = cache[key] { return made }
        guard !emptyPieces.contains(key) else { return nil }
        guard let ball = SpriteLibrary.sheetBall(frame, source: sourceImage("\(frame.animation.rawValue)_\(frame.frame)")), ball.roundAt == nil,
              let image = SpriteLibrary.paintBall(ball, art: ballPicture(look, spin: spin)) else {
            emptyPieces.insert(key)
            return nil
        }
        let made = SKTexture(cgImage: image)
        made.filteringMode = .nearest
        cache[key] = made
        keptImages[key] = image
        return made
    }

    /// A dribbled sheet's round ball, and FloState's floating one, takes the ball's frames in turn, one per frame it appears on,
    /// round again after the last, except a last appearance that would match the loop's first takes
    /// the second: this frame's, or nil where its ball isn't the round one.
    func roundBallSpin(_ frame: AnimationFrame) -> Int? {
        SpriteLibrary.roundBallSpin(frame) { self.sourceImage("\($0.animation.rawValue)_\($0.frame)") }
    }
    static func roundBallSpin(_ frame: AnimationFrame, source: (AnimationFrame) -> CGImage) -> Int? {
        guard Animation.dribbles.contains(frame.animation) || frame.animation == .taunt || frame.animation == .idleBallFloState else { return nil }
        func round(_ index: Int) -> Bool {
            let sheet = AnimationFrame(frame.animation, index)
            return sheetBall(sheet, source: source(sheet))?.roundAt != nil
        }
        guard round(frame.frame) else { return nil }
        let appearance = (0..<frame.frame).filter(round).count
        let appearances = (0..<frame.animation.frameCount).filter(round).count
        let spin = appearance % basketballFrameCount
        return appearances > 1 && appearance == appearances - 1 && spin == 0 ? 1 : spin
    }

    /// The sheets whose ball is painted on a layer of their own, in the ball's tones, and that layer.
    static let ballLayers: [Animation: String] = [.tauntFloState: "player_taunt2_ball"]

    /// A ball layer's frame in a look: each of the ball's tones swapped for the one the look's ball
    /// has in its place.
    /// `paintedBallTexture`'s picture as made, never read back off the GPU.
    func paintedBallPicture(_ frame: AnimationFrame, look: BallLook, spin: Int) -> CGImage? {
        guard paintedBallTexture(frame, look: look, spin: spin) != nil else { return nil }
        return keptImages["paintedball_\(frame.animation.rawValue)_\(frame.frame)_\(look)_\(spin)"]
    }

    /// A ball frame's picture, read once and kept: a read back off the GPU logs and allocates every time.
    func ballPicture(_ look: BallLook, spin: Int) -> CGImage {
        let key = "ballpicture_\(look)_\(spin)"
        if let kept = keptImages[key] { return kept }
        let picture = ballFrames(look)[spin].cgImage()
        keptImages[key] = picture
        return picture
    }

    func ballLayerTexture(_ sheet: String, _ frame: Int, look: BallLook) -> SKTexture {
        let key = "balllayer_\(sheet)_\(frame)_\(look)"
        if let made = cache[key] { return made }
        let painted = texture(sheet, frame)
        let made = look == .plain ? painted : SpriteLibrary.swapped(painted, ballToneSwaps(look))
        cache[key] = made
        return made
    }

    /// The aura round a ball layer's ball, held by energy rather than a hand: its silhouette in white,
    /// blurred `ballAuraBlur` art pixels, on the layer's cell padded `ballAuraPad` art pixels each side,
    /// `ballAuraResolution` texels an art pixel so the blur is smooth. The node colours it in the energy.
    static let ballAuraBlur: CGFloat = 2
    static let ballAuraStrength: CGFloat = 0.8
    static let ballAuraPad = 6
    static let ballAuraResolution = 4
    func ballLayerAura(_ sheet: String, _ frame: Int) -> SKTexture? {
        let key = "ballaura_\(sheet)_\(frame)"
        if let made = cache[key] { return made }
        guard let image = SpriteLibrary.ballAuraImage(sourceImage("\(sheet)_\(frame)")) else { return nil }
        let made = SKTexture(cgImage: image)
        made.filteringMode = .linear
        cache[key] = made
        return made
    }

    private static let auraContext = CIContext()
    static func ballAuraImage(_ layer: CGImage) -> CGImage? {
        let resolution = ballAuraResolution
        let width = (layer.width + ballAuraPad * 2) * resolution, height = (layer.height + ballAuraPad * 2) * resolution
        guard let (context, _) = canvas(width: width, height: height) else { return nil }
        let cell = CGRect(x: ballAuraPad * resolution, y: ballAuraPad * resolution, width: layer.width * resolution, height: layer.height * resolution)
        context.interpolationQuality = .none
        context.draw(layer, in: cell)
        context.setBlendMode(.sourceIn)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let silhouette = context.makeImage() else { return nil }
        let source = CIImage(cgImage: silhouette)
        let blurred = source.applyingGaussianBlur(sigma: Double(ballAuraBlur) * Double(resolution))
        return auraContext.createCGImage(blurred, from: source.extent)
    }

    /// A player's halo (`GlowSettings.playerHalo`): what glows, blurred `CustomizeArt.glowPixels` art
    /// pixels as the customize screen blurs it, with what glows itself cut out, so the halo lands round
    /// it and its own tones stay as painted. On the canvas padded `haloPad` art pixels each side, at
    /// `haloResolution` texels an art pixel so the blur is smooth.
    static let haloPad = 8
    static let haloResolution = 2
    static func haloImage(_ glowing: CGImage) -> CGImage? {
        let resolution = haloResolution
        let width = (glowing.width + haloPad * 2) * resolution, height = (glowing.height + haloPad * 2) * resolution
        guard let (context, pixels) = canvas(width: width, height: height) else { return nil }
        let cell = CGRect(x: haloPad * resolution, y: haloPad * resolution, width: glowing.width * resolution, height: glowing.height * resolution)
        context.interpolationQuality = .none
        context.draw(glowing, in: cell)
        // Three box blurs, near enough a Gaussian of the customize screen's radius.
        let sigma = Double(CustomizeArt.glowPixels) * Double(resolution)
        let box = UInt32((sqrt(4 * sigma * sigma + 1)).rounded()) | 1
        let rowBytes = width * 4
        guard let scratch = malloc(rowBytes * height) else { return nil }
        defer { free(scratch) }
        var image = vImage_Buffer(data: pixels, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)
        var spare = vImage_Buffer(data: scratch, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)
        for _ in 0..<3 {
            vImageBoxConvolve_ARGB8888(&image, &spare, nil, 0, 0, box, box, nil, vImage_Flags(kvImageEdgeExtend))
            swap(&image, &spare)
        }
        if image.data != UnsafeMutableRawPointer(pixels) { memcpy(pixels, image.data, rowBytes * height) }
        context.setBlendMode(.destinationOut)
        context.draw(glowing, in: cell)
        return context.makeImage()
    }
    /// One texture for pixel-identical pictures: much of what a frame is made into comes out the same in
    /// every look (its masks, its uncoloured lines), and each copy cost its share of the TV's memory.
    /// Held weakly, so a texture goes once nothing uses it; matched on size and two hashes of the pixels.
    nonisolated(unsafe) private static let sharedTextures = NSMapTable<NSString, SKTexture>.strongToWeakObjects()
    private static let sharedTextureLock = NSLock()
    static func sharedTexture(_ image: CGImage) -> SKTexture {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return SKTexture(cgImage: image) }
        let pixels = UnsafeRawBufferPointer(start: bytes, count: CFDataGetLength(data))
        var first = Hasher()
        first.combine(bytes: pixels)
        var second = Hasher()
        second.combine(0x9E37_79B9_7F4A_7C15 as UInt64)
        second.combine(bytes: pixels)
        let key = "\(image.width)x\(image.height)x\(image.bytesPerRow)_\(first.finalize())_\(second.finalize())" as NSString
        sharedTextureLock.lock()
        defer { sharedTextureLock.unlock() }
        if let found = sharedTextures.object(forKey: key) { return found }
        let texture = SKTexture(cgImage: image)
        sharedTextures.setObject(texture, forKey: key)
        return texture
    }

    /// The halo cut to where it shows, a clear texel kept round it so its edge blends as the whole
    /// canvas's would, and where it sits on that canvas (`haloPiece(of:)`): most of the padded canvas
    /// is clear, and the halos were the largest thing the game kept.
    static func haloTexture(_ glowing: CGImage) -> SKTexture? {
        guard let image = haloImage(glowing), let (piece, place) = trimmedHalo(image) else { return nil }
        let texture = SKTexture(cgImage: piece)
        texture.filteringMode = .linear
        haloPieceLock.lock()
        haloPieces.setObject(HaloPiece(canvas: CGSize(width: image.width, height: image.height), place: place), forKey: texture)
        haloPieceLock.unlock()
        return texture
    }

    /// Where a halo's piece sits on its whole canvas, in texels from the canvas's bottom left.
    final class HaloPiece {
        let canvas: CGSize
        let place: CGRect
        init(canvas: CGSize, place: CGRect) {
            self.canvas = canvas
            self.place = place
        }
    }
    /// Made on the rebuild's cores, read on the main thread.
    nonisolated(unsafe) private static let haloPieces = NSMapTable<SKTexture, HaloPiece>.weakToStrongObjects()
    private static let haloPieceLock = NSLock()
    static func haloPiece(of texture: SKTexture) -> HaloPiece {
        haloPieceLock.lock()
        defer { haloPieceLock.unlock() }
        if let piece = haloPieces.object(forKey: texture) { return piece }
        let size = texture.size()
        return HaloPiece(canvas: size, place: CGRect(origin: .zero, size: size))
    }

    /// `image` cut to its painted texels and one clear texel round them, and that piece's place on
    /// it from the bottom left; nil if nothing's painted.
    private static func trimmedHalo(_ image: CGImage) -> (CGImage, CGRect)? {
        let width = image.width, height = image.height
        guard let (context, pixels) = canvas(width: width, height: height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The buffer's rows run top down.
        var left = width, right = -1, top = height, bottom = -1
        for row in 0..<height {
            for column in 0..<width where pixels[(row * width + column) * 4 + 3] != 0 {
                left = min(left, column)
                right = max(right, column)
                top = min(top, row)
                bottom = max(bottom, row)
            }
        }
        guard right >= left, bottom >= top else { return nil }
        left = max(left - 1, 0)
        top = max(top - 1, 0)
        right = min(right + 1, width - 1)
        bottom = min(bottom + 1, height - 1)
        let pieceWidth = right - left + 1, pieceHeight = bottom - top + 1
        // Copied into its own canvas: a cropped image keeps the whole one's pixels alive.
        guard let (pieceContext, piecePixels) = canvas(width: pieceWidth, height: pieceHeight) else { return nil }
        for row in 0..<pieceHeight {
            memcpy(piecePixels + row * pieceWidth * 4, pixels + ((top + row) * width + left) * 4, pieceWidth * 4)
        }
        guard let piece = pieceContext.makeImage() else { return nil }
        return (piece, CGRect(x: left, y: height - 1 - bottom, width: pieceWidth, height: pieceHeight))
    }

    /// A frame's halo, the piece of its canvas padded `haloPad` art pixels that shows (`haloPiece(of:)`); nil where nothing glows.
    func haloTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        return cache[SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_halo"]
    }

    /// A hooded head's halo, its hood's glowing pixels blurred, looked up by the texture the hood shows.
    private let hoodHalos = NSMapTable<SKTexture, SKTexture>.weakToStrongObjects()
    func hoodHalo(for drawn: SKTexture) -> SKTexture? { hoodHalos.object(forKey: drawn) }

    /// Each of the plain ball's tones, and the tone the look's ball most often has at the same pixel.
    private var ballToneSwapsByLook: [BallLook: [RGB: RGB]] = [:]
    private func ballToneSwaps(_ look: BallLook) -> [RGB: RGB] {
        if let known = ballToneSwapsByLook[look] { return known }
        var counts: [RGB: [RGB: Int]] = [:]
        for (plainFrame, lookFrame) in zip(basketballFrames, ballFrames(look)) {
            let lookTones = SpriteLibrary.opaqueTones(lookFrame)
            for (pixel, tone) in SpriteLibrary.opaqueTones(plainFrame) {
                if let lookTone = lookTones[pixel] { counts[tone, default: [:]][lookTone, default: 0] += 1 }
            }
        }
        let swaps = counts.compactMapValues { tally in tally.max { $0.value < $1.value }?.key }
        ballToneSwapsByLook[look] = swaps
        return swaps
    }

    /// A frame's opaque pixels' colours, by pixel index.
    private static func opaqueTones(_ frame: SKTexture) -> [Int: RGB] {
        let picture = frame.cgImage()
        let width = picture.width, height = picture.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else { return [:] }
        context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        var tones: [Int: RGB] = [:]
        for pixel in 0..<(width * height) where pixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            tones[pixel] = RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])
        }
        return tones
    }

    /// Every reshaped ball in every look and spin, made ahead of play; Breaker Ball's in the players' energies too.
    /// The ball layers' frames in every look with them, and their auras.
    func warmPaintedBalls(breakerPlayers: [Int] = []) {
        let looks = BallLook.unbroken + breakerPlayers.compactMap { breakerBallLook(for: $0) }
        for (animation, layer) in SpriteLibrary.ballLayers {
            for index in 0..<animation.frameCount {
                for look in looks { _ = ballLayerTexture(layer, index, look: look) }
                _ = ballLayerAura(layer, index)
            }
        }
        for animation in SpriteLibrary.sheetBallSheets {
            for index in 0..<animation.frameCount {
                for look in looks {
                    for spin in 0..<SpriteLibrary.basketballFrameCount {
                        _ = paintedBallTexture(AnimationFrame(animation, index), look: look, spin: spin)
                    }
                }
            }
        }
    }

    /// A player frame's key in the cache: with `ballAsEnergy` the sheet's whites are all energy,
    /// with `ballLifted` its ball is lifted off and not drawn.
    static func frameKey(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool, ballLifted: Bool) -> String {
        "p\(player)_" + frameName(frame, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }
    static func frameName(_ frame: AnimationFrame, ballAsEnergy: Bool, ballLifted: Bool) -> String {
        "\(frame.animation.rawValue)_\(frame.frame)" + (ballAsEnergy ? "_whole" : "") + (ballLifted ? "_balllifted" : "")
    }

    /// Every frame's maps, by its look's shape and the frame (`mapKey`): one for every slot whose look
    /// has that shape, its colours the slot's own palette's.
    private var frameMaps: [String: PlayerFrameMaps] = [:]
    /// Maps a rebuild underway is making, so another slot's rebuild of the same shape leaves them to it.
    private var mapsUnderway: Set<String> = []
    /// The map shaders and the palette, each slot's look in its block.
    let artShaders = PlayerArtShaders()
    /// Each slot's shape's name, for its maps' keys; dropped as its look or line changes.
    private var shapeNames: [Int: String] = [:]
    private func shapeName(_ player: Int) -> String {
        if let name = shapeNames[player] { return name }
        let name = PlayerMap.ShapeKey(look(for: player), lineStyle: SpriteLibrary.lineStyle(for: player)).name
        shapeNames[player] = name
        return name
    }
    private func mapKey(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool, ballLifted: Bool) -> String {
        shapeName(player) + "|" + SpriteLibrary.frameName(frame, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }
    /// A look changed: the palette made again, and the maps no slot's shape uses any more let go.
    private func looksChanged() {
        shapeNames = [:]
        artShaders.setLooks(looks)
        let shapes = Set(looks.indices.map(shapeName))
        frameMaps = frameMaps.filter { shapes.contains(String($0.key.prefix { $0 != "|" })) }
    }

    /// A player frame in that player's look, without its head or its energy.
    /// With `ballAsEnergy`, a sheet that draws the ball has its whites taken as energy,
    /// ball and all, for a throw made with nothing in hand. With `ballLifted`, the ball the
    /// sheet draws is lifted off and not drawn, for a snatch that took nothing.
    func texture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> PlayerArt {
        PlayerArt(frame: maps(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted), layer: .body, look: player, shaders: artShaders)
    }

    /// A frame's maps in the player's shape, and everything kept of it in their look (its halo, its
    /// pieces, its landmarks): made now if they aren't yet.
    private func maps(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool, ballLifted: Bool) -> PlayerFrameMaps {
        let key = SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        let mapKey = mapKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        if landmarks[key] != nil, let made = frameMaps[mapKey] { return made }
        let missStart = CACurrentMediaTime()
        defer { reportMiss(key, since: missStart) }
        let made = makeFrame(frame, source: sourceImage("\(frame.animation.rawValue)_\(frame.frame)"),
                             look: look(for: player), holdsBall: (frame.animation.holdsBall && !ballAsEnergy) || ballLifted,
                             lineStyle: SpriteLibrary.lineStyle(for: player), makesMap: frameMaps[mapKey] == nil, key: key)
        for (suffix, texture) in made.textures { cache[key + suffix] = texture }
        for suffix in made.empty { emptyPieces.insert(key + suffix) }
        for (suffix, image) in made.images { keptImages[key + suffix] = image }
        landmarks[key] = made.landmarks
        if frameMaps[mapKey] == nil, let maps = made.maps { frameMaps[mapKey] = maps }
        return frameMaps[mapKey]!
    }

    /// One layer of a frame in the player's look, nil where the frame has none.
    private func art(_ layer: PlayerMapShaders.Layer, _ frame: AnimationFrame, player: Int, ballAsEnergy: Bool, ballLifted: Bool) -> PlayerArt? {
        texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted).layer(layer)
    }

    /// The palette row a frame's colours are on (`PlayerRecolour.adjusted`), as `look(_:for:)` adjusts its look.
    static func paletteRow(_ frame: AnimationFrame) -> Int {
        if armColoursSwapped[frame.animation]?.contains(frame.frame) == true { return 1 }
        if armSkinSwapped[frame.animation]?.contains(frame.frame) == true { return 2 }
        if handsLitArmsShaded[frame.animation]?.contains(frame.frame) == true { return 3 }
        return 0
    }

    /// The frames whose arms are drawn the other way round, the front arm behind: the ground
    /// throw's follow-through, 5 on, where the back arm comes forward over the head. Their front
    /// and back arm and hand colours swap.
    static let armColoursSwapped: [Animation: ClosedRange<Int>] = [.throwForward: 4...7]
    /// The frames whose bare arms and hands take each other's skin tone, the sleeves left on their
    /// own arms: the spin turned away, the far arm brought round in front.
    static let armSkinSwapped: [Animation: Set<Int>] = [.spinBall: [2], .spinDunk: [1]]
    /// The frames facing out: both hands in the skin's light tone, the rest of both bare arms in its shadow.
    static let handsLitArmsShaded: [Animation: Set<Int>] = [.spinBall: [1], .spinDunk: [0]]
    static func look(_ look: Look, for frame: AnimationFrame) -> Look {
        var adjusted = look
        if armColoursSwapped[frame.animation]?.contains(frame.frame) == true {
            for (front, back) in [(BodyPart.frontArm, BodyPart.backArm), (.frontHand, .backHand)] {
                let was = adjusted.colours[front]
                adjusted.colours[front] = adjusted.colours[back]
                adjusted.colours[back] = was
            }
        }
        let skinSwapped = armSkinSwapped[frame.animation]?.contains(frame.frame) == true
        let handsLit = handsLitArmsShaded[frame.animation]?.contains(frame.frame) == true
        if skinSwapped || handsLit {
            let skin = look.dressing.skin
            let tone = look.dressing.tone
            for part in [BodyPart.frontArm, .backArm, .frontHand, .backHand] {
                // Only what's showing its skin: a sleeve, or a look that isn't a human's, stays as it is.
                guard let own = skin[part], look.colours[part] == own else { continue }
                let hand = part == .frontHand || part == .backHand
                adjusted.colours[part] = handsLit ? (hand ? tone.front : tone.back) : (part.isBack ? tone.front : tone.back)
            }
        }
        return adjusted
    }

    /// A frame recoloured in the look as play draws it, every layer a picture; with `map`, its map too.
    private func pictures(_ frame: AnimationFrame, source: CGImage, look baseLook: Look, holdsBall: Bool, lineStyle: LineStyle,
                          sheetBall: SheetBall?, map: Bool) -> PlayerRecolour.Layers {
        // A human's frame with its neck filled and its line round the hood, where the hood goes on it.
        let look = SpriteLibrary.look(baseLook, for: frame)
        return PlayerRecolour.recolour(image: source, look: look, holdsBall: holdsBall, detach: true,
                                       tucked: SpriteLibrary.tuckedBall(frame) != nil, ballPixels: sheetBall?.pixels,
                                       hoodShape: SpriteLibrary.hoodShape(skin: look.dressing.skinTone, for: frame, energy: look.energyForm),
                                       hoodNudge: GameScene.headNudge(frame),
                                       // On every frame: a tipped head eases back level over whatever comes next.
                                       bareLine: !look.energyForm, lineStyle: lineStyle, hoodDrawnForHead: SpriteLibrary.hoodDrawnForHead,
                                       ballMinPixels: SpriteLibrary.ballMinPixels,
                                       map: map ? (SpriteLibrary.paletteRow(frame), PlayerMap.palette(baseLook), true) : nil)
    }

    /// A player frame's pictures in the player's look, made now and not kept: for the pieces made
    /// after the frame (`partsTexture`), so nothing's read back off the GPU.
    private func pictures(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool, ballLifted: Bool) -> PlayerRecolour.Layers {
        let source = sourceImage("\(frame.animation.rawValue)_\(frame.frame)")
        let holdsBall = (frame.animation.holdsBall && !ballAsEnergy) || ballLifted
        return pictures(frame, source: source, look: look(for: player), holdsBall: holdsBall, lineStyle: SpriteLibrary.lineStyle(for: player),
                        sheetBall: holdsBall ? SpriteLibrary.sheetBall(frame, source: source) : nil, map: false)
    }

    /// A player frame recoloured in a look: its maps in the look's shape (`makesMap`), and what's kept
    /// in the look itself: its halo, its pieces (the arms over the hood, the hands, what's over the
    /// ball), and where its glowing parts sit. `holdsBall`: the sheet's ball is the ball, lifted off to
    /// be drawn apart, rather than energy. Touches nothing kept, so it can be made off the main thread.
    private func makeFrame(_ frame: AnimationFrame, source: CGImage, look baseLook: Look, holdsBall: Bool, lineStyle: LineStyle, makesMap: Bool, key: String)
        -> (textures: [String: SKTexture], landmarks: [BodyPart: CGPoint], empty: [String], images: [String: CGImage], maps: PlayerFrameMaps?) {
        var madeImages: [String: CGImage] = [:]
        let look = SpriteLibrary.look(baseLook, for: frame)
        let sheetBall = holdsBall ? SpriteLibrary.sheetBall(frame, source: source) : nil
        let fittedBall = holdsBall ? SpriteLibrary.fittedBall(frame, source: source) : nil
        let result = pictures(frame, source: source, look: baseLook, holdsBall: holdsBall, lineStyle: lineStyle, sheetBall: sheetBall, map: makesMap)
        var maps: PlayerFrameMaps?
        if makesMap, let map = result.map {
            if map.faults > 0 { print("PlayerMap: \(key) left \(map.faults) pixels out") }
            maps = PlayerFrameMaps(map, thinLine: look.energyForm ? result.thinOutline : nil)
        }
        var textures: [String: SKTexture] = [:]
        if let glowing = result.glowing, let halo = SpriteLibrary.haloTexture(glowing) { textures["_halo"] = halo }
        if let head = result.head { textures["_head"] = SpriteLibrary.sharedTexture(head) }
        // Web Water's swing arm's sleeve, for the glow's mask: blended as a picture's alpha is.
        if frame.animation == .swingArm, let glowing = result.glowing { textures["_glowingpicture"] = SpriteLibrary.sharedTexture(glowing) }
        // The arms laid over the hood, their glowing parts and their own line, on the frames they
        // cross the head: made with the frame, so none is first made mid-match.
        var empty: [String] = []
        // FloState's look too: its hood is worn, though its look isn't a human's.
        let armsOverHood = GameScene.armPartsOverHood(frame)
        if !armsOverHood.isEmpty {
            let pieces: [(String, CGImage?)] = [
                ("_armsoverhood", SpriteLibrary.partsImage(drawn: result.drawn, source: source, parts: armsOverHood, style: lineStyle)),
                ("_armsoverhoodglowing", result.glowing.flatMap { SpriteLibrary.partsImage(drawn: $0, source: source, parts: armsOverHood, style: lineStyle) }),
                ("_armsoverhoodline", SpriteLibrary.partsLine(source: source, parts: armsOverHood,
                                                              hood: SpriteLibrary.hoodShape(skin: look.dressing.skinTone, for: frame, energy: look.energyForm),
                                                              hoodNudge: GameScene.headNudge(frame), style: lineStyle)),
            ]
            for (suffix, image) in pieces {
                if let image { textures[suffix] = SKTexture(cgImage: image) } else { empty.append(suffix) }
            }
        }
        // Z Tea's blast's arms, both on one sheet: each lined on its own, the back drawn behind the
        // body and the front over it.
        if frame.animation == .blastArms {
            for (suffix, arm) in [("_frontarm", Set<BodyPart>([.frontArm, .frontHand])), ("_backarm", Set<BodyPart>([.backArm, .backHand]))] {
                if let image = SpriteLibrary.partsImage(drawn: result.drawn, source: source, parts: arm, style: lineStyle) {
                    textures[suffix] = SKTexture(cgImage: image)
                } else {
                    empty.append(suffix)
                }
                // Each arm's own share of the frame's line, drawn round it apart.
                if let outline = result.outline, let line = SpriteLibrary.partsImage(drawn: outline, source: source, parts: arm, style: lineStyle) {
                    textures[suffix + "outline"] = SKTexture(cgImage: line)
                } else {
                    empty.append(suffix + "outline")
                }
            }
        }
        // The hands alone, unlined: Z Tea's kept charge breathes them white.
        if let hands = SpriteLibrary.partsImage(drawn: result.drawn, source: source, parts: [.frontHand, .backHand], lined: false) {
            textures["_hands"] = SKTexture(cgImage: hands)
        } else {
            empty.append("_hands")
        }
        // What the sheet draws in front of its round ball, and its line, laid over the ball in hand.
        if let fittedBall, fittedBall.roundAt != nil {
            if let over = SpriteLibrary.picked(result.drawn, pixels: fittedBall.covering) {
                textures["_overball"] = SKTexture(cgImage: over)
                madeImages["_overball"] = over
            }
            if let line = result.outline.flatMap({ SpriteLibrary.picked($0, pixels: fittedBall.covering) }) {
                textures["_overballline"] = SKTexture(cgImage: line)
                madeImages["_overballline"] = line
            }
        }
        for texture in textures.values { texture.filteringMode = .nearest }
        textures["_halo"]?.filteringMode = .linear
        let size = frame.animation.pixelSize, width = frame.animation.pixelWidth
        var landmarks = result.centres.mapValues { centre in
            CGPoint(x: centre.x - width / 2, y: size - centre.y - frame.animation.feetFromBottom)
        }
        if holdsBall, let tucked = SpriteLibrary.tuckedBall(frame) { landmarks[.ball] = tucked }
        if let fittedBall { landmarks[.ball] = SpriteLibrary.sheetBallCentre(fittedBall, in: frame) }
        return (textures, landmarks, empty, madeImages, maps)
    }

    /// A player frame as play draws it, and its line in white, as pictures: for a screen that lays
    /// out a figure of its own (the updates screen's, the gallery's).
    func framePicture(_ frame: AnimationFrame, player: Int) -> CGImage {
        pictures(frame, player: player, ballAsEnergy: false, ballLifted: false).drawn
    }
    func outlinePicture(_ frame: AnimationFrame, player: Int) -> CGImage? {
        pictures(frame, player: player, ballAsEnergy: false, ballLifted: false).outline
    }

    /// What the glow's mask draws for a body with the players' halo off: its glow mask where it has
    /// glowing parts, else the body itself.
    func glowMask(for body: PlayerArt) -> PlayerArt { body.layer(.glowMask) ?? body }

    /// Web Water's swing arm's glowing parts as a picture, for the glow's mask; nil where it has none.
    func glowingPicture(_ frame: AnimationFrame, player: Int) -> SKTexture? {
        _ = maps(frame, player: player, ballAsEnergy: false, ballLifted: false)
        return cache[SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: false, ballLifted: false) + "_glowingpicture"]
    }

    /// The head alone from a player frame, on the same canvas as the body, if the frame has one.
    func headTexture(_ frame: AnimationFrame, player: Int) -> SKTexture? {
        _ = maps(frame, player: player, ballAsEnergy: false, ballLifted: false)
        return cache["p\(player)_\(frame.animation.rawValue)_\(frame.frame)_head"]
    }

    /// The energy alone from a player frame, on the same canvas as the body: the slash's
    /// blade, the skid's puffs, a release's streaks. Toned through the energy ramp's colours, the
    /// node's own (`GameScene.setEnergyRamp`). Nil when the frame has none.
    func energyTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> PlayerArt? {
        art(.energy, frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }

    /// The line round a player frame alone, white, for the node's colour. Nil when the frame has none.
    func outlineTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> PlayerArt? {
        art(.line, frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }

    /// The share of a frame's line round its glowing parts, white; nil where it has none.
    func glowLineTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> PlayerArt? {
        art(.glowLine, frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }

    /// The same without the hood's ring, for a tipped hood that carries its own line; nil where it has none.
    func bareGlowLineTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> PlayerArt? {
        art(.bareGlowLine, frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }

    /// A frame's glowing parts alone, as drawn; nil where it has none.
    func glowingPartsTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> PlayerArt? {
        art(.glowing, frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }

    /// The glowing parts of the arms laid over the hood alone (a sleeve), for K&A's wash: drawn again
    /// unwashed over those arms, as the body's are over the body.
    func armsOverHoodGlowingTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        let key = SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_armsoverhoodglowing"
        if let made = cache[key] { return made }
        let missStart = CACurrentMediaTime()
        defer { reportMiss(key, since: missStart) }
        guard !emptyPieces.contains(key) else { return nil }
        guard let glowing = pictures(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted).glowing,
              let image = SpriteLibrary.partsImage(drawn: glowing, source: sourceImage("\(frame.animation.rawValue)_\(frame.frame)"),
                                                   parts: GameScene.armPartsOverHood(frame), style: SpriteLibrary.lineStyle(for: player)) else {
            emptyPieces.insert(key)
            return nil
        }
        let made = SKTexture(cgImage: image)
        made.filteringMode = .nearest
        cache[key] = made
        return made
    }

    /// The back hand alone, as drawn, on the body's canvas: Breaker Ball's, lit in the energy while it holds its chain.
    func backHandTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        let key = SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_backhand"
        if let made = cache[key] { return made }
        guard !emptyPieces.contains(key) else { return nil }
        let drawn = pictures(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted).drawn
        guard let image = SpriteLibrary.partsImage(drawn: drawn, source: sourceImage("\(frame.animation.rawValue)_\(frame.frame)"),
                                                   parts: [.backHand], lined: false, style: SpriteLibrary.lineStyle(for: player)) else {
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
        let missStart = CACurrentMediaTime()
        defer { reportMiss(key, since: missStart) }
        let headKey = SpriteLibrary.hoodHeadKey(skin: skin, player: player, energy: false, view: view)
        _ = hoodHead(skin: skin, player: player, view: view)
        guard let drawn = keptImages[headKey], let face = keptImages[headKey + "_face"], let image = makeHoodFace(drawn: drawn, face: face) else { return nil }
        let made = SKTexture(cgImage: image)
        made.filteringMode = .nearest
        cache[key] = made
        return made
    }

    /// A hooded head's face alone, as drawn.
    private func makeHoodFace(drawn: CGImage, face: CGImage) -> CGImage? {
        let width = drawn.width, height = drawn.height
        guard face.width == width, face.height == height,
              let (context, pixels) = makeCanvas(width: width, height: height),
              let (maskContext, maskPixels) = makeCanvas(width: width, height: height) else { return nil }
        context.draw(drawn, in: CGRect(x: 0, y: 0, width: width, height: height))
        maskContext.draw(face, in: CGRect(x: 0, y: 0, width: width, height: height))
        for pixel in 0..<(width * height) where maskPixels[pixel * 4 + 3] == 0 {
            for channel in 0..<4 { pixels[pixel * 4 + channel] = 0 }
        }
        return context.makeImage()
    }

    /// The line round a human's frame without the hood's place in it, for a tipped hood that
    /// carries its own line (`hoodLine`); nil for a look with no hood.
    func bareOutlineTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> PlayerArt? {
        guard !look(for: player).energyForm else { return nil }
        return art(.bareLine, frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }

    /// The line round the hooded head alone, in white, on its canvas, a pixel out from it: drawn
    /// with the hood when it tips, under the body, so only what's outside the body shows.
    /// `energy`: FloState's hood, its own shape.
    func hoodLine(skin: Int, view: Int = 0, energy: Bool = false, style: LineStyle = .normal) -> SKTexture? {
        let key = SpriteLibrary.hoodLineKey(skin: skin, view: view, energy: energy, style: style)
        if let made = cache[key] { return made }
        let missStart = CACurrentMediaTime()
        defer { reportMiss(key, since: missStart) }
        let headKey = SpriteLibrary.hoodHeadKey(skin: skin, player: 0, energy: energy, view: view)
        _ = hoodHead(skin: skin, player: 0, energy: energy, view: view)
        guard let drawn = keptImages[headKey], let image = makeHoodLine(drawn: drawn, style: style) else { return nil }
        let made = SKTexture(cgImage: image)
        made.filteringMode = .nearest
        cache[key] = made
        keptImages[key] = image
        return made
    }

    static func hoodLineKey(skin: Int, view: Int, energy: Bool, style: LineStyle) -> String {
        "hoodline_\(skin)_\(view)" + (energy ? "_energy" : "") + style.keyMark
    }

    /// The line round a hooded head's picture, out from it, in white.
    private func makeHoodLine(drawn image: CGImage, style: LineStyle) -> CGImage? {
        let width = image.width, height = image.height
        guard let (context, pixels) = makeCanvas(width: width, height: height),
              let (lineContext, linePixels) = makeCanvas(width: width, height: height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let filled = (0..<(width * height)).map { pixels[$0 * 4 + 3] != 0 }
        let line = SpriteLibrary.lineRound(filled, width: width, height: height, style: style) { _ in true }
        for pixel in line.indices where line[pixel] {
            for channel in 0..<4 { linePixels[pixel * 4 + channel] = 255 }
        }
        return lineContext.makeImage()
    }

    /// The line round a player frame at half its thickness, in white, on a canvas twice as fine: an
    /// energy form's alone, FloState's.
    func thinOutlineTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> PlayerArt? {
        let made = maps(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        return made.thinLine == nil ? nil : PlayerArt(frame: made, layer: nil, look: player, shaders: artShaders)
    }

    /// A human's clothes alone from a player frame, the dark ones and the energy's (the shoes), in
    /// white: the FloState lockout's flash. Nil when the frame shows none.
    func clothesTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> PlayerArt? {
        art(.clothes, frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }

    /// What the sheet draws in front of its round ball (a hand, an arm, a leg) as drawn, on the
    /// body's canvas, and that part's line in white: laid over the ball in hand. Nil where nothing's
    /// in front of it, or the frame's ball isn't the round one.
    func overBallTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        return cache[SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_overball"]
    }

    func overBallLineTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        return cache[SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_overballline"]
    }

    /// The same as pictures, as made.
    func overBallImages(_ frame: AnimationFrame, player: Int) -> (body: CGImage?, line: CGImage?) {
        let key = SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: false, ballLifted: false)
        _ = texture(frame, player: player)
        return (keptImages[key + "_overball"], keptImages[key + "_overballline"])
    }

    /// The hands alone as drawn, unlined, on the body's canvas: made with the frame. Nil with none in it.
    func handsTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        _ = texture(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
        return cache[SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + "_hands"]
    }

    /// The arms `GameScene.armPartsOverHood` names for the frame, as drawn with the line round them,
    /// on the body's canvas: laid over the hooded head where they cross it. Nil with none in the frame.
    func armsOverHoodTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        partsTexture(frame, player: player, parts: GameScene.armPartsOverHood(frame), suffix: "_armsoverhood", ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }

    /// The sheet's front arm alone (its arm and hand) as drawn with the line round it, on the body's
    /// canvas: Z Tea's blast's. Nil with no front arm in the frame.
    func frontArmTexture(_ frame: AnimationFrame, player: Int, ballAsEnergy: Bool = false, ballLifted: Bool = false) -> SKTexture? {
        partsTexture(frame, player: player, parts: [.frontArm, .frontHand], suffix: "_frontarm", ballAsEnergy: ballAsEnergy, ballLifted: ballLifted)
    }

    /// Z Tea's blast's arm's own line, white, for its node's colour: made with the frame.
    func blastArmOutlineTexture(_ frame: AnimationFrame, player: Int, front: Bool) -> SKTexture? {
        cache[SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: false, ballLifted: false) + (front ? "_frontarmoutline" : "_backarmoutline")]
    }

    /// The sheet's back arm alone, lined, on the body's canvas: Z Tea's blast's, drawn behind the body.
    func backArmTexture(_ frame: AnimationFrame, player: Int) -> SKTexture? {
        partsTexture(frame, player: player, parts: [.backArm, .backHand], suffix: "_backarm", ballAsEnergy: false, ballLifted: false)
    }

    /// The arms over the hood's own line, in white, for the line's node colour: round the arms and
    /// hands wherever they meet the hooded head or open air, so the arms laid over the hood are lined.
    func armsOverHoodLineTexture(_ frame: AnimationFrame, player: Int) -> SKTexture? {
        let look = look(for: player)
        let key = "p\(player)_\(frame.animation.rawValue)_\(frame.frame)_armsoverhoodline"
        if let made = cache[key] { return made }
        let missStart = CACurrentMediaTime()
        defer { reportMiss(key, since: missStart) }
        guard !emptyPieces.contains(key) else { return nil }
        let source = sourceImage("\(frame.animation.rawValue)_\(frame.frame)")
        guard let image = SpriteLibrary.partsLine(source: source, parts: GameScene.armPartsOverHood(frame),
                                                  hood: SpriteLibrary.hoodShape(skin: look.dressing.skinTone, for: frame, energy: look.energyForm),
                                                  hoodNudge: GameScene.headNudge(frame), style: SpriteLibrary.lineStyle(for: player)) else {
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
    static func partsLine(source: CGImage, parts: Set<BodyPart>, hood: CGImage?, hoodNudge: CGPoint = .zero, style: LineStyle = .normal) -> CGImage? {
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
            let offsetX = Int((headSum.x / CGFloat(heads) - there.x).rounded() + hoodNudge.x), offsetY = Int((headSum.y / CGFloat(heads) - there.y).rounded() - hoodNudge.y)
            for y in 0..<hood.height {
                for x in 0..<hood.width where hoodPixels[(y * hood.width + x) * 4 + 3] != 0 {
                    let fx = x + offsetX, fy = y + offsetY
                    if fx >= 0, fy >= 0, fx < width, fy < height { underHood[fy * width + fx] = true }
                }
            }
        }
        let isPart = owner.map { $0.map(parts.contains) == true }
        let line = SpriteLibrary.lineRound(isPart, width: width, height: height, style: style) { pixel in
            sourcePixels[pixel * 4 + 3] == 0 || owner[pixel] == .head || underHood[pixel]
        }
        var any = false
        for pixel in line.indices where line[pixel] {
            for channel in 0..<4 { linePixels[pixel * 4 + channel] = 255 }
            any = true
        }
        return any ? lineContext.makeImage() : nil
    }

    private func partsTexture(_ frame: AnimationFrame, player: Int, parts: Set<BodyPart>, suffix: String, ballAsEnergy: Bool, ballLifted: Bool) -> SKTexture? {
        let key = SpriteLibrary.frameKey(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted) + suffix
        if let made = cache[key] { return made }
        let missStart = CACurrentMediaTime()
        defer { reportMiss(key, since: missStart) }
        guard !emptyPieces.contains(key) else { return nil }
        let drawn = pictures(frame, player: player, ballAsEnergy: ballAsEnergy, ballLifted: ballLifted).drawn
        let source = sourceImage("\(frame.animation.rawValue)_\(frame.frame)")
        guard let image = SpriteLibrary.partsImage(drawn: drawn, source: source, parts: parts, style: SpriteLibrary.lineStyle(for: player)) else { emptyPieces.insert(key); return nil }
        let made = SKTexture(cgImage: image)
        made.filteringMode = .nearest
        cache[key] = made
        return made
    }

    /// The pixels of `parts` as `drawn` has them, found by the sheet's own colours in `source`, with
    /// the line drawn next to them; nil when the frame has none of them.
    static func partsImage(drawn: CGImage, source: CGImage, parts: Set<BodyPart>, lined: Bool = true, style: LineStyle = .normal) -> CGImage? {
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
        // The line round it: drawn where the sheet has nothing, next to the part.
        let line = lined ? SpriteLibrary.lineRound(isPart, width: width, height: height, style: style) { pixel in
            sourcePixels[pixel * 4 + 3] == 0 && drawnPixels[pixel * 4 + 3] > 0
        } : []
        for y in 0..<height {
            for x in 0..<width {
                let pixel = y * width + x
                let keep = isPart[pixel] || (lined && line[pixel])
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
        let result = makeSilhouette(image: sourceImage("\(name)_\(frame)"), look: look(for: player))
        cache[key] = result
        return result
    }

    /// A frame as a silhouette in a look's white energy; touches nothing kept.
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
        let result = makeToned(image: sourceImage("\(name)_\(frame)"), look: look(for: player), capped: Effect.sparkNames.contains(name))
        cache[key] = result
        return result
    }

    /// The hood's greys a touch down the ramp, nearer the legs' plain colour.
    static let hoodLevel = 0.9
    /// The skin `player_hoodheads_v2` is drawn in, EDG64's first, swapped for the player's.
    static let hoodHeadsSkin: (front: RGB, back: RGB) = (0xF6CA9F, 0xE69C69)

    /// The hooded head, a frame of `player_hoodheads` for one skin: its hood, the white and the
    /// cool greys, toned through the player's energy ramp, the skin left as drawn; and the hood
    /// and the face each alone in white, for the glow's mask. As the ice player, the frozen
    /// bodies' and ice clones' look, the face too is toned, in the ice's front colour.
    /// In FloState (`energy`), the hood is the energy form's near-white clothes colour
    /// (`EnergyColour.body`), shaded by its greys; the face stays skin, unglowing, as ever.
    /// `view`: which way the head faces (`HoodView`), the turned ones drawn from `player_hoodheads_v2`
    /// in the first skin and swapped into this one's two tones; FloState's from `player_hoodheads_flostate`.
    func hoodHead(skin: Int, player: Int, energy: Bool = false, view: Int = 0) -> (drawn: SKTexture, hood: SKTexture, face: SKTexture) {
        let key = SpriteLibrary.hoodHeadKey(skin: skin, player: player, energy: energy, view: view)
        if let drawn = cache[key], let hood = cache[key + "_hood"], let face = cache[key + "_face"] { return (drawn, hood, face) }
        let missStart = CACurrentMediaTime()
        defer { reportMiss(key, since: missStart) }
        let sourceName = SpriteLibrary.hoodSourceName(view: view, energy: energy)
        let source = atlasTexture(sourceName)
        guard let made = makeHoodHead(source: sourceImage(sourceName, texture: source), skin: skin, look: look(for: player), ice: player == SpriteLibrary.icePlayer,
                                      energy: energy) else { return (source, source, source) }
        keep(hoodHead: made, key: key)
        return (cache[key]!, cache[key + "_hood"]!, cache[key + "_face"]!)
    }

    /// The hooded head as drawn, from the picture kept when it was made, so nothing's read back off
    /// the GPU; the same picture each time until the head is made again.
    func hoodHeadPicture(skin: Int, player: Int) -> CGImage {
        let made = hoodHead(skin: skin, player: player)
        if let kept = keptImages[SpriteLibrary.hoodHeadKey(skin: skin, player: player, energy: false, view: 0)] { return kept }
        let key = "hoodpicture_\(ObjectIdentifier(made.drawn).hashValue)"
        if let read = keptImages[key] { return read }
        let read = made.drawn.cgImage()
        keptImages[key] = read
        return read
    }

    static func hoodHeadKey(skin: Int, player: Int, energy: Bool, view: Int) -> String {
        "p\(player)_hoodhead_\(skin)" + (view == 0 ? "" : "_v\(view)") + (energy ? "_energy" : "")
    }
    static func hoodSourceName(view: Int, energy: Bool) -> String {
        let sheet = energy ? "player_hoodheads_flostate" : "player_hoodheads_v2"
        return "\(sheet)_\(view == 0 || turnedHoodShapes[view] == nil ? 0 : view)"
    }

    private func keep(hoodHead made: (drawn: CGImage, hood: CGImage, face: CGImage), key: String) {
        for (suffix, image) in [("", made.drawn), ("_hood", made.hood), ("_face", made.face)] {
            let texture = SKTexture(cgImage: image)
            texture.filteringMode = .nearest
            cache[key + suffix] = texture
            keptImages[key + suffix] = image
        }
        // The hood's glowing pixels as drawn: the drawing kept only where the hood's mask is.
        if let drawn = cache[key], let (context, _) = makeCanvas(width: made.drawn.width, height: made.drawn.height) {
            let rect = CGRect(x: 0, y: 0, width: made.drawn.width, height: made.drawn.height)
            context.draw(made.drawn, in: rect)
            context.setBlendMode(.destinationIn)
            context.draw(made.hood, in: rect)
            if let glowing = context.makeImage(), let halo = SpriteLibrary.haloTexture(glowing) { hoodHalos.setObject(halo, forKey: drawn) }
        }
    }

    /// The hooded head's three pictures from its sheet's frame: as drawn, its hood alone and its
    /// face alone in white. Touches nothing kept, so it can be made off the main thread.
    private func makeHoodHead(source image: CGImage, skin: Int, look: Look, ice: Bool, energy: Bool) -> (drawn: CGImage, hood: CGImage, face: CGImage)? {
        // Every view drawn in one skin, EDG64's first, its two tones swapped for this one's.
        let from = SpriteLibrary.hoodHeadsSkin, to = HumanLook.everySkinTone[min(max(skin, 0), HumanLook.everySkinTone.count - 1)]
        let faceSwaps: [RGB: RGB] = from == to ? [:] : [from.front: to.front, from.back: to.back]
        let width = image.width, height = image.height
        guard let (context, pixels) = makeCanvas(width: width, height: height),
              let (hoodContext, hoodPixels) = makeCanvas(width: width, height: height),
              let (faceContext, facePixels) = makeCanvas(width: width, height: height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        func level(_ index: Int) -> Double {
            (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / 255
        }
        // The face's lightest tone, which the ice's colour stands for.
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
                if ice {
                    paint(pixels, index, Look.scaled(look.glow, min(level(index) / max(faceLightest, 0.01), 1)))
                } else if let swap = faceSwaps[RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])] {
                    paint(pixels, index, swap)
                }
                continue
            }
            let grey = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
            if energy, let body = look.body {
                paint(pixels, index, Look.scaled(body, min(grey, 1)))
            } else if ice {
                paint(pixels, index, look.energyTone(luminance: min(grey * SpriteLibrary.hoodLevel, 1)))
            } else {
                // White the energy colour, the greys its hood shadow.
                paint(pixels, index, red == 255 && green == 255 && blue == 255 ? look.hoodTones.plain : look.hoodTones.shadow)
            }
        }
        guard let drawn = context.makeImage(), let hood = hoodContext.makeImage(), let face = faceContext.makeImage() else { return nil }
        return (drawn, hood, face)
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
    /// The sheets drawn with props in them, kept as drawn: the drink's bottle, the drink choice's towel.
    static let propSheets: Set<String> = ["player_drink", "player_drinkchoice"]
    /// The drink's splashes, white, kept out of the line and laid back on as drawn.
    static let unlinedSplashSheets: Set<String> = ["player_drink"]
    static let splash: Set<RGB> = [0xFFFFFF]
    func standalone(_ name: String, frame: Int, player: Int, headTilt: CGFloat = 0, overHood: Set<RGB> = []) -> SKTexture {
        let key = "p\(player)_standalone_\(name)_\(frame)_\(headTilt)"
        if let made = cache[key] { return made }
        let look = look(for: player)
        let source = sourceImage("\(name)_\(frame)")
        let keepsProps = SpriteLibrary.propSheets.contains(name), lineStyle = SpriteLibrary.lineStyle(for: player)
        let lined = SpriteLibrary.unlinedSplashSheets.contains(name) ? SpriteLibrary.clearing(source, SpriteLibrary.splash) ?? source : source
        // Without the hood's cut: where the head is, and what's drawn again over the hood.
        let uncut = recolour(image: lined, look: look, holdsBall: false, detach: false, hoodShape: nil, keepsProps: keepsProps, lineStyle: lineStyle)
        // The hood's shape tipped as the hood is drawn, about the same middle, so its cut and line fit it.
        var hoodShape: CGImage? = look.energyForm ? nil : SpriteLibrary.plainHoodShape
        if headTilt != 0, let shape = hoodShape, let here = uncut.centres[.head], let there = SpriteLibrary.hoodDrawnForHead {
            let offset = CGPoint(x: (here.x - there.x).rounded(), y: (here.y - there.y).rounded())
            hoodShape = SpriteLibrary.turned(shape, by: headTilt, about: CGPoint(x: here.x - offset.x, y: here.y - offset.y)) ?? shape
        }
        let body = recolour(image: lined, look: look, holdsBall: false, detach: false, hoodShape: hoodShape, keepsProps: keepsProps, lineStyle: lineStyle)
        // Each step from the pictures as made, never read back off the GPU: a read back logs and
        // allocates every time, and the lock-in and the stage's load made dozens at once.
        var made = body.texture
        let image = body.images?.drawn ?? body.texture.cgImage()
        var madeImage = image
        if let (context, pixels) = makeCanvas(width: image.width, height: image.height),
           let (sourceContext, sourcePixels) = makeCanvas(width: source.width, height: source.height) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            sourceContext.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            let towel: Set<RGB> = [0xFFFFFF, 0xC7CFDD]
            for pixel in 0..<(min(image.width, source.width) * min(image.height, source.height)) where sourcePixels[pixel * 4 + 3] == 255 {
                let index = pixel * 4
                let colour = RGB(sourcePixels[index]) << 16 | RGB(sourcePixels[index + 1]) << 8 | RGB(sourcePixels[index + 2])
                guard towel.contains(colour) else { continue }
                for channel in 0..<4 { pixels[index + channel] = sourcePixels[index + channel] }
            }
            if let composed = context.makeImage() {
                made = SKTexture(cgImage: composed)
                madeImage = composed
            }
        }
        if !look.energyForm, let here = body.centres[.head], let there = SpriteLibrary.hoodDrawnForHead,
           let (context, _) = makeCanvas(width: image.width, height: image.height) {
            context.draw(madeImage, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let hood = hoodHeadPicture(skin: look.dressing.skinTone, player: player)
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
                // From the body before the hood's cut: the cut takes the bottle and hand where they cross the head.
                if !overHood.isEmpty, let over = overlaid(composed, from: uncut.images?.drawn ?? uncut.texture.cgImage(), where: source, in: overHood) { composed = over }
                made = SKTexture(cgImage: composed)
                madeImage = composed
            }
        }
        made.filteringMode = .nearest
        cache[key] = made
        keptImages[key] = madeImage
        return made
    }

    /// `standalone`'s picture as made, for a SwiftUI screen to show without reading it back off the GPU.
    func standalonePicture(_ name: String, frame: Int, player: Int, headTilt: CGFloat = 0, overHood: Set<RGB> = []) -> CGImage {
        let made = standalone(name, frame: frame, player: player, headTilt: headTilt, overHood: overHood)
        return keptImages["p\(player)_standalone_\(name)_\(frame)_\(headTilt)"] ?? made.cgImage()
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
        let key = SpriteLibrary.portraitKey(name, frame: frame, player: player, headNudge: headNudge, headScale: headScale)
        if cache[key] != nil, let made = portraits[key] { return made }
        let playerLook = look(for: player)
        let sheetFrame = Animation(rawValue: name).map { AnimationFrame($0, frame) }
        let look = sheetFrame.map { SpriteLibrary.look(playerLook, for: $0) } ?? playerLook
        let view = sheetFrame.map(HoodView.of) ?? 0
        var hood: (drawn: CGImage, hood: CGImage, line: CGImage?)?
        // In FloState (a side's energy form), the FloState hood, as play has it, of the side's own head.
        let energy = look.energyForm
        let headPlayer = energy ? player - SpriteLibrary.transformedPlayer(0) : player
        let skin = look.dressing.skinTone
        let headKey = SpriteLibrary.hoodHeadKey(skin: skin, player: headPlayer, energy: energy, view: view)
        _ = hoodHead(skin: skin, player: headPlayer, energy: energy, view: view)
        let style = SpriteLibrary.lineStyle(for: player)
        if let drawn = keptImages[headKey], let mask = keptImages[headKey + "_hood"] {
            let lineKey = SpriteLibrary.hoodLineKey(skin: skin, view: view, energy: energy, style: style)
            hood = (drawn, mask, keptImages[lineKey] ?? hoodLine(skin: skin, view: view, energy: energy, style: style)?.cgImage())
        }
        guard let made = makePortrait(name, frame: frame, look: look, source: sourceImage("\(name)_\(frame)"),
                                      drawnFor: sourceImage("\(headDrawnFor.animation.rawValue)_\(headDrawnFor.frame)"),
                                      hood: hood, headNudge: headNudge, headScale: headScale, holdsBall: holdsBall, lineStyle: style) else { return nil }
        keep(portrait: made, key: key)
        return made
    }

    static func portraitKey(_ name: String, frame: Int, player: Int, headNudge: CGPoint, headScale: CGFloat) -> String {
        "p\(player)_portrait_\(name)_\(frame)_\(headNudge.x)_\(headNudge.y)_\(headScale)"
    }

    private func keep(portrait made: Portrait, key: String) {
        // Kept in the cache too, so a new look drops it with the rest of the player's.
        cache[key] = SKTexture(cgImage: made.image)
        portraits[key] = made
    }

    /// A portrait from its sheet's frame, the frame the head's drawn for, and the hooded head as
    /// this frame's view has it (its picture, its hood alone, its line). Touches nothing kept,
    /// so it can be made off the main thread.
    private func makePortrait(_ name: String, frame: Int, look: Look, source: CGImage, drawnFor drawnForSource: CGImage,
                              hood givenHood: (drawn: CGImage, hood: CGImage, line: CGImage?)?, headNudge: CGPoint, headScale: CGFloat,
                              holdsBall: Bool, lineStyle: LineStyle = .normal) -> Portrait? {
        let sheetFrame = Animation(rawValue: name).map { AnimationFrame($0, frame) }
        let view = sheetFrame.map(HoodView.of) ?? 0
        let flipped = sheetFrame.map(HoodView.isFlipped) ?? false
        /// The hooded head as this frame wears it: its view, mirrored where it looks back.
        func wornHood(_ image: CGImage) -> CGImage { flipped ? SpriteLibrary.mirrored(image) ?? image : image }
        let ballPixels = holdsBall ? sheetFrame.flatMap { SpriteLibrary.sheetBall($0, source: source) }?.pixels : nil
        let plain = recolour(image: source, look: look, holdsBall: holdsBall, detach: false, ballPixels: ballPixels, lineStyle: lineStyle)
        let drawnFor = recolour(image: drawnForSource, look: look, holdsBall: false, detach: false, lineStyle: lineStyle)
        var figure = plain
        if let givenHood, let here = plain.centres[.head], let there = drawnFor.centres[.head] {
            let offset = CGPoint(x: (here.x - there.x).rounded(), y: (here.y - there.y).rounded())
            let place = SpriteLibrary.hoodPlace(head: here, offset: offset, nudge: headNudge, scale: headScale)
            figure = recolour(image: source, look: look, holdsBall: holdsBall, detach: true, ballPixels: ballPixels,
                              hood: (wornHood(givenHood.drawn), place.origin, place.scale), lineStyle: lineStyle)
        }
        guard var body = figure.images?.drawn else { return nil }
        // What play draws apart from the body, over it and under the hood: the blade, the gun,
        // the puffs and streaks, toned in the energy colour as play tones them (`Look.sparkTone`).
        let energy = figure.images?.energy.flatMap { SpriteLibrary.toned($0, look.sparkTone) }
        if let energy, let over = SpriteLibrary.drawn(energy, over: body) { body = over }
        let width = body.width, height = body.height
        guard let (glowContext, glowPixels) = makeCanvas(width: width, height: height),
              let (sourceContext, sourcePixels) = makeCanvas(width: width, height: height) else { return nil }
        // What glows: the figure's pixels of the parts that do, as drawn.
        glowContext.draw(body, in: CGRect(x: 0, y: 0, width: width, height: height))
        sourceContext.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let colour = RGB(sourcePixels[index]) << 16 | RGB(sourcePixels[index + 1]) << 8 | RGB(sourcePixels[index + 2])
            let glows = !look.energyForm && sourcePixels[index + 3] == 255 && BodyPart.owning(colour).map(look.dressing.glowing.contains) == true
            if !glows { for channel in 0..<4 { glowPixels[index + channel] = 0 } }
        }
        var offset = CGPoint.zero
        var hood: CGImage?, hoodGlowing: CGImage?
        if let givenHood, let here = figure.centres[.head], let there = drawnFor.centres[.head] {
            let drawn = wornHood(givenHood.drawn)
            hood = drawn
            offset = CGPoint(x: (here.x - there.x).rounded(), y: (here.y - there.y).rounded())
            // The hood glows; its face doesn't.
            if let (hoodContext, hoodPixels) = makeCanvas(width: drawn.width, height: drawn.height),
               let (maskContext, maskPixels) = makeCanvas(width: drawn.width, height: drawn.height) {
                hoodContext.draw(drawn, in: CGRect(x: 0, y: 0, width: drawn.width, height: drawn.height))
                maskContext.draw(wornHood(givenHood.hood), in: CGRect(x: 0, y: 0, width: drawn.width, height: drawn.height))
                for pixel in 0..<(drawn.width * drawn.height) where maskPixels[pixel * 4 + 3] == 0 {
                    for channel in 0..<4 { hoodPixels[pixel * 4 + channel] = 0 }
                }
                hoodGlowing = hoodContext.makeImage()
            }
        }
        // The energy glows, as it does in play.
        if let energy { glowContext.draw(energy, in: CGRect(x: 0, y: 0, width: width, height: height)) }
        guard let glowing = glowContext.makeImage() else { return nil }
        let hoodShape = SpriteLibrary.hoodShape(skin: look.dressing.skinTone, view: view, flipped: flipped, energy: look.energyForm)
        let bare = givenHood != nil ? recolour(image: source, look: look, holdsBall: holdsBall, detach: true, ballPixels: ballPixels,
                                               hoodShape: hoodShape, hoodNudge: headNudge, bareLine: true, lineStyle: lineStyle).images?.bareOutline : nil
        // The arms play lays over the hood on this frame; the front one where it lays none.
        let armsOverHood = sheetFrame.map(GameScene.armPartsOverHood).flatMap { $0.isEmpty ? nil : $0 } ?? [.frontArm, .frontHand]
        return Portrait(image: body, glowing: glowing, hood: hood, hoodGlowing: hoodGlowing, hoodOffset: offset,
                        centres: figure.centres, tops: SpriteLibrary.partTops(source),
                        line: figure.images?.outline, frontArm: SpriteLibrary.partsImage(drawn: body, source: source, parts: armsOverHood, style: lineStyle),
                        frontArmLine: SpriteLibrary.partsLine(source: source, parts: armsOverHood,
                                                              hood: givenHood != nil ? hoodShape : nil, hoodNudge: headNudge, style: lineStyle),
                        bareLine: bare, hoodLine: givenHood?.line)
    }

    /// A grey picture toned through `tone`, its alpha kept.
    static func toned(_ image: CGImage, _ tone: (Double) -> RGB) -> CGImage? {
        let width = image.width, height = image.height
        guard let (context, pixels) = canvas(width: width, height: height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let alpha = Int(pixels[index + 3])
            guard alpha > 0 else { continue }
            // The canvas is premultiplied: the grey level is the colour over the alpha.
            let grey = (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / Double(alpha)
            let colour = tone(min(grey, 1))
            pixels[index] = UInt8(Int((colour >> 16) & 0xFF) * alpha / 255)
            pixels[index + 1] = UInt8(Int((colour >> 8) & 0xFF) * alpha / 255)
            pixels[index + 2] = UInt8(Int(colour & 0xFF) * alpha / 255)
        }
        return context.makeImage()
    }

    /// An effect's frame in a player's energy colour as a picture, as `effectTexture` tones it,
    /// made on the CPU: for SwiftUI and the gallery, never read back off the GPU.
    func effectImage(_ name: String, _ frame: Int, player: Int) -> CGImage? {
        SpriteLibrary.toned(sourceImage("\(name)_\(frame)"), look(for: player).energyTone)
    }

    /// One picture drawn over another the same size.
    static func drawn(_ top: CGImage, over bottom: CGImage) -> CGImage? {
        guard let (context, _) = canvas(width: bottom.width, height: bottom.height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: bottom.width, height: bottom.height)
        context.draw(bottom, in: rect)
        context.draw(top, in: rect)
        return context.makeImage()
    }

    /// A grey frame through a look's energy ramp, or with `capped` the sparks' ramp, which
    /// stops at the colour; touches nothing kept.
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
        let image = sourceImage("\(name)_\(frame)")
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
    /// The idle frame the hood is drawn for; and the plain view's shape, `player_hoodheads_v2`'s
    /// first frame, every skin's (the faces are recoloured, the shape's the same), read once.
    static let hoodDrawnFor = AnimationFrame(.idle, 2)
    static let plainHoodShape: CGImage = SKTextureAtlas(named: "Sprites").textureNamed("player_hoodheads_v2_0").cgImage()
    /// A turned view's frames, `player_hoodheads_v2`'s second and third.
    static let turnedHoodShapes: [Int: CGImage] = {
        let atlas = SKTextureAtlas(named: "Sprites")
        return Dictionary(uniqueKeysWithValues: (1..<HoodView.count).compactMap { view in
            atlas.textureNames.contains("player_hoodheads_v2_\(view)") ? (view, atlas.textureNamed("player_hoodheads_v2_\(view)").cgImage()) : nil
        })
    }()
    /// FloState's hood's every view, `player_hoodheads_flostate`'s frames: its own shape.
    static let floStateHoodShapes: [Int: CGImage] = {
        let atlas = SKTextureAtlas(named: "Sprites")
        return Dictionary(uniqueKeysWithValues: (0..<HoodView.count).compactMap { view in
            atlas.textureNames.contains("player_hoodheads_flostate_\(view)") ? (view, atlas.textureNamed("player_hoodheads_flostate_\(view)").cgImage()) : nil
        })
    }()
    /// The hooded head's outline for a skin and view: where the body's line and neck go round it.
    /// `energy`: FloState's hood.
    static func hoodShape(skin: Int, view: Int, flipped: Bool = false, energy: Bool = false) -> CGImage {
        let plain = view == 0 ? plainHoodShape : turnedHoodShapes[view] ?? plainHoodShape
        let shape = energy ? floStateHoodShapes[turnedHoodShapes[view] == nil ? 0 : view] ?? plain : plain
        return flipped ? mirrored(shape) ?? shape : shape
    }
    /// A frame's hood shape: its view, mirrored where the head looks back.
    static func hoodShape(skin: Int, for frame: AnimationFrame, energy: Bool = false) -> CGImage {
        hoodShape(skin: skin, view: HoodView.of(frame), flipped: HoodView.isFlipped(frame), energy: energy)
    }
    /// An image turned round left to right about its middle.
    /// An image turned anticlockwise by `degrees` about `point` (pixels, rows down), unsmoothed.
    static func turned(_ image: CGImage, by degrees: CGFloat, about point: CGPoint) -> CGImage? {
        guard let (context, _) = canvas(width: image.width, height: image.height) else { return nil }
        context.interpolationQuality = .none
        context.translateBy(x: point.x, y: CGFloat(image.height) - point.y)
        context.rotate(by: degrees * .pi / 180)
        context.translateBy(x: -point.x, y: -(CGFloat(image.height) - point.y))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
    /// An image with its pixels in `colours` cleared.
    static func clearing(_ image: CGImage, _ colours: Set<RGB>) -> CGImage? {
        guard let (context, pixels) = canvas(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        for pixel in 0..<(image.width * image.height) where pixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            guard colours.contains(RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])) else { continue }
            for channel in 0..<4 { pixels[index + channel] = 0 }
        }
        return context.makeImage()
    }
    static func mirrored(_ image: CGImage) -> CGImage? {
        guard let (context, _) = canvas(width: image.width, height: image.height) else { return nil }
        context.translateBy(x: CGFloat(image.width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
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
        let tops = SpriteLibrary.partTops(sourceImage(key)).mapValues { top in
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

    /// A part's middle on a sheet frame, in art pixels from the feet as landmarks are: the sheet's
    /// alone, the same in every look, so asking makes no texture.
    private var partCentres: [String: [BodyPart: CGPoint]] = [:]
    func centre(_ part: BodyPart, in frame: AnimationFrame) -> CGPoint? {
        let key = "\(frame.animation.rawValue)_\(frame.frame)"
        if let found = partCentres[key] { return found[part] }
        let size = frame.animation.pixelSize, width = frame.animation.pixelWidth
        let centres = SpriteLibrary.partCentres(sourceImage(key)).mapValues { centre in
            CGPoint(x: centre.x - width / 2, y: size - centre.y - frame.animation.feetFromBottom)
        }
        partCentres[key] = centres
        return centres[part]
    }

    /// The parts' middles on a sheet frame, in its pixels from the top left.
    static func partCentres(_ image: CGImage) -> [BodyPart: CGPoint] {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return [:] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var sums: [BodyPart: (x: CGFloat, y: CGFloat, count: CGFloat)] = [:]
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] == 255 {
                let index = (y * width + x) * 4
                guard let part = BodyPart.owning(RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])) else { continue }
                let sum = sums[part] ?? (0, 0, 0)
                sums[part] = (sum.x + CGFloat(x) + 0.5, sum.y + CGFloat(y) + 0.5, sum.count + 1)
            }
        }
        return sums.mapValues { CGPoint(x: $0.x / $0.count, y: $0.y / $0.count) }
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
    var allTextures: [SKTexture] { Array(cache.values) + frameMaps.values.flatMap(\.textures) }

    /// A human player's hooded heads made ahead, every view, plain, in FloState and frozen, with the
    /// hood's line and K&A's face: none first made mid-match. What was made, to send to the GPU.
    @discardableResult
    func warmHoods(player: Int) -> [SKTexture] {
        let look = look(for: player)
        guard !look.energyForm, player < SpriteLibrary.icePlayer else { return [] }
        let skin = look.dressing.skinTone
        var made: [SKTexture] = []
        for view in 0..<HoodView.count {
            // Plain, in FloState, and frozen in this skin.
            for head in [hoodHead(skin: skin, player: player, view: view), hoodHead(skin: skin, player: player, energy: true, view: view),
                         hoodHead(skin: skin, player: SpriteLibrary.icePlayer, view: view)] {
                made += [head.drawn, head.hood, head.face] + [hoodHalo(for: head.drawn)].compactMap { $0 }
            }
            let style = SpriteLibrary.lineStyle(for: player)
            made += [hoodLine(skin: skin, view: view, style: style), hoodLine(skin: skin, view: view, energy: true, style: style),
                     hoodFace(skin: skin, player: player, view: view)].compactMap { $0 }
        }
        return made
    }

    /// Builds every frame of every player up front and sends them to the GPU, so nothing
    /// is made mid-draw. The sides' own looks first, `essentials` told once they've landed (the
    /// launch's splash lifts there); then the ice look, each side's energy form and turned one,
    /// built behind the menus, `completion` once everything's on the GPU.
    func warmUp(players: Int, essentials: (() -> Void)? = nil, completion: @escaping () -> Void) {
        // Built off the main thread on every core as a look change's are (`rewarm`): built here
        // on the main thread they held it seconds at launch, and the system ended the app for it.
        func needsBuilding(_ drawn: Int) -> Bool {
            rebuilding[drawn] == nil && landmarks[SpriteLibrary.frameKey(AnimationFrame(.idle, 0), player: drawn, ballAsEnergy: false, ballLifted: false)] == nil
        }
        for drawn in 0..<players where needsBuilding(drawn) { rewarm(player: drawn) }
        afterRebuilds { [weak self] in
            guard let self else { return }
            LoadTrace.mark("warm-up: the sides' own looks landed")
            essentials?()
            let held = self.heldForLaunch ?? []
            self.heldForLaunch = nil
            let turned = (0..<players).map(SpriteLibrary.turnedPlayer).filter { self.look(for: $0) != self.look(for: $0 - SpriteLibrary.turnedPlayer(0)) }
            // The frozen look isn't among them: built only once Frost Tea's in play (`warmIceLook`).
            let rest = (0..<players).map(SpriteLibrary.transformedPlayer) + turned
            for drawn in rest where needsBuilding(drawn) { self.rewarm(player: drawn) }
            // Asked for while held (a look set at launch), and not already rebuilt above.
            for drawn in held.sorted() where self.rebuilding[drawn] == nil { self.rewarm(player: drawn) }
            self.afterRebuilds { [weak self] in self?.finishWarmUp(completion: completion) }
        }
    }

    /// The frozen look built and sent to the GPU, if it isn't already or underway: asked for once a
    /// side has Frost Tea or it's on offer, so nobody's launch or match pays for it otherwise.
    func warmIceLook() {
        let ice = SpriteLibrary.icePlayer
        guard rebuilding[ice] == nil,
              landmarks[SpriteLibrary.frameKey(AnimationFrame(.idle, 0), player: ice, ballAsEnergy: false, ballLifted: false)] == nil else { return }
        rewarm(player: ice)
    }

    /// The warm-up's last, small pieces, then everything sent to the GPU.
    private func finishWarmUp(completion: @escaping () -> Void) {
        LoadTrace.mark("warm-up: every rebuild landed, preloading the atlas")
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
        group.notify(queue: .main) {
            LoadTrace.mark("warm-up: atlas on the GPU")
            completion()
        }
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

    /// A copy of the frame in the look, as `PlayerRecolour.recolour` makes it, with its layers as
    /// textures: for the pictures that aren't play's (the standalone figures, the portraits).
    private func recolour(image: CGImage, look: Look, holdsBall: Bool, detach: Bool, tucked: Bool = false, ballPixels: Set<Int>? = nil,
                          hood given: (shape: CGImage, origin: CGPoint, scale: CGFloat)? = nil, hoodShape: CGImage? = nil, hoodNudge: CGPoint = .zero,
                          bareLine: Bool = false, keepsProps: Bool = false, lineStyle: LineStyle = .normal) -> (texture: SKTexture, head: SKTexture?, energy: SKTexture?, outline: SKTexture?, glowMask: SKTexture?, skin: SKTexture?, thinOutline: SKTexture?, centres: [BodyPart: CGPoint], bareOutline: SKTexture?, glowingParts: SKTexture?, glowLine: SKTexture?, bareGlowLine: SKTexture?, images: (drawn: CGImage, glowing: CGImage?, outline: CGImage?, bareOutline: CGImage?, energy: CGImage?)?) {
        let layers = PlayerRecolour.recolour(image: image, look: look, holdsBall: holdsBall, detach: detach, tucked: tucked, ballPixels: ballPixels,
                                             hood: given, hoodShape: hoodShape, hoodNudge: hoodNudge, bareLine: bareLine, keepsProps: keepsProps,
                                             lineStyle: lineStyle, hoodDrawnForHead: SpriteLibrary.hoodDrawnForHead, ballMinPixels: SpriteLibrary.ballMinPixels)
        func shared(_ image: CGImage?) -> SKTexture? { image.map { SpriteLibrary.sharedTexture($0) } }
        let glowMask = shared(layers.glowMask)
        glowMask?.filteringMode = .nearest
        return (SpriteLibrary.sharedTexture(layers.drawn), shared(layers.head), shared(layers.energy), shared(layers.outline), glowMask, shared(layers.skin),
                shared(layers.thinOutline), layers.centres, shared(layers.bareOutline), shared(layers.glowing), shared(layers.glowLine), shared(layers.bareGlowLine),
                (layers.drawn, layers.glowing, layers.outline, layers.bareOutline, layers.energy))
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
    /// Z Tea's beam's three pieces, and its burst; its blast.
    case beam, burst, zBlast
    /// Two blades meeting.
    case slashClash
    /// Shielding: the shield, and the perfect shield's shine.
    case shield, shine

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
        case .zBlast: "blast"
        case .slashClash: "slashclash"
        case .shield: "shield"
        case .shine: "shine"
        }
    }

    /// Frames and the anchor come from the importer's measurements of the sheet.
    var frameCount: Int { EffectSheets.frames[name] ?? 1 }

    var fps: Double {
        switch self {
        case .charge: 30
        case .scoreStrike, .floAbsorb, .shield, .shine: 15
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
    static let frames: [Animation: [Int: Int]] = [
        .esperSlashFloState: [1: 1, 2: 2, 3: 2, 4: 1],
        .snatchFloState: [0: 1, 2: 1, 3: 2, 4: 1, 5: 1],
        .spinBall: [0: 1, 1: 0, 2: 1, 3: 2], .spin: [0: 1, 1: 0, 2: 1, 3: 2],
        .pivot: [2: 1],
        .dunk: [0: 1, 1: 1, 2: 1, 3: 1, 4: 1, 5: 1],
        // The spin dunk's spin as the Spin Move's frames 1-3, then side on.
        .spinDunk: [1: 1, 2: 2, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1],
        .beam: [3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1],
        // The blast's arms firing, side on; opening and at neutral, the plain view.
        .blast: [3: 1, 4: 1, 5: 1, 6: 1, 8: 1, 9: 1, 10: 1, 11: 1],
        .ledge: [0: 1, 1: 1, 2: 1, 3: 2, 4: 1],
        .gunShoot: every(1, of: .gunShoot), .gunShootAir: every(1, of: .gunShootAir), .gunSnipe: every(1, of: .gunSnipe),
        .gunRun: every(1, of: .gunRun), .gunRunShoot: every(1, of: .gunRunShoot),
        .layup: [2: 1, 3: 1, 4: 2, 5: 2, 6: 2, 7: 2, 8: 2],
        .esperSlash: [2: 1, 3: 1, 4: 1], .esperSlashAir: [0: 2, 1: 2, 2: 1, 3: 1, 4: 1, 5: 1],
        .shoot: [2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1],
        .shootAir: [2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1],
        .throwForward: [4: 1, 5: 2, 6: 2, 7: 1], .throwAir: [4: 1, 5: 2, 6: 2, 7: 1],
    ]
    private static func every(_ view: Int, of animation: Animation) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: (0..<animation.frameCount).map { ($0, view) })
    }
    static func of(_ frame: AnimationFrame) -> Int { frames[frame.animation]?[frame.frame] ?? 0 }
    /// The frames the hooded head is mirrored on, looking back the other way: FloState's snatch
    /// over its step-through, the pivot as it turns, the wall cling looking away from the wall.
    static let flipped: [Animation: Set<Int>] = [.snatchFloState: [1, 2], .pivot: [1], .spinBall: [1, 2], .spin: [1, 2], .spinDunk: [0, 1],
                                                 .wallLand: Set(0..<Animation.wallLand.frameCount), .wallLandBall: Set(0..<Animation.wallLandBall.frameCount),
                                                 .webshootWall: Set(0..<Animation.webshootWall.frameCount)]
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
