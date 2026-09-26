import EsperSim
import SpriteKit

/// The net's shape and feel: its mouth as wide as the rim's hole, tapering to the bottom,
/// a diamond mesh of this many rows and top knots; how heavy and how loose it is; and the
/// sparks it's drawn in.
enum NetTuning {
    static let topWidth: CGFloat = 18
    static let height: CGFloat = 17
    static let rows = 5
    static let columns = 5
    /// Share of the mouth's width the bottom loses.
    static let taper: CGFloat = 0.45
    static let gravity: CGFloat = 0.18
    /// Share of its speed a knot keeps from one frame to the next.
    static let damping: CGFloat = 0.9
    static let iterations = 4
    /// Share of the ball's travel a knot it touches is carried along by, as well as pushed out.
    static let drag: CGFloat = 0.4
    /// A body's reach, round its chest, for pushing the net.
    static let bodyRadius: CGFloat = 7
    /// The flashspark2 frames' scale on a knot and on each strand between two.
    static let knotScale: CGFloat = 0.13
    static let strandScale: CGFloat = 0.1
}

/// A hoop's net: Verlet cloth hung from the rim, a diamond mesh of knots joined by strands,
/// the top row pinned to the rim and following it. The ball pushes the knots out of its way
/// and drags them along its path, swept from where it was to where it is so a fast shot
/// can't pass between them; a body near the rim pushes them too. Nothing is scripted: a
/// swish is the ball going through. Drawn as small flashspark2s on every knot and every
/// strand's middle, overlapping so the strands read as chains, in the energy of the side
/// guarding the rim. At rest with nothing near, it sleeps. The view's alone.
final class HoopNet {
    private struct Knot {
        var at: CGPoint
        var was: CGPoint
        /// Pinned to the rim, at this offset from it.
        let pin: CGPoint?
    }
    private struct Strand {
        let a: Int, b: Int
        let rest: CGFloat
        let drawn: Bool
    }

    private var knots: [Knot] = []
    private var strands: [Strand] = []
    private var knotSprites: [SKSpriteNode] = []
    private var strandSprites: [SKSpriteNode] = []
    private var drawnStrands: [Int] = []
    private var rim = CGPoint.zero
    private var awake = true
    private var stillFrames = 0
    private var lastBall: CGPoint?

    init(at rim: CGPoint, frames: [SKTexture], frameCount: Int, into parent: SKNode) {
        self.rim = rim
        let rows = NetTuning.rows, columns = NetTuning.columns
        var index: [[Int]] = []
        for row in 0..<rows {
            let share = CGFloat(row) / CGFloat(rows - 1)
            let width = NetTuning.topWidth * (1 - NetTuning.taper * share)
            let count = row % 2 == 0 ? columns : columns - 1
            var line: [Int] = []
            for column in 0..<count {
                let across = -width / 2 + (CGFloat(column) + (row % 2 == 0 ? 0 : 0.5)) * width / CGFloat(columns - 1)
                let offset = CGPoint(x: across, y: -NetTuning.height * share)
                let at = CGPoint(x: rim.x + offset.x, y: rim.y + offset.y)
                line.append(knots.count)
                knots.append(Knot(at: at, was: at, pin: row == 0 ? offset : nil))
            }
            index.append(line)
        }
        func join(_ a: Int, _ b: Int, drawn: Bool = true) {
            strands.append(Strand(a: a, b: b, rest: HoopNet.distance(knots[a].at, knots[b].at), drawn: drawn))
        }
        for row in 0..<(rows - 1) {
            let line = index[row], below = index[row + 1]
            for (column, knot) in line.enumerated() {
                // The diamonds: each knot to the two below it on either side.
                let under = row % 2 == 0 ? [column - 1, column] : [column, column + 1]
                for next in under where below.indices.contains(next) { join(knot, below[next]) }
                // A longer tie two rows down, so the net hangs rather than stretching.
                if row + 2 < rows, index[row + 2].indices.contains(column) { join(knot, index[row + 2][column], drawn: false) }
            }
        }
        // The bottom ring, knot to knot, so the mouth below keeps its round.
        for (a, b) in zip(index[rows - 1], index[rows - 1].dropFirst()) { join(a, b) }

        func spark(scale: CGFloat, salt: Int) -> SKSpriteNode {
            let node = SKSpriteNode(texture: frames.first)
            node.setScale(scale)
            node.zPosition = 4
            let start = (salt * 7) % max(frameCount, 1)
            let looped = Array(frames[start...]) + Array(frames[..<start])
            node.run(.repeatForever(.animate(with: looped, timePerFrame: 1.0 / 24)), withKey: "shimmer")
            parent.addChild(node)
            return node
        }
        knotSprites = knots.indices.map { spark(scale: NetTuning.knotScale, salt: $0) }
        // The long ties hold the shape; only the diamonds' strands and the ring are drawn.
        drawnStrands = strands.indices.filter { strands[$0].drawn }
        strandSprites = drawnStrands.map { spark(scale: NetTuning.strandScale, salt: $0 + 11) }
        place()
    }

