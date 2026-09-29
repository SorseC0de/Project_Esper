import EsperSim
import SpriteKit

/// The net's shape and feel: straight columns of chevrons hung from the rim, how heavy and
/// how loose they are, and the chevrons themselves.
enum NetTuning {
    static let columns = 5
    static let chevronsPerColumn = 7
    /// Share of the way back to its place in the net's shape a knot is pulled each frame,
    /// so the net always settles to how it was built.
    static let settle: CGFloat = 0.08
    /// Most frames a swish drives the net for.
    static let swishFrames = 40
    /// Share of its speed a knot keeps from one frame to the next.
    static let damping: CGFloat = 0.9
    static let iterations = 4
    /// Share of the ball's travel a knot it touches is carried along by, as well as pushed out.
    static let drag: CGFloat = 0.4
    /// A body's reach, round its chest, for pushing the net.
    static let bodyRadius: CGFloat = 7
    /// A chevron, pointing down: art pixels across and deep at ×1, and 1 thick.
    static let chevronWidth: CGFloat = 2.25
    static let chevronDepth: CGFloat = 1.5
    static let lineWidth: CGFloat = 1
    /// NET TOP and NET BOTTOM on the UI tuning panel, under HUD: the chevrons' scale at the
    /// rim and at the bottom, those between stepping down evenly; NET SPREAD, art pixels
    /// between the columns; NET ROWS, between chevrons down a column; NET X and NET Y, the
    /// whole net against the rim, x mirrored on a left backboard as the hoop's art is;
    /// NET WEAVE, the share of the way each strand leans to the neighbour it's knotted to on
    /// a row, the pairing flipping every row, so the chevrons run in diagonals both ways;
    /// NET TAPER, the share of its width the net loses by the bottom; NET SKEW, art pixels
    /// each column is raised over the one before, toward the backboard, to match its angle.
    /// Kept between launches.
    static let topScaleKey = "ui.net.columns.topScale"
    static let bottomScaleKey = "ui.net.columns.bottomScale"
    static let spreadKey = "ui.net.columns.spread"
    static let rowSpacingKey = "ui.net.columns.rowSpacing"
    static let offsetXKey = "ui.net.offsetX"
    static let offsetYKey = "ui.net.offsetY"
    static let weaveKey = "ui.net.weave"
    static let taperKey = "ui.net.taper"
    static let skewKey = "ui.net.skew"
    static var topScale: CGFloat { stored(topScaleKey) ?? 1 }
    static var bottomScale: CGFloat { stored(bottomScaleKey) ?? 0.25 }
    static var spread: CGFloat { stored(spreadKey) ?? 4 }
    static var rowSpacing: CGFloat { stored(rowSpacingKey) ?? 2.75 }
    static var weave: CGFloat { stored(weaveKey) ?? 0.5 }
    static var taper: CGFloat { stored(taperKey) ?? 0.5 }
    static var skew: CGFloat { stored(skewKey) ?? 0 }
    static var offset: CGPoint { CGPoint(x: stored(offsetXKey) ?? -2, y: stored(offsetYKey) ?? -4) }
    /// What the mesh is built from; a change rebuilds it.
    static var meshValues: [CGFloat] { [spread, rowSpacing, weave, taper, skew] }
    private static func stored(_ key: String) -> CGFloat? {
        (UserDefaults.standard.object(forKey: key) as? Double).map { CGFloat($0) }
    }
}

/// A hoop's net: straight columns of chevrons hung from the rim, each chevron a knot of a
/// Verlet cloth, the top ones pinned to the rim and following it, each tied to the one
/// below and to its neighbours across, and each pulled back toward its place so the net
/// always settles to its shape. The ball pushes the knots out of its way and drags them
/// along its path, swept from where it was to where it is so a fast shot can't pass between
/// them; a body near the rim pushes them too. A ball dropping in through the rim is a
/// swish: from there the net is driven by the ball as it entered, carried on at that angle
/// and speed, not by the ball the sim then bounces off the back of the rim. In the energy
/// of the side guarding the rim. At rest with nothing near, it sleeps. The view's alone.
final class HoopNet {
    private struct Knot {
        var at: CGPoint
        var was: CGPoint
        /// Its place down the column, 0 at the rim.
        let row: Int
        /// Its place in the net's shape, from the rim.
        let home: CGPoint
        /// The top row, held at home.
        var pinned: Bool { row == 0 }
    }
    /// The ball as it came in through the rim, carried on: where it is, where it was, its
    /// speed, and the frames left.
    private struct Swish {
        var at: CGPoint
        var was: CGPoint
        let velocity: CGPoint
        var framesLeft: Int
    }
    private struct Tie {
        let a: Int, b: Int
        let rest: CGFloat
    }

