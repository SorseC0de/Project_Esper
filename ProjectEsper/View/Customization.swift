import EsperSim
import simd
import SwiftUI

/// A side's picks on the customize screen, kept between rounds and launches: the energy
/// colour and what the player wears.
struct PlayerCustomization: Codable, Equatable {
    var energy: EnergyColour
    var dressing = Dressing()

    var glow: RGB { energy.glow }
    var look: Look { Look.team(glow, body: Look.lightened(glow, EnergyColour.bodyLift), dressing: dressing) }

    private static func key(_ player: Int) -> String { "esper.customize.p\(player + 1)" }

    /// What a side last picked; before any, the title's colour for the first and teal for the second.
    static func saved(_ player: Int) -> PlayerCustomization {
        if let data = UserDefaults.standard.data(forKey: key(player)),
           let kept = try? JSONDecoder().decode(PlayerCustomization.self, from: data) { return kept }
        return PlayerCustomization(energy: player == 0 ? EnergyColour.saved : .teal)
    }

    func save(as player: Int) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key(player)) }
        // The first side's colour is this phone's: the title shows it and multiplayer sends it.
        if player == 0 { UserDefaults.standard.set(energy.rawValue, forKey: EnergyColour.storageKey) }
    }

    /// Both sides as they play: when the two pick the same colour, the second gives way to the opposite.
    static func clashed(_ sides: [PlayerCustomization]) -> [PlayerCustomization] {
        var sides = sides
        if sides.count > 1, sides[1].energy == sides[0].energy { sides[1].energy = sides[0].energy.opposite }
        return sides
    }

    static var sides: [PlayerCustomization] { clashed([saved(0), saved(1)]) }
}

/// Where a side's cursor can stand on the customize screen, top to bottom.
enum CustomizeSpot: Int, CaseIterable {
    /// The hood is the energy colour's picker.
    case skin, arms, legs, hood, start, back
}

extension FlowState {
    /// Over the title, before the stage select of a series in `mode`.
    func openCustomize(_ mode: GameMode) {
        customizeMode = mode
        customizations = [PlayerCustomization.saved(0), PlayerCustomization.saved(1)]
        customizeCursors = [.skin, .skin]
        customizeOpen = true
    }

    func closeCustomize() {
        SoundBoard.shared.play(.menuBack)
        customizeOpen = false
    }

    func startFromCustomize() {
        SoundBoard.shared.play(SoundBoard.confirm)
        customizeOpen = false
        startSeries?(customizeMode)
    }

    /// Both sides as they'll play, the clash settled.
    var shownCustomizations: [PlayerCustomization] { PlayerCustomization.clashed(customizations) }

    /// A side's cursor moved by its stick: up and down the spots; across, the skin, arms and
    /// legs change their pick and the hood its colour, round the wheel.
    func moveCustomize(_ player: Int, across: Int, down: Int) {
        let spot = customizeCursors[player]
        if across != 0 {
            switch spot {
            case .skin, .arms, .legs, .hood: cycle(player, spot, by: across)
            case .start, .back: break
            }
            return
        }
        guard let next = CustomizeSpot(rawValue: min(max(spot.rawValue + down, 0), CustomizeSpot.back.rawValue)), next != spot else { return }
        customizeCursors[player] = next
        SoundBoard.shared.play(SoundBoard.navigate)
    }

    /// A spot picked by a side's jump, or tapped.
    func activateCustomize(_ player: Int, _ spot: CustomizeSpot) {
        customizeCursors[player] = spot
        switch spot {
        case .skin, .arms, .legs, .hood: cycle(player, spot, by: 1)
        case .start: startFromCustomize()
        case .back: closeCustomize()
        }
    }

    /// The hood's colour picked outright, by a tap on the picker.
    func pickEnergy(_ player: Int, _ colour: EnergyColour) {
        customizeCursors[player] = .hood
        update(player) { $0.energy = colour }
    }

