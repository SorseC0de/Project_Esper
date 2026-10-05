/// The stages laid out by hand in the map maker.
public enum MapStage: String, CaseIterable, Codable {
    case elements, wetshot, flight

    /// Its size in tiles.
    public var columns: Int {
        switch self {
        case .elements: ElementsRules.columns
        case .wetshot: WetshotRules.columns
        case .flight: FlightRules.columns
        }
    }
    public var rows: Int {
        switch self {
        case .elements: ElementsRules.rows
        case .wetshot: WetshotRules.rows
        case .flight: FlightRules.rows
        }
    }
}

/// A stage's map, laid out by hand: tiles from a tileset dropped on a grid, props placed
/// whole, the walls painted apart from both, and where the rims, the players and the ball
/// start. The sim reads which cells are solid and where the markers are; the view reads
/// what's drawn where.
public struct StageMap: Equatable, Codable {
    public struct Cell: Equatable, Hashable, Codable {
        public var column: Int
        public var row: Int
        public init(_ column: Int, _ row: Int) { self.column = column; self.row = row }
    }

    /// What a wall cell is: a block, or a slope by where its solid half lies: the lower right
    /// (the surface rises to the right), the lower left (falls to the right), and the same
    /// two up under a ceiling; the two floor slopes again as slide slopes, which nobody
    /// stands or walks up on; and a one-way, stood on from above, passed through from below.
    public enum Kind: String, Codable, CaseIterable {
        case solid, lowerRight, lowerLeft, upperRight, upperLeft, slideLowerRight, slideLowerLeft, oneWay

        /// The same kind facing the other way, for the right side mirrored off the left.
        public var mirrored: Kind {
            switch self {
            case .solid: .solid
            case .lowerRight: .lowerLeft
            case .lowerLeft: .lowerRight
            case .upperRight: .upperLeft
            case .upperLeft: .upperRight
            case .slideLowerRight: .slideLowerLeft
            case .slideLowerLeft: .slideLowerRight
            case .oneWay: .oneWay
            }
        }
    }

    /// One cell of the walls: what bodies and the ball can't pass, kept apart from the art.
    public struct Wall: Equatable, Hashable, Codable {
        public var cell: Cell
        public var kind: Kind
        public init(_ cell: Cell, _ kind: Kind) { self.cell = cell; self.kind = kind }
    }

    /// A tile placed on the stage's grid, drawn as the tileset's cell `art`, on `layer`: 0 the
    /// ground, one to a cell, and 1 over it, drawn on top, such as a window on a wall.
    public struct Placed: Equatable, Hashable, Codable {
        public var cell: Cell
        public var art: Cell
        public var layer: Int
        public init(_ cell: Cell, art: Cell, layer: Int = 0) { self.cell = cell; self.art = art; self.layer = layer }

