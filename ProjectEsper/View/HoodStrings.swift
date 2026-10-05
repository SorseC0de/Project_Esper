import SpriteKit

/// A hood's two strings, drawn here rather than on the sprite: chains of whole art pixels off
/// the hood, each pixel a point that moves as a cord does and is drawn snapped to the hood's
/// pixel grid, over the body. On the hooded head they hang and swing, or, Super Smoothie flying,
/// stream out behind; off FloState's hood they float as if held up (Shenron's whiskers), one
/// back, the far one forward, shorter and curling more, waving along their length and trailing
/// when the body moves.
final class HoodStrings {
    /// One string's floating line: which way out of the hood (back is -1 across), and its wave,
    /// growing to `wave` pixels at the tip, `waveStep` radians a pixel apart along it.
    struct Strand {
        var length: Int
        var direction: CGVector = CGVector(dx: -1, dy: 0)
        var wave: CGFloat = 2.5
        var waveStep = 0.7
    }

    struct Style {
        /// The two strings, the near one first.
        var strands: [Strand]
        /// Pull down a frame, in art pixels.
        var gravity: CGFloat
        /// Floating: drawn each frame toward its waving line, this share of the way.
        var floatPull: CGFloat
        /// How much of last frame's motion carries on.
        var carry: CGFloat
    }

    /// Hanging: five pixels each. Streaming: twenty each, both straight back, level with where
    /// they start (shorter, they settled over the torso and were lost in its glow). FloState: the
    /// near one so, the far one forward, twelve, its wave twice as tight and bigger.
    static let hanging = Style(strands: [Strand(length: 5), Strand(length: 5)], gravity: 0.25, floatPull: 0, carry: 0.85)
    static let streaming = Style(strands: [Strand(length: 20), Strand(length: 20)], gravity: 0, floatPull: 0.08, carry: 0.9)
    static let floState = Style(strands: [Strand(length: 20), Strand(length: 12, direction: CGVector(dx: 1, dy: 0), wave: 4, waveStep: 1.4)],
                                gravity: 0, floatPull: 0.08, carry: 0.9)
    /// Where each string starts on the hooded head's 48-pixel canvas, column and row from the top left.
    static let anchorPixels = [CGPoint(x: 23, y: 23), CGPoint(x: 26, y: 23)]
    /// The floating strings' waves a second.
    static let floatWavesPerSecond = 0.6
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
    static func anchors(on hood: SKSpriteNode, scale: CGFloat) -> [CGPoint] {
        let canvas: CGFloat = 48
        return anchorPixels.map { pixel in
            let local = CGPoint(x: (pixel.x + 0.5 - canvas * hood.anchorPoint.x) * scale * (hood.xScale < 0 ? -1 : 1),
                                y: (canvas - pixel.y - 0.5 - canvas * hood.anchorPoint.y) * scale)
            let turn = hood.zRotation
            return CGPoint(x: hood.position.x + local.x * cos(turn) - local.y * sin(turn),
                           y: hood.position.y + local.x * sin(turn) + local.y * cos(turn))
        }
    }

    /// A frame on: the strings follow their anchors and are drawn, in `plain` with `accent`
    /// second from the tip, at `z`.
    func step(anchors: [CGPoint], style: Style, facing: CGFloat, scale: CGFloat, time: Double,
              plain: SKColor, accent: SKColor, z: CGFloat) {
        let segment = scale
        var shown: [(CGPoint, Bool)] = []
        for (string, anchor) in anchors.enumerated() where string < style.strands.count {
            let strand = style.strands[string]
            // New, a different length, or the anchor gone too far at once: laid straight down.
            if points[string].count != strand.length || HoodStrings.gap(points[string][0], anchor) > 24 * scale {
                points[string] = (0..<strand.length).map { CGPoint(x: anchor.x, y: anchor.y - CGFloat($0) * segment) }
                previous[string] = points[string]
            }
            var chain = points[string]
            let was = previous[string]
            previous[string] = chain
            chain[0] = anchor
            let direction = CGVector(dx: strand.direction.dx * facing, dy: strand.direction.dy)
            let across = CGVector(dx: -direction.dy, dy: direction.dx)
            for index in 1..<chain.count {
                var point = chain[index]
                point.x += (point.x - was[index].x) * style.carry
                point.y += (point.y - was[index].y) * style.carry - style.gravity * scale
                if style.floatPull > 0 {
                    // Toward a waving line out of the hood, the wave growing to the tip.
                    let along = CGFloat(index) * segment
                    let share = CGFloat(index) / CGFloat(chain.count - 1)
                    let wave = CGFloat(sin(time * 2 * .pi * HoodStrings.floatWavesPerSecond - Double(index) * strand.waveStep + Double(string) * .pi / 2))
                        * strand.wave * scale * share
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
