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
    static let litGrowth: CGFloat = 1.1
    static let fontName = "UpheavalTT-BRK-"
    /// Every piece at the same points per pixel of its import, so they keep their sizes in the vector.
    static let pointsPerPixel: CGFloat = 0.14

    static func font(size: CGFloat) -> Font {
        _ = Onomatopoeia.registered
        return .custom(fontName, size: size)
    }

    static func image(_ piece: String) -> UIImage { UIImage(named: "futuristic_\(piece)") ?? UIImage() }

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
        "6": CGPoint(x: 0.62, y: 0.49),
        "7": CGPoint(x: 0.50, y: 0.40),
        "9": CGPoint(x: 0.50, y: 0.32),
        "box4": CGPoint(x: 0.38, y: 0.50),
    ]
}

/// One of the vector's pieces at its imported size times `scale`, in a colour.
struct FuturisticPiece: View {
    let image: UIImage
    var colour: Color = Futuristic.line
    var scale: CGFloat = 1

    init(name: String, colour: Color = Futuristic.line, scale: CGFloat = 1) {
        self.init(image: Futuristic.image(name), colour: colour, scale: scale)
    }

    init(image: UIImage, colour: Color = Futuristic.line, scale: CGFloat = 1) {
        self.image = image
        self.colour = colour
        self.scale = scale
    }

    var size: CGSize {
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

/// A frame with something centred on its face; cyan, or gold and a tenth bigger when lit.
struct FuturisticFrame<Content: View>: View {
    let name: String
    let lit: Bool
    var scale: CGFloat = 1
    /// The frame alone sized, what it holds keeping its size.
    var frameScale: CGFloat = 1
    /// The frame turned round left to right, what it holds the right way round.
    var mirrored = false
    @ViewBuilder let content: (Color) -> Content

    var body: some View {
        let piece = FuturisticPiece(name: name, colour: lit ? Futuristic.lit : Futuristic.line, scale: scale * frameScale)
        let face = Futuristic.faces[name] ?? CGPoint(x: 0.5, y: 0.5)
        let faceX = mirrored ? 1 - face.x : face.x
        piece
            .scaleEffect(x: mirrored ? -1 : 1)
            .overlay {
                content(lit ? Futuristic.lit : Futuristic.line)
                    .offset(x: (faceX - 0.5) * piece.size.width, y: (face.y - 0.5) * piece.size.height)
            }
            .scaleEffect(lit ? Futuristic.litGrowth : 1)
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
