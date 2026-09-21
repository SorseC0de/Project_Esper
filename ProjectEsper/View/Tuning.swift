import EsperSim
import Foundation

/// Air models on the picker. A is the baseline as tuned; the rest change only the air
/// numbers so the ground stays the same under each.
enum AirVariant: Int, CaseIterable {
    case a, b, c, d, e

    var label: String { ["A", "B", "C", "D", "E"][rawValue] }

    func apply(to base: FighterSpec) -> FighterSpec {
        var spec = base
        switch self {
        case .a:
            break
        case .b:
            // Faster and snappier.
            spec.airSpeedMax = 1.2
            spec.airAccelerationAdditional = 0.16
            spec.jumpHorizontalVelocity = 1.2
            spec.doubleJumpHorizontalVelocity = 1.2
        case .c:
            // Near-instant turn, and letting go stops the drift.
            spec.airSpeedMax = 1.0
            spec.airAccelerationAdditional = 0.3
            spec.airFriction = 0.06
        case .d:
            // Momentum: Fox's own acceleration, fast cap, drift carries a long way.
            spec.airSpeedMax = 1.2
            spec.airAccelerationAdditional = 0.06
            spec.airFriction = 0.005
            spec.jumpHorizontalVelocity = 1.2
            spec.doubleJumpHorizontalVelocity = 1.2
        case .e:
            // Direct: the stick is the air speed, no momentum either way.
            spec.airSpeedMax = 1.1
            spec.airAccelerationAdditional = 2
            spec.airFriction = 2
            spec.jumpHorizontalVelocity = 1.1
            spec.doubleJumpHorizontalVelocity = 1.1
        }
        return spec
    }
}
