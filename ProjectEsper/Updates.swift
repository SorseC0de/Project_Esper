import EsperSim
import SwiftUI

// The updates screen's notes, at the top of the app's folder to be easy to find and edit; `UpdatesView`
// draws them. Brackets make a keyword gold; [Up] and [Down] are the fat arrow. A bullet's tone
// is .buff, .nerf or plain; a new `id` shows the screen again to everyone once.

/// What's new for testers, shown once over everything on launch until it's dismissed: box 1 on
/// black, a list scrolling inside it, left-aligned and bulleted, some lines with a moving icon.
/// A new set of notes gets a new `id`, so it shows again.
enum UpdatesNotes {
    static let id = "2026-11-11 build 14"
    static let seenKey = "esper.updates.seen"
    static var unseen: Bool { UserDefaults.standard.string(forKey: seenKey) != id }

    enum Icon {
        case shield, spin
        /// A figure as play draws it (`GameScene.updatesPose`).
        case pose(Pose)
    }
    enum Pose { case blast, flight, snipe, floState }
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
        /// A headline bullet: gold, on a gold highlight.
        case feature(String)
        case divider
    }

    /// The shield's sheet's whole frames that loop, the 11th to 14th (0-based 10 to 13).
    static let shieldIconFrames = Array(10...13)

    /// Each build's notes, newest first: the screen's tabs, a number in a circle each.
    struct Build {
        let number: Int
        let lines: [Line]
    }
    static let builds: [Build] = [
        Build(number: 14, lines: [
            .title("Core Changes"),
            .feature("New Mode: Breaker Ball (offline)"),
            .bullet("Wear down your opponent's [Barrier] with Breaker Balls and attacks, then score through the rim that appears over their head. First to 3 wins.", depth: 1),
            .feature("How To Play: a [Tutorial] from the title screen"),
            .bullet("Modes now sit on a turning ring on the title screen; VS CPU is picked per side on the customize screen."),
            .bullet("[Throws] are now chargeable. A full-charge throw can't be caught or snatched until it bounces."),
            .bullet("New [Dunk] animation"),
            .bullet("You can jump during [Hit Stun]", tone: .buff),
            .bullet("Repeated hits within 2s give growing invulnerability", tone: .buff),
            .bullet("[Shield] no longer knocks the ball out of a carrier's hands."),
            .bullet("Ground [Shots] release from higher up."),
            .bullet("Landing a [Parry] now returns you to neutral from any action."),
            .bullet("The CPU now uses its drink's powers."),
            .bullet("Drink picker layout changed."),
            .divider,
            .title("Stages"),
            .bullet("Longball Stadium"),
            .bullet("New stadium and goalpost art", depth: 1),
            .bullet("The portal carries players too", depth: 1),
            .bullet("No [Auto-aim] on shots", depth: 1, tone: .nerf),
            .bullet("The Elements: icicles evened out, 16 ➜ 15"),
            .bullet("The Wreck Center: the back wall no longer changes colour"),
            .divider,
            .title("Greateraid Changes"),
            .drink("Phantom Frappe (New Biomorph)", .phantomFrappe),
            .bullet("Level 1: [Spin Move] or taunt toggles [Phantom Mode]: pass through players, attacks and walls", depth: 1),
            .bullet("Level 2: a second [Spin Move] per jump", depth: 1),
            .drink("Floback Fresca (was Flo-efficient Frappe)", .flobackFresca),
            .bullet("Level 1: +5 [FLO] when you're hit", depth: 1),
            .bullet("Level 2: +5 [FLO] when you throw", depth: 1),
            .drink("Platform Protein Shake", .platformShake),
            .bullet("Slabs stay until broken or replaced (lasted 2s); slab and wall share one cooldown", depth: 1),
            .drink("Web Water", .webWater),
            .bullet("The Level 2 [Web Line] can break shields", depth: 1),
            .bullet("Swing cooldown 28 ➜ 20 frames", depth: 1, tone: .buff),
            .drink("Z-Tea", .zTea),
            .bullet("No more hold-to-autofire: tap [Strike] to queue the next [Blast]; jumping cancels it", depth: 1),
            .drink("Feather Float", .featherFloat),
            .bullet("Renamed from Feather Fresca", depth: 1),
            .divider,
            .title("Fixes"),
            .bullet("[Flash Fizz] warps no longer leave you stuck in walls"),
        ]),
        Build(number: 13, lines: [
            .title("Core Changes"),
            .feature("New Stage: Anozira"),
            .bullet("Scoring now locks the rim for 2s: a [Hex Shield] covers it, and the scorer can still fight for the ball but can't score again till it opens.", tone: .nerf),
            .bullet("A ball bouncing square off the [Hex Shield] is nudged toward the other rim."),
            .bullet("[Shield] no longer pushes players; it still knocks the ball loose and reflects it."),
            .bullet("[Exclusion] lasts longer: 1s ➜ 1.5s"),
            .bullet("[Auto-aim] range 160 ➜ 144, and it now needs at least 5 tiles of distance (was 3)"),
            .divider,
            .title("Greateraid Changes"),
            .drink("Titan Tea", .titanTea),
            .bullet("Gains no [FLO] in [FloState] from its quakes or [Trample]", depth: 1, tone: .nerf),
            .bullet("Quakes and [Trample] can't re-stun a body that's still stunned", depth: 1, tone: .nerf),
            .bullet("Its slower movement now lasts through level 2", depth: 1, tone: .nerf),
            .drink("Z-Tea", .zTea),
            .bullet("You stay planted while firing [Blasts]: the first straight, then the aim eases toward the stick, up to 45°", depth: 1),
            .bullet("[Beam] charges faster: 60 ➜ 40 frames", depth: 1, tone: .buff),
            .drink("Volta Cola", .voltaCola),
            .bullet("You can change direction while firing bolts", depth: 1),
            .drink("Blazing Boba", .blazingBoba),
            .bullet("Flames no longer stun-lock: a short grace after each stun", depth: 1, tone: .nerf),
            .divider,
            .title("Fixes"),
            .bullet("A basket after a failed [Dunk] no longer counts as a dunk"),
        ]),
        Build(number: 12, lines: [
            .title("Core Changes"),
            .bullet("Major movement and control feel overhaul", tone: .buff),
            .bullet("[Throw-stance Parry] removed. Counter [Slash] with [Shield].", tone: .nerf),
            .bullet("[CPU intelligence] improved on [The Wreck Center]", tone: .buff),
            .bullet("[Spin Move] now protects from all types of hits", tone: .buff),
            .bullet("Entering [FloState] now [Parries] [Throw], [Shieldflip], and [Snatch] in addition to [Slash].", tone: .buff),
            .divider,
            .title("Greateraid Changes"),
            .drink("Flo-efficient Frappe (New Booster)", .flobackFresca),
            .bullet("Level 1: Your [FloState] lasts longer", depth: 1, icon: .pose(.floState)),
            .bullet("Level 2: Gain more [FLO] from all sources", depth: 1),
            .drink("Super Smoothie", .superSmoothie),
            .bullet("[Super Jump] height reduced", depth: 1, tone: .nerf),
        ]),
        Build(number: 11, lines: [
            .title("Core Changes"),
            .bullet("Press [Up] or [Down] + [Guard] to [Shieldflip]. [Shield] can be used to reflect the ball or powers. [Parries] [Slash], loses to [Snatch] and [Throw].", icon: .shield),
            .bullet("Press [Down] + [Guard] with the ball to perform a [Spin Move]. Attacks go through you while spinning, however you only get one per airtime.", icon: .spin),
            .bullet("You can now select a [Greateraid] power to have during [FloState] in [47 Mode]"),
            .bullet("Increased [Stun] time 1.5s ➜ 2s", tone: .nerf),
            .divider,
            .title("Greateraid Changes"),
            .drink("Z-Tea", .zTea),
            .bullet("Press [Up] + [Strike] to fire an [Esper Blast]", depth: 1, icon: .pose(.blast), tone: .buff),
            .bullet("[Beam] no longer consumes [Flo] to fire.", depth: 1, tone: .buff),
            .drink("Platform Protein Shake", .platformShake),
            .bullet("Increased [Platform] duration 60 ➜ 120 frames", depth: 1),
            .drink("Super Smoothie", .superSmoothie),
            .bullet("Hold [Up] + [Jump] while grounded to [Super Jump] into [Flight]", depth: 1, icon: .pose(.flight), tone: .buff),
            .drink("Pulsepistol Punch", .pulsepistol),
            .bullet("Press [Up] + [Strike] to [Pull], [Down] + [Strike] to [Repel].", depth: 1),
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
        ]),
    ]

    /// The screen's face whatever the menus' is: E.
    static let face = Futuristic.listFace

    /// A line's lettering in the screen's face: its words in its tone, keywords and glyphs gold.
    static func text(_ text: String, size: CGFloat, tone: Tone) -> Text {
        let shownSize = Futuristic.fontSize(size, face: face)
        var made = Text("")
        for (index, piece) in PickScreen.blurbPieces(text).enumerated() {
            if index > 0, piece.spaced { made = made + Text(" ") }
            switch piece.kind {
            case .word(let word, let lit):
                made = made + Text(word).foregroundColor(lit ? DrinkPick.litColour : tone.colour)
            case .glyph(let image, let turn):
                made = made + Text(Image(uiImage: DrinkPick.glyph(image, turn: turn, side: shownSize)).renderingMode(.template)).foregroundColor(DrinkPick.litColour)
            }
        }
        return made.font(Futuristic.font(size: size, face: face))
    }
}
