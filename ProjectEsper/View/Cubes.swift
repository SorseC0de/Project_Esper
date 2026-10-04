import simd

/// Matches `CubeVertex` in Glow.metal: a corner of the unit cube and its face's normal.
struct CubeVertex {
    var position: SIMD4<Float>
    var normal: SIMD4<Float>
}

/// Matches `CubeInstance` in Glow.metal: a cube somewhere, turned and sized, in a colour,
/// drawn behind the players when `flags.x` is 1.
struct CubeInstance {
    var model: simd_float4x4
    var color: SIMD4<Float>
    var flags = SIMD4<Float>(0, 0, 0, 0)
}

/// Matches `CubeUniforms` in Glow.metal.
struct CubeUniforms {
    var viewProjection: simd_float4x4
    var light: SIMD4<Float>
    /// Under water the cubes take the water's tint as the scene under them does: its top and
    /// bottom colours, how strongly (top's a), and the target's height in pixels (bottom's a).
    var waterTop: SIMD4<Float> = .zero
    var waterBottom: SIMD4<Float> = .zero
}

enum CubeMesh {
    /// Thirty-six corners of a unit cube round its middle, six faces of two triangles.
    static let unit: [CubeVertex] = {
        let faces: [(normal: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>)] = [
            ([1, 0, 0], [0, 1, 0], [0, 0, 1]), ([-1, 0, 0], [0, 1, 0], [0, 0, 1]),
            ([0, 1, 0], [1, 0, 0], [0, 0, 1]), ([0, -1, 0], [1, 0, 0], [0, 0, 1]),
            ([0, 0, 1], [1, 0, 0], [0, 1, 0]), ([0, 0, -1], [1, 0, 0], [0, 1, 0]),
        ]
        var out: [CubeVertex] = []
        for (index, face) in faces.enumerated() {
            let n = face.normal * 0.5
            let corners = [n - face.u * 0.5 - face.v * 0.5, n + face.u * 0.5 - face.v * 0.5,
                           n + face.u * 0.5 + face.v * 0.5, n - face.u * 0.5 + face.v * 0.5]
            let normal = SIMD4<Float>(face.normal, Float(index))
            for corner in [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]] {
                out.append(CubeVertex(position: SIMD4<Float>(corner, 1), normal: normal))
            }
        }
        return out
    }()
}

enum SphereMesh {
    /// A unit sphere round its middle, twelve slices round and eight stacks up, its corners'
    /// normals pointing out of it so it shades round, drawn by the cubes' own pipeline.
    static let unit: [CubeVertex] = {
        let slices = 12, stacks = 8
        func corner(_ slice: Int, _ stack: Int) -> CubeVertex {
            let theta = Float(slice) / Float(slices) * 2 * .pi
            let phi = Float(stack) / Float(stacks) * .pi
            let normal = SIMD3<Float>(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
            return CubeVertex(position: SIMD4<Float>(normal * 0.5, 1), normal: SIMD4<Float>(normal, 0))
        }
        var out: [CubeVertex] = []
        for stack in 0..<stacks {
            for slice in 0..<slices {
                let a = corner(slice, stack), b = corner(slice + 1, stack), c = corner(slice + 1, stack + 1), d = corner(slice, stack + 1)
                out += [a, c, b, a, d, c]
            }
        }
        return out
    }()
}

extension simd_float4x4 {
    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(t, 1)
        return m
    }

    static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4<Float>(s, 1))
    }
}
