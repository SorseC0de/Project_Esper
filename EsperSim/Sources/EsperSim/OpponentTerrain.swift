import Foundation

/// The stage as the computer reads it to get about: where it can stand, which of those its
/// jumps reach from which, and the way from one to another. The jump is measured, not worked
/// out: a copy of its body jumps on an empty stage with the same water, so the reach is the
/// sim's own. Read once a stage; the links between surfaces as they're first asked for.
final class Terrain: Equatable {
    /// Somewhere to stand: the feet's height every `sampleStep` across from `left`; or a
    /// tornado's middle, where it holds a body.
    struct Surface {
        var left: Double
        var heights: [Double]
        var tornado: Int?
        /// Stood on only by one-ways: down drops through it, and a jump comes up through it.
        var passable: Bool

        var right: Double { left + Double(heights.count - 1) * Terrain.sampleStep }
        var middle: Double { (left + right) / 2 }
        func clamp(_ x: Double) -> Double { min(max(x, left), right) }
        func height(at x: Double) -> Double {
            heights[min(max(Int(((x - left) / Terrain.sampleStep).rounded()), 0), heights.count - 1)]
        }
    }

    /// How a link is played from its takeoff: the full hop, the second jump at its top if it's
    /// short; walking off the edge (or drifting out of a tornado), the second jump once it's
    /// fallen `jumpBelow` if that's set; or down through a one-way.
    enum Kind: Equatable { case hop, walkOff, dropThrough }

    /// From one surface onto another: stand at `takeoff`, then play `kind` for `landing`. Found
    /// by playing it, on the stage, with a copy of the body, so it's known to make it.
    struct Link: Equatable {
        var to: Int
        var kind: Kind
        var takeoff: Double
        var landing: Double
        var jumpBelow: Double?
        var cost: Double
        /// Taken from far enough in off the edge that a dribbled ball never hangs over it.
        var ballSafe = true
        /// A hop's stick held still this many frames before it steers, to rise clear of what's over the way.
        var steerAfter = 0
        /// Frames from setting off to coming down, the longest of its tries.
        var frames = 0
    }

    /// What the reading was made from, to tell when the stage or the body has changed.
    struct Signature: Equatable {
        var columns: Int
        var rows: Int
        var tiles: [Tile]
        var slopes: [Slope]
        var tornados: [Box]
        var underwater: Bool
        var bodyWidth: Double
        var bodyHeight: Double
        var hop: Double
        var doubleJump: Double
    }

    static let sampleStep = 5.0
    /// Each jump costs this many units of walking, so a flat way round is taken over a hop.
    static let jumpCost = 15.0

    let signature: Signature
    let surfaces: [Surface]
    /// The jump from standing with the stick held one way and the second jump at the top of the
    /// first, frame by frame from the press: how far across and up from the takeoff.
    let arc: [Vec2]
    /// The arc's highest frame, and how high that is.
    let apex: Int
    let rise: Double
    let lava: Double?
    let halfWidth: Double
    let bodyHeight: Double
    private let stage: Stage
    /// The body the links are played with.
    private let template: Player
    private var links: [Int: [Link]] = [:]
    /// The links still to be found, surface by surface, a share each frame.
    private var nextSource = 0
    private var nextTarget = 0
    private var found: [Link] = []

    static func == (left: Terrain, right: Terrain) -> Bool { left === right }

    static func signature(of stage: Stage, for player: Player) -> Signature {
        Signature(columns: stage.columns, rows: stage.rows, tiles: stage.tiles, slopes: stage.fixedSlopes + stage.ceilingSlopes,
                  tornados: stage.tornados, underwater: stage.features.underwater,
                  bodyWidth: player.spec.bodyWidth, bodyHeight: player.spec.bodyHeight,
                  hop: player.spec.fullHopVelocity, doubleJump: player.spec.doubleJumpVelocity)
    }

