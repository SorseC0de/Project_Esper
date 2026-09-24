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
    case none, webWater, superSmoothie, flashFizz, platformShake, quakeUp, zeusJuice, frostTea, blazingBoba, pulsepistol

    var label: String { ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"][rawValue] }

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
        }
    }
}

/// How each frame of the dunk sequence is drawn: nudged from the body's place on the rim
/// by this many art pixels, across (mirrored for the other rim) and up. Found on the
/// sliders with `DunkTuning` on, as the user placed them: the throw stance, then the
/// six sheet frames.
enum DunkArt {
    nonisolated(unsafe) static var offsets: [CGPoint] = [
        CGPoint(x: -6, y: 10), CGPoint(x: -4, y: 12), CGPoint(x: -2, y: 16), CGPoint(x: 4, y: 2),
        CGPoint(x: -3, y: 3), CGPoint(x: -2, y: 2), CGPoint(x: -2, y: 2),
    ]
}

/// Whether the head's fire and the double jump's platform are drawn with `esper_spark`,
/// scaled down to the squares' size, rather than the hard squares.
enum ParticleLook {
    static let sprites = true
    /// Each head particle's size, in art pixels square.
    static let energySize: CGFloat = 10
    static let snowflakeSize: CGFloat = 6
    static let fireSize: CGFloat = 12
    static let lightningSize: CGFloat = 8
}

/// Zeus Juice's charge swirl, `lightning_charge`, drawn at this share of its 240-pixel
/// sheet round the ball in hand.
enum ZeusTuning {
    nonisolated(unsafe) static var chargeScale: Float = 0.17
}

/// The helmets' drawing against their box, and the yard numbers' size, as tuned.
enum HelmetTuning {
    static let scale: CGFloat = 1.1
    /// Tipped back this far, radians, from the vector's own slight lift.
    static let tilt: CGFloat = .pi / 6
    static let numberScale: CGFloat = 1.5
}

/// The backboard, a cluster of flashes behind each rim: its place against the rim, in art
/// pixels, its size, its shear in degrees and its opacity. The sim's box matches it.
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
    static let crossbarAngle: CGFloat = 20
    /// The gold's width, and the black line round it and round the light panels.
    static let thickness: CGFloat = 8
    static let outline: CGFloat = 1
    /// The height, in units, the goalposts are drawn for, apart from the rims.
    static let postRimHeight = 120.0
}

/// Tuning the dunk's frames: with this on, the match doesn't run; player 1 is held on the
/// right rim in the dunk, on the sequence frame the DUNK FRAME slider picks, and the
/// DUNK X and DUNK Y sliders nudge that frame's art. The corner readout prints the table.
enum DunkTuning {
    static let enabled = false
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