    private func cycle(_ player: Int, _ spot: CustomizeSpot, by step: Int) {
        update(player) { pick in
            switch spot {
            case .skin:
                let tones = HumanLook.skinTones.count
                pick.dressing.skinTone = (pick.dressing.skinTone + step % tones + tones) % tones
            case .arms: pick.dressing.sleeves.toggle()
            case .legs: pick.dressing.pants.toggle()
            case .hood:
                let wheel = EnergyColour.wheel
                let at = wheel.firstIndex(of: pick.energy) ?? 0
                pick.energy = wheel[(at + step % wheel.count + wheel.count) % wheel.count]
            default: break
            }
        }
    }

    /// A pick changed: kept, and the players drawn in it at once.
    private func update(_ player: Int, _ change: (inout PlayerCustomization) -> Void) {
        change(&customizations[player])
        customizations[player].save(as: player)
        SoundBoard.shared.play(SoundBoard.navigate)
        scene.applySavedColours()
    }
}

/// The customize screen, between the title and the stage select, on `Customize_Screen.svg`'s
/// layers (`CustomizeLayout`): each side's player on a holo-projector in its halo, both in
/// the side's energy colour; the skin, arms and legs boxes beside it and the hood under them,
/// the hood's colours in the display below while it's chosen. CUSTOMIZE and the mode over
/// the middle, START on it, its rings turning; RETURN at the bottom. Each side's cursor is
/// ringed in its colour.
struct CustomizeScreen: View {
    @ObservedObject var flow: FlowState
    @Environment(\.displayScale) private var displayScale

    init(flow: FlowState) {
        self.flow = flow
        _ = Onomatopoeia.registered
    }

    /// An art pixel as a share of the screen's width, the projector's half of it and the
    /// player's three times it.
    static let artPixelShare: CGFloat = 0.168 / 64
    static let projectorPixels: CGFloat = 0.5
    static let playerPixels: CGFloat = 3
    /// The ring's middle down the halo's layer.
    static let ringShare: CGFloat = 0.9
    /// The halo's beam, clear at its top, whole this far down.
    static let haloFadeEnd: CGFloat = 0.75
    /// The projector's lens, the row the player stands on, and the player's feet, in art pixels.
    static let lensRow: CGFloat = 18
    static let feetRow: CGFloat = 40
    /// The rings round START, in degrees a second.
    static let spinSpeeds: (ccw: Double, cw: Double) = (24, 36)
    /// The hood's picker: its colour's share of each column, over the accent.
    static let swatchShare: CGFloat = 0.7

