import EsperSim
import Foundation

/// Air models on the picker. A is the baseline as tuned. B and C give the stick more say;
/// D and E keep the baseline's control and raise the cap. Only the air numbers change, so
/// the ground is the same under each.
enum AirVariant: Int, CaseIterable {
    case a, b, c, d, e

    var label: String { ["A", "B", "C", "D", "E"][rawValue] }

    func apply(to base: FighterSpec) -> FighterSpec {
        var spec = base
        switch self {
        case .a:
            break
        case .b:
            // Three-frame turn, and letting go stops the drift in a few frames.
            spec.airAccelerationAdditional = 0.4
            spec.airFriction = 0.08
        case .c:
            // Direct: the stick is the air speed, no momentum either way.
            spec.airAccelerationAdditional = 2
            spec.airFriction = 2
        case .d:
            spec.airSpeedMax = 1.6
            spec.jumpHorizontalVelocity = 1.6
            spec.doubleJumpHorizontalVelocity = 1.6
        case .e:
            spec.airSpeedMax = 1.8
            spec.jumpHorizontalVelocity = 1.8
            spec.doubleJumpHorizontalVelocity = 1.8
        }
        return spec
    }
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
