/// The Elements' map, laid out by hand: tiles from the elements tileset dropped on a grid,
/// and where the rims, the players and the ball start. The sim reads which cells are solid
/// and where the markers are; the view reads which piece of the tileset each cell is.
public struct ElementsMap: Equatable, Codable {
    public struct Cell: Equatable, Hashable, Codable {
        public var column: Int
        public var row: Int
        public init(_ column: Int, _ row: Int) { self.column = column; self.row = row }
    }

    /// What a wall cell is: a block, or a slope by where its solid half lies: the lower right
    /// (the surface rises to the right), the lower left (falls to the right), and the same
    /// two up under a ceiling.
    public enum Kind: String, Codable, CaseIterable {
        case solid, lowerRight, lowerLeft, upperRight, upperLeft
    }

    /// One cell of the walls: what bodies and the ball can't pass, kept apart from the art.
    public struct Wall: Equatable, Hashable, Codable {
        public var cell: Cell
        public var kind: Kind
        public init(_ cell: Cell, _ kind: Kind) { self.cell = cell; self.kind = kind }
    }

    /// A tile placed on the stage's grid, drawn as the tileset's cell `art`.
    public struct Placed: Equatable, Hashable, Codable {
        public var cell: Cell
        public var art: Cell
        public init(_ cell: Cell, art: Cell) { self.cell = cell; self.art = art }
    }

    public var tiles: [Placed]
    /// The rim with its backboard on the left, and the one with it on the right.
    public var leftRim: Cell
    public var rightRim: Cell
    /// Where each player starts: the cell their feet stand at the bottom of.
    public var spawns: [Cell]
    public var ball: Cell
    /// The tornados, each a whole 48 by 48 sprite three tiles across and three high, given
    /// by the cell its base's middle is in: it fills the columns either side and the two rows above.
    public var tornados: [Cell]
    /// The walls, painted in the map maker's walls mode; by default a block under every solid tile.
    public var walls: [Wall]

    public init(tiles: [Placed], leftRim: Cell, rightRim: Cell, spawns: [Cell], ball: Cell, tornados: [Cell] = [], walls: [Wall]? = nil) {
        self.tiles = tiles
        self.leftRim = leftRim
        self.rightRim = rightRim
        self.spawns = spawns
        self.ball = ball
        self.tornados = tornados
        self.walls = walls ?? ElementsMap.derivedWalls(from: tiles)
    }

    /// A block under every tile that isn't decoration, for a map with no walls of its own.
    public static func derivedWalls(from tiles: [Placed]) -> [Wall] {
        tiles.filter { !decoration.contains($0.art) }.map { Wall($0.cell, .solid) }
    }

    private enum CodingKeys: String, CodingKey { case tiles, leftRim, rightRim, spawns, ball, tornados, walls }

