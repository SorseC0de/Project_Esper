import EsperSim
import SpriteKit
import UIKit

/// The Wreck Center drawn whole from its Aseprite map (`Tools/import_stage_art.py wreck`), in
/// place of the flat tiles: back to front the background and back wall, the back wall's
/// possession pixels (palette 60), the tiles, the tiles' possession pixels (palette 59), and the
/// extras. The sim's tiles are the court's as ever; the art's bigger than the court, its box one
/// tile in from the art's sides and bottom, the rest padding the camera doesn't frame.
enum WreckCenterArt {
    /// The art's bottom left from the stage's, in art pixels.
    static let origin = CGPoint(x: -16, y: -16)
    /// Past the art: its background's colour.
    static let beyond: RGB = 0x2A2F4E
    /// The possession pixels unheld: the tiles' palette 59, held the energy set's colour. The back
    /// wall's, palette 60, stay their grey.
    static let tilesNeutral: RGB = 0x5D5D5D
    static let backNeutral: RGB = 0x3D3D3D
    /// Possession colours that read too bright on the floor's stripe, taken down
    /// to this share of their brightness.
    static let possessionShare: [EnergyColour: Double] = [.pink: 0.8]
    /// 47's three-point lines drawn on the back wall: over its possession pixels, under the tiles.
    static let threePointZ: CGFloat = -7.85

    /// Its pieces' frames a second, and the displays' pixels that light: white and its two greys.
    static let piecesPerSecond: Double = 10
    static let displayLitColours: Set<UInt32> = [0xFFFFFF, 0xC7CFDD, 0x92A1B9]
    static let piecesZ: CGFloat = -7.65
    /// The platforms and belts, which are in play: over the darkening wash, never under it.
    static let inPlayZ: CGFloat = -7.5
    static func isInPlay(_ kind: StageMap.PropKind) -> Bool { ![.displayFloor, .displayWall].contains(kind) }

    /// The map's darkening wash (its Background Dimmer, Aseprite's Darken): baked into the
    /// pictures by the importer; here, where it lies, for the displays put under it.
    struct Wash {
        let width: Int, height: Int
        let covered: [Bool]
        /// Its colour, 0 to 1, and its opacity.
        let colour: (red: CGFloat, green: CGFloat, blue: CGFloat)
        let alpha: CGFloat

        /// Whether it lies over this pixel of the stage, counted from the stage's bottom left.
        func covers(x: Int, y: Int) -> Bool {
            let column = x - Int(WreckCenterArt.origin.x), up = y - Int(WreckCenterArt.origin.y)
            guard column >= 0, column < width, up >= 0, up < height else { return false }
            return covered[(height - 1 - up) * width + column]
        }

        /// A colour as the wash leaves it: each channel the darker of the two, at its opacity.
        func darkened(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
            func channel(_ value: CGFloat, _ wash: CGFloat) -> CGFloat { value + (min(wash, value) - value) * alpha }
            return (channel(red, colour.red), channel(green, colour.green), channel(blue, colour.blue))
        }
    }
    static let wash: Wash? = {
        guard let image = UIImage(named: "WreckCenterDarken")?.cgImage, let (pixels, width, height) = WreckCenterArt.rgba(image) else { return nil }
        let covered = stride(from: 0, to: pixels.count, by: 4).map { pixels[$0 + 3] > 0 }
        guard let first = covered.firstIndex(of: true) else { return nil }
        // Premultiplied as drawn: the colour back out from under its alpha.
        let alpha = CGFloat(pixels[first * 4 + 3]) / 255
        func channel(_ offset: Int) -> CGFloat { CGFloat(pixels[first * 4 + offset]) / 255 / alpha }
        return Wash(width: width, height: height, covered: covered, colour: (channel(0), channel(1), channel(2)), alpha: alpha)
    }()

