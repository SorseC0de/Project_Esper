import Foundation

/// A colour as the sheets store it, 0xRRGGBB.
typealias RGB = UInt32

/// The figure's parts, one flat colour each on the sheets, plus the ball in its hands,
/// the Esper Slash's blade in pinks, and the energy: the sheets' white where it isn't
/// the ball, the skid's puffs and a release's streaks, told apart by size rather than
/// colour. The blade and the energy are toned by their brightness rather than painted
/// flat. Two of the parts are drawn in two close shades across the sheets, so a part can
/// own more than one source colour.
enum BodyPart: CaseIterable {
    case backHand, backArm, backLeg, backThigh, backFoot
    case pelvis, torso, head
    case frontThigh, frontLeg, frontArm, frontHand, frontFoot
    case ball
    case slash
    case energy

    /// What the sheets paint this part with, as the artist named the colours.
    var sourceColours: [RGB] {
        switch self {
        case .backHand: [0xBC4A9B]                        // AAP-64 27
        case .backArm: [0x793A80]                         // 28
        case .backLeg: [0xB4202A]                         // 4
        case .backThigh: [0x73172D]                       // 3, darker than the leg as the others are
        case .pelvis: [0xBB7547]                          // 34
        case .torso: [0xFA6A0A]                           // 6
        case .head: [0x20D6C7]                            // 20
        case .frontThigh: [0xFFD541]                      // 8
        case .frontLeg: [0xFFFC40]                        // 9
        case .frontArm: [0x59C135]                        // 12
        case .frontHand: [0x9CDB43]                       // 11
        case .frontFoot: [0xA6FCDB]                       // 21
        case .backFoot: [0xE86A73]                        // 26
        case .ball: [0xFFFFFF]                            // white
        case .slash: [0xF065C4, 0xF9ABFF, 0xFBC2FF, 0xEEA6F5, 0xF098F5, 0xFDD9FF, 0xEDCEF0] // pinks, edge to core
        case .energy: []
        }
    }

    var isBack: Bool {
        switch self {
        case .backHand, .backArm, .backLeg, .backThigh, .backFoot: true
        default: false
        }
    }

    /// The parts that burn: drawn in the team colour, outlined in it, and haloed. A human's
    /// head doesn't.
    func glows(human: Bool) -> Bool { (self == .head && !human) || self == .ball }

    /// The parts that are light rather than body: drawn on their own above the body so
    /// they bloom, with no line, in the team colour's tones by their brightness.
    var isEnergy: Bool { self == .slash || self == .energy }

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
    /// outside edge, in `glow` where it borders a glowing part and in `outline` elsewhere,
    /// the pixel palette's outline.
    var outline: RGB = PixelPalette.outline
    var outlineWidth = 1
    /// Groups of parts also outlined where they lie over the rest of the body, so each reads
    /// on its own; parts in one group take no line between them.
    var strokedGroups: [Set<BodyPart>] = []
    /// Drawn as a human, skin and clothes, the head on the body; else the energy form, the
    /// whole body in the energy's colours and the head apart.
    var human = HumanLook.enabled
    /// The head drawn apart from the body, a quarter bigger: the energy form's. Off
    /// (`energyFormHeadApart`), it's drawn on the body at its own size, as a human's is.
    var headApart: Bool { !human && Look.energyFormHeadApart }
    static let energyFormHeadApart = true
    /// The body colour the look was made from, for its other form.
    var body: RGB?
    /// The skin tone, sleeves and pants picked on the customize screen.
    var dressing = Dressing()

    /// The same player facing the other way: the sheet's front limbs are the other arm and leg,
    /// so the sleeves and boots swap front for back.
    var turnedRound: Look {
        guard human else { return self }
        return Look.team(glow, body: body ?? glow, human: true, dressing: dressing.turnedRound)
    }

    /// The same player in the energy form.
    var transformed: Look { Look.team(glow, body: body ?? glow, human: false, dressing: dressing) }

