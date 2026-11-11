import CoreGraphics
import simd

/// The net as a cylinder of chevron rings hung from the rim, drawn by the Metal layer as
/// thin boxes through the cube renderer: each ring's radius and chevrons stepping from the
/// top's to the bottom's, alternate rings turned half a chevron so they make diamonds, the
/// whole turned about its top by TILT X, TURN Y and ROLL Z. Each ring sways with its row
/// of the flat net's cloth and widens as far as the row spreads, the cloth still running
/// unseen for the swish and the pushing.
enum CylinderNet {
    /// A net's strokes as last built, ring by ring, against its top and with no sway: built
    /// again only when what shapes them changes, and otherwise only moved, each ring with its sway.
    final class Cache {
        fileprivate var key: Key?
        fileprivate var rings: [[CubeInstance]] = []
    }
    fileprivate struct Key: Equatable {
        var shape: NetTuning.Shape
        var spreads: [CGFloat]
        var flare, swish, turn: CGFloat
        var mirrored: Bool
        var colour: SIMD4<Float>
    }
    /// A row's spread to the nearest 64th, so the cloth's drift in the breeze doesn't build it every frame.
    private static let spreadStep: CGFloat = 64

    /// The strokes of one net hung at `top`, mirrored for a backboard on the left, each
    /// ring moved by its row's sway, in `colour`, behind the bodies and the rims.
    static func instances(cache: Cache, top: CGPoint, turn rimTurn: CGFloat, mirrored: Bool, sways: [CGPoint], spreads: [CGFloat], flare: CGFloat, swish: CGFloat,
                          colour: SIMD4<Float>, front: Bool = false, perspective: Bool = false) -> [CubeInstance] {
        let shape = NetTuning.shape(front: front, perspective: perspective)
        let across = NetTuning.swayShare * (1 + (NetTuning.swishShare - 1) * swish)
        let key = Key(shape: shape, spreads: spreads.map { ($0 * spreadStep).rounded() / spreadStep }, flare: flare, swish: swish, turn: rimTurn,
                      mirrored: mirrored, colour: colour)
        if cache.key != key {
            cache.key = key
            cache.rings = build(shape: shape, turn: rimTurn, mirrored: mirrored, spreads: key.spreads, flare: flare, across: across, colour: colour)
        }
        let rings = cache.rings.count
        var strokes: [CubeInstance] = []
        strokes.reserveCapacity(cache.rings.reduce(0) { $0 + $1.count })
        for (ring, local) in cache.rings.enumerated() {
            let share = rings > 1 ? Float(ring) / Float(rings - 1) : 0
            let row = sways.isEmpty ? .zero : sways[min(Int((share * Float(sways.count - 1)).rounded()), sways.count - 1)]
            let moved = SIMD4<Float>(Float(top.x + row.x * across), Float(top.y + row.y * NetTuning.swayShare), 0, 0)
            for var stroke in local {
                stroke.model.columns.3 += moved
                strokes.append(stroke)
            }
        }
        return strokes
    }

    private static func build(shape: NetTuning.Shape, turn rimTurn: CGFloat, mirrored: Bool, spreads: [CGFloat], flare: CGFloat, across: CGFloat,
                              colour: SIMD4<Float>) -> [[CubeInstance]] {
        // Wider at the bottom in a dunk's flare; moved across further in a swish.
        let radiusBottom = shape.radiusBottom + (NetTuning.dunkFlareRadius - shape.radiusBottom) * flare
        let rings = max(Int(shape.rings), 1), around = max(Int(shape.around), 3)
        let degrees = Float.pi / 180
        let turn = simd_quatf(angle: Float(shape.roll) * degrees, axis: [0, 0, 1])
            * simd_quatf(angle: Float(shape.turn) * degrees, axis: [0, 1, 0])
            * simd_quatf(angle: Float(shape.tilt) * degrees, axis: [1, 0, 0])
        let thickness = Float(NetTuning.lineWidth)
        let rimCos = Float(cos(rimTurn)), rimSin = Float(sin(rimTurn))
        return (0..<rings).map { ring in
            var strokes: [CubeInstance] = []
            let share = rings > 1 ? Float(ring) / Float(rings - 1) : 0
            // Widened, too, as far as its row of the cloth is spread, twice over.
            let rowSpread = spreads.isEmpty ? 1 : spreads[min(Int((share * Float(spreads.count - 1)).rounded()), spreads.count - 1)]
            let widened = 1 + (rowSpread - 1) * across
            let radius = max(Float((shape.radiusTop + (radiusBottom - shape.radiusTop) * CGFloat(share)) * widened), 0.5)
            let scale = Float(shape.topScale + (shape.bottomScale - shape.topScale) * CGFloat(share))
            let halfWidth = Float(NetTuning.chevronWidth) * scale / 2, halfDepth = Float(NetTuning.chevronDepth) * scale / 2
            let y = -Float(ring) * Float(shape.rowSpacing)
            func placed(_ angle: Float, _ height: Float) -> SIMD3<Float> {
                var point = turn.act(SIMD3<Float>(radius * sin(angle), height, radius * cos(angle)))
                if mirrored { point.x = -point.x }
                // Turned with the rim it hangs from.
                let sideways = point.x, up = point.y
                point.x = sideways * rimCos - up * rimSin
                point.y = sideways * rimSin + up * rimCos
                return point
            }
            for chevron in 0..<around {
                let angle = 2 * Float.pi * (Float(chevron) + (ring % 2 == 1 ? 0.5 : 0)) / Float(around)
                let spread = halfWidth / radius
                let left = placed(angle - spread, y + halfDepth), point = placed(angle, y - halfDepth), right = placed(angle + spread, y + halfDepth)
                for (from, to) in [(left, point), (point, right)] {
                    let span = to - from
                    let length = simd_length(span)
                    guard length > 0.01 else { continue }
                    let along = simd_quatf(from: [1, 0, 0], to: span / length)
                    let model = simd_float4x4.translation((from + to) / 2) * simd_float4x4(along)
                        * simd_float4x4.scale(SIMD3<Float>(length + thickness, thickness, thickness))
                    strokes.append(CubeInstance(model: model, color: colour, flags: SIMD4<Float>(2, 0, 0, 0)))
                }
            }
            return strokes
        }
    }
}
