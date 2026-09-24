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
