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
    static var spread: CGFloat { stored(spreadKey) ?? 3 }
    static var rowSpacing: CGFloat { stored(rowSpacingKey) ?? 2 }
    static var weave: CGFloat { stored(weaveKey) ?? 0.25 }
    static var taper: CGFloat { stored(taperKey) ?? 0.5 }
    static var skew: CGFloat { stored(skewKey) ?? -0.25 }
    static var offset: CGPoint { CGPoint(x: stored(offsetXKey) ?? 0, y: stored(offsetYKey) ?? -5) }
    /// NET X and NET Y for a stage: Longball Stadium's kept apart, the court's until set;
    /// the net goes where the stage's hoop art does against the court's too.
    static func offsetXKey(for look: StageLook) -> String { look == .footballField ? offsetXKey + ".stadium" : offsetXKey }
    static func offsetYKey(for look: StageLook) -> String { look == .footballField ? offsetYKey + ".stadium" : offsetYKey }
    /// What NET X and NET Y are set to on a stage: Longball Stadium's (-1, -5) as tuned.
    static func setting(for look: StageLook) -> CGPoint {
        let placed = look == .footballField ? CGPoint(x: -1, y: -5) : offset
        return CGPoint(x: stored(offsetXKey(for: look)) ?? placed.x, y: stored(offsetYKey(for: look)) ?? placed.y)
    }
    /// Where the net hangs against the rim: the setting, moved as far as the stage's hoop art is from `HoopTuning.netReference`.
    static func offset(for look: StageLook) -> CGPoint {
        let hoopMoved = HoopTuning.offset(for: look) - HoopTuning.netReference
        let setting = setting(for: look)
        return CGPoint(x: setting.x + hoopMoved.x, y: setting.y + hoopMoved.y)
    }
    /// The cylinder net, drawn by the Metal layer in place of the flat one, whose cloth
    /// still runs for its sway: each ring's radius at the top and bottom (NET RADIUS TOP and
    /// BOTTOM), how many rings (NET RINGS, NET ROWS apart) and chevrons round each (NET
    /// AROUND), and its turn about its top in degrees (NET TILT X, TURN Y, ROLL Z), kept
    /// between launches; the chevrons' sizes are NET TOP and NET BOTTOM.
    static let cylinder = true
    /// How far the cylinder moves against its row of the cloth: twice as far.
    static let swayShare: CGFloat = 2
    /// A dunk flares the net out at the bottom, like a lampshade: the bottom ring's radius out
    /// to this, eased in and back over these frames.
    static let dunkFlareRadius: CGFloat = 12
    static let dunkFlareFrames = 10
    /// A made shot's swish moves it across this much further again, fading over the swish.
    static let swishShare: CGFloat = 3
    static let radiusTopKey = "ui.net.cylinder.radiusTop"
    static let radiusBottomKey = "ui.net.cylinder.radiusBottom"
    static let ringsKey = "ui.net.cylinder.rings"
    static let aroundKey = "ui.net.cylinder.around"
    static let tiltKey = "ui.net.cylinder.tilt"
    static let turnKey = "ui.net.cylinder.turn"
    static let rollKey = "ui.net.cylinder.roll"
    static var radiusTop: CGFloat { stored(radiusTopKey) ?? 7.5 }
    static var radiusBottom: CGFloat { stored(radiusBottomKey) ?? 4.5 }
    static var rings: CGFloat { stored(ringsKey) ?? 7 }
    static var around: CGFloat { stored(aroundKey) ?? 9 }
    static var tilt: CGFloat { stored(tiltKey) ?? -20 }
    static var turn: CGFloat { stored(turnKey) ?? 0 }
    static var roll: CGFloat { stored(rollKey) ?? 0 }
    /// Every saved net value dropped once when `bakedVersion` goes up, so the values baked in
    /// here come back over whatever a slider last saved.
    static let bakedVersion = 1
    private static let bakedVersionKey = "ui.net.bakedVersion"
    static func dropSavedIfStale() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: bakedVersionKey) != bakedVersion else { return }
        let looks: [StageLook] = [.court, .footballField]
        let keys = [topScaleKey, bottomScaleKey, spreadKey, rowSpacingKey, weaveKey, taperKey, skewKey,
                    radiusTopKey, radiusBottomKey, ringsKey, aroundKey, tiltKey, turnKey, rollKey]
            + looks.flatMap { [offsetXKey(for: $0), offsetYKey(for: $0)] }
        for key in keys { defaults.removeObject(forKey: key) }
        defaults.set(bakedVersion, forKey: bakedVersionKey)
    }

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
    /// Further than this in a frame, the rim jumped.
    private static let jumpDistance: CGFloat = 40
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
    /// A wind's push on the net, pixels a frame along x at its bottom, less up toward the rim;
    /// while there's any it never sleeps.
    var wind: CGFloat = 0
    private var lastBall: CGPoint?
    private var swish: Swish?
    /// A left backboard mirrors the skew.
    private let facing: CGFloat
    private var builtSpacing: [CGFloat] = []
    private var drawnScales: [CGFloat] = []

    /// The strands as drawn this frame, in the parent's space; nil while hidden.
    var drawnPath: CGPath? { shape.isHidden ? nil : shape.path }
    /// Out of sight a while, as the Hoopfish spins the rim.
    var hidden = false { didSet { shape.isHidden = hidden || NetTuning.cylinder } }

    init(at rim: CGPoint, mirrored: Bool, colour: SKColor, into parent: SKNode, depth: CGFloat = 4) {
        self.rim = rim
        facing = mirrored ? -1 : 1
        shape.strokeColor = colour
        shape.lineWidth = NetTuning.lineWidth
        shape.lineCap = .square
        shape.isAntialiased = false
        shape.zPosition = depth
        shape.isHidden = NetTuning.cylinder
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

    /// For the cylinder: where the net hangs from, which way it's mirrored, its colour, and
    /// each row's sway, the cloth's knots on it against their places.
    var hangPoint: CGPoint { rim }
    /// How far into its dunk flare, 0 to 1; the scene eases it while someone hangs on the rim.
    var dunkFlare: CGFloat = 0
    /// 1 as a swish starts, fading to 0 over the swish's frames.
    private(set) var swishWeight: CGFloat = 0
    var mirrored: Bool { facing < 0 }
    var colour: SKColor { shape.strokeColor }
    var rowSways: [CGPoint] {
        (0..<NetTuning.chevronsPerColumn).map { row in
            let inRow = knots.filter { $0.row == row }
            guard !inRow.isEmpty else { return .zero }
            let total = inRow.reduce(CGPoint.zero) { sum, knot in
                CGPoint(x: sum.x + knot.at.x - rim.x - knot.home.x, y: sum.y + knot.at.y - rim.y - knot.home.y)
            }
            return CGPoint(x: total.x / CGFloat(inRow.count), y: total.y / CGFloat(inRow.count))
        }
    }
    /// Each row's width against its width at rest: a ball through the middle spreads the
    /// row both ways, which its sway, the average, doesn't show.
    var rowSpreads: [CGFloat] {
        (0..<NetTuning.chevronsPerColumn).map { row in
            let inRow = knots.filter { $0.row == row }
            guard let restLeft = inRow.map(\.home.x).min(), let restRight = inRow.map(\.home.x).max(), restRight - restLeft > 0.01,
                  let left = inRow.map(\.at.x).min(), let right = inRow.map(\.at.x).max() else { return 1 }
            return (right - left) / (restRight - restLeft)
        }
    }

    /// One frame: the rim where it is now, the ball where it is (nil while it's nowhere to
    /// be hit), and the chests of the bodies.
    func step(rim: CGPoint, ball: CGPoint?, ballRadius: CGFloat, bodies: [CGPoint]) {
        // A rim that jumped rather than moved, coming on from where it was parked, takes its
        // net with it whole rather than dragging it there.
        if HoopNet.distance(rim, self.rim) > HoopNet.jumpDistance {
            for index in knots.indices {
                let home = CGPoint(x: rim.x + knots[index].home.x, y: rim.y + knots[index].home.y)
                knots[index].at = home
                knots[index].was = home
            }
            self.rim = rim
            awake = true
        }
        let rimMoved = HoopNet.distance(rim, self.rim) > 0.01
        self.rim = rim
        if builtSpacing != NetTuning.meshValues { buildMesh() }
        let reach = NetTuning.spread * CGFloat(NetTuning.columns) + NetTuning.rowSpacing * CGFloat(NetTuning.chevronsPerColumn) + 24
        let ballNear = ball.map { HoopNet.distance($0, rim) < reach } ?? false
        let bodyNear = bodies.contains { HoopNet.distance($0, rim) < reach }
        if let ball, let lastBall, swish == nil { catchSwish(from: lastBall, to: ball, radius: ballRadius) }
        if swishWeight > 0 { swishWeight = max(swishWeight - 1 / CGFloat(NetTuning.swishFrames), 0) }
        if rimMoved || ballNear || bodyNear || swish != nil || wind != 0 {
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
            let depth = max(-(knots.map(\.home.y).min() ?? -1), 1)
            let push = wind * min(max(-knot.home.y / depth, 0), 1)
            knots[index].at = CGPoint(x: knot.at.x + velocity.x + push + (home.x - knot.at.x) * NetTuning.settle,
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
        swishWeight = 1
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
