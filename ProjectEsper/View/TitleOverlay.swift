import SwiftUI

/// The game and what its scene tells the SwiftUI layer: whether the title is up, whether
/// a screen wants the dark material under it, and what to do when the title's button is
/// pressed.
final class FlowState: ObservableObject {
    let scene = GameScene()
    @Published var showsTitle = true
    @Published var veiled = false
    var startSeries: (() -> Void)?

    init() {
        scene.flowState = self
    }
}

/// The title screen, over the Metal view on a dark ultra-thin material so the court shows
/// through it: the name, BEST OF 7, and MULTIPLAYER greyed until it's open.
struct TitleOverlay: View {
    @ObservedObject var flow: FlowState

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
                Image(uiImage: TitleText.image("MULTIPLAYER", size: 28))
                    .opacity(0.35)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
