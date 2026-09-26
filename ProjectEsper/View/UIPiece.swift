import SpriteKit
import SwiftUI
import UIKit

/// A piece of the dobo UI pack, brought into `ProjectEsper/UI` by `Tools/import_ui.py`,
/// and how far in from each edge its corners and rims reach, in the file's pixels, so it
/// stretches to any size with only its flat middle growing.
enum UIPiece: String {
    case buttonBlue = "ui_button_blue"
    case buttonGold = "ui_button_gold"
    case buttonBlack = "ui_button_black"
    case buttonPlum = "ui_button_plum"
    case headerBlue = "ui_header_blue"
    case cardBlack = "ui_card_black"

    /// Left, bottom, right, top: what doesn't stretch.
    var insets: (left: CGFloat, bottom: CGFloat, right: CGFloat, top: CGFloat) {
        switch self {
        case .buttonBlue, .buttonGold, .buttonBlack, .buttonPlum: (34, 34, 34, 30)
        case .headerBlue: (40, 20, 40, 20)
        case .cardBlack: (44, 44, 44, 44)
        }
    }

    /// The piece's pixels count as this many points: the files are half the pack's size,
    /// and the pack draws at about three pixels to the point.
    static let pointsPerPixel: CGFloat = 1.0 / 2.5

    var texture: SKTexture {
        UIPiece.textures[self] ?? {
            let texture = SKTexture(imageNamed: rawValue)
            UIPiece.textures[self] = texture
            return texture
        }()
    }
    private static var textures: [UIPiece: SKTexture] = [:]

    /// The piece stretched to `size` points, the corners kept.
    func node(size: CGSize) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture)
        fit(node, to: size)
        return node
    }

    /// Resizes a node already showing this piece: its centre stretches, the corners don't.
    func fit(_ node: SKSpriteNode, to size: CGSize) {
        let pixels = texture.size()
        guard pixels.width > 0, pixels.height > 0 else { return }
        let inset = insets
        node.texture = texture
        node.centerRect = CGRect(x: inset.left / pixels.width, y: inset.bottom / pixels.height,
                                 width: max(1 - (inset.left + inset.right) / pixels.width, 0.01),
                                 height: max(1 - (inset.bottom + inset.top) / pixels.height, 0.01))
        // Sized at the piece's natural points, then scaled: with a centre rect only the middle stretches.
        node.setScale(1)
        let natural = CGSize(width: pixels.width * UIPiece.pointsPerPixel, height: pixels.height * UIPiece.pointsPerPixel)
        node.size = natural
        node.xScale = max(size.width, natural.width * 0.3) / natural.width
        node.yScale = max(size.height, natural.height * 0.3) / natural.height
    }

    /// For SwiftUI: the piece as a stretchable image, the corners kept.
    var image: Image {
        guard let ui = UIImage(named: rawValue) else { return Image(systemName: "square") }
        let inset = insets
        let scaled = UIImage(cgImage: ui.cgImage!, scale: 1 / UIPiece.pointsPerPixel, orientation: .up)
        let points = UIPiece.pointsPerPixel
        return Image(uiImage: scaled.resizableImage(withCapInsets: UIEdgeInsets(top: inset.top * points, left: inset.left * points,
                                                                                 bottom: inset.bottom * points, right: inset.right * points),
                                                     resizingMode: .stretch))
    }
}
