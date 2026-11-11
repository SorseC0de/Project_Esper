import SpriteKit
import simd
import EsperSim

/// Breaker Ball's look: the barrier's percentage, its shards when it shatters, and the floating rims.
enum BreakerLook {
    /// The percentage's height, art pixels, its middle this far under the body's feet (BREAKER PERCENT Y), and how far it leans, degrees.
    static let percentHeight: CGFloat = 16
    nonisolated(unsafe) static var percentLift: CGFloat = 16
    static let percentLean: CGFloat = 12
    /// The decimal and the percent sign against the whole number; the sign's room off the tenths, art pixels.
    static let percentSmallShare: CGFloat = 0.55
    static let percentSignGap: CGFloat = 2
    /// The two characters after the point moved on, art pixels (BREAKER DECIMAL NUDGE).
    static var decimalNudge: CGFloat = 2
    /// A hit's shake: frames, art pixels at its most per point of damage and in all, and the pop in size.
    static let shakeFrames = 20
    static let shakePerDamage: CGFloat = 1
    static let shakeMost: CGFloat = 8
    static let shakePop: CGFloat = 0.3
    /// A mend's jitter: frames, art pixels at most.
    static let jitterFrames = 12
    static let jitter: CGFloat = 2
    /// A mend's light: beams rising round the barrier, how many, how wide and tall, how far they rise
    /// and how long; and sparkles rising with them.
    static let healBeams = 6
    static let healBeamWidth: CGFloat = 4
    static let healBeamHeight: CGFloat = 48
    static let healRise: CGFloat = 32
    static let healSeconds = 0.7
    static let healSparkles = 14
    /// Parking or taking back the rim lights the hand this many frames, in the bright.
    static let handFlashFrames = 15
    /// The barrier's tiles growing back in, frames.
    static let growFrames = 8
    /// A hit lights the tiles round where it landed, within this many degrees, fading over its frames;
    /// and sets tiles moving in and out of the sphere, this share of them, art pixels at most, a new
    /// set every few frames, fading over its own.
    static let hitLitFrames = 12
    static let hitSpreadDegrees: Float = 40
    static let wobbleFrames = 12
    static let wobbleShare: Float = 0.35
    static let wobbleReach: Float = 2
    static let wobbleStepFrames = 2
    /// A hit holds the barrier's turn this many frames; one of at least `popDamage` knocks out the
    /// `popTiles` tiles nearest where it landed, gone this long before they grow back, flying off as
    /// the shatter's do but quicker; and the whole sphere's knocked away from it, art pixels a frame
    /// per point of damage up to its most, sprung back.
    static let spinPauseFrames = 20
    static let popDamage = 2.0
    static let popTiles = 3
    static let popGoneFrames = 40
    static let popHangFrames = 24
    /// The knock's speed a point of damage, and its most: the BREAKER NUDGE sliders.
    static var nudgePerDamage: CGFloat = 3
    static var nudgeMost: CGFloat = 5
    static let nudgeSpring: CGFloat = 0.25
    static let nudgeKeep: CGFloat = 0.7
    /// The barrier's hexagons within this many art pixels of its middle, over the body, at this share
    /// of their alpha (BREAKER CLEAR).
    static var clearRadius: Float = 16
    static let clearAlpha: Float = 0.3
    /// A Breaker Ball's summon: the burst, in the summoner's energy, at this share of its size.
    static let summonBurstScale: CGFloat = 0.33
    /// The percentage counting back up to what the barrier has, points a frame.
    static let countUpPerFrame = 4.0
    /// The corner's barrier over `shatter.svg`, in place of FLO, points: the percentage's place off the
    /// corner, inward and down, its middle where a `hudPlaceSize` icon's would be (BREAKER HUD X and Y);
    /// the icon's size and place off the percentage, right and down for both (BREAKER HUD ICON sliders);
    /// and the percentage's size against the one under the body (BREAKER HUD PERCENT).
    static var hudPlace = CGPoint(x: 32, y: 32)
    static let hudPlaceSize: CGFloat = 40
    static var hudIconSize: CGFloat = 42
    static var hudIconX: CGFloat = -42
    static var hudIconY: CGFloat = -2
    static var hudPercentScale: CGFloat = 2
    /// The stock ticker on the scoreboard (STOCK TICKER): its icons' size and spacing, points, and
    /// the crosses' turn, counter-clockwise.
    static var stockTicker = StockTicker.mineralHeart
    static let tickerSize: CGFloat = 12
    static let tickerSpacing: CGFloat = 15
    static let crossTurnDegrees: CGFloat = 15
    /// The hoop appearing: cubes thrown off it, how many, how fast and for how long (off by request).
    static let hoopCubes = 16
    static let hoopCubeSpeed: CGFloat = 1.5
    static let hoopCubeLife: ClosedRange<Double> = 0.3...0.6
    /// Its alpha, against its own, while its defender's own ball is going through it, and how far round it that counts.
    static let ownBallAlpha: Float = 0.3
    static let ownBallReach: CGFloat = 1.5
    /// The chain: links in its rope, its slack against the straight way, its sag a frame, art pixels,
    /// how much of its swing it keeps, and how many passes pull its links to length.
    static let chainLinks = 14
    static let chainSlack: CGFloat = 1.15
    static let chainSag: CGFloat = 0.12
    static let chainKeep: CGFloat = 0.96
    static let chainPasses = 8
    /// Its links' cubes breaking off when it's parked: how fast they're thrown, and how long they last.
    static let chainBreakSpeed: CGFloat = 3
    /// Against a head's cube.
    static let chainCubeScale: CGFloat = 1.5
    static let chainBreakLife: ClosedRange<Double> = 0.5...0.9
    /// The shatter's flash, against the barrier's width, and frames.
    static let flashGrowth: CGFloat = 3
    static let flashFrames = 12
}

