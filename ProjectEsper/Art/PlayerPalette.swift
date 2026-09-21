import Foundation

/// A colour as the sheets store it, 0xRRGGBB.
typealias RGB = UInt32

/// The figure's parts, one flat colour each on the sheets, plus the ball in its hands.
/// Two of the parts are drawn in two close shades across the sheets, so a part can own
/// more than one source colour.
enum BodyPart: CaseIterable {
    case backHand, backArm, backLeg, backThigh
    case pelvis, torso, head
    case frontThigh, frontLeg, frontArm, frontHand
    case ball

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
    /// stroked on its own. The head is drawn apart from the body, with no line.
    static func team(_ glow: RGB, body: RGB) -> Look {
        var colours: [BodyPart: RGB] = [:]
        let back = greyedDarker(body)
        for part in BodyPart.allCases {
            colours[part] = part.glows ? glow : (part.isBack ? back : body)
        }
        return Look(colours: colours, glow: glow, strokedParts: [.frontArm, .frontHand])
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
    /// The bodies: a light orange and a light teal, clearly toward the team colour.
    static let lightOrange: RGB = 0xFFD8B0
    static let lightTeal: RGB = 0xB8EEF5

    static let playerOne = team(orange, body: lightOrange)
    static let playerTwo = team(teal, body: lightTeal)
    static let byPlayer = [playerOne, playerTwo]
}

enum BallLook {
    /// The loose ball is purple, after a while in the colour of whoever last let it go.
    static let neutral: RGB = 0xBF7BFF
    /// Frames it keeps the team colour after a shot or a throw, and frames of the shift back.
    static let holdFrames = 45
    static let shiftFrames = 30
    /// The chevrons over a resting ball.
    static let chevron: RGB = 0xFBF236
}
