// A preview tool: not on the TV, which has no steppers and no computer to save to.
#if !os(tvOS)
import SwiftUI
import SpriteKit
import EsperSim

/// The player gallery, an Xcode preview: every player sheet assembled as the game draws a body
/// (its look's colours, the neck filled, the line round it, the hooded head where the frame's
/// head is, the strings hanging off it, the cubes off its head and its boots and sleeves, and
/// the glow as the customize screen draws it), playing at a chosen rate or stepped a frame at a
/// time, and saved out as PNG sheets, or a folder of a sheet's frames, on #FF00FF, #00FF00 or
/// nothing, at any scale. A tool for looking at the art, not a part of the game.
#Preview("Player sheets") {
    PlayerGallery()
}

/// Where the saved sheets go: `_Graphic Assets/Pixel Art/Assembled/` in the project, found from
/// this file's own path, so the preview writes beside the art.
enum PlayerGalleryOutput {
    static let folder: URL = {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("_Graphic Assets/Pixel Art/Assembled", isDirectory: true)
    }()
}

/// What a sheet's drawn and saved on: magenta, green, or nothing.
enum GalleryBackground: String, CaseIterable {
    case magenta = "MAGENTA", green = "GREEN", none = "NONE"
    var rgb: RGB? {
        switch self {
        case .magenta: RGB(0xFF00FF)
        case .green: RGB(0x00FF00)
        case .none: nil
        }
    }
    var color: Color { rgb.map { Color(rgb: $0) } ?? .clear }
    /// A canvas of `size` filled with it, or left clear.
    func render(_ size: CGSize, draw: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = rgb != nil
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if let rgb {
                UIColor(rgb: rgb).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            draw(context)
        }
    }
}

/// One frame of a sheet as the game assembles it, on a canvas `pad` art pixels bigger each side
/// than the sheet's cell, at `pixel` points an art pixel. `motion` carries the strings and cubes
/// between frames; `time` drives them and the strings' wave. `armOverHood`: the arms drawn
/// again over the hood, as `GameScene.armPartsOverHood` has them in play.
struct AssembledFrame: View {
    let portrait: SpriteLibrary.Portrait
    let look: Look
    let frame: AnimationFrame
    let pixel: CGFloat
    let pad: CGFloat
    let mirrored: Bool
    let strings: Bool
    let cubes: Bool
    let glow: Bool
    let armOverHood: Bool
    /// The hooded head moved off its place, art pixels the way it faces and up (HEAD X, HEAD Y).
    var headNudge: CGPoint = .zero
    /// The ball drawn where the game draws it in the hand.
    var ball = false
    /// Arms drawn apart in play, Z Tea's beam's and blast's, laid on as play lays them.
    var armsBehind: [FigureLayer] = []
    var armsOver: [FigureLayer] = []
    /// The hooded head tipped back (anticlockwise, facing right) and moved, art pixels the way it
    /// faces and up, as play does firing Z Tea up.
    var headTip: CGFloat = 0
    var headShift: CGPoint = .zero
    /// What play draws round the figure on this sheet: the shield on its arc. Added over
    /// everything, as play adds it, and glowing.
    var props: [GalleryProp] = []
    let motion: CustomizeFigureMotion
    let time: Double

    /// The sheet's cell, art pixels high and across.
    var canvas: CGFloat { CGFloat(frame.animation.pixelSize) }
    var canvasWidth: CGFloat { CGFloat(frame.animation.pixelWidth) }
    /// The whole picture, in points.
    var pictureSize: CGSize { CGSize(width: (canvasWidth + 2 * pad) * pixel, height: (canvas + 2 * pad) * pixel) }

