import CoreText
import SpriteKit
import UIKit

/// Manga sound effects over the action, Jump Ultimate Stars style: a word in English or in
/// katakana, each in one of several faces, never a mix, its letters growing along the
/// word and rocking in turn, outlined and dropped like the title lettering, and the sprite
/// warped into a flare that snaps in and settles.
enum Onomatopoeia {
    /// The SFX picker's options: katakana in one of three faces, or English in one of four.
    enum Lettering: Int, CaseIterable {
        case cherryBomb, darumadrop, delaGothic
        case englishDex, englishCherry, englishDarumadrop, englishDela

        var label: String {
            switch self {
            case .cherryBomb: "CHERRY"
            case .darumadrop: "DARUMA"
            case .delaGothic: "DELA"
            case .englishDex: "EN DEX"
            case .englishCherry: "EN CHERRY"
            case .englishDarumadrop: "EN DARUMA"
            case .englishDela: "EN DELA"
            }
        }
        var fontName: String {
            switch self {
            case .cherryBomb, .englishCherry: "CherryBombOne-Regular"
            case .darumadrop, .englishDarumadrop: "DarumadropOne-Regular"
            case .delaGothic, .englishDela: "DelaGothicOne-Regular"
            case .englishDex: "Bigdex"
            }
        }
        var japanese: Bool { rawValue < Lettering.englishDex.rawValue }
        /// Darumadrop has no full-width "!", only the plain one.
        var plainBangs: Bool { self == .darumadrop }
        /// The letter the faces are centred and sized by.
        var reference: String { japanese ? "ド" : "D" }
        /// Dela Gothic's letters run wide for their height, so it's drawn smaller to sit with the rest.
        var scale: CGFloat { self == .delaGothic || self == .englishDela ? 0.85 : 1 }
    }
    private static let letteringKey = "soundWordFace"
    /// The SFX picker's choice, kept between launches.
    static var lettering: Lettering {
        get {
            let saved = Lettering(rawValue: UserDefaults.standard.integer(forKey: letteringKey)) ?? .cherryBomb
            return pickable.contains(saved) ? saved : .cherryBomb
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: letteringKey) }
    }
    /// The SFX picker's faces: Cherry Bomb, Darumadrop and Dela, in kana or English. Bigdex is
    /// the UI's, the FLO meter's word.
    static let pickable = Lettering.allCases.filter { $0 != .englishDex }

    /// What made the sound, spelled per language.
    enum Sound: CaseIterable {
        case swish, three, dunk
        case hit, steal, spike, parry, clang, squeak, walk, run, bounce
        case beam, burst, quake, freeze, explosion
        case sizzle, shatter, thunder

        /// English, then Japanese; the palette indexes over and under each letter's middle;
        /// the cap height in the world, in art pixels.
        private var spelling: (english: String, japanese: String, upper: Int, lower: Int, height: CGFloat) {
            switch self {
            // Baskets: the net, and the rim taking a dunk.
            case .swish: ("SWISH!", "パサッ！", 22, 19, 22)
            case .three: ("SWOOSH!!", "ザシュッ！！", 22, 19, 24)
            case .dunk: ("SLAM!!", "ドガァン！！", 8, 6, 28)
            // Bodies and the ball.
            case .hit: ("WHAM!", "ドゴッ！", 22, 5, 18)
            case .steal: ("SMACK!", "バシッ！", 22, 26, 16)
            case .spike: ("THWACK!", "バチィン！", 9, 5, 20)
            case .parry: ("TING!", "キィン！", 22, 39, 16)
            case .clang: ("CLANG", "ガキン", 39, 41, 14)
            case .squeak: ("SQUEAK", "キュッ", 22, 37, 9)
            // Footsteps, small by the feet.
            case .walk: ("TAP", "テク", 22, 37, 4)
            case .run: ("THUMP", "ダッ", 22, 37, 4.5)
            // The loose ball off the floor or a wall.
            case .bounce: ("BOMP", "ダム", 22, 6, 8)
            // Powers.
            case .beam: ("VWOOOM", "ズドドドド", 9, 7, 20)
            case .burst: ("BOOOM!", "ドオォン！", 9, 6, 26)
            case .quake: ("RUMBLE", "ゴゴゴゴ", 36, 34, 20)
            case .freeze: ("CRACK!", "ピキッ！", 22, 21, 16)
            case .explosion: ("KABOOM!", "ドカーン！", 8, 5, 22)
            // The stages.
            case .sizzle: ("SIZZLE", "ジュウゥ", 7, 5, 18)
            case .shatter: ("CRASH", "パリーン", 22, 19, 16)
            case .thunder: ("KRAKOOM!", "バリバリッ", 9, 8, 20)
            }
        }

        /// The word in the picked face, its letters growing to the right, or to the left.
        func word(growsLeft: Bool) -> Word {
            let spelling = spelling
            let lettering = Onomatopoeia.lettering
            let japanese = lettering.plainBangs ? spelling.japanese.replacingOccurrences(of: "！", with: "!") : spelling.japanese
            let line = PixelPalette.colours[Onomatopoeia.lineIndex]
            return Word(text: lettering.japanese ? japanese : spelling.english, lettering: lettering,
                        colours: Colours(upper: PixelPalette.colours[spelling.upper], lower: PixelPalette.colours[spelling.lower],
                                         lineUpper: line, lineLower: line),
                        height: spelling.height, growsLeft: growsLeft)
        }
    }

    /// A word's four colours: the fill over and under each letter's middle, and the outline and
    /// drop, two-toned the same way.
    struct Colours: Hashable {
        var upper: RGB
        var lower: RGB
        var lineUpper: RGB
        var lineLower: RGB
    }
    /// The sound words' outline and drop: palette 29.
    static let lineIndex = 29

    struct Word: Hashable {
        let text: String
        let lettering: Lettering
        let colours: Colours
        let height: CGFloat
        /// Its letters grow to the left, the small end on the right.
        var growsLeft = false
    }

    /// Bundled, and registered with the process on first use.
    private static let registered: Void = {
        for name in ["Bigdex", "CherryBombOne-Regular", "DarumadropOne-Regular", "DelaGothicOne-Regular"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    /// The reference letter's ink in `font`, up from the baseline.
    private static func ink(_ text: String, in font: UIFont) -> CGRect {
        var characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(font as CTFont, &characters, &glyphs, characters.count)
        var bounds = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font as CTFont, .horizontal, &glyphs, &bounds, 1)
        return bounds.isEmpty ? CGRect(x: 0, y: 0, width: font.capHeight, height: font.capHeight) : bounds
    }

    /// The size the lettering is drawn at before the sprite is scaled to the world.
    private static let drawSize: CGFloat = 64
    /// The last letter's size over the first's.
    private static let growth: CGFloat = 0.35
    /// Each letter's rock either way, and its rise and fall off the line, shares of its size.
    private static let rock: CGFloat = 7 * .pi / 180
    private static let bob: CGFloat = 0.05
    /// How far each letter tucks under the one before.
    private static let tuck: CGFloat = 0.1
    private static let stroke: CGFloat = 0.1
    private static let drop: CGFloat = 0.12
    private static let steps = 16
    /// Pixels a point the lettering is drawn at, so it stays crisp scaled up into the world.
    private static let renderScale: CGFloat = 3
    nonisolated(unsafe) private static var cache: [Word: (texture: SKTexture, capShare: CGFloat)] = [:]

    /// Every word drawn ahead in the picked face, so none is first drawn mid-match.
    static func warmed() -> [SKTexture] {
        Sound.allCases.flatMap { sound in [false, true].map { rendered(sound.word(growsLeft: $0)).texture } }
    }

    /// The word's sprite, sized for the world, warped flat; `show` brings it on.
    static func node(_ word: Word) -> SKSpriteNode {
        let (texture, capShare) = rendered(word)
        let node = SKSpriteNode(texture: texture)
        let height = word.height * word.lettering.scale / capShare
        node.size = CGSize(width: height * texture.size().width / max(texture.size().height, 1), height: height)
        return node
    }

    /// The word out of where its sound is made, as Jump Ultimate Stars has them: small at
    /// `source`, `gap` off it, growing away to the `away` side (1 right, -1 left) and turned up
    /// `rise` radians as it goes; in on a hard flare from its small end, settling to a softer
    /// one, held, then on out a little as it fades. A sprite in a holder at the source: the
    /// holder turns, scales and fades, the sprite warps. `z` in `parent`.
    @discardableResult
    static func show(_ sound: Sound, from source: CGPoint, away: CGFloat, rise: CGFloat, gap: CGFloat,
                     in parent: SKNode, z: CGFloat) -> SKNode {
        let left = away < 0
        let word = sound.word(growsLeft: left)
        let sprite = node(word)
        sprite.warpGeometry = flare(0)
        // Hung by its small end, the source side.
        sprite.anchorPoint = CGPoint(x: left ? 1 : 0, y: 0.5)
        sprite.position = CGPoint(x: away * gap, y: 0)
        let node = SKNode()
        node.addChild(sprite)
        node.position = source
        node.zPosition = z
        node.zRotation = away * rise
        node.setScale(0.3)
        let warp = SKAction.animate(withWarps: [flare(left ? -1.4 : 1.4), flare(left ? -1 : 1)], times: [0.08, 0.24]) ?? .wait(forDuration: 0.24)
        let punch = SKAction.scale(to: 1.15, duration: 0.08)
        punch.timingMode = .easeOut
        let settle = SKAction.scale(to: 1, duration: 0.16)
        settle.timingMode = .easeInEaseOut
        let drift = CGVector(dx: away * cos(rise) * word.height * 0.4, dy: sin(rise) * word.height * 0.4)
        let leave = SKAction.group([.move(by: drift, duration: 0.3), .fadeOut(withDuration: 0.3)])
        sprite.run(warp)
        node.run(.sequence([punch, settle, .wait(forDuration: holdSeconds), leave, .removeFromParent()]))
        parent.addChild(node)
        return node
    }
    static let holdSeconds = 0.5

    /// Lettering in a face, as the words are drawn, held still: its letters growing to the left or
    /// the right, and skewed, its left and right ends drawn `left` and `right` times its middle's
    /// height, the middle arched as a word's is. `height` is its cap height in points.
    static func still(_ text: String, face: Lettering, colours: Colours, height: CGFloat, growsLeft: Bool,
                      left: CGFloat, right: CGFloat) -> SKSpriteNode {
        let sprite = node(Word(text: text, lettering: face, colours: colours, height: height, growsLeft: growsLeft))
        sprite.warpGeometry = skew(left: left, right: right, bend: 0.08, columns: 3)
        return sprite
    }

    /// A sprite's warp: its left and right ends `left` and `right` times its middle's height,
    /// the height between running straight from one to the other, and its middle raised `bend`
    /// of its height (lowered, under 0), easing to nothing at the ends.
    static func skew(left: CGFloat, right: CGFloat, bend: CGFloat, columns: Int) -> SKWarpGeometryGrid {
        let source = (0...1).flatMap { row in (0...columns).map { SIMD2<Float>(Float($0) / Float(columns), Float(row)) } }
        let destination = source.map { vertex -> SIMD2<Float> in
            let stretch = Float(left) + (Float(right) - Float(left)) * vertex.x
            return SIMD2(vertex.x, 0.5 + (vertex.y - 0.5) * stretch + sin(vertex.x * .pi) * Float(bend))
        }
        return SKWarpGeometryGrid(columns: columns, rows: 1, sourcePositions: source, destinationPositions: destination)
    }

    /// A perspective flare along the word, `amount` 1 to the right and -1 to the left: the
    /// near end squeezed, the far end spread, the middle arched up.
    private static func flare(_ amount: Float) -> SKWarpGeometryGrid {
        let columns = 3
        let source = (0...1).flatMap { row in (0...columns).map { SIMD2<Float>(Float($0) / Float(columns), Float(row)) } }
        let destination = source.map { vertex -> SIMD2<Float> in
            // 0 at the squeezed end, 1 at the spread one.
            let along = amount >= 0 ? vertex.x : 1 - vertex.x
            let spread = abs(amount) * (along - 0.5) * 0.36
            let arch = abs(amount) * sin(vertex.x * .pi) * 0.08
            let fromMiddle = vertex.y - 0.5
            return SIMD2(vertex.x, 0.5 + fromMiddle * (1 + spread) + arch)
        }
        return SKWarpGeometryGrid(columns: columns, rows: 1, sourcePositions: source, destinationPositions: destination)
    }

    private struct Letter {
        let text: String
        let font: UIFont
        let centre: CGPoint
        let angle: CGFloat
    }

    private static func rendered(_ word: Word) -> (texture: SKTexture, capShare: CGFloat) {
        if let cached = cache[word] { return cached }
        _ = registered
        func font(_ size: CGFloat) -> UIFont { UIFont(name: word.lettering.fontName, size: size) ?? TitleText.font(size: size, italic: true) }
        let reference = word.lettering.reference
        let characters = word.text.map(String.init)
        let count = characters.count
        // Laid out along the line, each letter's middle on it.
        var letters: [Letter] = []
        var x: CGFloat = 0
        var top: CGFloat = 0
        for index in 0..<count {
            let along = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0
            let share = word.growsLeft ? 1 - along : along
            let size = drawSize * (1 + growth * share)
            let letterFont = font(size)
            let text = characters[index]
            let width = (text as NSString).size(withAttributes: [.font: letterFont]).width
            let sign: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            letters.append(Letter(text: text, font: letterFont, centre: CGPoint(x: x + width / 2, y: sign * bob * size), angle: sign * rock))
            x += width * (1 - tuck)
            top = max(top, ink(reference, in: letterFont).height * 0.6 + bob * size)
        }
        let largest = drawSize * (1 + growth)
        let ring = largest * stroke
        let shadow = largest * drop
        let pad = ring + shadow + largest * 0.15
        let width = x + largest * tuck + pad * 2
        let height = top * 2 + pad * 2
        let canvas = CGSize(width: ceil(width), height: ceil(height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = renderScale
        let lineY = canvas.height / 2
        let upper = colour(word.colours.upper), lower = colour(word.colours.lower)
        let lineUpper = colour(word.colours.lineUpper), lineLower = colour(word.colours.lineLower)
        /// Each letter turned and set on the line, `shift` off it, for `draw` to put down with
        /// its size and where its glyph is drawn from.
        func eachLetter(_ cg: CGContext, shift: CGFloat, draw: (Letter, CGFloat, CGPoint) -> Void) {
            for letter in letters {
                cg.saveGState()
                cg.translateBy(x: pad + letter.centre.x + shift, y: lineY + letter.centre.y + shift)
                cg.rotate(by: letter.angle)
                // The glyph's middle on the letter's centre.
                let origin = CGPoint(x: -(letter.text as NSString).size(withAttributes: [.font: letter.font]).width / 2,
                                     y: -(letter.font.ascender - ink(reference, in: letter.font).midY))
                draw(letter, letter.font.pointSize, origin)
                cg.restoreGState()
            }
        }
        func text(_ letter: Letter, _ colour: UIColor, at point: CGPoint) {
            (letter.text as NSString).draw(at: point, withAttributes: [.font: letter.font, .foregroundColor: colour])
        }
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            let cg = context.cgContext
            // The drop, then the outline, each a ring round every letter, split at its middle as the fill is.
            for shift in [shadow, 0] {
                eachLetter(cg, shift: shift) { letter, size, origin in
                    let letterRing = ring * size / largest
                    split(cg, size: size, upper: lineUpper, lower: lineLower) { colour in
                        for step in 0..<steps {
                            let angle = CGFloat(step) * 2 * .pi / CGFloat(steps)
                            text(letter, colour, at: CGPoint(x: origin.x + cos(angle) * letterRing, y: origin.y + sin(angle) * letterRing))
                        }
                    }
                }
            }
            // The fill, each letter `upper` over `lower` split at its middle.
            eachLetter(cg, shift: 0) { letter, size, origin in
                split(cg, size: size, upper: upper, lower: lower) { text(letter, $0, at: origin) }
            }
        }
        let capShare = ink(reference, in: font(drawSize)).height / canvas.height
        let result = (SKTexture(image: image), capShare)
        cache[word] = result
        return result
    }

    /// The fill drawn twice, `upper` above the letter's middle and `lower` under it.
    private static func split(_ cg: CGContext, size: CGFloat, upper: UIColor, lower: UIColor, draw: (UIColor) -> Void) {
        for (colour, rect) in [(upper, CGRect(x: -size * 2, y: -size * 2, width: size * 4, height: size * 2)),
                               (lower, CGRect(x: -size * 2, y: 0, width: size * 4, height: size * 2))] {
            cg.saveGState()
            cg.clip(to: rect)
            draw(colour)
            cg.restoreGState()
        }
    }

    private static func colour(_ rgb: RGB) -> UIColor {
        return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
