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
    @ObservedObject private var tuning = UITuning.shared

    /// The world with its glow at the bottom; the royal blue over it while a screen is up,
    /// opaque; the HUD's own view over that, so nothing in it glows and the screens sit on
    /// the material; and the title on top of everything.
    var body: some View {
        ZStack {
            MetalGameView(scene: flow.scene)
                .ignoresSafeArea()
            if flow.veiled {
                // The screens' ground: the royal blue, dark, the world just showing through.
                // Flat: the win screen on black's second, the rest on purple's last; the
                // Greateraid pick and wait on black, shaded.
                let ground: (top: RGB, bottom: RGB) = flow.blackGround ? (EsperPalette.black.light, EsperPalette.black.shadow)
                    : (flow.winGround ? (UIColourPicks.winGround, UIColourPicks.winGround) : (UIColourPicks.ground, UIColourPicks.ground))
                LinearGradient(colors: [Color(rgb: ground.top), Color(rgb: ground.bottom)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            HudView(scene: flow.scene)
                .ignoresSafeArea()
            if flow.showsTitle {
                TitleOverlay(flow: flow, net: flow.net)
                    .transition(.opacity)
            }
            if flow.tuningOpen {
                UITuningPanel(flow: flow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
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
