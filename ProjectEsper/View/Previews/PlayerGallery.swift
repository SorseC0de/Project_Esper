// A preview tool: not on the TV, which has no steppers and no computer to save to.
#if !os(tvOS)
import SwiftUI
import SpriteKit
import EsperSim

/// The player gallery, an Xcode preview: every player sheet assembled as the game draws a body
/// (its look's colours, the neck filled, the line round it, the hooded head where the frame's
/// head is, the strings hanging off it, the cubes off its head and its boots and sleeves, and
/// the glow as the customize screen draws it), playing at a chosen rate, and saved out as PNG
/// sheets on #FF00FF at any scale. A tool for looking at the art, not a part of the game.
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
/// between frames; `time` drives them and the strings' wave.
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
    let motion: CustomizeFigureMotion
    let time: Double

    /// The sheet's cell, art pixels a side.
    var canvas: CGFloat { CGFloat(frame.animation.pixelSize) }
    /// The whole picture's side, in points.
    var side: CGFloat { (canvas + 2 * pad) * pixel }

    var body: some View {
        Canvas { context, size in
            motion.advance(to: time, portrait: portrait, look: look, headNudge: .zero, headScale: 1, canvas: canvas, style: HoodStrings.hanging)
            var context = context
            if mirrored {
                context.translateBy(x: size.width, y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            /// An art point, y up from the figure's bottom left, on the canvas.
            func spot(_ point: CGPoint) -> CGPoint {
                CGPoint(x: (pad + point.x) * pixel, y: (pad + canvas - point.y) * pixel)
            }
            let figureRect = CGRect(x: pad * pixel, y: pad * pixel, width: canvas * pixel, height: canvas * pixel)
            let place = CustomizeFigure.hoodPlace(portrait, nudge: .zero, scale: 1)
            let hoodRect = CGRect(x: (pad + place.origin.x) * pixel, y: (pad + place.origin.y) * pixel, width: 48 * pixel, height: 48 * pixel)
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
            // The figure, its line in its look's colour, and its hooded head.
            context.draw(Image(decorative: portrait.image, scale: 1).interpolation(.none), in: figureRect)
            if let line = portrait.line {
                context.drawLayer { layer in
                    layer.addFilter(.colorMultiply(Color(rgb: look.outline)))
                    layer.draw(Image(decorative: line, scale: 1).interpolation(.none), in: figureRect)
                }
            }
            if let hood = portrait.hood { context.draw(Image(decorative: hood, scale: 1).interpolation(.none), in: hoodRect) }
            drawStrings(in: context)
            if cubes { for cube in motion.cubes where !cube.behind { CustomizeFigure.drawCube(cube, in: context, at: spot(cube.position), pixel: pixel) } }
            // The glow: what's energy again, blurred and added, as the customize screen draws it.
            guard glow else { return }
            var glowing = context
            glowing.blendMode = .plusLighter
            glowing.opacity = CustomizeArt.glowStrength
            glowing.drawLayer { layer in
                layer.addFilter(.blur(radius: pixel * CustomizeArt.glowPixels))
                layer.draw(Image(decorative: portrait.glowing, scale: 1).interpolation(.none), in: figureRect)
                if let hood = portrait.hoodGlowing { layer.draw(Image(decorative: hood, scale: 1).interpolation(.none), in: hoodRect) }
                drawStrings(in: layer)
                if cubes { for cube in motion.cubes { CustomizeFigure.drawCube(cube, in: layer, at: spot(cube.position), pixel: pixel) } }
            }
        }
        .frame(width: side, height: side)
    }
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
    /// strings and cubes moved on between frames as the frames play at `fps`.
    func sheet(_ animation: EsperSim.Animation, scale: CGFloat, pad: CGFloat, fps: Double, strip: Strip,
               mirrored: Bool, strings: Bool, cubes: Bool, glow: Bool) -> UIImage? {
        let motion = CustomizeFigureMotion()
        let cell = (CGFloat(animation.pixelSize) + 2 * pad) * scale
        let count = animation.frameCount
        let size = strip == .across ? CGSize(width: cell * CGFloat(count), height: cell) : CGSize(width: cell, height: cell * CGFloat(count))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let start = Date().timeIntervalSinceReferenceDate
        var frames: [UIImage] = []
        for index in 0..<count {
            let frame = AnimationFrame(animation, index)
            guard let portrait = portrait(frame) else { return nil }
            let view = AssembledFrame(portrait: portrait, look: look, frame: frame, pixel: scale, pad: pad, mirrored: mirrored,
                                      strings: strings, cubes: cubes, glow: glow, motion: motion, time: start + Double(index) / fps)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.uiImage else { return nil }
            frames.append(image)
        }
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(rgb: PlayerGalleryOutput.background).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, image) in frames.enumerated() {
                let at = strip == .across ? CGPoint(x: cell * CGFloat(index), y: 0) : CGPoint(x: 0, y: cell * CGFloat(index))
                image.draw(in: CGRect(origin: at, size: CGSize(width: cell, height: cell)))
            }
        }
    }

    /// `animations`' sheets saved as PNGs named for their sheets, in the output folder.
    func save(_ animations: [EsperSim.Animation], scale: CGFloat, pad: CGFloat, fps: Double, strip: Strip,
              mirrored: Bool, strings: Bool, cubes: Bool, glow: Bool) {
        let folder = PlayerGalleryOutput.folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var saved = 0
            for animation in animations {
                guard let sheet = sheet(animation, scale: scale, pad: pad, fps: fps, strip: strip, mirrored: mirrored,
                                        strings: strings, cubes: cubes, glow: glow),
                      let data = sheet.pngData() else { continue }
                try data.write(to: folder.appendingPathComponent("\(animation.rawValue).png"))
                saved += 1
            }
            status = "Saved \(saved) sheet\(saved == 1 ? "" : "s") at ×\(Int(scale)) to \(folder.path)"
        } catch {
            status = "Couldn't save: \(error.localizedDescription)"
        }
    }
}

