// A preview tool: not on the TV, which has no steppers and no computer to save to.
#if !os(tvOS)
import SwiftUI
import SpriteKit
import EsperSim

/// The player gallery, an Xcode preview: every player sheet assembled as the game draws a body
/// (its look's colours, the neck filled, the line round it, the hooded head where the frame's
/// head is, the strings hanging off it, the cubes off its head and its boots and sleeves, and
/// the glow as the customize screen draws it), playing at a chosen rate or stepped a frame at a
/// time, and saved out as PNG sheets on #FF00FF at any scale. A tool for looking at the art,
/// not a part of the game.
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
    static let background = RGB(0xFF00FF)
}

/// One frame of a sheet as the game assembles it, on a canvas `pad` art pixels bigger each side
/// than the sheet's cell, at `pixel` points an art pixel. `motion` carries the strings and cubes
/// between frames; `time` drives them and the strings' wave. `armOverHood`: the front arm drawn
/// again over the hood, as `GameScene.frontArmOverHood` has it in play.
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
    let motion: CustomizeFigureMotion
    let time: Double

    /// The sheet's cell, art pixels high and across.
    var canvas: CGFloat { CGFloat(frame.animation.pixelSize) }
    var canvasWidth: CGFloat { CGFloat(frame.animation.pixelWidth) }
    /// The whole picture, in points.
    var pictureSize: CGSize { CGSize(width: (canvasWidth + 2 * pad) * pixel, height: (canvas + 2 * pad) * pixel) }

    var body: some View {
        Canvas { context, size in
            let turn = GameScene.hoodTurn(frame)
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
            let hoodRect = CGRect(x: (pad + place.origin.x) * pixel, y: (pad + place.origin.y) * pixel, width: 48 * pixel, height: 48 * pixel)
            /// The hood drawn turned about the head's middle, where the sheet turns it.
            func drawHood(_ image: CGImage, in context: GraphicsContext) {
                guard turn != 0, let head = portrait.centres[.head].map({ CGPoint(x: $0.x + headNudge.x, y: $0.y - headNudge.y) }) else {
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
                context.drawLayer { layer in
                    layer.addFilter(.colorMultiply(Color(rgb: look.outline)))
                    if turned { drawHood(line, in: layer) } else { layer.draw(Image(decorative: line, scale: 1).interpolation(.none), in: figureRect) }
                }
            }
            // Turned, the hood carries its own line, under the body so only what's outside it shows,
            // and the body's line is drawn without the hood's place; else one line runs round both.
            let hoodTurned = (turn != 0 || headNudge != .zero) && portrait.bareLine != nil && portrait.hoodLine != nil
            // The ball where the game has it in the hand, behind the body on the frames that tuck it there.
            let ballAt = ball ? BallLandmarks.table["\(frame.animation.rawValue)_\(frame.frame)"].map {
                spot(CGPoint(x: canvasWidth / 2 + $0.x, y: frame.animation.feetFromBottom + $0.y))
            } : nil
            func drawBall() {
                guard let at = ballAt, let image = GalleryDrawing.ballImage else { return }
                let side = GalleryDrawing.ballPixels * pixel
                context.draw(Image(decorative: image, scale: 1).interpolation(.none), in: CGRect(x: at.x - side / 2, y: at.y - side / 2, width: side, height: side))
            }
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
            }
        }
        .frame(width: pictureSize.width, height: pictureSize.height)
    }
}

/// How a sheet is drawn and saved: the look's dressing aside, everything the gallery's controls set.
struct GalleryDrawing {
    var pad: CGFloat = 8
    var fps = 12.0
    var mirrored = false
    var strings = true
    var cubes = true
    var glow = true
    var ball = true
    /// The hooded heads moved, by sheet and frame: the game's table to start, changed here.
    var headNudges: [EsperSim.Animation: [Int: CGPoint]] = GameScene.headNudges
    func headNudge(_ frame: AnimationFrame) -> CGPoint { headNudges[frame.animation]?[frame.frame] ?? .zero }
    /// The ball's first frame, and its size in art pixels.
    static let ballImage: CGImage? = UIImage(named: "Basketball")?.cgImage?.cropping(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    static let ballPixels: CGFloat = 8
    /// The frames whose front arm goes over the hood, by sheet: the game's table to start,
    /// changed frame by frame here.
    var armOverHood: [EsperSim.Animation: Set<Int>] = Dictionary(uniqueKeysWithValues: GameScene.frontArmOverHood.map { ($0.key, Set($0.value)) })

    func armOverHood(_ frame: AnimationFrame) -> Bool { armOverHood[frame.animation]?.contains(frame.frame) ?? false }
}

/// The sheets' frames in a look, made as the customize screen's figure is, and the sheets
/// saved out.
@MainActor
final class PlayerGallerySheets: ObservableObject {
    private let sprites = SpriteLibrary()
    @Published var pick = PlayerCustomization.saved(0)
    @Published var status = ""