    /// The body in its colour and the back limbs in a greyed, darker version of it, the head
    /// and the ball in the team colour, a black line round the body, and the front arm
    /// stroked on its own. The head is drawn apart from the body, with no line, and so is
    /// the energy, toned by `energyTone`.
    static func team(_ glow: RGB, body: RGB, human: Bool = HumanLook.enabled, dressing: Dressing = Dressing()) -> Look {
        var colours: [BodyPart: RGB] = [:]
        let back = greyedDarker(body)
        for part in BodyPart.allCases {
            colours[part] = part.glows(human: human) || part.isEnergy ? glow : (part.isBack ? back : body)
        }
        if human {
            // Skin and clothes; the legs and feet in the energy's own colour, as the head's crown
            // is, the back ones at two thirds of it: darker but not greyed, so they glow too.
            for (part, skin) in dressing.skin { colours[part] = skin }
            for part in HumanLook.clothed { colours[part] = part.isBack ? HumanLook.backClothes : HumanLook.clothes }
            for part in dressing.glowing { colours[part] = part.isBack ? Look.scaled(glow, HumanLook.backLegShare) : glow }
        } else {
            // The energy form: the body in the lighter colour of the earlier builds, the back
            // parts down its ramp as a human's back leg is; what a human shows bare in the regular
            // energy colour.
            for part in BodyPart.allCases where !part.isEnergy && part != .ball {
                colours[part] = part.isBack ? Look.scaled(body, HumanLook.backLegShare) : body
            }
            for part in dressing.energyFormBare { colours[part] = part.isBack ? Look.scaled(glow, HumanLook.backLegShare) : glow }
        }
        return Look(colours: colours, glow: glow, strokedGroups: Look.strokedGroups, human: human, body: body, dressing: dressing)
    }

    /// Lined on their own, front to back: where two meet, the first's line sits on the
    /// second's pixels, so the first reads in front. The front arm and hand over everything,
    /// then the head. (The thighs as a group made a wedge where their line met the torso's;
    /// the torso's own is off for now: add `[.torso]` after the head to bring it back. The
    /// shoes' own are off with the feet in the energy's colours: `[.frontFoot], [.backFoot]`.)
    static let strokedGroups: [Set<BodyPart>] = [[.frontArm, .frontHand], [.head]]

    /// A grey level as a tone of the team colour, for everything that's energy: the
    /// blade, the puffs and streaks, the effect sheets. Black up to the colour over the
    /// dark half, the colour up to a quarter of the way to white over the light half, so
    /// mid grey is the colour itself and white a light tint that still reads as it.
    /// The sparks' tone (the jump spark, the wall spark, the dash's and slide's smoke, the
    /// skid's puffs and the sheets' energy): the ramp's dark half, then the colour itself,
    /// never lighter, as the legs and the crown are.
    func sparkTone(luminance: Double) -> RGB {
        luminance <= 0.5 ? Look.scaled(glow, luminance * 2) : glow
    }

    /// The colour's bright version: the energy ramp at its lightest.
    var bright: RGB { energyTone(luminance: 1) }

    func energyTone(luminance: Double) -> RGB {
        luminance <= 0.5 ? Look.scaled(glow, luminance * 2) : Look.lightened(glow, (luminance * 2 - 1) * 0.25)
    }

