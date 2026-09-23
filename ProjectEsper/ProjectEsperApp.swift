import SpriteKit
import SwiftUI

@main
struct ProjectEsperApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .preferredColorScheme(.dark)
                .phoneChrome()
        }
    }
}

struct GameView: View {
    @StateObject private var flow = FlowState()

    /// The world with its glow at the bottom; the dark material over it while a screen
    /// is up; the HUD's own view over that, so nothing in it glows and the screens sit on
    /// the material; and the title on top of everything.
    var body: some View {
        ZStack {
            MetalGameView(scene: flow.scene)
                .ignoresSafeArea()
            if flow.veiled {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .environment(\.colorScheme, .dark)
                    .transition(.opacity)
            }
            HudView(scene: flow.scene)
                .ignoresSafeArea()
            if flow.showsTitle {
                TitleOverlay(flow: flow, net: flow.net)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: flow.showsTitle)
        .animation(.easeOut(duration: 0.25), value: flow.veiled)
    }
}

extension View {
    /// The phone's chrome out of the way: no status bar, no home indicator, and the
    /// edge swipes held off. Nothing to do on the TV.
    @ViewBuilder
    func phoneChrome() -> some View {
        #if os(iOS)
        self.statusBarHidden()
            .persistentSystemOverlays(.hidden)
            .defersSystemGestures(on: .all)
        #else
        self
        #endif
    }
}
