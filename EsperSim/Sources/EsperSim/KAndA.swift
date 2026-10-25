import Foundation

/// The car's collision, K&A's red car's and Anozira's: one shape laid wherever a car stands
/// (`Stage.layCar`), its picture 128 by 48 art pixels. Cells from the picture's bottom-left one:
/// the hood's two one-ways and the trunk's on the bottom row, the roof's three a row up between
/// the windshield's and the back window's one-way slopes; the windshield brought this far in
/// from the car's outline, onto the glass.
public enum CarRules {
    public static let oneWays: [(column: Int, row: Int)] = [(0, 0), (1, 0), (7, 0), (3, 1), (4, 1), (5, 1)]
    public static let windshield = (column: 2, row: 1)
    public static let backWindow = (column: 6, row: 1)
    public static let windshieldInset = 4 * 0.625
    public static let lastColumn = 7

    /// The shape as boxes and slopes off the grid, with the picture's bottom left at `origin`
    /// (units), for a car that moves (Anozira's): its one-way tops, and its two one-way slopes.
    /// Facing right, mirrored, as Anozira's is.
    public static func collision(at origin: Vec2, facesRight: Bool) -> (tops: [Box], slopes: [Slope]) {
        let size = Stage.tileSize
        func square(_ cell: (column: Int, row: Int), across shift: Double = 0) -> Box {
            let column = facesRight ? lastColumn - cell.column : cell.column
            let corner = origin + Vec2(x: Double(column) * size + shift, y: Double(cell.row) * size)
            return Box(min: corner, max: corner + Vec2(x: size, y: size))
        }
        let inset = facesRight ? -windshieldInset : windshieldInset
        return (oneWays.map { square($0) },
                [Slope(box: square(windshield, across: inset), rising: !facesRight, oneWay: true),
                 Slope(box: square(backWindow), rising: facesRight, oneWay: true)])
    }
}

/// K&A: a street under a railway bridge, drawn whole in Aseprite (`K&A_Map.aseprite`, 592 by
/// 304, one of its pixels an art pixel): 37 tiles by 19, three rows of ground, the bridge's
/// deck along the top. The hoops hang from the bridge's underside on the Wreck Center's support
/// beams, as far under it as those reach over that stage's rim. Played in every mode.
public enum KAndARules {
    public static let columns = 37
    public static let rows = 19
    public static let floorRows = 3
    /// The bridge's underside, up from the floor: the tracks' 39 rows down from the picture's top.
    public static let bridgeBottom = Double(304 - 39) * 0.625
    /// How far under the bridge a rim hangs on the court's supports' reach; the map's baked rim
    /// cells are where they were put in the map maker, and a rim goes where it's put.
    public static let rimUnderBridge = 25.0
    /// The red car: its picture 128 by 48 art pixels, its bottom left at the ground's top, 64
    /// along, as the file's [Dont_Draw] layer places it; its span, for who stands on it.
    public static let carLeft = 64.0 * 0.625
    public static let carRight = 192.0 * 0.625
    /// The three street lights hanging off the wire: their middles along (the leftmost a tile
    /// right of where it was first), and their bottoms up, a tile lower than they were drawn first.
    public static let lampXs: [Double] = [87.5 * 0.625, 295.5 * 0.625, 503.5 * 0.625]
    public static let lampBottom = 240.0 * 0.625
}