    /// The sparks in another energy's frames.
    func recolour(frames: [SKTexture], frameCount: Int) {
        for (salt, node) in (knotSprites + strandSprites).enumerated() {
            let start = (salt * 7) % max(frameCount, 1)
            node.removeAction(forKey: "shimmer")
            node.run(.repeatForever(.animate(with: Array(frames[start...]) + Array(frames[..<start]), timePerFrame: 1.0 / 24)), withKey: "shimmer")
        }
    }

    /// One frame: the rim where it is now, the ball where it is (nil while it's nowhere to
    /// be hit), and the chests of the bodies.
    func step(rim: CGPoint, ball: CGPoint?, ballRadius: CGFloat, bodies: [CGPoint]) {
        let rimMoved = HoopNet.distance(rim, self.rim) > 0.01
        self.rim = rim
        let reach = NetTuning.topWidth + NetTuning.height + 24
        let ballNear = ball.map { HoopNet.distance($0, rim) < reach } ?? false
        let bodyNear = bodies.contains { HoopNet.distance($0, rim) < reach }
        if rimMoved || ballNear || bodyNear {
            awake = true
            stillFrames = 0
        }
        defer { lastBall = ball }
        guard awake else { return }

        var moved: CGFloat = 0
        for index in knots.indices {
            if let pin = knots[index].pin {
                knots[index].at = CGPoint(x: rim.x + pin.x, y: rim.y + pin.y)
                knots[index].was = knots[index].at
                continue
            }
            let knot = knots[index]
            let velocity = CGPoint(x: (knot.at.x - knot.was.x) * NetTuning.damping, y: (knot.at.y - knot.was.y) * NetTuning.damping)
            knots[index].was = knot.at
            knots[index].at = CGPoint(x: knot.at.x + velocity.x, y: knot.at.y + velocity.y - NetTuning.gravity)
        }
        // The ball's sweep this frame, and its carry.
        let from = (ballNear ? lastBall : nil) ?? ball
        for iteration in 0..<NetTuning.iterations {
            for strand in strands { relax(strand) }
            if ballNear, let ball, let from {
                push(outOf: from, to: ball, radius: ballRadius, carry: iteration == 0)
            }
            for body in bodies where HoopNet.distance(body, rim) < reach {
                push(outOf: body, to: body, radius: NetTuning.bodyRadius, carry: false)
            }
        }
        for knot in knots where knot.pin == nil { moved = max(moved, HoopNet.distance(knot.at, knot.was)) }
        place()
        // Settled, and nothing near: it sleeps until something comes.
        if moved < 0.02, !ballNear, !bodyNear {
            stillFrames += 1
            if stillFrames > 20 { awake = false }
        }
    }

    /// A strand back toward its length, each end taking half, a pinned end none.
    private func relax(_ strand: Strand) {
        let a = knots[strand.a].at, b = knots[strand.b].at
        let length = max(HoopNet.distance(a, b), 0.0001)
        let error = (length - strand.rest) / length
        let pinA = knots[strand.a].pin != nil, pinB = knots[strand.b].pin != nil
        guard !(pinA && pinB) else { return }
        let shareA: CGFloat = pinA ? 0 : (pinB ? 1 : 0.5)
        let shareB: CGFloat = pinB ? 0 : (pinA ? 1 : 0.5)
        let delta = CGPoint(x: (b.x - a.x) * error, y: (b.y - a.y) * error)
        knots[strand.a].at = CGPoint(x: a.x + delta.x * shareA, y: a.y + delta.y * shareA)
        knots[strand.b].at = CGPoint(x: b.x - delta.x * shareB, y: b.y - delta.y * shareB)
    }

    /// Every free knot out of the capsule swept from `from` to `to`, and on the first pass
    /// carried a share of the way the ball went.
    private func push(outOf from: CGPoint, to: CGPoint, radius: CGFloat, carry: Bool) {
        let path = CGPoint(x: to.x - from.x, y: to.y - from.y)
        let span = path.x * path.x + path.y * path.y
        for index in knots.indices where knots[index].pin == nil {
            let at = knots[index].at
            let share = span > 0 ? min(max(((at.x - from.x) * path.x + (at.y - from.y) * path.y) / span, 0), 1) : 0
            let nearest = CGPoint(x: from.x + path.x * share, y: from.y + path.y * share)
            var away = CGPoint(x: at.x - nearest.x, y: at.y - nearest.y)
            var gap = HoopNet.distance(at, nearest)
            guard gap < radius else { continue }
            if gap < 0.0001 {
                // Dead on the ball's line: out to whichever side of the rim the knot hangs.
                away = CGPoint(x: at.x >= rim.x ? 1 : -1, y: 0)
                gap = 1
            }
            let out = (radius - gap) / gap
            var next = CGPoint(x: at.x + away.x * out, y: at.y + away.y * out)
            if carry {
                next.x += path.x * NetTuning.drag
                next.y += path.y * NetTuning.drag
            }
            knots[index].at = next
        }
    }

    /// The sparks onto the knots and the strands' middles.
    private func place() {
        for (index, node) in knotSprites.enumerated() { node.position = knots[index].at }
        for (node, index) in zip(strandSprites, drawnStrands) {
            let a = knots[strands[index].a].at, b = knots[strands[index].b].at
            node.position = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
