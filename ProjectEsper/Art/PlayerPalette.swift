import Foundation

/// A colour as the sheets store it, 0xRRGGBB.
typealias RGB = UInt32

/// The figure's parts, one flat colour each on the sheets, plus the ball in its hands,
/// the Esper Slash's blade in three pinks, and the energy: the sheets' white where it
/// isn't the ball, the skid's puffs and a release's streaks, told apart by size rather
/// than colour. Two of the parts are drawn in two close shades across the sheets, so a
/// part can own more than one source colour.
enum BodyPart: CaseIterable {
    case backHand, backArm, backLeg, backThigh
    case pelvis, torso, head
    case frontThigh, frontLeg, frontArm, frontHand
    case ball
    case slashEdge, slashFill, slashCore
    case energy

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
        case .ball: [0xFFFFFF]                            // white
        case .slashEdge: [0xF065C4]                       // magenta
        case .slashFill: [0xF9ABFF, 0xFBC2FF, 0xEEA6F5, 0xF098F5] // pink
        case .slashCore: [0xFDD9FF, 0xEDCEF0]             // pale pink
        case .energy: []
        }
    }

    var isBack: Bool {
        switch self {
        case .backHand, .backArm, .backLeg, .backThigh: true
        default: false
        }
    }

    /// The parts that burn: drawn in the team colour, outlined in it, and haloed.
    var glows: Bool { self == .head || self == .ball }

    /// The parts that are light rather than body: drawn on their own above the body so
    /// they bloom, with no line.
    var isEnergy: Bool {
        switch self {
        case .slashEdge, .slashFill, .slashCore, .energy: true
        default: false
        }
    }

    /// The part a source colour belongs to, within two steps per channel.
    static func owning(_ colour: RGB) -> BodyPart? {
        let r = Int((colour >> 16) & 0xFF), g = Int((colour >> 8) & 0xFF), b = Int(colour & 0xFF)
        for part in allCases {
            for source in part.sourceColours {
                let sr = Int((source >> 16) & 0xFF), sg = Int((source >> 8) & 0xFF), sb = Int(source & 0xFF)
                if abs(sr - r) <= 2, abs(sg - g) <= 2, abs(sb - b) <= 2 { return part }
            }
        }
        return nil
    }
}

/// What each part is drawn in, and the lines drawn on the figure.
struct Look: Hashable {
    var colours: [BodyPart: RGB]
    /// The team colour: what the glowing parts are drawn and outlined in, and their halo.
    var glow: RGB
    /// Drawn around the figure's silhouette, this many pixels thick. It follows the
    /// outside edge, in `glow` where it borders a glowing part and in `outline` elsewhere.
    var outline: RGB = 0x000000
    var outlineWidth = 1
    /// Parts also outlined where they lie over the rest of the body, so they read on their own.
    var strokedParts: Set<BodyPart> = []

    /// The body in its colour and the back limbs in a greyed, darker version of it, the head
    /// and the ball in the team colour, a black line round the body, and the front arm
    /// stroked on its own. The head is drawn apart from the body, with no line, and so is
    /// the energy: the slash's edge and the sheets' puffs and streaks in the team colour
    /// outright, the slash's fill lightened, its core nearly white.
    static func team(_ glow: RGB, body: RGB) -> Look {
        var colours: [BodyPart: RGB] = [:]
        let back = greyedDarker(body)
        for part in BodyPart.allCases {
            switch part {
            case .slashFill: colours[part] = lightened(glow, 0.3)
            case .slashCore: colours[part] = lightened(glow, 0.7)
            default: colours[part] = part.glows || part.isEnergy ? glow : (part.isBack ? back : body)
            }
        }
        return Look(colours: colours, glow: glow, strokedParts: [.frontArm, .frontHand])
    }

    /// The colour moved this share of the way to white.
    static func lightened(_ colour: RGB, _ share: Double) -> RGB {
        func channel(_ shift: RGB) -> RGB {
            let value = Double((colour >> shift) & 0xFF)
            return RGB((value + (255 - value) * share).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// Halfway to grey, then two thirds as bright.
    static func greyedDarker(_ colour: RGB) -> RGB {
        func channel(_ shift: RGB) -> RGB {
            let value = Double((colour >> shift) & 0xFF)
            return RGB(((value + 128) / 2 * 0.65).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    static let orange: RGB = 0xF47E1B
    static let teal: RGB = 0x5FCDE4
    /// The bodies: an orange and a teal light enough to read as the body, deep enough that
    /// the glow doesn't wash them out.
    static let lightOrange: RGB = 0xFFB877
    static let lightTeal: RGB = 0x8EDCE8

    static let playerOne = team(orange, body: lightOrange)
    static let playerTwo = team(teal, body: lightTeal)
    static let byPlayer = [playerOne, playerTwo]
}

enum BallLook {
    /// The loose ball is purple, after a while in the colour of whoever last let it go.
    static let neutral: RGB = 0xBF7BFF
    /// Frames it keeps the team colour after a shot or a throw, the sim's owned window, and
    /// frames of the shift back.
    static let holdFrames = 60
    static let shiftFrames = 30
    /// The chevrons over a resting ball.
    static let chevron: RGB = 0xFBF236
}

enum CourtLook {
    /// The tiles are dark shades: a colour at this much of its brightness.
    static let shade = 0.45

    /// The floor and walls with nobody holding the ball; they take the holder's colour.
    static let neutral: RGB = shaded(BallLook.neutral)
    /// The one-way ledge in the middle.
    static let ledge: RGB = shaded(0xF040E0)

    static func shaded(_ colour: RGB) -> RGB {
        func channel(_ shift: RGB) -> RGB {
            RGB((Double((colour >> shift) & 0xFF) * shade).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
    /// The chevrons over the rim the holder scores on.
    static let targetChevron: RGB = 0x50E080
    /// Frames the floor and walls take to shift between colours.
    static let shiftFrames = 20
}