    /// A map kept before tornados were in it reads as having none.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tiles = try values.decode([Placed].self, forKey: .tiles)
        leftRim = try values.decode(Cell.self, forKey: .leftRim)
        rightRim = try values.decode(Cell.self, forKey: .rightRim)
        spawns = try values.decode([Cell].self, forKey: .spawns)
        ball = try values.decode(Cell.self, forKey: .ball)
        tornados = try values.decodeIfPresent([Cell].self, forKey: .tornados) ?? []
        walls = try values.decodeIfPresent([Wall].self, forKey: .walls) ?? ElementsMap.derivedWalls(from: tiles)
    }

    /// Where a tornado's sprite lies, in tile cells: its three columns and three rows.
    public static func tornadoCells(_ base: Cell) -> (columns: ClosedRange<Int>, rows: ClosedRange<Int>) {
        ((base.column - 1)...(base.column + 1), base.row...(base.row + 2))
    }

    /// A base cell moved to where a whole tornado fits on the stage.
    public static func fittingTornado(_ cell: Cell) -> Cell {
        Cell(min(max(cell.column, 1), ElementsRules.columns - 2), min(max(cell.row, 0), ElementsRules.rows - 3))
    }

    /// Up by one whenever a new map is baked in below, so a map kept from before it, which
    /// would stand in for it offline, is put aside and the baked one shows.
    public static let bakedVersion = 1

    /// The map every phone plays; the map maker's edits stand in for it offline only.
    public static let baked: ElementsMap = ElementsMap.defaultMap()
    nonisolated(unsafe) public static var current = baked

    /// Tileset cells that are only a fleck of art, such as the spikes over the big rock:
    /// drawn, but nothing to stand on or bump.
    public static let decoration: Set<Cell> = [Cell(2, 0), Cell(4, 0), Cell(5, 1)]

    public func isSolid(_ tile: Placed) -> Bool { !ElementsMap.decoration.contains(tile.art) }

    /// What the wall at a cell is, if it has one.
    public func wall(at cell: Cell) -> Kind? { walls.first { $0.cell == cell }?.kind }

    /// The map as Swift, for `ElementsMap.baked` to be pasted over.
    public var swiftSource: String {
        func cell(_ value: Cell) -> String { "Cell(\(value.column), \(value.row))" }
        var lines = ["    private static func defaultMap() -> ElementsMap {",
                     "        let tiles: [Placed] = ["]
        let ordered = tiles.sorted { ($0.cell.row, $0.cell.column) < ($1.cell.row, $1.cell.column) }
        var line = "           "
        for tile in ordered {
            let next = " Placed(\(cell(tile.cell)), art: \(cell(tile.art))),"
            if line.count + next.count > 118 { lines.append(line); line = "           " }
            line += next
        }
        lines.append(line)
        lines.append("        ]")
        // Walls of their own only when they aren't the blocks under the tiles.
        let ownWalls = walls != ElementsMap.derivedWalls(from: tiles)
        if ownWalls {
            lines.append("        let walls: [Wall] = [")
            var wallLine = "           "
            for wall in walls.sorted(by: { ($0.cell.row, $0.cell.column) < ($1.cell.row, $1.cell.column) }) {
                let next = " Wall(\(cell(wall.cell)), .\(wall.kind.rawValue)),"
                if wallLine.count + next.count > 118 { lines.append(wallLine); wallLine = "           " }
                wallLine += next
            }
            lines.append(wallLine)
            lines.append("        ]")
        }
        lines.append("        return ElementsMap(tiles: tiles, leftRim: \(cell(leftRim)), rightRim: \(cell(rightRim)),")
        lines.append("                           spawns: [\(spawns.map(cell).joined(separator: ", "))], ball: \(cell(ball)),")
        lines.append("                           tornados: [\(tornados.map(cell).joined(separator: ", "))]\(ownWalls ? ", walls: walls)" : ")")")
        lines.append("    }")
        return lines.joined(separator: "\n")
    }
}

/// The Elements' numbers: the size, and the lava along the bottom.
public enum ElementsRules {
    /// Two Wreck Centers across, less a column so there's a middle one, and two high.
    public static let columns = 67
    public static let rows = 32
    /// The lava's surface, in units above the floor: anyone whose feet go under it burns.
    public static let lavaSurface = 25.0
}

