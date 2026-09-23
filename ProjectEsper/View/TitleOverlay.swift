import SwiftUI

/// What the scene tells the SwiftUI layer: whether the title is up, and what to do when
/// its button is pressed.
final class FlowState: ObservableObject {
    @Published var showsTitle = true
    var startSeries: (() -> Void)?
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
