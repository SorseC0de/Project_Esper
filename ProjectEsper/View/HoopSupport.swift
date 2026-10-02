import SpriteKit
import UIKit

/// The hoops' supports: `hoop_support` pieces laid out free, as Hoopfish Hideaway's pile is,
/// around the hoop whose backboard is on the right, and drawn as one picture at each hoop, the
/// left one mirrored. A piece comes as painted, or dark: palette 40 and 41 ramped down to 41
/// and 42. Built in the support builder on the Wreck Center; kept between launches, standing in
/// for the baked layout.
enum HoopSupport {
    struct Piece: Codable, Equatable {
        var dark: Bool
        /// Its middle from the hoop's art point, in whole art pixels, and its turn in degrees.
        var x: Int
        var y: Int
        var rotation: Int
    }

    /// The layout baked in, from the builder's COPY.
    static let baked: [Piece] = []

    private static let savedKey = "esper.hoopSupport"
    static var pieces: [Piece] {
        get {
            guard let data = UserDefaults.standard.data(forKey: savedKey),
                  let saved = try? JSONDecoder().decode([Piece].self, from: data) else { return baked }
            return saved
        }
        set { if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: savedKey) } }
    }

    /// The layout as Swift, for `baked`.
    static func source(_ pieces: [Piece]) -> String {
        let lines = pieces.map { "        .init(dark: \($0.dark), x: \($0.x), y: \($0.y), rotation: \($0.rotation)),"}
        return (["    static let baked: [Piece] = ["] + lines + ["    ]"]).joined(separator: "\n")
    }

    /// A piece's picture, as painted or ramped down.
    static func picture(dark: Bool) -> CGImage? {
        if let made = pictures[dark] { return made }
        let texture = SKTextureAtlas(named: "Sprites").textureNamed("hoop_support_0")
        let painted = texture.cgImage()
        let made = dark ? rampedDown(painted) : painted
        pictures[dark] = made
        return made
    }
    nonisolated(unsafe) private static var pictures: [Bool: CGImage] = [:]

    /// Palette 40 to 41 and 41 to 42, the rest as it is.
    private static func rampedDown(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = context.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let swaps = [PixelPalette.colours[40]: PixelPalette.colours[41], PixelPalette.colours[41]: PixelPalette.colours[42]]
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
    static func assembled(_ pieces: [Piece]) -> (texture: SKTexture, anchor: CGPoint)? {
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
                guard let picture = picture(dark: piece.dark) else { continue }
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
        return (texture, CGPoint(x: -left / size.width, y: -bottom / size.height))
    }
    /// The assembled picture's pixels to an art pixel, so a turned piece keeps its steps.
    static let pictureScale: CGFloat = 3
}
