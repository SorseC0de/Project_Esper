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

/// The glow, as GameMaker's Glow filter had it: what counts as bright, how soft the cut is,
/// how far it spreads, how strong it comes back, and its colour.
enum GlowSettings {
    static let threshold: Float = 0.5
    static let softness: Float = 0.2
    /// Each pass blurs across and down at half size; more spreads further.
    static let blurPasses = 2
    static let intensity: Float = 1.0
    static let tint = SIMD4<Float>(1, 1, 1, 1)
}
