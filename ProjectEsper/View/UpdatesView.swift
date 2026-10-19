import EsperSim
import SwiftUI

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

struct UpdatesView: View {
    @ObservedObject var flow: FlowState

    /// Box 1's own shape, and the share of it its face leaves for the list, in from each side.
    static let boxAspect: CGFloat = 1314.0 / 708.0
    static let insetAcross: CGFloat = 0.09
    static let insetDown: CGFloat = 0.13
    /// The box's width at most, as a share of the screen's, and its height's.
    static let widthShare: CGFloat = 0.9
    static let heightShare: CGFloat = 0.86
    /// The lettering against the box's height, a title's and a bullet's; and an icon against a bullet's line.
    static let titleShare: CGFloat = 0.055
    static let bulletShare: CGFloat = 0.036
    static let iconLines: CGFloat = 2.6
    static let iconFramesPerSecond = 15.0
    /// The divider against the box's width; a bottle against a bullet's line, and its tilt anticlockwise in degrees.
    static let ruleShare: CGFloat = 0.3
    static let bottleLines: CGFloat = 1.8
    static let bottleTilt = 20.0

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width * UpdatesView.widthShare, geometry.size.height * UpdatesView.heightShare * UpdatesView.boxAspect)
            let height = width / UpdatesView.boxAspect
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: Futuristic.image("box1")).resizable().colorMultiply(Futuristic.line)
                    .frame(width: width, height: height)
                list(width: width, height: height)
                    .frame(width: width * (1 - 2 * UpdatesView.insetAcross), height: height * (1 - 2 * UpdatesView.insetDown))
                Text("TAP OR PRESS A TO CONTINUE")
                    .font(Futuristic.font(size: height * 0.03, face: UpdatesNotes.face))
                    .foregroundStyle(Futuristic.line.opacity(0.7))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + height / 2 + height * 0.04)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .onTapGesture { flow.closeUpdates() }
        }
        .ignoresSafeArea()
    }

    private func list(width: CGFloat, height: CGFloat) -> some View {
        let titleSize = height * UpdatesView.titleShare
        let bulletSize = height * UpdatesView.bulletShare
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: bulletSize * 0.6) {
                    ForEach(Array(UpdatesNotes.lines.enumerated()), id: \.offset) { index, line in
                        row(line, titleSize: titleSize, bulletSize: bulletSize, width: width).id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, bulletSize * 0.5)
            }
            .onChange(of: flow.updatesLine) { _, line in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(line, anchor: .top) }
            }
        }
    }

    @ViewBuilder
    private func row(_ line: UpdatesNotes.Line, titleSize: CGFloat, bulletSize: CGFloat, width: CGFloat) -> some View {
        switch line {
        case .title(let text):
            Text(text.uppercased())
                .font(Futuristic.font(size: titleSize, face: UpdatesNotes.face))
                .foregroundStyle(Futuristic.lit)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, bulletSize * 0.4)
        case .divider:
            Image(uiImage: Futuristic.image("rule6")).resizable().aspectRatio(contentMode: .fit)
                .colorMultiply(Futuristic.line)
                .frame(width: width * UpdatesView.ruleShare)
                .frame(maxWidth: .infinity)
                .padding(.vertical, bulletSize * 0.5)
        case .drink(let name, let drink):
            HStack(alignment: .center, spacing: bulletSize * 0.5) {
                Image(uiImage: DrinkPick.bottleImage(drink)).resizable().aspectRatio(contentMode: .fit)
                    .frame(height: bulletSize * UpdatesView.bottleLines)
                    .rotationEffect(.degrees(-UpdatesView.bottleTilt))
                UpdatesNotes.text(name, size: bulletSize, tone: .plain)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .bullet(let text, let depth, let icon, let tone):
            HStack(alignment: .center, spacing: bulletSize * 0.5) {
                Text("•").font(Futuristic.font(size: bulletSize, face: UpdatesNotes.face)).foregroundStyle(tone.colour)
                if let icon {
                    UpdatesIcon(flow: flow, icon: icon)
                        .frame(width: bulletSize * UpdatesView.iconLines, height: bulletSize * UpdatesView.iconLines)
                }
                UpdatesNotes.text(text, size: bulletSize, tone: tone)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(depth) * bulletSize * 2)
        }
    }
}

/// A bullet's moving icon: the shield's whole frames round and round, or the player as play
/// draws them (spinning with the ball, firing, flying, sniping), in the first side's look.
struct UpdatesIcon: View {
    @ObservedObject var flow: FlowState
    let icon: UpdatesNotes.Icon
    @State private var shieldFrames: [UIImage] = []

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                // The figure's canvas with its margin, its 48 pixels most of the icon's height.
                let canvas = 48 + 2 * CustomizeFigure.margin
                let pixel = geometry.size.height / canvas * UpdatesIcon.figureShare * canvas / 48
                switch icon {
                case .shield:
                    if !shieldFrames.isEmpty {
                        let frame = Int(time * UpdatesView.iconFramesPerSecond) % shieldFrames.count
                        Image(uiImage: shieldFrames[frame]).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                            .blendMode(.plusLighter)
                    }
                case .spin:
                    let pose = WinPose.spin
                    let frame = Int(time * pose.framesPerSecond) % max(pose.animation.frameCount, 1)
                    if let shown = flow.scene.winPortrait(player: 0, pose: pose, frame: frame) {
                        CustomizeFigure(portrait: shown.portrait, look: flow.scene.playerLook(0), pixel: pixel, mirrored: false,
                                        headNudge: shown.headNudge, headScale: shown.headScale, ball: shown.ball, overBall: shown.overBall)
                            .frame(width: canvas * pixel, height: canvas * pixel)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                case .pose(let pose):
                    if let shown = flow.scene.updatesPose(pose, tick: Int(time * 60)) {
                        CustomizeFigure(portrait: shown.portrait, look: flow.scene.playerLook(0), pixel: pixel, mirrored: false,
                                        headNudge: shown.headNudge, headScale: shown.headScale, extras: shown.extras)
                            .frame(width: canvas * pixel, height: canvas * pixel)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
            }
        }
        .onAppear {
            if case .shield = icon, shieldFrames.isEmpty { shieldFrames = flow.scene.updatesShieldFrames() }
        }
    }

    /// The figure's 48 pixels against the icon's height.
    static let figureShare: CGFloat = 0.8
}
