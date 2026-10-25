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

/// A sphere of curved hexagons with gaps between them, from Project RingOut's energy sphere: drawn
/// translucent and additive, so it reads as energy rather than a solid, a few tiles at a time
/// flashing bright. 47's locked rim.
enum HexSphere {
    /// Tiles a sphere, and each tile's angular radius, a little under half the spacing between
    /// tiles so the gaps show; how opaque, a flashing one more so, and how fast it turns, radians
    /// a second. Its flashes: picked afresh this many times a second, this many tiles in a hundred.
    static let tiles = 60
    static let tileRadius: Float = 0.42 * (4 * .pi / Float(tiles)).squareRoot()
    static let alpha: Float = 0.33
    static let flashAlpha: Float = 0.66
    static let spinRate: Float = 0.8
    static let flashesPerSecond = 8.0
    static let flashShare = 12

    /// One tile: a hexagon of `tileRadius` bent onto the unit sphere round +z, so a sphere of them curves.
    static let tile: [CubeVertex] = {
        let r = tileRadius
        let centre = SIMD3<Float>(0, 0, 1)
        let rim = (0..<6).map { k -> SIMD3<Float> in
            let a = Float(k) / 6 * 2 * .pi
            return SIMD3<Float>(sin(r) * cos(a), sin(r) * sin(a), cos(r))
        }
        var out: [CubeVertex] = []
        for k in 0..<6 {
            for p in [centre, rim[k], rim[(k + 1) % 6]] {
                out.append(CubeVertex(position: SIMD4<Float>(p, 1), normal: SIMD4<Float>(p, 0)))
            }
        }
        return out
    }()

    /// Where each tile points, spread evenly over the sphere, and its own twist.
    static let layout: [(direction: SIMD3<Float>, twist: Float)] = (0..<tiles).map { i in
        let z = 1 - 2 * (Float(i) + 0.5) / Float(tiles)
        let ring = (1 - z * z).squareRoot()
        let angle = Float(i) * 2.39996
        return (SIMD3<Float>(ring * cos(angle), ring * sin(angle), z), Float(i) * 0.7)
    }

    /// A sphere's tiles round `centre`, `radius` across, its tiles at `tileShare` of their size, turned by
    /// `spin`; in `colour`, the ones flashing at `time` in `flash`.
    static func instances(centre: SIMD3<Float>, radius: Float, tileShare: Float, spin: Float, colour: SIMD4<Float>,
                          flash: SIMD4<Float>, time: Double) -> [CubeInstance] {
        let turn = simd_quatf(angle: spin, axis: simd_normalize(SIMD3<Float>(0.3, 0.2, 1)))
        let window = UInt32(truncatingIfNeeded: Int(time * flashesPerSecond))
        return layout.enumerated().map { number, tile in
            // Scrambled tile by tile and window by window, so which flash looks random.
            var mixed = (UInt32(number) &* 73_856_093) ^ (window &* 19_349_663)
            mixed = (mixed ^ (mixed >> 16)) &* 0x45D9_F3B
            mixed ^= mixed >> 16
            let flashing = mixed % 100 < UInt32(flashShare)
            var shade = flashing ? flash : colour
            shade.w = flashing ? flashAlpha : alpha
            let model = simd_float4x4.translation(centre)
                * simd_float4x4(turn * simd_quatf(from: [0, 0, 1], to: tile.direction) * simd_quatf(angle: tile.twist, axis: [0, 0, 1]))
                * .scale(SIMD3<Float>(radius * tileShare, radius * tileShare, radius))
            return CubeInstance(model: model, color: shade)
        }
    }
}
