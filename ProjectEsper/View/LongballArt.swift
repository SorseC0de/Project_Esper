import CoreGraphics
import EsperSim
import SpriteKit
import UIKit

/// Longball Stadium's pixel art: each rim's goalpost put together from its pieces, and the stands
/// as painted with their lights over them, the lamps glowing.
enum LongballArt {
    private static func image(_ name: String) -> CGImage? { UIImage(named: name)?.cgImage }
    private static func picture(_ name: String) -> SKTexture {
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .nearest
        return texture
    }

    /// The crossbar's fall across its frame: its near end 32 pixels under its far one, 64 along.
    static let crossbarSlope: CGFloat = 0.5
    /// The goalpost's picture is the crossbar's frame wide.
    static let goalpostWidth = FieldRules.goalpostWidthPixels

    /// A goalpost's pieces: all of it, all but the near upright, or the near upright alone, which is
    /// drawn over the bodies.
    enum Part { case whole, back, nearUpright }

    /// A goalpost as one picture, the right rim's (the left's is it mirrored), up from the base's
    /// frame's foot: the base, `stems` stems, the bend on them, then the crossbar's frame centred on
    /// the bend's, `forks` forks on each of its ends and their caps. The crossbar's frame's left is
    /// the hoop's frame's.
    static func goalpost(stems: Int, forks: Int, part: Part = .whole) -> CGImage? {
        let bend = 64 + 16 * stems
        let foot = bend - 16
        let height = foot + 48 + 16 * forks + 16
        guard let context = CGContext(data: nil, width: goalpostWidth, height: height, bitsPerComponent: 8, bytesPerRow: goalpostWidth * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        func draw(_ name: String, _ x: Int, _ y: Int) {
            guard let piece = image(name) else { return }
            context.draw(piece, in: CGRect(x: x, y: y, width: piece.width, height: piece.height))
        }
        if part != .nearUpright {
            draw("LongballGoalpostBase", 48, 0)
            for stem in 0..<stems { draw("LongballGoalpostStem", 48, 64 + 16 * stem) }
            draw("LongballGoalpostBend", 16, bend)
            draw("LongballGoalpostAcross", 0, foot)
            // The far end's foot at the crossbar frame's top.
            for fork in 0..<forks { draw("LongballGoalpostForkFar", 0, foot + 48 + 16 * fork) }
            draw("LongballGoalpostCapFar", 0, foot + 48 + 16 * forks)
        }
        if part != .back {
            // The near end's 32 under the far one's.
            for fork in 0..<forks { draw("LongballGoalpostForkNear", 64, foot + 16 + 16 * fork) }
            draw("LongballGoalpostCapNear", 64, foot + 16 + 16 * forks)
        }
        return context.makeImage()
    }

    /// Where a goalpost's picture stands for a rim: its foot at `FieldRules.goalpostFootPixels`, its
    /// crossbar's frame's far side on the hoop's frame's (the left, mirrored for a backboard on the left).
    static func goalpostOrigin(for hoop: Hoop) -> (x: CGFloat, y: CGFloat, mirrored: Bool) {
        let rim = SpriteLibrary.point(hoop.position)
        let mirrored = hoop.backboard == .left
        let front = CGFloat(FieldRules.goalpostFrontOfRimPixels)
        return (mirrored ? rim.x + front : rim.x - front, CGFloat(FieldRules.goalpostFootPixels), mirrored)
    }

    static func goalpostNode(for hoop: Hoop, picture: CGImage) -> SKSpriteNode {
        let texture = SKTexture(cgImage: picture)
        texture.filteringMode = .nearest
        let node = SKSpriteNode(texture: texture)
        node.anchorPoint = .zero
        let origin = goalpostOrigin(for: hoop)
        node.position = CGPoint(x: origin.x, y: origin.y)
        node.xScale = origin.mirrored ? -1 : 1
        node.zPosition = -5
        return node
    }

    /// A goalpost's shadow: each of its pixels mirrored under the base's foot and sheared with the
    /// turf (`FieldArt.slope`), in white for the scene to tint; with where its bottom left goes.
    static func goalpostShadow(for hoop: Hoop, picture: CGImage, centre: CGFloat) -> (texture: SKTexture, origin: CGPoint)? {
        let width = picture.width, height = picture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Rows from the top in the bytes; up from the foot of the picture here.
        func opaque(_ x: Int, _ up: Int) -> Bool { bytes[((height - 1 - up) * width + x) * 4 + 3] > 0 }
        guard let footRow = (0..<height).first(where: { up in (0..<width).contains { opaque($0, up) } }) else { return nil }
        let origin = goalpostOrigin(for: hoop)
        let foot = Int(origin.y) + footRow
        var cast = Set<[Int]>()
        for up in footRow..<height {
            for x in 0..<width where opaque(x, up) {
                let worldX = origin.mirrored ? Int(origin.x) - 1 - x : Int(origin.x) + x
                let rise = CGFloat(up - footRow) + 0.5
                let slid = CGFloat(worldX) + 0.5 - FieldArt.slope(at: CGFloat(worldX) + 0.5, centre: centre) * rise
                cast.insert([Int(slid.rounded(.down)), foot - 1 - (up - footRow)])
            }
        }
        guard let minX = cast.map({ $0[0] }).min(), let maxX = cast.map({ $0[0] }).max(),
              let minY = cast.map({ $0[1] }).min(), let maxY = cast.map({ $0[1] }).max() else { return nil }
        let columns = maxX - minX + 1, rows = maxY - minY + 1
        var shadow = [UInt8](repeating: 0, count: columns * rows * 4)
        for pixel in cast {
            let at = ((maxY - pixel[1]) * columns + pixel[0] - minX) * 4
            shadow[at] = 255; shadow[at + 1] = 255; shadow[at + 2] = 255; shadow[at + 3] = 255
        }
        return (FieldArt.pixelTexture(shadow, width: columns, height: rows), CGPoint(x: minX, y: minY))
    }

    // MARK: Stadium

    /// The stands as painted (`LongballStadium_Map.aseprite`, by `Tools/import_stage_art.py`): the
    /// stadium's whole width, its foot `mapBelow` under the floor's foot; its shadow darkened in,
    /// its display strips over that.
    static let backdrop = picture("LongballStadiumBackdrop")
    static let mapBelow: CGFloat = 64
    static let stadiumLight = picture("LongballStadiumLight")
    static let lightpost = picture("LongballLightpost")
    static let downMarker = picture("LongballDownMarker")
    /// The lights where the map paints them, one every 24 tiles: the stadium lights along its top,
    /// the lightposts over the upper display strip and the shadow.
    static let lightSpacing: CGFloat = 384
    static let stadiumLightFirst = CGPoint(x: 48, y: 432)
    static let stadiumLightCount = 10
    static let lightpostFirst = CGPoint(x: 240, y: 256)
    static let lightpostCount = 9
    /// The lower display strip's live area, the map's palette 61 (its off colour), the stadium's
    /// width across. The upper one is off the screen and stays off.
    static let displayBottom: CGFloat = 64
    static let displayHeight = 32

    /// Under everything else of the field's; the lights over the strips' lettering.
    static let backdropZ: CGFloat = -20
    static let lightsZ: CGFloat = -15

    struct Stadium {
        var backdrop: SKSpriteNode
        var lights: [SKSpriteNode]
    }

    static func stadium(into parent: SKNode) -> Stadium {
        func sprite(_ texture: SKTexture, at point: CGPoint, z: CGFloat) -> SKSpriteNode {
            let node = SKSpriteNode(texture: texture)
            node.anchorPoint = .zero
            node.size = texture.size()
            node.position = point
            node.zPosition = z
            parent.addChild(node)
            return node
        }
        let backdrop = sprite(backdrop, at: CGPoint(x: 0, y: -mapBelow), z: backdropZ)
        let stadiumLights = (0..<stadiumLightCount).map { index in
            sprite(stadiumLight, at: stadiumLightFirst + CGPoint(x: CGFloat(index) * lightSpacing, y: 0), z: lightsZ)
        }
        let lightposts = (0..<lightpostCount).map { index in
            sprite(lightpost, at: lightpostFirst + CGPoint(x: CGFloat(index) * lightSpacing, y: 0), z: lightsZ)
        }
        return Stadium(backdrop: backdrop, lights: stadiumLights + lightposts)
    }

    /// A light's lamps alone, its white and cream (EDG64 16 and 1), what glows over it.
    private static func lamps(_ name: String) -> SKTexture? {
        guard let light = image(name) else { return nil }
        let width = light.width, height = light.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(light, in: CGRect(x: 0, y: 0, width: width, height: height))
        let lit: Set<RGB> = [PixelPalette.colours[16], PixelPalette.colours[1]]
        for at in stride(from: 0, to: bytes.count, by: 4) {
            let colour = RGB(bytes[at]) << 16 | RGB(bytes[at + 1]) << 8 | RGB(bytes[at + 2])
            if bytes[at + 3] == 0 || !lit.contains(colour) { bytes[at] = 0; bytes[at + 1] = 0; bytes[at + 2] = 0; bytes[at + 3] = 0 }
        }
        return FieldArt.pixelTexture(bytes, width: width, height: height)
    }
    private static let stadiumLightLamps = lamps("LongballStadiumLight")
    private static let lightpostLamps = lamps("LongballLightpost")

    /// The lit lamps over each light, for the glow's mask to let through.
    static func lampSnapshots(_ lights: [SKSpriteNode]) -> [BodySnapshot] {
        lights.compactMap { light in
            guard let lamps = light.texture === lightpost ? lightpostLamps : stadiumLightLamps else { return nil }
            return BodySnapshot(texture: lamps, position: light.position, anchor: .zero, xScale: 1, size: light.size)
        }
    }

    // MARK: Display

    /// The display's picture repeats every `displayRepeat` pixels: its parallelograms and rectangles
    /// in one layer, its chevrons, pointing right, in another, each in white for the scene to tint
    /// and a repeat wider than `width`, for sliding along it. Hard-edged, whole pixels.
    static let displayRepeat = 96
    static func displayShapes(width: Int) -> SKTexture {
        displayLayer(width: width) { set in
            // Parallelograms leaning a pixel across a pixel up: full height, and half.
            func parallelogram(_ left: Int, _ wide: Int, rows: ClosedRange<Int>) {
                for row in rows { for x in 0..<wide { set(left + x + (displayHeight - 1 - row), row) } }
            }
            func rectangle(_ left: Int, _ top: Int, _ wide: Int, _ high: Int) {
                for row in top..<(top + high) { for x in left..<(left + wide) { set(x, row) } }
            }
            parallelogram(0, 12, rows: 0...31)
            parallelogram(18, 3, rows: 0...31)
            parallelogram(70, 8, rows: 10...21)
            rectangle(44, 3, 28, 5)
            rectangle(44, 24, 14, 5)
            rectangle(62, 24, 6, 5)
            rectangle(30, 15, 34, 2)
            rectangle(84, 2, 10, 2)
        }
    }
    static func displayChevrons(width: Int) -> SKTexture {
        displayLayer(width: width) { set in
            // Three chevrons 24 high, their arms 4 across, the tip at the middle row.
            for left in [4, 16, 28] {
                for row in 4...27 {
                    let reach = 11 - Int(abs(Double(row) - 15.5).rounded(.down))
                    for x in 0..<4 { set(left + reach + x, row) }
                }
            }
        }
    }
    /// A layer's repeat drawn along `width` and a repeat more, rows top down.
    private static func displayLayer(width: Int, draw: ((Int, Int) -> Void) -> Void) -> SKTexture {
        let columns = width + displayRepeat
        var bytes = [UInt8](repeating: 0, count: columns * displayHeight * 4)
        var cell = [Bool](repeating: false, count: displayRepeat * displayHeight)
        draw { x, row in cell[row * displayRepeat + ((x % displayRepeat) + displayRepeat) % displayRepeat] = true }
        for row in 0..<displayHeight {
            for x in 0..<columns where cell[row * displayRepeat + x % displayRepeat] {
                let at = (row * columns + x) * 4
                bytes[at] = 255; bytes[at + 1] = 255; bytes[at + 2] = 255; bytes[at + 3] = 255
            }
        }
        return FieldArt.pixelTexture(bytes, width: columns, height: displayHeight)
    }

    /// `width` of a layer, slid `shift` pixels right along its repeat.
    static func displayWindow(_ layer: SKTexture, width: Int, shift: Int) -> SKTexture {
        let columns = CGFloat(width + displayRepeat)
        let start = CGFloat(displayRepeat - ((shift % displayRepeat) + displayRepeat) % displayRepeat)
        let window = SKTexture(rect: CGRect(x: start / columns, y: 0, width: CGFloat(width) / columns, height: 1), in: layer)
        window.filteringMode = .nearest
        return window
    }
}
