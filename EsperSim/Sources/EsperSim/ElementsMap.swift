/// The Elements' map, laid out by hand: tiles from the elements tileset dropped on a grid,
/// and where the rims, the players and the ball start. The sim reads which cells are solid
/// and where the markers are; the view reads which piece of the tileset each cell is.
public struct ElementsMap: Equatable, Codable {
    public struct Cell: Equatable, Hashable, Codable {
        public var column: Int
        public var row: Int
        public init(_ column: Int, _ row: Int) { self.column = column; self.row = row }
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

    public init(tiles: [Placed], leftRim: Cell, rightRim: Cell, spawns: [Cell], ball: Cell) {
        self.tiles = tiles
        self.leftRim = leftRim
        self.rightRim = rightRim
        self.spawns = spawns
        self.ball = ball
    }

    /// The map every phone plays; the map maker's edits stand in for it offline only.
    public static let baked: ElementsMap = ElementsMap.defaultMap()
    nonisolated(unsafe) public static var current = baked

    /// Tileset cells that are only a fleck of art, such as the spikes over the big rock:
    /// drawn, but nothing to stand on or bump.
    public static let decoration: Set<Cell> = [Cell(2, 0), Cell(4, 0), Cell(5, 1)]

    public func isSolid(_ tile: Placed) -> Bool { !ElementsMap.decoration.contains(tile.art) }

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
        lines.append("        return ElementsMap(tiles: tiles, leftRim: \(cell(leftRim)), rightRim: \(cell(rightRim)),")
        lines.append("                           spawns: [\(spawns.map(cell).joined(separator: ", "))], ball: \(cell(ball)))")
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
    /// A first map to play on: two islands with a rock block each for a backboard, one over
    /// the middle, and steps between, all over the lava.
    private static func defaultMap() -> ElementsMap {
        var tiles: [Placed] = []
        func put(_ column: Int, _ row: Int, _ art: Cell) { tiles.append(Placed(Cell(column, row), art: art)) }
        /// A hanging island: a top row down to a point, `width` across.
        func island(left: Int, top: Int, width: Int) {
            put(left, top, Cell(7, 3))
            put(left + width - 1, top, Cell(13, 3))
            for offset in 1..<(width - 1) { put(left + offset, top, Cell(8 + (offset - 1) % 5, 3)) }
            put(left + 1, top - 1, Cell(8, 4))
            put(left + width - 2, top - 1, Cell(12, 4))
            for offset in 2..<(width - 2) { put(left + offset, top - 1, Cell(9 + (offset - 2) % 3, 4)) }
            let middle = left + width / 2
            put(middle - 1, top - 2, Cell(9, 5))
            put(middle, top - 2, Cell(10, 5))
            put(middle + 1, top - 2, Cell(11, 5))
        }
        /// A block of rock, `width` across and `height` tall, its top row and its bottom edge from the big rock.
        func rock(left: Int, bottom: Int, width: Int, height: Int) {
            for row in 0..<height {
                let artRow = row == height - 1 ? 2 : (row == 0 ? 4 : 3)
                for offset in 0..<width { put(left + offset, bottom + row, Cell(2 + offset % 3, artRow)) }
            }
        }
        // Laid out to mirror about the middle column, 33.
        island(left: 2, top: 9, width: 15)
        island(left: 50, top: 9, width: 15)
        island(left: 28, top: 14, width: 11)
        rock(left: 0, bottom: 15, width: 2, height: 5)
        rock(left: 65, bottom: 15, width: 2, height: 5)
        // Steps over the gap, and ledges high up.
        put(20, 11, Cell(6, 1)); put(21, 11, Cell(7, 1))
        put(45, 11, Cell(6, 1)); put(46, 11, Cell(7, 1))
        for offset in 0..<3 { put(12 + offset, 20, Cell(11 + offset, 1)); put(52 + offset, 20, Cell(11 + offset, 1)) }
        put(33, 23, Cell(9, 1))
        return ElementsMap(tiles: tiles, leftRim: Cell(2, 17), rightRim: Cell(64, 17),
                           spawns: [Cell(5, 10), Cell(61, 10)], ball: Cell(33, 18))
    }
}
