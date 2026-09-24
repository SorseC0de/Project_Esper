import SpriteKit
import UIKit

/// Title lettering, as CardCourt's TwoXMark has it: Avenir Next Condensed Heavy, white
/// over light blue split at the letters' middle, a thick black outline walked round a
/// ring, and a black drop to the south-east. Drawn once per string and size into a
/// texture, at the screen's scale.
enum TitleText {
    static let face = "AvenirNextCondensed-Heavy"
    static let italicFace = "AvenirNextCondensed-HeavyItalic"
    /// Times the screen's scale the lettering is rendered at, so a HUD scaled up for a
    /// big screen stays crisp. The scene sets it from its HUD scale.
    nonisolated(unsafe) static var renderScale: CGFloat = 1
    static let lightBlue = UIColor(red: 0x89 / 255, green: 0xD7 / 255, blue: 0xED / 255, alpha: 1)
    /// The outline and the drop, as shares of the text size, and the steps round the ring.
    private static let stroke: CGFloat = 0.09
    private static let drop: CGFloat = 0.12
    private static let steps = 16
    nonisolated(unsafe) private static var cache: [String: SKTexture] = [:]
    nonisolated(unsafe) private static var images: [String: UIImage] = [:]

    static func texture(_ text: String, size: CGFloat, italic: Bool = false) -> SKTexture {
        let key = "\(size)|\(italic)|\(renderScale)|\(text)"
        if let texture = cache[key] { return texture }
        let texture = SKTexture(image: image(text, size: size, italic: italic))
        cache[key] = texture
        return texture
    }

    /// The lettering as an image, for the SwiftUI layer.
    static func image(_ text: String, size: CGFloat, italic: Bool = false) -> UIImage {
        let key = "\(size)|\(italic)|\(renderScale)|\(text)"
        if let image = images[key] { return image }
        let font = UIFont(name: italic ? italicFace : face, size: size) ?? UIFont.boldSystemFont(ofSize: size)
        let measured = (text as NSString).size(withAttributes: [.font: font])
        let ring = size * stroke
        let shadow = size * drop
        let pad = ring + shadow + 2
        let canvas = CGSize(width: ceil(measured.width + pad * 2), height: ceil(measured.height + pad * 2))
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale * renderScale
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let origin = CGPoint(x: pad, y: pad)
            func draw(_ colour: UIColor, offset: CGPoint) {
                (text as NSString).draw(at: CGPoint(x: origin.x + offset.x, y: origin.y + offset.y),
                                        withAttributes: [.font: font, .foregroundColor: colour])
            }
            for centre in [CGPoint(x: shadow, y: shadow), .zero] {
                for step in 0..<steps {
                    let angle = Double(step) * 2 * .pi / Double(steps)
                    draw(.black, offset: CGPoint(x: centre.x + cos(angle) * ring, y: centre.y + sin(angle) * ring))
                }
            }
            // The fill splits at the middle of the capitals.
            let middle = origin.y + font.ascender - font.capHeight / 2
            let cg = context.cgContext
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: 0, width: canvas.width, height: middle))
            draw(.white, offset: .zero)
            cg.restoreGState()
            cg.saveGState()
            cg.clip(to: CGRect(x: 0, y: middle, width: canvas.width, height: canvas.height - middle))
            draw(lightBlue, offset: .zero)
            cg.restoreGState()
        }
        images[key] = image
        return image
    }

    /// A sprite of the lettering, sized in points.
    static func node(_ text: String, size: CGFloat, italic: Bool = false) -> SKSpriteNode {
        let texture = texture(text, size: size, italic: italic)
        let node = SKSpriteNode(texture: texture)
        node.size = CGSize(width: texture.size().width / renderScale, height: texture.size().height / renderScale)
        return node
    }

    /// Swaps a sprite's lettering, keeping its place.
    static func set(_ node: SKSpriteNode, to text: String, size: CGFloat, italic: Bool = false) {
        let texture = texture(text, size: size, italic: italic)
        node.texture = texture
        node.size = CGSize(width: texture.size().width / renderScale, height: texture.size().height / renderScale)
    }
}