    /// The colour moved this share of the way to white.
    static func lightened(_ colour: RGB, _ share: Double) -> RGB {
        func channel(_ shift: RGB) -> RGB {
            let value = Double((colour >> shift) & 0xFF)
            return RGB((value + (255 - value) * share).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    /// The colour at this share of its brightness.
    static func scaled(_ colour: RGB, _ share: Double) -> RGB {
        func channel(_ shift: RGB) -> RGB {
            RGB((Double((colour >> shift) & 0xFF) * share).rounded()) << shift
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

    /// Orange and teal, as the two sides start, from `PixelPalette`.
    static let orange: RGB = PixelPalette.orange
    static let teal: RGB = PixelPalette.teal
    /// The bodies: the energy lifted two fifths of the way to white.
    static let lightOrange: RGB = lightened(orange, 0.4)
    static let lightTeal: RGB = lightened(teal, 0.4)

    static let playerOne = team(orange, body: lightOrange)
    static let playerTwo = team(teal, body: lightTeal)
    static let byPlayer = [playerOne, playerTwo]

    /// Frozen bodies and Frost Tea's ice clones: the front parts, the head and the torso's
    /// light in palette 57, the back parts and the torso's shadow (the pelvis) in 49, outlined in 22.
    static let ice: Look = {
        let front = PixelPalette.colours[57], back = PixelPalette.colours[49]
        var colours: [BodyPart: RGB] = [:]
        for part in BodyPart.allCases { colours[part] = part.isBack || part == .pelvis ? back : front }
        return Look(colours: colours, glow: front, outline: PixelPalette.colours[22], strokedGroups: Look.strokedGroups)
    }()
}

/// The energy colours a player can pick on the title, each paired with its opposite: when
/// two sides pick the same, the one that gives way takes the opposite.
enum EnergyColour: String, CaseIterable, Codable {
    case orange, teal, red, lime, pink, blue, gold, purple

    /// The glow, from `PixelPalette`.
    var glow: RGB {
        switch self {
        case .orange: PixelPalette.orange
        case .teal: PixelPalette.teal
        case .red: PixelPalette.red
        case .lime: PixelPalette.lime
        case .pink: PixelPalette.pink
        case .blue: PixelPalette.blue
        case .gold: PixelPalette.gold
        case .purple: PixelPalette.colours[28]
        }
    }

    /// Its name, a gem's.
    var name: String {
        switch self {
        case .blue: "Sapphire"
        case .orange: "Topaz"
        case .red: "Ruby"
        case .purple: "Amethyst"
        case .pink: "Quartz"
        case .lime: "Peridot"
        case .teal: "Tourmaline"
        case .gold: "Citrine"
        }
    }

    /// The body: the glow lifted a third of the way to white.
    var body: RGB { Look.lightened(glow, EnergyColour.bodyLift) }
    static let bodyLift = 0.33

    /// The shade down its ramp in the pixel palette: the customize screen's second row.
    var rampDown: RGB {
        switch self {
        case .red: PixelPalette.colours[4]
        case .orange: PixelPalette.colours[5]
        case .gold: PixelPalette.colours[6]
        case .lime: PixelPalette.colours[12]
        case .teal: PixelPalette.colours[19]
        case .blue: PixelPalette.colours[17]
        case .pink: PixelPalette.colours[28]
        case .purple: PixelPalette.colours[29]
        }
    }

    /// The customize screen's picker, round the colour wheel.
    static let wheel: [EnergyColour] = [.red, .orange, .gold, .lime, .teal, .blue, .purple, .pink]

    var opposite: EnergyColour {
        switch self {
        case .gold: .teal
        case .teal: .gold
        case .red: .lime
        case .lime: .red
        case .purple: .pink
        case .pink: .purple
        case .orange: .blue
        case .blue: .orange
        }
    }

    var look: Look { Look.team(glow, body: body) }

    /// Both sides' colours: each keeps its own unless they match, and then the second gives
    /// way to the opposite.
    static func pair(first: EnergyColour, second: EnergyColour) -> [EnergyColour] {
        [first, second == first ? first.opposite : second]
    }

    /// What this phone picked, kept between launches.
    static let storageKey = "esper.energyColour"
    static var saved: EnergyColour {
        UserDefaults.standard.string(forKey: storageKey).flatMap(EnergyColour.init(rawValue:)) ?? .orange
    }
}

enum BallLook {
    /// The loose ball is the neutral colour, palette 40, after a while in the colour of
    /// whoever last let it go.
    static let neutral: RGB = PixelPalette.colours[40]
    /// Frames of the shift back to neutral once the ball has bounced and is nobody's.
    static let shiftFrames = 30
    /// The chevrons over a resting ball.
    static let chevron: RGB = 0xFBF236
    /// The dark purple of an empty round circle and the ball's off-screen chevrons' outline.
    static let darkPurple: RGB = 0x3A2A48
}

enum CourtLook {
    /// The tiles are dark shades: a colour at this much of its brightness.
    static let shade = 0.45

    /// The floor and walls with nobody holding the ball; they take the holder's colour.
    static let neutral: RGB = shaded(BallLook.neutral)
    /// The one-way ledge in the middle: palette 39, shaded as the rest.
    static let ledge: RGB = shaded(PixelPalette.colours[39])

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
    /// On a score the floor and walls go white with the bolt's flash and fade back over this many frames.
    static let strikeFadeFrames = 20
}

/// An experiment: the players drawn as people. Skin on the head, the arms, the hands and the
/// lower legs, in the side's skin tone (`Dressing`); the torso, pelvis and thighs in palette 41 for
/// everyone; the lower legs and feet in the energy's colours, glowing; the head drawn as
/// part of the body, not apart, and not glowing. `enabled` off puts everything back as it was.
enum HumanLook {
    static let enabled = true
    /// The parts still in the energy's colours, which glow as energy does: the shoes.
    static let glowingParts: Set<BodyPart> = [.frontFoot, .backFoot]
    /// The six skins of `player_hoodheads`, a frame each, as palette indexes: the lighter
    /// tone the front limbs', the darker the back's (`_Design/skin-tones.md`).
    static let skinTones: [(front: Int, back: Int)] = [(36, 35), (24, 47), (47, 46), (35, 34), (34, 33), (33, 44), (38, 39)]
    /// The robot's, the seventh: no frame of its own, drawn from the fourth's with its two tones swapped for greys.
    static let robotSkinTone = 6
    static let robotDrawnFrom = 3
    /// The `player_hoodheads` frame a skin is drawn from.
    static func hoodHeadFrame(_ tone: Int) -> Int { tone == robotSkinTone ? robotDrawnFrom : tone }
    /// The fourth, the bodies' before the customize screen.
    static let defaultSkinTone = 3
    /// What shows bare with nothing over it: the head, the arms and hands, the lower legs.
    static let bareParts: Set<BodyPart> = [.head, .frontArm, .frontHand, .frontLeg, .backArm, .backHand, .backLeg]
    /// The back leg and foot's share of the energy colour's brightness.
    static let backLegShare = 0.66
    /// The torso, pelvis and thighs, the same for every player: palette 41, the back thigh
    /// the next down its ramp, 42.
    static let clothed: Set<BodyPart> = [.torso, .pelvis, .frontThigh, .backThigh]
    /// What a human shows bare, but the head (the hooded head's own): in the energy form, the
    /// regular energy colour rather than the energy form's lighter one, glowing.
    static let clothes = PixelPalette.colours[41], backClothes = PixelPalette.colours[42]
}

/// What a player picked to wear on the customize screen: a skin tone, a frame of
/// `player_hoodheads` (or the robot's, drawn from another); a sleeve over each arm, the hand
/// left bare, and a boot over each lower leg. Sleeves and boots are energy: the energy's colour,
/// the back ones down its ramp as the back shoe is, and they glow.
struct Dressing: Hashable, Codable {
    var skinTone = HumanLook.defaultSkinTone
    var frontSleeve = false
    var backSleeve = false
    var frontBoot = true
    var backBoot = true

    init() {}

    /// Kept picks from before a field was added keep the rest, the new field its default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fresh = Dressing()
        skinTone = try container.decodeIfPresent(Int.self, forKey: .skinTone) ?? fresh.skinTone
        frontSleeve = try container.decodeIfPresent(Bool.self, forKey: .frontSleeve) ?? fresh.frontSleeve
        backSleeve = try container.decodeIfPresent(Bool.self, forKey: .backSleeve) ?? fresh.backSleeve
        frontBoot = try container.decodeIfPresent(Bool.self, forKey: .frontBoot) ?? fresh.frontBoot
        backBoot = try container.decodeIfPresent(Bool.self, forKey: .backBoot) ?? fresh.backBoot
    }

    var turnedRound: Dressing {
        var turned = self
        turned.frontSleeve = backSleeve
        turned.backSleeve = frontSleeve
        turned.frontBoot = backBoot
        turned.backBoot = frontBoot
        return turned
    }

    var tone: (front: Int, back: Int) { HumanLook.skinTones[min(max(skinTone, 0), HumanLook.skinTones.count - 1)] }

    /// The parts in skin, by the tone's front and back.
    var skin: [BodyPart: RGB] {
        var parts: [BodyPart: RGB] = [:]
        for part in HumanLook.bareParts.subtracting(covered) {
            parts[part] = PixelPalette.colours[part.isBack ? tone.back : tone.front]
        }
        return parts
    }

    var covered: Set<BodyPart> {
        var parts: Set<BodyPart> = []
        if frontSleeve { parts.insert(.frontArm) }
        if backSleeve { parts.insert(.backArm) }
        if frontBoot { parts.insert(.frontLeg) }
        if backBoot { parts.insert(.backLeg) }
        return parts
    }

    /// The parts in the energy's colours, glowing: the shoes, and the sleeves and boots.
    var glowing: Set<BodyPart> { HumanLook.glowingParts.union(covered) }

    /// What a human shows bare or in sleeves and boots, but the head (the hooded head's own):
    /// in the energy form, the regular energy colour rather than the energy form's lighter one, glowing.
    var energyFormBare: Set<BodyPart> { HumanLook.bareParts.subtracting([.head]) }
}
