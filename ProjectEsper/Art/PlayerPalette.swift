import Foundation

/// A colour as the sheets store it, 0xRRGGBB.
typealias RGB = UInt32

/// The figure's parts, one flat colour each on the sheets. Two of the parts are drawn in
/// two close shades across the sheets, so a part can own more than one source colour.
enum BodyPart: CaseIterable {
    case backHand, backArm, backLeg, backThigh
    case pelvis, torso, head
    case frontThigh, frontLeg, frontArm, frontHand

    /// What the sheets paint this part with, as the artist named the colours.
    var sourceColours: [RGB] {
        switch self {
        case .backHand: [0x951799, 0xAF1AB2, 0x94149C]   // purple
        case .backArm: [0xAC3232]                         // dark red
        case .backLeg: [0xCE5050]                         // red
        case .backThigh: [0xD95763]                       // red-orange
        case .pelvis: [0xC46423, 0xB35B20]                // dark orange
        case .torso: [0xDF7126, 0xDE7120]                 // orange
        case .head: [0x5FCDE4]                            // teal
        case .frontThigh: [0xD1CC60]                      // light yellow
        case .frontLeg: [0xFBF236]                        // yellow
        case .frontArm: [0x6ABE30]                        // lime
        case .frontHand: [0x99E550]                       // yellow-green
        }
    }

    var isBack: Bool {
        switch self {
        case .backHand, .backArm, .backLeg, .backThigh: true
        default: false
        }
    }
}

/// What each part is drawn in, and the line around the whole figure. A swap table for
/// the sprite library.
struct Look: Hashable {
    var colours: [BodyPart: RGB]
    /// Drawn around the figure's silhouette, this many pixels thick, or none. It follows
    /// the outside edge only: parts that touch share no line.
    var outline: RGB? = 0x000000
    var outlineWidth = 1

    /// Back limbs grey, everything else white, a black line round it all.
    static let plain: Look = {
        var colours: [BodyPart: RGB] = [:]
        for part in BodyPart.allCases {
            colours[part] = part.isBack ? 0x808080 : 0xFFFFFF
        }
        return Look(colours: colours)
    }()

    /// Every source colour to what it becomes.
    var swaps: [RGB: RGB] {
        var table: [RGB: RGB] = [:]
        for (part, colour) in colours {
            for source in part.sourceColours {
                table[source] = colour
            }
        }
        return table
    }
}

enum BallLook {
    /// The sheets draw the ball white, in the player's hands too; it plays orange.
    static let white: RGB = 0xFFFFFF
    static let orange: RGB = 0xF47E1B
    static let swaps: [RGB: RGB] = [white: orange]
}
