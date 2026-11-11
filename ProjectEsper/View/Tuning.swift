import SpriteKit
import EsperSim
import Foundation

/// How the head follows the body, on the picker. Both close half the gap each frame; B
/// leads sideways instead of trailing, the offset reversed across only.
enum HeadVariant: Int, CaseIterable {
    case a, b

    var label: String { ["A", "B"][rawValue] }

    /// The share of the gap closed each frame.
    var lag: CGFloat { 0.5 }

    var reversedAcross: Bool { self == .b }
}

/// The power level the POWER picker's choice is played at.
enum PowerLevelVariant: Int, CaseIterable {
    case one, two
    var label: String { ["1", "2"][rawValue] }
    var level: Int { rawValue + 1 }
}

/// The powers on the picker. A is none.
enum PowerVariant: Int, CaseIterable {
    case none, webWater, superSmoothie, flashFizz, platformShake, voltaCola, frostTea, blazingBoba, pulsepistol, surfSoda, titanTea, galeAle, zTea, phantomFrappe

    var label: String { ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N"][rawValue] }

    var power: Power {
        switch self {
        case .none: .none
        case .webWater: .webWater
        case .superSmoothie: .superSmoothie
        case .flashFizz: .flashFizz
        case .platformShake: .platformShake
        case .voltaCola: .voltaCola
        case .frostTea: .frostTea
        case .blazingBoba: .blazingBoba
        case .pulsepistol: .pulsepistol
        case .surfSoda: .surfSoda
        case .titanTea: .titanTea
        case .galeAle: .galeAle
        case .zTea: .zTea
        case .phantomFrappe: .phantomFrappe
        }
    }
}

/// How each frame of the dunk sequence is drawn: nudged from the body's place on the rim
/// by this many art pixels, across (mirrored for the other rim) and up. Found on the
/// sliders with `DunkTuning` on, as the user placed them: the throw stance, then the
/// sheet's frames.
enum DunkArt {
    /// Per stage, since each stage's hoop art is its own: Wreck Center's for the straight-on
    /// hoop (starting from Stadium's, to be tuned), and Longball Stadium's.
    nonisolated(unsafe) static var courtOffsets: [CGPoint] = [
        CGPoint(x: -6, y: 10), CGPoint(x: -4, y: 12), CGPoint(x: -2, y: 16), CGPoint(x: 2, y: 1),
        CGPoint(x: -3, y: 3), CGPoint(x: -1, y: -1), CGPoint(x: -1, y: -1),
    ]
    nonisolated(unsafe) static var stadiumOffsets: [CGPoint] = [
        CGPoint(x: -6, y: 10), CGPoint(x: -4, y: 12), CGPoint(x: -2, y: 16), CGPoint(x: 2, y: 1),
        CGPoint(x: -3, y: 3), CGPoint(x: -1, y: -1), CGPoint(x: -1, y: -1),
    ]
    /// The spin dunk's (`Animation.dunkSpins`): the court's as the user placed them on Wreck Center;
    /// the stadium's still seeded from the plain dunk's matching poses.
    nonisolated(unsafe) static var spinCourtOffsets: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: -6, y: 8), CGPoint(x: -6, y: 12), CGPoint(x: -6, y: 14), CGPoint(x: -2, y: 12),
        CGPoint(x: -2, y: 12), CGPoint(x: -2, y: 10), CGPoint(x: 0, y: 6), CGPoint(x: -2, y: 0), CGPoint(x: -3, y: 0),
        CGPoint(x: -3, y: 0),
    ]
    nonisolated(unsafe) static var spinStadiumOffsets: [CGPoint] = [
        CGPoint(x: -6, y: 10), CGPoint(x: -4, y: 12), CGPoint(x: -4, y: 12), CGPoint(x: -4, y: 12), CGPoint(x: -4, y: 12),
        CGPoint(x: -4, y: 12), CGPoint(x: -3, y: 14), CGPoint(x: -2, y: 16), CGPoint(x: -3, y: 3), CGPoint(x: -3, y: 3),
        CGPoint(x: -1, y: -1),
    ]
    /// The Tutorial hub's front-facing hoops' (`Hoop.frontFacing`): the court's to the slam, then its own.
    nonisolated(unsafe) static var spinFrontOffsets: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: -6, y: 8), CGPoint(x: -6, y: 12), CGPoint(x: -6, y: 14), CGPoint(x: -2, y: 12),
        CGPoint(x: -2, y: 12), CGPoint(x: -2, y: 10), CGPoint(x: 0, y: 6), CGPoint(x: -2, y: 1), CGPoint(x: -1, y: 2),
        CGPoint(x: -1, y: 2),
    ]
    nonisolated(unsafe) static var frontOffsets: [CGPoint] = courtOffsets
    static func offsets(for look: StageLook, frontFacing: Bool) -> [CGPoint] {
        if frontFacing { return Animation.dunkSpins ? spinFrontOffsets : frontOffsets }
        if Animation.dunkSpins { return look.tiltedHoop ? spinStadiumOffsets : spinCourtOffsets }
        return look.tiltedHoop ? stadiumOffsets : courtOffsets
    }
    static func set(_ offset: CGPoint, frame: Int, for look: StageLook, frontFacing: Bool) {
        switch (Animation.dunkSpins, frontFacing, look.tiltedHoop) {
        case (true, true, _): spinFrontOffsets[frame] = offset
        case (false, true, _): frontOffsets[frame] = offset
        case (true, false, true): spinStadiumOffsets[frame] = offset
        case (true, false, false): spinCourtOffsets[frame] = offset
        case (false, false, true): stadiumOffsets[frame] = offset
        case (false, false, false): courtOffsets[frame] = offset
        }
    }
}

