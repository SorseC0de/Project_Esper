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

    public func offset(by d: Vec2) -> Box { Box(min: min + d, max: max + d) }
}

/// The court: a grid of tiles, row 0 at the bottom, plus the rims and where everyone starts.
public struct Stage: Equatable {
    public static let tileSize = 10.0

    public let columns: Int
    public let rows: Int
    public var tiles: [Tile]
    public var hoops: [Hoop]
    public var playerSpawns: [Vec2]
    public var playerFacings: [Facing]
    public var ballSpawn: Vec2

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

    public func tile(column: Int, row: Int) -> Tile {
        guard column >= 0, column < columns, row >= 0, row < rows else { return .solid }
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

    /// Any solid tile under the box. One-way platforms don't count.
    public func overlapsSolid(_ box: Box) -> Bool {
        for row in rows(of: box) {
            for column in columns(of: box) where tile(column: column, row: row) == .solid {
                return true
            }
        }
        return false
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
        for column in span {
            var hit = false
            for row in rows(of: box) where tile(column: column, row: row) == .solid {
                hit = true
                break
            }
            if hit {
                let wall = direction == .right ? Double(column) * Stage.tileSize : Double(column + 1) * Stage.tileSize
                return (wall - leading, direction)
            }
        }
        return (dx, nil)
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
            for row in stride(from: from, through: to, by: -1) {
                let top = Double(row + 1) * Stage.tileSize
                for column in columns(of: box) {
                    switch tile(column: column, row: row) {
                    case .solid:
                        return (top - feet, true, false)
                    case .oneWay where feet >= top - Stage.edge:
                        return (top - feet, true, false)
                    default:
                        continue
                    }
                }
            }
            return (dy, false, false)
        } else {
            let head = box.max.y
            let target = head + dy
            let from = row(at: head + Stage.edge)
            let to = row(at: target - Stage.edge)
            for row in from...max(from, to) {
                let bottom = Double(row) * Stage.tileSize
                for column in columns(of: box) where tile(column: column, row: row) == .solid {
                    return (bottom - head, false, true)
                }
            }
            return (dy, false, false)
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
        return false
    }

    /// The side with a wall pressed against the box, if either.
    public func wall(beside box: Box) -> Facing? {
        let rows = rows(of: box)
        let rightColumn = column(at: box.max.x + Stage.edge)
        let leftColumn = column(at: box.min.x - Stage.edge)
        for row in rows {
            if tile(column: rightColumn, row: row) == .solid { return .right }
            if tile(column: leftColumn, row: row) == .solid { return .left }
        }
        return nil
    }

    // MARK: The court

    /// 30 by 14 tiles, not quite two Final Destinations wide: floor, walls and ceiling, a
    /// backboard block each side with its rim on the inward face, and a one-way ledge in the
    /// middle. Player 0 starts left and scores on the right rim.
    public static let court: Stage = {
        var stage = Stage(
            columns: 30, rows: 14,
            hoops: [
                Hoop(position: Vec2(x: 48, y: 50), owner: 1, backboard: .left),
                Hoop(position: Vec2(x: 252, y: 50), owner: 0, backboard: .right),
            ],
            playerSpawns: [Vec2(x: 110, y: 10), Vec2(x: 190, y: 10)],
            playerFacings: [.right, .left],
            ballSpawn: Vec2(x: 150, y: 70)
        )
        stage.fill(.solid, columns: 0...29, rows: 0...0)
        stage.fill(.solid, columns: 0...29, rows: 13...13)
        stage.fill(.solid, columns: 0...0, rows: 0...13)
        stage.fill(.solid, columns: 29...29, rows: 0...13)
        stage.fill(.solid, columns: 2...3, rows: 4...5)
        stage.fill(.solid, columns: 26...27, rows: 4...5)
        stage.fill(.oneWay, columns: 13...16, rows: 3...3)
        return stage
    }()
}
