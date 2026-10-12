import EsperSim
import SpriteKit
import UIKit

/// Each stage's big panel from its preview (the whole stage, `MangaPage.bigPanel`), taken off the
/// renderer as the preview's page fills and kept in the app's caches, for the stage select's
/// window to show. A stage whose preview hasn't played yet has none.
@MainActor
final class StageShots {
    static let shared = StageShots()
    private var textures: [StageChoice: SKTexture] = [:]
    private let folder: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = caches.appendingPathComponent("StageShots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
    /// A shot's come in: what's showing one can show it.
    var onStored: ((StageChoice) -> Void)?

    private func file(for stage: StageChoice) -> URL { folder.appendingPathComponent("\(stage).png") }

    /// A shot with the flat bands at its top and bottom cut off (a stage seen whole fitted with
    /// the colour beyond it over and under it, as K&A is), so the window shows the stage, not
    /// the padding; at most a third off each end.
    static func trimmed(_ image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        guard width > 0, height > 8,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        // Memory's first row is the picture's top.
        func flat(_ row: Int, like reference: Int) -> Bool {
            for x in stride(from: 0, to: width, by: 2) {
                let at = (row * width + x) * 4, ref = (reference * width) * 4
                for channel in 0..<3 where abs(Int(pixels[at + channel]) - Int(pixels[ref + channel])) > bandTolerance { return false }
            }
            return true
        }
        let most = height / 3
        var top = 0
        while top < most, flat(top, like: 0) { top += 1 }
        var bottom = 0
        while bottom < most, flat(height - 1 - bottom, like: height - 1) { bottom += 1 }
        guard top + bottom > 0 else { return image }
        return image.cropping(to: CGRect(x: 0, y: top, width: width, height: height - top - bottom)) ?? image
    }
    /// How far a pixel can be off the band's colour, a channel, and still be the band.
    static let bandTolerance = 6

    func texture(for stage: StageChoice) -> SKTexture? {
        if let made = textures[stage] { return made }
        // Trimmed again as it's read, for a shot kept before trimming was.
        guard let image = UIImage(contentsOfFile: file(for: stage).path)?.cgImage else { return nil }
        let texture = SKTexture(cgImage: StageShots.trimmed(image))
        textures[stage] = texture
        return texture
    }

    func store(_ image: CGImage, for stage: StageChoice) {
        let picture = UIImage(cgImage: StageShots.trimmed(image))
        textures[stage] = SKTexture(image: picture)
        try? picture.pngData()?.write(to: file(for: stage))
        onStored?(stage)
    }
}