/// Whether the head's fire and the double jump's platform are drawn with `esper_spark`,
/// scaled down to the squares' size, rather than the hard squares.
enum ParticleLook {
    static let sprites = true
    /// The regular energy off a head as small cubes turning in 3D, drawn by the Metal layer,
    /// in place of the `esper_particle` sprite (parked: false brings it back): this many art
    /// pixels on an edge, this many a second off a head (half with a power's own
    /// particles), let go anywhere within `cubeSpread` art pixels of the crown's middle
    /// either way, spun up to this fast on each axis, radians a second. `cubeSliders` puts
    /// the size and the spread on the debug panel.
    static let cubes = true
    static let cubeSliders = false
    nonisolated(unsafe) static var cubeSize: Float = 3
    static let cubeRate: Float = 24
    /// What rises off a head or a leg leans toward the ball's side: pushed this hard along x,
    /// art pixels a second each second, easing off inside this many art pixels of level with it.
    static let flowSpeed: CGFloat = 140
    static let flowEaseDistance: CGFloat = 6
    /// With the ball in hand, it sways side to side instead, this many times a second, as hard.
    static let swayPerSecond = 1.1
    /// A human's legs' own cubes, smaller: size and spread as the head's, on sliders beside
    /// them; this many a second off each leg, cubes only.
    nonisolated(unsafe) static var legCubeSize: Float = 2
    nonisolated(unsafe) static var legCubeSpread: Float = 1
    /// How far a cube trail runs, head's and legs' alike, art pixels: a cube lives as long as it
    /// takes to rise this far. It was 14, the head's speed over 0.6 seconds. A point longer for
    /// each 10 FLO, to 14 at most.
    static let cubeTrail: Float = 4
    static let cubeTrailMost = 14.0
    static let legCubeRate: Float = 12
    nonisolated(unsafe) static var cubeSpread: Float = 5
    static let cubeSpin: Float = 6
    /// Each head particle's size, in art pixels square.
    static let energySize: CGFloat = 10
    static let snowflakeSize: CGFloat = 6
    static let fireSize: CGFloat = 12
    static let lightningSize: CGFloat = 8
    static let bubbleSize: CGFloat = 10
    /// Surf Soda's bubbles, a light plum or the pixel palette's dark one by a coin flip.
    static let sodas = [SKColor(rgb: EsperPalette.plum.highlight), SKColor(rgb: PixelPalette.plumDark)]
    /// The board, a plum, and its tail's shadow, the pixel palette's dark plum.
    static let boardPurple: UInt32 = EsperPalette.plum.body
    static let boardShadow: UInt32 = PixelPalette.plumDark
}

