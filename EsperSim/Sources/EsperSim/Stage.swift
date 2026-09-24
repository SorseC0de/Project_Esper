import Foundation

public enum Tile: UInt8, Equatable {
    case empty, solid, oneWay
}

/// A rim. The ball falls through it from above into the owner's score.
public struct Hoop: Equatable {
    /// Centre of the rim.
    public var position: Vec2
    /// Which player scores here.
    public var owner: Int
    /// The side the backboard is on; the rim opens the other way.
    public var backboard: Facing

    public init(position: Vec2, owner: Int, backboard: Facing) {
        self.position = position
        self.owner = owner
        self.backboard = backboard
    }
}

/// An axis-aligned box in units.
public struct Box: Equatable {
    public var min: Vec2
    public var max: Vec2

    public init(min: Vec2, max: Vec2) {
        self.min = min
        self.max = max
    }

    public init(center: Vec2, width: Double, height: Double) {
        min = Vec2(x: center.x - width / 2, y: center.y - height / 2)
        max = Vec2(x: center.x + width / 2, y: center.y + height / 2)
    }

    public var center: Vec2 { Vec2(x: (min.x + max.x) / 2, y: (min.y + max.y) / 2) }
    public var width: Double { max.x - min.x }
    public var height: Double { max.y - min.y }

    public func overlaps(_ o: Box) -> Bool {
        min.x < o.max.x && max.x > o.min.x && min.y < o.max.y && max.y > o.min.y
    }

    /// How far the point is from the box's nearest edge; zero inside it.
    public func distance(to point: Vec2) -> Double {
        let across = Swift.max(min.x - point.x, 0, point.x - max.x)
        let up = Swift.max(min.y - point.y, 0, point.y - max.y)
        return (across * across + up * up).squareRoot()
    }

    public func offset(by d: Vec2) -> Box { Box(min: min + d, max: max + d) }
}

/// The court: a grid of tiles, row 0 at the bottom, plus the rims and where everyone starts.
public struct Stage: Equatable {
    public static let tileSize = 10.0
    /// Rows of open sky above the grid before a ceiling, so a ball thrown straight up comes back.
    public static let skyRows = 10

    public let columns: Int
    public let rows: Int
    public var tiles: [Tile]
    public var hoops: [Hoop]
    public var playerSpawns: [Vec2]
    public var playerFacings: [Facing]
    public var ballSpawn: Vec2
    /// Solid boxes that come and go, such as a made platform. Everything that asks the
    /// stage about solids sees them.
    public var extras: [Box] = []
    /// What the stage has beyond its tiles.
    public var features = StageFeatures()

    public var width: Double { Double(columns) * Stage.tileSize }
    public var height: Double { Double(rows) * Stage.tileSize }

    public init(columns: Int, rows: Int, hoops: [Hoop], playerSpawns: [Vec2], playerFacings: [Facing], ballSpawn: Vec2) {
        self.columns = columns
        self.rows = rows
        tiles = Array(repeating: .empty, count: columns * rows)
        self.hoops = hoops
        self.playerSpawns = playerSpawns
        self.playerFacings = playerFacings
        self.ballSpawn = ballSpawn
    }

    /// Outside the grid: solid below and to the sides, and above the top the side walls
    /// carry on up through `skyRows` of open sky to a ceiling.
    public func tile(column: Int, row: Int) -> Tile {
        guard column >= 0, column < columns, row >= 0 else { return .solid }
        guard row < rows else {
            return column == 0 || column == columns - 1 || row >= rows + Stage.skyRows ? .solid : .empty
        }
        return tiles[row * columns + column]
    }

    public mutating func set(_ tile: Tile, column: Int, row: Int) {
        guard column >= 0, column < columns, row >= 0, row < rows else { return }
        tiles[row * columns + column] = tile
    }

    public mutating func fill(_ tile: Tile, columns: ClosedRange<Int>, rows: ClosedRange<Int>) {
        for row in rows {
            for column in columns {
                set(tile, column: column, row: row)
            }
        }
    }

