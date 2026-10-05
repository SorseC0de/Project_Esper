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
    case none, webWater, superSmoothie, flashFizz, platformShake, quakeUp, zeusJuice, frostTea, blazingBoba, pulsepistol, surfSoda, titanTea, galeAle, zTea

    var label: String { ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N"][rawValue] }

    var power: Power {
        switch self {
        case .none: .none
        case .webWater: .webWater
        case .superSmoothie: .superSmoothie
        case .flashFizz: .flashFizz
        case .platformShake: .platformShake
        case .quakeUp: .quakeUp
        case .zeusJuice: .zeusJuice
        case .frostTea: .frostTea
        case .blazingBoba: .blazingBoba
        case .pulsepistol: .pulsepistol
        case .surfSoda: .surfSoda
        case .titanTea: .titanTea
        case .galeAle: .galeAle
        case .zTea: .zTea
        }
    }
}

/// How each frame of the dunk sequence is drawn: nudged from the body's place on the rim
/// by this many art pixels, across (mirrored for the other rim) and up. Found on the
/// sliders with `DunkTuning` on, as the user placed them: the throw stance, then the
/// six sheet frames.
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
    static func offsets(for look: StageLook) -> [CGPoint] { look == .footballField ? stadiumOffsets : courtOffsets }
    /// Titan Tea's whole dunk moved by this on top of each frame's, on every stage; on
    /// TITAN DUNK X and Y with `DunkTuning` on.
    nonisolated(unsafe) static var titanOffset = CGPoint(x: -5, y: -11)
    static func set(_ offset: CGPoint, frame: Int, for look: StageLook) {
        if look == .footballField { stadiumOffsets[frame] = offset } else { courtOffsets[frame] = offset }
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

/// Zeus Juice's charge swirl, `lightning_charge`, drawn at this share of its 240-pixel
/// sheet round the ball in hand.
enum ZeusTuning {
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
    static let numberScale: CGFloat = 1.5
}

/// The backboard, a cluster of flashes behind each rim: its place against the rim, in art
/// pixels, its size, its shear in degrees and its opacity. The sim's box matches it.
/// Longball Stadium's zonal camera: within this share of the screen's width from its edge,
/// the local player sends it sliding to the next zone.
/// The chevrons over the basket the ball's holder scores on: the top one this many art
/// pixels over the rim, on the BASKET CHEVRON Y debug slider with `slider`.
enum ChevronTuning {
    nonisolated(unsafe) static var basketLift: CGFloat = 18
    static let slider = false
}

/// Wetshot Wake's water: the tint over everything (WATER TINT), and the screen's sway (WATER
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
    static let colours: [RGB] = [7, 11, 19, 20, 27].map { PixelPalette.colours[$0] }
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
    /// A shake off the ball: how many frames, and how far up the backboard counts from the rim, in units.
    static let jitterFrames = 8
    static let boardHeight = 20.0
    static let damping: CGFloat = 0.08
}

enum HoopTuning {
    /// Where the rim turns, on its art's canvas (0 to 1, from the bottom left): the back edge
    /// of its ellipse, where it meets the backboard.
    static func pivot(for look: StageLook) -> CGPoint {
        [StageLook.court, .elements, .wetshot, .flight].contains(look) ? CGPoint(x: 29.5 / 48, y: 1 - 35.5 / 48) : CGPoint(x: 27.5 / 48, y: 1 - 34 / 48)
    }
    /// The hoop's two pieces for a stage: Wreck Center's straight on, the rest turned.
    static func art(for look: StageLook) -> (backboard: String, rim: String) {
        [StageLook.court, .elements, .wetshot, .flight].contains(look) ? ("backboard_straight", "hoop_straight") : ("backboard", "hoop")
    }
    nonisolated(unsafe) static var courtOffset = CGPoint(x: 5, y: 10)
    /// The hoop offset the nets' NET X and Y were first set against: a net goes as far
    /// from there as its stage's hoop art does.
    static let netReference = CGPoint(x: 5, y: 10)
    nonisolated(unsafe) static var stadiumOffset = CGPoint(x: 0, y: 10)
    static func offset(for look: StageLook) -> CGPoint { look == .footballField ? stadiumOffset : courtOffset }
    static func set(_ offset: CGPoint, for look: StageLook) {
        if look == .footballField { stadiumOffset = offset } else { courtOffset = offset }
    }
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
}

