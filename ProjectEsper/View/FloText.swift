import SpriteKit
import SwiftUI

/// Lettering as the FLO meter's word is when it's lit: Bigdex (or a face of the caller's), gold's
/// first over the cyan, outlined in plum and purple (`FloTuning.colours`), straight. One look,
/// used wherever a word is called out in it: the count, BALL OUT on its Z card, the Greateraid
/// pick's drink, the customize screen's titles.
///
/// `height` is its cap height, whatever the face; wider than `maxWidth`, it's scaled down to it.
struct FloText: View {
    let text: String
    let height: CGFloat
    var fontName: String? = nil
    var maxWidth: CGFloat? = nil
    /// Space between the letters, a share of each one's size.
    var spacing: CGFloat = 0
    /// Lit, as ever; or the FLO word's short of full (`FloTuning.shortColours`).
    var colours = FloTuning.colours

    init(_ text: String, height: CGFloat, fontName: String? = nil, maxWidth: CGFloat? = nil, spacing: CGFloat = 0,
         colours: Onomatopoeia.Colours = FloTuning.colours) {
        self.text = text
        self.height = height
        self.fontName = fontName
        self.maxWidth = maxWidth
        self.spacing = spacing
        self.colours = colours
    }

    var body: some View {
        let word = Onomatopoeia.picture(text, face: .englishDex, colours: colours, growsLeft: true, height: height,
                                        spacing: spacing, fontName: fontName)
        let width = word.height * word.image.size.width / max(word.image.size.height, 1)
        let shrink = maxWidth.map { min($0 / max(width, 1), 1) } ?? 1
        Image(uiImage: word.image).resizable().aspectRatio(contentMode: .fit).frame(height: word.height * shrink)
    }

    /// The same lettering as a SpriteKit sprite, centred on its position, sized in points.
    static func node(_ text: String, height: CGFloat) -> SKSpriteNode {
        Onomatopoeia.still(text, face: .englishDex, colours: FloTuning.colours, height: height, growsLeft: true, left: 1, right: 1)
    }
}

/// `FloText` whose letters roll as it changes, as Apple's numeric text does: a letter that's
/// changed slides up and out, blurring and fading, as its new one slides up into its place
/// from below, coming clear; the letters that stay move and size to their new places. Drawn
/// a letter at a time (`Onomatopoeia.letterPictures`), every outline under every fill, so at
/// rest it's the word's own picture.
struct FloRollText: View {
    let text: String
    let height: CGFloat
    var fontName: String? = nil
    var maxWidth: CGFloat? = nil
    var spacing: CGFloat = 0

    init(_ text: String, height: CGFloat, fontName: String? = nil, maxWidth: CGFloat? = nil, spacing: CGFloat = 0) {
        self.text = text
        self.height = height
        self.fontName = fontName
        self.maxWidth = maxWidth
        self.spacing = spacing
    }

    static let roll = Animation.spring(response: 0.4, dampingFraction: 0.85)
    /// How far a letter rolls in or out, and how blurred it is there, as shares of the word's height.
    static let rollShare: CGFloat = 0.5
    static let blurShare: CGFloat = 0.12

    var body: some View {
        let letters = Onomatopoeia.letterPictures(text, face: .englishDex, colours: FloTuning.colours, growsLeft: true, height: height,
                                                  spacing: spacing, fontName: fontName)
        let shown = height * Onomatopoeia.Lettering.englishDex.scale / max(letters.capShare, 0.01)
        let points = shown / max(letters.canvas.height, 1)
        let size = CGSize(width: letters.canvas.width * points, height: shown)
        let shrink = maxWidth.map { min($0 / max(size.width, 1), 1) } ?? 1
        let rolling = AnyTransition.asymmetric(
            insertion: .modifier(active: Roll(drop: shown * FloRollText.rollShare, blur: shown * FloRollText.blurShare, opacity: 0),
                                 identity: Roll(drop: 0, blur: 0, opacity: 1)),
            removal: .modifier(active: Roll(drop: -shown * FloRollText.rollShare, blur: shown * FloRollText.blurShare, opacity: 0),
                               identity: Roll(drop: 0, blur: 0, opacity: 1)))
        let pieces = Array(letters.pieces.enumerated())
        ZStack(alignment: .topLeading) {
            ForEach(pieces, id: \.offset) { index, piece in
                letter(piece.outline, piece.frame, points)
                    .id("\(index)\(piece.text)")
                    .transition(rolling)
            }
            ForEach(pieces, id: \.offset) { index, piece in
                letter(piece.fill, piece.frame, points)
                    .id("\(index)\(piece.text)")
                    .transition(rolling)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(FloRollText.roll, value: text)
        .scaleEffect(shrink)
        .frame(width: size.width * shrink, height: size.height * shrink)
    }

    private func letter(_ image: UIImage, _ frame: CGRect, _ points: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .frame(width: frame.width * points, height: frame.height * points)
            .position(x: frame.midX * points, y: frame.midY * points)
    }

    /// A letter on its way in or out: dropped (up, under 0), blurred and faded.
    private struct Roll: ViewModifier {
        let drop: CGFloat
        let blur: CGFloat
        let opacity: Double

        func body(content: Content) -> some View {
            content.offset(y: drop).blur(radius: blur).opacity(opacity)
        }
    }
}