/// The gallery: a sheet playing, its look, pace and padding, and the save controls.
struct PlayerGallery: View {
    @StateObject private var sheets = PlayerGallerySheets()
    @State private var animation: EsperSim.Animation = .idle
    @State private var fps = 12.0
    @State private var pad = 8.0
    @State private var pixel = 6.0
    @State private var saveScale = 4.0
    @State private var strip = PlayerGallerySheets.Strip.down
    @State private var mirrored = false
    @State private var strings = true
    @State private var cubes = true
    @State private var glow = true
    @State private var motion = CustomizeFigureMotion()

    private static let saveScales: [Double] = [1, 2, 3, 4, 6, 8]

    var body: some View {
        VStack(spacing: 14) {
            Text("PLAYER SHEETS")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(4)
                .foregroundStyle(.secondary)
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let index = Int(time * fps) % animation.frameCount
                let frame = AnimationFrame(animation, index)
                ZStack {
                    Color(rgb: PlayerGalleryOutput.background)
                    if let portrait = sheets.portrait(frame) {
                        AssembledFrame(portrait: portrait, look: sheets.look, frame: frame, pixel: pixel, pad: pad, mirrored: mirrored,
                                       strings: strings, cubes: cubes, glow: glow, motion: motion, time: time)
                    }
                }
                .frame(width: (CGFloat(animation.pixelSize) + 2 * pad) * pixel, height: (CGFloat(animation.pixelSize) + 2 * pad) * pixel)
                .overlay(alignment: .bottomTrailing) {
                    Text("\(animation.rawValue)  \(index + 1)/\(animation.frameCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(4)
                        .background(.black.opacity(0.6))
                        .foregroundStyle(.white)
                }
            }
            controls
            Text(sheets.status)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(16)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Sheet", selection: $animation) {
                    ForEach(EsperSim.Animation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Colour", selection: $sheets.pick.energy) {
                    ForEach(EnergyColour.wheel, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
            }
            HStack(spacing: 12) {
                Toggle("MIRROR", isOn: $mirrored)
                Toggle("STRINGS", isOn: $strings)
                Toggle("CUBES", isOn: $cubes)
                Toggle("GLOW", isOn: $glow)
            }
            .toggleStyle(.button)
            HStack {
                Stepper("FPS \(Int(fps))", value: $fps, in: 1...60)
                Stepper("PAD \(Int(pad))", value: $pad, in: 0...32)
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
                Button("SAVE THIS SHEET") { save([animation]) }
                Button("SAVE ALL \(EsperSim.Animation.allCases.count)") { save(EsperSim.Animation.allCases) }
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .frame(maxWidth: 520)
    }

    private func save(_ animations: [EsperSim.Animation]) {
        sheets.save(animations, scale: saveScale, pad: pad, fps: fps, strip: strip, mirrored: mirrored, strings: strings, cubes: cubes, glow: glow)
    }
}
#endif