extension ElementsMap {
    /// The map as laid out by hand: the left side and the middle platform the ball starts on
    /// drawn, the right side its counterpart tile for tile, each tile the one opposite it in
    /// its piece of the tileset (a slope's left tile for its right), and the ceiling along the
    /// top. The middle platform is 11 across, columns 28 to 38, centred on the middle column.
    private static func defaultMap() -> ElementsMap {
        let tiles: [Placed] = [
            Placed(Cell(20, 5), art: Cell(6, 1)), Placed(Cell(21, 5), art: Cell(7, 1)),
            Placed(Cell(45, 5), art: Cell(6, 1)), Placed(Cell(46, 5), art: Cell(7, 1)),
            Placed(Cell(8, 7), art: Cell(9, 5)), Placed(Cell(9, 7), art: Cell(10, 5)),
            Placed(Cell(10, 7), art: Cell(11, 5)), Placed(Cell(56, 7), art: Cell(9, 5)),
            Placed(Cell(57, 7), art: Cell(10, 5)), Placed(Cell(58, 7), art: Cell(11, 5)),
            Placed(Cell(3, 8), art: Cell(9, 5)), Placed(Cell(4, 8), art: Cell(10, 5)),
            Placed(Cell(5, 8), art: Cell(2, 4)), Placed(Cell(6, 8), art: Cell(3, 4)),
            Placed(Cell(7, 8), art: Cell(4, 4)), Placed(Cell(8, 8), art: Cell(10, 4)),
            Placed(Cell(9, 8), art: Cell(11, 4)), Placed(Cell(10, 8), art: Cell(11, 4)),
            Placed(Cell(11, 8), art: Cell(4, 4)), Placed(Cell(12, 8), art: Cell(10, 5)),
            Placed(Cell(13, 8), art: Cell(10, 5)), Placed(Cell(14, 8), art: Cell(11, 5)),
            Placed(Cell(26, 8), art: Cell(6, 1)), Placed(Cell(27, 8), art: Cell(7, 1)),
            Placed(Cell(39, 8), art: Cell(6, 1)), Placed(Cell(40, 8), art: Cell(7, 1)),
            Placed(Cell(52, 8), art: Cell(9, 5)), Placed(Cell(53, 8), art: Cell(10, 5)),
            Placed(Cell(54, 8), art: Cell(10, 5)), Placed(Cell(55, 8), art: Cell(2, 4)),
            Placed(Cell(56, 8), art: Cell(9, 4)), Placed(Cell(57, 8), art: Cell(9, 4)),
            Placed(Cell(58, 8), art: Cell(10, 4)), Placed(Cell(59, 8), art: Cell(2, 4)),
            Placed(Cell(60, 8), art: Cell(3, 4)), Placed(Cell(61, 8), art: Cell(4, 4)),
            Placed(Cell(62, 8), art: Cell(10, 5)), Placed(Cell(63, 8), art: Cell(11, 5)),
            Placed(Cell(2, 9), art: Cell(7, 3)), Placed(Cell(3, 9), art: Cell(8, 3)),
            Placed(Cell(4, 9), art: Cell(9, 3)), Placed(Cell(5, 9), art: Cell(10, 3)),
            Placed(Cell(6, 9), art: Cell(11, 3)), Placed(Cell(7, 9), art: Cell(12, 3)),
            Placed(Cell(8, 9), art: Cell(8, 3)), Placed(Cell(9, 9), art: Cell(9, 3)),
            Placed(Cell(10, 9), art: Cell(10, 3)), Placed(Cell(11, 9), art: Cell(11, 3)),
            Placed(Cell(12, 9), art: Cell(12, 3)), Placed(Cell(13, 9), art: Cell(8, 3)),
            Placed(Cell(14, 9), art: Cell(9, 3)), Placed(Cell(15, 9), art: Cell(13, 3)),
            Placed(Cell(51, 9), art: Cell(7, 3)), Placed(Cell(52, 9), art: Cell(11, 3)),
            Placed(Cell(53, 9), art: Cell(12, 3)), Placed(Cell(54, 9), art: Cell(8, 3)),
            Placed(Cell(55, 9), art: Cell(9, 3)), Placed(Cell(56, 9), art: Cell(10, 3)),
            Placed(Cell(57, 9), art: Cell(11, 3)), Placed(Cell(58, 9), art: Cell(12, 3)),
            Placed(Cell(59, 9), art: Cell(8, 3)), Placed(Cell(60, 9), art: Cell(9, 3)),
            Placed(Cell(61, 9), art: Cell(10, 3)), Placed(Cell(62, 9), art: Cell(11, 3)),
            Placed(Cell(63, 9), art: Cell(12, 3)), Placed(Cell(64, 9), art: Cell(13, 3)),
            Placed(Cell(21, 10), art: Cell(9, 5)), Placed(Cell(22, 10), art: Cell(10, 5)),
            Placed(Cell(23, 10), art: Cell(5, 4)), Placed(Cell(43, 10), art: Cell(1, 4)),
            Placed(Cell(44, 10), art: Cell(10, 5)), Placed(Cell(45, 10), art: Cell(11, 5)),
            Placed(Cell(20, 11), art: Cell(8, 4)), Placed(Cell(21, 11), art: Cell(9, 4)),
            Placed(Cell(22, 11), art: Cell(3, 3)), Placed(Cell(23, 11), art: Cell(5, 3)),
            Placed(Cell(43, 11), art: Cell(1, 3)), Placed(Cell(44, 11), art: Cell(3, 3)),
            Placed(Cell(45, 11), art: Cell(11, 4)), Placed(Cell(46, 11), art: Cell(12, 4)),
            Placed(Cell(19, 12), art: Cell(8, 4)), Placed(Cell(20, 12), art: Cell(9, 4)),
            Placed(Cell(21, 12), art: Cell(3, 3)), Placed(Cell(22, 12), art: Cell(3, 2)),
            Placed(Cell(23, 12), art: Cell(5, 3)), Placed(Cell(32, 12), art: Cell(9, 5)),
            Placed(Cell(33, 12), art: Cell(10, 5)), Placed(Cell(34, 12), art: Cell(11, 5)),
            Placed(Cell(43, 12), art: Cell(1, 3)), Placed(Cell(44, 12), art: Cell(3, 2)),
            Placed(Cell(45, 12), art: Cell(3, 3)), Placed(Cell(46, 12), art: Cell(11, 4)),
            Placed(Cell(47, 12), art: Cell(12, 4)), Placed(Cell(15, 13), art: Cell(9, 5)),
            Placed(Cell(16, 13), art: Cell(10, 5)), Placed(Cell(17, 13), art: Cell(10, 5)),
            Placed(Cell(18, 13), art: Cell(10, 5)), Placed(Cell(19, 13), art: Cell(9, 4)),
            Placed(Cell(20, 13), art: Cell(3, 3)), Placed(Cell(21, 13), art: Cell(2, 3)),
            Placed(Cell(22, 13), art: Cell(3, 3)), Placed(Cell(23, 13), art: Cell(5, 3)),
            Placed(Cell(29, 13), art: Cell(8, 4)), Placed(Cell(30, 13), art: Cell(10, 5)),
            Placed(Cell(31, 13), art: Cell(4, 4)), Placed(Cell(32, 13), art: Cell(9, 4)),
            Placed(Cell(33, 13), art: Cell(3, 3)), Placed(Cell(34, 13), art: Cell(11, 4)),
            Placed(Cell(35, 13), art: Cell(3, 4)), Placed(Cell(36, 13), art: Cell(2, 4)),
            Placed(Cell(37, 13), art: Cell(12, 4)), Placed(Cell(43, 13), art: Cell(1, 3)),
            Placed(Cell(44, 13), art: Cell(3, 3)), Placed(Cell(45, 13), art: Cell(4, 3)),
            Placed(Cell(46, 13), art: Cell(3, 3)), Placed(Cell(47, 13), art: Cell(11, 4)),
            Placed(Cell(48, 13), art: Cell(10, 5)), Placed(Cell(49, 13), art: Cell(10, 5)),
            Placed(Cell(50, 13), art: Cell(10, 5)), Placed(Cell(51, 13), art: Cell(11, 5)),
            Placed(Cell(14, 14), art: Cell(8, 4)), Placed(Cell(15, 14), art: Cell(9, 4)),
            Placed(Cell(16, 14), art: Cell(2, 3)), Placed(Cell(17, 14), art: Cell(3, 3)),
            Placed(Cell(18, 14), art: Cell(3, 3)), Placed(Cell(19, 14), art: Cell(4, 2)),
            Placed(Cell(20, 14), art: Cell(3, 1)), Placed(Cell(21, 14), art: Cell(3, 1)),
            Placed(Cell(22, 14), art: Cell(3, 1)), Placed(Cell(23, 14), art: Cell(4, 1)),
            Placed(Cell(28, 14), art: Cell(7, 3)), Placed(Cell(29, 14), art: Cell(8, 3)),
            Placed(Cell(30, 14), art: Cell(9, 3)), Placed(Cell(31, 14), art: Cell(10, 3)),
            Placed(Cell(32, 14), art: Cell(11, 3)), Placed(Cell(33, 14), art: Cell(12, 3)),
            Placed(Cell(34, 14), art: Cell(8, 3)), Placed(Cell(35, 14), art: Cell(3, 1)),
            Placed(Cell(36, 14), art: Cell(3, 1)), Placed(Cell(37, 14), art: Cell(12, 3)),
            Placed(Cell(38, 14), art: Cell(13, 3)), Placed(Cell(43, 14), art: Cell(2, 1)),
            Placed(Cell(44, 14), art: Cell(3, 1)), Placed(Cell(45, 14), art: Cell(3, 1)),
            Placed(Cell(46, 14), art: Cell(3, 1)), Placed(Cell(47, 14), art: Cell(2, 2)),
            Placed(Cell(48, 14), art: Cell(3, 3)), Placed(Cell(49, 14), art: Cell(3, 3)),
            Placed(Cell(50, 14), art: Cell(4, 3)), Placed(Cell(51, 14), art: Cell(11, 4)),
            Placed(Cell(52, 14), art: Cell(12, 4)), Placed(Cell(0, 15), art: Cell(11, 5)),
            Placed(Cell(13, 15), art: Cell(8, 4)), Placed(Cell(14, 15), art: Cell(9, 4)),
            Placed(Cell(15, 15), art: Cell(3, 3)), Placed(Cell(16, 15), art: Cell(3, 3)),
            Placed(Cell(17, 15), art: Cell(3, 3)), Placed(Cell(18, 15), art: Cell(4, 2)),
            Placed(Cell(19, 15), art: Cell(6, 5)), Placed(Cell(21, 15), art: Cell(5, 1)),
            Placed(Cell(23, 15), art: Cell(4, 0)), Placed(Cell(33, 15), art: Cell(5, 1)),
            Placed(Cell(43, 15), art: Cell(2, 0)), Placed(Cell(45, 15), art: Cell(5, 1)),
            Placed(Cell(47, 15), art: Cell(7, 5)), Placed(Cell(48, 15), art: Cell(2, 2)),
            Placed(Cell(49, 15), art: Cell(3, 3)), Placed(Cell(50, 15), art: Cell(3, 3)),
            Placed(Cell(51, 15), art: Cell(3, 3)), Placed(Cell(52, 15), art: Cell(11, 4)),
            Placed(Cell(53, 15), art: Cell(12, 4)), Placed(Cell(66, 15), art: Cell(9, 5)),
            Placed(Cell(0, 16), art: Cell(11, 4)), Placed(Cell(1, 16), art: Cell(5, 4)),
            Placed(Cell(12, 16), art: Cell(8, 4)), Placed(Cell(13, 16), art: Cell(9, 4)),
            Placed(Cell(14, 16), art: Cell(3, 3)), Placed(Cell(15, 16), art: Cell(3, 3)),
            Placed(Cell(16, 16), art: Cell(3, 3)), Placed(Cell(17, 16), art: Cell(4, 2)),
            Placed(Cell(18, 16), art: Cell(6, 5)), Placed(Cell(48, 16), art: Cell(7, 5)),
            Placed(Cell(49, 16), art: Cell(2, 2)), Placed(Cell(50, 16), art: Cell(3, 3)),
            Placed(Cell(51, 16), art: Cell(3, 3)), Placed(Cell(52, 16), art: Cell(3, 3)),
            Placed(Cell(53, 16), art: Cell(11, 4)), Placed(Cell(54, 16), art: Cell(12, 4)),
            Placed(Cell(65, 16), art: Cell(1, 4)), Placed(Cell(66, 16), art: Cell(9, 4)),
            Placed(Cell(0, 17), art: Cell(4, 3)), Placed(Cell(1, 17), art: Cell(5, 3)),
            Placed(Cell(11, 17), art: Cell(9, 5)), Placed(Cell(12, 17), art: Cell(9, 4)),
            Placed(Cell(13, 17), art: Cell(3, 3)), Placed(Cell(14, 17), art: Cell(3, 3)),
            Placed(Cell(15, 17), art: Cell(3, 3)), Placed(Cell(16, 17), art: Cell(4, 2)),
            Placed(Cell(17, 17), art: Cell(6, 5)), Placed(Cell(49, 17), art: Cell(7, 5)),
            Placed(Cell(50, 17), art: Cell(2, 2)), Placed(Cell(51, 17), art: Cell(3, 3)),
            Placed(Cell(52, 17), art: Cell(3, 3)), Placed(Cell(53, 17), art: Cell(3, 3)),
            Placed(Cell(54, 17), art: Cell(11, 4)), Placed(Cell(55, 17), art: Cell(11, 5)),
            Placed(Cell(65, 17), art: Cell(1, 3)), Placed(Cell(66, 17), art: Cell(2, 3)),
            Placed(Cell(0, 18), art: Cell(2, 3)), Placed(Cell(1, 18), art: Cell(5, 3)),
            Placed(Cell(10, 18), art: Cell(8, 4)), Placed(Cell(11, 18), art: Cell(9, 4)),
            Placed(Cell(12, 18), art: Cell(3, 3)), Placed(Cell(13, 18), art: Cell(3, 3)),
            Placed(Cell(14, 18), art: Cell(3, 2)), Placed(Cell(15, 18), art: Cell(4, 2)),
            Placed(Cell(16, 18), art: Cell(6, 5)), Placed(Cell(50, 18), art: Cell(7, 5)),
            Placed(Cell(51, 18), art: Cell(2, 2)), Placed(Cell(52, 18), art: Cell(3, 2)),
            Placed(Cell(53, 18), art: Cell(3, 3)), Placed(Cell(54, 18), art: Cell(3, 3)),
            Placed(Cell(55, 18), art: Cell(11, 4)), Placed(Cell(56, 18), art: Cell(12, 4)),
            Placed(Cell(65, 18), art: Cell(1, 3)), Placed(Cell(66, 18), art: Cell(4, 3)),
            Placed(Cell(0, 19), art: Cell(3, 3)), Placed(Cell(1, 19), art: Cell(11, 4)),
            Placed(Cell(2, 19), art: Cell(11, 5)), Placed(Cell(9, 19), art: Cell(9, 5)),
            Placed(Cell(10, 19), art: Cell(9, 4)), Placed(Cell(11, 19), art: Cell(3, 3)),
            Placed(Cell(12, 19), art: Cell(3, 3)), Placed(Cell(13, 19), art: Cell(3, 3)),
            Placed(Cell(14, 19), art: Cell(4, 2)), Placed(Cell(15, 19), art: Cell(6, 5)),
            Placed(Cell(51, 19), art: Cell(7, 5)), Placed(Cell(52, 19), art: Cell(2, 2)),
            Placed(Cell(53, 19), art: Cell(3, 3)), Placed(Cell(54, 19), art: Cell(3, 3)),
            Placed(Cell(55, 19), art: Cell(3, 3)), Placed(Cell(56, 19), art: Cell(11, 4)),
            Placed(Cell(57, 19), art: Cell(11, 5)), Placed(Cell(64, 19), art: Cell(9, 5)),
            Placed(Cell(65, 19), art: Cell(9, 4)), Placed(Cell(66, 19), art: Cell(3, 3)),
            Placed(Cell(0, 20), art: Cell(3, 3)), Placed(Cell(1, 20), art: Cell(3, 2)),
            Placed(Cell(2, 20), art: Cell(11, 4)), Placed(Cell(3, 20), art: Cell(10, 5)),
            Placed(Cell(4, 20), art: Cell(2, 4)), Placed(Cell(5, 20), art: Cell(3, 4)),
            Placed(Cell(6, 20), art: Cell(4, 4)), Placed(Cell(7, 20), art: Cell(2, 4)),
            Placed(Cell(8, 20), art: Cell(10, 5)), Placed(Cell(9, 20), art: Cell(9, 4)),
            Placed(Cell(10, 20), art: Cell(2, 3)), Placed(Cell(11, 20), art: Cell(3, 3)),
            Placed(Cell(12, 20), art: Cell(3, 3)), Placed(Cell(13, 20), art: Cell(4, 2)),
            Placed(Cell(14, 20), art: Cell(6, 5)), Placed(Cell(52, 20), art: Cell(7, 5)),
            Placed(Cell(53, 20), art: Cell(2, 2)), Placed(Cell(54, 20), art: Cell(3, 3)),
            Placed(Cell(55, 20), art: Cell(3, 3)), Placed(Cell(56, 20), art: Cell(4, 3)),
            Placed(Cell(57, 20), art: Cell(11, 4)), Placed(Cell(58, 20), art: Cell(10, 5)),
            Placed(Cell(59, 20), art: Cell(4, 4)), Placed(Cell(60, 20), art: Cell(2, 4)),
            Placed(Cell(61, 20), art: Cell(3, 4)), Placed(Cell(62, 20), art: Cell(4, 4)),
            Placed(Cell(63, 20), art: Cell(10, 5)), Placed(Cell(64, 20), art: Cell(9, 4)),
            Placed(Cell(65, 20), art: Cell(3, 2)), Placed(Cell(66, 20), art: Cell(3, 3)),
            Placed(Cell(0, 21), art: Cell(3, 1)), Placed(Cell(1, 21), art: Cell(3, 1)),
            Placed(Cell(2, 21), art: Cell(3, 1)), Placed(Cell(3, 21), art: Cell(3, 1)),
            Placed(Cell(4, 21), art: Cell(3, 1)), Placed(Cell(5, 21), art: Cell(3, 1)),
            Placed(Cell(6, 21), art: Cell(3, 1)), Placed(Cell(7, 21), art: Cell(3, 1)),
            Placed(Cell(8, 21), art: Cell(3, 1)), Placed(Cell(9, 21), art: Cell(3, 1)),
            Placed(Cell(10, 21), art: Cell(3, 1)), Placed(Cell(11, 21), art: Cell(3, 1)),
            Placed(Cell(12, 21), art: Cell(3, 1)), Placed(Cell(13, 21), art: Cell(6, 5)),
            Placed(Cell(53, 21), art: Cell(7, 5)), Placed(Cell(54, 21), art: Cell(3, 1)),
            Placed(Cell(55, 21), art: Cell(3, 1)), Placed(Cell(56, 21), art: Cell(3, 1)),
            Placed(Cell(57, 21), art: Cell(3, 1)), Placed(Cell(58, 21), art: Cell(3, 1)),
            Placed(Cell(59, 21), art: Cell(3, 1)), Placed(Cell(60, 21), art: Cell(3, 1)),
            Placed(Cell(61, 21), art: Cell(3, 1)), Placed(Cell(62, 21), art: Cell(3, 1)),
            Placed(Cell(63, 21), art: Cell(3, 1)), Placed(Cell(64, 21), art: Cell(3, 1)),
            Placed(Cell(65, 21), art: Cell(3, 1)), Placed(Cell(66, 21), art: Cell(3, 1)),
            Placed(Cell(0, 22), art: Cell(5, 1)), Placed(Cell(4, 22), art: Cell(2, 0)),
            Placed(Cell(10, 22), art: Cell(5, 1)), Placed(Cell(56, 22), art: Cell(5, 1)),
            Placed(Cell(62, 22), art: Cell(4, 0)), Placed(Cell(66, 22), art: Cell(5, 1)),
            Placed(Cell(12, 25), art: Cell(11, 1)), Placed(Cell(13, 25), art: Cell(12, 1)),
            Placed(Cell(14, 25), art: Cell(13, 1)), Placed(Cell(52, 25), art: Cell(11, 1)),
            Placed(Cell(53, 25), art: Cell(12, 1)), Placed(Cell(54, 25), art: Cell(13, 1)),
            Placed(Cell(0, 31), art: Cell(2, 4)), Placed(Cell(1, 31), art: Cell(3, 4)),
            Placed(Cell(2, 31), art: Cell(4, 4)), Placed(Cell(3, 31), art: Cell(2, 4)),
            Placed(Cell(4, 31), art: Cell(3, 4)), Placed(Cell(5, 31), art: Cell(4, 4)),
            Placed(Cell(6, 31), art: Cell(2, 4)), Placed(Cell(7, 31), art: Cell(3, 4)),
            Placed(Cell(8, 31), art: Cell(4, 4)), Placed(Cell(9, 31), art: Cell(2, 4)),
            Placed(Cell(10, 31), art: Cell(3, 4)), Placed(Cell(11, 31), art: Cell(4, 4)),
            Placed(Cell(12, 31), art: Cell(2, 4)), Placed(Cell(13, 31), art: Cell(3, 4)),
            Placed(Cell(14, 31), art: Cell(4, 4)), Placed(Cell(15, 31), art: Cell(2, 4)),
            Placed(Cell(16, 31), art: Cell(3, 4)), Placed(Cell(17, 31), art: Cell(4, 4)),
            Placed(Cell(18, 31), art: Cell(2, 4)), Placed(Cell(19, 31), art: Cell(3, 4)),
            Placed(Cell(20, 31), art: Cell(4, 4)), Placed(Cell(21, 31), art: Cell(2, 4)),
            Placed(Cell(22, 31), art: Cell(3, 4)), Placed(Cell(23, 31), art: Cell(4, 4)),
            Placed(Cell(24, 31), art: Cell(2, 4)), Placed(Cell(25, 31), art: Cell(3, 4)),
            Placed(Cell(26, 31), art: Cell(4, 4)), Placed(Cell(27, 31), art: Cell(2, 4)),
            Placed(Cell(28, 31), art: Cell(3, 4)), Placed(Cell(29, 31), art: Cell(4, 4)),
            Placed(Cell(30, 31), art: Cell(2, 4)), Placed(Cell(31, 31), art: Cell(3, 4)),
            Placed(Cell(32, 31), art: Cell(4, 4)), Placed(Cell(33, 31), art: Cell(2, 4)),
            Placed(Cell(34, 31), art: Cell(3, 4)), Placed(Cell(35, 31), art: Cell(4, 4)),
            Placed(Cell(36, 31), art: Cell(2, 4)), Placed(Cell(37, 31), art: Cell(3, 4)),
            Placed(Cell(38, 31), art: Cell(4, 4)), Placed(Cell(39, 31), art: Cell(2, 4)),
            Placed(Cell(40, 31), art: Cell(3, 4)), Placed(Cell(41, 31), art: Cell(4, 4)),
            Placed(Cell(42, 31), art: Cell(2, 4)), Placed(Cell(43, 31), art: Cell(3, 4)),
            Placed(Cell(44, 31), art: Cell(4, 4)), Placed(Cell(45, 31), art: Cell(2, 4)),
            Placed(Cell(46, 31), art: Cell(3, 4)), Placed(Cell(47, 31), art: Cell(4, 4)),
            Placed(Cell(48, 31), art: Cell(2, 4)), Placed(Cell(49, 31), art: Cell(3, 4)),
            Placed(Cell(50, 31), art: Cell(4, 4)), Placed(Cell(51, 31), art: Cell(2, 4)),
            Placed(Cell(52, 31), art: Cell(3, 4)), Placed(Cell(53, 31), art: Cell(4, 4)),
            Placed(Cell(54, 31), art: Cell(2, 4)), Placed(Cell(55, 31), art: Cell(3, 4)),
            Placed(Cell(56, 31), art: Cell(4, 4)), Placed(Cell(57, 31), art: Cell(2, 4)),
            Placed(Cell(58, 31), art: Cell(3, 4)), Placed(Cell(59, 31), art: Cell(4, 4)),
            Placed(Cell(60, 31), art: Cell(2, 4)), Placed(Cell(61, 31), art: Cell(3, 4)),
            Placed(Cell(62, 31), art: Cell(4, 4)), Placed(Cell(63, 31), art: Cell(2, 4)),
            Placed(Cell(64, 31), art: Cell(3, 4)), Placed(Cell(65, 31), art: Cell(4, 4)),
            Placed(Cell(66, 31), art: Cell(2, 4)),
        ]
        return ElementsMap(tiles: tiles, leftRim: Cell(2, 16), rightRim: Cell(64, 16),
                           spawns: [Cell(13, 26), Cell(53, 26)], ball: Cell(33, 18),
                           tornados: [])
    }
}
