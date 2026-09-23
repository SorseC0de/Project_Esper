import SpriteKit
import SwiftUI

@main
struct ProjectEsperApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}

struct GameView: View {
    @StateObject private var flow = FlowState()

    var body: some View {
        ZStack {
            MetalGameView(flow: flow)
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .defersSystemGestures(on: .all)
            if flow.showsTitle {
                TitleOverlay(flow: flow)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: flow.showsTitle)
    }
}