    private var knots: [Knot] = []
    private var ties: [Tie] = []
    private let shape = SKShapeNode()
    private var rim = CGPoint.zero
    private var awake = true
    private var stillFrames = 0
    private var lastBall: CGPoint?
    private var swish: Swish?
    /// A left backboard mirrors the skew.
    private let facing: CGFloat
    private var builtSpacing: [CGFloat] = []
    private var drawnScales: [CGFloat] = []

    init(at rim: CGPoint, mirrored: Bool, colour: SKColor, into parent: SKNode, depth: CGFloat = 4) {
        self.rim = rim
        facing = mirrored ? -1 : 1
        shape.strokeColor = colour
        shape.lineWidth = NetTuning.lineWidth
        shape.lineCap = .square
        shape.isAntialiased = false
        shape.zPosition = depth
        parent.addChild(shape)
        buildMesh()
    }

    /// The strands hung from the rim a spread apart, each row leaning pairs of neighbours
    /// together into knots, the pairs shifting by one every row.
    private func buildMesh() {
        builtSpacing = NetTuning.meshValues
        knots = []
        ties = []
        let columns = NetTuning.columns, rows = NetTuning.chevronsPerColumn
        let halfWidth = NetTuning.spread * CGFloat(columns - 1) / 2
        var index: [[Int]] = []
        for column in 0..<columns {
            var line: [Int] = []
            let topX = -halfWidth + CGFloat(column) * NetTuning.spread
            for row in 0..<rows {
                // Toward the right-hand neighbour on one row, the left-hand one on the next;
                // an edge strand with no one that side hangs straight.
                let partner = (column + row) % 2 == 1 ? column + 1 : column - 1
                let lean: CGFloat = row == 0 || !(0..<columns).contains(partner) ? 0 : CGFloat(partner - column)
                let widthShare = 1 - NetTuning.taper * CGFloat(row) / CGFloat(rows - 1)
                let x = (topX + lean * NetTuning.weave * NetTuning.spread / 2) * widthShare
                let raised = NetTuning.skew * CGFloat(column - (columns - 1) / 2) * facing
                let home = CGPoint(x: x, y: -CGFloat(row) * NetTuning.rowSpacing + raised)
                let at = CGPoint(x: rim.x + home.x, y: rim.y + home.y)
                line.append(knots.count)
                knots.append(Knot(at: at, was: at, row: row, home: home))
            }
            index.append(line)
        }
        func tie(_ a: Int, _ b: Int) {
            ties.append(Tie(a: a, b: b, rest: HoopNet.distance(knots[a].at, knots[b].at)))
        }
        for column in 0..<columns {
            for row in 0..<(rows - 1) { tie(index[column][row], index[column][row + 1]) }
        }
        // Across, each knot to its neighbour in the row as they lie, strands that meet tied
        // where they cross.
        for row in 1..<rows {
            let across = (0..<columns).map { index[$0][row] }.sorted { knots[$0].at.x < knots[$1].at.x }
            for (a, b) in zip(across, across.dropFirst()) { tie(a, b) }
        }
        awake = true
        stillFrames = 0
        place()
    }

    func recolour(_ colour: SKColor) {
        shape.strokeColor = colour
    }

    /// One frame: the rim where it is now, the ball where it is (nil while it's nowhere to
    /// be hit), and the chests of the bodies.
    func step(rim: CGPoint, ball: CGPoint?, ballRadius: CGFloat, bodies: [CGPoint]) {
        let rimMoved = HoopNet.distance(rim, self.rim) > 0.01
        self.rim = rim
        if builtSpacing != NetTuning.meshValues { buildMesh() }
        let reach = NetTuning.spread * CGFloat(NetTuning.columns) + NetTuning.rowSpacing * CGFloat(NetTuning.chevronsPerColumn) + 24
        let ballNear = ball.map { HoopNet.distance($0, rim) < reach } ?? false
        let bodyNear = bodies.contains { HoopNet.distance($0, rim) < reach }
        if let ball, let lastBall, swish == nil { catchSwish(from: lastBall, to: ball, radius: ballRadius) }
        if rimMoved || ballNear || bodyNear || swish != nil {
            awake = true
            stillFrames = 0
        }
        defer { lastBall = ball }
        guard awake else {
            // Asleep, it still redraws for the tuning panel.
            if drawnScales != [NetTuning.topScale, NetTuning.bottomScale] { place() }
            return
        }

        for index in knots.indices {
            let knot = knots[index]
            let home = CGPoint(x: rim.x + knot.home.x, y: rim.y + knot.home.y)
            if knot.pinned {
                knots[index].at = home
                knots[index].was = home
                continue
            }
            let velocity = CGPoint(x: (knot.at.x - knot.was.x) * NetTuning.damping, y: (knot.at.y - knot.was.y) * NetTuning.damping)
            knots[index].was = knot.at
            knots[index].at = CGPoint(x: knot.at.x + velocity.x + (home.x - knot.at.x) * NetTuning.settle,
                                      y: knot.at.y + velocity.y + (home.y - knot.at.y) * NetTuning.settle)
        }
        // This frame's sweep: the swish's carried-on ball while there is one, else the ball.
        var sweep: (from: CGPoint, to: CGPoint)?
        if var carried = swish {
            carried.was = carried.at
            carried.at = CGPoint(x: carried.at.x + carried.velocity.x, y: carried.at.y + carried.velocity.y)
            carried.framesLeft -= 1
            sweep = (carried.was, carried.at)
            let bottom = rim.y + (knots.map(\.home.y).min() ?? 0) - ballRadius
            swish = carried.framesLeft > 0 && carried.at.y > bottom ? carried : nil
        } else if ballNear, let ball {
            sweep = (lastBall ?? ball, ball)
        }
        for iteration in 0..<NetTuning.iterations {
            for tie in ties { relax(tie) }
            if let sweep {
                push(outOf: sweep.from, to: sweep.to, radius: ballRadius, carry: iteration == 0)
            }
            for body in bodies where HoopNet.distance(body, rim) < reach {
                push(outOf: body, to: body, radius: NetTuning.bodyRadius, carry: false)
            }
        }
        var moved: CGFloat = 0
        for knot in knots where !knot.pinned { moved = max(moved, HoopNet.distance(knot.at, knot.was)) }
        place()
        // Settled, and nothing near: it sleeps until something comes.
        if moved < 0.02, !ballNear, !bodyNear, swish == nil {
            stillFrames += 1
            if stillFrames > 20 { awake = false }
        }
    }