/// Volta Cola's charge swirl, `lightning_charge`, drawn at this share of its 240-pixel
/// sheet round the ball in hand.
enum VoltaTuning {
    nonisolated(unsafe) static var chargeScale: Float = 0.17
}

/// The helicopter's size against 96 pixels across.
enum TrafficTuning {
    static let helicopterScale: Float = 0.9
}

/// Gemini's rift, as the portal, with Project Stars' own numbers: the small pair's size
/// against the big, the length trade's period, the jumps' reach in art pixels and rate a
/// second, and how faint a plate can roll.
enum RiftLook {
    static let innerScale: CGFloat = 0.5
    static let tradePeriod = 1.5
    static let jumpReach: CGFloat = 1.5
    static let jumpRate = 12.0
    static let faintest = 0.01
}

/// The helmets' drawing against their box, and the yard numbers' size, as tuned.
enum HelmetTuning {
    static let scale: CGFloat = 1.1
    /// Tipped back this far, radians, from the vector's own slight lift.
    static let tilt: CGFloat = .pi / 6 + .pi / 18
    /// Each helmet bobs round a circle this many art pixels across, as a hover does.
    static let orbit: CGFloat = 2
}

/// The backboard, a cluster of flashes behind each rim: its place against the rim, in art
/// pixels, its size, its shear in degrees and its opacity. The sim's box matches it.
/// Longball Stadium's zonal camera: within this share of the screen's width from its edge,
/// the local player sends it sliding to the next zone.
/// The chevrons over the basket the ball's holder scores on: the top one this many art
/// pixels over the rim, on the BASKET CHEVRON Y debug slider with `slider`.
/// A score's orb and its bolt's foot, art pixels up off the rim (STRIKE Y, parked).
enum StrikeTuning {
    nonisolated(unsafe) static var lift: CGFloat = 16
}

/// FloState's run with the ball, whose sheet draws none: the ball rides a ring round the body,
/// seen edge on as a line slanted `tiltDegrees`, its front end down; slid along it and scaled up
/// passing in front, down passing behind. Art pixels from the feet, facing right.
enum BallRing {
    nonisolated(unsafe) static var tiltDegrees: CGFloat = 15
    nonisolated(unsafe) static var radiusPixels: CGFloat = 20
    nonisolated(unsafe) static var centreHeightPixels: CGFloat = 16
    /// Scale added at the front of the ring, taken away at the back.
    nonisolated(unsafe) static var depthScale: CGFloat = 0.25
    nonisolated(unsafe) static var orbitsPerRunCycle: CGFloat = 0.5

    static func place(runPhase: Double) -> (offset: CGPoint, scale: CGFloat, inFront: Bool) {
        let runCycle = CGFloat(EsperSim.Animation.runBallFloState.frameCount)
        let angle = CGFloat(runPhase) / runCycle * orbitsPerRunCycle * 2 * .pi
        let tilt = tiltDegrees * .pi / 180
        let along = radiusPixels * cos(angle)
        let depth = sin(angle)
        let offset = CGPoint(x: (along * cos(tilt)).rounded(), y: (centreHeightPixels - along * sin(tilt)).rounded())
        return (offset, 1 + depthScale * depth, depth > 0)
    }
}

enum ChevronTuning {
    nonisolated(unsafe) static var basketLift: CGFloat = 18
    /// Longball's tilted hoops' own, HOOP CHEVRON X and Y: up from the rim, and across it toward its
    /// backboard, in art pixels.
    nonisolated(unsafe) static var stadiumLift: CGFloat = 14
    nonisolated(unsafe) static var stadiumAcross: CGFloat = -6
    static func offset(for look: StageLook) -> CGPoint {
        look.tiltedHoop ? CGPoint(x: stadiumAcross, y: stadiumLift) : CGPoint(x: 0, y: basketLift)
    }
    static let slider = false
}

