import EsperSim
import SpriteKit

/// The Tutorial hub's hoops as drawn (`Hoop_front.aseprite`, `import_stage_art.py hoopfront`): each
/// front-facing hoop's board and the rim's back and front, at its rim in the match, out of sight
/// while it's parked; over the lessons' hoops, their titles in the Tutorial's lettering; behind
/// each row, a belt of the Wreck Center's conveyor pieces, running as a page turn carries the row
/// (the top right, the next left; back, the other way), behind the tiles. Standing, a hoop's board
/// and rim's back are under the ball and its rim's front over it, the bodies over both; through a
/// page turn the hoops are behind the tiles too, going round. A rim bounced on or dunked on drops
/// and pinches in a pixel each side. On each side's beam, the page that side's rim turns to, white
/// on black. A lesson done turns its board green (EDG64 15, 14, 13 to 30, 29, 28), glowing; the
/// rest doesn't glow.
final class TutorialHubArt {
    /// The rim's middle on the 48 by 48 picture, art pixels from its bottom left.
    static let rimOnPicture = CGPoint(x: 24, y: 11)
    /// A title's bottom this far over the rim, art pixels.
    static let titleLift: CGFloat = 36
    /// A belt's top this far over its row's rims, art pixels (HUB BELT Y on the debug strip).
    nonisolated(unsafe) static var beltLift: CGFloat = 30
    /// A belt's ends, art pixels from a room's left: a piece past each wall's inside, its end
    /// under the wall.
    static let beltSpan: ClosedRange<CGFloat> = -16...560
    /// A page label's black round its lettering, art pixels each side.
    static let labelPadding: CGFloat = 2
    static let doneSwaps: [RGB: RGB] = [PixelPalette.colours[15]: PixelPalette.colours[30], PixelPalette.colours[14]: PixelPalette.colours[29],
                                        PixelPalette.colours[13]: PixelPalette.colours[28]]
    /// Under the tiles (`WreckCenterArt`'s at -7.8), over the empty back wall: the belts, then the
    /// boards, the rims' backs, their fronts, the aim's outline and the titles.
    static let beltZ: CGFloat = -7.895
    static let boardZ: CGFloat = -7.89
    static let backRimZ: CGFloat = -7.885
    static let frontRimZ: CGFloat = -7.875
    static let outlineZ: CGFloat = -7.87
    static let titleZ: CGFloat = -7.865
    /// Standing: the board and the rim's back in the ground under the ball, the rim's front and
    /// the outline just under the bodies, in their layer.
    static let standingBoardZ: CGFloat = 4.8
    static let standingBackRimZ: CGFloat = 5.9
    static let standingFrontRimZ: CGFloat = -0.1
    static let standingOutlineZ: CGFloat = -0.09
    /// A rim at its deepest dip, art pixels down; past half of it, pinched in a pixel each side.
    static let dipPixels: CGFloat = 2
    /// Each rim layer's width on its picture, art pixels, for the pinch.
    static let frontRimWidth: CGFloat = 18
    static let backRimWidth: CGFloat = 18
    /// The page labels on the beams, over the tiles and their lit pixels.
    static let labelZ: CGFloat = -7.62

    private struct Drawn {
        let hoop: Int
        let slot: Int
        let room: Int
        let board: SKSpriteNode
        let backRim: SKSpriteNode
        let frontRim: SKSpriteNode
        let title: SKSpriteNode
        /// The rim outlined green while the aim would score through it.
        let outline: SKSpriteNode
        /// The lesson shown on it, and whether its board's green.
        var lesson: TutorialRun.Lesson?
        var done = false
    }
    private struct Belt {
        let room: Int
        let row: Int
        let pieces: [(node: SKSpriteNode, frames: [SKTexture])]
    }
    private struct PageLabel {
        let room: Int
        /// -1 the left beam's (the page before), 1 the right's (the next).
        let way: Int
        let plate: SKSpriteNode
        let text: SKSpriteNode
        var shown: String?
    }
    private var drawn: [Drawn] = []
    private var belts: [Belt] = []
    private var labels: [PageLabel] = []
    private static let board = TutorialHubArt.texture("HoopFrontBoard")
    private static let doneBoard: SKTexture? = {
        guard let image = UIImage(named: "HoopFrontBoard")?.cgImage else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for pixel in 0..<(width * height) where pixels[pixel * 4 + 3] == 255 {
            let at = pixel * 4
            let colour = RGB(pixels[at]) << 16 | RGB(pixels[at + 1]) << 8 | RGB(pixels[at + 2])
            guard let swapped = doneSwaps[colour] else { continue }
            pixels[at] = UInt8(swapped >> 16 & 0xFF); pixels[at + 1] = UInt8(swapped >> 8 & 0xFF); pixels[at + 2] = UInt8(swapped & 0xFF)
        }
        return FieldArt.pixelTexture(pixels, width: width, height: height)
    }()