    /// An image's pixels, premultiplied RGBA, top row first.
    fileprivate static func rgba(_ image: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }
    fileprivate static func texture(_ pixels: [UInt8], width: Int, height: Int) -> SKTexture? {
        var pixels = pixels
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = context.makeImage() else { return nil }
        let made = SKTexture(cgImage: image)
        made.filteringMode = .nearest
        return made
    }

    /// A piece as placed: its frames, darkened where the wash lies over it; and its lit pixels,
    /// out from under the wash in their own greys, tinted, and under it each grey alone in white,
    /// tinted the grey's darkened colour.
    final class Piece {
        let kind: StageMap.PropKind
        let cell: StageMap.Cell
        let base: SKSpriteNode
        let frames: [SKTexture]
        let lit: [(node: SKSpriteNode, frames: [SKTexture], under: RGB?)]

        init(kind: StageMap.PropKind, cell: StageMap.Cell, base: SKSpriteNode, frames: [SKTexture], lit: [(node: SKSpriteNode, frames: [SKTexture], under: RGB?)]) {
            self.kind = kind
            self.cell = cell
            self.base = base
            self.frames = frames
            self.lit = lit
        }
    }

    final class Handles {
        /// The painted pictures, kept out of the glow.
        let flats: [SKSpriteNode]
        /// The possession pixels in white, tinted the court's colour, glowing; the back wall's
        /// under the wash apart, tinted as the wash leaves its colour.
        let backLit: SKSpriteNode
        let backLitDarkened: SKSpriteNode?
        let tilesLit: SKSpriteNode
        let parent: SKNode
        /// The map's pieces: each animated, the displays with their lit pixels over them.
        fileprivate(set) var pieces: [Piece] = []
        fileprivate var displayColour = SKColor.white
        /// Whether the court's held: neutral, the possession pixels stay out of the glow.
        fileprivate(set) var held = false
        /// The Tutorial's second copy of its map (its tiles and extras, and its tiles' possession
        /// pixels), its doors and its floor's belt, each piece with its frames.
        var copies: [SKSpriteNode] = []
        var tilesLitCopy: SKSpriteNode?
        var doors: [SKSpriteNode] = []
        var belt: [(node: SKSpriteNode, frames: [SKTexture])] = []

        init(flats: [SKSpriteNode], backLit: SKSpriteNode, backLitDarkened: SKSpriteNode?, tilesLit: SKSpriteNode, parent: SKNode) {
            self.flats = flats
            self.backLit = backLit
            self.backLitDarkened = backLitDarkened
            self.tilesLit = tilesLit
            self.parent = parent
        }

        /// The pieces as the mask should mark them: none of the art glows but the lit pixels.
        var pieceFlats: [BodySnapshot] {
            pieces.compactMap { piece in
                piece.base.texture.map { BodySnapshot(texture: $0, position: piece.base.position, anchor: .zero, xScale: piece.base.xScale, size: WreckCenterArt.size(piece.kind)) }
            } + (copies + doors + belt.map(\.node)).compactMap { node in
                node.texture.map { BodySnapshot(texture: $0, position: node.position, anchor: .zero, xScale: node.xScale, size: node.size) }
            }
        }

        /// What glows through the flats under it: the possession pixels, while the court's held.
        var glowing: [BodySnapshot] {
            guard held else { return [] }
            return [tilesLit, tilesLitCopy].compactMap { $0 }.filter { !$0.isHidden }.compactMap { node in
                node.texture.map { BodySnapshot(texture: $0, position: node.position, anchor: .zero, xScale: 1, size: node.size) }
            }
        }

        /// The displays' screens, glowing through their own pieces, which don't.
        var screens: [BodySnapshot] {
            pieces.flatMap { piece in
                piece.lit.compactMap { lit in
                    lit.node.texture.map { BodySnapshot(texture: $0, position: lit.node.position, anchor: .zero, xScale: lit.node.xScale, size: WreckCenterArt.size(piece.kind)) }
                }
            }
        }