/// Hoopfish Hideaway's water: the tint over everything (WATER TINT), and the screen's sway (WATER
/// SWAY), its reach in game pixels, waves down the screen and speed, on the debug panel there.
enum WaterTuning {
    nonisolated(unsafe) static var overlayAlpha: CGFloat = 0.33
    nonisolated(unsafe) static var swayPixels = 1.5
    static let swayWaves = 3.0
    static let swaySpeed = 1.5
}

/// The Elements' rain: how many streaks, 0.5 unless moved, from none to four times as many as at 1 (RAIN DENSITY on
/// the debug panel there, kept between launches).
enum RainTuning {
    static let densityKey = "elements.rain.density.2"
    static var density: Double {
        get { (UserDefaults.standard.object(forKey: densityKey) as? Double) ?? 0.5 }
        set { UserDefaults.standard.set(newValue, forKey: densityKey) }
    }
}

/// 47's three-point lines: their thickness in art pixels (3PT WIDTH on the UI tuning panel,
/// under HUD, kept between launches), and their breath, from gone to a quarter and back.
enum ThreePointTuning {
    static let widthKey = "ui.threePoint.width"
    static var lineWidth: CGFloat { (UserDefaults.standard.object(forKey: widthKey) as? Double).map { CGFloat($0) } ?? 4 }
    static let breathMax: CGFloat = 0.25
    static let breathSeconds = 6.0
}

/// In the zone (a placeholder, off until something puts a player in it): the players' outline runs through these
/// palette colours, easing from one to the next every `stepSeconds`, and each head particle
/// comes out in one of them at random.
enum ZoneTuning {
    nonisolated(unsafe) static var inTheZone = false
    static let colours: [RGB] = [7, 11, 19, 20, 27].map { PixelPalette.aap64[$0] }
    static let stepSeconds = 0.25

    /// The outline's colour at `time`.
    static func outline(at time: Double) -> SKColor { cycle(colours, at: time, stepSeconds: stepSeconds) }

    /// `colours` eased through in turn, `stepSeconds` each, at `time`.
    static func cycle(_ colours: [RGB], at time: Double, stepSeconds: Double) -> SKColor {
        let phase = time / stepSeconds
        let index = Int(phase.rounded(.down)) % colours.count
        let share = CGFloat(phase - phase.rounded(.down))
        let from = colours[index], to = colours[(index + 1) % colours.count]
        func channel(_ shift: RGB) -> CGFloat {
            let start = CGFloat((from >> shift) & 0xFF), end = CGFloat((to >> shift) & 0xFF)
            return (start + (end - start) * share) / 255
        }
        return SKColor(red: channel(16), green: channel(8), blue: channel(0), alpha: 1)
    }
}

/// The hoop's art, backboard and rim together, against the rim's point, in art pixels:
/// across away from the backboard, and up; the court's, and Longball Stadium's. On HOOP X
/// and Y with `DunkTuning` on, for the stage being played.
/// The rim's give, the view's alone: it turns about its back edge, on the backboard, as a
/// damped spring; a landing on it kicks it down by how fast it came, and a dunk holds it down
/// this far, the dunker turning with it. Degrees, and a share a frame.
enum RimLook {
    static let dunkDip: CGFloat = 12
    static let kickPerSpeed: CGFloat = 4
    static let stiffness: CGFloat = 0.2
    /// A shake off the ball: how many frames (how far up the backboard counts is `Stage.backboardTop`).
    static let jitterFrames = 8
    static let damping: CGFloat = 0.08
}

extension StageLook {
    /// The hoop tilted down, its rim seen from above, with Longball Stadium's hoop, net and dunk
    /// placing; else straight on.
    var tiltedHoop: Bool { self == .footballField || self == .flightB411 }
}