    init(stage given: Stage, player: Player) {
        signature = Terrain.signature(of: given, for: player)
        // Only what stays put: no slabs, helmets or cars.
        var stage = given
        stage.extras = given.fixedExtras
        stage.slopes = given.fixedSlopes
        self.stage = stage
        lava = stage.features.lavaSurface
        halfWidth = player.spec.bodyWidth / 2
        bodyHeight = player.spec.bodyHeight
        template = Player(spec: player.spec, index: player.index, position: .zero, facing: .right)
        arc = Terrain.measureJump(of: player, underwater: stage.features.underwater)
        var highest = 0
        for (frame, point) in arc.enumerated() where point.y > arc[highest].y { highest = frame }
        apex = highest
        rise = arc.isEmpty ? 0 : arc[highest].y
        surfaces = Terrain.readSurfaces(of: stage, halfWidth: halfWidth, bodyHeight: bodyHeight, lava: lava)
    }

    // MARK: Reading the stage

    /// Every height across the stage a body stands at, the stage's own collision deciding, run
    /// together into surfaces where neighbours are within a slope's step; then the tornados.
    private static func readSurfaces(of stage: Stage, halfWidth: Double, bodyHeight: Double, lava: Double?) -> [Surface] {
        var surfaces: [Surface] = []
        var open: [Int] = []
        let count = Int(stage.width / sampleStep)
        for sample in 0..<count {
            let x = (Double(sample) + 0.5) * sampleStep
            let column = Int(x / Stage.tileSize)
            var heights: Set<Double> = []
            for row in 0..<stage.rows where stage.tile(column: column, row: row) != .empty {
                heights.insert(Double(row + 1) * Stage.tileSize)
            }
            for slope in stage.slopes where slope.box.min.x <= x && x <= slope.box.max.x { heights.insert(slope.surface(at: x)) }
            for slope in stage.ceilingSlopes where slope.box.min.x <= x && x <= slope.box.max.x { heights.insert(slope.box.max.y) }
            for extra in stage.extras where extra.min.x <= x && x <= extra.max.x && extra.max.y < stage.height { heights.insert(extra.max.y) }
            var continued: [Int] = []
            for y in heights.sorted() {
                if let lava, y < lava + 1 { continue }
                let body = Box(min: Vec2(x: x - halfWidth, y: y), max: Vec2(x: x + halfWidth, y: y + bodyHeight))
                guard !stage.overlapsSolid(body), stage.isGrounded(body) else { continue }
                let passable = stage.standsOnlyOnOneWays(body)
                let joined = open.first { index in
                    let surface = surfaces[index]
                    return surface.tornado == nil && abs(surface.heights.last! - y) <= sampleStep + 0.5 && surface.passable == passable
                        && !continued.contains(index)
                }
                if let joined {
                    surfaces[joined].heights.append(y)
                    continued.append(joined)
                } else {
                    surfaces.append(Surface(left: x, heights: [y], passable: passable))
                    continued.append(surfaces.count - 1)
                }
            }
            open = continued
        }
        for (index, tornado) in stage.tornados.enumerated() {
            let centre = tornado.center
            surfaces.append(Surface(left: centre.x - sampleStep, heights: [centre.y - bodyHeight / 2, centre.y - bodyHeight / 2, centre.y - bodyHeight / 2],
                                    tornado: index, passable: true))
        }
        return surfaces
    }

    /// A copy of the body jumps on an empty stage with the same water: off a ledge high up, the
    /// stick held right, the hop held full, the second jump at the top of the first, down to
    /// the floor far below. Where it is each frame from the press, from where it stood.
    private static func measureJump(of player: Player, underwater: Bool) -> [Vec2] {
        let columns = 60, rows = 60
        var stage = Stage(columns: columns, rows: rows, hoops: [Hoop(position: HighwayRules.parked, owner: 0, backboard: .right)],
                          playerSpawns: [], playerFacings: [], ballSpawn: .zero)
        stage.fill(.solid, columns: 0...(columns - 1), rows: 0...0)
        stage.fill(.solid, columns: 0...10, rows: 39...39)
        stage.features.underwater = underwater
        var body = Player(spec: player.spec, index: player.index, position: Vec2(x: 105, y: 400), facing: .right)
        var events: [MatchEvent] = []
        for _ in 0..<4 { _ = body.step(input: .idle, stage: stage, events: &events) }
        let start = body.position
        var arc: [Vec2] = []
        var leftGround = false, doubled = false, jumpWasDown = false
        for _ in 0..<900 {
            var input = PlayerInput(stick: Vec2(x: 1, y: 0))
            if !leftGround {
                input.jump = true
            } else if !doubled, body.velocity.y < 0.5 {
                input.jump = !jumpWasDown
                if input.jump { doubled = true }
            }
            jumpWasDown = input.jump
            _ = body.step(input: input, stage: stage, events: &events)
            if !body.grounded { leftGround = true }
            arc.append(body.position - start)
            if leftGround, body.grounded { break }
        }
        return arc
    }