        /// The map's pieces put down again, each with its bottom left on its cell.
        func setPieces(_ placed: [StageMap.Prop]) {
            pieces.forEach { piece in
                piece.base.removeFromParent()
                piece.lit.forEach { $0.node.removeFromParent() }
            }
            pieces = placed.compactMap { prop in
                guard let sources = WreckCenterArt.sources[prop.kind], let drawn = WreckCenterArt.frames[prop.kind] else { return nil }
                let size = WreckCenterArt.size(prop.kind)
                let flipped = WreckCenterArt.isFlipped(prop.kind)
                let origin = CGPoint(x: CGFloat(prop.cell.column) * 16 + (flipped ? size.width : 0), y: CGFloat(prop.cell.row) * 16)
                let z = WreckCenterArt.isInPlay(prop.kind) ? WreckCenterArt.inPlayZ : WreckCenterArt.piecesZ
                func node(_ texture: SKTexture, z: CGFloat) -> SKSpriteNode {
                    let sprite = SKSpriteNode(texture: texture)
                    sprite.anchorPoint = .zero
                    sprite.size = size
                    sprite.xScale = flipped ? -1 : 1
                    sprite.position = origin
                    sprite.zPosition = z
                    parent.addChild(sprite)
                    return sprite
                }
                // Only what's only to look at goes under the wash; the pieces in play are over it.
                let washed = WreckCenterArt.isInPlay(prop.kind) ? nil : WreckCenterArt.wash
                let lights = !WreckCenterArt.isInPlay(prop.kind)
                var frames: [SKTexture] = [], litOut: [SKTexture] = [], litUnder: [RGB: [SKTexture]] = [:]
                var anyOut = false, anyUnder: Set<RGB> = []
                for (index, source) in sources.enumerated() {
                    let (pixels, width, height) = source
                    var base = pixels, out = [UInt8](repeating: 0, count: pixels.count)
                    var under: [RGB: [UInt8]] = [:]
                    for pixel in 0..<(width * height) where pixels[pixel * 4 + 3] == 255 {
                        let i = pixel * 4
                        let colour = RGB(pixels[i]) << 16 | RGB(pixels[i + 1]) << 8 | RGB(pixels[i + 2])
                        let column = pixel % width, row = pixel / width
                        let x = Int(prop.cell.column) * 16 + (flipped ? width - 1 - column : column), y = Int(prop.cell.row) * 16 + height - 1 - row
                        let covered = washed?.covers(x: x, y: y) ?? false
                        if covered, let washed {
                            let dark = washed.darkened(CGFloat(pixels[i]) / 255, CGFloat(pixels[i + 1]) / 255, CGFloat(pixels[i + 2]) / 255)
                            base[i] = UInt8((dark.0 * 255).rounded()); base[i + 1] = UInt8((dark.1 * 255).rounded()); base[i + 2] = UInt8((dark.2 * 255).rounded())
                        }
                        guard lights, WreckCenterArt.displayLitColours.contains(UInt32(colour)) else { continue }
                        if covered {
                            under[colour, default: [UInt8](repeating: 0, count: pixels.count)].replaceSubrange(i..<(i + 4), with: [255, 255, 255, 255])
                            anyUnder.insert(colour)
                        } else {
                            out.replaceSubrange(i..<(i + 4), with: pixels[i..<(i + 4)])
                            anyOut = true
                        }
                    }
                    frames.append(washed == nil ? drawn[index] : WreckCenterArt.texture(base, width: width, height: height) ?? drawn[index])
                    if lights {
                        // A frame with none of a layer's pixels is a clear frame, never an empty texture, which draws as a box.
                        let clear = [UInt8](repeating: 0, count: pixels.count)
                        litOut.append(WreckCenterArt.texture(out, width: width, height: height) ?? drawn[index])
                        for grey in WreckCenterArt.displayLitColours.map({ RGB($0) }) {
                            litUnder[grey, default: []].append(WreckCenterArt.texture(under[grey] ?? clear, width: width, height: height) ?? drawn[index])
                        }
                    }
                }
                let base = node(frames[0], z: z)
                var lit: [(node: SKSpriteNode, frames: [SKTexture], under: RGB?)] = []
                if anyOut { lit.append((node(litOut[0], z: z + 0.01), litOut, nil)) }
                for grey in anyUnder.sorted() { lit.append((node(litUnder[grey]![0], z: z + 0.01), litUnder[grey]!, grey)) }
                for entry in lit { entry.node.colorBlendFactor = 1 }
                let piece = Piece(kind: prop.kind, cell: prop.cell, base: base, frames: frames, lit: lit)
                WreckCenterArt.colourLights(piece, displayColour)
                return piece
            }
        }
    }

