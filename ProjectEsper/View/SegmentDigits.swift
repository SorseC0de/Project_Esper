import SpriteKit
import UIKit

/// Seven-segment digits, CardCourt's shot clock's: each segment a hexagon with mitred points,
/// stopping just short of its neighbours as a real LED display's do, the lit ones in a colour
/// with a glow round them, a tight core and a wide halo, the unlit ones faint. Drawn into a
/// texture per number and colour, at the screen's scale.
enum SegmentDigits {
    enum Segment: CaseIterable {
        case a, b, c, d, e, f, g

        static func lit(for digit: Int) -> Set<Segment> {
            switch digit {
            case 0: [.a, .b, .c, .d, .e, .f]
            case 1: [.b, .c]
            case 2: [.a, .b, .g, .e, .d]
            case 3: [.a, .b, .g, .c, .d]
            case 4: [.f, .g, .b, .c]
            case 5: [.a, .f, .g, .c, .d]
            case 6: [.a, .f, .g, .e, .c, .d]
            case 7: [.a, .b, .c]
            case 8: [.a, .b, .c, .d, .e, .f, .g]
            case 9: [.a, .b, .c, .d, .f, .g]
            default: []
            }
        }
    }

    /// The glow, as CardCourt has it for a 40-point digit: its core and halo, scaled with the digit.
    private static let coreRadius: CGFloat = 3
    private static let coreStrength: CGFloat = 1
    private static let haloRadius: CGFloat = 10
    private static let haloStrength: CGFloat = 0.9
    private static let referenceHeight: CGFloat = 40
    nonisolated(unsafe) private static var cache: [String: SKTexture] = [:]

    /// `value` in at least `digits` digits, `lit` its colour, each digit `digitSize` points;
    /// the texture's size in points, its digits in the middle with `pad` round them for the glow.
    static func texture(_ value: Int, digits: Int = 2, lit: RGB, digitSize: CGSize) -> (texture: SKTexture, size: CGSize, pad: CGFloat) {
        let text = String(format: "%0\(digits)d", max(value, 0))
        let glyphs = text.compactMap(\.wholeNumberValue).map(Segment.lit(for:))
        let glow = digitSize.height / referenceHeight
        let pad = (haloRadius * glow * 2).rounded(.up)
        let spacing = digitSize.width * 0.16
        let width = CGFloat(glyphs.count) * digitSize.width + CGFloat(glyphs.count - 1) * spacing
        let size = CGSize(width: width + pad * 2, height: digitSize.height + pad * 2)
        let key = "\(text)|\(lit)|\(digitSize.width)x\(digitSize.height)|\(TitleText.renderScale)"
        if let made = cache[key] { return (made, size, pad) }
        let colour = SKColor(rgb: lit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale * TitleText.renderScale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            for (index, on) in glyphs.enumerated() {
                let origin = CGPoint(x: pad + CGFloat(index) * (digitSize.width + spacing), y: pad)
                // The unlit ones flat, then the lit ones twice more glowing, a core and a halo.
                draw(Set(Segment.allCases).subtracting(on), in: cg, at: origin, size: digitSize, colour: SKColor.white.withAlphaComponent(0.12))
                for (radius, strength) in [(haloRadius, haloStrength), (coreRadius, coreStrength)] {
                    cg.saveGState()
                    cg.setShadow(offset: .zero, blur: radius * glow * 2, color: colour.withAlphaComponent(strength).cgColor)
                    draw(on, in: cg, at: origin, size: digitSize, colour: colour)
                    cg.restoreGState()
                }
            }
        }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return (texture, size, pad)
    }

    private static func draw(_ segments: Set<Segment>, in cg: CGContext, at origin: CGPoint, size: CGSize, colour: SKColor) {
        let thickness = size.width * 0.14
        let gap = thickness * 0.09
        cg.setFillColor(colour.cgColor)
        for segment in segments {
            let box = rect(segment, in: size, t: thickness, gap: gap).offsetBy(dx: origin.x, dy: origin.y)
            guard box.width > 0, box.height > 0 else { continue }
            cg.addPath(hexagon(in: box, horizontal: box.width > box.height))
            cg.fillPath()
        }
    }

    /// Each segment's own box: the bars stop short of the posts, and the posts short of the
    /// bars above and below them. Top-down, as the renderer's y runs.
    private static func rect(_ segment: Segment, in size: CGSize, t: CGFloat, gap: CGFloat) -> CGRect {
        let midY = size.height / 2
        let barX = t + gap
        let barWidth = size.width - 2 * (t + gap)
        let upperTop = t + gap, upperBottom = midY - t / 2 - gap
        let lowerTop = midY + t / 2 + gap, lowerBottom = size.height - t - gap
        switch segment {
        case .a: return CGRect(x: barX, y: 0, width: barWidth, height: t)
        case .g: return CGRect(x: barX, y: midY - t / 2, width: barWidth, height: t)
        case .d: return CGRect(x: barX, y: size.height - t, width: barWidth, height: t)
        case .f: return CGRect(x: 0, y: upperTop, width: t, height: upperBottom - upperTop)
        case .b: return CGRect(x: size.width - t, y: upperTop, width: t, height: upperBottom - upperTop)
        case .e: return CGRect(x: 0, y: lowerTop, width: t, height: lowerBottom - lowerTop)
        case .c: return CGRect(x: size.width - t, y: lowerTop, width: t, height: lowerBottom - lowerTop)
        }
    }

    /// A hexagon filling the box, its two short edges collapsed to points.
    private static func hexagon(in rect: CGRect, horizontal: Bool) -> CGPath {
        let path = CGMutablePath()
        if horizontal {
            let half = rect.height / 2
            path.addLines(between: [CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.minX + half, y: rect.minY),
                                    CGPoint(x: rect.maxX - half, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY),
                                    CGPoint(x: rect.maxX - half, y: rect.maxY), CGPoint(x: rect.minX + half, y: rect.maxY)])
        } else {
            let half = rect.width / 2
            path.addLines(between: [CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY + half),
                                    CGPoint(x: rect.maxX, y: rect.maxY - half), CGPoint(x: rect.midX, y: rect.maxY),
                                    CGPoint(x: rect.minX, y: rect.maxY - half), CGPoint(x: rect.minX, y: rect.minY + half)])
        }
        path.closeSubpath()
        return path
    }
}
