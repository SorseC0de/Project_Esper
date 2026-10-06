import SpriteKit
import SwiftUI
import UIKit

/// Title lettering: the system's rounded face at its heaviest, white over the palette's
/// light blue split at the letters' middle, a thick black outline walked round a ring, and
/// a black drop to the south-east, CardCourt's styling in a rounder face. Drawn once per
/// string and size into a texture, at the screen's scale.
enum TitleText {
    /// The title's A/B, kept between launches: B letters it in Bigdex.
    nonisolated(unsafe) static var bigdex = UserDefaults.standard.bool(forKey: bigdexKey) {
        didSet { UserDefaults.standard.set(bigdex, forKey: bigdexKey) }
    }
    private static let bigdexKey = "esper.titleText.bigdex"

    /// SF Pro Rounded Black, italic when asked; with `bigdex`, Bigdex.
    static func font(size: CGFloat, italic: Bool) -> UIFont {
        if bigdex, let face = UIFont(name: "Bigdex", size: size) { return face }
        let base = UIFont.systemFont(ofSize: size, weight: .black)
        var descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        if italic { descriptor = descriptor.withSymbolicTraits(.traitItalic) ?? descriptor }
        return UIFont(descriptor: descriptor, size: size)
    }
    /// Times the screen's scale the lettering is rendered at, so a HUD scaled up for a
    /// big screen stays crisp. The scene sets it from its HUD scale.
    nonisolated(unsafe) static var renderScale: CGFloat = 1
    /// The lower half's fill, `UIColourPicks.letters`; `lit` on a gold plate, the cursor's.
    private static func lowerColour(lit: Bool) -> UIColor {
        let fill = lit ? UIColourPicks.litLetters : UIColourPicks.letters
        return UIColor(red: CGFloat((fill >> 16) & 0xFF) / 255, green: CGFloat((fill >> 8) & 0xFF) / 255,
                       blue: CGFloat(fill & 0xFF) / 255, alpha: 1)
    }
    /// The outline and the drop, as shares of the text size, and the steps round the ring.
    private static let stroke: CGFloat = 0.09
    private static let drop: CGFloat = 0.12
    private static let steps = 16
    nonisolated(unsafe) private static var cache: [String: SKTexture] = [:]
    nonisolated(unsafe) private static var images: [String: UIImage] = [:]

    /// The title's small switches' face, as the lettering's A/B has it.
    static func switchFont(size: CGFloat) -> Font {
        bigdex ? .custom("Bigdex", size: size) : .system(size: size, weight: .heavy, design: .rounded)
    }

    static func texture(_ text: String, size: CGFloat, italic: Bool = false, lit: Bool = false) -> SKTexture {
        let key = "\(size)|\(italic)|\(renderScale)|\(lit)|\(bigdex)|\(text)"
        if let texture = cache[key] { return texture }
        let texture = SKTexture(image: image(text, size: size, italic: italic, lit: lit))
        cache[key] = texture
        return texture
    }

    /// The lettering as an image, for the SwiftUI layer.
    static func image(_ text: String, size: CGFloat, italic: Bool = false, lit: Bool = false) -> UIImage {
        let key = "\(size)|\(italic)|\(renderScale)|\(lit)|\(bigdex)|\(text)"
        if let image = images[key] { return image }
        let font = font(size: size, italic: italic)
        // The fill splits at the middle of the capitals.
        let image = render(text, font: font, size: size, upper: .white, lower: lowerColour(lit: lit), outline: .black) { $0 + font.ascender - font.capHeight / 2 }
        images[key] = image
        return image
    }

    /// CardCourt's 2X mark as it is there, Avenir Next Condensed Heavy split at the middle of
    /// its line, in palette colours by index.
    static func markTexture(_ text: String, size: CGFloat, upper: Int, lower: Int, outline: Int) -> SKTexture {
        let key = "mark|\(size)|\(renderScale)|\(upper)|\(lower)|\(outline)|\(text)"
        if let texture = cache[key] { return texture }
        let font = UIFont(name: "AvenirNextCondensed-Heavy", size: size) ?? font(size: size, italic: false)
        func colour(_ index: Int) -> UIColor {
            let rgb = PixelPalette.colours[index]
            return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
        let line = (text as NSString).size(withAttributes: [.font: font]).height
        let image = render(text, font: font, size: size, upper: colour(upper), lower: colour(lower), outline: colour(outline)) { $0 + line / 2 }
        let texture = SKTexture(image: image)
        cache[key] = texture
        return texture
    }

    /// The lettering drawn: the outline walked round a ring, again dropped to the south-east,
    /// and the fill, `upper` over `lower` split at `middle` of the line's top.
    private static func render(_ text: String, font: UIFont, size: CGFloat, upper: UIColor, lower: UIColor, outline: UIColor,
                               middle: (CGFloat) -> CGFloat) -> UIImage {
        let measured = (text as NSString).size(withAttributes: [.font: font])
        let ring = size * stroke
        let shadow = size * drop
        let pad = ring + shadow + 2
        let canvas = CGSize(width: ceil(measured.width + pad * 2), height: ceil(measured.height + pad * 2))
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale * renderScale
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let origin = CGPoint(x: pad, y: pad)
            func draw(_ colour: UIColor, offset: CGPoint) {
                (text as NSString).draw(at: CGPoint(x: origin.x + offset.x, y: origin.y + offset.y),
                                        withAttributes: [.font: font, .foregroundColor: colour])
            }
            for centre in [CGPoint(x: shadow, y: shadow), .zero] {
                for step in 0..<steps {
                    let angle = Double(step) * 2 * .pi / Double(steps)
                    draw(outline, offset: CGPoint(x: centre.x + cos(angle) * ring, y: centre.y + sin(angle) * ring))
                }
            }
            let middle = middle(origin.y)
            let cg = context.cgContext
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: 0, width: canvas.width, height: middle))
            draw(upper, offset: .zero)
            cg.restoreGState()
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: middle, width: canvas.width, height: canvas.height - middle))
            draw(lower, offset: .zero)
            cg.restoreGState()
        }
    }

    /// How far lettering of `size` reads off its middle, its black drop falling to the
    /// south-east: half that drop, to take off when centring it on something.
    static func dropShift(size: CGFloat) -> CGFloat { size * drop / 2 }

    /// A sprite of the lettering, sized in points.
    static func node(_ text: String, size: CGFloat, italic: Bool = false) -> SKSpriteNode {
        let texture = texture(text, size: size, italic: italic)
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: texture.size().width / renderScale, height: texture.size().height / renderScale)
        return node
    }

    /// Swaps a sprite's lettering, keeping its place.
    static func set(_ node: SKSpriteNode, to text: String, size: CGFloat, italic: Bool = false, lit: Bool = false) {
        let texture = texture(text, size: size, italic: italic, lit: lit)
        node.texture = texture
        node.size = CGSize(width: texture.size().width / renderScale, height: texture.size().height / renderScale)
    }
}