    // MARK: Where things are

    /// The surface a body is on, by its feet.
    func surface(under feet: Vec2, suspendedIn tornado: Int? = nil) -> Int? {
        if let tornado { return surfaces.firstIndex { $0.tornado == tornado } }
        var best: (index: Int, gap: Double)?
        for (index, surface) in surfaces.enumerated() where surface.tornado == nil
            && feet.x >= surface.left - Terrain.sampleStep && feet.x <= surface.right + Terrain.sampleStep {
            let gap = abs(surface.height(at: feet.x) - feet.y)
            if gap <= 4, best == nil || gap < best!.gap { best = (index, gap) }
        }
        return best?.index
    }

    /// The place to stand nearest a point, under it rather than over it: the ball's landing,
    /// a guard spot. A tornado only for a point inside one.
    func standing(nearest point: Vec2, avoiding avoided: Set<Int> = []) -> (surface: Int, x: Double)? {
        var best: (surface: Int, x: Double, score: Double)?
        for (index, surface) in surfaces.enumerated() where !avoided.contains(index) {
            if let tornado = surface.tornado {
                guard stage.tornados[tornado].contains(point) else { continue }
                return (index, surface.middle)
            }
            let x = surface.clamp(point.x)
            let y = surface.height(at: x)
            let above = y - point.y
            let score = abs(x - point.x) + (above > 0 ? above * 2 : -above * 0.5)
            if best == nil || score < best!.score { best = (index, x, score) }
        }
        return best.map { ($0.surface, $0.x) }
    }

    /// Whether there's anywhere to land under `x` before the lava.
    func ground(under x: Double, below y: Double) -> Bool {
        surfaces.contains { $0.tornado == nil && x >= $0.left - 2 && x <= $0.right + 2 && $0.height(at: x) <= y + 1 }
    }

    // MARK: The way

    /// The cheapest way from one surface to another, as the links to take in turn; empty when
    /// they're the same, nil when there's none. `usable` rules a link out for now.
    func route(from start: Int, to goal: Int, usable: (Int, Link) -> Bool) -> [Link]? {
        route(from: start, to: goal, at: nil, speed: 1) { from, link, _, _ in usable(from, link) }
    }

    /// The cheapest way, timed: setting off from `x` (or the surface's middle) walking at `speed`,
    /// each link asked whether it can be taken leaving and landing so many frames from now.
    func route(from start: Int, to goal: Int, at x: Double?, speed: Double, usable: (Int, Link, Int, Int) -> Bool) -> [Link]? {
        if start == goal { return [] }
        var cost = Array(repeating: Double.infinity, count: surfaces.count)
        var time = Array(repeating: 0, count: surfaces.count)
        var entry = surfaces.map(\.middle)
        entry[start] = x ?? surfaces[start].middle
        var via: [Int: (from: Int, link: Link)] = [:]
        var done = Array(repeating: false, count: surfaces.count)
        cost[start] = 0
        while true {
            var current: Int?
            for index in surfaces.indices where !done[index] && cost[index] < .infinity && (current == nil || cost[index] < cost[current!]) {
                current = index
            }
            guard let here = current else { return nil }
            if here == goal { break }
            done[here] = true
            for link in links(from: here) where !done[link.to] {
                let leaves = time[here] + Int(abs(link.takeoff - entry[here]) / max(speed, 0.1))
                let lands = leaves + link.frames
                guard usable(here, link, leaves, lands) else { continue }
                let total = cost[here] + link.cost
                if total < cost[link.to] {
                    cost[link.to] = total
                    time[link.to] = lands
                    entry[link.to] = link.landing
                    via[link.to] = (here, link)
                }
            }
        }
        var path: [Link] = []
        var at = goal
        while at != start, let step = via[at] {
            path.insert(step.link, at: 0)
            at = step.from
        }
        return path
    }

