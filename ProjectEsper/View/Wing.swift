import SpriteKit

/// A wing in the manner of Mithos's in Tales of Symphonia: not a drawn wing but a fan of
/// separate glowing feather shapes floating behind the shoulder. It flaps while the body
/// runs, dissolves when it stops, and sweeps once on a double jump.
final class Wing: SKNode {
    private static let featherCount = 5
    /// The fan is a sideways V with its point at the shoulder: the middle feather goes
    /// straight back, the top and bottom ones furthest back and up or down. Angles from
    /// straight back in radians, and where each feather's base sits, lowest feather first.
    private static let spread: [CGFloat] = [-0.7, -0.35, 0, 0.35, 0.7]
    private static let bases: [CGPoint] = [
        CGPoint(x: -12, y: -5), CGPoint(x: -8, y: -1), CGPoint(x: -5, y: 2), CGPoint(x: -8, y: 5), CGPoint(x: -12, y: 9),
    ]
    private static let flapsPerSecond: CGFloat = 2.5

    private var feathers: [SKSpriteNode] = []
    private var phase: CGFloat = 0
    private var strength: CGFloat = 0
    /// Frames left of the double-jump sweep, 0 when none.
    private var flourish = 0
    private static let flourishFrames = 20

    init(colour: SKColor, texture: SKTexture) {
        super.init()
        for index in 0..<Wing.featherCount {
            let feather = SKSpriteNode(texture: texture)
            feather.size = CGSize(width: 6, height: 18)
            feather.anchorPoint = CGPoint(x: 0.5, y: 0.1)
            feather.color = Wing.tint(colour, by: CGFloat(index - 2) * 0.04)
            feather.colorBlendFactor = 1
            feather.blendMode = .add
            feather.alpha = 0
            addChild(feather)
            feathers.append(feather)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The colour with its hue turned by `turn`, for a fan that isn't one flat colour.
    private static func tint(_ colour: SKColor, by turn: CGFloat) -> SKColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        colour.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return SKColor(hue: (hue + turn + 1).truncatingRemainder(dividingBy: 1), saturation: saturation * 0.8, brightness: 1, alpha: 1)
    }

    /// One hard sweep, for the double jump.
    func sweep() {
        flourish = Wing.flourishFrames
        strength = 1
    }

    /// Once a frame. `running` keeps the flap going; anything else lets it dissolve.
    /// `facing` is +1 for right, and the wing hangs off the back.
    func step(running: Bool, facing: CGFloat) {
        xScale = -facing
        if flourish > 0 {
            flourish -= 1
            let t = 1 - CGFloat(flourish) / CGFloat(Wing.flourishFrames)
            let eased = t * t * (3 - 2 * t)
            // Raised and wide, then swept down and out away from the body.
            let swing = 0.5 - eased * 1.5
            for (index, feather) in feathers.enumerated() {
                let base = Wing.bases[index]
                feather.zRotation = -.pi / 2 + Wing.spread[index] * (1.3 - eased * 0.5) + swing
                feather.position = CGPoint(x: base.x * (1 + eased * 0.8), y: base.y - eased * 10)
                feather.alpha = (1 - t) * 0.9
                feather.setScale(1.3 - eased * 0.3)
            }
            return
        }
        if running {
            strength = min(strength + 0.1, 1)
            phase += 2 * .pi * Wing.flapsPerSecond / 60
        } else {
            strength = max(strength - 0.06, 0)
        }
        let flap = sin(phase)
        for (index, feather) in feathers.enumerated() {
            let base = Wing.bases[index]
            let lift = running ? 0 : (1 - strength) * 6
            feather.zRotation = -.pi / 2 + Wing.spread[index] * (0.9 + flap * 0.3) + flap * 0.3
            feather.position = CGPoint(x: base.x * (1 + flap * 0.15), y: base.y + lift)
            feather.alpha = strength * 0.7
            feather.setScale(1)
        }
    }
}
