import SpriteKit
import SwiftUI

/// The menus' look from `Futuristic_UI.svg` (brought in by Tools/import_futuristic.py): its
/// frames and rules on the customize screen's ground (`MenuGround`), lettered in Upheaval. Pieces come in white and are multiplied
/// by the vector's cyan, or by gold when highlighted, when they also grow a tenth.
enum Futuristic {
    /// The menus' blue, their pieces' and their lettering's.
    static let lineRGB: RGB = 0x88D7ED
    static let line = Color(rgb: lineRGB)
    /// The customize screen's top line.
    static let lit = Color(rgb: EsperPalette.gold.light)
    /// The menus' face: the debug strip's UI FONT pick, A to K, Upheaval to start; kept.
    static let typefaces = ["UpheavalTT-BRK-", "InfiniumGuardian", "PlanetaryContact", "SadMachine", "BoldPixels", "Caja",
                        "7pixelsOfPerfect", "BoardofDirectors-Heavy", "BMarmyA12", "Kapel", "LongShot"]
    static let typefaceKey = "ui.futuristic.face"
    /// Face I, BMarmyA12, until one is picked.
    static let defaultTypeface = 8
    static var typefacePick: Int {
        get { min(max((UserDefaults.standard.object(forKey: typefaceKey) as? Int) ?? defaultTypeface, 0), typefaces.count - 1) }
        set { UserDefaults.standard.set(newValue, forKey: typefaceKey) }
    }
    static var fontName: String { typefaces[typefacePick] }
    /// Every face drawn so its capitals stand as tall as Upheaval's at the same size.
    static func fontSize(_ size: CGFloat) -> CGFloat {
        _ = Onomatopoeia.registered
        let probe: CGFloat = 100
        guard let reference = UIFont(name: typefaces[0], size: probe), let face = UIFont(name: fontName, size: probe), face.capHeight > 0 else { return size }
        return size * reference.capHeight / face.capHeight
    }
    /// Every piece at the same points per pixel of its import, so they keep their sizes in the vector.
    static let pointsPerPixel: CGFloat = 0.14

    /// How far the menus' face's capitals sit below the middle of the line SwiftUI centres, at
    /// `size`: a line's box is centred on its ascent and descent, not its capitals, so lettering
    /// set in the middle of something is moved up this much to look it.
    static func capDrop(size: CGFloat) -> CGFloat {
        _ = Onomatopoeia.registered
        guard let face = UIFont(name: fontName, size: fontSize(size)) else { return 0 }
        return (face.ascender + face.descender) / 2 - face.capHeight / 2
    }

    static func font(size: CGFloat) -> Font {
        .custom(fontName, size: fontSize(size))
    }

    /// A line in the menus' face for SpriteKit, centred on its position, in the blue.
    static func label(_ text: String, size: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: fontName)
        label.text = text
        label.fontSize = fontSize(size)
        label.fontColor = lineColour
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }

    static func image(_ piece: String) -> UIImage { UIImage(named: "futuristic_\(piece)") ?? UIImage() }

    /// Frame 8 without the tail under it, the scoreboard's: its picture down to the row where the
    /// tail leaves the lower bar, 412 of its 579; and where its face's middle is then, from the top.
    static let taillessEightRows = 412.0 / 579.0
    @MainActor static let taillessEight: UIImage = {
        let whole = image("8")
        guard let picture = whole.cgImage,
              let cut = picture.cropping(to: CGRect(x: 0, y: 0, width: picture.width, height: Int((Double(picture.height) * taillessEightRows).rounded())))
        else { return whole }
        return UIImage(cgImage: cut, scale: whole.scale, orientation: whole.imageOrientation)
    }()
    static var taillessEightFaceY: CGFloat { (faces["8"]?.y ?? 0.5) / taillessEightRows }

    /// The same for SpriteKit: the blue and the gold, and a piece as a sprite at `scale` of the
    /// menus' size, in the blue.
    static let lineColour = SKColor(rgb: lineRGB)
    static let litColour = SKColor(rgb: EsperPalette.gold.light)
    static func sprite(_ piece: String, scale: CGFloat) -> SKSpriteNode {
        sprite(image: image(piece), scale: scale)
    }
    static func sprite(image: UIImage, scale: CGFloat) -> SKSpriteNode {
        let sprite = SKSpriteNode(texture: SKTexture(image: image))
        sprite.size = CGSize(width: image.size.width * image.scale * pointsPerPixel * scale, height: image.size.height * image.scale * pointsPerPixel * scale)
        sprite.color = lineColour
        sprite.colorBlendFactor = 1
        return sprite
    }

    /// Two of a piece as one image, the left one mirrored, meeting at the piece's left end. That
    /// end's soft edge (its first `softEdge` pixel columns) is cut from both, so they join solid.
    @MainActor static func mirroredPair(_ piece: String) -> UIImage {
        if let made = pairs[piece] { return made }
        let softEdge = 2
        let source = image(piece)
        guard let whole = source.cgImage,
              let cut = whole.cropping(to: CGRect(x: softEdge, y: 0, width: whole.width - softEdge, height: whole.height)) else { return source }
        let half = CGSize(width: cut.width, height: cut.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let made = UIGraphicsImageRenderer(size: CGSize(width: half.width * 2, height: half.height), format: format).image { context in
            let cg = context.cgContext
            // Core Graphics draws bottom up: flipped once for the page, the left copy again across.
            cg.translateBy(x: 0, y: half.height)
            cg.scaleBy(x: 1, y: -1)
            cg.draw(cut, in: CGRect(origin: CGPoint(x: half.width, y: 0), size: half))
            cg.translateBy(x: half.width, y: 0)
            cg.scaleBy(x: -1, y: 1)
            cg.draw(cut, in: CGRect(origin: .zero, size: half))
        }
        pairs[piece] = made
        return made
    }
    @MainActor private static var pairs: [String: UIImage] = [:]

    /// The middle of what a frame holds, as a share of its image from the top left: where its
    /// lettering or icon sits, the frames' leads and trim being off to a side.
    static let faces: [String: CGPoint] = [
        "1": CGPoint(x: 0.75, y: 0.48),
        "5": CGPoint(x: 0.60, y: 0.33),
        "6": CGPoint(x: 0.62, y: 0.49),
        "7": CGPoint(x: 0.50, y: 0.40),
        "8": CGPoint(x: 0.48, y: 0.36),
        "9": CGPoint(x: 0.50, y: 0.32),
        "10": CGPoint(x: 0.45, y: 0.32),
        "11": CGPoint(x: 0.54, y: 0.35),
        "12": CGPoint(x: 0.48, y: 0.38),
        "4": CGPoint(x: 0.60, y: 0.38),
        "box4": CGPoint(x: 0.38, y: 0.50),
    ]
}

