import SpriteKit
import CoreText
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
    /// Every face drawn so its capitals stand as tall as Upheaval's at the same size: the picked
    /// one, or one by its place in `typefaces`.
    static func fontSize(_ size: CGFloat, face faceIndex: Int? = nil) -> CGFloat {
        _ = Onomatopoeia.registered
        let probe: CGFloat = 100
        let name = faceIndex.map { typefaces[$0] } ?? fontName
        guard let reference = UIFont(name: typefaces[0], size: probe), let face = UIFont(name: name, size: probe), face.capHeight > 0 else { return size }
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

    /// The bullet every list uses: ◈ where the face has it, else the plain dot. By its place in
    /// `typefaces`, or the picked one.
    static func bullet(face faceIndex: Int? = nil) -> String {
        let name = faceIndex.map { typefaces[$0] } ?? fontName
        if let known = bullets[name] { return known }
        _ = Onomatopoeia.registered
        var character: [UniChar] = [0x25C8]
        var glyph: [CGGlyph] = [0]
        let has = UIFont(name: name, size: 12).map { CTFontGetGlyphsForCharacters($0 as CTFont, &character, &glyph, 1) } ?? false
        let bullet = has ? "\u{25C8}" : "\u{2022}"
        bullets[name] = bullet
        return bullet
    }
    nonisolated(unsafe) private static var bullets: [String: String] = [:]

    /// Face E, BoldPixels: the lists' and descriptions' whatever the menus' face is (the updates
    /// screen, the power pick's description).
    static let listFace = 4

    /// A face of its own whatever's picked, by its place in `typefaces`: E is 4.
    static func font(size: CGFloat, face: Int) -> Font {
        .custom(typefaces[face], size: fontSize(size, face: face))
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

    /// Frame 6 cut where its box meets its tail, a share of its width from the left; and its box
    /// alone, without the tail, the settings' categories.
    static let sixTailSplit: CGFloat = 330.0 / 1358.0
    @MainActor static let taillessSix: UIImage = {
        let whole = image("6")
        guard let picture = whole.cgImage else { return whole }
        let left = Int(CGFloat(picture.width) * sixTailSplit)
        guard let cut = picture.cropping(to: CGRect(x: left, y: 0, width: picture.width - left, height: picture.height)) else { return whole }
        return UIImage(cgImage: cut, scale: whole.scale, orientation: whole.imageOrientation)
    }()

    /// Frame 2 without the tail into its top left, the title's UPDATES: its picture from the thin
    /// line beside its left wall, and that line carried straight on where the tail crossed it.
    static let taillessTwoLeft = 334
    static let taillessTwoWidth = 18
    static let taillessTwoCrossed = 309...366
    static let taillessTwoClearRow = 420
    @MainActor static let taillessTwo: UIImage = {
        let whole = image("2")
        guard let picture = whole.cgImage,
              let cut = picture.cropping(to: CGRect(x: taillessTwoLeft, y: 0, width: picture.width - taillessTwoLeft, height: picture.height)),
              let clearRow = picture.cropping(to: CGRect(x: taillessTwoLeft, y: taillessTwoClearRow, width: taillessTwoWidth, height: 1))
        else { return whole }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: cut.width, height: cut.height)
        let mended = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            // Back to y up, so the picture draws upright; a row from the top is then the height less it.
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(cut, in: CGRect(origin: .zero, size: size))
            for row in taillessTwoCrossed {
                let band = CGRect(x: 0, y: size.height - CGFloat(row) - 1, width: CGFloat(taillessTwoWidth), height: 1)
                context.clear(band)
                context.draw(clearRow, in: band)
            }
        }
        guard let mendedPicture = mended.cgImage else { return whole }
        return UIImage(cgImage: mendedPicture, scale: whole.scale, orientation: whole.imageOrientation)
    }()

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
        // Frame 2 without its tail (`taillessTwo`).
        "2": CGPoint(x: 0.52, y: 0.65),
        // Frame 6 without its tail (`taillessSix`): 6's face, against the box alone.
        "6tailless": CGPoint(x: (0.62 - sixTailSplit) / (1 - sixTailSplit), y: 0.49),
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
    /// A picture of the frame made from its own, `taillessTwo`'s, in place of the piece by its name.
    var image: UIImage?
    @ViewBuilder let content: (Color) -> Content

    var body: some View {
        let colour = lit ? Futuristic.lit : Futuristic.line
        let piece = image.map { FuturisticPiece(image: $0, colour: colour, scale: scale * frameScale, stretched: stretched) }
            ?? FuturisticPiece(name: name, colour: colour, scale: scale * frameScale, stretched: stretched)
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