    // MARK: Collision

    private static let edge = 1e-6

    private func column(at x: Double) -> Int { Int((x / Stage.tileSize).rounded(.down)) }
    private func row(at y: Double) -> Int { Int((y / Stage.tileSize).rounded(.down)) }

    /// Columns a box spans, its right edge exclusive.
    private func columns(of box: Box) -> ClosedRange<Int> {
        column(at: box.min.x + Stage.edge)...column(at: box.max.x - Stage.edge)
    }

    private func rows(of box: Box) -> ClosedRange<Int> {
        row(at: box.min.y + Stage.edge)...row(at: box.max.y - Stage.edge)
    }

    /// Any solid tile or extra under the box. One-way platforms don't count.
    public func overlapsSolid(_ box: Box) -> Bool {
        for row in rows(of: box) {
            for column in columns(of: box) where tile(column: column, row: row) == .solid {
                return true
            }
        }
        return extras.contains { $0.overlaps(box) }
    }

    private func spansY(_ extra: Box, _ box: Box) -> Bool {
        extra.min.y < box.max.y - Stage.edge && extra.max.y > box.min.y + Stage.edge
    }

    private func spansX(_ extra: Box, _ box: Box) -> Bool {
        extra.min.x < box.max.x - Stage.edge && extra.max.x > box.min.x + Stage.edge
    }

    /// Slides the box sideways by `dx`, stopping at the first solid. Returns how far it got
    /// and which side stopped it.
    public func sweepHorizontally(_ box: Box, by dx: Double) -> (moved: Double, blocked: Facing?) {
        guard dx != 0 else { return (0, nil) }
        let direction: Facing = dx > 0 ? .right : .left
        let leading = direction == .right ? box.max.x : box.min.x
        let target = leading + dx
        let from = column(at: direction == .right ? leading + Stage.edge : leading - Stage.edge)
        let to = column(at: direction == .right ? target - Stage.edge : target + Stage.edge)
        let span = from <= to ? Array(from...to) : Array((to...from).reversed())
        var moved = dx
        var blocked: Facing?
        for column in span {
            var hit = false
            for row in rows(of: box) where tile(column: column, row: row) == .solid {
                hit = true
                break
            }
            if hit {
                let wall = direction == .right ? Double(column) * Stage.tileSize : Double(column + 1) * Stage.tileSize
                moved = wall - leading
                blocked = direction
                break
            }
        }
        for extra in extras where spansY(extra, box) {
            if direction == .right, extra.min.x >= leading - Stage.edge, extra.min.x - leading < moved {
                moved = max(extra.min.x - leading, 0)
                blocked = direction
            } else if direction == .left, extra.max.x <= leading + Stage.edge, extra.max.x - leading > moved {
                moved = min(extra.max.x - leading, 0)
                blocked = direction
            }
        }
        return (moved, blocked)
    }

    /// Drops or lifts the box by `dy`. Falling stops on solids and on the top of one-way
    /// platforms the feet were above; rising stops under solids.
    public func sweepVertically(_ box: Box, by dy: Double) -> (moved: Double, landed: Bool, ceiling: Bool) {
        guard dy != 0 else { return (0, false, false) }
        if dy < 0 {
            let feet = box.min.y
            let target = feet + dy
            let from = row(at: feet - Stage.edge)
            let to = row(at: target + Stage.edge)
            var moved = dy
            var landed = false
            search: for row in stride(from: from, through: to, by: -1) {
                let top = Double(row + 1) * Stage.tileSize
                for column in columns(of: box) {
                    switch tile(column: column, row: row) {
                    case .solid:
                        moved = top - feet
                        landed = true
                        break search
                    case .oneWay where feet >= top - Stage.edge:
                        moved = top - feet
                        landed = true
                        break search
                    default:
                        continue
                    }
                }
            }
            for extra in extras where spansX(extra, box) && extra.max.y <= feet + Stage.edge && extra.max.y - feet > moved {
                moved = min(extra.max.y - feet, 0)
                landed = true
            }
            return (moved, landed, false)
        } else {
            let head = box.max.y
            let target = head + dy
            let from = row(at: head + Stage.edge)
            let to = row(at: target - Stage.edge)
            var moved = dy
            var ceiling = false
            search: for row in from...max(from, to) {
                let bottom = Double(row) * Stage.tileSize
                for column in columns(of: box) where tile(column: column, row: row) == .solid {
                    moved = bottom - head
                    ceiling = true
                    break search
                }
            }
            for extra in extras where spansX(extra, box) && extra.min.y >= head - Stage.edge && extra.min.y - head < moved {
                moved = max(extra.min.y - head, 0)
                ceiling = true
            }
            return (moved, false, ceiling)
        }
    }

