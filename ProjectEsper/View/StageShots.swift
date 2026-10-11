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

    func texture(for stage: StageChoice) -> SKTexture? {
        if let made = textures[stage] { return made }
        guard let image = UIImage(contentsOfFile: file(for: stage).path) else { return nil }
        let texture = SKTexture(image: image)
        textures[stage] = texture
        return texture
    }

    func store(_ image: CGImage, for stage: StageChoice) {
        let picture = UIImage(cgImage: image)
        textures[stage] = SKTexture(image: picture)
        try? picture.pngData()?.write(to: file(for: stage))
        onStored?(stage)
    }
}