    /// The ball crossing down through the rim's opening this frame starts a swish, carried
    /// on at the speed and angle it came in at, at least a pixel a frame downward.
    private func catchSwish(from: CGPoint, to: CGPoint, radius: CGFloat) {
        guard from.y > rim.y, to.y <= rim.y else { return }
        let share = (from.y - rim.y) / (from.y - to.y)
        let crossingX = from.x + (to.x - from.x) * share
        let halfOpening = NetTuning.spread * CGFloat(NetTuning.columns - 1) / 2
        guard abs(crossingX - rim.x) < halfOpening + radius else { return }
        let velocity = CGPoint(x: to.x - from.x, y: min(to.y - from.y, -1))
        let entry = CGPoint(x: crossingX, y: rim.y)
        swish = Swish(at: entry, was: entry, velocity: velocity, framesLeft: NetTuning.swishFrames)
    }

    /// A tie back toward its length, each end taking half, a pinned end none.
    private func relax(_ tie: Tie) {
        let a = knots[tie.a].at, b = knots[tie.b].at
        let length = max(HoopNet.distance(a, b), 0.0001)
        let error = (length - tie.rest) / length
        let pinA = knots[tie.a].pinned, pinB = knots[tie.b].pinned
        guard !(pinA && pinB) else { return }
        let shareA: CGFloat = pinA ? 0 : (pinB ? 1 : 0.5)
        let shareB: CGFloat = pinB ? 0 : (pinA ? 1 : 0.5)
        let delta = CGPoint(x: (b.x - a.x) * error, y: (b.y - a.y) * error)
        knots[tie.a].at = CGPoint(x: a.x + delta.x * shareA, y: a.y + delta.y * shareA)
        knots[tie.b].at = CGPoint(x: b.x - delta.x * shareB, y: b.y - delta.y * shareB)
    }

    /// Every free knot out of the capsule swept from `from` to `to`, and on the first pass
    /// carried a share of the way the ball went.
    private func push(outOf from: CGPoint, to: CGPoint, radius: CGFloat, carry: Bool) {
        let path = CGPoint(x: to.x - from.x, y: to.y - from.y)
        let span = path.x * path.x + path.y * path.y
        for index in knots.indices where !knots[index].pinned {
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

    /// A chevron on every knot, smaller a step at a time down the column.
    private func place() {
        let topScale = NetTuning.topScale, bottomScale = NetTuning.bottomScale
        drawnScales = [topScale, bottomScale]
        let lastRow = CGFloat(max(NetTuning.chevronsPerColumn - 1, 1))
        let path = CGMutablePath()
        for knot in knots {
            let scale = topScale + (bottomScale - topScale) * CGFloat(knot.row) / lastRow
            let halfWidth = NetTuning.chevronWidth * scale / 2, halfDepth = NetTuning.chevronDepth * scale / 2
            path.move(to: CGPoint(x: knot.at.x - halfWidth, y: knot.at.y + halfDepth))
            path.addLine(to: CGPoint(x: knot.at.x, y: knot.at.y - halfDepth))
            path.addLine(to: CGPoint(x: knot.at.x + halfWidth, y: knot.at.y + halfDepth))
        }
        shape.path = path
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
