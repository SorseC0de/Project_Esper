import CoreGraphics
import simd

/// The net as a cylinder of chevron rings hung from the rim, drawn by the Metal layer as
/// thin boxes through the cube renderer: each ring's radius and chevrons stepping from the
/// top's to the bottom's, alternate rings turned half a chevron so they make diamonds, the
/// whole turned about its top by TILT X, TURN Y and ROLL Z. Each ring sways with its row
/// of the flat net's cloth, which still runs unseen for the swish and the pushing.
enum CylinderNet {
    /// The strokes of one net hung at `top`, mirrored for a backboard on the left, each
    /// ring moved by its row's sway, in `colour`, behind the bodies and the rims.
    static func instances(top: CGPoint, mirrored: Bool, sways: [CGPoint], colour: SIMD4<Float>) -> [CubeInstance] {
        let rings = max(Int(NetTuning.rings), 1), around = max(Int(NetTuning.around), 3)
        let degrees = Float.pi / 180
        let turn = simd_quatf(angle: Float(NetTuning.roll) * degrees, axis: [0, 0, 1])
            * simd_quatf(angle: Float(NetTuning.turn) * degrees, axis: [0, 1, 0])
            * simd_quatf(angle: Float(NetTuning.tilt) * degrees, axis: [1, 0, 0])
        let thickness = Float(NetTuning.lineWidth)
        var strokes: [CubeInstance] = []
        for ring in 0..<rings {
            let share = rings > 1 ? Float(ring) / Float(rings - 1) : 0
            let radius = max(Float(NetTuning.radiusTop + (NetTuning.radiusBottom - NetTuning.radiusTop) * CGFloat(share)), 0.5)
            let scale = Float(NetTuning.topScale + (NetTuning.bottomScale - NetTuning.topScale) * CGFloat(share))
            let halfWidth = Float(NetTuning.chevronWidth) * scale / 2, halfDepth = Float(NetTuning.chevronDepth) * scale / 2
            let y = -Float(ring) * Float(NetTuning.rowSpacing)
            let sway = sways.isEmpty ? .zero : sways[min(Int((share * Float(sways.count - 1)).rounded()), sways.count - 1)]
            func placed(_ angle: Float, _ height: Float) -> SIMD3<Float> {
                var point = turn.act(SIMD3<Float>(radius * sin(angle), height, radius * cos(angle)))
                if mirrored { point.x = -point.x }
                return point + SIMD3<Float>(Float(top.x + sway.x), Float(top.y + sway.y), 0)
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
        }
        return strokes
    }
}
