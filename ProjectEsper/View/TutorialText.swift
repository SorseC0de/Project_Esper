import CoreText
import EsperSim
import SpriteKit

/// The Tutorial's lettering on its back wall, in white, in a pixel face at its own size: typed out
/// a character a second at `charactersPerSecond`, and ending always in an underscore, solid while
/// it types and flashing slowly once it's done. A line's `[left]`, `[right]`, `[up]`, `[jump]`,
/// `[shoot]` and `[throw]` are the controls player one plays with (`InputHub.Source`): the
/// keyboard's keys in a keycap; on a controller its buttons' letters, on touch its buttons' names,
/// each in a keycap, and arrows for the stick.
/// Changed text types on from where it first differs; text already all out changes at once.
final class TutorialText {
    /// The faces to choose from (TUTORIAL FONT on the debug strip), each at the size its pixels are drawn for.
    enum Face: Int, CaseIterable {
        case boldPixels, sevenPixels, upheaval
        var label: String { ["BOLD", "7PX", "UPHEAVAL"][rawValue] }
        var name: String { ["BoldPixels", "7pixelsOfPerfect", "UpheavalTT-BRK-"][rawValue] }
        var size: CGFloat { [16, 16, 20][rawValue] }
    }
    nonisolated(unsafe) static var face = Face.boldPixels
    static let charactersPerSecond = 30.0
    /// The underscore's flash once the text's all out: this long on, this long off.
    static let underscoreSeconds = 0.5
    /// Between lines, art pixels.
    static let lineGap = 4
    static let colour: RGB = PixelPalette.colours[16]
    /// A control a lesson names, as its token in a line.
    enum Control: String, CaseIterable {
        case left, right, up, jump, shoot, throwBall = "throw"
        /// How it's shown: a keycap's label, or an arrow (its way: -1 left, 1 right, 0 up).
        func shown(on source: InputHub.Source) -> (key: String?, arrow: Int?) {
            switch (self, source) {
            case (.left, .keyboard): ("A", nil)
            case (.right, .keyboard): ("D", nil)
            case (.up, .keyboard): ("W", nil)
            case (.left, _): (nil, -1)
            case (.right, _): (nil, 1)
            case (.up, _): (nil, 0)
            case (.jump, .keyboard): ("SPACE", nil)
            case (.shoot, .keyboard): ("J", nil)
            case (.throwBall, .keyboard): ("K", nil)
            case (.jump, .controller): ("A", nil)
            case (.shoot, .controller): ("X", nil)
            case (.throwBall, .controller): ("B", nil)
            case (.jump, .touch): ("JUMP", nil)
            case (.shoot, .touch): ("SHOOT", nil)
            case (.throwBall, .touch): ("THROW", nil)
            }
        }
    }

    private enum Piece: Equatable {
        case text(String)
        case control(Control)
    }

    /// The picture, its top middle at `top` on the stage, in art pixels.
    let node = SKSpriteNode()
    /// Moved to the room the lesson's in.
    var top: CGPoint
    private var lines: [[Piece]] = []
    private var source = InputHub.Source.keyboard
    private var shown = 0.0
    private var lastTime: CFTimeInterval?
    private var drawn: (count: Int, underscore: Bool, face: Face)?
    private var fullWidth = 0
    /// Room kept at the end for the underscore; a title keeps none.
    private var underscored = true

    init(top: CGPoint) {
        self.top = top
        node.anchorPoint = CGPoint(x: 0, y: 1)
    }

    /// The lines to show, with the controls they name.
    func set(_ text: [String], source: InputHub.Source) {
        let parsed = text.map(TutorialText.pieces)
        guard parsed != lines || source != self.source else { return }
        let total = TutorialText.count(lines)
        let common = TutorialText.commonPrefix(lines, parsed)
        shown = Double(shown >= Double(total) ? TutorialText.count(parsed) : min(Int(shown), common))
        lines = parsed
        self.source = source
        drawn = nil
    }

