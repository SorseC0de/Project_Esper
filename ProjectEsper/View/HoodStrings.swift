import SpriteKit

/// A hood's two strings, drawn here rather than on the sprite: chains of whole art pixels off
/// the hood, each pixel a point that moves as a cord does and is drawn snapped to the hood's
/// pixel grid, over the body. Up, on the hooded head, they hang and swing; down, off FloState's
/// hood, they float as if held up, waving along their length, and trail when the body moves.
final class HoodStrings {
    struct Style {
        /// Pixels a string, the first pinned to the hood.
        var length: Int
        /// Pull down a frame, in art pixels.
        var gravity: CGFloat
        /// Floating: drawn each frame toward a waving line out of the hood, this share of the way.
        var floatPull: CGFloat
        /// How much of last frame's motion carries on.
        var carry: CGFloat
    }

    /// Up: five pixels, hanging. Down: nine, floating.
    static let up = Style(length: 5, gravity: 0.25, floatPull: 0, carry: 0.85)
    static let down = Style(length: 9, gravity: 0, floatPull: 0.08, carry: 0.9)
    /// Where each string starts on the hood's 48-pixel canvas, column and row from the top left:
    /// the hooded head's, and the hood down's.
    static let upAnchors = [CGPoint(x: 23, y: 23), CGPoint(x: 26, y: 23)]
    static let downAnchors = [CGPoint(x: 23, y: 24), CGPoint(x: 27, y: 24)]
    /// The floating strings' line: back from the body and down, its wave growing to this many
    /// pixels at the tip, this many times a second, this far apart along it (radians a pixel).
    static let floatDirection = CGVector(dx: -0.7, dy: -0.7)
    static let floatWave: CGFloat = 2.5
    static let floatWavesPerSecond = 0.6
    static let floatWaveStep = 0.7
    /// The pixel second from the tip is palette 37, as the hood's shading is.
    static let accentFromTip = 2

    private var points: [[CGPoint]] = [[], []]
    private var previous: [[CGPoint]] = [[], []]
    private var pixels: [SKSpriteNode] = []
    private let parent: SKNode
    private let square: SKTexture

    init(parent: SKNode, square: SKTexture) {
        self.parent = parent
        self.square = square
    }

    /// Where each string's first pixel sits, through the hood's own placing.
    static func anchors(on hood: SKSpriteNode, down: Bool, scale: CGFloat) -> [CGPoint] {
        let canvas: CGFloat = 48
        return (down ? downAnchors : upAnchors).map { pixel in
            let local = CGPoint(x: (pixel.x + 0.5 - canvas * hood.anchorPoint.x) * scale * (hood.xScale < 0 ? -1 : 1),
                                y: (canvas - pixel.y - 0.5 - canvas * hood.anchorPoint.y) * scale)
            let turn = hood.zRotation
            return CGPoint(x: hood.position.x + local.x * cos(turn) - local.y * sin(turn),
                           y: hood.position.y + local.x * sin(turn) + local.y * cos(turn))
        }
    }

    /// A frame on: the strings follow their anchors and are drawn, in `plain` with `accent`
    /// second from the tip, at `z`.
    func step(anchors: [CGPoint], down: Bool, facing: CGFloat, scale: CGFloat, time: Double,
              plain: SKColor, accent: SKColor, z: CGFloat) {
        let style = down ? HoodStrings.down : HoodStrings.up
        let segment = scale
        var shown: [(CGPoint, Bool)] = []
        for (string, anchor) in anchors.enumerated() {
            // New, a different length, or the anchor gone too far at once: laid straight down.
            if points[string].count != style.length || HoodStrings.gap(points[string][0], anchor) > 24 * scale {
                points[string] = (0..<style.length).map { CGPoint(x: anchor.x, y: anchor.y - CGFloat($0) * segment) }
                previous[string] = points[string]
            }
            var chain = points[string]
            let was = previous[string]
            previous[string] = chain
            chain[0] = anchor
            let direction = CGVector(dx: HoodStrings.floatDirection.dx * facing, dy: HoodStrings.floatDirection.dy)
            let across = CGVector(dx: -direction.dy, dy: direction.dx)
            for index in 1..<chain.count {
                var point = chain[index]
                point.x += (point.x - was[index].x) * style.carry
                point.y += (point.y - was[index].y) * style.carry - style.gravity * scale
                if style.floatPull > 0 {
                    // Toward a waving line out of the hood, the wave growing to the tip.
                    let along = CGFloat(index) * segment
                    let share = CGFloat(index) / CGFloat(chain.count - 1)
                    let wave = CGFloat(sin(time * 2 * .pi * HoodStrings.floatWavesPerSecond - Double(index) * HoodStrings.floatWaveStep + Double(string) * .pi / 2))
                        * HoodStrings.floatWave * scale * share
                    let target = CGPoint(x: anchor.x + direction.dx * along + across.dx * wave,
                                         y: anchor.y + direction.dy * along + across.dy * wave)
                    point.x += (target.x - point.x) * style.floatPull
                    point.y += (target.y - point.y) * style.floatPull
                }
                chain[index] = point
            }
            // Each pixel a pixel from the last, out from the pinned one.
            for index in 1..<chain.count {
                let from = chain[index - 1]
                let gap = HoodStrings.gap(chain[index], from)
                guard gap > 0 else { chain[index] = CGPoint(x: from.x, y: from.y - segment); continue }
                chain[index] = CGPoint(x: from.x + (chain[index].x - from.x) / gap * segment,
                                       y: from.y + (chain[index].y - from.y) / gap * segment)
            }
            points[string] = chain
            // Snapped to the hood's grid: whole pixels from the pinned one.
            for (index, point) in chain.enumerated() {
                let snapped = CGPoint(x: anchor.x + ((point.x - anchor.x) / segment).rounded() * segment,
                                      y: anchor.y + ((point.y - anchor.y) / segment).rounded() * segment)
                shown.append((snapped, index == chain.count - HoodStrings.accentFromTip))
            }
        }
        while pixels.count < shown.count {
            let pixel = SKSpriteNode(texture: square)
            pixel.colorBlendFactor = 1
            parent.addChild(pixel)
            pixels.append(pixel)
        }
        for (index, pixel) in pixels.enumerated() {
            guard index < shown.count else { pixel.isHidden = true; continue }
            pixel.isHidden = false
            pixel.position = shown[index].0
            pixel.size = CGSize(width: segment, height: segment)
            pixel.color = shown[index].1 ? accent : plain
            pixel.zPosition = z
        }
    }

    private static func gap(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    func hide() {
        pixels.forEach { $0.isHidden = true }
        points = [[], []]
    }

    /// The strings' pixels as drawn, for the glow's mask.
    var snapshots: [BodySnapshot] {
        pixels.filter { !$0.isHidden }.compactMap { pixel in
            pixel.texture.map { BodySnapshot(texture: $0, position: pixel.position, anchor: pixel.anchorPoint, xScale: 1, size: pixel.size) }
        }
    }
}