/// The percentage in Smash Ultimate's manner: the whole number big, the tenths and the sign small,
/// leaning, filled top to bottom in two colours over a thick dark line and a drop shadow. Its colours
/// by tens: white over light grey down to dark red over off-black under 10.
enum BreakerPercent {
    static let bands: [(upper: RGB, lower: RGB)] = [
        (0x891E2B, 0x1C121C), (0x891E2B, 0x391F21), (0xC42430, 0x571C27), (0xEA323C, 0x8E251D), (0xED7614, 0xC64524),
        (0xFFA214, 0xE07438), (0xFFC825, 0xED7614), (0xFFEB57, 0xEDAB50), (0xFFFFFF, 0xB4B4B4), (0xFFFFFF, 0xC7CFDD),
    ]
    static let line: RGB = 0x0E071B
    static let fontName = "BoardofDirectors-Heavy"
    /// Drawn this many times its shown size, so it stays crisp under the camera.
    static let renderScale: CGFloat = 6

    /// What's shown: the whole number, and the tenths with the sign.
    static func parts(_ value: Double) -> (whole: String, small: String) {
        let tenths = Int((max(value, 0) * 10).rounded(.down))
        return ("\(tenths / 10)", ".\(tenths % 10)%")
    }

    /// A character of it: its picture, how far on the next starts, and where its own origin is on the picture; art pixels.
    /// The point is drawn over the rest.
    struct Glyph {
        let texture: SKTexture
        let advance: CGFloat
        let anchor: CGPoint
        let drawnOver: Bool
    }
    private static var glyphs: [String: Glyph] = [:]

    /// Each character of the value, in its band's colours, the whole number big and the rest small.
    static func glyphs(_ value: Double) -> [Glyph] {
        let parts = parts(value)
        let band = min(max(Int((value - 0.0001) / 10), 0), bands.count - 1)
        return parts.whole.map { glyph($0, small: false, band: band) } + parts.small.map { glyph($0, small: true, band: band) }
    }