    /// A frame on: more of it typed, the underscore flashing, drawn again if that changed.
    func step(at time: CFTimeInterval) {
        let step = max(time - (lastTime ?? time), 0)
        lastTime = time
        let total = TutorialText.count(lines)
        shown = min(shown + step * TutorialText.charactersPerSecond, Double(total))
        let count = Int(shown)
        let underscore = count < total || Int(time / TutorialText.underscoreSeconds) % 2 == 0
        guard drawn.map({ $0.count != count || $0.underscore != underscore || $0.face != TutorialText.face }) ?? true else { return }
        defer { node.position = CGPoint(x: (top.x - CGFloat(fullWidth) / 2).rounded(), y: top.y) }
        drawn = (count, underscore, TutorialText.face)
        draw(count: count, underscore: underscore)
    }

    /// A line of the lettering whole, no underscore, as a picture: the hub's hoops' titles.
    static func label(_ text: String) -> SKTexture? {
        let lettering = TutorialText(top: .zero)
        lettering.underscored = false
        lettering.set([text], source: .keyboard)
        lettering.shown = Double(TutorialText.count(lettering.lines))
        lettering.draw(count: Int(lettering.shown), underscore: false)
        return lettering.node.texture
    }

    // MARK: The text

    private static func pieces(_ line: String) -> [Piece] {
        var pieces: [Piece] = []
        var rest = Substring(line)
        next: while !rest.isEmpty {
            for control in Control.allCases where rest.hasPrefix("[\(control.rawValue)]") {
                pieces.append(.control(control))
                rest = rest.dropFirst(control.rawValue.count + 2)
                continue next
            }
            pieces.append(.text(String(rest.removeFirst())))
        }
        return pieces
    }
    private static func count(_ lines: [[Piece]]) -> Int { lines.reduce(0) { $0 + $1.count } }
    /// How many pieces, line after line, two texts share from the start.
    private static func commonPrefix(_ a: [[Piece]], _ b: [[Piece]]) -> Int {
        let flatA = a.flatMap { $0 + [.text("\n")] }, flatB = b.flatMap { $0 + [.text("\n")] }
        var lineBreaks = 0, common = 0
        for (x, y) in zip(flatA, flatB) {
            guard x == y else { break }
            if x == .text("\n") { lineBreaks += 1 } else { common += 1 }
        }
        return common
    }

    // MARK: Drawing

    /// Pixels on, in art pixels, x right and y down from a line's top left; and how far it reaches.
    private struct Ink {
        var on: Set<[Int]> = []
        var width = 0
    }

    private func font() -> CTFont {
        _ = Onomatopoeia.registered
        return CTFontCreateWithName(TutorialText.face.name as CFString, TutorialText.face.size, nil)
    }