    private static func texture(_ name: String) -> SKTexture {
        let texture = SKTexture(imageNamed: name)
        texture.filteringMode = .nearest
        return texture
    }
    /// Each line of lettering drawn once.
    private static var labelTextures: [String: SKTexture] = [:]
    static func labelTexture(_ text: String) -> SKTexture? {
        if let texture = labelTextures[text] { return texture }
        let texture = TutorialText.label(text)
        labelTextures[text] = texture
        return texture
    }

    /// Every hub hoop's art, its rows' belts and each room's page labels, into `ground`; the rims'
    /// fronts and the outlines into `bodies`, the bodies' layer.
    init(hoops: [Hoop], ground: SKNode, bodies: SKNode) {
        func sprite(_ texture: SKTexture?, z: CGFloat, anchor: CGPoint, into parent: SKNode = ground) -> SKSpriteNode {
            let node = SKSpriteNode(texture: texture)
            node.size = texture?.size() ?? .zero
            node.anchorPoint = anchor
            node.zPosition = z
            node.isHidden = true
            parent.addChild(node)
            return node
        }
        let onRim = CGPoint(x: TutorialHubArt.rimOnPicture.x / 48, y: TutorialHubArt.rimOnPicture.y / 48)
        for (index, hoop) in hoops.enumerated() where hoop.frontFacing {
            guard let slot = TutorialRules.hubSlot(of: index) else { continue }
            let outline = sprite(TutorialHubArt.outline ?? TutorialHubArt.board, z: TutorialHubArt.standingOutlineZ,
                                 anchor: CGPoint(x: (TutorialHubArt.rimOnPicture.x + 1) / 50, y: (TutorialHubArt.rimOnPicture.y + 1) / 50), into: bodies)
            drawn.append(Drawn(hoop: index, slot: slot, room: (index - TutorialRules.hubHoop(slot: 0, room: 0)) / TutorialRules.hubSlotCount,
                               board: sprite(TutorialHubArt.board, z: TutorialHubArt.standingBoardZ, anchor: onRim),
                               backRim: sprite(TutorialHubArt.texture("HoopFrontBackRim"), z: TutorialHubArt.standingBackRimZ, anchor: onRim),
                               frontRim: sprite(TutorialHubArt.texture("HoopFrontFrontRim"), z: TutorialHubArt.standingFrontRimZ, anchor: onRim, into: bodies),
                               title: sprite(nil, z: TutorialHubArt.titleZ, anchor: CGPoint(x: 0.5, y: 0)), outline: outline))
        }
        let span = TutorialHubArt.beltSpan
        let count = Int((span.upperBound - span.lowerBound) / 32)
        for room in 0..<TutorialRules.rooms {
            for row in TutorialRules.hubRowCounts.indices {
                // Carrying right as drawn; carrying left mirrored, its ends swapped.
                let left = row % 2 == 1
                let pieces = (0..<count).compactMap { index -> (node: SKSpriteNode, frames: [SKTexture])? in
                    let end: StageMap.PropKind = index == 0 ? (left ? .conveyorR : .conveyorL) : index == count - 1 ? (left ? .conveyorL : .conveyorR) : .conveyorM
                    guard let frames = WreckCenterArt.frames[end] else { return nil }
                    let node = sprite(frames.first, z: TutorialHubArt.beltZ, anchor: .zero)
                    node.size = WreckCenterArt.size(end)
                    node.xScale = left ? -1 : 1
                    return (node, frames)
                }
                belts.append(Belt(room: room, row: row, pieces: pieces))
            }
            for way in [-1, 1] {
                let plate = sprite(nil, z: TutorialHubArt.labelZ, anchor: CGPoint(x: 0.5, y: 0.5))
                plate.color = .black
                labels.append(PageLabel(room: room, way: way, plate: plate, text: sprite(nil, z: TutorialHubArt.labelZ + 0.01, anchor: CGPoint(x: 0.5, y: 0.5))))
            }
        }
    }