    /// One character drawn as the whole was: leaning, filled top to bottom over the big line's height,
    /// over its line and shadow, every one on a canvas as tall so their baselines meet.
    static func glyph(_ character: Character, small: Bool, band index: Int) -> Glyph {
        let key = "\(character)|\(small)|\(index)"
        if let made = glyphs[key] { return made }
        _ = Onomatopoeia.registered
        let band = bands[index]
        let size = BreakerLook.percentHeight * renderScale
        let big = UIFont(name: fontName, size: size) ?? TitleText.font(size: size, italic: false)
        let font = small ? (UIFont(name: fontName, size: size * BreakerLook.percentSmallShare) ?? TitleText.font(size: size * BreakerLook.percentSmallShare, italic: false)) : big
        func text(_ colour: UIColor, stroke: CGFloat = 0) -> NSAttributedString {
            NSAttributedString(string: String(character), attributes: [.font: font, .foregroundColor: colour, .strokeColor: colour, .strokeWidth: stroke])
        }
        let lineWidth = size * 0.14
        let lean = tan(BreakerLook.percentLean * .pi / 180)
        let width = text(.white).size().width
        let lineHeight = big.lineHeight
        let pad = lineWidth * 2
        let canvas = CGSize(width: (width + lineHeight * lean + pad * 2).rounded(.up), height: (lineHeight + pad * 2).rounded(.up))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        func render(_ draw: (CGContext) -> Void) -> UIImage {
            UIGraphicsImageRenderer(size: canvas, format: format).image { context in draw(context.cgContext) }
        }
        func leaned(_ context: CGContext, _ draw: () -> Void) {
            context.saveGState()
            context.concatenate(CGAffineTransform(a: 1, b: 0, c: -lean, d: 1, tx: canvas.height * lean, ty: 0))
            draw()
            context.restoreGState()
        }
        let origin = CGPoint(x: pad, y: pad + big.ascender - font.ascender)
        let lettering = render { context in leaned(context) { text(.white).draw(at: origin) } }
        let gradient = render { context in
            let colours = [UIColor(rgb: band.upper).cgColor, UIColor(rgb: band.lower).cgColor] as CFArray
            guard let shading = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0.3, 0.8]) else { return }
            context.drawLinearGradient(shading, start: CGPoint(x: 0, y: pad), end: CGPoint(x: 0, y: pad + lineHeight), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        let filled = render { _ in
            gradient.draw(at: .zero)
            lettering.draw(at: .zero, blendMode: .destinationIn, alpha: 1)
        }
        let strokePercent = lineWidth / font.pointSize * 100 * 2
        let image = render { context in
            leaned(context) {
                text(UIColor(rgb: line).withAlphaComponent(0.6), stroke: strokePercent).draw(at: CGPoint(x: origin.x + lineWidth * 0.5, y: origin.y + lineWidth * 0.8))
                text(UIColor(rgb: line), stroke: strokePercent).draw(at: origin)
            }
            filled.draw(at: .zero)
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        let gap = character == "%" ? BreakerLook.percentSignGap * renderScale : 0
        let made = Glyph(texture: texture, advance: (width + gap) / renderScale, anchor: CGPoint(x: (pad + lineHeight * lean / 2 - gap) / canvas.width, y: 0.5),
                         drawnOver: character == ".")
        glyphs[key] = made
        return made
    }
}

/// A barrier tile's way out from its middle, the sphere turned by `spin`.
func barrierTileDirection(_ number: Int, spin: Float) -> SIMD3<Float> {
    let turn = simd_quatf(angle: spin, axis: simd_normalize(SIMD3<Float>(0.3, 0.2, 1)))
    let tile = HexSphere.layout[number]
    return (turn * simd_quatf(from: [0, 0, 1], to: tile.direction)).act(SIMD3<Float>(0, 0, 1))
}

/// Where a hit landed on a barrier, the way out from its middle, and frames since.
struct BarrierHit {
    var direction: SIMD3<Float>
    var age = 0
}

/// A standing barrier's tiles: `HexSphere`'s, lit round where it's just been hit, and shaken, tiles
/// moving in and out, after; behind the bodies and the percentage.
enum BarrierLook {
    /// The share of a mixed barrier's tiles (Diamond's) in `accents` rather than its own colour.
    static let accentShare: Float = 0.25

