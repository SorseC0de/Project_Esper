import CoreGraphics
import Foundation

/// How a body's line is drawn. Normal: one pixel, only where a pixel's straight beside the
/// body, above or below it, never at a corner alone, as drawn by hand. Semibold: one pixel,
/// corners too (the stepped line). Bold: two pixels, as Normal's grown again.
/// Settings' PLAYER VISIBILITY picks the in-match players'; everywhere else it's Normal.
enum PlayerLineStyle: Int, CaseIterable {
    case normal, semibold, bold
    /// Whether a pixel this far off a body's pixel is next to it, for its line.
    func reaches(_ dx: Int, _ dy: Int) -> Bool { self == .semibold ? dx != 0 || dy != 0 : abs(dx) + abs(dy) == 1 }
    var width: Int { self == .bold ? 2 : 1 }
    /// A key's mark for the style: none for Normal.
    var keyMark: String { self == .normal ? "" : "_line\(rawValue)" }
}

/// A player frame recoloured in a look, on the CPU: every layer the figure is drawn in, as
/// pictures. Pure (CoreGraphics only), so the headless check (`Tools/PlayerArtCheck`) runs it too.
enum PlayerRecolour {
    /// Every layer one recolour makes, and the frame's map (`PlayerMap`) when one was asked for.
    struct Layers {
        var drawn: CGImage
        var head: CGImage?
        var energy: CGImage?
        var outline: CGImage?
        var glowMask: CGImage?
        var skin: CGImage?
        var thinOutline: CGImage?
        var centres: [BodyPart: CGPoint] = [:]
        var bareOutline: CGImage?
        var glowing: CGImage?
        var glowLine: CGImage?
        var bareGlowLine: CGImage?
        var map: PlayerMap?
        init(drawn: CGImage) { self.drawn = drawn }
    }