        private enum CodingKeys: String, CodingKey { case cell, art, layer }
        /// Tiles kept before there were layers are on the ground.
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            cell = try values.decode(Cell.self, forKey: .cell)
            art = try values.decode(Cell.self, forKey: .art)
            layer = try values.decodeIfPresent(Int.self, forKey: .layer) ?? 0
        }
    }
    /// The layers a cell can hold.
    public static let layers = 0...1

    /// A whole picture placed with its bottom left on a cell: Wetshot Wake's plants, rocks and
    /// its Hoopfish, which carries the stage's one rim.
    public enum PropKind: String, Codable, CaseIterable {
        case plant1, plant2, plant3, plant4, plant5, rock1, rock2, hoopfish

        /// Maps saved before the Hoopfish was renamed call it the hooperfish.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let kind = PropKind(rawValue: raw == "hooperfish" ? "hoopfish" : raw) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No prop \(raw)"))
            }
            self = kind
        }

        public var isPlant: Bool { [.plant1, .plant2, .plant3, .plant4, .plant5].contains(self) }

        /// Its size in art pixels.
        public var pixelSize: (width: Int, height: Int) {
            switch self {
            case .plant1: (16, 21)
            case .plant2: (24, 35)
            case .plant3: (28, 61)
            case .plant4: (42, 61)
            case .plant5: (80, 64)
            case .rock1, .rock2: (112, 112)
            case .hoopfish: (96, 48)
            }
        }
    }

    public struct Prop: Equatable, Hashable, Codable {
        public var kind: PropKind
        public var cell: Cell
        public init(_ kind: PropKind, at cell: Cell) { self.kind = kind; self.cell = cell }
    }

    /// A piece of Hoopfish Hideaway's pile of backboards and hoops in the background, the ones
    /// it's collected: placed anywhere, not on the grid, by its middle in art pixels, turned in degrees.
    public struct PilePiece: Equatable, Hashable, Codable {
        public enum Kind: String, Codable, CaseIterable {
            case backboard1, backboard2, backboard3, hoop1, hoop2, hoop3
            /// The atlas strip it's drawn from, and its frame there.
            public var sheet: String { [.backboard1, .backboard2, .backboard3].contains(self) ? "backboards" : "hoops" }
            public var frame: Int {
                switch self {
                case .backboard1, .hoop1: 0
                case .backboard2, .hoop2: 1
                case .backboard3, .hoop3: 2
                }
            }

            /// Pieces put down before the pile had its own sheets read as the nearest of these.
            public init(from decoder: Decoder) throws {
                let raw = try decoder.singleValueContainer().decode(String.self)
                let older = ["backboard": "backboard1", "backboardStraight": "backboard2", "hoop": "hoop1", "hoopStraight": "hoop2"]
                guard let kind = Kind(rawValue: older[raw] ?? raw) else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No pile piece \(raw)"))
                }
                self = kind
            }
        }
        public var kind: Kind
        public var x: Double
        public var y: Double
        public var rotation: Double
        public init(_ kind: Kind, x: Double, y: Double, rotation: Double = 0) {
            self.kind = kind
            self.x = x
            self.y = y
            self.rotation = rotation
        }
    }

    public var tiles: [Placed]
    public var props: [Prop]
    /// The background pile, drawn between the background and its foreground.
    public var pile: [PilePiece]
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

    public init(tiles: [Placed] = [], props: [Prop] = [], pile: [PilePiece] = [], leftRim: Cell, rightRim: Cell, spawns: [Cell], ball: Cell,
                tornados: [Cell] = [], walls: [Wall]? = nil) {
        self.tiles = tiles
        self.props = props
        self.pile = pile
        self.leftRim = leftRim
        self.rightRim = rightRim
        self.spawns = spawns
        self.ball = ball
        self.tornados = tornados
        self.walls = walls ?? StageMap.derivedWalls(from: tiles)
    }

    /// A block under every tile that isn't decoration, for a map with no walls of its own.
    public static func derivedWalls(from tiles: [Placed]) -> [Wall] {
        tiles.filter { $0.layer == 0 && !decoration.contains($0.art) }.map { Wall($0.cell, .solid) }
    }

    private enum CodingKeys: String, CodingKey { case tiles, props, pile, leftRim, rightRim, spawns, ball, tornados, walls }

    /// A map kept before tornados were in it reads as having none.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tiles = try values.decode([Placed].self, forKey: .tiles)
        props = try values.decodeIfPresent([Prop].self, forKey: .props) ?? []
        pile = try values.decodeIfPresent([PilePiece].self, forKey: .pile) ?? []
        leftRim = try values.decode(Cell.self, forKey: .leftRim)
        rightRim = try values.decode(Cell.self, forKey: .rightRim)
        spawns = try values.decode([Cell].self, forKey: .spawns)
        ball = try values.decode(Cell.self, forKey: .ball)
        tornados = try values.decodeIfPresent([Cell].self, forKey: .tornados) ?? []
        walls = try values.decodeIfPresent([Wall].self, forKey: .walls) ?? StageMap.derivedWalls(from: tiles)
    }

    /// Where a tornado's sprite lies, in tile cells: its three columns and three rows.
    public static func tornadoCells(_ base: Cell) -> (columns: ClosedRange<Int>, rows: ClosedRange<Int>) {
        ((base.column - 1)...(base.column + 1), base.row...(base.row + 2))
    }

    /// A base cell moved to where a whole tornado fits on the stage.
    public static func fittingTornado(_ cell: Cell) -> Cell {
        Cell(min(max(cell.column, 1), ElementsRules.columns - 2), min(max(cell.row, 0), ElementsRules.rows - 3))
    }

    /// The Hoopfish, if it's placed: the stage's one rim rides it.
    public var hoopfish: Prop? { props.first { $0.kind == .hoopfish } }

    /// Up by one whenever a new map is baked in below, so a map kept from before it, which
    /// would stand in for it offline, is put aside and the baked one shows.
    public static func bakedVersion(_ stage: MapStage) -> Int { stage == .flight ? 3 : 5 }

    /// The map every phone plays; the map maker's edits stand in for it offline only.
    public static func baked(_ stage: MapStage) -> StageMap {
        switch stage {
        case .elements: elementsBaked
        case .wetshot: wetshotBaked
        case .flight: flightBaked
        }
    }
    private static let elementsBaked: StageMap = StageMap.defaultMap()
    private static let wetshotBaked: StageMap = StageMap.wetshotDefaultMap()
    private static let flightBaked: StageMap = StageMap.flightDefaultMap()

    /// Flight, to start at 8x: a floor along the bottom, the rims five rows up near each end, the
    /// starts either side of the middle, the ball over it; no tiles, the backdrop being the art.
    private static func flightDefaultMap() -> StageMap {
        let floor = (0..<FlightRules.columns).map { Wall(Cell($0, 0), .solid) }
        return StageMap(leftRim: Cell(2, 5), rightRim: Cell(FlightRules.columns - 3, 5),
                        spawns: [Cell(7, 1), Cell(12, 1)], ball: Cell(10, 5), walls: floor)
    }

    /// The maps in play: each stage's baked one, or offline the map maker's.
    public struct Store {
        private var maps: [MapStage: StageMap] = [:]
        public subscript(stage: MapStage) -> StageMap {
            get { maps[stage] ?? StageMap.baked(stage) }
            set { maps[stage] = newValue }
        }
    }
    nonisolated(unsafe) public static var current = Store()

    /// Tileset cells that are only a fleck of art, such as the spikes over the big rock:
    /// drawn, but nothing to stand on or bump.
    public static let decoration: Set<Cell> = [Cell(2, 0), Cell(4, 0), Cell(5, 1)]

    public func isSolid(_ tile: Placed) -> Bool { !StageMap.decoration.contains(tile.art) }

    /// What the wall at a cell is, if it has one.
    public func wall(at cell: Cell) -> Kind? { walls.first { $0.cell == cell }?.kind }

    /// The map as Swift, for a stage's baked map to be pasted over.
    public func swiftSource(_ stage: MapStage) -> String {
        func cell(_ value: Cell) -> String { "Cell(\(value.column), \(value.row))" }
        let name = switch stage {
        case .elements: "defaultMap"
        case .wetshot: "wetshotDefaultMap"
        case .flight: "flightDefaultMap"
        }
        var lines = ["    private static func \(name)() -> StageMap {",
                     "        let tiles: [Placed] = ["]
        let ordered = tiles.sorted { ($0.layer, $0.cell.row, $0.cell.column) < ($1.layer, $1.cell.row, $1.cell.column) }
        var line = "           "
        for tile in ordered {
            let next = " Placed(\(cell(tile.cell)), art: \(cell(tile.art))\(tile.layer == 0 ? "" : ", layer: \(tile.layer)")),"
            if line.count + next.count > 118 { lines.append(line); line = "           " }
            line += next
        }
        lines.append(line)
        lines.append("        ]")
        lines.append("        let props: [Prop] = [")
        var propLine = "           "
        for prop in props.sorted(by: { ($0.cell.row, $0.cell.column, $0.kind.rawValue) < ($1.cell.row, $1.cell.column, $1.kind.rawValue) }) {
            let next = " Prop(.\(prop.kind.rawValue), at: \(cell(prop.cell))),"
            if propLine.count + next.count > 118 { lines.append(propLine); propLine = "           " }
            propLine += next
        }
        lines.append(propLine)
        lines.append("        ]")
        // Walls of their own only when they aren't the blocks under the tiles.
        let ownWalls = walls != StageMap.derivedWalls(from: tiles)
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
        lines.append("        return StageMap(tiles: tiles, props: props, leftRim: \(cell(leftRim)), rightRim: \(cell(rightRim)),")
        lines.append("                           spawns: [\(spawns.map(cell).joined(separator: ", "))], ball: \(cell(ball)),")
        lines.append("                           tornados: [\(tornados.map(cell).joined(separator: ", "))]\(ownWalls ? ", walls: walls)" : ")")")
        lines.append("    }")
        return lines.joined(separator: "\n")
    }

    /// The pile's pieces, one a line: kind, middle's x and y in art pixels, turn in degrees.
    public var pileSource: String {
        pile.map { "\($0.kind.rawValue) x \(Int($0.x.rounded())) y \(Int($0.y.rounded())) rot \(Int($0.rotation.rounded()))" }.joined(separator: "\n")
    }
}

/// The Elements' numbers: the size, and the lava along the bottom.
/// The Elements' tornados, in sim frames: up for three seconds, then bursting where they
/// stand, gone a second, and half a second rising back up out of the lava to their places;
/// every fourth to come up is fire, which burns whoever it touches. A regular one holds
/// whoever comes into it, and the ball, while it's up or rising: drawn to its middle a share
/// of the way a frame, the stick drifting a body sideways; jumped out of, it can't take them
/// again for a moment. Bursting, it has nothing to hold with. Blazing Boba is held by a fire
/// one as by a regular one.
public enum TornadoRules {
    public static let upFrames = 180
    /// The burst's ten frames at fifteen a second.
    public static let burstFrames = 40
    public static let burstSheetFramesPerSecond = 15
    public static let underFrames = 60
    public static let riseFrames = 30
    public static var cycleFrames: Int { upFrames + burstFrames + underFrames + riseFrames }
    public static let fireEvery = 4
    public static let pullShare = 0.15
    public static let jumpOutCooldownFrames = 30
    /// A body held in one drifts sideways at this share of the air's drift.
    public static let driftShare = 0.25
    /// Where a sunk tornado's bottom is, in units: under the lava's surface.
    public static let sunkBottom = -30.0

    /// Which rise it's on at `frame`: each counts from the start of its rise.
    public static func appearance(at frame: Int) -> Int { (frame + riseFrames) / cycleFrames }
    public static func isFire(at frame: Int) -> Bool { appearance(at: frame) % fireEvery == fireEvery - 1 }
    /// Up and holding, before it bursts.
    public static func isUp(at frame: Int) -> Bool { frame % cycleFrames < upFrames }
    /// Up, or rising back: it holds whoever and whatever it catches, and a fire one burns.
    public static func holds(at frame: Int) -> Bool {
        let time = frame % cycleFrames
        return time < upFrames || time >= upFrames + burstFrames + underFrames
    }
    /// Frames into its burst, if it's bursting.
    public static func burstFrame(at frame: Int) -> Int? {
        let time = frame % cycleFrames - upFrames
        return (0..<burstFrames).contains(time) ? time : nil
    }

