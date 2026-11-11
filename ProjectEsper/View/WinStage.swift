import CoreGraphics
import EsperSim
import SwiftUI

/// What the winner does on the win screen, looping. More to come; the taunt with the ball first.
/// The Spin Move's, for the updates screen's icon.
enum WinPose: Equatable {
    case taunt, spin

    var animation: EsperSim.Animation {
        switch self {
        case .taunt: .taunt
        case .spin: .spinBall
        }
    }
    var framesPerSecond: Double {
        switch self {
        case .taunt: 15
        case .spin: Double(SpinRules.sheetFramesPerSecond)
        }
    }
    var holdsBall: Bool {
        switch self {
        case .taunt, .spin: true
        }
    }
}

/// Who won and how they show it, for the win screen's stage.
struct WinFigure: Equatable {
    let player: Int
    let pose: WinPose
}

/// The win screen's top: the winner on the customize screen's projector, its halo over them,
/// looping their pose with the ball in hand. Laid out in the HUD's points, as the win screen's
/// box and options under it are (`WinScreen`), and drawn under the HUD.
struct WinStage: View {
    @ObservedObject var flow: FlowState
    let figure: WinFigure

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let scale = HudScene.scale(forHeight: size.height)
            let pixel = WinScreen.figurePixel * scale
            // The customize screen's art pixel against its player's: the projector and halo in proportion.
            let base = pixel / CustomizeScreen.playerScale
            let projectorPixel = base * CustomizeScreen.projectorScale
            // The ring, in the HUD's points from the middle, y up, as a point in this view.
            let ring = CGPoint(x: size.width / 2, y: size.height / 2 - WinScreen.ringY * scale)
            let haloSize = CGSize(width: CustomizeLayout.haloShare.width / CustomizeScreen.artPixelShare * base,
                                  height: CustomizeLayout.haloShare.height / CustomizeLayout.aspect / CustomizeScreen.artPixelShare * base)
            let haloMiddle = CGPoint(x: ring.x, y: ring.y - haloSize.height * CustomizeScreen.ringShare + haloSize.height / 2)
            let projectorAt = CGPoint(x: ring.x, y: ring.y - CustomizeScreen.projectorY * base)
            let lens = projectorAt.y + (CustomizeScreen.lensRow - 32) * projectorPixel
            let figureMiddle = lens - (CustomizeScreen.feetRow - 24) * pixel - CustomizeScreen.playerY * base
            let glow = flow.scene.playerLook(figure.player).glow
            ZStack {
                if let projector = CustomizeArt.projector(glow), let lit = CustomizeArt.projectorEnergy(glow) {
                    ZStack {
                        Image(uiImage: projector).resizable().interpolation(.none)
                        Image(uiImage: lit).resizable().interpolation(.none)
                            .blur(radius: projectorPixel * 3)
                            .blendMode(.plusLighter)
                            .opacity(CustomizeArt.glowStrength)
                    }
                    .frame(width: 64 * projectorPixel, height: 64 * projectorPixel)
                    .position(projectorAt)
                }
                Image(uiImage: UIImage(named: "customize_p1_halo") ?? UIImage()).resizable()
                    .colorMultiply(Color(rgb: glow))
                    .frame(width: haloSize.width, height: haloSize.height)
                    .energyGlow(radius: haloSize.width * 0.02)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: CustomizeScreen.haloFadeEnd)],
                                         startPoint: .top, endPoint: .bottom))
                    .position(haloMiddle)
                TimelineView(.animation) { timeline in
                    let frameCount = figure.pose.animation.frameCount
                    let frame = Int(timeline.date.timeIntervalSinceReferenceDate * figure.pose.framesPerSecond) % max(frameCount, 1)
                    if let shown = flow.scene.winPortrait(player: figure.player, pose: figure.pose, frame: frame) {
                        CustomizeFigure(portrait: shown.portrait, look: flow.scene.playerLook(figure.player), pixel: pixel, mirrored: false,
                                        headNudge: shown.headNudge, headScale: shown.headScale, ball: shown.ball, overBall: shown.overBall, overBallLine: shown.overBallLine)
                            .frame(width: (48 + 2 * CustomizeFigure.margin) * pixel, height: (48 + 2 * CustomizeFigure.margin) * pixel)
                            .position(x: ring.x, y: figureMiddle)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
