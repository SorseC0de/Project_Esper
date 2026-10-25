import simd
import SwiftUI

/// FloState's strings: two chains of slightly long diamonds off the upper chest, drawn in the
/// Metal layer as the head's cubes are, rising and sweeping back as Mega Rayquaza's upper
/// whiskers do. Each chain is a cord: it lags the body when it jumps and moves, its tips wave,
/// and through a spin it winds round the body, the two waving together. The near string is the
/// energy form's own colour, its hood's; the far one the energy colour, and past its first diamond
/// it's drawn behind the body. Art pixels, y up, z toward the viewer; the game's points or the
/// customize canvas's pixels by `scale`.
enum FloStrings {
    /// One diamond: its middle, turned so its length runs along the string, its length and width,
    /// whether it's the far string's, and whether the body covers it.
    struct Diamond {
        var centre: SIMD3<Float>
        var orientation: simd_quatf
        var length: Float
        var width: Float
        var far: Bool
        var behind: Bool
    }

    /// A string at rest: its first heading (degrees anticlockwise from facing ahead), turning on
    /// to the tip's (`tipAngle`) evenly diamond to diamond, and how far toward or away from the viewer.
    struct Rest {
        var heading: Float
        var depth: Float
    }
    /// The far string leaves forward, low, and sweeps up and back, behind; the near one leaves higher, in front.
    static let rests = [Rest(heading: 20, depth: -1.5), Rest(heading: 60, depth: 1.5)]
    /// Which string is the far one, in the energy's shadow and behind the body past its first diamonds.
    static let farString = 0
    /// Where each string leaves the chest on the hooded head's 48-pixel canvas, column and row from the top left.
    static let chestPixels = [CGPoint(x: 25, y: 29), CGPoint(x: 22, y: 28)]
    /// On the debug bench, kept on this device: the tip's heading, degrees; a diamond's width and
    /// the art pixels from one to the next; its length over its width (1, every edge alike); and
    /// how many diamonds a string. The second to last this much bigger.
    static let tipAngleKey = "esper.floStrings.tipAngle", sizeKey = "esper.floStrings.size", spacingKey = "esper.floStrings.spacing"
    static let lengthKey = "esper.floStrings.length", countKey = "esper.floStrings.count"
    static let offsetXKey = "esper.floStrings.x", offsetYKey = "esper.floStrings.y", turnKey = "esper.floStrings.turn"
    nonisolated(unsafe) static var tipAngle = Float(UserDefaults.standard.object(forKey: tipAngleKey) as? Double ?? 60)
    nonisolated(unsafe) static var width = Float(UserDefaults.standard.object(forKey: sizeKey) as? Double ?? 2.5)
    nonisolated(unsafe) static var segment = Float(UserDefaults.standard.object(forKey: spacingKey) as? Double ?? 5)
    nonisolated(unsafe) static var lengthShare = Float(UserDefaults.standard.object(forKey: lengthKey) as? Double ?? 1.5)
    nonisolated(unsafe) static var diamonds = UserDefaults.standard.object(forKey: countKey) as? Int ?? 10
    /// Both strings moved off the chest, art pixels right (the way the body faces) and up; and the
    /// whole of their rest shape turned about where they start, degrees anticlockwise.
    nonisolated(unsafe) static var offsetX = Float(UserDefaults.standard.object(forKey: offsetXKey) as? Double ?? 3)
    nonisolated(unsafe) static var offsetY = Float(UserDefaults.standard.object(forKey: offsetYKey) as? Double ?? 3)
    nonisolated(unsafe) static var turn = Float(UserDefaults.standard.object(forKey: turnKey) as? Double ?? 100)
    /// Where each string leaves the chest on the hooded head's canvas, the X and Y sliders' move with it (rows run down).
    static var anchorPixels: [CGPoint] {
        chestPixels.map { CGPoint(x: $0.x + CGFloat(offsetX), y: $0.y - CGFloat(offsetY)) }
    }
    static let bigScale: Float = 1.25
    /// The far string's first this many diamonds over the body, the rest behind it.
    static let farOverBody = 1
    /// The wave: art pixels at the tip across and in depth, waves a second, radians a diamond apart
    /// (a ripple along the length). Moving, the strings flutter: the wave this much bigger and
    /// faster at full flutter, which is the chest moving this many art pixels a frame; in flight
    /// they flutter this much even hovering, and the drag's this much stronger and reaches further.
    static let waveAcross: Float = 4
    static let waveDepth: Float = 2
    static let wavesPerSecond = 0.6
    static let waveStep = 0.8
    static let flutterGrowth: Float = 0.8
    static let flutterSpeedUp: Float = 2.5
    static let flutterFullSpeed: Float = 3
    static let flightFlutter: Float = 0.6
    static let flightDrag: Float = 1.8
    /// How much of last frame's motion carries on; how far toward its line a diamond's drawn each
    /// frame, at the root (the tip half that, so it trails); and while winding round in a spin.
    static let carry: Float = 0.9
    static let pull: Float = 0.07
    static let coilPull: Float = 0.12
    /// The body's motion swept back along the strings: their line pushed against how it moves,
    /// this many frames of it at the tip (less toward the chest), at most this many art pixels,
    /// the push eased in and out over frames this share at a time. A jump streams them down.
    static let drag: Float = 7
    static let dragMost: Float = 10
    static let dragEase: Float = 0.25
    /// The coil, loose, flaring: its radius round the body's middle at the chest, growing this much
    /// more by the tip, and its drop down the body a diamond, art pixels; turns a second; radians a
    /// diamond round; and the share of the way in or out of it a frame.
    static let coilRadius: Float = 8
    static let coilFlare: Float = 1.5
    static let coilDrop: Float = 1.2
    static let coilTurnsPerSecond = 2.0
    static let coilStep: Float = 0.6
    static let coilEase: Float = 0.15
    /// Turning round: the strings swing half a turn round the body from the old side to the new,
    /// over this many frames, wrapped this loosely.
    static let turnFrames = 16
    static let turnWrap: Float = 0.6
    /// The diamonds' slow roll about their length, radians a second, and a diamond on from the last.
    static let rollPerSecond: Float = 1.5
    static let rollStep: Float = 0.4