    /// Each where its hoop is, hidden while it's parked, titled with the lesson it loads as the
    /// run shows it and its board green if that's done, its rim given as far as `give` has it (art
    /// pixels down, and pinched); behind the tiles through a page turn; the belts behind the rows
    /// up, running as far as a page turn's carried them; the beams' labels the pages either side.
    func place(_ hoops: [Hoop], run: TutorialRun, completed: Set<TutorialRun.Lesson>, give: (Int) -> (down: CGFloat, pinch: Bool)) {
        var roomUp = Array(repeating: false, count: TutorialRules.rooms)
        let turning = run.pageTurn != nil
        let bodiesZ = drawn.first?.frontRim.parent?.zPosition ?? 0
        for index in drawn.indices where hoops.indices.contains(drawn[index].hoop) {
            let entry = drawn[index]
            let hoop = hoops[entry.hoop]
            let away = hoop.position == HighwayRules.parked
            if !away { roomUp[entry.room] = true }
            let at = SpriteLibrary.point(hoop.position)
            let point = CGPoint(x: at.x.rounded(), y: at.y.rounded())
            let given = give(entry.hoop)
            let dropped = CGPoint(x: point.x, y: point.y - given.down)
            entry.board.position = point
            entry.backRim.position = dropped
            entry.frontRim.position = dropped
            entry.backRim.xScale = given.pinch ? (TutorialHubArt.backRimWidth - 2) / TutorialHubArt.backRimWidth : 1
            entry.frontRim.xScale = given.pinch ? (TutorialHubArt.frontRimWidth - 2) / TutorialHubArt.frontRimWidth : 1
            for node in [entry.board, entry.backRim, entry.frontRim] { node.isHidden = away }
            entry.board.zPosition = turning ? TutorialHubArt.boardZ : TutorialHubArt.standingBoardZ
            entry.backRim.zPosition = turning ? TutorialHubArt.backRimZ : TutorialHubArt.standingBackRimZ
            entry.frontRim.zPosition = turning ? TutorialHubArt.frontRimZ - bodiesZ : TutorialHubArt.standingFrontRimZ
            entry.outline.zPosition = turning ? TutorialHubArt.outlineZ - bodiesZ : TutorialHubArt.standingOutlineZ
            entry.outline.position = dropped
            if away { entry.outline.isHidden = true }
            let lesson = run.hubLesson(slot: entry.slot)
            let done = lesson.map(completed.contains) ?? false
            if lesson != entry.lesson || entry.title.texture == nil && lesson != nil {
                drawn[index].lesson = lesson
                entry.title.texture = lesson.flatMap { TutorialHubArt.labelTexture($0.title) }
                entry.title.size = entry.title.texture?.size() ?? .zero
            }
            if done != entry.done || entry.board.userData == nil {
                drawn[index].done = done
                entry.board.texture = done ? TutorialHubArt.doneBoard ?? TutorialHubArt.board : TutorialHubArt.board
                entry.board.userData = ["done": done]
            }
            entry.title.isHidden = away || entry.title.texture == nil
            entry.title.position = CGPoint(x: point.x, y: point.y + TutorialHubArt.titleLift)
        }
        // The belts' art moves 2 pixels a frame, as the Wreck Center's does.
        let tick = Int((run.hubSlide / 2).rounded(.down))
        for belt in belts {
            let up = roomUp[belt.room]
            let y = CGFloat(TutorialRules.hubTopRow - Double(belt.row) * TutorialRules.hubRowSpacing) + TutorialHubArt.beltLift - 32
            let shift = CGFloat(belt.room) * WreckCenterArt.copyShift
            let moved = belt.room == 0 ? tick : 0
            for (index, piece) in belt.pieces.enumerated() {
                piece.node.isHidden = !up
                guard up else { continue }
                let x = TutorialHubArt.beltSpan.lowerBound + CGFloat(index) * 32 + shift
                piece.node.position = CGPoint(x: piece.node.xScale < 0 ? x + 32 : x, y: y)
                let count = piece.frames.count
                if count > 0 { piece.node.texture = piece.frames[(moved % count + count) % count] }
            }
        }
        for index in labels.indices {
            let label = labels[index]
            let up = roomUp[label.room]
            label.plate.isHidden = !up
            label.text.isHidden = !up
            let beam = label.way < 0 ? 0 : 1
            guard up, TutorialRules.blockColumns.indices.contains(beam) else { continue }
            let columns = TutorialRules.blockColumns[beam]
            let title = label.way < 0 ? run.previousPageTitle : run.nextPageTitle
            if title != label.shown {
                labels[index].shown = title
                label.text.texture = TutorialHubArt.labelTexture(title)
                label.text.size = label.text.texture?.size() ?? .zero
                label.plate.size = CGSize(width: label.text.size.width + 2 * TutorialHubArt.labelPadding, height: label.text.size.height + 2 * TutorialHubArt.labelPadding)
            }
            let rows = TutorialRules.blockRows
            let middle = CGPoint(x: (CGFloat(columns.lowerBound + columns.upperBound + 1) * 8 + CGFloat(label.room) * WreckCenterArt.copyShift).rounded(),
                                 y: (CGFloat(rows.lowerBound + rows.upperBound + 1) * 8).rounded())
            // Whole pixels at the lettering's edges: an odd size's middle on a half.
            func centred(_ size: CGSize) -> CGPoint {
                CGPoint(x: middle.x + (Int(size.width) % 2 == 1 ? 0.5 : 0), y: middle.y + (Int(size.height) % 2 == 1 ? 0.5 : 0))
            }
            label.plate.position = centred(label.plate.size)
            label.text.position = centred(label.text.size)
        }
    }