    var look: Look { pick.look }

    func portrait(_ frame: AnimationFrame) -> SpriteLibrary.Portrait? {
        sprites.setCustomizeLook(look, for: 0)
        return sprites.portrait(frame.animation.rawValue, frame: frame.frame, player: SpriteLibrary.customizePlayer(0),
                                headDrawnFor: SpriteLibrary.hoodDrawnFor, headNudge: .zero, headScale: 1, holdsBall: frame.animation.holdsBall)
    }

    /// Which way a sheet's frames run.
    enum Strip: String, CaseIterable {
        case down = "DOWN", across = "ACROSS"
    }

    /// A sheet of every frame of `animation` at `scale` pixels an art pixel, on #FF00FF: the
    /// strings and cubes moved on between frames as the frames play at the drawing's rate.
    func sheet(_ animation: EsperSim.Animation, scale: CGFloat, strip: Strip, drawing: GalleryDrawing) -> UIImage? {
        let motion = CustomizeFigureMotion()
        let cell = CGSize(width: (CGFloat(animation.pixelWidth) + 2 * drawing.pad) * scale, height: (CGFloat(animation.pixelSize) + 2 * drawing.pad) * scale)
        let count = GallerySheets.frameCount(animation)
        let size = strip == .across ? CGSize(width: cell.width * CGFloat(count), height: cell.height) : CGSize(width: cell.width, height: cell.height * CGFloat(count))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let start = Date().timeIntervalSinceReferenceDate
        var frames: [UIImage] = []
        for index in 0..<count {
            let frame = GallerySheets.frame(animation, index)
            guard let portrait = portrait(frame) else { return nil }
            let view = AssembledFrame(portrait: portrait, look: look, frame: frame, pixel: scale, pad: drawing.pad, mirrored: drawing.mirrored,
                                      strings: drawing.strings, cubes: drawing.cubes, glow: drawing.glow, armOverHood: drawing.armOverHood(frame),
                                      headNudge: drawing.headNudge(frame), ball: drawing.ball,
                                      motion: motion, time: start + Double(index) / drawing.fps)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.uiImage else { return nil }
            frames.append(image)
        }
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(rgb: PlayerGalleryOutput.background).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, image) in frames.enumerated() {
                let at = strip == .across ? CGPoint(x: cell.width * CGFloat(index), y: 0) : CGPoint(x: 0, y: cell.height * CGFloat(index))
                image.draw(in: CGRect(origin: at, size: cell))
            }
        }
    }

    /// `animations`' sheets saved as PNGs named for their sheets, in the output folder.
    func save(_ animations: [EsperSim.Animation], scale: CGFloat, strip: Strip, drawing: GalleryDrawing) {
        let folder = PlayerGalleryOutput.folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var saved = 0
            for animation in animations {
                guard let sheet = sheet(animation, scale: scale, strip: strip, drawing: drawing), let data = sheet.pngData() else { continue }
                try data.write(to: folder.appendingPathComponent("\(animation.rawValue).png"))
                saved += 1
            }
            status = "Saved \(saved) sheet\(saved == 1 ? "" : "s") at ×\(Int(scale)) to \(folder.path)"
        } catch {
            status = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

/// The sheets as the gallery lists them: by name in words, the idles first.
enum GallerySheets {
    static let first: [EsperSim.Animation] = [.idle, .dribbleIdle]
    static let listed: [EsperSim.Animation] = first + EsperSim.Animation.allCases.filter { !first.contains($0) }
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

    /// A sheet's name in words: `player_dbl_jump` as Double Jump.
    static func name(_ animation: EsperSim.Animation) -> String {
        if animation == .shield { return "Shield Backflip" }
        let words: [String: String] = ["dbl": "Double", "esperslash": "Esper Slash", "flostate": "FloState"]
        return animation.rawValue.replacingOccurrences(of: "player_", with: "").split(separator: "_")
            .map { words[String($0)] ?? $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

/// The frame last drawn while playing, for the pause to hold on.
final class Playhead {
    var shown = 0
}

/// The gallery: a sheet playing or stepped, its look, pace and padding, the per-frame arm
/// over the hood, and the save controls.
struct PlayerGallery: View {
    @StateObject private var sheets = PlayerGallerySheets()
    @State private var animation: EsperSim.Animation = .idle
    @State private var drawing = GalleryDrawing()
    @State private var pixel = 6.0
    @State private var saveScale = 4.0
    @State private var strip = PlayerGallerySheets.Strip.down
    @State private var paused = false
    @State private var held = 0
    @State private var motion = CustomizeFigureMotion()
    @State private var playhead = Playhead()

    private static let saveScales: [Double] = [1, 2, 3, 4, 6, 8]

    var body: some View {
        VStack(spacing: 14) {
            Text("PLAYER SHEETS")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(4)
                .foregroundStyle(.secondary)
            TimelineView(.animation(paused: paused)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let index = paused ? held : Int(time * drawing.fps) % GallerySheets.frameCount(animation)
                let frame = GallerySheets.frame(animation, index)
                let _ = playhead.shown = index
                ZStack {
                    Color(rgb: PlayerGalleryOutput.background)
                    if let portrait = sheets.portrait(frame) {
                        AssembledFrame(portrait: portrait, look: sheets.look, frame: frame, pixel: pixel, pad: drawing.pad, mirrored: drawing.mirrored,
                                       strings: drawing.strings, cubes: drawing.cubes, glow: drawing.glow, armOverHood: drawing.armOverHood(frame),
                                       headNudge: drawing.headNudge(frame), ball: drawing.ball, motion: motion, time: time)
                    }
                }
                .frame(width: (CGFloat(animation.pixelWidth) + 2 * drawing.pad) * pixel, height: (CGFloat(animation.pixelSize) + 2 * drawing.pad) * pixel)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(GallerySheets.name(animation))  \(index + 1)/\(GallerySheets.frameCount(animation))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(4)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                }
            }
            transport
            controls
            Text(sheets.status)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(16)
        .onChange(of: animation) { held = 0 }
    }

    /// Play or pause, and a frame back or on (which pauses); the arm over the hood for this frame.
    private var transport: some View {
        let shown = paused ? held : playhead.shown
        let frame = GallerySheets.frame(animation, shown)
        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button("\u{25C0}") { step(-1) }
                Button(paused ? "\u{25B6} PLAY" : "\u{23F8} PAUSE") {
                    if !paused { held = playhead.shown }
                    paused.toggle()
                }
                .frame(width: 110)
                Button("\u{25B6}") { step(1) }
            }
            .buttonStyle(.bordered)
            Toggle("ARM OVER HOOD, FRAME \(shown + 1)", isOn: Binding(
                get: { drawing.armOverHood(frame) },
                set: { on in
                    var frames = drawing.armOverHood[animation] ?? []
                    if on { frames.insert(frame.frame) } else { frames.remove(frame.frame) }
                    drawing.armOverHood[animation] = frames.isEmpty ? nil : frames
                }))
            .toggleStyle(.button)
            // The hooded head moved on this frame, and every move so far, frames from 1, to report.
            HStack(spacing: 12) {
                Stepper("HEAD X \(Int(drawing.headNudge(frame).x))", value: headNudgeBinding(frame, \.x), in: -12...12)
                Stepper("HEAD Y \(Int(drawing.headNudge(frame).y))", value: headNudgeBinding(frame, \.y), in: -12...12)
            }
            Text(headNudgeSummary)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .font(.system(size: 12, weight: .bold, design: .monospaced))
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
        return lines.isEmpty ? "head: none moved" : "head x, y (frames from 1): " + lines.joined(separator: "  ·  ")
    }

    private func step(_ by: Int) {
        if !paused { held = playhead.shown; paused = true }
        let count = GallerySheets.frameCount(animation)
        held = (held + by + count) % count
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Sheet", selection: $animation) {
                    ForEach(GallerySheets.listed, id: \.self) { Text(GallerySheets.name($0)).tag($0) }
                }
                Picker("Colour", selection: $sheets.pick.energy) {
                    ForEach(EnergyColour.wheel, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
            }
            HStack(spacing: 12) {
                Toggle("MIRROR", isOn: $drawing.mirrored)
                Toggle("STRINGS", isOn: $drawing.strings)
                Toggle("CUBES", isOn: $drawing.cubes)
                Toggle("GLOW", isOn: $drawing.glow)
                Toggle("BALL", isOn: $drawing.ball)
            }
            .toggleStyle(.button)
            HStack {
                Stepper("FPS \(Int(drawing.fps))", value: $drawing.fps, in: 1...60)
                Stepper("PAD \(Int(drawing.pad))", value: $drawing.pad, in: 0...32)
                Stepper("VIEW ×\(Int(pixel))", value: $pixel, in: 1...12)
            }
            HStack {
                Picker("Save scale", selection: $saveScale) {
                    ForEach(PlayerGallery.saveScales, id: \.self) { Text("×\(Int($0))").tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Strip", selection: $strip) {
                    ForEach(PlayerGallerySheets.Strip.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            HStack(spacing: 12) {
                Button("SAVE THIS SHEET") { sheets.save([animation], scale: saveScale, strip: strip, drawing: drawing) }
                Button("SAVE ALL \(EsperSim.Animation.allCases.count)") { sheets.save(EsperSim.Animation.allCases, scale: saveScale, strip: strip, drawing: drawing) }
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .frame(maxWidth: 520)
    }
}
#endif
