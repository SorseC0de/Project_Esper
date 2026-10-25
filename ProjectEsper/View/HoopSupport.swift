import EsperSim
import SpriteKit
import UIKit

/// The hoops' supports: `hoop_support` pieces laid out free, as Hoopfish Hideaway's pile is,
/// around the hoop whose backboard is on the right, and drawn as one picture at each hoop, the
/// left one mirrored. A piece comes as painted, or dark: palette 13 and 12 ramped down to 12
/// and 11. Built in the support builder on the Wreck Center; kept between launches, standing in
/// for the baked layout.
enum HoopSupport {
    struct Piece: Codable, Equatable {
        var dark: Bool
        /// The half-length rod: the end caps with the middle 16 pixels taken out.
        var half = false
        /// Its middle from the hoop's art point, in whole art pixels, and its turn in degrees.
        var x: Int
        var y: Int
        var rotation: Int

        init(dark: Bool, half: Bool = false, x: Int, y: Int, rotation: Int) {
            self.dark = dark
            self.half = half
            self.x = x
            self.y = y
            self.rotation = rotation
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            dark = try values.decode(Bool.self, forKey: .dark)
            half = try values.decodeIfPresent(Bool.self, forKey: .half) ?? false
            x = try values.decode(Int.self, forKey: .x)
            y = try values.decode(Int.self, forKey: .y)
            rotation = try values.decode(Int.self, forKey: .rotation)
        }
    }

    /// Each stage's own layout: the Wreck Center's bars (K&A hangs its hoops on the same), and
    /// Anozira's pole assembly, from the truck's pole to its backboard.
    enum Layout {
        case wreckCenter, anozira

        init?(look: StageLook) {
            switch look {
            case .court, .kAndA: self = .wreckCenter
            case .anozira: self = .anozira
            default: return nil
            }
        }

        var baked: [Piece] { self == .anozira ? HoopSupport.anoziraBaked : HoopSupport.baked }
        var bakedName: String { self == .anozira ? "anoziraBaked" : "baked" }
        /// v2: the first layouts were made with the pieces drawn a third of their size.
        var savedKey: String { self == .anozira ? "esper.hoopSupport.anozira" : "esper.hoopSupport.v2" }
        /// Its pieces' colours swapped for the ones round them: Anozira's for the truck pole's greys
        /// (palette 13, 12 and 11 to 59, 60 and 61), after the dark ones' ramp down.
        var colours: [RGB: RGB] {
            self == .anozira ? [PixelPalette.colours[13]: PixelPalette.colours[59], PixelPalette.colours[12]: PixelPalette.colours[60],
                                PixelPalette.colours[11]: PixelPalette.colours[61]] : [:]
        }
        var key: Int { self == .anozira ? 4 : 0 }
    }

    /// The Wreck Center's layout baked in, from the builder's COPY.
    static let baked: [Piece] = [
        .init(dark: true, half: false, x: 28, y: 15, rotation: 90),
        .init(dark: true, half: false, x: 20, y: 1, rotation: -25),
        .init(dark: true, half: false, x: 5, y: 15, rotation: 90),
        .init(dark: true, half: false, x: 20, y: 11, rotation: 0),
        .init(dark: false, half: true, x: 11, y: 23, rotation: 90),
        .init(dark: false, half: false, x: 34, y: 9, rotation: 90),
        .init(dark: false, half: true, x: 34, y: 23, rotation: 90),
        .init(dark: false, half: false, x: 21, y: -8, rotation: 20),
        .init(dark: false, half: false, x: 21, y: 16, rotation: 0),
        .init(dark: false, half: false, x: 23, y: 5, rotation: -25),
    ]

    /// Anozira's pole assembly baked in, from the builder's COPY.
    static let anoziraBaked: [Piece] = [
        .init(dark: true, half: false, x: 15, y: 7, rotation: -30),
        .init(dark: true, half: false, x: 13, y: -6, rotation: 15),
        .init(dark: false, half: false, x: 18, y: 7, rotation: -45),
        .init(dark: false, half: false, x: 15, y: -9, rotation: 20),
    ]

    /// A stage's layout: the builder's, kept, or the baked one.
    static func pieces(_ layout: Layout) -> [Piece] {
        guard let data = UserDefaults.standard.data(forKey: layout.savedKey),
              let saved = try? JSONDecoder().decode([Piece].self, from: data) else { return layout.baked }
        return saved
    }
    static func keep(_ pieces: [Piece], for layout: Layout) {
        if let data = try? JSONEncoder().encode(pieces) { UserDefaults.standard.set(data, forKey: layout.savedKey) }
    }