    /// Tile `number`'s colour: its barrier's, or for a mixed barrier, one of `accents` on a share of its
    /// tiles, the same tiles always, so a tile keeps its colour as the barrier turns and as it shatters.
    static func tileColour(_ number: Int, colour: SIMD4<Float>, accents: [SIMD4<Float>]) -> SIMD4<Float> {
        guard !accents.isEmpty else { return colour }
        let pick = shatterRandom(number, 7, seed: 0)
        guard pick < accentShare else { return colour }
        return accents[min(Int(pick / accentShare * Float(accents.count)), accents.count - 1)]
    }

    /// Its tiles `tileRadius` big (shrinking with the barrier), at `radius`; those in `missing` left out;
    /// those drawn within `clearRadius` of its middle at `clearAlpha` of their alpha; some in `accents`.
    static func instances(centre: SIMD3<Float>, radius: Float, tileRadius: Float, tileShare: Float, spin: Float, colour: SIMD4<Float>, flash: SIMD4<Float>,
                          time: Double, hits: [BarrierHit], wobble: Float, wobbleStep: Int, missing: Set<Int> = [], alphaShare: Float = 1,
                          clearRadius: Float = 0, clearAlpha: Float = 1, accents: [SIMD4<Float>] = []) -> [CubeInstance] {
        let turn = simd_quatf(angle: spin, axis: simd_normalize(SIMD3<Float>(0.3, 0.2, 1)))
        let window = UInt32(truncatingIfNeeded: Int(time * HexSphere.flashesPerSecond))
        let spread = cos(BreakerLook.hitSpreadDegrees * .pi / 180)
        func mixed(_ number: Int, _ salt: UInt32) -> UInt32 {
            var value = (UInt32(number) &* 73_856_093) ^ (salt &* 19_349_663)
            value = (value ^ (value >> 16)) &* 0x45D9_F3B
            return value ^ (value >> 16)
        }
        return HexSphere.layout.enumerated().compactMap { number, tile -> CubeInstance? in
            guard !missing.contains(number) else { return nil }
            let base = turn * simd_quatf(from: [0, 0, 1], to: tile.direction) * simd_quatf(angle: tile.twist, axis: [0, 0, 1])
            let outward = base.act(SIMD3<Float>(0, 0, 1))
            var lit: Float = 0
            for hit in hits where hit.age < BreakerLook.hitLitFrames {
                let along = simd_dot(outward, hit.direction)
                guard along > spread else { continue }
                lit = max(lit, (along - spread) / (1 - spread) * (1 - Float(hit.age) / Float(BreakerLook.hitLitFrames)))
            }
            let flashing = mixed(number, window) % 100 < UInt32(HexSphere.flashShare)
            var shade = flashing ? flash : tileColour(number, colour: colour, accents: accents)
            shade = shade + (flash - shade) * lit
            // Over the middle, faded, so the body inside shows; eased in over its last few pixels.
            let across = simd_length(SIMD2<Float>(outward.x, outward.y)) * radius
            let clear = clearRadius > 0 ? clearAlpha + (1 - clearAlpha) * min(max((across - clearRadius + 4) / 4, 0), 1) : 1
            shade.w = ((flashing ? HexSphere.flashAlpha : HexSphere.alpha) + (1 - HexSphere.alpha) * lit) * alphaShare * clear
            var shift: Float = 0
            let step = UInt32(truncatingIfNeeded: wobbleStep)
            if wobble > 0, Float(mixed(number, step &+ 77) % 1000) / 1000 < BreakerLook.wobbleShare {
                shift = (Float(mixed(number, step &+ 131) % 1000) / 500 - 1) * BreakerLook.wobbleReach * wobble
            }
            let model = simd_float4x4.translation(centre + outward * shift) * simd_float4x4(base)
                * .scale(SIMD3<Float>(tileRadius * tileShare, tileRadius * tileShare, radius))
            // The far half behind the body, the near half over it, where BREAKER CLEAR shows the body through.
            return CubeInstance(model: model, color: shade, flags: SIMD4<Float>(outward.z < 0 ? 1 : 0, 0, 0, 0))
        }
    }
}

/// A shattered barrier's tiles, Breath of the Wild's broken weapon: burst out, caught hanging in the
/// air, turning slowly, then gone.
struct BarrierShatter {
    var centre: SIMD3<Float>
    var radius: Float
    var tileRadius: Float
    /// Only these tiles, a hit's few knocked out; nil, every one; and how long each hangs.
    var tiles: Set<Int>? = nil
    var hangFrames = BarrierShatter.hangFrames
    var spin: Float
    var colour: SIMD4<Float>
    var flash: SIMD4<Float>
    var age = 0
    var seed: UInt32
    /// A mixed barrier's other colours, its tiles keeping theirs as they fly (`BarrierLook.tileColour`).
    var accents: [SIMD4<Float>] = []