    /// The two chains as cords, apart from how they're drawn.
    final class Motion {
        private var points: [[SIMD3<Float>]] = [[], []]
        private var previous: [[SIMD3<Float>]] = [[], []]
        private var coil: Float = 0
        private var lastAnchor: SIMD3<Float>?
        /// The coil's angle round the body, and a turn round's frames left and the way it faced.
        private var spinAngle: Float = 0
        private var turnLeft = 0
        private var lastFacing: Float?
        private var push = SIMD3<Float>(repeating: 0)
        /// How much the strings flutter now (0 to 1), eased; and the wave's phase, run on at its pace.
        private var flutter: Float = 0
        private var wavePhase = 0.0

        /// A frame on. `anchors`: where each string leaves the chest; `facing`: 1 right, -1 left;
        /// `lean`: the body's turn, radians anticlockwise; `scale`: units an art pixel; `spinning`
        /// and `middle`: winding round the body's middle in a spin.
        func step(anchors: [SIMD3<Float>], facing: Float, lean: Float, scale: Float, time: Double,
                  spinning: Bool, middle: SIMD3<Float>, flying: Bool = false) -> [Diamond] {
            // Turned round: half a turn round the body, from the side they trailed on to the new back.
            if let lastFacing, lastFacing != facing, !spinning {
                turnLeft = FloStrings.turnFrames
                spinAngle = facing > 0 ? 0 : .pi
            }
            lastFacing = facing
            if spinning {
                spinAngle += Float(2 * .pi * FloStrings.coilTurnsPerSecond / 60) * facing
                turnLeft = 0
            } else if turnLeft > 0 {
                spinAngle += .pi / Float(FloStrings.turnFrames)
                turnLeft -= 1
            }
            coil += ((spinning ? 1 : (turnLeft > 0 ? FloStrings.turnWrap : 0)) - coil) * FloStrings.coilEase
            if coil < 0.001 { coil = 0 }
            // How the chest moved since last frame, swept back as the push on the strings' line.
            if let first = anchors.first {
                let moved = lastAnchor.map { first - $0 } ?? .zero
                lastAnchor = first
                let speed = simd_length(moved) / max(scale, 0.0001)
                let fluttering = max(min(speed / FloStrings.flutterFullSpeed, 1), flying ? FloStrings.flightFlutter : 0)
                flutter += (fluttering - flutter) * FloStrings.dragEase
                wavePhase += 2 * .pi * FloStrings.wavesPerSecond * Double(1 + FloStrings.flutterSpeedUp * flutter) / 60
                var wanted = -moved * FloStrings.drag * (flying ? FloStrings.flightDrag : 1)
                let most = FloStrings.dragMost * scale * (flying ? FloStrings.flightDrag : 1)
                if simd_length(wanted) > most { wanted = simd_normalize(wanted) * most }
                if simd_length(moved) > 24 * scale { wanted = .zero }
                push += (wanted - push) * FloStrings.dragEase
            }
            let segment = FloStrings.segment * scale
            let count = FloStrings.diamonds + 1
            var made: [Diamond] = []
            for (string, anchor) in anchors.enumerated() where string < FloStrings.rests.count {
                let rest = FloStrings.rests[string]
                // New, or the anchor gone too far at once: laid out along its line.
                let targets = line(string: string, rest: rest, anchor: anchor, facing: facing, lean: lean, scale: scale, time: time, middle: middle)
                if points[string].count != count || simd_distance(points[string][0], anchor) > 24 * scale {
                    points[string] = targets
                    previous[string] = targets
                }
                var chain = points[string]
                let was = previous[string]
                previous[string] = chain
                chain[0] = anchor
                for index in 1..<count {
                    let share = Float(index) / Float(count - 1)
                    let pull = (FloStrings.pull * (1 - 0.5 * share)) * (1 - coil) + FloStrings.coilPull * coil
                    var point = chain[index] + (chain[index] - was[index]) * FloStrings.carry
                    let target = targets[index] + push * share * (1 - coil)
                    point += (target - point) * pull
                    chain[index] = point
                }
                // Each a diamond's step from the last, out from the pinned one.
                for index in 1..<count {
                    let apart = chain[index] - chain[index - 1]
                    let gap = simd_length(apart)
                    chain[index] = gap > 0.0001 ? chain[index - 1] + apart / gap * segment : chain[index - 1] + SIMD3<Float>(0, segment, 0)
                }
                points[string] = chain
                let far = string == FloStrings.farString
                for index in 0..<(count - 1) {
                    let from = chain[index], to = chain[index + 1]
                    let along = simd_normalize(to - from)
                    let roll = Float(time) * FloStrings.rollPerSecond + Float(index) * FloStrings.rollStep
                    let orientation = simd_quatf(angle: roll, axis: along) * simd_quatf(from: SIMD3<Float>(1, 0, 0), to: along)
                    let size: Float = index == FloStrings.diamonds - 2 ? FloStrings.bigScale : 1
                    let centre = (from + to) / 2
                    // Behind the body: the far string past its first diamonds, and the back of a coil.
                    let behind = (far && index >= FloStrings.farOverBody) || (coil > 0.3 && centre.z < middle.z)
                    let width = FloStrings.width * scale * size
                    made.append(Diamond(centre: centre, orientation: orientation, length: width * FloStrings.lengthShare,
                                        width: width, far: far, behind: behind))
                }
            }
            return made
        }