    /// The layout as Swift, for its baked one.
    static func source(_ pieces: [Piece], for layout: Layout) -> String {
        let lines = pieces.map { "        .init(dark: \($0.dark), half: \($0.half), x: \($0.x), y: \($0.y), rotation: \($0.rotation)),"}
        return (["    static let \(layout.bakedName): [Piece] = ["] + lines + ["    ]"]).joined(separator: "\n")
    }

    /// A piece's picture, as painted or ramped down, whole or half, in its layout's colours.
    static func picture(dark: Bool, half: Bool = false, layout: Layout = .wreckCenter) -> CGImage? {
        let key = (dark ? 1 : 0) + (half ? 2 : 0) + layout.key
        if let made = pictures[key] { return made }
        let texture = SKTextureAtlas(named: "Sprites").textureNamed("hoop_support_0")
        let painted = texture.cgImage()
        let ramped = dark ? swapped(painted, [PixelPalette.colours[13]: PixelPalette.colours[12], PixelPalette.colours[12]: PixelPalette.colours[11]]) : painted
        let coloured = layout.colours.isEmpty ? ramped : ramped.flatMap { swapped($0, layout.colours) }
        let made = half ? coloured.flatMap(halved) : coloured
        pictures[key] = made
        return made
    }
    nonisolated(unsafe) private static var pictures: [Int: CGImage] = [:]

    /// The rod half as long: its first and last quarters side by side, end caps and all.
    private static func halved(_ image: CGImage) -> CGImage? {
        let quarter = image.width / 4
        guard let left = image.cropping(to: CGRect(x: 0, y: 0, width: quarter, height: image.height)),
              let right = image.cropping(to: CGRect(x: image.width - quarter, y: 0, width: quarter, height: image.height)),
              let context = CGContext(data: nil, width: quarter * 2, height: image.height, bitsPerComponent: 8, bytesPerRow: quarter * 8,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(left, in: CGRect(x: 0, y: 0, width: quarter, height: image.height))
        context.draw(right, in: CGRect(x: quarter, y: 0, width: quarter, height: image.height))
        return context.makeImage()
    }

    /// Colours swapped, all at once (the dark ramp's 13 to 12 and 12 to 11 don't chain), the rest as it is.
    private static func swapped(_ image: CGImage, _ swaps: [RGB: RGB]) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for pixel in 0..<(width * height) where pixels[pixel * 4 + 3] == 255 {
            let index = pixel * 4
            let rgb = RGB(pixels[index]) << 16 | RGB(pixels[index + 1]) << 8 | RGB(pixels[index + 2])
            guard let swap = swaps[rgb] else { continue }
            pixels[index] = UInt8((swap >> 16) & 0xFF)
            pixels[index + 1] = UInt8((swap >> 8) & 0xFF)
            pixels[index + 2] = UInt8(swap & 0xFF)
        }
        return context.makeImage()
    }

    /// The whole layout as one picture, each piece turned about its middle without smoothing;
    /// where the hoop's art point sits in it, as an anchor. Nil with nothing laid out.
    static func assembled(_ pieces: [Piece], layout: Layout = .wreckCenter) -> (texture: SKTexture, size: CGSize, anchor: CGPoint)? {
        guard !pieces.isEmpty, let side = picture(dark: false).map({ CGFloat(max($0.width, $0.height)) }) else { return nil }
        // Room for any turn of a piece round its middle.
        let reach = (side * 0.75).rounded(.up)
        let left = CGFloat(pieces.map(\.x).min()!) - reach, right = CGFloat(pieces.map(\.x).max()!) + reach
        let bottom = CGFloat(pieces.map(\.y).min()!) - reach, top = CGFloat(pieces.map(\.y).max()!) + reach
        let size = CGSize(width: right - left, height: top - bottom)
        let format = UIGraphicsImageRendererFormat()
        format.scale = HoopSupport.pictureScale
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.interpolationQuality = .none
            for piece in pieces {
                guard let picture = picture(dark: piece.dark, half: piece.half, layout: layout) else { continue }
                cg.saveGState()
                // The picture's y runs down: the hoop's up is its down.
                cg.translateBy(x: CGFloat(piece.x) - left, y: top - CGFloat(piece.y))
                cg.rotate(by: -CGFloat(piece.rotation) * .pi / 180)
                // CGContext draws images bottom up in this flipped space: flipped back for the draw.
                cg.scaleBy(x: 1, y: -1)
                cg.draw(picture, in: CGRect(x: -CGFloat(picture.width) / 2, y: -CGFloat(picture.height) / 2,
                                            width: CGFloat(picture.width), height: CGFloat(picture.height)))
                cg.restoreGState()
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        return (texture, size, CGPoint(x: -left / size.width, y: -bottom / size.height))
    }
    /// The assembled picture's pixels to an art pixel, so a turned piece keeps its steps.
    private static let pictureScale: CGFloat = 3
}
