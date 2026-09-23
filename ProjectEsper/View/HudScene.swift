import SpriteKit
import SwiftUI

/// The HUD's own scene: the controls, the lettering, the drinks and the screens, drawn by
/// a transparent SpriteKit view laid over the Metal view, so none of it goes through the
/// glow. Its size is the view's in points and its origin the centre, y up, so the game
/// scene lays the HUD out in it exactly as it laid it out under the camera.
final class HudScene: SKScene {
    let hud = SKNode()

    override init() {
        super.init(size: CGSize(width: 640, height: 288))
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = .clear
        hud.zPosition = 100
        addChild(hud)
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// The view that shows it. It sits on top, so every touch lands here and goes to the game
/// scene's controls in points from the top-left, as the Metal view used to hand them over.
final class HudSKView: SKView {
    weak var game: GameScene?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            game?.touchBegan(touch, at: touch.location(in: self), viewSize: bounds.size)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            game?.touchMoved(touch, to: touch.location(in: self), viewSize: bounds.size)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        touches.forEach { game?.touchEnded($0) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touches.forEach { game?.touchEnded($0) }
    }
}

struct HudView: UIViewRepresentable {
    let scene: GameScene

    func makeUIView(context: Context) -> HudSKView {
        let view = HudSKView(frame: .zero)
        view.allowsTransparency = true
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        view.preferredFramesPerSecond = 60
        view.ignoresSiblingOrder = true
        view.game = scene
        view.presentScene(scene.hudScene)
        return view
    }

    func updateUIView(_ uiView: HudSKView, context: Context) {}
}