        /// Where each point of a string is drawn toward: its resting arc, waving, or round the body in a spin.
        private func line(string: Int, rest: Rest, anchor: SIMD3<Float>, facing: Float, lean: Float, scale: Float,
                          time: Double, middle: SIMD3<Float>) -> [SIMD3<Float>] {
            let count = FloStrings.diamonds + 1
            let segment = FloStrings.segment * scale
            var arc = [anchor]
            var heading = (rest.heading + FloStrings.turn) * .pi / 180 + lean * facing
            let turn = (FloStrings.tipAngle - rest.heading) / Float(max(count - 2, 1)) * .pi / 180
            for index in 1..<count {
                let share = Float(index) / Float(count - 1)
                let phase = wavePhase - Double(index) * FloStrings.waveStep
                let last = arc[index - 1]
                let ahead = SIMD3<Float>(cos(heading) * facing, sin(heading), 0)
                var point = last + ahead * segment
                // Across the line and in depth, growing to the tip.
                let across = SIMD3<Float>(-ahead.y, ahead.x, 0)
                point += across * Float(sin(phase)) * FloStrings.waveAcross * (1 + FloStrings.flutterGrowth * flutter) * scale * share
                point.z = anchor.z + rest.depth * scale + Float(cos(phase)) * FloStrings.waveDepth * scale * share
                arc.append(point)
                heading += turn
            }
            guard coil > 0 else { return arc }
            // Loosely round the body's middle, flaring wider to the tip, a little down it from the chest.
            return arc.enumerated().map { index, point in
                guard index > 0 else { return point }
                let share = Float(index) / Float(count - 1)
                let angle = spinAngle + Float(index) * FloStrings.coilStep * facing + Float(string) * .pi
                let radius = FloStrings.coilRadius * (1 + FloStrings.coilFlare * share) * scale
                let round = SIMD3<Float>(middle.x + cos(angle) * radius,
                                         anchor.y - Float(index) * FloStrings.coilDrop * scale,
                                         middle.z + sin(angle) * radius)
                return point + (round - point) * coil
            }
        }