    /// Out of the bodies' layer, which outlives the stage's art.
    func removeFromBodies() {
        for entry in drawn {
            entry.frontRim.removeFromParent()
            entry.outline.removeFromParent()
        }
    }

    /// Whether the ball at `point` is passing through a standing hoop's rim, to go under its front.
    func ringsBall(at point: CGPoint) -> Bool {
        drawn.contains { entry in
            !entry.frontRim.isHidden && entry.frontRim.zPosition == TutorialHubArt.standingFrontRimZ
                && abs(point.x - entry.frontRim.position.x) <= 24 && abs(point.y - entry.frontRim.position.y) <= 24
        }
    }

    /// The aim's hoop outlined, the rest not.
    func highlight(_ hoop: Int?) {
        for entry in drawn { entry.outline.isHidden = entry.hoop != hoop || entry.frontRim.isHidden }
    }

    /// Both rim layers' pixels outlined a pixel out, straight beside them, in the made shot's green
    /// (`GameScene.madeShotOutlineColour`), on a canvas a pixel bigger all round.
    static let outline: SKTexture? = {
        func pixels(_ name: String) -> [UInt8]? {
            guard let image = UIImage(named: name)?.cgImage, image.width == 48, image.height == 48 else { return nil }
            var pixels = [UInt8](repeating: 0, count: 48 * 48 * 4)
            guard let context = CGContext(data: &pixels, width: 48, height: 48, bitsPerComponent: 8, bytesPerRow: 48 * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 48, height: 48))
            return pixels
        }
        guard let back = pixels("HoopFrontBackRim"), let front = pixels("HoopFrontFrontRim") else { return nil }
        func solid(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < 48, y < 48 else { return false }
            return back[(y * 48 + x) * 4 + 3] != 0 || front[(y * 48 + x) * 4 + 3] != 0
        }
        var out = [UInt8](repeating: 0, count: 50 * 50 * 4)
        let rgb = GameScene.madeShotOutlineColour
        for row in 0..<50 {
            for column in 0..<50 {
                let x = column - 1, y = row - 1
                guard !solid(x, y), solid(x - 1, y) || solid(x + 1, y) || solid(x, y - 1) || solid(x, y + 1) else { continue }
                let at = (row * 50 + column) * 4
                out[at] = UInt8(rgb >> 16 & 0xFF); out[at + 1] = UInt8(rgb >> 8 & 0xFF); out[at + 2] = UInt8(rgb & 0xFF); out[at + 3] = 255
            }
        }
        return FieldArt.pixelTexture(out, width: 50, height: 50)
    }()

    /// The rims, both layers, where they're up: their nets hang behind them.
    var rims: [SKSpriteNode] { drawn.flatMap { [$0.backRim, $0.frontRim] } }

    /// What mustn't glow: the boards of lessons not done, the rims, the titles, the belts and the
    /// page labels, where they're up.
    var flats: [SKSpriteNode] {
        var nodes: [SKSpriteNode] = []
        for entry in drawn {
            if !entry.done { nodes.append(entry.board) }
            nodes += [entry.backRim, entry.frontRim, entry.title]
        }
        for belt in belts { nodes += belt.pieces.map(\.node) }
        for label in labels { nodes += [label.plate, label.text] }
        return nodes.filter { !$0.isHidden && $0.texture != nil }
    }
}