    /// The links off a surface, once they've been found.
    func links(from index: Int) -> [Link] { links[index] ?? [] }

    /// Whether every surface's links have been found.
    var ready: Bool { nextSource >= surfaces.count }

    /// Finds more links, playing moves until about `budget` frames of the body have been stepped.
    func prepare(budget: Int) {
        var steps = 0
        while steps < budget, nextSource < surfaces.count {
            if nextTarget < surfaces.count {
                found += links(from: nextSource, to: nextTarget, steps: &steps)
                nextTarget += 1
            } else {
                links[nextSource] = found
                found = []
                nextSource += 1
                nextTarget = 0
            }
        }
    }

    /// The cheapest move from one surface onto another that makes it, if any does: each way of
    /// going played with a copy of the body.
    private func links(from start: Int, to end: Int, steps: inout Int) -> [Link] {
        guard start != end else { return [] }
        let from = surfaces[start], to = surfaces[end]
        if from.tornado != nil, to.tornado == from.tornado { return [] }
        let fromY = from.tornado != nil ? from.heights[0] : from.height(at: from.clamp(to.middle))
        let toY = to.tornado != nil ? to.heights[0] : to.height(at: to.clamp(from.middle))
        let gap = max(to.left - from.right, from.left - to.right, 0)
        // Too high, or too far for any jump to cross.
        if toY - fromY > rise + 8 || gap > Terrain.farthest { return [] }
        var options: [(Kind, Double, Double)] = []
        let overlapLeft = max(from.left, to.left), overlapRight = min(from.right, to.right)
        if from.tornado != nil {
            // Out of a tornado by the jump: drifting out, its edge only takes the body back.
            let landing = to.tornado != nil ? to.middle : to.clamp(from.middle)
            options.append((.hop, from.middle, landing))
        } else if to.tornado != nil {
            let takeoff = from.clamp(to.middle)
            options.append((.hop, takeoff, to.middle))
            if to.heights[0] < from.height(at: takeoff) {
                options.append((.walkOff, to.middle >= from.right ? from.right : from.left, to.middle))
            }
        } else if overlapLeft <= overlapRight {
            let middle = (overlapLeft + overlapRight) / 2
            if to.height(at: middle) > from.height(at: middle) {
                // Up onto one over it: through a one-way, or round its end.
                if to.passable { options.append((.hop, middle, middle)) }
                if from.left <= to.left - 10 { options.append((.hop, to.left - 10, to.left + 5)) }
                if from.right >= to.right + 10 { options.append((.hop, to.right + 10, to.right - 5)) }
            } else {
                // Down onto one under it: through a one-way, or off its end.
                if from.passable { options.append((.dropThrough, middle, middle)) }
                if to.left < from.left - 5 {
                    options.append((.walkOff, from.left, max(to.left + 5, from.left - 20)))
                    options.append((.hop, from.left + 2, max(to.left + 5, from.left - 20)))
                }
                if to.right > from.right + 5 {
                    options.append((.walkOff, from.right, min(to.right - 5, from.right + 20)))
                    options.append((.hop, from.right - 2, min(to.right - 5, from.right + 20)))
                }
            }
        } else if to.left > from.right {
            options.append((.hop, from.right - 2, to.left + 5))
            options.append((.walkOff, from.right, to.left + 5))
        } else {
            options.append((.hop, from.left + 2, to.right - 5))
            options.append((.walkOff, from.left, to.right - 5))
        }
        // The same hops again from a body's length in off the edge, so a ball being dribbled
        // doesn't hang out over it first.
        if from.tornado == nil {
            for (kind, takeoff, landing) in options where kind == .hop {
                let toward: Double = landing >= takeoff ? 1 : -1
                let inset = toward > 0 ? min(takeoff, from.right - Terrain.dribbleInset) : max(takeoff, from.left + Terrain.dribbleInset)
                if inset != takeoff, inset >= from.left, inset <= from.right { options.append((.hop, inset, landing)) }
            }
        }
        var found: [Link] = []
        for (kind, takeoff, landing) in options {
            let toward: Double = landing >= takeoff ? 1 : -1
            let fromEdge = from.tornado != nil ? Double.infinity : (toward > 0 ? from.right - takeoff : takeoff - from.left)
            // Out of a tornado there's no dribble to hang over anything.
            let ballSafe = from.tornado != nil || (kind != .walkOff && fromEdge >= Terrain.dribbleInset - 1)
            // One of each: the cheapest that makes it, and the cheapest that does with a ball in hand.
            if found.contains(where: { !$0.ballSafe }) && !ballSafe { continue }
            if found.contains(where: { $0.ballSafe }) && ballSafe { continue }
            let falls: [Double?] = kind == .walkOff ? [nil, 10, 30] : [nil]
            for jumpBelow in falls {
                let link = Link(to: end, kind: kind, takeoff: takeoff, landing: landing, jumpBelow: jumpBelow,
                                cost: abs(landing - takeoff) + (kind == .hop || jumpBelow != nil ? Terrain.jumpCost : 0) + abs(toY - fromY) * 0.5,
                                ballSafe: ballSafe)
                // Made from a little either side of the takeoff too: the body's never quite on it.
                let tries = [0.0, -Terrain.takeoffSlack, Terrain.takeoffSlack].map { plays(link, from: start, offset: $0, steps: &steps) }
                if tries.allSatisfy({ $0 != nil }) {
                    var made = link
                    made.frames = tries.compactMap { $0 }.max() ?? 0
                    found.append(made)
                    break
                }
            }
        }
        // Out of a tornado with nothing found: up first and across after, or the second jump held
        // back till it's dropped a little, for a way across under something.
        // Only from one tornado to another: onto solid ground these come down against walls in play.
        if found.isEmpty, from.tornado != nil, to.tornado != nil {
            let landing = to.tornado != nil ? to.middle : to.clamp(from.middle)
            variants: for steerAfter in [0, 15, 30] {
                for jumpBelow in [nil, 5.0, 20.0] where steerAfter > 0 || jumpBelow != nil {
                    var link = Link(to: end, kind: .hop, takeoff: from.middle, landing: landing, jumpBelow: jumpBelow,
                                    cost: abs(landing - from.middle) + Terrain.jumpCost + Terrain.variantCost + abs(toY - fromY) * 0.5)
                    link.steerAfter = steerAfter
                    let tries = [0.0, -Terrain.takeoffSlack, Terrain.takeoffSlack].map { plays(link, from: start, offset: $0, steps: &steps) }
                    if tries.allSatisfy({ $0 != nil }) {
                        link.frames = tries.compactMap { $0 }.max() ?? 0
                        found.append(link)
                        break variants
                    }
                }
            }
        }
        return found
    }

