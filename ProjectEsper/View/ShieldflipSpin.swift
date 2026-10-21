import CoreGraphics
import EsperSim

/// The Shieldflip drawn as a spin: the spin sheet looping, the body turned once backward about its
/// middle over the flip's arc, upright at both ends (Zero Suit Samus's flipjump). The tumble after
/// it keeps the backflip.
enum ShieldflipSpin {
    /// The sheet frame shown in the flip, nil otherwise.
    static func frame(_ player: Player) -> AnimationFrame? {
        guard player.state == .flipJump else { return nil }
        return AnimationFrame(.spin, player.stateTimer * SpinRules.sheetFramesPerSecond / 60 % Animation.spin.frameCount)
    }

    /// The backward turn over the flip, in radians: one whole turn by the arc's end.
    static func turn(_ player: Player) -> CGFloat? {
        guard player.state == .flipJump else { return nil }
        let share = min(CGFloat(player.stateTimer) / CGFloat(max(ShieldRules.flipFrames, 1)), 1)
        return 2 * .pi * share * CGFloat(player.facing.sign)
    }
}
