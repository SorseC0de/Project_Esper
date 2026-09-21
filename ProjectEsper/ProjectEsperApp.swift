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
    var body: some View {
        MetalGameView()
            .ignoresSafeArea()
            .persistentSystemOverlays(.hidden)
            .defersSystemGestures(on: .all)
    }
}