    /// What a held-back hop costs on top, so a way of plain hops is taken whenever there is one:
    /// those ways out are fussier, and the body's never quite where its try was.
    static let variantCost = 200.0

    /// How far in off an edge a hop is also tried from, so a dribbled ball stays over ground.
    static let dribbleInset = 10.0

    /// How far off its takeoff a move is also tried from, either side.
    static let takeoffSlack = 3.0
    /// Nothing farther across than this is tried.
    private static let farthest = 220.0
    /// A move played this long without landing has failed.
    private static let moveFrames = 360

    /// Plays the link with a copy of the body from standing at its takeoff, or held in its
    /// tornado: whether it comes down on the surface it's for.
    /// The frames it took to come down where it's for, or nil if it didn't.
    private func plays(_ link: Link, from start: Int, offset: Double, steps: inout Int) -> Int? {
        let from = surfaces[start], to = surfaces[link.to]
        let takeoff = from.tornado != nil ? link.takeoff + offset : from.clamp(link.takeoff + offset)
        let startY = from.tornado != nil ? from.heights[0] : from.height(at: takeoff)
        var body = template
        body.position = Vec2(x: takeoff, y: startY)
        body.facing = link.landing >= link.takeoff ? .right : .left
        if let tornado = from.tornado {
            body.grounded = false
            body.enter(.suspended)
            body.tornadoCentre = stage.tornados[tornado].center
        }
        var events: [MatchEvent] = []
        var leftGround = false
        var jumpWasDown = false
        for frame in 0..<Terrain.moveFrames {
            let input = Terrain.input(for: link, body: body, startY: startY, target: to, leftGround: leftGround, jumpWasDown: jumpWasDown, halfWidth: halfWidth,
                                      framesIn: frame)
            jumpWasDown = input.jump
            _ = body.step(input: input, stage: stage, events: &events)
            steps += 1
            // As the match does: out of the tornado's box, out of its hold.
            if body.state == .suspended, let tornado = from.tornado, !body.body.overlaps(stage.tornados[tornado]) { body.enter(.air) }
            if !body.grounded, body.state != .suspended, body.state != .jumpSquat { leftGround = true }
            if let lava, body.position.y < lava { return nil }
            if body.position.y < 0 { return nil }
            // Through another tornado on the way it would be caught there, if it's up.
            if leftGround, body.state == .air, stage.tornados.indices.contains(where: { $0 != from.tornado && $0 != to.tornado && stage.tornados[$0].overlaps(body.body) }) {
                return nil
            }
            if let tornado = to.tornado {
                if leftGround, body.body.overlaps(stage.tornados[tornado]) { return frame + 1 }
            } else if leftGround, body.grounded {
                return surface(under: body.position) == link.to ? frame + 1 : nil
            }
            if !leftGround, frame > 60 { return nil }
        }
        return nil
    }

