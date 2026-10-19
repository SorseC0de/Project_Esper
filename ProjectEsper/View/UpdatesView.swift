import EsperSim
import SwiftUI

/// What's new for testers, shown once over everything on launch until it's dismissed: box 1 on
/// black, a list scrolling inside it, left-aligned and bulleted, some lines with a moving icon.
/// A new set of notes gets a new `id`, so it shows again.
enum UpdatesNotes {
    static let id = "2026-10-19"
    static let seenKey = "esper.updates.seen"
    static var unseen: Bool { UserDefaults.standard.string(forKey: seenKey) != id }

    enum Icon { case shield, spin }
    enum Line: Hashable {
        case title(String)
        /// A bullet, indented `depth` levels, maybe with its icon.
        case bullet(String, depth: Int, icon: Icon?)
        case divider
    }

    /// The shield's sheet's whole frames that loop, the 11th to 14th (0-based 10 to 13).
    static let shieldIconFrames = Array(10...13)

    static let lines: [Line] = [
        .title("Core Changes"),
        .bullet("Press Up + Slash to shieldflip. Shield can be used to reflect the ball or powers. Parries Slash, loses to Snatch and Throw.", depth: 0, icon: .shield),
        .bullet("Press Down + Throw with the ball to perform a Spin Move. Attacks go through you while spinning, however you only get one per airtime.", depth: 0, icon: .spin),
        .bullet("You can now select a Greateraid power to have during FloState in 47 Mode", depth: 0, icon: nil),
        .bullet("Increased Stun time 1.5s ➜ 2s", depth: 0, icon: nil),
        .divider,
        .title("Greateraid Changes"),
        .bullet("Z-Tea", depth: 0, icon: nil),
        .bullet("Press Up + Slash to fire an Esper Blast", depth: 1, icon: nil),
        .bullet("Platform Protein Shake", depth: 0, icon: nil),
        .bullet("Increased Platform duration 60 ➜ 120 frames", depth: 1, icon: nil),
        .bullet("Super Smoothie", depth: 0, icon: nil),
        .bullet("Hold Up + Jump while grounded to super jump into flight", depth: 1, icon: nil),
        .bullet("Pulsepistol Punch", depth: 0, icon: nil),
        .bullet("Press Up+Slash to Pull, Down+Slash to Repel.", depth: 1, icon: nil),
        .bullet("Increased Pull on players and ball", depth: 1, icon: nil),
        .bullet("Snipe Repel shot now stuns", depth: 1, icon: nil),
        .bullet("Cannon Cola", depth: 0, icon: nil),
        .bullet("Increased shot animation speed", depth: 1, icon: nil),
        .bullet("Slide Cider", depth: 0, icon: nil),
        .bullet("Level 2 now stuns", depth: 1, icon: nil),
        .bullet("Guarderade (New Booster)", depth: 0, icon: nil),
        .bullet("Level 1: Bigger Shield", depth: 1, icon: nil),
        .bullet("Level 2: Shield a second time before you land", depth: 1, icon: nil),
        .bullet("Shelter Seltzer (New Booster)", depth: 0, icon: nil),
        .bullet("Level 1: Your Shield lingers where it ends for a second", depth: 1, icon: nil),
        .bullet("Level 2: Your Snatches raise a Shield where your hand is", depth: 1, icon: nil),
    ]
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
                    .font(Futuristic.font(size: height * 0.03))
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
                .font(Futuristic.font(size: titleSize))
                .foregroundStyle(Futuristic.lit)
                .padding(.top, bulletSize * 0.4)
        case .divider:
            Image(uiImage: Futuristic.image("rule6")).resizable().aspectRatio(contentMode: .fit)
                .colorMultiply(Futuristic.line)
                .frame(width: width * 0.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, bulletSize * 0.5)
        case .bullet(let text, let depth, let icon):
            HStack(alignment: .center, spacing: bulletSize * 0.5) {
                Text("•").font(Futuristic.font(size: bulletSize)).foregroundStyle(Futuristic.line)
                if let icon {
                    UpdatesIcon(flow: flow, icon: icon)
                        .frame(width: bulletSize * UpdatesView.iconLines, height: bulletSize * UpdatesView.iconLines)
                }
                Text(text)
                    .font(Futuristic.font(size: bulletSize))
                    .foregroundStyle(Futuristic.line)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, CGFloat(depth) * bulletSize * 2)
        }
    }
}

/// A bullet's moving icon: the shield's whole frames round and round, or the player spinning
/// with the ball, in the first side's look.
struct UpdatesIcon: View {
    @ObservedObject var flow: FlowState
    let icon: UpdatesNotes.Icon
    @State private var shieldFrames: [UIImage] = []

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
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
                        // The figure's canvas with its margin, fitted to the icon.
                        let pixel = geometry.size.height / (48 + 2 * CustomizeFigure.margin) * 1.6
                        CustomizeFigure(portrait: shown.portrait, look: flow.scene.playerLook(0), pixel: pixel, mirrored: false,
                                        headNudge: shown.headNudge, headScale: shown.headScale, ball: shown.ball, overBall: shown.overBall)
                            .frame(width: (48 + 2 * CustomizeFigure.margin) * pixel, height: (48 + 2 * CustomizeFigure.margin) * pixel)
                            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                }
            }
        }
        .onAppear { if icon == .shield, shieldFrames.isEmpty { shieldFrames = flow.scene.updatesShieldFrames() } }
    }
}