enum HoopTuning {
    /// Where the rim turns, on its art's canvas (0 to 1, from the bottom left): the back edge
    /// of its ellipse, where it meets the backboard.
    static func pivot(for look: StageLook) -> CGPoint {
        look.tiltedHoop ? CGPoint(x: 27.5 / 48, y: 1 - 34 / 48) : CGPoint(x: 29.5 / 48, y: 1 - 35.5 / 48)
    }
    /// The hoop's two pieces for a stage: straight on, Longball Stadium's turned, or Flight B411's
    /// tilted down, the first of the Hoopfish pile's sheets (`backboards`, `hoops`).
    static func art(for look: StageLook) -> (backboard: String, rim: String) {
        if look == .flightB411 { return ("backboards", "hoops") }
        return look.tiltedHoop ? ("backboard", "hoop") : ("backboard_straight", "hoop_straight")
    }
    nonisolated(unsafe) static var courtOffset = CGPoint(x: 5, y: 10)
    /// The hoop offset the nets' NET X and Y were first set against: a net goes as far
    /// from there as its stage's hoop art does.
    static let netReference = CGPoint(x: 5, y: 10)
    nonisolated(unsafe) static var stadiumOffset = CGPoint(x: 0, y: 10)
    static func offset(for look: StageLook) -> CGPoint { look.tiltedHoop ? stadiumOffset : courtOffset }
    static func set(_ offset: CGPoint, for look: StageLook) {
        if look.tiltedHoop { stadiumOffset = offset } else { courtOffset = offset }
    }
}

/// Platform Protein Shake's blocks: their depth, slanted up and back this far a pixel of it, in
/// the scene's pixels; their energy's strength; the cubes they give off, and break into.
enum PlatformLook {
    static let depth: Float = 8
    static let slant = SIMD2<Float>(0.5, 0.5)
    static let alpha: Float = 0.66
    static let cubesPerSecond = 8.0
    static let shatterCubesPerArea: CGFloat = 1.0 / 20
    static let shatterCubes = 12...48
    static let shatterRise: ClosedRange<CGFloat> = 20...40
    static let shatterLife: ClosedRange<Double> = 0.6...0.9
}

/// Phantom Frappe's form: half seen, a third of the way to the energy; its glitch's rows this many
/// pixels high, this share of them jumping up to this many pixels sideways, this many times a second;
/// its head's cubes off the body at this share of the head's rate.
enum PhantomLook {
    static let alpha: CGFloat = 0.5
    static let tint = 0.33
    static let glitchRowHeight = 2.0
    static let glitchRowShare = 0.15
    static let glitchShift: CGFloat = 3
    static let glitchRate = 12.0
    static let cubeRateScale = 0.25
}

enum BackboardTuning {
    static let x: CGFloat = 10
    static let y: CGFloat = 24
    static let size: CGFloat = 0.4
    static let skew: CGFloat = 20
    static let alpha: CGFloat = 0.66
    static let columns = 3
    static let rows = 4
    static let spacing: CGFloat = 9
    /// The fence's sparks past its middle three columns, at this share; a hit's spark fading out over this.
    static let outerScale: CGFloat = 0.75
    static let hitFade: TimeInterval = 1.5
}

/// Tuning the dunk's frames: with this on, the match doesn't run; player 1 is held on the
/// right rim in the dunk, on the sequence frame the DUNK FRAME slider picks, and the
/// DUNK X and DUNK Y sliders nudge that frame's art. The corner readout prints the table.
/// The FLO meters' look, the whole meter's scale on a slider: the whole meter's scale, the bar's and
/// the word's own, the word's left and right ends' heights over its middle's, and the word moved
/// from its place, in points.
/// Z Tea's beam firing, the hooded head at the aim's full tip, in proportion to it: lifted this
/// many art pixels whichever way it's aimed, slid this many back aimed up and forward aimed down;
/// and turned this many times flight's tip, up and down. On the BEAM sliders.
enum BeamHeadTuning {
    nonisolated(unsafe) static var lift: CGFloat = 7
    nonisolated(unsafe) static var slide: CGFloat = 2
    nonisolated(unsafe) static var upTurn: CGFloat = 2
    nonisolated(unsafe) static var downTurn: CGFloat = 3.5
}

