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
    /// The black card in the menus' purple.
    case cardPurple = "ui_card_purple"
    case circleBlue = "ui_circle_blue"
    case circleBlack = "ui_circle_black"
    case circlePlum = "ui_circle_plum"
    case circleGold = "ui_circle_gold"
    case plateBlack = "ui_plate_black"
    case plateBlue = "ui_plate_blue"

    /// Left, bottom, right, top: what doesn't stretch.
    var insets: (left: CGFloat, bottom: CGFloat, right: CGFloat, top: CGFloat) {
        switch self {
        case .buttonBlue, .buttonGold, .buttonBlack, .buttonPlum: (34, 34, 34, 30)
        case .headerBlue: (40, 20, 40, 20)
        case .cardBlack, .cardPurple: (44, 44, 44, 44)
        // A round button scales whole, never stretched out of round.
        case .circleBlue, .circleBlack, .circlePlum, .circleGold: (54, 58, 54, 58)
        case .plateBlack, .plateBlue: (60, 26, 60, 26)
        }
    }

    /// Points, at its natural size, that the piece's face sits above its middle: a plate's
    /// dark lip and drop shadow are along its bottom, so lettering centred on the whole
    /// piece reads low on the face.
    var faceRise: CGFloat {
        switch self {
        case .buttonBlue, .buttonGold, .buttonBlack, .buttonPlum, .circleBlue, .circleBlack, .circlePlum, .circleGold: 5 * UIPiece.pointsPerPixel
        case .plateBlack, .plateBlue: 7.5 * UIPiece.pointsPerPixel
        case .headerBlue, .cardBlack, .cardPurple: 0
        }
    }

    /// The piece's pixels count as this many points: the files are half the pack's size,
    /// and the pack draws at about three pixels to the point.
    static let pointsPerPixel: CGFloat = 1.0 / 2.5

    var texture: SKTexture {
        let key = "\(rawValue)|\(toneMap.map { "\($0.targets)" } ?? "")"
        return UIPiece.textures[key] ?? {
            let texture = cgImage.map { SKTexture(cgImage: $0) } ?? SKTexture(imageNamed: file)
            UIPiece.textures[key] = texture
            return texture
        }()
    }
    private static var textures: [String: SKTexture] = [:]

    // MARK: Recoloured pieces

    /// The shades a piece is drawn in, and what each becomes: the plum pieces' tones for
    /// good (the bottom edge's lip and shadow both one), the black and blue buttons' as
    /// picked on the title (a tone unpicked is left), the menus' card on purple, its rims
    /// lightened and darkened from it as they are from its face. Nil, drawn as it is.
    private var toneMap: (sources: [RGB], targets: [RGB])? {
        switch self {
        case .buttonPlum, .circlePlum:
            // Main black's second, top blue's third, bottom gold's last.
            return (EsperPalette.plum.shades, [EsperPalette.blue.body, EsperPalette.black.light, EsperPalette.gold.shadow, EsperPalette.gold.shadow])
        case .buttonBlack, .circleBlack:
            return UIPiece.picked(.nonSelected, sources: [0x433F56, 0x262634, 0x17171F])
        case .buttonBlue, .circleBlue:
            return UIPiece.picked(.blue, sources: [0x6C8DFF, 0x466DF9, 0x183EAD])
        case .cardPurple:
            let sources: [RGB] = [0x615C69, 0x262634, 0x1A1A24]
            return (sources, UIPiece.shades(of: UIColourPicks.menuCard, like: sources, face: 1))
        default:
            return nil
        }
    }

    /// A grid's picks as targets for a piece's top, main and bottom shades.
    private static func picked(_ grid: UIColourPicks.Grid, sources: [RGB]) -> (sources: [RGB], targets: [RGB])? {
        let top = UIColourPicks.colour(grid, .top), main = UIColourPicks.colour(grid, .main), bottom = UIColourPicks.colour(grid, .bottom)
        guard top != nil || main != nil || bottom != nil else { return nil }
        return (sources, [top ?? sources[0], main ?? sources[1], bottom ?? sources[2]])
    }

    /// `colour` as the face, with the other shades lightened or darkened from it by as much
    /// as `sources`' are from the face at `face`.
    private static func shades(of colour: RGB, like sources: [RGB], face: Int) -> [RGB] {
        func luminance(_ c: RGB) -> Double {
            0.2126 * Double((c >> 16) & 0xFF) + 0.7152 * Double((c >> 8) & 0xFF) + 0.0722 * Double(c & 0xFF)
        }
        let faceLuminance = max(luminance(sources[face]), 1)
        return sources.map { shade in
            let share = luminance(shade) / faceLuminance
            return share >= 1 ? Look.lightened(colour, min(share - 1, 1)) : Look.scaled(colour, share)
        }
    }

    /// The file the piece is drawn from: the menus' purple card is the black one recoloured.
    private var file: String { self == .cardPurple ? UIPiece.cardBlack.rawValue : rawValue }

    /// The piece's pixels, recoloured by its tone map.
    private var cgImage: CGImage? {
        guard let source = UIImage(named: file)?.cgImage else { return nil }
        guard let map = toneMap else { return source }
        let key = "\(rawValue)|\(map.targets)"
        if let made = UIPiece.recoloured[key] { return made }
        let made = UIPiece.recolour(source, from: map.sources, to: map.targets) ?? source
        UIPiece.recoloured[key] = made
        return made
    }
    private static var recoloured: [String: CGImage] = [:]

    /// Each pixel as a mix of two of the source shades, or of one and the black line, the
    /// pair and the share that fit it best, drawn as the same mix of their tones: a shade
    /// is its tone, and the soft corners and edges between the face and a rim, or a rim
    /// and the line, stay blends of the new colours. Anything no mix fits (a glint, the
    /// line itself) is left as it is.
    private static func recolour(_ image: CGImage, from sources: [RGB], to targets: [RGB]) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        func channels(_ c: RGB) -> SIMD3<Double> { SIMD3(Double((c >> 16) & 0xFF), Double((c >> 8) & 0xFF), Double(c & 0xFF)) }
        // The shades and the line, and what each becomes.
        let from = sources.map(channels) + [SIMD3(0, 0, 0)]
        let to = targets.map(channels) + [SIMD3(0, 0, 0)]
        let line = from.count - 1
        var pairs: [(Int, Int)] = []
        for a in 0..<from.count { for b in a..<from.count where !(a == line && b == line) { pairs.append((a, b)) } }
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            let alpha = Double(pixels[index + 3])
            guard alpha > 0 else { continue }
            let colour = SIMD3(Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2])) * 255 / alpha
            guard max(colour.x, colour.y, colour.z) >= 12 else { continue }
            var best: (error: Double, a: Int, b: Int, share: Double)?
            for (a, b) in pairs {
                let span = from[b] - from[a]
                let length = (span * span).sum()
                let share = length > 0 ? min(max(((colour - from[a]) * span).sum() / length, 0), 1) : 0
                let miss = colour - (from[a] + span * share)
                let error = (miss * miss).sum()
                if best == nil || error < best!.error { best = (error, a, b, share) }
            }
            guard let best, best.error <= 300 else { continue }
            let made = to[best.a] + (to[best.b] - to[best.a]) * best.share
            pixels[index] = UInt8(min(max(made.x, 0), 255) * alpha / 255)
            pixels[index + 1] = UInt8(min(max(made.y, 0), 255) * alpha / 255)
            pixels[index + 2] = UInt8(min(max(made.z, 0), 255) * alpha / 255)
        }
        return context.makeImage()
    }

    /// The piece stretched to `size` points. `corners` scales the corners and rims with it,
    /// so a plate drawn bigger keeps its depth rather than flattening round small corners.
    func node(size: CGSize, corners: CGFloat = 1) -> SKSpriteNode {
        let node = SKSpriteNode(texture: texture)
        fit(node, to: size, corners: corners)
        return node
    }

    /// Resizes a node already showing this piece: its centre stretches, the corners at
    /// `corners` times their size.
    func fit(_ node: SKSpriteNode, to size: CGSize, corners: CGFloat = 1) {
        let pixels = texture.size()
        guard pixels.width > 0, pixels.height > 0 else { return }
        let inset = insets
        node.texture = texture
        node.centerRect = CGRect(x: inset.left / pixels.width, y: inset.bottom / pixels.height,
                                 width: max(1 - (inset.left + inset.right) / pixels.width, 0.01),
                                 height: max(1 - (inset.bottom + inset.top) / pixels.height, 0.01))
        // Sized at the piece's natural points, then scaled: with a centre rect only the middle stretches.
        node.setScale(1)
        let natural = CGSize(width: pixels.width * UIPiece.pointsPerPixel * corners, height: pixels.height * UIPiece.pointsPerPixel * corners)
        node.size = natural
        node.xScale = max(size.width, natural.width * 0.3) / natural.width
        node.yScale = max(size.height, natural.height * 0.3) / natural.height
    }

    /// For SwiftUI: the piece as a stretchable image, the corners at their size.
    var image: Image { image(corners: 1) }

    /// For SwiftUI: the piece as a stretchable image, the corners at `corners` times their size.
    func image(corners: CGFloat) -> Image {
        guard let pixels = cgImage else { return Image(systemName: "square") }
        let inset = insets
        let points = UIPiece.pointsPerPixel * corners
        let scaled = UIImage(cgImage: pixels, scale: 1 / points, orientation: .up)
        return Image(uiImage: scaled.resizableImage(withCapInsets: UIEdgeInsets(top: inset.top * points, left: inset.left * points,
                                                                                 bottom: inset.bottom * points, right: inset.right * points),
                                                     resizingMode: .stretch))
    }
}