    /// How far down from its place a tornado is at `frame`, from 0 up to 1 all the way sunk:
    /// in place up and bursting, sunk while it's gone, eased out rising.
    public static func sunkShare(at frame: Int) -> Double {
        let time = frame % cycleFrames
        if time < upFrames + burstFrames { return 0 }
        if time < upFrames + burstFrames + underFrames { return 1 }
        let share = Double(time - upFrames - burstFrames - underFrames) / Double(riseFrames)
        return (1 - share) * (1 - share)
    }
}

/// The Elements' fireball: every five seconds one rises out of the lava two tiles short of
/// the leftmost tornado and arcs through every tornado's middle to two tiles past the
/// rightmost, back under the lava, each pass the other way from the last. It strips whoever
/// it touches and bursts on them; Blazing Boba it only bursts on.
public enum StageFireballRules {
    public static let everyFrames = 300
    public static let travelFrames = 150
    public static let radius = 5.0
    /// Frames a body it strikes coasts on the knock before the stick has it again.
    public static let knockCoastFrames = 20
    /// Tiles out past the end tornados it rises and sets, and how far under the lava's surface.
    public static let reachPastTornados = 2.0
    public static let underLava = -10.0
}

/// The Elements' lightning: every ten seconds the sky flashes, and two seconds later a small
/// bolt strikes an open top of rock, picked by the flash's count, stripping whoever it
/// touches; Zeus Juice it doesn't touch.
public enum LightningRules {
    public static let everyFrames = 600
    public static let warningFrames = 120
    /// The bolt's reach either side of its line, in units.
    public static let halfWidth = 8.0
}

/// The Elements' icicles: sockets side by side along the ceiling, centred, but for the
/// ceiling's ends (`freeColumns` and under, and their mirror). Every two seconds one socket,
/// picked by the count, grows an icicle if it's empty, holds it two to five seconds, then
/// drops it: falling as the ball falls, it shatters on the first ground or the lava, and on
/// whoever it meets, whom it strips and freezes; Frost Tea it only shatters on.
public enum IcicleRules {
    /// A socket's width and height in units, and how far down from its top the grown icicle hangs.
    public static let socketWidth = 20.0
    public static let socketHeight = 30.0
    public static let hangLength = 16.25
    public static let freeColumns = 16
    public static let everyFrames = 120
    /// The grow's six frames at fifteen a second, then the hold.
    public static let formFrames = 24
    public static let holdFrames = 120...300
    /// The falling icicle's box: its tip at the bottom.
    public static let width = 5.0
    public static let length = 13.0

}

/// Flight: drawn for 8x, its backdrop 2496 by 1152 screen pixels, 312 by 144 art pixels: 19 and a
/// half tiles across, so 20 with a quarter either side of it, and 9 high. At 8x a 2532-pixel screen
/// shows all but a pixel and three quarters at each end.
public enum FlightRules {
    public static let columns = 20
    public static let rows = 9
}

/// Wetshot Wake: 37 by 19, under water, its one rim on the Hoopfish: the background's 17 rows a
/// row up off the floor's, with one of water over them.
public enum WetshotRules {
    public static let columns = 37
    public static let rows = 19
    /// The rim's centre from the Hoopfish's bottom left, in whole art pixels: `hoop_straight`
    /// sits on its leftmost 48 pixels, 10 up, and the rim is 5 left and 10 down of that art's
    /// middle (`HoopTuning.courtOffset`); 15 across, as tuned, and 24 up. Across is on the HOOP X slider
    /// while it's tuned, offline.
    nonisolated(unsafe) public static var rimPixelsAcross = 15
    public static let rimPixelsUp = 24
    /// Where the ball hangs on the antenna before it's taken, the same way, whole art pixels from
    /// the Hoopfish's bottom left: on the BALL X and BALL Y sliders while it's tuned, offline.
    nonisolated(unsafe) public static var ballPixelsAcross = 24
    nonisolated(unsafe) public static var ballPixelsUp = 24
    public static var rimFromHoopfish: Vec2 { Vec2(x: Double(rimPixelsAcross) / 1.6, y: Double(rimPixelsUp) / 1.6) }
}

public enum ElementsRules {
    /// Two Wreck Centers across, less a column so there's a middle one, and 24 high: a large stage's most, all of it on screen at 3x on a phone.
    public static let columns = 67
    public static let rows = 24
    /// The lava's surface, in units above the floor: anyone whose feet go under it burns.
    public static let lavaSurface = 25.0

    /// A count mixed into a number to pick by, the same on every phone: which spot lightning
    /// strikes, which socket grows an icicle.
    public static func pick(_ count: Int) -> UInt64 {
        var mixed = UInt64(truncatingIfNeeded: count + 1) &* 0x9E37_79B9_7F4A_7C15
        mixed ^= mixed >> 31
        mixed = mixed &* 0xBF58_476D_1CE4_E5B9
        mixed ^= mixed >> 29
        return mixed
    }
}