        func reset() {
            points = [[], []]
            lastAnchor = nil
            lastFacing = nil
            turnLeft = 0
            push = .zero
            coil = 0
        }
    }

    /// Web Water's line as diamonds: laid straight from `from` to `to`, a string's spacing apart,
    /// rolling as the strings' do, every other one this much bigger.
    static let webBigScale: Float = 1.25
    static func line(from: SIMD3<Float>, to: SIMD3<Float>, scale: Float, time: Double) -> [Diamond] {
        let apart = to - from
        let length = simd_length(apart)
        let segment = FloStrings.segment * scale
        guard length > segment else { return [] }
        let along = apart / length
        let count = Int(length / segment)
        return (0..<count).map { index in
            let roll = Float(time) * FloStrings.rollPerSecond + Float(index) * FloStrings.rollStep
            let size: Float = index % 2 == 1 ? FloStrings.webBigScale : 1
            let width = FloStrings.width * scale * size
            return Diamond(centre: from + along * (segment * (Float(index) + 0.5)),
                           orientation: simd_quatf(angle: roll, axis: along) * simd_quatf(from: SIMD3<Float>(1, 0, 0), to: along),
                           length: width * FloStrings.lengthShare, width: width, far: false, behind: false)
        }
    }

    /// A diamond's colour: the near string the energy form's own, its hood's and clothes' (the
    /// brighter), the far one the energy colour.
    static func colour(_ diamond: Diamond, look: Look) -> RGB {
        diamond.far ? look.glow : (look.body ?? look.glow)
    }
}

/// A unit diamond round its middle, its points half a unit out along each axis: slightly long
/// once scaled along x. Drawn by the cubes' pipeline, its faces flat-shaded.
enum DiamondMesh {
    static let unit: [CubeVertex] = {
        var out: [CubeVertex] = []
        for sx: Float in [1, -1] {
            for sy: Float in [1, -1] {
                for sz: Float in [1, -1] {
                    let a = SIMD3<Float>(sx * 0.5, 0, 0), b = SIMD3<Float>(0, sy * 0.5, 0), c = SIMD3<Float>(0, 0, sz * 0.5)
                    let normal = simd_normalize(SIMD3<Float>(sx, sy, sz))
                    // Wound as the cube's faces are: anticlockwise seen from outside.
                    let corners = simd_dot(simd_cross(b - a, c - a), normal) > 0 ? [a, b, c] : [a, c, b]
                    for corner in corners { out.append(CubeVertex(position: SIMD4<Float>(corner, 1), normal: SIMD4<Float>(normal, 0))) }
                }
            }
        }
        return out
    }()

    /// The diamond's faces toward the viewer, flat, for a canvas: each its corners and its normal.
    static func faces(_ diamond: FloStrings.Diamond) -> [(corners: [SIMD3<Float>], normal: SIMD3<Float>)] {
        let scale = SIMD3<Float>(diamond.length, diamond.width, diamond.width)
        var faces: [(corners: [SIMD3<Float>], normal: SIMD3<Float>)] = []
        for start in stride(from: 0, to: unit.count, by: 3) {
            let corners = (0..<3).map { diamond.centre + diamond.orientation.act(SIMD3<Float>(unit[start + $0].position.x, unit[start + $0].position.y, unit[start + $0].position.z) * scale) }
            let normal = simd_normalize(simd_cross(corners[1] - corners[0], corners[2] - corners[0]))
            guard normal.z > 0 else { continue }
            faces.append((corners, normal))
        }
        return faces
    }
}