    var body: some View {
        GeometryReader { geometry in
            let size = CustomizeScreen.fitted(geometry.size)
            ZStack(alignment: .topLeading) {
                layer("customize_ground", size)
                heading(size)
                ForEach(0..<2, id: \.self) { player in side(player, size) }
                middle(size)
                returnButton(size)
            }
            .frame(width: size.width, height: size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .background {
            // The ground's dark edge past the 16:9, taking the taps the screen doesn't.
            Color(rgb: EsperPalette.black.shadow)
                .contentShape(Rectangle())
                .onTapGesture {}
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    /// The vector's 16:9, as large as fits.
    static func fitted(_ space: CGSize) -> CGSize {
        let width = min(space.width, space.height * CustomizeLayout.aspect)
        return CGSize(width: width, height: width / CustomizeLayout.aspect)
    }

    private func rect(_ name: String, _ size: CGSize) -> CGRect {
        let share = CustomizeLayout.frames[name] ?? .zero
        return CGRect(x: share.minX * size.width, y: share.minY * size.height, width: share.width * size.width, height: share.height * size.height)
    }

    private func picture(_ name: String) -> Image { Image(uiImage: UIImage(named: name) ?? UIImage()) }

    private func layer(_ name: String, _ size: CGSize) -> some View {
        let frame = rect(name, size)
        return picture(name).resizable().frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
    }

    /// `pixels` art pixels' worth of screen, a whole number of the screen's own.
    private func artPixel(_ size: CGSize, times pixels: CGFloat) -> CGFloat {
        max((size.width * CustomizeScreen.artPixelShare * pixels * displayScale).rounded(), 1) / displayScale
    }

    private func title(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.custom("Bigdex", size: size))
            .foregroundStyle(.white)
            .shadow(color: .black, radius: 0, x: 1, y: 2)
            .fixedSize()
    }

    /// Lettered as FLO is when it's lit, in Bigdex: gold's first over the cyan, outlined in plum
    /// and purple. `height` is its cap height.
    private func litTitle(_ text: String, height: CGFloat) -> some View {
        let word = Onomatopoeia.picture(text, face: .englishDex, colours: FloTuning.colours, growsLeft: true, height: height)
        return Image(uiImage: word.image).resizable().aspectRatio(contentMode: .fit).frame(height: word.height)
    }

    private func subtitle(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black, radius: 0, x: 1, y: 1)
    }

    /// CUSTOMIZE on the heading's plate, and the series' mode large under it.
    @ViewBuilder
    private func heading(_ size: CGSize) -> some View {
        litTitle("CUSTOMIZE", height: size.height * 0.05)
            .position(x: size.width / 2, y: size.height * 0.078)
        title(flow.customizeMode == .rounds ? "BEST OF 7" : "47", size: size.height * 0.08)
            .position(x: size.width / 2, y: size.height * 0.19)
    }

    // MARK: A side

    @ViewBuilder
    private func side(_ player: Int, _ size: CGSize) -> some View {
        let tag = "customize_p\(player + 1)_"
        let pick = flow.customizations[player]
        let glow = flow.shownCustomizations[player].glow
        let cursor = flow.customizeCursors[player]
        let halo = rect(tag + "halo", size)
        let ring = CGPoint(x: halo.midX, y: halo.minY + halo.height * CustomizeScreen.ringShare)
        let projectorPixel = artPixel(size, times: CustomizeScreen.projectorPixels)
        let playerPixel = artPixel(size, times: CustomizeScreen.playerPixels)

        // The beam fading out to nothing at its top.
        picture(tag + "halo").resizable()
            .colorMultiply(Color(rgb: glow))
            .frame(width: halo.width, height: halo.height)
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: CustomizeScreen.haloFadeEnd)],
                                 startPoint: .top, endPoint: .bottom))
            .position(x: halo.midX, y: halo.midY)
        if let projector = CustomizeArt.projector(glow) {
            Image(uiImage: projector).resizable().interpolation(.none)
                .frame(width: 64 * projectorPixel, height: 64 * projectorPixel)
                .position(ring)
        }
        if let portrait = flow.scene.customizePortrait(player: player) {
            // Standing on the lens, the second side facing the first.
            let lens = ring.y + (CustomizeScreen.lensRow - 32) * projectorPixel
            let side = (48 + 2 * CustomizeFigure.margin) * playerPixel
            CustomizeFigure(portrait: portrait, look: flow.shownCustomizations[player].look, pixel: playerPixel, mirrored: player == 1)
                .frame(width: side, height: side)
                .allowsHitTesting(false)
                .position(x: ring.x, y: lens - (CustomizeScreen.feetRow - 24) * playerPixel)
        }

        box(player, .skin, tag + "skin", label: "SKIN", size: size, glow: glow, cursor: cursor) { frame in
            let tone = HumanLook.skinTones[pick.dressing.skinTone]
            VStack(spacing: 0) {
                Color(rgb: PixelPalette.colours[tone.front])
                Color(rgb: PixelPalette.colours[tone.back])
            }
            .frame(width: frame.width * 0.5, height: frame.height * 0.5)
            .clipShape(RoundedRectangle(cornerRadius: frame.width * 0.08))
        }
        box(player, .arms, tag + "arms", label: "ARMS", size: size, glow: glow, cursor: cursor) { frame in
            subtitle(pick.dressing.sleeves ? "SLEEVES" : "BARE", size: frame.height * 0.16)
        }
        box(player, .legs, tag + "legs", label: "LEGS", size: size, glow: glow, cursor: cursor) { frame in
            subtitle(pick.dressing.pants ? "PANTS" : "SHORTS", size: frame.height * 0.16)
        }
        box(player, .hood, tag + "hood", label: "H.O.O.D", size: size, glow: glow, cursor: cursor) { frame in
            if let hood = flow.scene.customizeHood(player: player) {
                Image(uiImage: UIImage(cgImage: hood)).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                    .frame(width: frame.width * 0.7, height: frame.height * 0.7)
                    .scaleEffect(x: player == 0 ? 1 : -1)
            }
        }
        picker(player, tag + "display", size: size, pick: flow.shownCustomizations[player], shown: cursor == .hood)
        if cursor == .hood {
            // What the H.O.O.D. is, over the halo's outer corner.
            VStack(alignment: player == 0 ? .leading : .trailing, spacing: size.height * 0.004) {
                title("H.O.O.D.", size: size.height * 0.05)
                subtitle("Hyper-Osmotic Output Driver", size: size.height * 0.026)
            }
            .frame(width: halo.width, height: size.height * 0.13, alignment: player == 0 ? .bottomLeading : .bottomTrailing)
            .position(x: halo.midX, y: halo.minY - size.height * 0.065)
        }
    }

    /// One of a side's boxes, its pick in it and its label under it; ringed in the side's
    /// colour under its cursor.
    private func box(_ player: Int, _ spot: CustomizeSpot, _ name: String, label: String, size: CGSize, glow: RGB,
                     cursor: CustomizeSpot, @ViewBuilder content: (CGRect) -> some View) -> some View {
        let frame = rect(name, size)
        let lit = cursor == spot
        return ZStack {
            picture(name).resizable()
            content(frame)
            if lit {
                RoundedRectangle(cornerRadius: frame.width * 0.16)
                    .stroke(Color(rgb: glow), lineWidth: max(frame.width * 0.05, 2))
                    .padding(-frame.width * 0.06)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .overlay(alignment: .top) {
            title(label, size: frame.height * 0.4)
                .offset(y: frame.height * 1.04)
        }
        .scaleEffect(lit ? TitleOverlay.cursorGrowth : 1)
        .contentShape(Rectangle())
        .onTapGesture { flow.activateCustomize(player, spot) }
        .position(x: frame.midX, y: frame.midY)
    }

    /// The hood's colours in the side's display, while the hood is chosen: a column a colour,
    /// leaning, the colour over the shade down its ramp as an accent, corner to corner; the
    /// picked one lined in white.
    private func picker(_ player: Int, _ name: String, size: CGSize, pick: PlayerCustomization, shown: Bool) -> some View {
        let frame = rect(name, size)
        let wheel = EnergyColour.wheel
        let inner = CGSize(width: frame.width * 0.84, height: frame.height * 0.6)
        let split = CustomizeScreen.swatchShare
        return ZStack {
            picture(name).resizable()
            if shown {
                HStack(spacing: inner.width / CGFloat(wheel.count) * 0.12) {
                    ForEach(wheel, id: \.self) { colour in
                        let picked = pick.energy == colour
                        ZStack {
                            LeaningBand(from: 0, to: split).fill(Color(rgb: colour.glow))
                            LeaningBand(from: split, to: 1).fill(Color(rgb: colour.rampDown))
                            LeaningBand(from: 0, to: 1).stroke(.white, lineWidth: picked ? 2.5 : 0)
                        }
                        .scaleEffect(picked ? 1.12 : 1)
                        .contentShape(Rectangle())
                        .onTapGesture { flow.pickEnergy(player, colour) }
                    }
                }
                .frame(width: inner.width, height: inner.height)
                .offset(y: -frame.height * 0.08)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    // MARK: The middle

    private func middle(_ size: CGSize) -> some View {
        let start = rect("customize_start", size)
        let lit = flow.customizeCursors.contains(.start)
        return TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                layer("customize_start", size)
                spinning("customize_spin_ccw", size, about: start, degrees: -seconds * CustomizeScreen.spinSpeeds.ccw)
                spinning("customize_spin_cw", size, about: start, degrees: seconds * CustomizeScreen.spinSpeeds.cw)
                litTitle("START", height: size.height * 0.07)
                    .position(x: start.midX, y: start.midY)
            }
            .frame(width: size.width, height: size.height)
        }
        .brightness(lit ? 0.15 : 0)
        .scaleEffect(lit ? TitleOverlay.cursorGrowth : 1, anchor: UnitPoint(x: start.midX / size.width, y: start.midY / size.height))
        .contentShape(Rectangle().path(in: start))
        .onTapGesture { flow.activateCustomize(0, .start) }
    }

    /// A ring turned about START's middle.
    private func spinning(_ name: String, _ size: CGSize, about centre: CGRect, degrees: Double) -> some View {
        let frame = rect(name, size)
        let anchor = UnitPoint(x: (centre.midX - frame.minX) / frame.width, y: (centre.midY - frame.minY) / frame.height)
        return picture(name).resizable()
            .frame(width: frame.width, height: frame.height)
            .rotationEffect(.degrees(degrees.truncatingRemainder(dividingBy: 360)), anchor: anchor)
            .position(x: frame.midX, y: frame.midY)
    }

    private func returnButton(_ size: CGSize) -> some View {
        let frame = rect("customize_return", size)
        let lit = flow.customizeCursors.contains(.back)
        return picture("customize_return").resizable()
            .frame(width: frame.width, height: frame.height)
            .brightness(lit ? 0.2 : 0)
            .scaleEffect(lit ? TitleOverlay.cursorGrowth : 1)
            .contentShape(Rectangle())
            .onTapGesture { flow.activateCustomize(0, .back) }
            .position(x: frame.midX, y: frame.midY)
    }
}

/// A band across a column leaning right, a fifth of its width over its height, from `from` to
/// `to` of the way down: bands of one column meet corner to corner.
struct LeaningBand: Shape {
    var from: CGFloat
    var to: CGFloat
    var lean: CGFloat = 0.2

    func path(in rect: CGRect) -> Path {
        let shift = rect.width * lean
        // The left edge at a share of the way down; the right a column's width less the lean along.
        func left(_ down: CGFloat) -> CGFloat { rect.minX + shift * (1 - down) }
        let width = rect.width - shift
        var path = Path()
        path.move(to: CGPoint(x: left(from), y: rect.minY + rect.height * from))
        path.addLine(to: CGPoint(x: left(from) + width, y: rect.minY + rect.height * from))
        path.addLine(to: CGPoint(x: left(to) + width, y: rect.minY + rect.height * to))
        path.addLine(to: CGPoint(x: left(to), y: rect.minY + rect.height * to))
        path.closeSubpath()
        return path
    }
}

/// A side's player on the customize screen, drawn a frame at a time: the figure, its strings
/// floating off the hood and swaying from one side to the other, and the cubes off its head
/// and shoes, as in play. In art pixels, `margin` round the figure's 48 for the strings and cubes.
struct CustomizeFigure: View {
    let portrait: SpriteLibrary.Portrait
    let look: Look
    /// Screen points an art pixel.
    let pixel: CGFloat
    let mirrored: Bool
    @State private var motion = CustomizeFigureMotion()

    static let margin: CGFloat = 24

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                motion.advance(to: timeline.date.timeIntervalSinceReferenceDate, portrait: portrait, look: look)
                var context = context
                if mirrored {
                    context.translateBy(x: size.width, y: 0)
                    context.scaleBy(x: -1, y: 1)
                }
                let margin = CustomizeFigure.margin
                /// An art point, y up from the figure's bottom left, on the canvas.
                func spot(_ point: CGPoint) -> CGPoint {
                    CGPoint(x: (margin + point.x) * pixel, y: (margin + 48 - point.y) * pixel)
                }
                for cube in motion.cubes where cube.behind { draw(cube, in: context, at: spot(cube.position)) }
                let figure = Image(decorative: portrait.image, scale: 1).interpolation(.none)
                context.draw(figure, in: CGRect(x: margin * pixel, y: margin * pixel, width: 48 * pixel, height: 48 * pixel))
                let plain = Color(rgb: look.energyTone(luminance: SpriteLibrary.hoodLevel))
                let accent = Color(rgb: look.energyTone(luminance: GameScene.stringAccentLuminance * SpriteLibrary.hoodLevel))
                for string in motion.strings {
                    let at = spot(string.point)
                    context.fill(Path(CGRect(x: at.x - pixel / 2, y: at.y - pixel / 2, width: pixel, height: pixel)), with: .color(string.accent ? accent : plain))
                }
                for cube in motion.cubes where !cube.behind { draw(cube, in: context, at: spot(cube.position)) }
            }
        }
    }

    /// A cube as the Metal layer shades one: its faces toward us, each its colour lit toward
    /// white where it faces the light, never dark.
    private func draw(_ cube: CustomizeFigureMotion.Cube, in context: GraphicsContext, at centre: CGPoint) {
        let share = cube.age / cube.life
        let side = Float(cube.size * pixel * (share < 0.45 ? 1 : (share < 0.75 ? 0.66 : 0.33)))
        let alpha = share < 0.85 ? 0.9 : 0.9 * (1 - share) / 0.15
        let light = simd_normalize(SIMD3<Float>(-0.4, 0.7, 0.6))
        let base = SIMD3<Float>(Float((cube.colour >> 16) & 0xFF), Float((cube.colour >> 8) & 0xFF), Float(cube.colour & 0xFF)) / 255
        let axes: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        var faces: [(depth: Float, corners: [CGPoint], colour: Color)] = []
        for axis in axes {
            for sign: Float in [1, -1] {
                let normal = cube.orientation.act(axis * sign)
                guard normal.z > 0 else { continue }
                let others = axes.filter { $0 != axis }.map { cube.orientation.act($0) * side / 2 }
                let middle = normal * side / 2
                let corners = [middle - others[0] - others[1], middle + others[0] - others[1],
                               middle + others[0] + others[1], middle - others[0] + others[1]]
                    .map { CGPoint(x: centre.x + CGFloat($0.x), y: centre.y - CGFloat($0.y)) }
                let lit = max(simd_dot(normal, light), 0)
                let mixed = simd_mix(base * (0.85 + 0.15 * lit), SIMD3<Float>(repeating: 1), SIMD3<Float>(repeating: 0.35 * lit * lit))
                faces.append((normal.z, corners, Color(red: Double(mixed.x), green: Double(mixed.y), blue: Double(mixed.z)).opacity(alpha)))
            }
        }
        for face in faces.sorted(by: { $0.depth < $1.depth }) {
            var path = Path()
            path.addLines(face.corners)
            path.closeSubpath()
            context.fill(path, with: .color(face.colour))
        }
    }
}