extension StageMap {
    /// The map as laid out by hand: the left side and the middle platform the ball starts on
    /// drawn, the right side its counterpart tile for tile, each tile the one opposite it in
    /// its piece of the tileset (a slope's left tile for its right), and the ceiling along the
    /// top. The middle platform is 11 across, columns 28 to 38, centred on the middle column.
    private static func defaultMap() -> StageMap {
        let tiles: [Placed] = [
            Placed(Cell(8, 7), art: Cell(9, 5)), Placed(Cell(9, 7), art: Cell(10, 5)),
            Placed(Cell(10, 7), art: Cell(11, 5)), Placed(Cell(56, 7), art: Cell(9, 5)),
            Placed(Cell(57, 7), art: Cell(10, 5)), Placed(Cell(58, 7), art: Cell(11, 5)),
            Placed(Cell(3, 8), art: Cell(9, 5)), Placed(Cell(4, 8), art: Cell(10, 5)),
            Placed(Cell(5, 8), art: Cell(2, 4)), Placed(Cell(6, 8), art: Cell(3, 4)),
            Placed(Cell(7, 8), art: Cell(4, 4)), Placed(Cell(8, 8), art: Cell(10, 4)),
            Placed(Cell(9, 8), art: Cell(11, 4)), Placed(Cell(10, 8), art: Cell(11, 4)),
            Placed(Cell(11, 8), art: Cell(4, 4)), Placed(Cell(12, 8), art: Cell(10, 5)),
            Placed(Cell(13, 8), art: Cell(10, 5)), Placed(Cell(14, 8), art: Cell(11, 5)),
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
            Placed(Cell(14, 9), art: Cell(12, 3)), Placed(Cell(15, 9), art: Cell(13, 3)),
            Placed(Cell(51, 9), art: Cell(7, 3)), Placed(Cell(52, 9), art: Cell(8, 3)),
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
            Placed(Cell(16, 13), art: Cell(2, 4)), Placed(Cell(17, 13), art: Cell(3, 4)),
            Placed(Cell(18, 13), art: Cell(4, 4)), Placed(Cell(19, 13), art: Cell(9, 4)),
            Placed(Cell(20, 13), art: Cell(3, 3)), Placed(Cell(21, 13), art: Cell(2, 3)),
            Placed(Cell(22, 13), art: Cell(3, 3)), Placed(Cell(23, 13), art: Cell(5, 3)),
            Placed(Cell(29, 13), art: Cell(8, 4)), Placed(Cell(30, 13), art: Cell(10, 5)),
            Placed(Cell(31, 13), art: Cell(4, 4)), Placed(Cell(32, 13), art: Cell(9, 4)),
            Placed(Cell(33, 13), art: Cell(3, 3)), Placed(Cell(34, 13), art: Cell(11, 4)),
            Placed(Cell(35, 13), art: Cell(2, 4)), Placed(Cell(36, 13), art: Cell(10, 5)),
            Placed(Cell(37, 13), art: Cell(12, 4)), Placed(Cell(43, 13), art: Cell(1, 3)),
            Placed(Cell(44, 13), art: Cell(3, 3)), Placed(Cell(45, 13), art: Cell(4, 3)),
            Placed(Cell(46, 13), art: Cell(3, 3)), Placed(Cell(47, 13), art: Cell(11, 4)),
            Placed(Cell(48, 13), art: Cell(2, 4)), Placed(Cell(49, 13), art: Cell(3, 4)),
            Placed(Cell(50, 13), art: Cell(4, 4)), Placed(Cell(51, 13), art: Cell(11, 5)),
            Placed(Cell(14, 14), art: Cell(8, 4)), Placed(Cell(15, 14), art: Cell(9, 4)),
            Placed(Cell(16, 14), art: Cell(2, 3)), Placed(Cell(17, 14), art: Cell(3, 3)),
            Placed(Cell(18, 14), art: Cell(6, 6)), Placed(Cell(19, 14), art: Cell(3, 1)),
            Placed(Cell(20, 14), art: Cell(3, 1)), Placed(Cell(21, 14), art: Cell(3, 1)),
            Placed(Cell(22, 14), art: Cell(3, 1)), Placed(Cell(23, 14), art: Cell(4, 1)),
            Placed(Cell(28, 14), art: Cell(7, 3)), Placed(Cell(29, 14), art: Cell(8, 3)),
            Placed(Cell(30, 14), art: Cell(9, 3)), Placed(Cell(31, 14), art: Cell(10, 3)),
            Placed(Cell(32, 14), art: Cell(11, 3)), Placed(Cell(33, 14), art: Cell(12, 3)),
            Placed(Cell(34, 14), art: Cell(9, 3)), Placed(Cell(35, 14), art: Cell(10, 3)),
            Placed(Cell(36, 14), art: Cell(11, 3)), Placed(Cell(37, 14), art: Cell(12, 3)),
            Placed(Cell(38, 14), art: Cell(13, 3)), Placed(Cell(43, 14), art: Cell(2, 1)),
            Placed(Cell(44, 14), art: Cell(3, 1)), Placed(Cell(45, 14), art: Cell(3, 1)),
            Placed(Cell(46, 14), art: Cell(3, 1)), Placed(Cell(47, 14), art: Cell(3, 1)),
            Placed(Cell(48, 14), art: Cell(7, 6)), Placed(Cell(49, 14), art: Cell(3, 3)),
            Placed(Cell(50, 14), art: Cell(4, 3)), Placed(Cell(51, 14), art: Cell(11, 4)),
            Placed(Cell(52, 14), art: Cell(12, 4)), Placed(Cell(0, 15), art: Cell(11, 5)),
            Placed(Cell(13, 15), art: Cell(8, 4)), Placed(Cell(14, 15), art: Cell(9, 4)),
            Placed(Cell(15, 15), art: Cell(3, 3)), Placed(Cell(16, 15), art: Cell(3, 3)),
            Placed(Cell(17, 15), art: Cell(4, 2)), Placed(Cell(18, 15), art: Cell(6, 5)),
            Placed(Cell(21, 15), art: Cell(5, 1)), Placed(Cell(23, 15), art: Cell(4, 0)),
            Placed(Cell(33, 15), art: Cell(5, 1)), Placed(Cell(43, 15), art: Cell(2, 0)),
            Placed(Cell(45, 15), art: Cell(5, 1)), Placed(Cell(48, 15), art: Cell(7, 5)),
            Placed(Cell(49, 15), art: Cell(2, 2)), Placed(Cell(50, 15), art: Cell(3, 3)),
            Placed(Cell(51, 15), art: Cell(3, 3)), Placed(Cell(52, 15), art: Cell(11, 4)),
            Placed(Cell(53, 15), art: Cell(12, 4)), Placed(Cell(66, 15), art: Cell(9, 5)),
            Placed(Cell(0, 16), art: Cell(11, 4)), Placed(Cell(1, 16), art: Cell(5, 4)),
            Placed(Cell(12, 16), art: Cell(8, 4)), Placed(Cell(13, 16), art: Cell(9, 4)),
            Placed(Cell(14, 16), art: Cell(3, 3)), Placed(Cell(15, 16), art: Cell(3, 3)),
            Placed(Cell(16, 16), art: Cell(4, 2)), Placed(Cell(17, 16), art: Cell(6, 5)),
            Placed(Cell(49, 16), art: Cell(7, 5)), Placed(Cell(50, 16), art: Cell(2, 2)),
            Placed(Cell(51, 16), art: Cell(3, 3)), Placed(Cell(52, 16), art: Cell(3, 3)),
            Placed(Cell(53, 16), art: Cell(11, 4)), Placed(Cell(54, 16), art: Cell(12, 4)),
            Placed(Cell(65, 16), art: Cell(1, 4)), Placed(Cell(66, 16), art: Cell(9, 4)),
            Placed(Cell(0, 17), art: Cell(4, 3)), Placed(Cell(1, 17), art: Cell(5, 3)),
            Placed(Cell(11, 17), art: Cell(9, 5)), Placed(Cell(12, 17), art: Cell(9, 4)),
            Placed(Cell(13, 17), art: Cell(3, 3)), Placed(Cell(14, 17), art: Cell(3, 3)),
            Placed(Cell(15, 17), art: Cell(4, 2)), Placed(Cell(16, 17), art: Cell(6, 5)),
            Placed(Cell(50, 17), art: Cell(7, 5)), Placed(Cell(51, 17), art: Cell(2, 2)),
            Placed(Cell(52, 17), art: Cell(3, 3)), Placed(Cell(53, 17), art: Cell(3, 3)),
            Placed(Cell(54, 17), art: Cell(11, 4)), Placed(Cell(55, 17), art: Cell(11, 5)),
            Placed(Cell(65, 17), art: Cell(1, 3)), Placed(Cell(66, 17), art: Cell(2, 3)),
            Placed(Cell(0, 18), art: Cell(2, 3)), Placed(Cell(1, 18), art: Cell(5, 3)),
            Placed(Cell(10, 18), art: Cell(8, 4)), Placed(Cell(11, 18), art: Cell(9, 4)),
            Placed(Cell(12, 18), art: Cell(3, 3)), Placed(Cell(13, 18), art: Cell(3, 2)),
            Placed(Cell(14, 18), art: Cell(4, 2)), Placed(Cell(15, 18), art: Cell(6, 5)),
            Placed(Cell(51, 18), art: Cell(7, 5)), Placed(Cell(52, 18), art: Cell(2, 2)),
            Placed(Cell(53, 18), art: Cell(3, 2)), Placed(Cell(54, 18), art: Cell(3, 3)),
            Placed(Cell(55, 18), art: Cell(11, 4)), Placed(Cell(56, 18), art: Cell(12, 4)),
            Placed(Cell(65, 18), art: Cell(1, 3)), Placed(Cell(66, 18), art: Cell(4, 3)),
            Placed(Cell(0, 19), art: Cell(3, 3)), Placed(Cell(1, 19), art: Cell(11, 4)),
            Placed(Cell(2, 19), art: Cell(11, 5)), Placed(Cell(9, 19), art: Cell(9, 5)),
            Placed(Cell(10, 19), art: Cell(9, 4)), Placed(Cell(11, 19), art: Cell(3, 3)),
            Placed(Cell(12, 19), art: Cell(3, 3)), Placed(Cell(13, 19), art: Cell(4, 2)),
            Placed(Cell(14, 19), art: Cell(6, 5)), Placed(Cell(52, 19), art: Cell(7, 5)),
            Placed(Cell(53, 19), art: Cell(2, 2)), Placed(Cell(54, 19), art: Cell(3, 3)),
            Placed(Cell(55, 19), art: Cell(3, 3)), Placed(Cell(56, 19), art: Cell(11, 4)),
            Placed(Cell(57, 19), art: Cell(11, 5)), Placed(Cell(64, 19), art: Cell(9, 5)),
            Placed(Cell(65, 19), art: Cell(9, 4)), Placed(Cell(66, 19), art: Cell(3, 3)),
            Placed(Cell(0, 20), art: Cell(3, 3)), Placed(Cell(1, 20), art: Cell(3, 2)),
            Placed(Cell(2, 20), art: Cell(11, 4)), Placed(Cell(3, 20), art: Cell(10, 5)),
            Placed(Cell(4, 20), art: Cell(2, 4)), Placed(Cell(5, 20), art: Cell(3, 4)),
            Placed(Cell(6, 20), art: Cell(4, 4)), Placed(Cell(7, 20), art: Cell(2, 4)),
            Placed(Cell(8, 20), art: Cell(4, 4)), Placed(Cell(9, 20), art: Cell(9, 4)),
            Placed(Cell(10, 20), art: Cell(2, 3)), Placed(Cell(11, 20), art: Cell(3, 3)),
            Placed(Cell(12, 20), art: Cell(4, 2)), Placed(Cell(13, 20), art: Cell(6, 5)),
            Placed(Cell(53, 20), art: Cell(7, 5)), Placed(Cell(54, 20), art: Cell(2, 2)),
            Placed(Cell(55, 20), art: Cell(3, 3)), Placed(Cell(56, 20), art: Cell(4, 3)),
            Placed(Cell(57, 20), art: Cell(11, 4)), Placed(Cell(58, 20), art: Cell(2, 4)),
            Placed(Cell(59, 20), art: Cell(4, 4)), Placed(Cell(60, 20), art: Cell(2, 4)),
            Placed(Cell(61, 20), art: Cell(3, 4)), Placed(Cell(62, 20), art: Cell(4, 4)),
            Placed(Cell(63, 20), art: Cell(10, 5)), Placed(Cell(64, 20), art: Cell(9, 4)),
            Placed(Cell(65, 20), art: Cell(3, 2)), Placed(Cell(66, 20), art: Cell(3, 3)),
            Placed(Cell(0, 21), art: Cell(3, 3)), Placed(Cell(1, 21), art: Cell(3, 3)),
            Placed(Cell(2, 21), art: Cell(3, 3)), Placed(Cell(3, 21), art: Cell(3, 3)),
            Placed(Cell(4, 21), art: Cell(3, 3)), Placed(Cell(5, 21), art: Cell(3, 3)),
            Placed(Cell(6, 21), art: Cell(3, 3)), Placed(Cell(7, 21), art: Cell(3, 3)),
            Placed(Cell(8, 21), art: Cell(3, 3)), Placed(Cell(9, 21), art: Cell(3, 3)),
            Placed(Cell(10, 21), art: Cell(3, 3)), Placed(Cell(11, 21), art: Cell(4, 2)),
            Placed(Cell(12, 21), art: Cell(6, 5)), Placed(Cell(54, 21), art: Cell(7, 5)),
            Placed(Cell(55, 21), art: Cell(2, 2)), Placed(Cell(56, 21), art: Cell(3, 3)),
            Placed(Cell(57, 21), art: Cell(3, 3)), Placed(Cell(58, 21), art: Cell(3, 3)),
            Placed(Cell(59, 21), art: Cell(3, 3)), Placed(Cell(60, 21), art: Cell(3, 3)),
            Placed(Cell(61, 21), art: Cell(3, 3)), Placed(Cell(62, 21), art: Cell(3, 3)),
            Placed(Cell(63, 21), art: Cell(3, 3)), Placed(Cell(64, 21), art: Cell(3, 3)),
            Placed(Cell(65, 21), art: Cell(3, 3)), Placed(Cell(66, 21), art: Cell(3, 3)),
            Placed(Cell(0, 22), art: Cell(3, 3)), Placed(Cell(1, 22), art: Cell(3, 3)),
            Placed(Cell(2, 22), art: Cell(3, 3)), Placed(Cell(3, 22), art: Cell(3, 3)),
            Placed(Cell(4, 22), art: Cell(3, 3)), Placed(Cell(5, 22), art: Cell(3, 3)),
            Placed(Cell(6, 22), art: Cell(3, 3)), Placed(Cell(7, 22), art: Cell(3, 3)),
            Placed(Cell(8, 22), art: Cell(3, 3)), Placed(Cell(9, 22), art: Cell(3, 3)),
            Placed(Cell(10, 22), art: Cell(3, 3)), Placed(Cell(11, 22), art: Cell(5, 3)),
            Placed(Cell(55, 22), art: Cell(1, 3)), Placed(Cell(56, 22), art: Cell(3, 3)),
            Placed(Cell(57, 22), art: Cell(3, 3)), Placed(Cell(58, 22), art: Cell(3, 3)),
            Placed(Cell(59, 22), art: Cell(3, 3)), Placed(Cell(60, 22), art: Cell(3, 3)),
            Placed(Cell(61, 22), art: Cell(3, 3)), Placed(Cell(62, 22), art: Cell(3, 3)),
            Placed(Cell(63, 22), art: Cell(3, 3)), Placed(Cell(64, 22), art: Cell(3, 3)),
            Placed(Cell(65, 22), art: Cell(3, 3)), Placed(Cell(66, 22), art: Cell(3, 3)),
            Placed(Cell(0, 23), art: Cell(3, 3)), Placed(Cell(1, 23), art: Cell(3, 3)),
            Placed(Cell(2, 23), art: Cell(3, 3)), Placed(Cell(3, 23), art: Cell(3, 3)),
            Placed(Cell(4, 23), art: Cell(3, 3)), Placed(Cell(5, 23), art: Cell(3, 3)),
            Placed(Cell(6, 23), art: Cell(3, 3)), Placed(Cell(7, 23), art: Cell(3, 3)),
            Placed(Cell(8, 23), art: Cell(3, 3)), Placed(Cell(9, 23), art: Cell(3, 3)),
            Placed(Cell(10, 23), art: Cell(3, 3)), Placed(Cell(11, 23), art: Cell(5, 3)),
            Placed(Cell(15, 23), art: Cell(9, 5)), Placed(Cell(16, 23), art: Cell(2, 4)),
            Placed(Cell(17, 23), art: Cell(3, 4)), Placed(Cell(18, 23), art: Cell(2, 4)),
            Placed(Cell(19, 23), art: Cell(3, 4)), Placed(Cell(20, 23), art: Cell(4, 4)),
            Placed(Cell(21, 23), art: Cell(2, 4)), Placed(Cell(22, 23), art: Cell(3, 4)),
            Placed(Cell(23, 23), art: Cell(4, 4)), Placed(Cell(24, 23), art: Cell(2, 4)),
            Placed(Cell(25, 23), art: Cell(3, 4)), Placed(Cell(26, 23), art: Cell(4, 4)),
            Placed(Cell(27, 23), art: Cell(2, 4)), Placed(Cell(28, 23), art: Cell(3, 4)),
            Placed(Cell(29, 23), art: Cell(4, 4)), Placed(Cell(30, 23), art: Cell(2, 4)),
            Placed(Cell(31, 23), art: Cell(3, 4)), Placed(Cell(32, 23), art: Cell(4, 4)),
            Placed(Cell(33, 23), art: Cell(2, 4)), Placed(Cell(34, 23), art: Cell(2, 4)),
            Placed(Cell(35, 23), art: Cell(3, 4)), Placed(Cell(36, 23), art: Cell(4, 4)),
            Placed(Cell(37, 23), art: Cell(2, 4)), Placed(Cell(38, 23), art: Cell(3, 4)),
            Placed(Cell(39, 23), art: Cell(4, 4)), Placed(Cell(40, 23), art: Cell(2, 4)),
            Placed(Cell(41, 23), art: Cell(3, 4)), Placed(Cell(42, 23), art: Cell(4, 4)),
            Placed(Cell(43, 23), art: Cell(2, 4)), Placed(Cell(44, 23), art: Cell(3, 4)),
            Placed(Cell(45, 23), art: Cell(4, 4)), Placed(Cell(46, 23), art: Cell(2, 4)),
            Placed(Cell(47, 23), art: Cell(3, 4)), Placed(Cell(48, 23), art: Cell(4, 4)),
            Placed(Cell(49, 23), art: Cell(3, 4)), Placed(Cell(50, 23), art: Cell(4, 4)),
            Placed(Cell(51, 23), art: Cell(11, 5)), Placed(Cell(55, 23), art: Cell(1, 3)),
            Placed(Cell(56, 23), art: Cell(3, 3)), Placed(Cell(57, 23), art: Cell(3, 3)),
            Placed(Cell(58, 23), art: Cell(3, 3)), Placed(Cell(59, 23), art: Cell(3, 3)),
            Placed(Cell(60, 23), art: Cell(3, 3)), Placed(Cell(61, 23), art: Cell(3, 3)),
            Placed(Cell(62, 23), art: Cell(3, 3)), Placed(Cell(63, 23), art: Cell(3, 3)),
            Placed(Cell(64, 23), art: Cell(3, 3)), Placed(Cell(65, 23), art: Cell(3, 3)),
            Placed(Cell(66, 23), art: Cell(3, 3)),
        ]
        let walls: [Wall] = [
            Wall(Cell(8, 7), .upperRight), Wall(Cell(9, 7), .solid), Wall(Cell(10, 7), .upperLeft),
            Wall(Cell(56, 7), .upperRight), Wall(Cell(57, 7), .solid), Wall(Cell(58, 7), .upperLeft),
            Wall(Cell(3, 8), .upperRight), Wall(Cell(4, 8), .solid), Wall(Cell(5, 8), .solid),
            Wall(Cell(6, 8), .solid), Wall(Cell(7, 8), .solid), Wall(Cell(8, 8), .solid), Wall(Cell(9, 8), .solid),
            Wall(Cell(10, 8), .solid), Wall(Cell(11, 8), .solid), Wall(Cell(12, 8), .solid),
            Wall(Cell(13, 8), .solid), Wall(Cell(14, 8), .upperLeft), Wall(Cell(52, 8), .upperRight),
            Wall(Cell(53, 8), .solid), Wall(Cell(54, 8), .solid), Wall(Cell(55, 8), .solid),
            Wall(Cell(56, 8), .solid), Wall(Cell(57, 8), .solid), Wall(Cell(58, 8), .solid),
            Wall(Cell(59, 8), .solid), Wall(Cell(60, 8), .solid), Wall(Cell(61, 8), .solid),
            Wall(Cell(62, 8), .solid), Wall(Cell(63, 8), .upperLeft), Wall(Cell(2, 9), .upperRight),
            Wall(Cell(3, 9), .solid), Wall(Cell(4, 9), .solid), Wall(Cell(5, 9), .solid), Wall(Cell(6, 9), .solid),
            Wall(Cell(7, 9), .solid), Wall(Cell(8, 9), .solid), Wall(Cell(9, 9), .solid), Wall(Cell(10, 9), .solid),
            Wall(Cell(11, 9), .solid), Wall(Cell(12, 9), .solid), Wall(Cell(13, 9), .solid),
            Wall(Cell(14, 9), .solid), Wall(Cell(15, 9), .upperLeft), Wall(Cell(51, 9), .upperRight),
            Wall(Cell(52, 9), .solid), Wall(Cell(53, 9), .solid), Wall(Cell(54, 9), .solid),
            Wall(Cell(55, 9), .solid), Wall(Cell(56, 9), .solid), Wall(Cell(57, 9), .solid),
            Wall(Cell(58, 9), .solid), Wall(Cell(59, 9), .solid), Wall(Cell(60, 9), .solid),
            Wall(Cell(61, 9), .solid), Wall(Cell(62, 9), .solid), Wall(Cell(63, 9), .solid),
            Wall(Cell(64, 9), .upperLeft), Wall(Cell(21, 10), .upperRight), Wall(Cell(22, 10), .solid),
            Wall(Cell(23, 10), .upperLeft), Wall(Cell(43, 10), .upperRight), Wall(Cell(44, 10), .solid),
            Wall(Cell(45, 10), .upperLeft), Wall(Cell(20, 11), .upperRight), Wall(Cell(21, 11), .solid),
            Wall(Cell(22, 11), .solid), Wall(Cell(23, 11), .solid), Wall(Cell(43, 11), .solid),
            Wall(Cell(44, 11), .solid), Wall(Cell(45, 11), .solid), Wall(Cell(46, 11), .upperLeft),
            Wall(Cell(19, 12), .upperRight), Wall(Cell(20, 12), .solid), Wall(Cell(21, 12), .solid),
            Wall(Cell(22, 12), .solid), Wall(Cell(23, 12), .solid), Wall(Cell(32, 12), .upperRight),
            Wall(Cell(33, 12), .solid), Wall(Cell(34, 12), .upperLeft), Wall(Cell(43, 12), .solid),
            Wall(Cell(44, 12), .solid), Wall(Cell(45, 12), .solid), Wall(Cell(46, 12), .solid),
            Wall(Cell(47, 12), .upperLeft), Wall(Cell(15, 13), .upperRight), Wall(Cell(16, 13), .solid),
            Wall(Cell(17, 13), .solid), Wall(Cell(18, 13), .solid), Wall(Cell(19, 13), .solid),
            Wall(Cell(20, 13), .solid), Wall(Cell(21, 13), .solid), Wall(Cell(22, 13), .solid),
            Wall(Cell(23, 13), .solid), Wall(Cell(29, 13), .upperRight), Wall(Cell(30, 13), .solid),
            Wall(Cell(31, 13), .solid), Wall(Cell(32, 13), .solid), Wall(Cell(33, 13), .solid),
            Wall(Cell(34, 13), .solid), Wall(Cell(35, 13), .solid), Wall(Cell(36, 13), .solid),
            Wall(Cell(37, 13), .upperLeft), Wall(Cell(43, 13), .solid), Wall(Cell(44, 13), .solid),
            Wall(Cell(45, 13), .solid), Wall(Cell(46, 13), .solid), Wall(Cell(47, 13), .solid),
            Wall(Cell(48, 13), .solid), Wall(Cell(49, 13), .solid), Wall(Cell(50, 13), .solid),
            Wall(Cell(51, 13), .upperLeft), Wall(Cell(14, 14), .upperRight), Wall(Cell(15, 14), .solid),
            Wall(Cell(16, 14), .solid), Wall(Cell(17, 14), .solid), Wall(Cell(18, 14), .solid),
            Wall(Cell(19, 14), .solid), Wall(Cell(20, 14), .solid), Wall(Cell(21, 14), .solid),
            Wall(Cell(22, 14), .solid), Wall(Cell(23, 14), .solid), Wall(Cell(28, 14), .upperRight),
            Wall(Cell(29, 14), .solid), Wall(Cell(30, 14), .solid), Wall(Cell(31, 14), .solid),
            Wall(Cell(32, 14), .solid), Wall(Cell(33, 14), .solid), Wall(Cell(34, 14), .solid),
            Wall(Cell(35, 14), .solid), Wall(Cell(36, 14), .solid), Wall(Cell(37, 14), .solid),
            Wall(Cell(38, 14), .upperLeft), Wall(Cell(43, 14), .solid), Wall(Cell(44, 14), .solid),
            Wall(Cell(45, 14), .solid), Wall(Cell(46, 14), .solid), Wall(Cell(47, 14), .solid),
            Wall(Cell(48, 14), .solid), Wall(Cell(49, 14), .solid), Wall(Cell(50, 14), .solid),
            Wall(Cell(51, 14), .solid), Wall(Cell(52, 14), .upperLeft), Wall(Cell(0, 15), .upperLeft),
            Wall(Cell(13, 15), .upperRight), Wall(Cell(14, 15), .solid), Wall(Cell(15, 15), .solid),
            Wall(Cell(16, 15), .solid), Wall(Cell(17, 15), .solid), Wall(Cell(18, 15), .slideLowerLeft),
            Wall(Cell(48, 15), .slideLowerRight), Wall(Cell(49, 15), .solid), Wall(Cell(50, 15), .solid),
            Wall(Cell(51, 15), .solid), Wall(Cell(52, 15), .solid), Wall(Cell(53, 15), .upperLeft),
            Wall(Cell(66, 15), .upperRight), Wall(Cell(0, 16), .solid), Wall(Cell(1, 16), .upperLeft),
            Wall(Cell(12, 16), .upperRight), Wall(Cell(13, 16), .solid), Wall(Cell(14, 16), .solid),
            Wall(Cell(15, 16), .solid), Wall(Cell(16, 16), .solid), Wall(Cell(17, 16), .slideLowerLeft),
            Wall(Cell(49, 16), .slideLowerRight), Wall(Cell(50, 16), .solid), Wall(Cell(51, 16), .solid),
            Wall(Cell(52, 16), .solid), Wall(Cell(53, 16), .solid), Wall(Cell(54, 16), .upperLeft),
            Wall(Cell(65, 16), .upperRight), Wall(Cell(66, 16), .solid), Wall(Cell(0, 17), .solid),
            Wall(Cell(1, 17), .solid), Wall(Cell(11, 17), .upperRight), Wall(Cell(12, 17), .solid),
            Wall(Cell(13, 17), .solid), Wall(Cell(14, 17), .solid), Wall(Cell(15, 17), .solid),
            Wall(Cell(16, 17), .slideLowerLeft), Wall(Cell(50, 17), .slideLowerRight), Wall(Cell(51, 17), .solid),
            Wall(Cell(52, 17), .solid), Wall(Cell(53, 17), .solid), Wall(Cell(54, 17), .solid),
            Wall(Cell(55, 17), .upperLeft), Wall(Cell(65, 17), .solid), Wall(Cell(66, 17), .solid),
            Wall(Cell(0, 18), .solid), Wall(Cell(1, 18), .solid), Wall(Cell(10, 18), .upperRight),
            Wall(Cell(11, 18), .solid), Wall(Cell(12, 18), .solid), Wall(Cell(13, 18), .solid),
            Wall(Cell(14, 18), .solid), Wall(Cell(15, 18), .slideLowerLeft), Wall(Cell(51, 18), .slideLowerRight),
            Wall(Cell(52, 18), .solid), Wall(Cell(53, 18), .solid), Wall(Cell(54, 18), .solid),
            Wall(Cell(55, 18), .solid), Wall(Cell(56, 18), .upperLeft), Wall(Cell(65, 18), .solid),
            Wall(Cell(66, 18), .solid), Wall(Cell(0, 19), .solid), Wall(Cell(1, 19), .solid),
            Wall(Cell(2, 19), .upperLeft), Wall(Cell(9, 19), .upperRight), Wall(Cell(10, 19), .solid),
            Wall(Cell(11, 19), .solid), Wall(Cell(12, 19), .solid), Wall(Cell(13, 19), .solid),
            Wall(Cell(14, 19), .slideLowerLeft), Wall(Cell(52, 19), .slideLowerRight), Wall(Cell(53, 19), .solid),
            Wall(Cell(54, 19), .solid), Wall(Cell(55, 19), .solid), Wall(Cell(56, 19), .solid),
            Wall(Cell(57, 19), .upperLeft), Wall(Cell(64, 19), .upperRight), Wall(Cell(65, 19), .solid),
            Wall(Cell(66, 19), .solid), Wall(Cell(0, 20), .solid), Wall(Cell(1, 20), .solid),
            Wall(Cell(2, 20), .solid), Wall(Cell(3, 20), .solid), Wall(Cell(4, 20), .solid),
            Wall(Cell(5, 20), .solid), Wall(Cell(6, 20), .solid), Wall(Cell(7, 20), .solid),
            Wall(Cell(8, 20), .solid), Wall(Cell(9, 20), .solid), Wall(Cell(10, 20), .solid),
            Wall(Cell(11, 20), .solid), Wall(Cell(12, 20), .solid), Wall(Cell(13, 20), .slideLowerLeft),
            Wall(Cell(53, 20), .slideLowerRight), Wall(Cell(54, 20), .solid), Wall(Cell(55, 20), .solid),
            Wall(Cell(56, 20), .solid), Wall(Cell(57, 20), .solid), Wall(Cell(58, 20), .solid),
            Wall(Cell(59, 20), .solid), Wall(Cell(60, 20), .solid), Wall(Cell(61, 20), .solid),
            Wall(Cell(62, 20), .solid), Wall(Cell(63, 20), .solid), Wall(Cell(64, 20), .solid),
            Wall(Cell(65, 20), .solid), Wall(Cell(66, 20), .solid), Wall(Cell(0, 21), .solid),
            Wall(Cell(1, 21), .solid), Wall(Cell(2, 21), .solid), Wall(Cell(3, 21), .solid),
            Wall(Cell(4, 21), .solid), Wall(Cell(5, 21), .solid), Wall(Cell(6, 21), .solid),
            Wall(Cell(7, 21), .solid), Wall(Cell(8, 21), .solid), Wall(Cell(9, 21), .solid),
            Wall(Cell(10, 21), .solid), Wall(Cell(11, 21), .solid), Wall(Cell(12, 21), .slideLowerLeft),
            Wall(Cell(54, 21), .slideLowerRight), Wall(Cell(55, 21), .solid), Wall(Cell(56, 21), .solid),
            Wall(Cell(57, 21), .solid), Wall(Cell(58, 21), .solid), Wall(Cell(59, 21), .solid),
            Wall(Cell(60, 21), .solid), Wall(Cell(61, 21), .solid), Wall(Cell(62, 21), .solid),
            Wall(Cell(63, 21), .solid), Wall(Cell(64, 21), .solid), Wall(Cell(65, 21), .solid),
            Wall(Cell(66, 21), .solid), Wall(Cell(0, 22), .solid), Wall(Cell(1, 22), .solid),
            Wall(Cell(2, 22), .solid), Wall(Cell(3, 22), .solid), Wall(Cell(4, 22), .solid),
            Wall(Cell(5, 22), .solid), Wall(Cell(6, 22), .solid), Wall(Cell(7, 22), .solid),
            Wall(Cell(8, 22), .solid), Wall(Cell(9, 22), .solid), Wall(Cell(10, 22), .solid),
            Wall(Cell(11, 22), .solid), Wall(Cell(55, 22), .solid), Wall(Cell(56, 22), .solid),
            Wall(Cell(57, 22), .solid), Wall(Cell(58, 22), .solid), Wall(Cell(59, 22), .solid),
            Wall(Cell(60, 22), .solid), Wall(Cell(61, 22), .solid), Wall(Cell(62, 22), .solid),
            Wall(Cell(63, 22), .solid), Wall(Cell(64, 22), .solid), Wall(Cell(65, 22), .solid),
            Wall(Cell(66, 22), .solid), Wall(Cell(0, 23), .solid), Wall(Cell(1, 23), .solid),
            Wall(Cell(2, 23), .solid), Wall(Cell(3, 23), .solid), Wall(Cell(4, 23), .solid),
            Wall(Cell(5, 23), .solid), Wall(Cell(6, 23), .solid), Wall(Cell(7, 23), .solid),
            Wall(Cell(8, 23), .solid), Wall(Cell(9, 23), .solid), Wall(Cell(10, 23), .solid),
            Wall(Cell(11, 23), .solid), Wall(Cell(15, 23), .solid), Wall(Cell(16, 23), .solid),
            Wall(Cell(17, 23), .solid), Wall(Cell(18, 23), .solid), Wall(Cell(19, 23), .solid),
            Wall(Cell(20, 23), .solid), Wall(Cell(21, 23), .solid), Wall(Cell(22, 23), .solid),
            Wall(Cell(23, 23), .solid), Wall(Cell(24, 23), .solid), Wall(Cell(25, 23), .solid),
            Wall(Cell(26, 23), .solid), Wall(Cell(27, 23), .solid), Wall(Cell(28, 23), .solid),
            Wall(Cell(29, 23), .solid), Wall(Cell(30, 23), .solid), Wall(Cell(31, 23), .solid),
            Wall(Cell(32, 23), .solid), Wall(Cell(33, 23), .solid), Wall(Cell(34, 23), .solid),
            Wall(Cell(35, 23), .solid), Wall(Cell(36, 23), .solid), Wall(Cell(37, 23), .solid),
            Wall(Cell(38, 23), .solid), Wall(Cell(39, 23), .solid), Wall(Cell(40, 23), .solid),
            Wall(Cell(41, 23), .solid), Wall(Cell(42, 23), .solid), Wall(Cell(43, 23), .solid),
            Wall(Cell(44, 23), .solid), Wall(Cell(45, 23), .solid), Wall(Cell(46, 23), .solid),
            Wall(Cell(47, 23), .solid), Wall(Cell(48, 23), .solid), Wall(Cell(49, 23), .solid),
            Wall(Cell(50, 23), .solid), Wall(Cell(51, 23), .solid), Wall(Cell(55, 23), .solid),
            Wall(Cell(56, 23), .solid), Wall(Cell(57, 23), .solid), Wall(Cell(58, 23), .solid),
            Wall(Cell(59, 23), .solid), Wall(Cell(60, 23), .solid), Wall(Cell(61, 23), .solid),
            Wall(Cell(62, 23), .solid), Wall(Cell(63, 23), .solid), Wall(Cell(64, 23), .solid),
            Wall(Cell(65, 23), .solid), Wall(Cell(66, 23), .solid),
        ]
        return StageMap(tiles: tiles, leftRim: Cell(2, 16), rightRim: Cell(64, 16),
                           spawns: [Cell(13, 29), Cell(53, 29)], ball: Cell(33, 18),
                           tornados: [Cell(26, 8), Cell(18, 5), Cell(40, 8), Cell(48, 5)], walls: walls)
    }
}