    static func canvas(width: Int, height: Int) -> (CGContext, UnsafeMutablePointer<UInt8>)? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        return (context, data.bindMemory(to: UInt8.self, capacity: width * height * 4))
    }

    /// The frames whose arms are drawn the other way round, the front arm behind, take row 1 of a
    /// look's palette; the frames whose bare arms and hands take each other's skin tone, row 2; the
    /// frames facing out, both hands in the skin's light tone, row 3; every other frame row 0.
    static let paletteRows = 4

    /// A look as one palette row draws it: row 1 swaps the front and back arm and hand colours; rows 2
    /// and 3 tone the bare arms and hands (`SpriteLibrary.look(_:for:)` picks the row by frame).
    static func adjusted(_ look: Look, row: Int) -> Look {
        var adjusted = look
        if row == 1 {
            for (front, back) in [(BodyPart.frontArm, BodyPart.backArm), (.frontHand, .backHand)] {
                let was = adjusted.colours[front]
                adjusted.colours[front] = adjusted.colours[back]
                adjusted.colours[back] = was
            }
        }
        let skinSwapped = row == 2
        let handsLit = row == 3
        if skinSwapped || handsLit {
            let skin = look.dressing.skin
            let tone = look.dressing.tone
            for part in [BodyPart.frontArm, .backArm, .frontHand, .backHand] {
                // Only what's showing its skin: a sleeve, or a look that isn't a human's, stays as it is.
                guard let own = skin[part], look.colours[part] == own else { continue }
                let hand = part == .frontHand || part == .backHand
                adjusted.colours[part] = handsLit ? (hand ? tone.front : tone.back) : (part.isBack ? tone.front : tone.back)
            }
        }
        return adjusted
    }

    /// A copy of the frame in the look: every part swapped to its colour, the stroked parts
    /// lined where they lie over the body, the silhouette lined round the outside, and the
    /// centre of each glowing part found. The ball is looked for only where the sheet
    /// `holdsBall`. With `detach`, the head and the energy come back as their own pictures
    /// with no line, and the body is drawn and lined without them.
    /// `hood`: the hooded head, its shape (`player_hoodheads`' drawn pixels) placed on the
    /// canvas, or with `hoodShape` placed as the game places it, moved from the idle frame it's
    /// drawn for by how far this frame's head is from that one's: the sheet's head is kept under
    /// it as its neck, in the skin's shadow tone, and the outside line runs round the body and
    /// the hood together, the hood's own pixels left clear for it to be drawn in.
    /// `map`: with `detach`, the frame's map made too, its colours on that row of the look's palette.
    static func recolour(image: CGImage, look: Look, holdsBall: Bool, detach: Bool, tucked: Bool = false, ballPixels: Set<Int>? = nil,
                         hood given: (shape: CGImage, origin: CGPoint, scale: CGFloat)? = nil, hoodShape: CGImage? = nil, hoodNudge: CGPoint = .zero,
                         bareLine: Bool = false, keepsProps: Bool = false, lineStyle: PlayerLineStyle = .normal,
                         hoodDrawnForHead: CGPoint?, ballMinPixels: Int, map: (row: Int, palette: [UInt8], lenient: Bool)? = nil) -> Layers {
        let width = image.width, height = image.height
        guard let (context, pixels) = canvas(width: width, height: height) else { return Layers(drawn: image) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let count = width * height
        // The line's pixels, for `detach` to lift onto their own canvas; each energy pixel's
        // grey, for the view to tone in any colour.
        var lined = [Bool](repeating: false, count: count)
        var greys = [Double](repeating: 0, count: count)

        // Which part each pixel came from, before anything changes.
        var parts = [BodyPart?](repeating: nil, count: count)
        for pixel in 0..<count where pixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            let colour = RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])
            let part = BodyPart.owning(colour)
            parts[pixel] = keepsProps && (part == .ball || part == .slash) ? nil : part
        }
        markEnergy(&parts, holdsBall: holdsBall, ballPixels: ballPixels, minPixels: tucked ? 1 : ballMinPixels, width: width, height: height)
        // Where the hood will be drawn over this canvas, if it's given or its shape is.
        var hood = given
        if hood == nil, let hoodShape, let there = hoodDrawnForHead {
            var sum = CGPoint.zero, heads = 0
            for pixel in 0..<count where parts[pixel] == .head {
                sum.x += CGFloat(pixel % width) + 0.5
                sum.y += CGFloat(pixel / width) + 0.5
                heads += 1
            }
            if heads > 0 {
                hood = (hoodShape, CGPoint(x: (sum.x / CGFloat(heads) - there.x).rounded() + hoodNudge.x, y: (sum.y / CGFloat(heads) - there.y).rounded() - hoodNudge.y), 1)
            }
        }
        var hoodCover = [Bool](repeating: false, count: count)
        var headTakenOut: [Int] = []
        if let hood, let (shapeContext, shapePixels) = canvas(width: hood.shape.width, height: hood.shape.height) {
            shapeContext.draw(hood.shape, in: CGRect(x: 0, y: 0, width: hood.shape.width, height: hood.shape.height))
            for pixel in 0..<count {
                let x = Int(((CGFloat(pixel % width) + 0.5 - hood.origin.x) / hood.scale).rounded(.down))
                let y = Int(((CGFloat(pixel / width) + 0.5 - hood.origin.y) / hood.scale).rounded(.down))
                guard (0..<hood.shape.width).contains(x), (0..<hood.shape.height).contains(y) else { continue }
                hoodCover[pixel] = shapePixels[(y * hood.shape.width + x) * 4 + 3] > 0
            }
            // The hooded head replaces the sheet's: any of the sheet's head showing past the hood is taken out.
            for pixel in 0..<count where parts[pixel] == .head && !hoodCover[pixel] {
                headTakenOut.append(pixel)
                parts[pixel] = nil
                for channel in 0..<4 { pixels[pixel * 4 + channel] = 0 }
            }
        }

        // Each part to its colour; the energy to the tone of its own brightness.
        var sums: [BodyPart: (x: CGFloat, y: CGFloat, n: Int)] = [:]
        for pixel in 0..<count {
            guard let part = parts[pixel] else { continue }
            let index = pixel * 4
            // The glowing parts' middles, and the head's however it's drawn: where the head
            // and its particles go.
            // And the limbs' ends, where cubes come off them; and the torso, for the hood down behind it.
            if part.glows(energyForm: look.energyForm) || part == .head || [.frontLeg, .backLeg, .frontFoot, .backFoot, .frontHand, .backHand, .frontArm, .backArm, .torso].contains(part) {
                var sum = sums[part] ?? (0, 0, 0)
                sum.x += CGFloat(pixel % width) + 0.5
                sum.y += CGFloat(pixel / width) + 0.5
                sum.n += 1
                sums[part] = sum
            }
            if part.isEnergy {
                let grey = (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / 255
                greys[pixel] = grey
                paint(pixels, index, look.energyTone(luminance: grey))
            } else if let target = look.colours[part] {
                paint(pixels, index, target)
            }
        }

        // The head and the energy onto their own canvases, and off this one; the ball off
        // this one too, since it's drawn as its own sprite wherever the frame puts it.
        var head: CGImage?
        var energyImage: CGImage?
        if detach {
            let headCanvas = sums[.head] != nil && look.headApart ? canvas(width: width, height: height) : nil
            let energyCanvas = parts.contains { $0?.isEnergy == true } ? canvas(width: width, height: height) : nil
            for pixel in 0..<count {
                // A human's head stays on the body.
                guard let part = parts[pixel], (part == .head && look.headApart) || part == .ball || part.isEnergy else { continue }
                let index = pixel * 4
                if part == .head, let (_, headPixels) = headCanvas {
                    paint(headPixels, index, look.colours[.head] ?? look.glow)
                    headPixels[index + 3] = 255
                } else if part.isEnergy, let (_, energyPixels) = energyCanvas {
                    // In grey: the view tones it through the energy ramp in whatever colour.
                    let level = UInt8((greys[pixel] * 255).rounded())
                    energyPixels[index] = level
                    energyPixels[index + 1] = level
                    energyPixels[index + 2] = level
                    energyPixels[index + 3] = 255
                }
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
                pixels[index + 3] = 0
                parts[pixel] = nil
            }
            head = headCanvas?.0.makeImage()
            energyImage = energyCanvas?.0.makeImage()
        }

        func neighbours(_ pixel: Int, _ body: (Int) -> Bool) -> Bool {
            let x = pixel % width, y = pixel / width
            for dy in -1...1 {
                for dx in -1...1 where lineStyle.reaches(dx, dy) {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, ny >= 0, nx < width, ny < height, body(ny * width + nx) { return true }
                }
            }
            return false
        }

        /// The glowing parts get no line round them; the head under the hood is the neck, and does.
        func lineless(_ part: BodyPart?) -> Bool {
            guard let part else { return false }
            return part == .head ? hood == nil && part.glows(energyForm: look.energyForm) : part.glows(energyForm: look.energyForm)
        }

        // Stroked groups: the body pixels next to one take the line, so it keeps its shape. A
        // pixel already lined is neither lined again nor counted as the group's, so where two
        // groups meet there's one line, not two.
        // With the hood given, the head is only its neck: no line of its own.
        for group in look.strokedGroups where hood == nil || !group.contains(.head) {
            let stroked = (0..<count).map { parts[$0].map(group.contains) == true && !lined[$0] }
            for pixel in 0..<count where parts[pixel] != nil && !stroked[pixel] && !lined[pixel] && neighbours(pixel, { stroked[$0] }) {
                paint(pixels, pixel * 4, look.outline)
                lined[pixel] = true
            }
        }

        // The body's line as thick as the style's, if the look has one.
        let lineWidth = look.outlineWidth > 0 ? lineStyle.width : 0

        // With `bareLine` and the hood's place given, the same line again round the body alone,
        // the hood's place left out of it, for a tipped hood that carries its own.
        var bareLined: [Bool]?
        if bareLine, detach, hood != nil, lineWidth > 0 {
            var lineHere = lined
            var filled = (0..<count).map { pixels[$0 * 4 + 3] != 0 }
            var body = (0..<count).map { filled[$0] && !lineless(parts[$0]) }
            for _ in 0..<lineWidth {
                let grown = (0..<count).filter { !filled[$0] && neighbours($0, { body[$0] }) }
                for pixel in grown {
                    filled[pixel] = true
                    body[pixel] = true
                    lineHere[pixel] = true
                }
            }
            bareLined = lineHere
        }

        // The outside line, grown a pixel at a time round the body. The glowing parts get
        // none: a clear pixel next to nothing but the ball stays clear.
        if lineWidth > 0 {
            var body = (0..<count).map { (pixels[$0 * 4 + 3] != 0 && !lineless(parts[$0])) || hoodCover[$0] }
            for _ in 0..<lineWidth {
                var grown: [Int] = []
                for pixel in 0..<count where pixels[pixel * 4 + 3] == 0 && !hoodCover[pixel] && neighbours(pixel, { body[$0] }) {
                    grown.append(pixel)
                }
                for pixel in grown {
                    paint(pixels, pixel * 4, look.outline)
                    pixels[pixel * 4 + 3] = 255
                    body[pixel] = true
                    lined[pixel] = true
                }
            }
        }

        // A human's head is the view's, `player_hoodheads` over it: the sheet's own is taken
        // out, its line left round where it was.
        // Under the hood, the neck in the skin's shadow tone.
        if hood != nil {
            for pixel in 0..<count where parts[pixel] == .head && !lined[pixel] {
                // The back hand's colour: the skin's back tone, or the ice look's back colour; in
                // FloState the skin's, as its face is.
                paint(pixels, pixel * 4, look.energyForm ? look.dressing.tone.back : look.colours[.backHand] ?? look.dressing.tone.back)
            }
        }
        if !look.energyForm, hood == nil {
            for pixel in 0..<count where parts[pixel] == .head && !lined[pixel] {
                for channel in 0..<4 { pixels[pixel * 4 + channel] = 0 }
            }
        }

        // A human's energy-coloured parts glow; the energy form glows all over but its bare
        // arms and legs, in their skin.
        // Under the hood the head is only the neck, in skin.
        func bareSkin(_ part: BodyPart?) -> Bool { part.map { $0 == .head ? hood != nil : look.dressing.skin[$0] != nil } == true }
        let glowing = (0..<count).map { !look.energyForm ? parts[$0].map(look.dressing.glowing.contains) == true : parts[$0] != nil && !bareSkin(parts[$0]) }

        // The glowing parts' share of the line: each line pixel whose nearest body pixel glows, a ring
        // at a time out from the body, so it doesn't creep along the line past where the part ends.
        // In white, for the view to draw over the line in the energy's dark (`EnergyColour.glowLine`).
        // The hood's place counts as glowing, the energy's colour as it is, so its line takes the dark too.
        // And without the hood's ring, for a tipped hood that carries its own line (`bareLined`).
        var glowLine: CGImage?, bareGlowLine: CGImage?
        if detach, lined.contains(true), glowing.contains(true) || hoodCover.contains(true),
           let (glowLineContext, glowLinePixels) = canvas(width: width, height: height) {
            let bareCanvas = bareLined != nil ? canvas(width: width, height: height) : nil
            var anyBare = false
            var ring = (0..<count).map { (pixels[$0 * 4 + 3] != 0 && !lined[$0]) || hoodCover[$0] ? 0 : -1 }
            var glows = (0..<count).map { ring[$0] == 0 && (glowing[$0] || hoodCover[$0]) }
            var any = false
            for distance in 1...(lineWidth + 1) {
                let reached = (0..<count).filter { lined[$0] && ring[$0] < 0 && neighbours($0, { ring[$0] >= 0 && ring[$0] < distance }) }
                let lit = reached.filter { pixel in neighbours(pixel, { ring[$0] >= 0 && ring[$0] < distance && glows[$0] }) }
                for pixel in reached { ring[pixel] = distance }
                for pixel in lit {
                    glows[pixel] = true
                    any = true
                    for channel in 0..<4 { glowLinePixels[pixel * 4 + channel] = 255 }
                    if let bareCanvas, bareLined?[pixel] == true {
                        anyBare = true
                        for channel in 0..<4 { bareCanvas.1[pixel * 4 + channel] = 255 }
                    }
                }
            }
            if any { glowLine = glowLineContext.makeImage() }
            if anyBare, let bareCanvas { bareGlowLine = bareCanvas.0.makeImage() }
        }

        // The line at half its thickness, on a canvas twice as fine: of each line pixel only the
        // quarters against the body, so it hugs it. FloState's rainbow line.
        var thinOutline: CGImage?
        if detach, lined.contains(true), let (thinContext, thinPixels) = canvas(width: width * 2, height: height * 2) {
            // The hood's place counts as body, so the line hugs it too.
            let body = (0..<count).map { (pixels[$0 * 4 + 3] != 0 && !lined[$0]) || hoodCover[$0] }
            func isBody(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height && body[y * width + x] }
            for pixel in 0..<count where lined[pixel] {
                let x = pixel % width, y = pixel / width
                for half in 0..<4 {
                    let dx = half % 2 == 0 ? -1 : 1, dy = half / 2 == 0 ? -1 : 1
                    guard isBody(x + dx, y) || isBody(x, y + dy) || isBody(x + dx, y + dy) else { continue }
                    let index = ((y * 2 + half / 2) * width * 2 + x * 2 + half % 2) * 4
                    for channel in 0..<4 { thinPixels[index + channel] = 255 }
                }
            }
            thinOutline = thinContext.makeImage()
        }

        // With `detach`, the line comes off onto its own canvas in white, so the view can
        // draw it in any colour, frame by frame.
        var outlineImage: CGImage?
        if detach, lined.contains(true), let (lineContext, linePixels) = canvas(width: width, height: height) {
            for pixel in 0..<count where lined[pixel] {
                let index = pixel * 4
                linePixels[index] = 255
                linePixels[index + 1] = 255
                linePixels[index + 2] = 255
                linePixels[index + 3] = 255
                pixels[index] = 0
                pixels[index + 1] = 0
                pixels[index + 2] = 0
                pixels[index + 3] = 0
            }
            outlineImage = lineContext.makeImage()
        }

        var bareOutlineImage: CGImage?
        if let bareLined, let (bareContext, barePixels) = canvas(width: width, height: height) {
            for pixel in 0..<count where bareLined[pixel] {
                for channel in 0..<4 { barePixels[pixel * 4 + channel] = 255 }
            }
            bareOutlineImage = bareContext.makeImage()
        }

        // The glowing parts alone, as drawn: over K&A's wash, so the night doesn't dim them.
        var glowingImage: CGImage?
        if detach, glowing.contains(true), let (partsContext, partsPixels) = canvas(width: width, height: height) {
            for pixel in 0..<count where pixels[pixel * 4 + 3] != 0 && glowing[pixel] {
                for channel in 0..<4 { partsPixels[pixel * 4 + channel] = pixels[pixel * 4 + channel] }
            }
            glowingImage = partsContext.makeImage()
        }

        // The body as the glow's mask sees it, in white, the glowing pixels black so they take
        // the glow's plain threshold rather than the body's, whatever's under them: left out, a
        // stage's flat backdrop showed through and they didn't glow. A human's skin is green, so
        // it never glows however light it is.
        var glowMask: CGImage?
        if detach, glowing.contains(true), let (maskContext, maskPixels) = canvas(width: width, height: height) {
            for pixel in 0..<count where pixels[pixel * 4 + 3] != 0 && glowing[pixel] {
                maskPixels[pixel * 4 + 3] = 255
            }
            for pixel in 0..<count where pixels[pixel * 4 + 3] != 0 && !glowing[pixel] {
                let index = pixel * 4
                // Skin is green, never glowing; the neck under the hood red, shielded as the face over it is,
                // so the hood's bloom lights neither and no edge shows between them.
                let skin = bareSkin(parts[pixel])
                let neck = skin && parts[pixel] == .head
                maskPixels[index] = skin && !neck ? 0 : 255
                maskPixels[index + 1] = neck ? 0 : 255
                maskPixels[index + 2] = skin ? 0 : 255
                maskPixels[index + 3] = 255
            }
            // Pixel-exact, as the body's drawn: smoothed, its edges blended skin into body and glowed.
            glowMask = maskContext.makeImage()
        }

        // A human's skin alone in white, as it's drawn: for the
        // FloState lockout's flash.
        // A human's clothes alone in white, the dark ones and the energy's, as drawn: for the
        // FloState lockout's flash.
        var skin: CGImage?
        if detach, !look.energyForm, let (skinContext, skinPixels) = canvas(width: width, height: height) {
            var any = false
            for pixel in 0..<count where pixels[pixel * 4 + 3] != 0 && !lined[pixel]
                && parts[pixel].map({ HumanLook.clothed.contains($0) || look.dressing.glowing.contains($0) }) == true {
                let index = pixel * 4
                for channel in 0..<4 { skinPixels[index + channel] = 255 }
                any = true
            }
            if any { skin = skinContext.makeImage() }
        }

        guard let recoloured = context.makeImage() else { return Layers(drawn: image) }
        // The head's middle as the sheet draws it, what was taken out still counted: the hood was placed by it.
        if !headTakenOut.isEmpty, var head = sums[.head] {
            for pixel in headTakenOut {
                head.x += CGFloat(pixel % width) + 0.5
                head.y += CGFloat(pixel / width) + 0.5
                head.n += 1
            }
            sums[.head] = head
        }
        let centres = sums.mapValues { CGPoint(x: $0.x / CGFloat($0.n), y: $0.y / CGFloat($0.n)) }
        var layers = Layers(drawn: recoloured)
        layers.head = head
        layers.energy = energyImage
        layers.outline = outlineImage
        layers.glowMask = glowMask
        layers.skin = skin
        layers.thinOutline = thinOutline
        layers.centres = centres
        layers.bareOutline = bareOutlineImage
        layers.glowing = glowingImage
        layers.glowLine = glowLine
        layers.bareGlowLine = bareGlowLine
        if detach, let map {
            layers.map = PlayerMap.make(layers: layers, parts: parts, hooded: hood != nil, row: map.row, palette: map.palette, width: width, height: height,
                                        lenient: map.lenient)
        }
        return layers
    }

    /// The sheets' white is the ball only on a sheet that holds it, and there only where
    /// it's the biggest 8-connected blob of white in the frame and big enough to be one;
    /// every other white pixel becomes energy: the skid's puffs, a release's streaks, the
    /// slide's speed lines.
    /// `ballPixels`: the ball as `sheetBall` found it, taken as it is.
    private static func markEnergy(_ parts: inout [BodyPart?], holdsBall: Bool, ballPixels: Set<Int>?, minPixels: Int, width: Int, height: Int) {
        guard holdsBall else {
            for pixel in parts.indices where parts[pixel] == .ball { parts[pixel] = .energy }
            return
        }
        if let ballPixels {
            for pixel in parts.indices where parts[pixel] == .ball && !ballPixels.contains(pixel) { parts[pixel] = .energy }
            return
        }
        var label = [Int](repeating: 0, count: parts.count)
        var sizes = [0]
        for start in parts.indices where parts[start] == .ball && label[start] == 0 {
            let id = sizes.count
            sizes.append(0)
            label[start] = id
            var stack = [start]
            while let pixel = stack.popLast() {
                sizes[id] += 1
                let x = pixel % width, y = pixel / width
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let neighbour = ny * width + nx
                        if parts[neighbour] == .ball, label[neighbour] == 0 {
                            label[neighbour] = id
                            stack.append(neighbour)
                        }
                    }
                }
            }
        }
        guard sizes.count > 1, let biggest = sizes.indices.dropFirst().max(by: { sizes[$0] < sizes[$1] }) else { return }
        let ball = sizes[biggest] >= minPixels ? biggest : 0
        for pixel in parts.indices where parts[pixel] == .ball && label[pixel] != ball {
            parts[pixel] = .energy
        }
    }

    private static func paint(_ pixels: UnsafeMutablePointer<UInt8>, _ index: Int, _ colour: RGB) {
        pixels[index] = UInt8((colour >> 16) & 0xFF)
        pixels[index + 1] = UInt8((colour >> 8) & 0xFF)
        pixels[index + 2] = UInt8(colour & 0xFF)
    }

}