    /// Each piece's sheet in the sprite atlas; the flipped conveyors are their own strips mirrored.
    private static func sheet(_ kind: StageMap.PropKind) -> String? {
        switch kind {
        case .onewayPlatform: "oneway_platform"
        case .conveyorL, .flippedConveyorL: "conveyor_l"
        case .conveyorM, .flippedConveyorM: "conveyor_m"
        case .conveyorR, .flippedConveyorR: "conveyor_r"
        case .displayFloor: "display_floor"
        case .displayWall: "display_wall"
        default: nil
        }
    }
    private static func frameCount(_ kind: StageMap.PropKind) -> Int { kind == .onewayPlatform ? 8 : 4 }
    static func isFlipped(_ kind: StageMap.PropKind) -> Bool { [.flippedConveyorL, .flippedConveyorM, .flippedConveyorR].contains(kind) }
    static func size(_ kind: StageMap.PropKind) -> CGSize { CGSize(width: kind.pixelSize.width, height: kind.pixelSize.height) }

    /// Every piece's frames, and the displays' lit pixels in their own greys, made at loading.
    static let frames: [StageMap.PropKind: [SKTexture]] = {
        let atlas = SKTextureAtlas(named: "Sprites")
        var all: [StageMap.PropKind: [SKTexture]] = [:]
        for kind in StageMap.PropKind.kinds(for: .wreckCenter) {
            guard let sheet = sheet(kind) else { continue }
            all[kind] = (0..<frameCount(kind)).map { frame in
                let texture = atlas.textureNamed("\(sheet)_\(frame)")
                texture.filteringMode = .nearest
                return texture
            }
        }
        return all
    }()
    /// Every piece's frames read out once, for placing them over and under the wash.
    static let sources: [StageMap.PropKind: [(pixels: [UInt8], width: Int, height: Int)]] = {
        frames.compactMapValues { textures in
            let read = textures.compactMap { rgba($0.cgImage()) }
            return read.count == textures.count ? read : nil
        }
    }()

