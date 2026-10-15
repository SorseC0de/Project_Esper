import EsperSim
import GameKit
import SwiftUI

/// The game's own multiplayer screen, in place of Game Center's sheet, doing what it did:
/// play now (matched with anyone looking), or invite a friend from the Game Center friends
/// list and hear back, and the wait for either, cancellable. Full screen in the menus' look:
/// the grid on black, the name lettered as FLO is, the modes as words with rule6 between them,
/// each choice in Futuristic_UI's frame 8, every other one turned round both ways, the cursor's
/// gold; back is the corner arrow, or B.
struct MultiplayerScreen: View {
    @ObservedObject var flow: FlowState
    @ObservedObject var net: GameCenter
    @ObservedObject private var tuning = UITuning.shared
    private func scale(_ part: UIPart) -> CGFloat { tuning.scale(.title, part) }

    /// The choices' frames against the menus' size, a list's smaller; their lettering's size.
    static let choiceScale: CGFloat = 0.8
    static let listScale: CGFloat = 0.6
    static let choiceTextSize: CGFloat = 12
    static let titleHeight: CGFloat = 15

    var body: some View {
        ZStack {
            MenuGround(glows: false).ignoresSafeArea()
            VStack(spacing: 14 * scale(.buttons)) {
                FloText("MULTIPLAYER", height: MultiplayerScreen.titleHeight * scale(.titles))
                content
                if let caption = flow.zonesOnlinePicked && flow.multiplayerPage == .menu ? net.turnNote : net.state.caption {
                    Text(caption)
                        .font(Futuristic.font(size: 12 * scale(.text)))
                        .foregroundStyle(Futuristic.line.opacity(0.8))
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
        VStack(spacing: 8 * scale(.buttons)) {
            // The mode first; the host's is played.
            HStack(spacing: 12 * scale(.buttons)) {
                ForEach(Array(FlowState.onlineModes.enumerated()), id: \.offset) { index, mode in
                    if index > 0 { rule6 }
                    modeSwitch(mode)
                }
            }
            framed(flow.zonesOnlinePicked ? "NEW MATCH" : "PLAY NOW", item: .playNow, place: 0)
            framed("INVITE A FRIEND", item: .inviteFriend, place: 1)
            if flow.zonesOnlinePicked { turnMatches }
        }
    }

    /// ZONES: this player's matches, whose turn each is on or how it ended, with the other
    /// side's name; on its turn, tapped to play, lit whole, the rest dim.
    private var turnMatches: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 4 * scale(.buttons)) {
                    ForEach(Array(net.turnMatches.enumerated()), id: \.element.matchID) { index, match in
                        framed("\(net.turnLine(for: match)) VS \(net.otherName(in: match))", item: .turnMatch(match.matchID), place: index,
                               frameScale: MultiplayerScreen.listScale, dim: !net.isLocalTurn(match))
                            .id(match.matchID)
                    }
                }
            }
            .frame(maxHeight: 150 * scale(.buttons))
            .onChange(of: flow.multiplayerCursor) {
                if case .turnMatch(let id) = flow.multiplayerSelection { withAnimation { reader.scrollTo(id) } }
            }
        }
    }

    private var friendsList: some View {
        VStack(spacing: 8 * scale(.buttons)) {
            if let note = net.friendsNote { line(note) }
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 4 * scale(.buttons)) {
                        ForEach(Array(net.friends.enumerated()), id: \.element.gamePlayerID) { index, friend in
                            framed(friend.displayName.uppercased(), item: .friend(friend.gamePlayerID), place: index, frameScale: MultiplayerScreen.listScale)
                                .id(friend.gamePlayerID)
                        }
                    }
                }
                .frame(maxHeight: 200 * scale(.buttons))
                .onChange(of: flow.multiplayerCursor) {
                    // The pad's cursor kept in sight down a long list.
                    if case .friend(let id) = flow.multiplayerSelection { withAnimation { reader.scrollTo(id) } }
                }
            }
        }
    }

    /// The search or the invite, and whoever was invited with their answer.
    private var waiting: some View {
        VStack(spacing: 8 * scale(.buttons)) {
            ForEach(net.invited, id: \.gamePlayerID) { friend in
                line("\(friend.displayName.uppercased()): \(answer(net.answers[friend.gamePlayerID] ?? .waiting))")
            }
            framed("CANCEL", item: .cancel, place: 0)
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
            .font(Futuristic.font(size: 13 * scale(.text)))
            .foregroundStyle(Futuristic.line)
    }

    private var rule6: some View {
        FuturisticPiece(name: "rule6", scale: 0.3 * scale(.buttons))
    }

    /// A mode as a word, as the title's VS CPU and VS HUMAN are: the one asked for in the blue, the
    /// rest dim, gold under the cursor.
    private func modeSwitch(_ mode: GameMode) -> some View {
        let lit = flow.multiplayerSelection == .mode(mode)
        let picked = GameScene.savedOnlineMode == mode
        let parked = GameMode.parked.contains(mode)
        return Button { flow.activate(.mode(mode)) } label: {
            Text(mode == .rounds ? "ROUNDS" : mode == .zones ? "ZONES" : "47")
                .font(Futuristic.font(size: 18 * scale(.text)))
                .foregroundStyle(lit && !parked ? Futuristic.lit : Futuristic.line.opacity(picked ? 1 : TitleOverlay.unpickedOpacity))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(parked)
        .saturation(parked ? 0 : 1)
        .opacity(parked ? TitleOverlay.parkedOpacity : 1)
        .noSystemFocus()
    }

    /// A choice in frame 8, the second, fourth and so on of a column turned round both ways.
    private func framed(_ text: String, item: FlowState.MultiplayerItem, place: Int, frameScale: CGFloat = MultiplayerScreen.choiceScale,
                        dim: Bool = false) -> some View {
        let lit = flow.multiplayerSelection == item
        let turned = place % 2 == 1
        return Button { flow.activate(item) } label: {
            FuturisticFrame(name: "8", lit: lit, scale: frameScale * scale(.buttons), mirrored: turned, upsideDown: turned) { colour in
                Text(text)
                    .font(Futuristic.font(size: MultiplayerScreen.choiceTextSize * frameScale / MultiplayerScreen.choiceScale * scale(.text)))
                    .foregroundStyle(colour)
                    .fixedSize()
            }
            .opacity(dim && !lit ? TitleOverlay.unpickedOpacity : 1)
        }
        .buttonStyle(.plain)
        .noSystemFocus()
    }
}