    /// Whether there is floor right under the feet.
    public func isGrounded(_ box: Box) -> Bool {
        let feet = box.min.y
        let row = row(at: feet - Stage.edge)
        let top = Double(row + 1) * Stage.tileSize
        for column in columns(of: box) {
            switch tile(column: column, row: row) {
            case .solid:
                return true
            case .oneWay where abs(feet - top) < 0.01:
                return true
            default:
                continue
            }
        }
        return extras.contains { spansX($0, box) && abs($0.max.y - feet) < 0.01 }
    }

    /// The smallest nudge, up first, then sideways, then down, that gets the box clear of
    /// solids, up to `reach`. Zero if it's already clear or nothing within reach works.
    public func pushOut(_ box: Box, reach: Double = 20) -> Vec2 {
        guard overlapsSolid(box) else { return .zero }
        var distance = 1.0
        while distance <= reach {
            for direction in [Vec2(x: 0, y: distance), Vec2(x: distance, y: 0), Vec2(x: -distance, y: 0), Vec2(x: 0, y: -distance)]
            where !overlapsSolid(box.offset(by: direction)) {
                return direction
            }
            distance += 1
        }
        return .zero
    }

    /// How far down from `y` to the top of the first floor under `x`, solid, one-way or extra.
    public func drop(fromX x: Double, y: Double) -> Double {
        var nearest = y
        let column = column(at: x)
        var row = row(at: y - Stage.edge)
        while row >= 0 {
            if tile(column: column, row: row) != .empty {
                nearest = y - Double(row + 1) * Stage.tileSize
                break
            }
            row -= 1
        }
        for extra in extras where extra.min.x <= x && x < extra.max.x && extra.max.y <= y + Stage.edge {
            nearest = min(nearest, y - extra.max.y)
        }
        return nearest
    }

    /// The side with a wall pressed against the box, if either. Only within the court's
    /// rows: the walls up in the sky can't be clung to or jumped off.
    public func wall(beside box: Box) -> Facing? {
        let rows = rows(of: box)
        let rightColumn = column(at: box.max.x + Stage.edge)
        let leftColumn = column(at: box.min.x - Stage.edge)
        for row in rows where row < self.rows {
            if tile(column: rightColumn, row: row) == .solid { return .right }
            if tile(column: leftColumn, row: row) == .solid { return .left }
        }
        for extra in extras where spansY(extra, box) {
            if abs(extra.min.x - box.max.x) < 0.01 { return .right }
            if abs(extra.max.x - box.min.x) < 0.01 { return .left }
        }
        return nil
    }