    /// A display's lit pixels in the shown colour: out from under the wash as drawn times it; under
    /// it, each grey times it, darkened as the wash leaves it.
    fileprivate static func colourLights(_ piece: Piece, _ colour: SKColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        for lit in piece.lit {
            guard let grey = lit.under, let wash else {
                lit.node.color = colour
                continue
            }
            let dark = wash.darkened(CGFloat((grey >> 16) & 0xFF) / 255 * r, CGFloat((grey >> 8) & 0xFF) / 255 * g, CGFloat(grey & 0xFF) / 255 * b)
            lit.node.color = SKColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)
        }
    }

    /// The pieces on their frame for this moment, the belts and displays all in step; a
    /// platform on its first frame, or where its turn in the sim has it.
    static func animate(_ handles: Handles, at time: TimeInterval, match: Match) {
        let tick = Int(time * piecesPerSecond)
        // The Tutorial's belt, running, as fast as it carries (its art moves the Wreck Center belt's
        // 2 pixels a frame, so its frames come that many times as often); still, on its first.
        if let belt = match.stage.conveyors.first, !handles.belt.isEmpty {
            let beltTick = belt.running ? Int(time * piecesPerSecond * belt.speed / WreckCenterRules.beltSpeed) : 0
            for piece in handles.belt where !piece.frames.isEmpty { piece.node.texture = piece.frames[beltTick % piece.frames.count] }
        }
        for piece in handles.pieces {
            let frames = piece.frames, cell = piece.cell
            guard !frames.isEmpty else { continue }
            var frame = tick % frames.count
            if piece.kind == .onewayPlatform {
                let index = match.stage.dropPlatforms.firstIndex { $0.columns.lowerBound == cell.column && $0.row == cell.row + 1 }
                let left = index.flatMap { match.dropPlatformFrames.indices.contains($0) ? match.dropPlatformFrames[$0] : nil } ?? 0
                frame = min(WreckCenterRules.platformArtFrame(framesLeft: left), frames.count - 1)
            }
            piece.base.texture = frames[frame]
            for lit in piece.lit where lit.frames.indices.contains(frame) { lit.node.texture = lit.frames[frame] }
        }
    }

    /// `map`: the pictures' names' start, "WreckCenter", or "Tutorial" for the Tutorial's map
    /// (no back wall, so none of its possession pixels: those nodes left empty and hidden).
    static func build(into parent: SKNode, map: String = "WreckCenter") -> Handles? {
        guard UIImage(named: "\(map)Back") != nil else { return nil }
        func picture(_ name: String, z: CGFloat) -> SKSpriteNode {
            let node = SKSpriteNode()
            if UIImage(named: name) != nil {
                let texture = SKTexture(imageNamed: name)
                texture.filteringMode = .nearest
                node.texture = texture
                node.size = texture.size()
            } else {
                node.isHidden = true
            }
            node.anchorPoint = .zero
            node.position = origin
            node.zPosition = z
            parent.addChild(node)
            return node
        }
        let back = picture("\(map)Back", z: -8.0)
        let backLit = picture("\(map)BackLit", z: -7.9)
        backLit.colorBlendFactor = 1
        let backLitDarkened = UIImage(named: "\(map)BackLitDarkened") == nil ? nil : picture("\(map)BackLitDarkened", z: -7.9)
        backLitDarkened?.colorBlendFactor = 1
        let tiles = picture("\(map)Tiles", z: -7.8)
        let tilesLit = picture("\(map)TilesLit", z: -7.7)
        tilesLit.colorBlendFactor = 1
        let extras = picture("\(map)Extras", z: -7.6)
        _ = (sources, wash)
        return Handles(flats: [back, tiles, extras], backLit: backLit, backLitDarkened: backLitDarkened, tilesLit: tilesLit, parent: parent)
    }

    /// The Tutorial: its map again to the right of the first (`copyShift` along), so the way on reads
    /// as one hall; its doors (`TutorialDoor`, 16 frames of 32 by 64 down the strip), all facing
    /// left, in the openings at each end of the floor, the copies' shared one between them; and its
    /// belt the floor's whole length under both, the Wreck Center's conveyor pieces end to end (L,
    /// the Ms, R), their tops the floor's. Doors and belt in play, over the wash; the doors shut and
    /// the belt still, on their first frames.
    static let doorFrames: [SKTexture] = {
        let sheet = SKTexture(imageNamed: "TutorialDoor")
        sheet.filteringMode = .nearest
        let count = max(Int(sheet.size().height / 64), 1)
        return (0..<count).map { row in
            let cell = SKTexture(rect: CGRect(x: 0, y: CGFloat(count - 1 - row) / CGFloat(count), width: 1, height: 1 / CGFloat(count)), in: sheet)
            cell.filteringMode = .nearest
            return cell
        }
    }()
    static let doorSize = CGSize(width: 32, height: 64)
    /// The door's frames: shut on the first, open on `doorOpenFrame` (0-based), shut again by the last.
    static let doorOpenFrame = 11
    /// The second copy's shift: one court along, so its left wall is the first's right.
    static let copyShift: CGFloat = 544
    /// The doors' bottom lefts, stage art pixels, on the floor: in the first copy's left opening,
    /// between the copies, and in the second's right.
    static let doorOrigins: [CGPoint] = [CGPoint(x: -16, y: 16), CGPoint(x: 528, y: 16), CGPoint(x: 528 + copyShift, y: 16)]
    /// The belt's columns, a piece every two, from one before the first copy's left wall to one past the second's right.
    static let beltColumns = stride(from: -1, through: 67, by: 2)

    static func layTutorial(_ handles: Handles) {
        // The map again, one court on: its tiles, their possession pixels and its extras.
        for (flat, z) in [(handles.flats[1], CGFloat(-7.8)), (handles.flats[2], CGFloat(-7.6))] {
            let copy = SKSpriteNode(texture: flat.texture)
            copy.anchorPoint = .zero
            copy.size = flat.size
            copy.position = CGPoint(x: flat.position.x + copyShift, y: flat.position.y)
            copy.zPosition = z
            copy.isHidden = flat.isHidden
            handles.parent.addChild(copy)
            handles.copies.append(copy)
        }
        let lit = SKSpriteNode(texture: handles.tilesLit.texture)
        lit.anchorPoint = .zero
        lit.size = handles.tilesLit.size
        lit.position = CGPoint(x: handles.tilesLit.position.x + copyShift, y: handles.tilesLit.position.y)
        lit.zPosition = handles.tilesLit.zPosition
        lit.colorBlendFactor = 1
        handles.parent.addChild(lit)
        handles.tilesLitCopy = lit
        for origin in doorOrigins {
            let door = SKSpriteNode(texture: doorFrames.first)
            door.anchorPoint = .zero
            door.size = doorSize
            door.position = origin
            door.zPosition = inPlayZ
            handles.parent.addChild(door)
            handles.doors.append(door)
        }
        let columns = Array(beltColumns)
        for (index, column) in columns.enumerated() {
            let kind: StageMap.PropKind = index == 0 ? .conveyorL : index == columns.count - 1 ? .conveyorR : .conveyorM
            guard let frames = frames[kind] else { continue }
            let piece = SKSpriteNode(texture: frames.first)
            piece.anchorPoint = .zero
            piece.size = size(kind)
            piece.position = CGPoint(x: CGFloat(column) * 16, y: 16 - piece.size.height)
            piece.zPosition = inPlayZ
            handles.parent.addChild(piece)
            handles.belt.append((piece, frames))
        }
    }

    /// The tiles' possession pixels in the court's colour, the back wall's in their grey; the
    /// displays' at the tiles' at full brightness, so the neutral grey leaves them as drawn.
    static func tint(_ handles: Handles, _ colour: SKColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.getRed(&r, green: &g, blue: &b, alpha: &a)
        handles.tilesLit.color = colour
        handles.tilesLitCopy?.color = colour
        let back = SKColor(rgb: backNeutral)
        handles.backLit.color = back
        var backRed: CGFloat = 0, backGreen: CGFloat = 0, backBlue: CGFloat = 0
        back.getRed(&backRed, green: &backGreen, blue: &backBlue, alpha: &a)
        if let wash, let darkened = handles.backLitDarkened {
            let dark = wash.darkened(backRed, backGreen, backBlue)
            darkened.color = SKColor(red: dark.0, green: dark.1, blue: dark.2, alpha: 1)
        }
        let neutral = CGFloat(0x5D) / 255
        handles.held = abs(r - neutral) > 0.01 || abs(g - neutral) > 0.01 || abs(b - neutral) > 0.01
        let brightest = max(r, g, b, 0.001)
        handles.displayColour = SKColor(red: r / brightest, green: g / brightest, blue: b / brightest, alpha: 1)
        for piece in handles.pieces { colourLights(piece, handles.displayColour) }
    }
}