extension StageMap {
    /// Hoopfish Hideaway's map, laid out in the map maker: the floor along the bottom row, under the
    /// background, a one-way ledge either side, the plants and rocks, where the Hoopfish starts, and
    /// the pile of backboards and hoops behind it all, in the order they were put down.
    private static func wetshotDefaultMap() -> StageMap {
        let props: [Prop] = [
            Prop(.rock1, at: Cell(0, 1)), Prop(.plant3, at: Cell(4, 1)), Prop(.plant1, at: Cell(5, 1)),
            Prop(.plant1, at: Cell(13, 1)), Prop(.plant2, at: Cell(14, 1)), Prop(.plant5, at: Cell(25, 1)),
            Prop(.rock2, at: Cell(30, 1)), Prop(.plant4, at: Cell(34, 1)), Prop(.hoopfish, at: Cell(17, 11)),
        ]
        let pile: [PilePiece] = [
            .init(.backboard2, x: 340, y: 42, rotation: -115), .init(.backboard1, x: 320, y: 45, rotation: 22),
            .init(.hoop2, x: 356, y: 55, rotation: 0), .init(.backboard2, x: 174, y: 52, rotation: -68),
            .init(.backboard3, x: 122, y: 115, rotation: -108), .init(.backboard2, x: 198, y: 42, rotation: 66),
            .init(.backboard2, x: 149, y: 45, rotation: 45), .init(.hoop2, x: 266, y: 91, rotation: -63),
            .init(.backboard1, x: 267, y: 44, rotation: 0), .init(.hoop3, x: 278, y: 45, rotation: -126),
            .init(.backboard2, x: 259, y: 42, rotation: 0), .init(.hoop2, x: 176, y: 56, rotation: 0),
            .init(.hoop2, x: 549, y: 134, rotation: 26), .init(.backboard2, x: 564, y: 132, rotation: -70),
            .init(.hoop3, x: 254, y: 75, rotation: -135), .init(.backboard1, x: 215, y: 51, rotation: 25),
            .init(.backboard2, x: 118, y: 48, rotation: 26), .init(.backboard1, x: 440, y: 49, rotation: 0),
        ]
        let walls: [Wall] = (0..<WetshotRules.columns).map { Wall(Cell($0, 0), .solid) }
            + ((1...5).map { $0 } + (31...35).map { $0 }).map { Wall(Cell($0, 4), .oneWay) }
        return StageMap(props: props, pile: pile, leftRim: Cell(0, 0), rightRim: Cell(0, 0),
                        spawns: [Cell(3, 5), Cell(33, 5)], ball: Cell(18, 12), walls: walls)
    }
}
