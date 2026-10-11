import Foundation

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