enum FloTuning {
    nonisolated(unsafe) static var meterScale: CGFloat = 1.25
    /// The whole meter moved up from level with the scoreboard, in points.
    nonisolated(unsafe) static var meterY: CGFloat = -2
    /// The meters in the screen's top corners: each one's outer end this far in from the corner and
    /// its top this far down (past the safe insets; up into them below 0), in points; FLO INSET X and
    /// Y on the strip. Both level, the second under pause, which sits over it in the same corner.
    nonisolated(unsafe) static var cornerInsetX: CGFloat = 20
    nonisolated(unsafe) static var cornerInsetY: CGFloat = -25
    static let barScale: CGFloat = 1
    static let wordScale: CGFloat = 1.25
    static let leftSkew: CGFloat = 1.5
    static let rightSkew: CGFloat = 0.5
    static let offsetX: CGFloat = 15
    static let offsetY: CGFloat = -6
    /// The bar squeezed across and down, over its scale; the word keeps its own.
    static let xScale: CGFloat = 0.75
    static let yScale: CGFloat = 1.5
    /// The bar's warp: its front (left) and back (right) ends' heights over its middle's, and its
    /// middle raised by this share of its height.
    static let barFront: CGFloat = 1.5
    static let barBack: CGFloat = 0.5
    static let barBend: CGFloat = 0.5
    /// MAX on the bar's top trailing corner when it's full: its scale, and moved, in points.
    static let maxScale: CGFloat = 1.5
    static let maxX: CGFloat = -5
    static let maxY: CGFloat = -15
    /// The stroke round the bar and the word together, in the player's glow, in points.
    static let stroke: CGFloat = 1.5

    /// The stroke in FloState breathes from this much seen to all of it and back, over this long.
    static let strokeBreathLeast: CGFloat = 0.1
    static let strokeBreathSeconds = 3.0
    /// The word's and MAX's four colours: gold's first over blue's (the cyan), outlined plum's
    /// second over purple's last.
    static let colours = Onomatopoeia.Colours(upper: EsperPalette.gold.highlight, lower: EsperPalette.blue.highlight,
                                              lineUpper: EsperPalette.plum.light, lineLower: EsperPalette.purple.shadow)
    /// Bar A's word short of full: palette 34 over 51, outlined as ever.
    static let shortColours = Onomatopoeia.Colours(upper: PixelPalette.aap64[34], lower: PixelPalette.aap64[51],
                                                   lineUpper: EsperPalette.plum.light, lineLower: EsperPalette.purple.shadow)
    /// The A/B test of the bar: A's missing FLO from the word's end on, MAX on the word's top
    /// outer corner, moved and sized on its sliders; B's missing from the far end back. Kept
    /// between launches.
    enum BarVariant: Int { case emptiesFromWord, fillsFromWord }
    private static let variantKey = "esper.floBarVariant"
    static var variant: BarVariant {
        get { BarVariant(rawValue: UserDefaults.standard.integer(forKey: variantKey)) ?? .emptiesFromWord }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: variantKey) }
    }
    nonisolated(unsafe) static var cornerMaxScale: CGFloat = 1.25
    nonisolated(unsafe) static var cornerMaxX: CGFloat = 54
    nonisolated(unsafe) static var cornerMaxY: CGFloat = 0
    /// Spending FLO, sparkles at the fill's end: this many a second, each this long, in points across.
    static let sparklesPerSecond = 30.0
    static let sparkleSeconds = 0.4
    static let sparkleSize: CGFloat = 3
    /// How long after a FLO is spent the sparkles keep coming.
    static let sparkleAfterSpendSeconds = 0.3
}

enum DunkTuning {
    /// On to place dunk art: the game holds a body hung on the right rim, with sliders. The debug
    /// bench's DUNK MODE: player 1 held there at plain size, frame by frame on DUNK FRAME.
    nonisolated(unsafe) static var enabled = false
    /// The stage the tuning starts on, since the held match can't reach the stage select.
    static var stage: StageChoice { frontFacing ? .tutorial : .wreckCenter }
    /// Hung on a Tutorial hub hoop, the front-facing kind, instead of a side rim.
    static let frontFacing = true
    nonisolated(unsafe) static var frame = 0
    /// Held as Titan Tea instead of plain.
    static let titan = false
}

