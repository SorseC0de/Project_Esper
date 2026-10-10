import SwiftUI

/// The menus' look from `Futuristic_UI.svg` (brought in by Tools/import_futuristic.py): its
/// frames and rules on black, lettered in Upheaval. Pieces come in white and are multiplied
/// by the vector's cyan, or by gold when highlighted, when they also grow a tenth.
enum Futuristic {
    static let ground = Color.black
    /// The vector's own cyan.
    static let line = Color(rgb: 0x00D0FF)
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
    let name: String
    var colour: Color = Futuristic.line
    var scale: CGFloat = 1

    var size: CGSize {
        let image = Futuristic.image(name)
        return CGSize(width: image.size.width * image.scale * Futuristic.pointsPerPixel * scale,
                      height: image.size.height * image.scale * Futuristic.pointsPerPixel * scale)
    }

    var body: some View {
        Image(uiImage: Futuristic.image(name))
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
    @ViewBuilder let content: (Color) -> Content

    var body: some View {
        let piece = FuturisticPiece(name: name, colour: lit ? Futuristic.lit : Futuristic.line, scale: scale)
        let face = Futuristic.faces[name] ?? CGPoint(x: 0.5, y: 0.5)
        piece
            .overlay {
                content(lit ? Futuristic.lit : .white)
                    .offset(x: (face.x - 0.5) * piece.size.width, y: (face.y - 0.5) * piece.size.height)
            }
            .scaleEffect(lit ? Futuristic.litGrowth : 1)
    }
}
