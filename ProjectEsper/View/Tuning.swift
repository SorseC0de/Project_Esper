import EsperSim
import Foundation

/// Air models on the picker. A is the baseline as tuned; each step gives the stick more
/// say in the air. Only the air numbers change, so the ground is the same under each.
enum AirVariant: Int, CaseIterable {
    case a, b, c, d, e

    var label: String { ["A", "B", "C", "D", "E"][rawValue] }

    func apply(to base: FighterSpec) -> FighterSpec {
        var spec = base
        switch self {
        case .a:
            break
        case .b:
            // Turns in about five frames.
            spec.airAccelerationAdditional = 0.24
        case .c:
            // Five-frame turn and a faster cap.
            spec.airAccelerationAdditional = 0.24
            spec.airSpeedMax = 1.4
            spec.jumpHorizontalVelocity = 1.4
            spec.doubleJumpHorizontalVelocity = 1.4
        case .d:
            // Three-frame turn, and letting go stops the drift in a few frames.
            spec.airAccelerationAdditional = 0.4
            spec.airSpeedMax = 1.3
            spec.airFriction = 0.08
            spec.jumpHorizontalVelocity = 1.3
            spec.doubleJumpHorizontalVelocity = 1.3
        case .e:
            // Direct: the stick is the air speed, no momentum either way.
            spec.airAccelerationAdditional = 2
            spec.airSpeedMax = 1.3
            spec.airFriction = 2
            spec.jumpHorizontalVelocity = 1.3
            spec.doubleJumpHorizontalVelocity = 1.3
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