    var body: some View {
        Canvas { context, size in
            // The sheet's turn, clockwise, less any tip back.
            let turn = GameScene.hoodTurn(frame) - headTip
            motion.advance(to: time, portrait: portrait, look: look, headNudge: headNudge, headScale: 1, canvas: canvas, style: HoodStrings.hanging, turn: turn)
            var context = context
            if mirrored {
                context.translateBy(x: size.width, y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            /// An art point, y up from the figure's bottom left, on the canvas.
            func spot(_ point: CGPoint) -> CGPoint {
                CGPoint(x: (pad + point.x) * pixel, y: (pad + canvas - point.y) * pixel)
            }
            let figureRect = CGRect(x: pad * pixel, y: pad * pixel, width: canvasWidth * pixel, height: canvas * pixel)
            let place = CustomizeFigure.hoodPlace(portrait, nudge: headNudge, scale: 1)
            let hoodRect = CGRect(x: (pad + place.origin.x + headShift.x) * pixel, y: (pad + place.origin.y - headShift.y) * pixel, width: 48 * pixel, height: 48 * pixel)
            /// The hood drawn turned about the head's middle, where the sheet turns it.
            func drawHood(_ image: CGImage, in context: GraphicsContext) {
                guard turn != 0, let head = portrait.centres[.head].map({ CGPoint(x: $0.x + headNudge.x + headShift.x, y: $0.y - headNudge.y - headShift.y) }) else {
                    return context.draw(Image(decorative: image, scale: 1).interpolation(.none), in: hoodRect)
                }
                let middle = CGPoint(x: (pad + head.x) * pixel, y: (pad + head.y) * pixel)
                context.drawLayer { layer in
                    layer.translateBy(x: middle.x, y: middle.y)
                    layer.rotate(by: Angle(radians: turn))
                    layer.translateBy(x: -middle.x, y: -middle.y)
                    layer.draw(Image(decorative: image, scale: 1).interpolation(.none), in: hoodRect)
                }
            }
            // Strings go under the arms on some sheets' frames, as in play.
            let stringsShown = strings && !GameScene.stringsUnderArms(frame)
            let plain = Color(rgb: look.energyTone(luminance: SpriteLibrary.hoodLevel))
            let accent = Color(rgb: look.energyTone(luminance: GameScene.stringAccentLuminance * SpriteLibrary.hoodLevel))
            func drawStrings(in context: GraphicsContext) {
                guard stringsShown else { return }
                for string in motion.strings {
                    let at = spot(string.point)
                    context.fill(Path(CGRect(x: at.x - pixel / 2, y: at.y - pixel / 2, width: pixel, height: pixel)),
                                 with: .color(string.accent ? accent : plain))
                }
            }
            if cubes { for cube in motion.cubes where cube.behind { CustomizeFigure.drawCube(cube, in: context, at: spot(cube.position), pixel: pixel) } }
            func drawLine(_ line: CGImage, in context: GraphicsContext, turned: Bool) {
                guard look.outlineWidth > 0 else { return }
                context.drawLayer { layer in
                    layer.addFilter(.colorMultiply(Color(rgb: look.outline)))
                    if turned { drawHood(line, in: layer) } else { layer.draw(Image(decorative: line, scale: 1).interpolation(.none), in: figureRect) }
                }
            }
            // Turned, the hood carries its own line, under the body so only what's outside it shows,
            // and the body's line is drawn without the hood's place; else one line runs round both.
            let hoodTurned = (turn != 0 || headShift != .zero) && portrait.bareLine != nil && portrait.hoodLine != nil
            // The ball where the game has it in the hand, behind the body on the frames that tuck it there;
            // on the art's own pixels where the round ball fits its white, painted where the sheet reshapes it.
            let sheetBall = ball ? SpriteLibrary.fittedBall(frame, source: GalleryDrawing.source(frame)) : nil
            let ballCentre = sheetBall.map { SpriteLibrary.sheetBallCentre($0, in: frame) }
                ?? BallLandmarks.table["\(frame.animation.rawValue)_\(frame.frame)"].map { CGPoint(x: $0.x, y: $0.y) }
            let ballAt = ball ? ballCentre.map { spot(CGPoint(x: canvasWidth / 2 + $0.x, y: frame.animation.feetFromBottom + $0.y)) } : nil
            func drawBall() {
                guard let at = ballAt, let art = GalleryDrawing.ballImage(spin: 0) else { return }
                let image = sheetBall.flatMap { $0.roundAt == nil ? SpriteLibrary.paintBall($0, art: art) : GalleryDrawing.ballImage(spin: SpriteLibrary.roundBallSpin(frame, source: GalleryDrawing.source) ?? 0) } ?? art
                let width = CGFloat(image.width) * pixel, height = CGFloat(image.height) * pixel
                context.draw(Image(decorative: image, scale: 1).interpolation(.none), in: CGRect(x: at.x - width / 2, y: at.y - height / 2, width: width, height: height))
                // What the sheet draws in front of the round ball, and its line, again over it.
                guard let sheetBall, sheetBall.roundAt != nil else { return }
                if let over = SpriteLibrary.picked(portrait.image, pixels: sheetBall.covering) {
                    context.draw(Image(decorative: over, scale: 1).interpolation(.none), in: figureRect)
                }
                if let line = hoodTurned ? portrait.bareLine : portrait.line, let over = SpriteLibrary.picked(line, pixels: sheetBall.covering) {
                    drawLine(over, in: context, turned: false)
                }
            }
            /// An arm of its own, its line under it, moved and turned about its pivot.
            func drawArms(_ layer: FigureLayer) {
                var turned = context
                turned.translateBy(x: layer.offset.x * pixel, y: -layer.offset.y * pixel)
                let pivot = spot(layer.pivot)
                turned.translateBy(x: pivot.x, y: pivot.y)
                turned.rotate(by: .radians(-layer.turn))
                turned.translateBy(x: -pivot.x, y: -pivot.y)
                if let line = layer.line { drawLine(line, in: turned, turned: false) }
                turned.draw(Image(decorative: layer.image, scale: 1).interpolation(.none), in: figureRect)
            }
            for layer in armsBehind { drawArms(layer) }
            let ballBehind = GameScene.ballBehindBody(frame)
            if ballBehind { drawBall() }
            if hoodTurned, let hoodLine = portrait.hoodLine { drawLine(hoodLine, in: context, turned: true) }
            // The figure, its line in its look's colour, and its hooded head.
            context.draw(Image(decorative: portrait.image, scale: 1).interpolation(.none), in: figureRect)
            if let line = hoodTurned ? portrait.bareLine : portrait.line { drawLine(line, in: context, turned: false) }
            if let hood = portrait.hood { drawHood(hood, in: context) }
            drawStrings(in: context)
            if !ballBehind { drawBall() }
            // The front arm over the hood and the strings, as in play, with its own line.
            if armOverHood, let arm = portrait.frontArm {
                if let armLine = portrait.frontArmLine { drawLine(armLine, in: context, turned: false) }
                context.draw(Image(decorative: arm, scale: 1).interpolation(.none), in: figureRect)
            }
            for layer in armsOver { drawArms(layer) }
            /// A prop at its place, turned, added on.
            func drawProps(in context: GraphicsContext) {
                for prop in props {
                    var placed = context
                    placed.blendMode = .plusLighter
                    let at = spot(prop.centre)
                    placed.translateBy(x: at.x, y: at.y)
                    placed.rotate(by: .radians(-prop.turn))
                    let width = CGFloat(prop.image.width) * prop.scale * pixel, height = CGFloat(prop.image.height) * prop.scale * pixel
                    placed.draw(Image(decorative: prop.image, scale: 1).interpolation(.none), in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
                }
            }
            drawProps(in: context)
            if cubes { for cube in motion.cubes where !cube.behind { CustomizeFigure.drawCube(cube, in: context, at: spot(cube.position), pixel: pixel) } }
            // The glow: what's energy again, blurred and added, as the customize screen draws it.
            guard glow else { return }
            var glowing = context
            glowing.blendMode = .plusLighter
            glowing.opacity = CustomizeArt.glowStrength
            glowing.drawLayer { layer in
                layer.addFilter(.blur(radius: pixel * CustomizeArt.glowPixels))
                layer.draw(Image(decorative: portrait.glowing, scale: 1).interpolation(.none), in: figureRect)
                if let hood = portrait.hoodGlowing { drawHood(hood, in: layer) }
                drawStrings(in: layer)
                if cubes { for cube in motion.cubes { CustomizeFigure.drawCube(cube, in: layer, at: spot(cube.position), pixel: pixel) } }
                drawProps(in: layer)
            }
        }
        .frame(width: pictureSize.width, height: pictureSize.height)
    }
}

/// A picture play draws round the figure, its middle in art pixels from the canvas's bottom
/// left, turned anticlockwise, at a share of its own size.
struct GalleryProp {
    let image: CGImage
    let centre: CGPoint
    let turn: CGFloat
    let scale: CGFloat
}

/// How a sheet is drawn and saved: the look's dressing aside, everything the gallery's controls set.
struct GalleryDrawing {
    var pad: CGFloat = 8
    /// The pad round a sheet: room enough for what's drawn round the figure (the shield's arc),
    /// the figure kept its size in a saved sheet.
    func pad(for animation: EsperSim.Animation) -> CGFloat { pad + (animation == .shield ? GallerySheets.shieldRoom : 0) }
    var fps = 12.0
    var mirrored = false
    var strings = true
    var cubes = true
    var glow = true
    var ball = true
    var background = GalleryBackground.magenta
    /// The blast fired up off the ground: its arms 45 degrees up and the head tipped back, as play has it.
    var blastUp = false
    func headTip(_ frame: AnimationFrame) -> CGFloat { blastUp && frame.animation == .blast ? GameScene.blastUpTip : 0 }
    func headShift(_ frame: AnimationFrame) -> CGPoint { blastUp && frame.animation == .blast ? GameScene.aimedHeadShift(tip: GameScene.blastUpTip, blast: true) : .zero }
    /// The hooded heads moved, by sheet and frame: the game's table to start, changed here.
    var headNudges: [EsperSim.Animation: [Int: CGPoint]] = GameScene.headNudges
    func headNudge(_ frame: AnimationFrame) -> CGPoint { headNudges[frame.animation]?[frame.frame] ?? .zero }
    /// One of the ball's frames.
    static func ballImage(spin: Int) -> CGImage? {
        UIImage(named: "Basketball")?.cgImage?.cropping(to: CGRect(x: spin * 8, y: 0, width: 8, height: 8))
    }
    /// A player frame as the sheet has it, before any recolouring.
    static func source(_ frame: AnimationFrame) -> CGImage {
        SKTextureAtlas(named: "Sprites").textureNamed("\(frame.animation.rawValue)_\(frame.frame)").cgImage()
    }
    /// The frames whose front arm goes over the hood, by sheet: the game's table to start,
    /// changed frame by frame here.
    var armOverHood: [EsperSim.Animation: Set<Int>] = GameScene.frontArmOverHood.mapValues { Set($0) }
        .merging(GameScene.bothArmsOverHood.mapValues { Set($0) }) { $0.union($1) }

    func armOverHood(_ frame: AnimationFrame) -> Bool { armOverHood[frame.animation]?.contains(frame.frame) ?? false }
}

/// The sheets' frames in a look, made as the customize screen's figure is, and the sheets
/// saved out.
@MainActor
final class PlayerGallerySheets: ObservableObject {
    private let sprites = SpriteLibrary()
    @Published var pick = PlayerCustomization.saved(0)
    @Published var status = ""

    /// The gallery's OUTLINE: off, the look drawn with no line at all, outside or between parts,
    /// so every pixel keeps its recoloured colour.
    @Published var outlined = true
    var look: Look {
        guard !outlined else { return pick.look }
        var unlined = pick.look
        unlined.outlineWidth = 0
        unlined.strokedGroups = []
        return unlined
    }

    /// A frame's portrait, its line and neck made for the hood moved by `headNudge`, as play bakes it.
    func portrait(_ frame: AnimationFrame, headNudge: CGPoint) -> SpriteLibrary.Portrait? {
        sprites.setCustomizeLook(look, for: 0)
        return sprites.portrait(frame.animation.rawValue, frame: frame.frame, player: SpriteLibrary.customizePlayer(0),
                                headDrawnFor: SpriteLibrary.hoodDrawnFor, headNudge: headNudge, headScale: 1, holdsBall: frame.animation.holdsBall)
    }

    /// What play draws round the figure on a sheet's frame: the shield on its arc for the shield's
    /// backflip, the frame's share of the flip, at its place round the body's middle, turned to its face.
    func props(_ animation: EsperSim.Animation, _ index: Int) -> [GalleryProp] {
        guard animation == .shield else { return [] }
        sprites.setCustomizeLook(look, for: 0)
        let count = GallerySheets.frameCount(animation)
        let age = Int((Double(index) / Double(max(count - 1, 1)) * Double(ShieldRules.flipFrames - 1)).rounded())
        guard let image = sprites.effectImage(EnergyEffect.shield.name, ShieldRules.sheetFrame(atAge: age), player: SpriteLibrary.customizePlayer(0)) else { return [] }
        let unit = SpriteLibrary.pixelsPerUnit
        let middle = CGPoint(x: animation.pixelWidth / 2, y: animation.feetFromBottom + FighterSpec.meleeMario.bodyHeight / 2 * unit)
        let place = Shield.place(atAge: age)
        let centre = CGPoint(x: middle.x + cos(place) * ShieldRules.arcRadius * unit, y: middle.y + sin(place) * ShieldRules.arcRadius * unit)
        return [GalleryProp(image: image, centre: centre, turn: Shield.faceAngle(atAge: age), scale: GameScene.shieldScale)]
    }

    /// Z Tea's arms for a frame of the beam or the blast as play lays them on the body: the blast's
    /// level in the air, 45 degrees up off the ground.
    func arms(_ frame: AnimationFrame, blastUp: Bool) -> (behind: [FigureLayer], over: [FigureLayer]) {
        sprites.setCustomizeLook(look, for: 0)
        return GameScene.zTeaArms(frame, sprites: sprites, player: SpriteLibrary.customizePlayer(0), blastTurn: blastUp ? .pi / 4 : 0,
                                  image: { _, make in make()?.cgImage() })
    }

    /// The sheets outside play's, on the chair as the Greateraid pick draws them: the drinker
    /// choosing and the drinker drinking, each over `player_bench`.
    enum Seated: String, CaseIterable {
        case drinkChoice = "player_drinkchoice", drink = "player_drink"
        var name: String { self == .drinkChoice ? "Drink Choice + Chair" : "Drink + Chair" }
        /// Its frames, as many as the atlas has.
        var frameCount: Int {
            let names = Set(SKTextureAtlas(named: "Sprites").textureNames)
            return max((0..<64).prefix { names.contains("\(rawValue)_\($0)") || names.contains("\(rawValue)_\($0).png") }.count, 1)
        }
    }

    /// A seated frame in the look, as the pick draws it: the chair, and the figure on it (the
    /// drink's head tipped back and its bottle over the hood, frame by frame).
    func seated(_ sheet: Seated, frame: Int) -> (chair: CGImage, figure: CGImage) {
        sprites.setCustomizeLook(look, for: 0)
        let slot = SpriteLibrary.customizePlayer(0)
        let chair = sprites.standalone("player_bench", frame: 0, player: slot).cgImage()
        let figure = sheet == .drink
            ? sprites.standalone(sheet.rawValue, frame: frame, player: slot, headTilt: PickScreen.drinkHeadTilts[min(frame, PickScreen.drinkHeadTilts.count - 1)],
                                 overHood: PickScreen.drinkOverHood)
            : sprites.standalone(sheet.rawValue, frame: frame, player: slot)
        return (chair, figure.cgImage())
    }

    /// The gallery's OLD LINE: the line drawn as before build 12 (Semibold, corners too), or as now.
    func useOldLine(_ old: Bool) {
        sprites.setCustomizeLineStyle(old ? .semibold : nil)
        objectWillChange.send()
    }

    /// A seated sheet's frames at `scale`, each on its own canvas, clear, `pad` art pixels round each.
    func seatedFrames(_ sheet: Seated, scale: CGFloat, pad: CGFloat) -> [UIImage] {
        let frames = (0..<sheet.frameCount).map { seated(sheet, frame: $0) }
        let art = GallerySeatedFrame.canvas(frames.first)
        let cell = CGSize(width: (art.width + 2 * pad) * scale, height: (art.height + 2 * pad) * scale)
        return frames.map { frame in
            GalleryBackground.none.render(cell) { context in
                context.cgContext.interpolationQuality = .none
                for (image, origin) in GallerySeatedFrame.layers(frame, canvas: art) {
                    UIImage(cgImage: image).draw(in: CGRect(x: (pad + origin.x) * scale, y: (pad + origin.y) * scale,
                                                            width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale))
                }
            }
        }
    }

    func saveSeated(_ sheet: Seated, scale: CGFloat, strip: Strip, pad: CGFloat, background: GalleryBackground) {
        write("\(sheet.rawValue)_chair", frames: seatedFrames(sheet, scale: scale, pad: pad), strip: strip, background: background,
              saved: "Saved \(sheet.name) at ×\(Int(scale))")
    }

    func exportSeatedFrames(_ sheet: Seated, scale: CGFloat, pad: CGFloat, background: GalleryBackground) {
        writeFrames("\(sheet.rawValue)_chair", frames: seatedFrames(sheet, scale: scale, pad: pad), background: background, scale: scale)
    }

    /// Frames laid one after another, down or across, on the background.
    static func strip(_ frames: [UIImage], strip: Strip, background: GalleryBackground) -> UIImage? {
        guard let cell = frames.first?.size else { return nil }
        let count = CGFloat(frames.count)
        let size = strip == .across ? CGSize(width: cell.width * count, height: cell.height) : CGSize(width: cell.width, height: cell.height * count)
        return background.render(size) { _ in
            for (index, image) in frames.enumerated() {
                let at = strip == .across ? CGPoint(x: cell.width * CGFloat(index), y: 0) : CGPoint(x: 0, y: cell.height * CGFloat(index))
                image.draw(in: CGRect(origin: at, size: cell))
            }
        }
    }

    /// A sheet's frames saved as one PNG named for it, in the output folder.
    private func write(_ name: String, frames: [UIImage], strip: Strip, background: GalleryBackground, saved: String) {
        let folder = PlayerGalleryOutput.folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard let data = PlayerGallerySheets.strip(frames, strip: strip, background: background)?.pngData() else { return }
            try data.write(to: folder.appendingPathComponent("\(name).png"))
            status = "\(saved) to \(folder.path)"
        } catch {
            status = "Couldn't save: \(error.localizedDescription)"
        }
    }

    /// A sheet's frames saved one PNG each, `name_01.png` on, in a folder named for the sheet in
    /// the output folder, emptied first.
    private func writeFrames(_ name: String, frames: [UIImage], background: GalleryBackground, scale: CGFloat) {
        let folder = PlayerGalleryOutput.folder.appendingPathComponent(name, isDirectory: true)
        do {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for (index, frame) in frames.enumerated() {
                guard let data = background.render(frame.size, draw: { _ in frame.draw(at: .zero) }).pngData() else { continue }
                try data.write(to: folder.appendingPathComponent(String(format: "%@_%02d.png", name, index + 1)))
            }
            status = "Exported \(frames.count) frames at ×\(Int(scale)) to \(folder.path)"
        } catch {
            status = "Couldn't export: \(error.localizedDescription)"
        }
    }

    /// Which way a sheet's frames run.
    enum Strip: String, CaseIterable {
        case down = "DOWN", across = "ACROSS"
    }

    /// Every frame of `animation` at `scale` pixels an art pixel, each clear: the strings and
    /// cubes moved on between frames as the frames play at the drawing's rate.
    func frames(_ animation: EsperSim.Animation, scale: CGFloat, drawing: GalleryDrawing) -> [UIImage]? {
        let motion = CustomizeFigureMotion()
        let pad = drawing.pad(for: animation)
        let count = GallerySheets.frameCount(animation)
        let start = Date().timeIntervalSinceReferenceDate
        var frames: [UIImage] = []
        for index in 0..<count {
            let frame = GallerySheets.frame(animation, index)
            guard let portrait = portrait(frame, headNudge: drawing.headNudge(frame)) else { return nil }
            let arms = arms(frame, blastUp: drawing.blastUp)
            let view = AssembledFrame(portrait: portrait, look: look, frame: frame, pixel: scale, pad: pad, mirrored: drawing.mirrored,
                                      strings: drawing.strings, cubes: drawing.cubes, glow: drawing.glow, armOverHood: drawing.armOverHood(frame),
                                      headNudge: drawing.headNudge(frame), ball: drawing.ball, armsBehind: arms.behind, armsOver: arms.over,
                                      headTip: drawing.headTip(frame), headShift: drawing.headShift(frame),
                                      props: props(animation, index),
                                      motion: motion, time: start + Double(index) / drawing.fps)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.uiImage else { return nil }
            frames.append(image)
        }
        return frames
    }

    /// `animations`' sheets saved as PNGs named for their sheets, in the output folder.
    func save(_ animations: [EsperSim.Animation], scale: CGFloat, strip: Strip, drawing: GalleryDrawing) {
        let folder = PlayerGalleryOutput.folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var saved = 0
            for animation in animations {
                guard let frames = frames(animation, scale: scale, drawing: drawing),
                      let data = PlayerGallerySheets.strip(frames, strip: strip, background: drawing.background)?.pngData() else { continue }
                try data.write(to: folder.appendingPathComponent("\(animation.rawValue).png"))
                saved += 1
            }
            status = "Saved \(saved) sheet\(saved == 1 ? "" : "s") at ×\(Int(scale)) to \(folder.path)"
        } catch {
            status = "Couldn't save: \(error.localizedDescription)"
        }
    }

    /// `animation`'s frames, a PNG each, in a folder named for the sheet in the output folder.
    func exportFrames(_ animation: EsperSim.Animation, scale: CGFloat, drawing: GalleryDrawing) {
        guard let frames = frames(animation, scale: scale, drawing: drawing) else { return status = "Couldn't draw \(GallerySheets.name(animation))" }
        writeFrames(animation.rawValue, frames: frames, background: drawing.background, scale: scale)
    }
}

/// The sheets as the gallery lists them: by name in words, the idles first.
enum GallerySheets {
    static let first: [EsperSim.Animation] = [.idle, .dribbleIdle]
    /// Z Tea's arms' sheets aren't listed: the beam and the blast are drawn with theirs on.
    static let armsAlone: [EsperSim.Animation] = [.beamArms, .blastArms, .webshootBackArm, .webshootFrontArm, .webshootWallArm]
    static let listed: [EsperSim.Animation] = first + EsperSim.Animation.allCases.filter { !first.contains($0) && !armsAlone.contains($0) }
        .sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }

