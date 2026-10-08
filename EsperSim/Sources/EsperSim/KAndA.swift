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
    public static let rimInset = 58.0
    /// How far under the bridge the rim hangs: the court's supports reach this far over its rim.
    public static let rimUnderBridge = 25.0
    public static var rimHeight: Double { bridgeBottom - rimUnderBridge }
    public static let startInsets = (150.0, 220.0)
    public static let ballHeight = 100.0
}