/// The glow, as GameMaker's Glow filter had it: what counts as bright, how soft the cut is,
/// how far it spreads, how strong it comes back, and its colour.
/// Debug strip sliders put away once tuned; their values stay as baked.
enum ParkedSliders {
    /// Only these sliders on the debug bench for now: the hub's spacing, Breaker's, Web Water's swing gap and FloState's ball ring's height and depth scale.
    static var showing: [String] { ["HUB", "BREAKER", "WEB", "RING HEIGHT", "RING DEPTH"] + (DunkTuning.enabled ? ["DUNK"] : []) }
    static func shown(_ title: String) -> Bool { showing.contains { title.hasPrefix($0) } }
    static let net = true
    static let flo = true
    static let kAndALights = true
    static let gemGlow = true
    static let beam = true
}

enum GlowSettings {
    /// Each energy colour's glow, times this: the deep ones' brightest channel still reads darker
    /// than the light ones'. On the debug sliders (GLOW and the gem), kept between launches.
    /// Kept under a second key since the tuned values became the defaults, so the old ones don't stand.
    static func energyGainKey(_ colour: EnergyColour) -> String { "esper.glow.gain2.\(colour.rawValue)" }
    static let energyGainDefaults: [EnergyColour: Float] = [.orange: 1.75, .blue: 1.25, .green: 1.75, .purple: 1.75, .red: 1.25, .teal: 0.75, .lime: 0.75]
    nonisolated(unsafe) static var energyGains: [EnergyColour: Float] = {
        // Teal's and lime's tuned values (0.75 each) over whatever their sliders were left at, once.
        let resetKey = "esper.glow.reset.tealLime2"
        if !UserDefaults.standard.bool(forKey: resetKey) {
            for colour in [EnergyColour.teal, .lime] { UserDefaults.standard.removeObject(forKey: energyGainKey(colour)) }
            UserDefaults.standard.set(true, forKey: resetKey)
        }
        return Dictionary(uniqueKeysWithValues: EnergyColour.hued.map { colour in
            (colour, (UserDefaults.standard.object(forKey: energyGainKey(colour)) as? Double).map(Float.init) ?? energyGainDefaults[colour] ?? 1)
        })
    }()
    /// The nine hued colours for the glow pass: each colour over its brightest channel, its gain in w.
    static var energyUniforms: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        let packed = EnergyColour.hued.map { colour -> SIMD4<Float> in
            let rgb = SIMD3<Float>(Float((colour.glow >> 16) & 0xFF), Float((colour.glow >> 8) & 0xFF), Float(colour.glow & 0xFF)) / 255
            return SIMD4(rgb / max(rgb.max(), 0.001), energyGains[colour] ?? 1)
        }
        return (packed[0], packed[1], packed[2], packed[3], packed[4], packed[5], packed[6], packed[7], packed[8])
    }
    /// Every colour's hood tones for the composite, Diamond's too, the light and the shadow in the same order.
    static var hoodLightUniforms: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        ten(EnergyColour.allCases.map(\.glow))
    }
    static var hoodShadowUniforms: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        ten(EnergyColour.allCases.map(\.hoodShadow))
    }
    private static func ten(_ colours: [RGB]) -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        let packed = colours.map { SIMD4<Float>(Float(($0 >> 16) & 0xFF) / 255, Float(($0 >> 8) & 0xFF) / 255, Float($0 & 0xFF) / 255, 1) }
        return (packed[0], packed[1], packed[2], packed[3], packed[4], packed[5], packed[6], packed[7], packed[8], packed[9])
    }
    /// Luminance above which a pixel glows, and the higher bar the bodies have to clear.
    static let threshold: Float = 0.2
    static let bodyThreshold: Float = 0.8
    static let softness: Float = 0.2
    /// Each pass blurs across and down at half size; more spreads further.
    static let blurPasses = 2
    static let intensity: Float = 1.0
    static let tint = SIMD4<Float>(1, 1, 1, 1)
    /// The share of its glow a hooded head's hood takes, as the customize screen draws it
    /// (`CustomizeArt.glowStrength`): the hood is lighter than the energy colour and big, and at
    /// the whole glow it went to gold; on K&A, under its wash, the whole of it.
    static let hoodShare: Float = 0.6
    static let kAndAHoodShare: Float = 1.0
    static func hoodShare(on look: StageLook) -> Float { look == .kAndA ? kAndAHoodShare : hoodShare }
}
