import SwiftUI

/// The game and what its scene tells the SwiftUI layer: whether the title is up, whether
/// a screen wants the dark material under it, and what to do when the title's button is
/// pressed.
@MainActor
final class FlowState: ObservableObject {
    let scene = GameScene()
    let net = GameCenter()
    @Published var showsTitle = true
    @Published var veiled = false
    var startSeries: (() -> Void)?

    init() {
        scene.flowState = self
    }
}

/// The title screen, over the Metal view on a dark ultra-thin material so the court shows
/// through it: the name, BEST OF 7 against the computer, and MULTIPLAYER, which opens
/// Game Center's matchmaker for a best of seven against another phone, with Game
/// Center's word lettered under it.
struct TitleOverlay: View {
    @ObservedObject var flow: FlowState
    @ObservedObject var net: GameCenter

    private var busy: Bool {
        switch net.state {
        case .signingIn, .finding, .connecting, .connected: true
        default: false
        }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 32) {
                Image(uiImage: TitleText.image("PROJECT ESPER", size: 56))
                Button {
                    flow.startSeries?()
                } label: {
                    Image(uiImage: TitleText.image("BEST OF 7", size: 28))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                VStack(spacing: 10) {
                    Button {
                        net.findMatch()
                    } label: {
                        Image(uiImage: TitleText.image("MULTIPLAYER", size: 28))
                            .opacity(busy ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    if let caption = net.state.caption {
                        Text(caption)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if net.state == .finding {
                        Button {
                            net.cancelFinding()
                        } label: {
                            Image(uiImage: TitleText.image("CANCEL", size: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { net.signIn() }
    }
}
