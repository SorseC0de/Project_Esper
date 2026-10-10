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
            // The stage preview's name over its big panel, low in it, in FLO lettering.
            if let title = flow.previewTitle {
                GeometryReader { geometry in
                    let fit = MangaPage.fit(in: geometry.size)
                    let box = MangaPage.bounds(MangaPage.bigPanel)
                    FloText(title, height: geometry.size.height * MangaPage.titleHeight, maxWidth: box.width * fit.scale * 0.85)
                        .position(x: fit.origin.x + box.midX * fit.scale, y: fit.origin.y + (box.maxY - box.height * 0.16) * fit.scale)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.scale(scale: 1.4).combined(with: .opacity))
            }
            // BALL OUT on the Z card, its bars' streaks the customize screen's top and bottom lines'.
            if let call = flow.ballOutCall, !flow.veiled {
                GeometryReader { geometry in
                    ZCardView(upperStreaks: Color(rgb: EsperPalette.gold.light), lowerStreaks: Color(rgb: EsperPalette.blue.light),
                              onFinished: { if flow.ballOutCall == call { flow.ballOutCall = nil } }) {
                        FloText("BALL OUT!!!", height: ZCardStyle.bar(across: geometry.size).height * ZCardStyle.wordsHeight)
                    }
                }
                .id(call)
                .ignoresSafeArea()
            }
            if flow.showsTitle {
                TitleOverlay(flow: flow, net: flow.net)
                    .transition(.opacity)
            }
            if flow.zonesHud != nil, !flow.showsTitle, !flow.settingsOpen {
                ZonesOverlay(flow: flow)
            }
            if flow.customizeOpen {
                CustomizeScreen(flow: flow)
                    .transition(.opacity)
            }
            if flow.multiplayerOpen {
                MultiplayerScreen(flow: flow, net: flow.net)
                    .transition(.opacity)
            }
            if flow.settingsOpen {
                SettingsScreen(flow: flow)
                    .transition(.opacity)
            }
            if DebugUI.enabled, flow.tuningOpen {
                UITuningPanel(flow: flow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
            }
            // The curtain between screens, over everything, taking the touches while it's down.
            TransitionCurtain(transition: flow.curtainStyle, cover: flow.curtain)
        }
        .animation(.easeOut(duration: 0.25), value: flow.showsTitle)
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: flow.previewTitle)
        .animation(.easeOut(duration: 0.25), value: flow.veiled)
        .animation(.easeOut(duration: 0.2), value: flow.multiplayerOpen)
        .animation(.easeOut(duration: 0.2), value: flow.settingsOpen)
        .animation(.easeOut(duration: 0.2), value: flow.customizeOpen)
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
