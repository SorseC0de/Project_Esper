// A tool, not a part of the game: not on the TV, which has no computer to save to.
#if !os(tvOS)
import EsperSim
import SpriteKit
import UIKit

/// Longball Stadium's field and goalposts as a picture at one pixel an art pixel, for laying its
/// tiles round in Aseprite: the whole stage across, from four tiles under the floor up through its
/// sky, on the 16-pixel grid the stage's tiles are on (the floor's top 80 pixels up from the bottom).
enum LongballExporter {
    static let below: CGFloat = 64

    /// Debug builds launched with `debug.exportLongball` set: the field alone, the goalposts with their
    /// hoops alone, and the two together, saved into the app's temporary folder, `Longball/`.
    static func exportIfRequested(sprites: SpriteLibrary) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "debug.exportLongball") else { return }
        UserDefaults.standard.removeObject(forKey: "debug.exportLongball")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Longball", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pictures: [(String, Bool, Bool)] = [("longball_stage", true, true), ("longball_field", true, false), ("longball_goalposts", false, true)]
        for (name, field, goalposts) in pictures {
            guard let data = picture(sprites: sprites, field: field, goalposts: goalposts).flatMap({ UIImage(cgImage: $0).pngData() }) else { continue }
            try? data.write(to: folder.appendingPathComponent("\(name).png"))
        }
        try? "done".write(to: folder.appendingPathComponent("done"), atomically: true, encoding: .utf8)
        #endif
    }

    static func picture(sprites: SpriteLibrary, field: Bool, goalposts: Bool) -> CGImage? {
        let stage = Stage.footballField
        let width = stage.columns * 16, height = Int(below) + (stage.rows + stage.skyRows) * 16
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        // An art-pixel point's picture with its bottom left there, mirrored about that point's left.
        func draw(_ image: CGImage?, at point: CGPoint, mirrored: Bool = false, tint: SKColor? = nil) {
            guard let image else { return }
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.saveGState()
            context.translateBy(x: point.x, y: point.y + below)
            if mirrored { context.scaleBy(x: -1, y: 1) }
            if let tint {
                context.clip(to: rect, mask: image)
                context.setFillColor(tint.cgColor)
                context.fill(rect)
            } else {
                context.draw(image, in: rect)
            }
            context.restoreGState()
        }
        if field {
            // The field as the game builds it, its turf, end zones and numbers.
            let holder = SKNode()
            let handles = FieldArt.build(for: stage, into: holder)
            if let turf = handles.turf { draw(turf.texture?.cgImage(), at: turf.position) }
            for (zone, end) in zip(handles.endZones, [Facing.left, .right]) {
                guard let hoop = stage.hoops.first(where: { $0.backboard == end }) else { continue }
                let glow = sprites.look(for: 1 - hoop.owner).glow
                draw(zone.texture?.cgImage(), at: zone.position, tint: SKColor(rgb: EnergyColour.withGlow(glow)?.backLimbs ?? glow))
            }
            for group in handles.numbers {
                for case let sprite as SKSpriteNode in group.children { draw(sprite.texture?.cgImage(), at: group.position + sprite.position) }
            }
        }
        if goalposts, let goalpost = LongballArt.goalpost(stems: FieldRules.goalpostStems, forks: FieldRules.goalpostForks) {
            let pieces = HoopTuning.art(for: .footballField)
            for hoop in stage.hoops {
                let origin = LongballArt.goalpostOrigin(for: hoop)
                draw(goalpost, at: CGPoint(x: origin.x, y: origin.y), mirrored: origin.mirrored)
                // The hoop's frame by its middle, as the scene places it.
                let middle = GameScene.hoopArtPoint(for: hoop, on: .footballField)
                let mirrored = hoop.backboard == .left
                for name in [pieces.backboard, pieces.rim] {
                    draw(sprites.texture(name, 0).cgImage(), at: CGPoint(x: middle.x + (mirrored ? 24 : -24), y: middle.y - 24), mirrored: mirrored)
                }
            }
        }
        return context.makeImage()
    }
}
#endif
