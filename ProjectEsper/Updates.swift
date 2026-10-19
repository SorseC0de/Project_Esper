import EsperSim
import SwiftUI

// The updates screen's notes, at the top of the app's folder to be easy to find and edit; `UpdatesView`
// draws them. Brackets make a keyword gold; [Up] and [Down] are the fat arrow. A bullet's tone
// is .buff, .nerf or plain; a new `id` shows the screen again to everyone once.

/// What's new for testers, shown once over everything on launch until it's dismissed: box 1 on
/// black, a list scrolling inside it, left-aligned and bulleted, some lines with a moving icon.
/// A new set of notes gets a new `id`, so it shows again.
enum UpdatesNotes {
    static let id = "2026-10-19"
    static let seenKey = "esper.updates.seen"
    static var unseen: Bool { UserDefaults.standard.string(forKey: seenKey) != id }

    enum Icon {
        case shield, spin
        /// A figure as play draws it (`GameScene.updatesPose`).
        case pose(Pose)
    }
    enum Pose { case blast, flight, snipe }
    /// A line's lettering: the list's blue, or a buff's or a nerf's.
    enum Tone {
        case plain, buff, nerf
        var colour: Color {
            switch self {
            case .plain: Futuristic.line
            case .buff: Color(rgb: PixelPalette.colours[29])
            case .nerf: Color(rgb: PixelPalette.colours[64])
            }
        }
    }
    /// Lines' words in brackets are keywords, gold; [Up] and [Down] the fat arrow (`PickScreen.blurbPieces`).
    enum Line {
        case title(String)
        /// A bullet, indented `depth` levels, maybe with its icon.
        case bullet(String, depth: Int = 0, icon: Icon? = nil, tone: Tone = .plain)
        /// A Greateraid's name, its bottle tilted in place of the bullet.
        case drink(String, Greateraid)
        case divider
    }

    /// The shield's sheet's whole frames that loop, the 11th to 14th (0-based 10 to 13).
    static let shieldIconFrames = Array(10...13)

    static let lines: [Line] = [
        .title("Core Changes"),
        .bullet("Press [Up] + [Slash] to [Shieldflip]. [Shield] can be used to reflect the ball or powers. [Parries] [Slash], loses to [Snatch] and [Throw].", icon: .shield),
        .bullet("Press [Down] + [Throw] with the ball to perform a [Spin Move]. Attacks go through you while spinning, however you only get one per airtime.", icon: .spin),
        .bullet("You can now select a [Greateraid] power to have during [FloState] in [47 Mode]"),
        .bullet("Increased [Stun] time 1.5s ➜ 2s", tone: .nerf),
        .divider,
        .title("Greateraid Changes"),
        .drink("Z-Tea", .zTea),
        .bullet("Press [Up] + [Slash] to fire an [Esper Blast]", depth: 1, icon: .pose(.blast), tone: .buff),
        .drink("Platform Protein Shake", .platformShake),
        .bullet("Increased [Platform] duration 60 ➜ 120 frames", depth: 1),
        .drink("Super Smoothie", .superSmoothie),
        .bullet("Hold [Up] + [Jump] while grounded to [Super Jump] into [Flight]", depth: 1, icon: .pose(.flight), tone: .buff),
        .drink("Pulsepistol Punch", .pulsepistol),
        .bullet("Press [Up] + [Slash] to [Pull], [Down] + [Slash] to [Repel].", depth: 1),
        .bullet("Increased [Pull] on players and ball", depth: 1),
        .bullet("[Snipe] [Repel] shot now [Stuns]", depth: 1, icon: .pose(.snipe), tone: .buff),
        .drink("Cannon Cola", .cannonCola),
        .bullet("Increased [Shot] animation speed", depth: 1, tone: .buff),
        .drink("Slide Cider", .slideCider),
        .bullet("Level 2 now [Stuns]", depth: 1, tone: .buff),
        .drink("Guarderade (New Booster)", .guarderade),
        .bullet("Level 1: Bigger [Shield]", depth: 1),
        .bullet("Level 2: [Shield] a second time before you land", depth: 1),
        .drink("Shelter Seltzer (New Booster)", .shelterSeltzer),
        .bullet("Level 1: Your [Shield] lingers where it ends for a second", depth: 1),
        .bullet("Level 2: Your [Snatches] raise a [Shield] where your hand is", depth: 1),
    ]

    /// The screen's face whatever the menus' is: E.
    static let face = 4

    /// A line's lettering in the screen's face: its words in its tone, keywords gold, [Up] and
    /// [Down] the fat arrow turned that way, gold.
    static func text(_ text: String, size: CGFloat, tone: Tone) -> Text {
        let shownSize = Futuristic.fontSize(size, face: face)
        var made = Text("")
        for (index, piece) in PickScreen.blurbPieces(text).enumerated() {
            if index > 0, piece.spaced { made = made + Text(" ") }
            switch piece.kind {
            case .word(let word, let lit):
                made = made + Text(word).foregroundColor(lit ? DrinkPick.litColour : tone.colour)
            case .arrow(let turn):
                made = made + Text(Image(uiImage: DrinkPick.arrow(turn: turn, side: shownSize)).renderingMode(.template)).foregroundColor(DrinkPick.litColour)
            }
        }
        return made.font(Futuristic.font(size: size, face: face))
    }
}
