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

    init(_ text: String, height: CGFloat, fontName: String? = nil, maxWidth: CGFloat? = nil, spacing: CGFloat = 0) {
        self.text = text
        self.height = height
        self.fontName = fontName
        self.maxWidth = maxWidth
        self.spacing = spacing
    }

    var body: some View {
        let word = Onomatopoeia.picture(text, face: .englishDex, colours: FloTuning.colours, growsLeft: true, height: height,
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