    /// The shield's old sheet stands in for the shield's backflip now: the double jump backward.
    static func frameCount(_ animation: EsperSim.Animation) -> Int {
        animation == .shield ? EsperSim.Animation.doubleJump.frameCount : animation.frameCount
    }
    static func frame(_ animation: EsperSim.Animation, _ index: Int) -> AnimationFrame {
        guard animation == .shield else { return AnimationFrame(animation, index) }
        let count = EsperSim.Animation.doubleJump.frameCount
        return AnimationFrame(.doubleJump, count - 1 - index % count)
    }

    /// Room added round the shield's sheet for the shield on its arc, art pixels each side.
    static let shieldRoom: CGFloat = 20

    /// A sheet's name in words: `player_dbl_jump` as Double Jump.
    static func name(_ animation: EsperSim.Animation) -> String {
        if animation == .shield { return "Shield Backflip" }
        if animation == .blast { return "Blast" }
        let words: [String: String] = ["dbl": "Double", "esperslash": "Esper Slash", "flostate": "FloState"]
        return animation.rawValue.replacingOccurrences(of: "player_", with: "").split(separator: "_")
            .map { words[String($0)] ?? $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

/// A seated frame drawn as the pick lays it: the chair and the figure each anchored at the same
/// feet (`PickScreen.drinkerFeet` up, the middle across), on one canvas that holds both.
struct GallerySeatedFrame: View {
    let frame: (chair: CGImage, figure: CGImage)
    let pixel: CGFloat
    let pad: CGFloat

    /// The canvas both fit on, art pixels.
    static func canvas(_ frame: (chair: CGImage, figure: CGImage)?) -> CGSize {
        guard let frame else { return CGSize(width: 48, height: 48) }
        return CGSize(width: CGFloat(max(frame.chair.width, frame.figure.width)), height: CGFloat(max(frame.chair.height, frame.figure.height)))
    }

    /// Each picture with its top left on the canvas, art pixels from the canvas's top left: the
    /// chair under, the figure over, their feet together.
    static func layers(_ frame: (chair: CGImage, figure: CGImage), canvas: CGSize) -> [(CGImage, CGPoint)] {
        let feet = CGPoint(x: canvas.width / 2, y: canvas.height * (1 - PickScreen.drinkerFeet))
        return [frame.chair, frame.figure].map { image in
            let width = CGFloat(image.width), height = CGFloat(image.height)
            return (image, CGPoint(x: (feet.x - width / 2).rounded(), y: (feet.y - height * (1 - PickScreen.drinkerFeet)).rounded()))
        }
    }

    var body: some View {
        let art = GallerySeatedFrame.canvas(frame)
        Canvas { context, _ in
            for (image, origin) in GallerySeatedFrame.layers(frame, canvas: art) {
                context.draw(Image(decorative: image, scale: 1).interpolation(.none),
                             in: CGRect(x: (pad + origin.x) * pixel, y: (pad + origin.y) * pixel, width: CGFloat(image.width) * pixel, height: CGFloat(image.height) * pixel))
            }
        }
        .frame(width: (art.width + 2 * pad) * pixel, height: (art.height + 2 * pad) * pixel)
    }
}

/// What the gallery's sheet list picks: one of play's sheets, or a seated one on its chair.
enum GalleryEntry: Hashable {
    case sheet(EsperSim.Animation)
    case seated(PlayerGallerySheets.Seated)
}

/// The frame last drawn while playing, for the pause to hold on.
final class Playhead {
    var shown = 0
}

/// The gallery: the sheet picked at the top, the frame playing or stepped under it, then the
/// controls in sections: how it's drawn, this frame's tweaks, the view, and saving.
struct PlayerGallery: View {
    @StateObject private var sheets = PlayerGallerySheets()
    @State private var animation: EsperSim.Animation = .idle
    /// A seated sheet shown in the sheet's place, or none.
    @State private var seated: PlayerGallerySheets.Seated?
    @State private var oldLine = false
    @State private var drawing = GalleryDrawing()
    @State private var pixel = 6.0
    @State private var saveScale = 4.0
    @State private var strip = PlayerGallerySheets.Strip.down
    @State private var paused = false
    @State private var held = 0
    @State private var motion = CustomizeFigureMotion()
    @State private var playhead = Playhead()

    private static let saveScales: [Double] = [1, 2, 3, 4, 6, 8]
    private static let stageHeight: CGFloat = 320
    private static let controlFont = Font.system(size: 12, weight: .semibold, design: .monospaced)

    private var frameCount: Int { seated?.frameCount ?? GallerySheets.frameCount(animation) }
    private var sheetName: String { seated?.name ?? GallerySheets.name(animation) }
    private var shownIndex: Int { paused ? held : playhead.shown }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                sheetPicker
                stage
                transport
                GallerySection("DRAW") { drawControls }
                if seated == nil {
                    GallerySection("FRAME \(shownIndex + 1)") { frameControls }
                }
                GallerySection("VIEW") { viewControls }
                GallerySection("SAVE") { saveControls }
            }
            .font(PlayerGallery.controlFont)
            .padding(16)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: animation) { held = 0 }
        .onChange(of: seated) { held = 0 }
        .onChange(of: oldLine) { sheets.useOldLine(oldLine) }
        .onDisappear { sheets.useOldLine(false) }
    }