    /// A string's pixels at the pen, from the line's top, its baseline `ascent` down.
    private func letters(_ text: String, font: CTFont, ascent: Int, at pen: Int, into ink: inout Ink) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]))
        let advance = Int(CTLineGetTypographicBounds(line, nil, nil, nil).rounded())
        let height = ascent + Int(CTFontGetDescent(font).rounded(.up)) + 2, width = advance + 4
        var alpha = [UInt8](repeating: 0, count: width * height)
        alpha.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.setFillColor(gray: 1, alpha: 1)
            context.setShouldAntialias(false)
            context.textPosition = CGPoint(x: 0, y: CGFloat(height - ascent))
            CTLineDraw(line, context)
        }
        for y in 0..<height { for x in 0..<width where alpha[y * width + x] >= 128 { ink.on.insert([pen + x, y]) } }
        ink.width = max(ink.width, pen + advance)
    }

    /// A line's first `limit` pieces, and the underscore after them if it's due.
    private func ink(_ pieces: [Piece], limit: Int, underscore: Bool, font: CTFont, ascent: Int, capHeight: Int) -> Ink {
        var ink = Ink()
        var pen = 0
        for piece in pieces.prefix(limit) {
            switch piece {
            case .text(let text):
                letters(text, font: font, ascent: ascent, at: pen, into: &ink)
                pen = ink.width
            case .control(let control):
                let shown = control.shown(on: source)
                if let key = shown.key {
                    // The key's label in a keycap: a box a pixel round it, two clear.
                    let boxTop = ascent - capHeight - 3, boxBottom = ascent + 2
                    var label = Ink()
                    letters(key, font: font, ascent: ascent, at: 0, into: &label)
                    let boxWidth = label.width + 5
                    for x in 0..<boxWidth { ink.on.insert([pen + x, boxTop]); ink.on.insert([pen + x, boxBottom]) }
                    for y in boxTop...boxBottom { ink.on.insert([pen, y]); ink.on.insert([pen + boxWidth - 1, y]) }
                    for pixel in label.on { ink.on.insert([pen + 3 + pixel[0], pixel[1]]) }
                    pen += boxWidth
                } else if let way = shown.arrow {
                    // An arrow the letters' height, pointing the way: across, or up.
                    let half = max(capHeight / 2, 2)
                    if way == 0 {
                        for row in 0...half {
                            for x in (half - row)...(half + row) { ink.on.insert([pen + x, ascent - capHeight + row]) }
                        }
                        pen += 2 * half + 1
                    } else {
                        for column in 0...half {
                            let reach = way < 0 ? column : half - column
                            for y in (ascent - half - reach)...(ascent - half + reach) { ink.on.insert([pen + column, y]) }
                        }
                        pen += half + 1
                    }
                }
                ink.width = max(ink.width, pen)
            }
        }
        if underscore { letters("_", font: font, ascent: ascent, at: pen, into: &ink) }
        return ink
    }

    private func draw(count: Int, underscore: Bool) {
        let font = font()
        let ascent = Int(CTFontGetAscent(font).rounded(.up))
        let lineHeight = ascent + Int(CTFontGetDescent(font).rounded(.up)) + TutorialText.lineGap
        let capHeight = Int(CTFontGetCapHeight(font).rounded())
        // The block's width as it'll be all typed out, so it doesn't move as it types.
        fullWidth = lines.map { ink($0, limit: $0.count, underscore: underscored, font: font, ascent: ascent, capHeight: capHeight).width }.max() ?? 0
        // Line by line as far as it's typed, the underscore where the typing's got to.
        var on: [[Int]] = []
        var left = count
        var lastLine = 0
        for (index, line) in lines.enumerated() {
            lastLine = index
            let limit = min(left, line.count)
            left -= limit
            let atEnd = left == 0
            let inked = ink(line, limit: limit, underscore: underscore && atEnd, font: font, ascent: ascent, capHeight: capHeight)
            on += inked.on.map { [$0[0], $0[1] + index * lineHeight] }
            if atEnd { break }
        }
        let height = (lastLine + 1) * lineHeight
        let width = max(fullWidth, 1)
        var bytes = [UInt8](repeating: 0, count: width * max(height, 1) * 4)
        let r = UInt8(TutorialText.colour >> 16 & 0xFF), g = UInt8(TutorialText.colour >> 8 & 0xFF), b = UInt8(TutorialText.colour & 0xFF)
        for pixel in on where pixel[0] >= 0 && pixel[0] < width && pixel[1] >= 0 && pixel[1] < height {
            let at = (pixel[1] * width + pixel[0]) * 4
            bytes[at] = r; bytes[at + 1] = g; bytes[at + 2] = b; bytes[at + 3] = 255
        }
        let texture = FieldArt.pixelTexture(bytes, width: width, height: max(height, 1))
        node.texture = texture
        node.size = CGSize(width: width, height: max(height, 1))
        node.position = CGPoint(x: (top.x - CGFloat(fullWidth) / 2).rounded(), y: top.y)
    }
}