    /// One frame of a link being played, the same for the copy that tried it and the body taking
    /// it: the hop held full and the stick let go through the squat, then steered for the landing,
    /// held off a solid surface's near end until over its height; the second jump when it's short.
    static func input(for link: Link, body: Player, startY: Double, target: Surface, leftGround: Bool, jumpWasDown: Bool, halfWidth: Double,
                      framesIn: Int) -> PlayerInput {
        var input = PlayerInput()
        let direction: Double = link.landing >= link.takeoff ? 1 : -1
        let targetY = target.tornado != nil ? target.heights[0] : target.height(at: link.landing)
        var aim = link.landing
        // Held off only while it can still rise: falling with no jump left, it goes for the edge.
        if !target.passable, target.tornado == nil, body.position.y < targetY + 1, body.jumpsLeft > 0 || body.velocity.y > 0 {
            // Its end sample is half a step in from the solid's edge: clear of that by a body's half and a step.
            let limit = (direction > 0 ? target.left : target.right) - direction * (halfWidth + Terrain.sampleStep)
            if (aim - limit) * direction > 0, (body.position.x - limit) * direction <= 0 { aim = limit }
        }
        let dx = aim - body.position.x
        let steer: Double = abs(dx) > 2 ? (dx > 0 ? 1 : -1) : 0
        let press = !jumpWasDown
        switch link.kind {
        case .hop:
            if body.state == .suspended {
                input.jump = press
                input.stick = Vec2(x: link.steerAfter > 0 ? 0 : direction, y: 0)
            } else if !leftGround {
                input.jump = true
            } else {
                input.stick = Vec2(x: framesIn < link.steerAfter ? 0 : steer, y: 0)
                // The second jump when it's short, or, given a depth, once it's fallen that far below where it set off.
                let due = link.jumpBelow.map { body.velocity.y < 0 && body.position.y < startY - $0 }
                    ?? (body.position.y < targetY - 2 || (targetY > startY && body.position.y < targetY + 12)) && body.velocity.y < 0.5
                if due, body.jumpsLeft > 0 { input.jump = press }
            }
        case .walkOff:
            if !leftGround {
                input.stick = Vec2(x: direction, y: 0)
            } else {
                input.stick = Vec2(x: steer, y: 0)
                if let below = link.jumpBelow, body.jumpsLeft > 0, body.velocity.y < 0, body.position.y < startY - below { input.jump = press }
            }
        case .dropThrough:
            input.stick = leftGround ? Vec2(x: steer, y: 0) : Vec2(x: 0, y: -1)
        }
        return input
    }

    /// The frames from a jump's press until it's this high, on the way up; nil past its reach.
    func framesToRise(_ height: Double) -> Int? {
        arc.prefix(apex + 1).firstIndex { $0.y >= height }.map { $0 + 1 }
    }
}

extension Box {
    func contains(_ point: Vec2) -> Bool {
        point.x >= min.x && point.x <= max.x && point.y >= min.y && point.y <= max.y
    }
}
