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
    @State private var scene = GameScene()

    var body: some View {
        SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
            .ignoresSafeArea()
            .persistentSystemOverlays(.hidden)
    }
}