/// One of the vector's pieces at its imported size times `scale`, in a colour.
struct FuturisticPiece: View {
    let image: UIImage
    var colour: Color = Futuristic.line
    var scale: CGFloat = 1
    /// Drawn this size outright, stretched to it, in place of its own at `scale`.
    var stretched: CGSize?

    init(name: String, colour: Color = Futuristic.line, scale: CGFloat = 1, stretched: CGSize? = nil) {
        self.init(image: Futuristic.image(name), colour: colour, scale: scale, stretched: stretched)
    }

    init(image: UIImage, colour: Color = Futuristic.line, scale: CGFloat = 1, stretched: CGSize? = nil) {
        self.image = image
        self.colour = colour
        self.scale = scale
        self.stretched = stretched
    }

    var size: CGSize {
        if let stretched { return stretched }
        return CGSize(width: image.size.width * image.scale * Futuristic.pointsPerPixel * scale,
                      height: image.size.height * image.scale * Futuristic.pointsPerPixel * scale)
    }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .colorMultiply(colour)
            .frame(width: size.width, height: size.height)
    }
}

/// A frame with something centred on its face; cyan, or gold when lit.
struct FuturisticFrame<Content: View>: View {
    let name: String
    let lit: Bool
    var scale: CGFloat = 1
    /// The frame alone sized, what it holds keeping its size.
    var frameScale: CGFloat = 1
    /// The frame turned round left to right, or upside down, what it holds the right way round.
    var mirrored = false
    var upsideDown = false
    /// The frame stretched to this size outright, as another frame's.
    var stretched: CGSize?
    @ViewBuilder let content: (Color) -> Content

    var body: some View {
        let piece = FuturisticPiece(name: name, colour: lit ? Futuristic.lit : Futuristic.line, scale: scale * frameScale, stretched: stretched)
        let face = Futuristic.faces[name] ?? CGPoint(x: 0.5, y: 0.5)
        let faceX = mirrored ? 1 - face.x : face.x
        let faceY = upsideDown ? 1 - face.y : face.y
        piece
            .scaleEffect(x: mirrored ? -1 : 1, y: upsideDown ? -1 : 1)
            .overlay {
                content(lit ? Futuristic.lit : Futuristic.line)
                    .offset(x: (faceX - 0.5) * piece.size.width, y: (faceY - 0.5) * piece.size.height)
            }
    }
}

/// Back, on a touch screen: arrow6 turned to point left, bottom right of the screens between
/// the title and play.
struct BackArrow: View {
    let action: () -> Void
    static let scale: CGFloat = 1

    var body: some View {
        Button(action: action) {
            FuturisticPiece(name: "arrow6", scale: BackArrow.scale)
                .scaleEffect(x: -1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noSystemFocus()
    }
}

/// The loading bar: bar4's frame and slot outlines, `litSlots` of its sixteen slots filled
/// from the left (`FuturisticMeter`).
struct LoadingBar: View {
    let litSlots: Int
    var scale: CGFloat = 1

    var body: some View {
        FuturisticPiece(name: "bar4_frame", scale: scale)
            .overlay {
                Canvas { context, size in
                    for slot in FuturisticMeter.slots.prefix(litSlots) {
                        var path = Path()
                        path.addLines(slot.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
                        path.closeSubpath()
                        context.fill(path, with: .color(Futuristic.line))
                    }
                }
            }
    }
}