    /// Frames of the burst's ease, how long each tile hangs (give or take), and its fade.
    static let burstFrames: Float = 5
    static let hangFrames = 70
    static let hangSpread = 15
    static let fadeFrames = 20
    static let flashFrames = 6
    /// How far out a tile bursts, against the barrier's radius, and its slow drift after, pixels a frame.
    static let burstReach: ClosedRange<Float> = 0.5...1.6
    static let drift: Float = 0.08
    static let fall: Float = 0.03
    /// Its turn in the burst, radians, and after, radians a frame.
    static let burstTurn: Float = 2.5
    static let hangTurn: Float = 0.02
    static let alpha: Float = 0.6

    var finished: Bool { age > hangFrames + BarrierShatter.hangSpread + BarrierShatter.fadeFrames }

    private func random(_ number: Int, _ salt: UInt32) -> Float { shatterRandom(number, salt, seed: seed) }

    func instances() -> [CubeInstance] {
        let turn = simd_quatf(angle: spin, axis: simd_normalize(SIMD3<Float>(0.3, 0.2, 1)))
        let time = Float(age)
        let burst = 1 - exp(-time / BarrierShatter.burstFrames)
        return HexSphere.layout.enumerated().compactMap { number, tile in
            guard tiles?.contains(number) ?? true else { return nil }
            let hang = hangFrames + Int(random(number, 1) * Float(2 * BarrierShatter.hangSpread)) - BarrierShatter.hangSpread
            let fading = Float(age - hang) / Float(BarrierShatter.fadeFrames)
            guard fading < 1 else { return nil }
            let left = 1 - max(fading, 0)
            let base = turn * simd_quatf(from: [0, 0, 1], to: tile.direction) * simd_quatf(angle: tile.twist, axis: [0, 0, 1])
            let outward = base.act(SIMD3<Float>(0, 0, 1))
            let relative = outward * radius
            let reach = BarrierShatter.burstReach.lowerBound + random(number, 2) * (BarrierShatter.burstReach.upperBound - BarrierShatter.burstReach.lowerBound)
            let offset = outward * (radius * reach * burst + BarrierShatter.drift * time) + SIMD3<Float>(0, -BarrierShatter.fall * time, 0)
            let axis = simd_normalize(SIMD3<Float>(random(number, 3) - 0.5, random(number, 4) - 0.5, random(number, 5) - 0.5) + SIMD3<Float>(0, 0, 0.001))
            let tumble = simd_quatf(angle: BarrierShatter.burstTurn * burst * (random(number, 6) + 0.5) + BarrierShatter.hangTurn * time, axis: axis)
            let model = simd_float4x4.translation(centre + relative + offset) * simd_float4x4(tumble) * .scale(SIMD3<Float>(repeating: left))
                * .translation(-relative) * simd_float4x4(base) * .scale(SIMD3<Float>(tileRadius, tileRadius, radius))
            var shade = age < BarrierShatter.flashFrames ? flash : BarrierLook.tileColour(number, colour: colour, accents: accents)
            shade.w = BarrierShatter.alpha * left
            // Split as the standing barrier is: the far half's pieces behind the body, the near half's over it.
            return CubeInstance(model: model, color: shade, flags: SIMD4<Float>(outward.z < 0 ? 1 : 0, 0, 0, 0))
        }
    }
}

/// A shatter's random between 0 and 1, the same for the same piece, salt and seed.
func shatterRandom(_ number: Int, _ salt: UInt32, seed: UInt32) -> Float {
    var mixed = (UInt32(number) &* 73_856_093) ^ (seed &* 19_349_663) ^ (salt &* 83_492_791)
    mixed = (mixed ^ (mixed >> 16)) &* 0x45D9_F3B
    mixed ^= mixed >> 16
    return Float(mixed % 10_000) / 10_000
}

/// One triangle, both sides drawn: any triangle is it stretched (`GlassShatter`).
enum ShardMesh {
    static let unit: [CubeVertex] = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)].map {
        CubeVertex(position: SIMD4<Float>($0, 1), normal: SIMD4<Float>(0, 0, 1, 0))
    }
}