    /// The sheet, play's then the seated ones on their chair, in one list; and the energy colour.
    private var sheetPicker: some View {
        HStack {
            Picker("Sheet", selection: Binding<GalleryEntry>(
                get: { seated.map(GalleryEntry.seated) ?? .sheet(animation) },
                set: { entry in
                    switch entry {
                    case .sheet(let sheet): seated = nil; animation = sheet
                    case .seated(let sheet): seated = sheet
                    }
                })) {
                ForEach(GallerySheets.listed, id: \.self) { Text(GallerySheets.name($0)).tag(GalleryEntry.sheet($0)) }
                ForEach(PlayerGallerySheets.Seated.allCases, id: \.self) { Text($0.name).tag(GalleryEntry.seated($0)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Colour", selection: $sheets.pick.energy) {
                ForEach(EnergyColour.wheel, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
            }
        }
        .pickerStyle(.menu)
    }

    /// The frame on its background, centred on a stage of fixed height so the controls under it
    /// stay put; its name and number under it.
    private var stage: some View {
        VStack(spacing: 6) {
            TimelineView(.animation(paused: paused)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let index = paused ? held : Int(time * drawing.fps) % frameCount
                let _ = playhead.shown = index
                picture(index: index, time: time)
                    .background { GalleryBackdrop(background: drawing.background) }
                    .frame(maxWidth: .infinity, minHeight: PlayerGallery.stageHeight)
            }
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            Text("\(sheetName)   \(shownIndex + 1) / \(frameCount)")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func picture(index: Int, time: Double) -> some View {
        if let seated {
            GallerySeatedFrame(frame: sheets.seated(seated, frame: index), pixel: pixel, pad: drawing.pad)
        } else {
            let frame = GallerySheets.frame(animation, index)
            // Room for what's round the figure, the figure shrunk to keep the view's size.
            let pad = drawing.pad(for: animation)
            let shown = pixel * (CGFloat(animation.pixelSize) + 2 * drawing.pad) / (CGFloat(animation.pixelSize) + 2 * pad)
            if let portrait = sheets.portrait(frame, headNudge: drawing.headNudge(frame)) {
                let arms = sheets.arms(frame, blastUp: drawing.blastUp)
                AssembledFrame(portrait: portrait, look: sheets.look, frame: frame, pixel: shown, pad: pad, mirrored: drawing.mirrored,
                               strings: drawing.strings, cubes: drawing.cubes, glow: drawing.glow, armOverHood: drawing.armOverHood(frame),
                               headNudge: drawing.headNudge(frame), ball: drawing.ball, armsBehind: arms.behind, armsOver: arms.over,
                               headTip: drawing.headTip(frame), headShift: drawing.headShift(frame),
                               props: sheets.props(animation, index),
                               motion: motion, time: time)
            }
        }
    }

    /// A frame back, play or pause, a frame on (stepping pauses); and the rate.
    private var transport: some View {
        HStack(spacing: 10) {
            Button { step(-1) } label: { Image(systemName: "backward.frame.fill") }
            Button {
                if !paused { held = playhead.shown }
                paused.toggle()
            } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill").frame(width: 44)
            }
            Button { step(1) } label: { Image(systemName: "forward.frame.fill") }
            Spacer()
            Stepper("FPS \(Int(drawing.fps))", value: $drawing.fps, in: 1...60)
                .fixedSize()
        }
        .buttonStyle(.bordered)
    }

    /// What's drawn: the toggles in an even grid, then the background.
    private var drawControls: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                GalleryToggle("MIRROR", isOn: $drawing.mirrored)
                GalleryToggle("STRINGS", isOn: $drawing.strings)
                GalleryToggle("CUBES", isOn: $drawing.cubes)
                GalleryToggle("GLOW", isOn: $drawing.glow)
                GalleryToggle("BALL", isOn: $drawing.ball)
                GalleryToggle("OLD LINE", isOn: $oldLine)
                GalleryToggle("OUTLINE", isOn: $sheets.outlined)
                if seated == nil && animation == .blast { GalleryToggle("BLAST UP", isOn: $drawing.blastUp) }
            }
            GalleryRow("BACKGROUND") {
                Picker("Background", selection: $drawing.background) {
                    ForEach(GalleryBackground.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    /// The shown frame's own tweaks, and every head moved so far to report.
    private var frameControls: some View {
        let frame = GallerySheets.frame(animation, shownIndex)
        return VStack(spacing: 10) {
            GalleryToggle("ARM OVER HOOD", isOn: Binding(
                get: { drawing.armOverHood(frame) },
                set: { on in
                    var frames = drawing.armOverHood[animation] ?? []
                    if on { frames.insert(frame.frame) } else { frames.remove(frame.frame) }
                    drawing.armOverHood[animation] = frames.isEmpty ? nil : frames
                }))
            GalleryRow("HEAD X") {
                Stepper("\(Int(drawing.headNudge(frame).x))", value: headNudgeBinding(frame, \.x), in: -12...12)
            }
            GalleryRow("HEAD Y") {
                Stepper("\(Int(drawing.headNudge(frame).y))", value: headNudgeBinding(frame, \.y), in: -12...12)
            }
            Text(headNudgeSummary)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var viewControls: some View {
        VStack(spacing: 10) {
            GalleryRow("PAD") { Stepper("\(Int(drawing.pad)) px", value: $drawing.pad, in: 0...32) }
            GalleryRow("ZOOM") { Stepper("×\(Int(pixel))", value: $pixel, in: 1...12) }
        }
    }

    /// The scale and the strip's way, then what to save: this sheet as one PNG, its frames as a
    /// folder of PNGs, or every sheet; and what happened.
    private var saveControls: some View {
        VStack(spacing: 10) {
            GalleryRow("SCALE") {
                Picker("Save scale", selection: $saveScale) {
                    ForEach(PlayerGallery.saveScales, id: \.self) { Text("×\(Int($0))").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            GalleryRow("STRIP") {
                Picker("Strip", selection: $strip) {
                    ForEach(PlayerGallerySheets.Strip.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 8) {
                Button { saveSheet() } label: { Text("SAVE SHEET").frame(maxWidth: .infinity) }
                Button { exportFrames() } label: { Text("EXPORT FRAMES").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            Button { sheets.save(GallerySheets.listed, scale: saveScale, strip: strip, drawing: drawing) } label: {
                Text("SAVE ALL \(GallerySheets.listed.count) SHEETS").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if !sheets.status.isEmpty {
                Text(sheets.status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func saveSheet() {
        if let seated {
            sheets.saveSeated(seated, scale: saveScale, strip: strip, pad: drawing.pad, background: drawing.background)
        } else {
            sheets.save([animation], scale: saveScale, strip: strip, drawing: drawing)
        }
    }

    private func exportFrames() {
        if let seated {
            sheets.exportSeatedFrames(seated, scale: saveScale, pad: drawing.pad, background: drawing.background)
        } else {
            sheets.exportFrames(animation, scale: saveScale, drawing: drawing)
        }
    }

    private func headNudgeBinding(_ frame: AnimationFrame, _ axis: WritableKeyPath<CGPoint, CGFloat>) -> Binding<CGFloat> {
        Binding(get: { drawing.headNudge(frame)[keyPath: axis] }, set: { value in
            var point = drawing.headNudge(frame)
            point[keyPath: axis] = value
            var frames = drawing.headNudges[frame.animation] ?? [:]
            frames[frame.frame] = point == .zero ? nil : point
            drawing.headNudges[frame.animation] = frames.isEmpty ? nil : frames
        })
    }

    /// Every head moved, sheet by sheet, frames from 1, x the way it faces and y up.
    private var headNudgeSummary: String {
        let lines = drawing.headNudges.sorted { $0.key.rawValue < $1.key.rawValue }.map { sheet in
            "\(GallerySheets.name(sheet.key)): " + sheet.value.sorted { $0.key < $1.key }
                .map { "\($0.key + 1) (\(Int($0.value.x)), \(Int($0.value.y)))" }.joined(separator: ", ")
        }
        return lines.isEmpty ? "No heads moved." : "Heads moved, x, y (frames from 1):\n" + lines.joined(separator: "\n")
    }

    private func step(_ by: Int) {
        if !paused { held = playhead.shown; paused = true }
        held = (held + by + frameCount) % frameCount
    }
}

/// A titled group of the gallery's controls on a quiet panel.
struct GallerySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.secondary)
            content
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

/// A control with its label in a fixed column on the left.
struct GalleryRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
            content
        }
    }
}

/// An on/off button filling its column.
struct GalleryToggle: View {
    let label: String
    @Binding var isOn: Bool
    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }
    var body: some View {
        Toggle(isOn: $isOn) { Text(label).frame(maxWidth: .infinity) }
            .toggleStyle(.button)
    }
}

/// What's behind the picture: the background's colour, or a checkerboard for none.
struct GalleryBackdrop: View {
    let background: GalleryBackground
    var body: some View {
        if background == .none {
            Canvas { context, size in
                let square: CGFloat = 8
                for row in 0..<Int((size.height / square).rounded(.up)) {
                    for column in 0..<Int((size.width / square).rounded(.up)) where (row + column) % 2 == 0 {
                        context.fill(Path(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square)),
                                     with: .color(.gray.opacity(0.35)))
                    }
                }
            }
            .background(Color.white)
        } else {
            background.color
        }
    }
}
#endif
