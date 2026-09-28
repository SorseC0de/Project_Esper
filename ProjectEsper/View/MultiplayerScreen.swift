import GameKit
import SwiftUI

/// The game's own multiplayer screen, in place of Game Center's sheet, doing what it did:
/// play now (matched with anyone looking), or invite a friend from the Game Center friends
/// list and hear back, and the wait for either, cancellable. Full screen on the screens'
/// ground, the title's lettering and plates, the cursor's plate gold.
struct MultiplayerScreen: View {
    @ObservedObject var flow: FlowState
    @ObservedObject var net: GameCenter
    @ObservedObject private var tuning = UITuning.shared
    private func scale(_ part: UIPart) -> CGFloat { tuning.scale(.title, part) }

    var body: some View {
        ZStack {
            // Full screen, on the screens' ground.
            Color(rgb: UIColourPicks.ground).ignoresSafeArea()
            VStack(spacing: 18 * scale(.buttons)) {
                Image(uiImage: TitleText.image("MULTIPLAYER", size: 56 * scale(.titles)))
                content
                if let caption = net.state.caption {
                    Text(caption)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        switch net.state {
        case .finding, .connecting:
            waiting
        default:
            if flow.multiplayerPage == .friends { friendsList } else { menu }
        }
    }

    private var menu: some View {
        VStack(spacing: 10 * scale(.buttons)) {
            plated("PLAY NOW", piece: .buttonBlue, item: .playNow)
            plated("INVITE A FRIEND", piece: .buttonBlue, item: .inviteFriend)
            plated("BACK", piece: .buttonPlum, item: .back)
        }
    }

    private var friendsList: some View {
        VStack(spacing: 10 * scale(.buttons)) {
            if let note = net.friendsNote { line(note) }
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 6 * scale(.buttons)) {
                        ForEach(net.friends, id: \.gamePlayerID) { friend in
                            plated(friend.displayName.uppercased(), piece: .buttonBlack, item: .friend(friend.gamePlayerID), size: 18)
                                .id(friend.gamePlayerID)
                        }
                    }
                }
                .frame(maxHeight: 180 * scale(.buttons))
                .onChange(of: flow.multiplayerCursor) {
                    // The pad's cursor kept in sight down a long list.
                    if case .friend(let id) = flow.multiplayerSelection { withAnimation { reader.scrollTo(id) } }
                }
            }
            plated("BACK", piece: .buttonPlum, item: .back)
        }
    }

    /// The search or the invite, and whoever was invited with their answer.
    private var waiting: some View {
        VStack(spacing: 10 * scale(.buttons)) {
            ForEach(net.invited, id: \.gamePlayerID) { friend in
                line("\(friend.displayName.uppercased()): \(answer(net.answers[friend.gamePlayerID] ?? .waiting))")
            }
            plated("CANCEL", piece: .buttonPlum, item: .cancel)
        }
    }

    private func answer(_ answer: GameCenter.InviteAnswer) -> String {
        switch answer {
        case .waiting: "INVITED"
        case .accepted: "ON THEIR WAY"
        case .declined: "CAN'T PLAY"
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 0, x: 1, y: 1)
    }

    /// A lettered button on a plate at the title's sizes; under the cursor, gold, a little
    /// bigger, the lettering's lower half lit.
    private func plated(_ text: String, piece: UIPiece, item: FlowState.MultiplayerItem, size: CGFloat = 24) -> some View {
        let lit = flow.multiplayerSelection == item
        let plate = lit ? UIPiece.buttonGold : piece
        let textSize = size * scale(.text)
        let rise = tuning.textRise
        let shift = TitleText.dropShift(size: textSize) * rise
        return Button { flow.activate(item) } label: {
            Image(uiImage: TitleText.image(text, size: textSize, lit: lit))
                .offset(x: -shift, y: -(plate.faceRise * scale(.buttons) * rise + shift))
                .frame(width: 260 * scale(.buttons), height: 50 * scale(.buttons))
                .background(plate.image(corners: scale(.buttons)))
        }
        .buttonStyle(.plain)
        .scaleEffect(lit ? TitleOverlay.cursorGrowth : 1)
        .noSystemFocus()
    }
}