/// A scored-on rim's glass: its rim and board cracked out from the rim's middle, rings across the
/// cracks, into random pieces that burst out as a shattered barrier's tiles do, hang turning, then go.
struct GlassShatter {
    struct Shard {
        var middle: SIMD3<Float>
        /// Its triangles' corners, off its middle.
        var triangles: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)]
    }
    var impact: SIMD3<Float>
    var shards: [Shard] = []
    var reach: Float
    var colour: SIMD4<Float>
    var flash: SIMD4<Float>
    var age = 0
    var seed: UInt32

    /// The cracks out from the middle, and the rings across them, each line's share of the way out.
    static let cracks = 9
    /// Frames of the barrier's shatter it plays each frame (GLASS SPEED): a scored-on rim breaks quicker.
    nonisolated(unsafe) static var speed = 2
    static let rings: [Float] = [0.3, 0.65]
    static let ringJitter: Float = 0.12
    static let crackJitter: Float = 0.35
    /// Its pieces off the ground, burst out by this share of the glass's size.
    static let burstReach: ClosedRange<Float> = 0.4...1.2

    /// `bounds`, the rim and board's, scene points; cracked from `impact`.
    init(bounds: CGRect, impact: CGPoint, colour: SIMD4<Float>, flash: SIMD4<Float>, seed: UInt32) {
        self.impact = SIMD3<Float>(Float(impact.x), Float(impact.y), 0)
        self.reach = Float(max(bounds.width, bounds.height)) / 2
        self.colour = colour
        self.flash = flash
        self.seed = seed
        let count = GlassShatter.cracks
        let angles = (0..<count).map { crack in
            (Float(crack) + (shatterRandom(crack, 11, seed: seed) - 0.5) * GlassShatter.crackJitter) / Float(count) * 2 * .pi
        }
        // How far each crack runs: to the edge of the bounds its way.
        func edge(_ angle: Float) -> Float {
            let way = SIMD2<Float>(cos(angle), sin(angle))
            let along = [way.x > 0.001 ? (Float(bounds.maxX) - self.impact.x) / way.x : .infinity,
                         way.x < -0.001 ? (Float(bounds.minX) - self.impact.x) / way.x : .infinity,
                         way.y > 0.001 ? (Float(bounds.maxY) - self.impact.y) / way.y : .infinity,
                         way.y < -0.001 ? (Float(bounds.minY) - self.impact.y) / way.y : .infinity]
            return max(along.min() ?? 0, 0)
        }
        func point(_ crack: Int, _ ring: Int) -> SIMD3<Float> {
            let angle = angles[crack % count]
            let share: Float
            if ring == 0 { share = 0 } else if ring > GlassShatter.rings.count { share = 1 } else {
                share = GlassShatter.rings[ring - 1] + (shatterRandom(crack % count, UInt32(20 + ring), seed: seed) - 0.5) * GlassShatter.ringJitter
            }
            return self.impact + SIMD3<Float>(cos(angle), sin(angle), 0) * edge(angle) * share
        }
        for crack in 0..<count {
            for ring in 0...GlassShatter.rings.count {
                let corners = [point(crack, ring), point(crack + 1, ring), point(crack + 1, ring + 1), point(crack, ring + 1)]
                let middle = corners.reduce(SIMD3<Float>(), +) / Float(corners.count)
                let local = corners.map { $0 - middle }
                let triangles = ring == 0 ? [(local[0], local[2], local[3])] : [(local[0], local[1], local[2]), (local[0], local[2], local[3])]
                shards.append(Shard(middle: middle, triangles: triangles))
            }
        }
    }

    var finished: Bool { age > BarrierShatter.hangFrames + BarrierShatter.hangSpread + BarrierShatter.fadeFrames }

    func instances() -> [CubeInstance] {
        let time = Float(age)
        let burst = 1 - exp(-time / BarrierShatter.burstFrames)
        return shards.enumerated().flatMap { number, shard -> [CubeInstance] in
            let hang = BarrierShatter.hangFrames + Int(shatterRandom(number, 1, seed: seed) * Float(2 * BarrierShatter.hangSpread)) - BarrierShatter.hangSpread
            let fading = Float(age - hang) / Float(BarrierShatter.fadeFrames)
            guard fading < 1 else { return [] }
            let left = 1 - max(fading, 0)
            let away = shard.middle - impact
            let outward = simd_normalize((simd_length(away) > 0.01 ? simd_normalize(away) : SIMD3<Float>(0, 1, 0))
                                         + SIMD3<Float>(0, 0, shatterRandom(number, 7, seed: seed) - 0.5))
            let reachShare = GlassShatter.burstReach.lowerBound + shatterRandom(number, 2, seed: seed) * (GlassShatter.burstReach.upperBound - GlassShatter.burstReach.lowerBound)
            let offset = outward * (reach * reachShare * burst + BarrierShatter.drift * time) + SIMD3<Float>(0, -BarrierShatter.fall * time, 0)
            let axis = simd_normalize(SIMD3<Float>(shatterRandom(number, 3, seed: seed) - 0.5, shatterRandom(number, 4, seed: seed) - 0.5,
                                                   shatterRandom(number, 5, seed: seed) - 0.5) + SIMD3<Float>(0, 0, 0.001))
            let tumble = simd_quatf(angle: BarrierShatter.burstTurn * burst * (shatterRandom(number, 6, seed: seed) + 0.5) + BarrierShatter.hangTurn * time, axis: axis)
            let placed = simd_float4x4.translation(shard.middle + offset) * simd_float4x4(tumble) * .scale(SIMD3<Float>(repeating: left))
            var shade = age < BarrierShatter.flashFrames ? flash : colour
            shade.w = BarrierShatter.alpha * left
            return shard.triangles.map { first, second, third in
                let stretch = simd_float4x4(columns: (SIMD4<Float>(second - first, 0), SIMD4<Float>(third - first, 0),
                                                      SIMD4<Float>(0, 0, 1, 0), SIMD4<Float>(first, 1)))
                return CubeInstance(model: placed * stretch, color: shade)
            }
        }
    }
}