/// The customize figure's strings and cubes, stepped at the game's 60 a second.
final class CustomizeFigureMotion {
    struct Cube {
        var position: CGPoint
        var velocity: CGVector
        var age = 0.0
        var life: Double
        var orientation: simd_quatf
        var spin: SIMD3<Float>
        var size: CGFloat
        var colour: RGB
        var behind: Bool
    }

    private let stringMotion = HoodStrings.Motion()
    private(set) var strings: [(point: CGPoint, accent: Bool)] = []
    private(set) var cubes: [Cube] = []
    private var credit: [BodyPart: Double] = [:]
    private var last: Double?
    private var owed = 0.0

    /// The strings' sway from one side over the top to the other, a second.
    static let stringSwayPerSecond = 0.25
    /// The head's cubes a second, the shoes' each; the game's at no FLO.
    static let headCubeRate = 24.0
    static let shoeCubeRate = Double(ParticleLook.legCubeRate)

    func advance(to time: Double, portrait: SpriteLibrary.Portrait, look: Look) {
        let step = 1.0 / 60
        owed += last.map { min(time - $0, 0.1) } ?? step
        last = time
        while owed >= step {
            owed -= step
            tick(time: time, step: step, portrait: portrait, look: look)
        }
    }

    private func tick(time: Double, step: Double, portrait: SpriteLibrary.Portrait, look: Look) {
        // The strings off the hood's own anchors, wherever the hood went on the figure, floating
        // as FloState's do, both swaying the same way, round from back over the top to forward.
        let anchors = HoodStrings.anchorPixels.map { pixel in
            CGPoint(x: pixel.x + 0.5 + portrait.hoodOffset.x, y: 48 - (pixel.y + 0.5 + portrait.hoodOffset.y))
        }
        let turn = Double.pi / 2 + Double.pi / 2 * sin(time * 2 * .pi * CustomizeFigureMotion.stringSwayPerSecond)
        var style = HoodStrings.floState
        for index in style.strands.indices { style.strands[index].direction = CGVector(dx: cos(turn), dy: sin(turn)) }
        strings = stringMotion.step(anchors: anchors, style: style, facing: 1, scale: 1, time: time)

        // Cubes off the head's crown and the shoes, as a human's are in play.
        let wind = sin(time * 2 * .pi * ParticleLook.swayPerSecond) * Double(ParticleLook.flowSpeed)
        let sources: [(part: BodyPart, rate: Double, size: Float, spread: Float, lift: CGFloat)] = [
            (.head, CustomizeFigureMotion.headCubeRate, ParticleLook.cubeSize, ParticleLook.cubeSpread, GameScene.crownLift),
            (.frontFoot, CustomizeFigureMotion.shoeCubeRate, ParticleLook.legCubeSize, ParticleLook.legCubeSpread, 0),
            (.backFoot, CustomizeFigureMotion.shoeCubeRate, ParticleLook.legCubeSize, ParticleLook.legCubeSpread, 0),
        ]
        for source in sources {
            guard let centre = portrait.centres[source.part] else { continue }
            credit[source.part, default: 0] += source.rate * step
            while credit[source.part, default: 0] >= 1 {
                credit[source.part, default: 0] -= 1
                let spread = CGFloat(source.spread)
                let angle = Double.pi / 2 + Double.random(in: -Double.pi / 28...Double.pi / 28)
                let speed = 24 + Double.random(in: -2...2)
                let axis = simd_normalize(SIMD3<Float>.random(in: -1...1) + SIMD3<Float>(0, 0, 0.001))
                cubes.append(Cube(position: CGPoint(x: centre.x + .random(in: -spread...spread),
                                                    y: 48 - centre.y + source.lift + .random(in: -spread / 2...spread / 2)),
                                  velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                                  life: Double(ParticleLook.cubeTrail) / speed + .random(in: -0.05...0.05),
                                  orientation: simd_quatf(angle: .random(in: 0..<(2 * .pi)), axis: axis),
                                  spin: SIMD3<Float>.random(in: -ParticleLook.cubeSpin...ParticleLook.cubeSpin),
                                  size: CGFloat(source.size), colour: look.colours[source.part] ?? look.glow,
                                  behind: source.part.isBack))
            }
        }
        cubes = cubes.compactMap { cube in
            var cube = cube
            cube.age += step
            guard cube.age < cube.life else { return nil }
            let rate = simd_length(cube.spin)
            if rate > 0 { cube.orientation = simd_normalize(simd_quatf(angle: rate * Float(step), axis: cube.spin / rate) * cube.orientation) }
            cube.velocity.dx += wind * step
            cube.velocity.dy += 10 * step
            cube.position = CGPoint(x: cube.position.x + cube.velocity.dx * step, y: cube.position.y + cube.velocity.dy * step)
            return cube
        }
    }
}

/// The customize screen's pixel art.
@MainActor
enum CustomizeArt {
    private static var projectors: [RGB: UIImage] = [:]

    /// `Holo-Projector_v2`, its white in an energy colour.
    static func projector(_ glow: RGB) -> UIImage? {
        if let made = projectors[glow] { return made }
        guard let source = UIImage(named: "HoloProjector")?.cgImage else { return nil }
        let width = source.width, height = source.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for pixel in 0..<(width * height) where pixels[pixel * 4 + 3] == 255
            && pixels[pixel * 4] == 255 && pixels[pixel * 4 + 1] == 255 && pixels[pixel * 4 + 2] == 255 {
            pixels[pixel * 4] = UInt8((glow >> 16) & 0xFF)
            pixels[pixel * 4 + 1] = UInt8((glow >> 8) & 0xFF)
            pixels[pixel * 4 + 2] = UInt8(glow & 0xFF)
        }
        guard let made = context.makeImage() else { return nil }
        let image = UIImage(cgImage: made)
        projectors[glow] = image
        return image
    }

    /// Cut to what's drawn.
    static func trimmed(_ image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var left = width, top = height, right = -1, bottom = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        guard right >= 0 else { return image }
        return image.cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) ?? image
    }
}