/// The goalposts: the crossbar's height below the rim and the uprights' length above it,
/// in art pixels, and the crossbar's tilt in degrees, on the CROSSBAR ANGLE slider until
/// it's settled; the far end rises, and its upright with it.
enum GoalpostTuning {
    static let crossbarBelowRim: CGFloat = 20
    static let prongHeight: CGFloat = 100
    nonisolated(unsafe) static var crossbarAngle: CGFloat = 25
    /// The stands, sky, rails and floodlights above the turf covered in flat black, so tuning
    /// sliders read over it; off, they show.
    static let sceneryHidden = false
    /// The gold's width, and the black line round it and round the light panels.
    static let thickness: CGFloat = 8
    static let outline: CGFloat = 1
    /// The height, in units, the goalposts are drawn for, apart from the rims.
    static let postRimHeight = 120.0
}

/// Tuning the dunk's frames: with this on, the match doesn't run; player 1 is held on the
/// right rim in the dunk, on the sequence frame the DUNK FRAME slider picks, and the
/// DUNK X and DUNK Y sliders nudge that frame's art. The corner readout prints the table.
/// The FLO meters' look, the whole meter's scale on a slider: the whole meter's scale, the bar's and
/// the word's own, the word's left and right ends' heights over its middle's, and the word moved
/// from its place, in points.
enum FloTuning {
    nonisolated(unsafe) static var meterScale: CGFloat = 0.75
    /// The whole meter moved up from level with the scoreboard, in points.
    nonisolated(unsafe) static var meterY: CGFloat = -2
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

    /// The word's and MAX's four colours: gold's first over blue's (the cyan), outlined plum's
    /// second over purple's last.
    static let colours = Onomatopoeia.Colours(upper: EsperPalette.gold.highlight, lower: EsperPalette.blue.highlight,
                                              lineUpper: EsperPalette.plum.light, lineLower: EsperPalette.purple.shadow)
    /// Bar A's word short of full: palette 34 over 51, outlined as ever.
    static let shortColours = Onomatopoeia.Colours(upper: PixelPalette.colours[34], lower: PixelPalette.colours[51],
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
    /// In FloState the stroke cycles these, a tenth of a second each.
    static let floStateStroke: [RGB] = [6, 7, 8, 18, 19, 20, 26, 27, 28].map { PixelPalette.colours[$0] }
    static let floStateStrokeStepSeconds = 0.1
    /// Spending FLO, sparkles at the fill's end: this many a second, each this long, in points across.
    static let sparklesPerSecond = 30.0
    static let sparkleSeconds = 0.4
    static let sparkleSize: CGFloat = 3
    /// How long after a FLO is spent the sparkles keep coming.
    static let sparkleAfterSpendSeconds = 0.3
}

enum DunkTuning {
    /// On to place dunk art: the game holds a body hung on the right rim, with sliders.
    static let enabled = false
    /// The stage the tuning starts on, since the held match can't reach the stage select.
    static let stage = StageChoice.wreckCenter
    nonisolated(unsafe) static var frame = 0
}

/// The glow, as GameMaker's Glow filter had it: what counts as bright, how soft the cut is,
/// how far it spreads, how strong it comes back, and its colour.
enum GlowSettings {
    /// Luminance above which a pixel glows, and the higher bar the bodies have to clear.
    static let threshold: Float = 0.2
    static let bodyThreshold: Float = 0.8
    static let softness: Float = 0.2
    /// Each pass blurs across and down at half size; more spreads further.
    static let blurPasses = 2
    static let intensity: Float = 1.0
    static let tint = SIMD4<Float>(1, 1, 1, 1)
}