/// Breaker Ball's stock ticker: three icons a side on the scoreboard, lit in the side's energy.
enum StockTicker: Int, CaseIterable {
    /// Three lit; each basket scored on you puts one of yours out.
    case mineralHeart
    /// Three dark; each basket scored on you lights one of yours. Both crosses turned 15 degrees.
    case crossSlash
    case splitCross
    /// Three dark; each basket you score lights one of yours, as the rounds do.
    case moebiusTriangle

    var title: String {
        switch self {
        case .mineralHeart: "HEART"
        case .crossSlash: "SLASH"
        case .splitCross: "CROSS"
        case .moebiusTriangle: "MOEBIUS"
        }
    }
    var icon: String {
        switch self {
        case .mineralHeart: "futuristic_icon_mineral_heart"
        case .crossSlash: "futuristic_icon_cross_slash"
        case .splitCross: "futuristic_icon_split_cross"
        case .moebiusTriangle: "futuristic_icon_moebius_triangle"
        }
    }
    var turned: Bool { self == .crossSlash || self == .splitCross }
    /// How many of a side's three are lit, from that side's baskets and the other's.
    func lit(scored: Int, scoredOn: Int) -> Int {
        switch self {
        case .mineralHeart: max(BreakerRules.winningScore - scoredOn, 0)
        case .crossSlash, .splitCross: min(scoredOn, BreakerRules.winningScore)
        case .moebiusTriangle: min(scored, BreakerRules.winningScore)
        }
    }
}