    /// The top corner of a floor or ledge tile within `reach` of the box's `side`, with
    /// its top in `top`, nothing beside it toward the box and nothing above either: what a
    /// hand can hang from. The nearest, if any. A corner may sit up to two units back
    /// inside the box's span. Only within the court's rows, and never a made platform.
    public func ledge(beside box: Box, side: Facing, reach: Double, top: ClosedRange<Double>) -> Vec2? {
        let near = side == .right ? box.max.x : box.min.x
        let far = near + side.sign * reach
        let back = near - side.sign * 2
        let columns = side == .right ? column(at: back)...column(at: far) : column(at: far)...column(at: back)
        let lowRow = Swift.max(row(at: top.lowerBound) - 1, 0)
        let highRow = Swift.min(row(at: top.upperBound), rows - 1)
        var best: Vec2?
        var bestDistance = Double.infinity
        for row in stride(from: lowRow, through: highRow, by: 1) {
            let tileTop = Double(row + 1) * Stage.tileSize
            guard top.contains(tileTop) else { continue }
            for column in columns where tile(column: column, row: row) != .empty {
                let toward = column - side.rawValue
                guard tile(column: toward, row: row) == .empty,
                      tile(column: column, row: row + 1) == .empty,
                      tile(column: toward, row: row + 1) == .empty else { continue }
                let face = side == .right ? Double(column) * Stage.tileSize : Double(column + 1) * Stage.tileSize
                let ahead = (face - near) * side.sign
                guard ahead >= -2, ahead <= reach, abs(ahead) < bestDistance else { continue }
                bestDistance = abs(ahead)
                best = Vec2(x: face, y: tileTop)
            }
        }
        return best
    }

    // MARK: The court

    /// 34 by 16 tiles with no ceiling: floor and walls, a backboard block each side, two cells
    /// in from the wall, with its rim on the inward face 70 units above the floor, and a
    /// one-way ledge in the middle. Player 0 starts left and scores on the right rim.
    public static let court: Stage = {
        var stage = Stage(
            columns: 34, rows: 16,
            hoops: [
                Hoop(position: Vec2(x: 58, y: 80), owner: 1, backboard: .left),
                Hoop(position: Vec2(x: 282, y: 80), owner: 0, backboard: .right),
            ],
            playerSpawns: [Vec2(x: 130, y: 10), Vec2(x: 210, y: 10)],
            playerFacings: [.right, .left],
            ballSpawn: Vec2(x: 170, y: 80)
        )
        stage.fill(.solid, columns: 0...33, rows: 0...0)
        stage.fill(.solid, columns: 0...0, rows: 0...15)
        stage.fill(.solid, columns: 33...33, rows: 0...15)
        stage.fill(.solid, columns: 3...4, rows: 7...8)
        stage.fill(.solid, columns: 29...30, rows: 7...8)
        stage.fill(.oneWay, columns: 15...18, rows: 3...3)
        return stage
    }()

    /// The football field: ten courts long and 20 rows high, flat and empty but for the
    /// floor and the end walls. The rims float between the goalposts' uprights, four tiles
    /// higher than the court's, six tiles in from each wall. Each player starts under the
    /// rim they guard, and the ball starts in someone's hands by the coin flip. Helmets
    /// sweep it and a portal hangs over it.
    /// The field's rims' height, on the BASKET Y slider offline until it's settled; both
    /// phones keep the default online.
    nonisolated(unsafe) public static var fieldRimHeight = 120.0

    public static var footballField: Stage {
        let columns = 340, rows = 20
        let width = Double(columns) * Stage.tileSize
        let inset = 60.0
        var stage = Stage(
            columns: columns, rows: rows,
            hoops: [
                Hoop(position: Vec2(x: inset, y: fieldRimHeight), owner: 1, backboard: .left),
                Hoop(position: Vec2(x: width - inset, y: fieldRimHeight), owner: 0, backboard: .right),
            ],
            playerSpawns: [Vec2(x: inset, y: 10), Vec2(x: width - inset, y: 10)],
            playerFacings: [.right, .left],
            ballSpawn: Vec2(x: width / 2, y: 80)
        )
        stage.fill(.solid, columns: 0...(columns - 1), rows: 0...0)
        stage.fill(.solid, columns: 0...0, rows: 0...(rows - 1))
        stage.fill(.solid, columns: (columns - 1)...(columns - 1), rows: 0...(rows - 1))
        stage.features = StageFeatures(helmets: true, portals: true, startsHeld: true)
        return stage
    }

    /// The stage being tuned; the court comes back with stage selection.
    public static var current: Stage { footballField }
}
